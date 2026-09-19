import Foundation
import Observation

enum OverlayMode: String, CaseIterable, Identifiable {
    case whileTiming   // only when a timer is going — the default
    case always        // always parked in the corner
    case never
    var id: String { rawValue }
    var title: String {
        switch self {
        case .whileTiming: return "While a timer is running"
        case .always: return "Always"
        case .never: return "Never"
        }
    }
}

enum OverlayCorner: String, CaseIterable, Identifiable {
    case topRight, topLeft, bottomRight, bottomLeft
    var id: String { rawValue }
    var title: String {
        switch self {
        case .topRight: return "Top right"
        case .topLeft: return "Top left"
        case .bottomRight: return "Bottom right"
        case .bottomLeft: return "Bottom left"
        }
    }
}

/// Everything the user can tune, mirrored into `UserDefaults` on write.
@Observable
final class AppSettings {

    // Pulse — the signature behaviour
    var pulseEnabled: Bool { didSet { d.set(pulseEnabled, forKey: K.pulseEnabled) } }
    /// Scales the peak of the glow. Low is a whisper, high is hard to miss.
    var pulseIntensity: Double { didSet { d.set(pulseIntensity, forKey: K.pulseIntensity) } }
    var pulseSound: Bool { didSet { d.set(pulseSound, forKey: K.pulseSound) } }

    // Finishing
    var finishSound: String { didSet { d.set(finishSound, forKey: K.finishSound) } }
    var notifyOnFinish: Bool { didSet { d.set(notifyOnFinish, forKey: K.notifyOnFinish) } }
    var continueIntoOvertime: Bool { didSet { d.set(continueIntoOvertime, forKey: K.continueIntoOvertime) } }

    // Overlay
    var overlayMode: OverlayMode { didSet { d.set(overlayMode.rawValue, forKey: K.overlayMode) } }
    var overlayCorner: OverlayCorner { didSet { d.set(overlayCorner.rawValue, forKey: K.overlayCorner) } }
    var overlayScale: Double { didSet { d.set(overlayScale, forKey: K.overlayScale) } }
    /// Nil until the user drags the overlay somewhere they prefer.
    var overlayOrigin: CGPoint? {
        didSet {
            if let p = overlayOrigin {
                d.set([p.x, p.y], forKey: K.overlayOrigin)
            } else {
                d.removeObject(forKey: K.overlayOrigin)
            }
        }
    }

    // System behaviour
    var keepDisplayAwake: Bool { didSet { d.set(keepDisplayAwake, forKey: K.keepDisplayAwake) } }
    var showDockIcon: Bool { didSet { d.set(showDockIcon, forKey: K.showDockIcon) } }
    var launchAtLogin: Bool { didSet { d.set(launchAtLogin, forKey: K.launchAtLogin) } }
    var hotkeysEnabled: Bool { didSet { d.set(hotkeysEnabled, forKey: K.hotkeysEnabled) } }

    // Quick presets, in minutes
    var presets: [Int] { didSet { d.set(presets, forKey: K.presets) } }

    /// Remembered so relaunching lands on the duration you use most.
    var lastDuration: Int { didSet { d.set(lastDuration, forKey: K.lastDuration) } }

    @ObservationIgnored private let d: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.d = defaults
        pulseEnabled = d.object(forKey: K.pulseEnabled) as? Bool ?? true
        pulseIntensity = d.object(forKey: K.pulseIntensity) as? Double ?? 0.7
        pulseSound = d.object(forKey: K.pulseSound) as? Bool ?? false
        finishSound = d.string(forKey: K.finishSound) ?? "Glass"
        notifyOnFinish = d.object(forKey: K.notifyOnFinish) as? Bool ?? true
        continueIntoOvertime = d.object(forKey: K.continueIntoOvertime) as? Bool ?? true
        overlayMode = OverlayMode(rawValue: d.string(forKey: K.overlayMode) ?? "") ?? .whileTiming
        overlayCorner = OverlayCorner(rawValue: d.string(forKey: K.overlayCorner) ?? "") ?? .topRight
        overlayScale = d.object(forKey: K.overlayScale) as? Double ?? 1.0
        if let pair = d.array(forKey: K.overlayOrigin) as? [Double], pair.count == 2 {
            overlayOrigin = CGPoint(x: pair[0], y: pair[1])
        }
        keepDisplayAwake = d.object(forKey: K.keepDisplayAwake) as? Bool ?? false
        showDockIcon = d.object(forKey: K.showDockIcon) as? Bool ?? true
        launchAtLogin = d.object(forKey: K.launchAtLogin) as? Bool ?? false
        hotkeysEnabled = d.object(forKey: K.hotkeysEnabled) as? Bool ?? true
        presets = (d.array(forKey: K.presets) as? [Int]) ?? [5, 10, 15, 25, 45, 60]
        lastDuration = d.object(forKey: K.lastDuration) as? Int ?? 25 * 60
    }

    private enum K {
        static let pulseEnabled = "pulseEnabled"
        static let pulseIntensity = "pulseIntensity"
        static let pulseSound = "pulseSound"
        static let finishSound = "finishSound"
        static let notifyOnFinish = "notifyOnFinish"
        static let continueIntoOvertime = "continueIntoOvertime"
        static let overlayMode = "overlayMode"
        static let overlayCorner = "overlayCorner"
        static let overlayScale = "overlayScale"
        static let overlayOrigin = "overlayOrigin"
        static let keepDisplayAwake = "keepDisplayAwake"
        static let showDockIcon = "showDockIcon"
        static let launchAtLogin = "launchAtLogin"
        static let hotkeysEnabled = "hotkeysEnabled"
        static let presets = "presets"
        static let lastDuration = "lastDuration"
    }
}
