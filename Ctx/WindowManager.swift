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
    var cycleIndex: Int = 0 // for Option+~ cycling within config
}

class WindowManager: ObservableObject {
    @Published var configs: [WindowConfig] = [
        WindowConfig(name: "Work", windowIDs: []),
        WindowConfig(name: "Research", windowIDs: [])
    ]
    @Published var activeConfigIndex: Int = 0

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

    func setWindowIDs(forConfigAt index: Int, windowIDs: [CGWindowID]) {
        guard configs.indices.contains(index) else { return }
        configs[index].windowIDs = windowIDs
        configs[index].cycleIndex = 0
        activeConfigIndex = index
        NotificationCenter.default.post(name: .ctxConfigChanged, object: nil)
    }

    // MARK: - Cycling

    func cycleNextConfig() {
        guard configs.count > 1 else { return }
        switchToConfig(at: (activeConfigIndex + 1) % configs.count)
    }

    func switchToConfig(at index: Int) {
        guard configs.indices.contains(index) else { return }
        activeConfigIndex = index
        NotificationCenter.default.post(name: .ctxConfigChanged, object: nil)
        raiseActiveConfig()
    }

    // Cycles focus through individual windows within the active config (Option+~)
    func cycleWindowInConfig() {
        guard var config = activeConfig, !config.windowIDs.isEmpty else { return }
        config.cycleIndex = (config.cycleIndex + 1) % config.windowIDs.count
        configs[activeConfigIndex] = config

        let targetID = config.windowIDs[config.cycleIndex]
        let list = onScreenWindowList()
        if let info = list.first(where: { ($0[kCGWindowNumber as String] as? CGWindowID) == targetID }) {
            axRaiseWindow(info: info)
            if let pid = info[kCGWindowOwnerPID as String] as? pid_t {
                let app = NSRunningApplication(processIdentifier: pid)
                if #available(macOS 14.0, *) {
                    app?.activate()
                } else {
                    app?.activate(options: .activateIgnoringOtherApps)
                }
            }
        }
    }

    // MARK: - Raise

    func raiseActiveConfig() {
        guard let config = activeConfig, !config.windowIDs.isEmpty else { return }

        let list = onScreenWindowList()

        // Config windows in current z-order (front-to-back as returned by CGWindowList)
        let configInZOrder = list.compactMap { info -> [String: Any]? in
            guard let id = info[kCGWindowNumber as String] as? CGWindowID,
                  config.windowIDs.contains(id) else { return nil }
            return info
        }
        guard !configInZOrder.isEmpty else { return }

        // Step 1: AXRaise all windows back-to-front to set correct within-app z-order
        for info in configInZOrder.reversed() {
            axRaiseWindow(info: info)
        }

        // Step 2: Brief delay lets AXRaise settle in the window server before
        // we activate apps, preventing the race where activate fires before
        // the within-app z-order is committed.
        let snapshot = configInZOrder
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            var activatedPIDs = Set<pid_t>()
            for info in snapshot.reversed() {
                guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                      !activatedPIDs.contains(pid) else { continue }
                activatedPIDs.insert(pid)
                let app = NSRunningApplication(processIdentifier: pid)
                if #available(macOS 14.0, *) {
                    app?.activate()
                } else {
                    app?.activate(options: .activateIgnoringOtherApps)
                }
            }
        }
    }

    // AXRaise only — no app activation. Uses CGWindowID for exact matching.
    private func axRaiseWindow(info: [String: Any]) {
        guard
            let windowID = info[kCGWindowNumber as String] as? CGWindowID,
            let pid = info[kCGWindowOwnerPID as String] as? pid_t,
            let axWindow = axElement(for: windowID, pid: pid)
        else { return }
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

    private func onScreenWindowList() -> [[String: Any]] {
        CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []
    }

}

extension Notification.Name {
    static let ctxConfigChanged = Notification.Name("ctx.configChanged")
}
