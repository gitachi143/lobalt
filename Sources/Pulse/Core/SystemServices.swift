import AppKit
import Carbon.HIToolbox
import IOKit.pwr_mgt
import UserNotifications

// MARK: - Sound

enum SoundPlayer {
    /// Built-in alert sounds, in the order they appear in Settings.
    static let choices = ["None", "Glass", "Ping", "Hero", "Submarine", "Purr",
                          "Bottle", "Funk", "Blow", "Tink", "Sosumi"]

    static func play(_ name: String, volume: Float = 1.0) {
        guard name != "None", let sound = NSSound(named: NSSound.Name(name)) else { return }
        sound.volume = volume
        sound.stop()          // allow rapid re-triggering
        sound.play()
    }

    /// The finish alert: a short double chime reads as "done" more clearly
    /// than a single hit, without becoming an alarm.
    static func playFinish(_ name: String) {
        play(name)
        guard name != "None" else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { play(name, volume: 0.7) }
    }
}

// MARK: - Keeping the display awake

/// Holds an IOKit assertion so the screen doesn't sleep mid-timer.
final class DisplayAwakeAssertion {
    private var assertionID: IOPMAssertionID = 0
    private var held = false

    func setHeld(_ shouldHold: Bool, reason: String = "Pulse timer running") {
        guard shouldHold != held else { return }
        if shouldHold {
            var id: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason as CFString,
                &id
            )
            guard result == kIOReturnSuccess else { return }
            assertionID = id
            held = true
        } else {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
            held = false
        }
    }

    deinit { if held { IOPMAssertionRelease(assertionID) } }
}

// MARK: - Global hot keys

enum HotKeyAction: UInt32, CaseIterable {
    case toggleTimer = 1
    case voice = 2
    case showWindow = 3

    var keyCode: UInt32 {
        switch self {
        case .toggleTimer: return UInt32(kVK_ANSI_T)
        case .voice: return UInt32(kVK_ANSI_V)
        case .showWindow: return UInt32(kVK_ANSI_P)
        }
    }
    /// All three share ⌃⌥⌘ — unlikely to collide with anything else.
    var modifiers: UInt32 { UInt32(controlKey | optionKey | cmdKey) }

    var displayName: String {
        switch self {
        case .toggleTimer: return "Start / pause timer"
        case .voice: return "Speak a timer"
        case .showWindow: return "Show Pulse"
        }
    }
    var shortcutText: String {
        switch self {
        case .toggleTimer: return "⌃⌥⌘T"
        case .voice: return "⌃⌥⌘V"
        case .showWindow: return "⌃⌥⌘P"
        }
    }
}

private var hotKeyHandlers: [UInt32: () -> Void] = [:]

private func pulseHotKeyCallback(_ next: EventHandlerCallRef?,
                                 _ event: EventRef?,
                                 _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    var hkID = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                   EventParamType(typeEventHotKeyID), nil,
                                   MemoryLayout<EventHotKeyID>.size, nil, &hkID)
    guard status == noErr else { return status }
    let handler = hotKeyHandlers[hkID.id]
    DispatchQueue.main.async { handler?() }
    return noErr
}

/// System-wide shortcuts via Carbon, which — unlike an event monitor — needs no
/// Accessibility permission.
final class HotKeyCenter {
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlerRef: EventHandlerRef?
    private let signature: OSType = 0x504C5345   // 'PLSE'

    func install(_ bindings: [HotKeyAction: () -> Void]) {
        uninstall()
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), pulseHotKeyCallback, 1, &spec, nil, &handlerRef)

        for (action, handler) in bindings {
            hotKeyHandlers[action.rawValue] = handler
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: signature, id: action.rawValue)
            let status = RegisterEventHotKey(action.keyCode, action.modifiers, id,
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref { refs[action.rawValue] = ref }
        }
    }

    func uninstall() {
        for (_, ref) in refs { UnregisterEventHotKey(ref) }
        refs.removeAll()
        hotKeyHandlers.removeAll()
        if let handlerRef { RemoveEventHandler(handlerRef) }
        handlerRef = nil
    }

    deinit { uninstall() }
}

// MARK: - Notifications

/// Best-effort banner when a timer ends while you're in another app.
enum Notifier {
    private static var authorized = false
    private static var available: Bool { Bundle.main.bundleIdentifier != nil }

    static func requestAuthorization() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            authorized = granted
        }
    }

    static func timerFinished(label: String, planned: String) {
        guard available, authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = label.isEmpty ? "Time's up" : label
        content.body = "\(planned) done."
        content.interruptionLevel = .timeSensitive
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
