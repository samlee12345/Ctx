import AppKit
import ApplicationServices
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    let windowManager = WindowManager()
    private var hotkeyManager: HotkeyManager?
    private var managerWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        requestAccessibilityIfNeeded()
        startHotkeys()

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
        statusItem?.button?.title = windowManager.activeConfigName
        statusItem?.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // One item per config — click to switch to it
        for (index, config) in windowManager.configs.enumerated() {
            let item = NSMenuItem(
                title: config.name,
                action: #selector(switchToConfig(_:)),
                keyEquivalent: ""
            )
            item.tag = index
            item.target = self
            item.state = index == windowManager.activeConfigIndex ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let openItem = NSMenuItem(title: "Open Ctx", action: #selector(openManager), keyEquivalent: ",")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Ctx", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    @objc private func switchToConfig(_ sender: NSMenuItem) {
        windowManager.switchToConfig(at: sender.tag)
    }

    @objc private func configChanged() {
        statusItem?.button?.title = windowManager.activeConfigName
        statusItem?.menu = buildMenu()
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

    // MARK: - Accessibility

    private func requestAccessibilityIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Hotkeys

    private func startHotkeys() {
        hotkeyManager = HotkeyManager(windowManager: windowManager)
        if !hotkeyManager!.start() {
            print("Ctx: Could not start hotkey manager — grant Accessibility permission and relaunch")
        }
    }
}
