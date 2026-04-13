import AppKit
import Carbon.HIToolbox

class HotkeyManager {
    private let windowManager: WindowManager
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var wakeObserver: NSObjectProtocol?

    init(windowManager: WindowManager) {
        self.windowManager = windowManager
    }

    func start() -> Bool {
        guard AXIsProcessTrusted() else { return false }

        // Include tap-disabled pseudo-events so we can re-arm the tap if macOS kills it
        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.tapDisabledByTimeout.rawValue)
            | CGEventMask(1 << CGEventType.tapDisabledByUserInput.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon -> Unmanaged<CGEvent>? in
            guard let refcon else { return Unmanaged.passRetained(event) }
            return Unmanaged<HotkeyManager>
                .fromOpaque(refcon)
                .takeUnretainedValue()
                .handle(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        // Recreate the tap after sleep/wake — macOS can invalidate it silently
        let ws = NSWorkspace.shared.notificationCenter
        wakeObserver = ws.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.restart()
        }

        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS disabled the tap (e.g. secure input, timeout) — re-arm immediately
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passRetained(event)
        }

        guard type == .keyDown else { return Unmanaged.passRetained(event) }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        let relevant = flags.intersection([.maskAlternate, .maskCommand, .maskControl, .maskShift])
        let optionOnly  = relevant == .maskAlternate
        let optionShift = relevant == [.maskAlternate, .maskShift]

        guard optionOnly || optionShift else { return Unmanaged.passRetained(event) }

        switch Int(keyCode) {
        case kVK_Tab where optionOnly: // Option+Tab — cycle configs forward
            DispatchQueue.main.async { self.windowManager.cycleNextConfig() }
            return nil

        case kVK_ANSI_Grave where optionOnly: // Option+` — cycle windows forward
            DispatchQueue.main.async { self.windowManager.cycleWindowInConfig(forward: true) }
            return nil

        case kVK_ANSI_Grave where optionShift: // Shift+Option+` — cycle windows backward
            DispatchQueue.main.async { self.windowManager.cycleWindowInConfig(forward: false) }
            return nil

        default:
            return Unmanaged.passRetained(event)
        }
    }

    func restart() {
        stop()
        _ = start()
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil

        if let obs = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            wakeObserver = nil
        }
    }
}
