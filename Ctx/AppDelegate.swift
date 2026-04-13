import AppKit
import ApplicationServices
import Carbon
import Combine
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    let windowManager = WindowManager()
    private var hotkeyManager: HotkeyManager?
    private var managerWindow: NSWindow?
    private var focusedWindowSnapshot: WindowManager.WindowInfo?
    private var cyclerPanel: NSPanel?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        requestAccessibilityIfNeeded()
        startHotkeys()
        observeCycling()

        windowManager.noOpHandler = { [weak self] in
            self?.flashStatusBar(warning: true)
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(configChanged),
            name: .ctxConfigChanged,
            object: nil
        )
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusTitle()
        statusItem?.menu = buildMenu()
    }

    private func updateStatusTitle() {
        let base = windowManager.activeConfigName
        // Show a lock glyph when secure input is blocking the event tap
        let title = IsSecureEventInputEnabled() ? "[locked] \(base)" : base
        statusItem?.button?.title = title
    }

    // Briefly prefix the status title with a warning to signal a no-op hotkey press
    private func flashStatusBar(warning: Bool) {
        guard let button = statusItem?.button else { return }
        let original = button.title
        button.title = "! \(windowManager.activeConfigName)"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            button.title = original
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        populateMenuItems(menu)
        return menu
    }

    private func populateMenuItems(_ menu: NSMenu) {
        menu.removeAllItems()

        // Warn if accessibility has been revoked since launch
        if !AXIsProcessTrusted() {
            let warnItem = NSMenuItem(
                title: "Accessibility required — click to fix",
                action: #selector(openAccessibilitySettings),
                keyEquivalent: ""
            )
            warnItem.target = self
            menu.addItem(warnItem)
            menu.addItem(.separator())
        }

        for (index, config) in windowManager.configs.enumerated() {
            // Config switch item
            let item = NSMenuItem(
                title: config.name,
                action: #selector(switchToConfig(_:)),
                keyEquivalent: ""
            )
            item.tag = index
            item.target = self
            item.state = index == windowManager.activeConfigIndex ? .on : .off
            menu.addItem(item)

            // Quick-add item for the focused window
            if let snapshot = focusedWindowSnapshot {
                let alreadyAdded = windowManager.configs[index].windowIDs.contains(snapshot.id)
                let raw = snapshot.windowTitle
                let displayTitle = raw.count > 32 ? String(raw.prefix(29)) + "..." : raw
                let addItem = NSMenuItem(
                    title: "Add \"\(displayTitle)\" to \(config.name)",
                    action: #selector(addFocusedWindowToConfig(_:)),
                    keyEquivalent: ""
                )
                addItem.tag = index
                addItem.target = self
                addItem.indentationLevel = 1
                addItem.isEnabled = !alreadyAdded
                menu.addItem(addItem)
            }
        }

        menu.addItem(.separator())

        let openItem = NSMenuItem(title: "Open Ctx", action: #selector(openManager), keyEquivalent: ",")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Ctx", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func switchToConfig(_ sender: NSMenuItem) {
        windowManager.switchToConfig(at: sender.tag)
    }

    @objc private func addFocusedWindowToConfig(_ sender: NSMenuItem) {
        guard let window = focusedWindowSnapshot else { return }
        windowManager.addWindow(window.id, appName: window.appName, toConfigAt: sender.tag)
    }

    @objc private func configChanged() {
        updateStatusTitle()
        // Menu items refresh via menuNeedsUpdate next time the menu opens
    }

    // MARK: - Manager Window

    @objc private func openManager() {
        if let existing = managerWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = ConfigManagerView(windowManager: windowManager)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Ctx"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.setContentSize(NSSize(width: 620, height: 430))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        managerWindow = window
    }

    // MARK: - Config Cycler Overlay

    private func observeCycling() {
        windowManager.$isCyclingConfigs
            .receive(on: RunLoop.main)
            .sink { [weak self] cycling in
                if cycling { self?.showCyclerPanel() }
                else { self?.hideCyclerPanel() }
            }
            .store(in: &cancellables)
    }

    private func showCyclerPanel() {
        if cyclerPanel == nil {
            let panel = NSPanel(
                contentRect: .zero,
                styleMask: [.nonactivatingPanel, .borderless, .hudWindow],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .floating
            panel.hasShadow = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            cyclerPanel = panel
        }

        let hostingView = NSHostingView(rootView: ConfigCyclerView(windowManager: windowManager))
        let size = hostingView.fittingSize
        cyclerPanel?.contentView = hostingView

        if let screen = NSScreen.main, let panel = cyclerPanel {
            let sf = screen.visibleFrame
            let origin = NSPoint(x: sf.midX - size.width / 2, y: sf.midY - size.height / 2)
            panel.setFrame(NSRect(origin: origin, size: size), display: false)
        }

        cyclerPanel?.orderFrontRegardless()
    }

    private func hideCyclerPanel() {
        cyclerPanel?.orderOut(nil)
    }

    // MARK: - Accessibility

    private func requestAccessibilityIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Hotkeys

    private func startHotkeys() {
        hotkeyManager?.stop()
        let hkm = HotkeyManager(windowManager: windowManager)
        hotkeyManager = hkm
        if !hkm.start() {
            print("Ctx: hotkey tap failed — Accessibility permission required")
        }
    }
}

// MARK: - NSMenuDelegate

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        focusedWindowSnapshot = windowManager.focusedWindowInfo()
        populateMenuItems(menu)
    }
}
