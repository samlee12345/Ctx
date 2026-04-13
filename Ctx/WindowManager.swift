import AppKit
import ApplicationServices
import Combine

// Private AX function — stable across all macOS versions, used by yabai/Hammerspoon/etc.
// Maps a CGWindowID directly to its AXUIElement without any bounds matching.
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: inout CGWindowID) -> AXError

struct WindowConfig {
    var name: String
    var windowIDs: [CGWindowID]
    // Stores the app name for each window ID so we can detect if an ID has been
    // reused by a different app (CGWindowIDs are recycled by macOS after windows close).
    var windowAppNames: [CGWindowID: String] = [:]
    var cycleIndex: Int = 0
}

// MARK: - Codable

extension WindowConfig: Codable {
    enum CodingKeys: String, CodingKey {
        case name, windowIDs, windowAppNames, cycleIndex
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(windowIDs, forKey: .windowIDs)
        // JSON requires string keys; CGWindowID (UInt32) is stringified for storage
        let stringKeyed = Dictionary(uniqueKeysWithValues: windowAppNames.map { ("\($0.key)", $0.value) })
        try c.encode(stringKeyed, forKey: .windowAppNames)
        try c.encode(cycleIndex, forKey: .cycleIndex)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name       = try c.decode(String.self, forKey: .name)
        windowIDs  = try c.decode([CGWindowID].self, forKey: .windowIDs)
        let strKeyed = try c.decodeIfPresent([String: String].self, forKey: .windowAppNames) ?? [:]
        windowAppNames = Dictionary(uniqueKeysWithValues: strKeyed.compactMap { k, v in
            guard let id = CGWindowID(k) else { return nil }
            return (id, v)
        })
        cycleIndex = try c.decodeIfPresent(Int.self, forKey: .cycleIndex) ?? 0
    }
}

// MARK: - WindowManager

private let kConfigsKey      = "ctx.configs.v1"
private let kActiveIndexKey  = "ctx.activeConfigIndex.v1"

class WindowManager: ObservableObject {
    @Published var configs: [WindowConfig]
    @Published var activeConfigIndex: Int
    @Published var isCyclingConfigs = false   // true while Option is held during config cycling
    var noOpHandler: (() -> Void)?   // called by cycle/raise when no valid window found

    private var cancellables = Set<AnyCancellable>()

    init() {
        let loaded: [WindowConfig]
        if let data = UserDefaults.standard.data(forKey: kConfigsKey),
           let saved = try? JSONDecoder().decode([WindowConfig].self, from: data), !saved.isEmpty {
            loaded = saved
        } else {
            loaded = [WindowConfig(name: "Work", windowIDs: []),
                      WindowConfig(name: "Research", windowIDs: [])]
        }
        _configs = Published(initialValue: loaded)

        let savedIndex = UserDefaults.standard.integer(forKey: kActiveIndexKey)
        _activeConfigIndex = Published(initialValue: min(savedIndex, max(0, loaded.count - 1)))

        // Auto-save on any change, debounced to avoid thrashing UserDefaults
        Publishers.CombineLatest($configs, $activeConfigIndex)
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _, _ in self?.persist() }
            .store(in: &cancellables)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(configs) else { return }
        UserDefaults.standard.set(data, forKey: kConfigsKey)
        UserDefaults.standard.set(activeConfigIndex, forKey: kActiveIndexKey)
    }

    var activeConfig: WindowConfig? {
        guard configs.indices.contains(activeConfigIndex) else { return nil }
        return configs[activeConfigIndex]
    }

    var activeConfigName: String {
        activeConfig?.name ?? "Ctx"
    }

    // MARK: - Window Picker

    struct WindowInfo: Identifiable {
        let id: CGWindowID
        let appName: String
        let windowTitle: String
        let icon: NSImage?
    }

    func allVisibleWindows() -> [WindowInfo] {
        let myPID = pid_t(ProcessInfo.processInfo.processIdentifier)
        return onScreenWindowList().compactMap { info in
            guard
                let id = info[kCGWindowNumber as String] as? CGWindowID,
                let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                let appName = info[kCGWindowOwnerName as String] as? String,
                let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                let layer = info[kCGWindowLayer as String] as? Int,
                layer == 0,
                pid != myPID
            else { return nil }

            // AX title is the richest source (page title for browsers, file name for editors)
            // Falls back to CGWindowName, then a position hint for disambiguation
            let title = axWindowTitle(windowID: id, pid: pid)
                ?? (info[kCGWindowName as String] as? String)
                ?? positionHint(for: bounds)

            let icon = NSRunningApplication(processIdentifier: pid)?.icon
            return WindowInfo(id: id, appName: appName, windowTitle: title, icon: icon)
        }
        .sorted { ($0.appName, $0.windowTitle) < ($1.appName, $1.windowTitle) }
    }

    private func axWindowTitle(windowID: CGWindowID, pid: pid_t) -> String? {
        guard let axWindow = axElement(for: windowID, pid: pid) else { return nil }
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef) == .success,
              let title = titleRef as? String, !title.isEmpty else { return nil }
        return title
    }

    private func positionHint(for bounds: CGRect) -> String {
        // Find the screen this window is on
        let screen = NSScreen.screens.first {
            $0.frame.intersects(bounds)
        } ?? NSScreen.main

        guard let screen else { return "\(Int(bounds.width))×\(Int(bounds.height))" }

        let sf = screen.frame
        let isWide = bounds.width >= sf.width * 0.85
        let isTall = bounds.height >= sf.height * 0.85
        let isLeft = bounds.midX < sf.midX
        let screenLabel = NSScreen.screens.count > 1
            ? (screen == NSScreen.screens.first ? "Main" : "External") + " — "
            : ""

        switch (isWide, isTall) {
        case (true, true):  return "\(screenLabel)Full screen"
        case (true, false): return "\(screenLabel)\(bounds.minY < sf.midY ? "Top half" : "Bottom half")"
        case (false, true): return "\(screenLabel)\(isLeft ? "Left half" : "Right half")"
        default:            return "\(screenLabel)\(Int(bounds.width))×\(Int(bounds.height))"
        }
    }

    func focusedWindowInfo() -> WindowInfo? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              frontApp.processIdentifier != pid_t(ProcessInfo.processInfo.processIdentifier)
        else { return nil }

        let pid = frontApp.processIdentifier
        let appName = frontApp.localizedName ?? "Unknown"
        let icon = frontApp.icon

        let appElement = AXUIElementCreateApplication(pid)
        // Cap AX call time so a frozen app can't hang the menu
        AXUIElementSetMessagingTimeout(appElement, 0.15)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let ref = windowRef,
              CFGetTypeID(ref) == AXUIElementGetTypeID()
        else { return nil }
        let axWindow = ref as! AXUIElement // safe: type verified above

        var titleRef: CFTypeRef?
        let title: String
        if AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef) == .success,
           let t = titleRef as? String, !t.isEmpty {
            title = t
        } else {
            title = appName
        }

        var windowID: CGWindowID = 0
        guard _AXUIElementGetWindow(axWindow, &windowID) == .success, windowID != 0 else { return nil }

        return WindowInfo(id: windowID, appName: appName, windowTitle: title, icon: icon)
    }

    func addWindow(_ windowID: CGWindowID, appName: String, toConfigAt index: Int) {
        guard configs.indices.contains(index),
              !configs[index].windowIDs.contains(windowID) else { return }
        configs[index].windowIDs.append(windowID)
        configs[index].windowAppNames[windowID] = appName
        NotificationCenter.default.post(name: .ctxConfigChanged, object: nil)
    }

    func setWindowIDs(forConfigAt index: Int, windowIDs: [CGWindowID]) {
        guard configs.indices.contains(index) else { return }
        configs[index].windowIDs = windowIDs
        configs[index].cycleIndex = 0
        activeConfigIndex = index
        NotificationCenter.default.post(name: .ctxConfigChanged, object: nil)
    }

    // MARK: - Cycling

    // Advance the active config index without raising any windows.
    // Used by the hotkey handler while Option is held — windows raise on Option release.
    func advanceConfig(forward: Bool = true) {
        guard configs.count > 1 else { return }
        let step = forward ? 1 : configs.count - 1
        activeConfigIndex = (activeConfigIndex + step) % configs.count
        NotificationCenter.default.post(name: .ctxConfigChanged, object: nil)
    }

    func cycleNextConfig(forward: Bool = true) {
        guard configs.count > 1 else { return }
        let step = forward ? 1 : configs.count - 1
        switchToConfig(at: (activeConfigIndex + step) % configs.count)
    }

    func switchToConfig(at index: Int) {
        guard configs.indices.contains(index) else { return }
        activeConfigIndex = index
        NotificationCenter.default.post(name: .ctxConfigChanged, object: nil)
        raiseActiveConfig()
    }

    // Cycles focus through individual windows within the active config (Option+~ / Shift+Option+~).
    // Skips any ID whose current on-screen app doesn't match the stored app name — this prevents
    // raising the wrong window when macOS reuses a CGWindowID after a window closes.
    func cycleWindowInConfig(forward: Bool = true) {
        guard let config = activeConfig, !config.windowIDs.isEmpty else { return }

        // Use the full list (all Spaces + minimized) so stored IDs are always resolvable
        let list = configWindowList()

        // Map on-screen window ID -> current app name for validation
        var onScreenAppNames: [CGWindowID: String] = [:]
        for info in list {
            if let id = info[kCGWindowNumber as String] as? CGWindowID,
               let app = info[kCGWindowOwnerName as String] as? String {
                onScreenAppNames[id] = app
            }
        }

        // Valid = on screen AND app name matches what we recorded (or no name recorded = legacy)
        let validIDs = config.windowIDs.filter { id in
            guard let currentApp = onScreenAppNames[id] else { return false }
            if let storedApp = config.windowAppNames[id] { return currentApp == storedApp }
            return true
        }
        guard !validIDs.isEmpty else { noOpHandler?(); return }

        // Find where we are in the valid subset, then step forward or backward
        let currentID = config.windowIDs.indices.contains(config.cycleIndex)
            ? config.windowIDs[config.cycleIndex] : nil
        let currentValidIndex = currentID.flatMap { validIDs.firstIndex(of: $0) }
            ?? (forward ? validIDs.count - 1 : 0)
        let count = validIDs.count
        let nextValidIndex = (currentValidIndex + (forward ? 1 : count - 1)) % count
        let targetID = validIDs[nextValidIndex]

        // Sync cycleIndex back to the full array
        if let fullIndex = config.windowIDs.firstIndex(of: targetID) {
            configs[activeConfigIndex].cycleIndex = fullIndex
        }

        if let info = list.first(where: { ($0[kCGWindowNumber as String] as? CGWindowID) == targetID }),
           let pid = info[kCGWindowOwnerPID as String] as? pid_t {
            // Skip re-activation if this window is already frontmost (single-window config no-op)
            let alreadyFront = NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
                && validIDs.count == 1
            if !alreadyFront {
                axRaiseWindow(info: info)
                let app = NSRunningApplication(processIdentifier: pid)
                if #available(macOS 14.0, *) {
                    // activate(from:) works from a non-frontmost/accessory process;
                    // the plain activate() silently no-ops when Ctx isn't the active app.
                    app?.activate(from: NSRunningApplication.current)
                } else {
                    app?.activate(options: .activateIgnoringOtherApps)
                }
            }
        }
    }

    // MARK: - Raise

    func raiseActiveConfig() {
        guard let config = activeConfig, !config.windowIDs.isEmpty else { return }

        let list = configWindowList()

        // Config windows in current z-order, filtering out IDs that have been reused
        // by a different app (stale entries from a previous session or app restart)
        let configInZOrder = list.compactMap { info -> [String: Any]? in
            guard let id = info[kCGWindowNumber as String] as? CGWindowID,
                  config.windowIDs.contains(id) else { return nil }
            if let storedApp = config.windowAppNames[id],
               let currentApp = info[kCGWindowOwnerName as String] as? String,
               storedApp != currentApp { return nil }
            return info
        }
        guard !configInZOrder.isEmpty else { noOpHandler?(); return }

        // Step 1: AXRaise all windows back-to-front to set correct within-app z-order
        for info in configInZOrder.reversed() {
            axRaiseWindow(info: info)
        }

        // Step 2: Stagger app activations so each settles before the next fires.
        // Firing all at once causes a race in the window server that drops some.
        // Back-to-front order means the originally-frontmost app activates last
        // and ends up with keyboard focus.
        let snapshot = configInZOrder
        var pidsInOrder: [pid_t] = []
        var seen = Set<pid_t>()
        for info in snapshot.reversed() {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  !seen.contains(pid) else { continue }
            seen.insert(pid)
            pidsInOrder.append(pid)
        }

        // 80ms initial settle + 80ms between each app activation
        for (i, pid) in pidsInOrder.enumerated() {
            let delay = 0.08 + Double(i) * 0.08
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let app = NSRunningApplication(processIdentifier: pid)
                if #available(macOS 14.0, *) {
                    // activate(from:) works from a non-frontmost/accessory process;
                    // the plain activate() silently no-ops when Ctx isn't the active app.
                    app?.activate(from: NSRunningApplication.current)
                } else {
                    app?.activate(options: .activateIgnoringOtherApps)
                }
            }
        }
    }

    // AXRaise — unminimizes if needed, then raises. Uses CGWindowID for exact matching.
    private func axRaiseWindow(info: [String: Any]) {
        guard
            let windowID = info[kCGWindowNumber as String] as? CGWindowID,
            let pid = info[kCGWindowOwnerPID as String] as? pid_t,
            let axWindow = axElement(for: windowID, pid: pid)
        else { return }

        // Unminimize before raising so the window is visible
        var minRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axWindow, kAXMinimizedAttribute as CFString, &minRef) == .success,
           let isMinimized = minRef as? Bool, isMinimized {
            AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, false as CFTypeRef)
        }

        AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
    }

    // Resolve a CGWindowID to its AXUIElement via the private _AXUIElementGetWindow function.
    private func axElement(for windowID: CGWindowID, pid: pid_t) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let axWindows = windowsRef as? [AXUIElement] else { return nil }
        for axWindow in axWindows {
            var wid: CGWindowID = 0
            if _AXUIElementGetWindow(axWindow, &wid) == .success, wid == windowID {
                return axWindow
            }
        }
        return nil
    }

    // MARK: - Helpers

    // Used by the window picker — only shows what's actually visible on screen right now.
    private func onScreenWindowList() -> [[String: Any]] {
        CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []
    }

    // Used for config resolution — includes minimized and windows on other Spaces so
    // stored IDs are found even when the user hasn't switched to that Space yet.
    private func configWindowList() -> [[String: Any]] {
        CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []
    }

}

extension Notification.Name {
    static let ctxConfigChanged = Notification.Name("ctx.configChanged")
}
