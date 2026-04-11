import AppKit
import Carbon.HIToolbox

class HotkeyManager {
    private let windowManager: WindowManager
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(windowManager: WindowManager) {
        self.windowManager = windowManager
    }

    func start() -> Bool {
        guard AXIsProcessTrusted() else { return false }

        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)

        let callback: CGEventTapCallBack = { _, _, event, refcon -> Unmanaged<CGEvent>? in
            guard let refcon else { return Unmanaged.passRetained(event) }
            return Unmanaged<HotkeyManager>
                .fromOpaque(refcon)
                .takeUnretainedValue()
                .handle(event: event)
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
        return true
    }

    private func handle(event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // Require Option only — no Command, Control, or Shift
        let optionOnly = flags.intersection([.maskAlternate, .maskCommand, .maskControl, .maskShift]) == .maskAlternate
        guard optionOnly else { return Unmanaged.passRetained(event) }

        switch Int(keyCode) {
        case kVK_Tab: // Option+Tab — cycle configs
            DispatchQueue.main.async { self.windowManager.cycleNextConfig() }
            return nil // consume event

        case kVK_ANSI_Grave: // Option+~ — cycle windows within active config
            DispatchQueue.main.async { self.windowManager.cycleWindowInConfig() }
            return nil

        default:
            return Unmanaged.passRetained(event)
        }
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
    }
}
