import SwiftUI
import LobaltKit

/// Dark-first palette. The timer surfaces stay dark regardless of system
/// appearance so the red pulse reads identically every time.
enum Palette {
    static let canvas = Color(red: 0.055, green: 0.063, blue: 0.075)
    static let raised = Color(red: 0.102, green: 0.114, blue: 0.133)
    static let hairline = Color.white.opacity(0.08)
    static let track = Color.white.opacity(0.10)

    static let calm = Color(red: 0.247, green: 0.839, blue: 0.659)   // mint
    static let warn = Color(red: 0.949, green: 0.757, blue: 0.306)   // amber
    static let urgent = Color(red: 0.941, green: 0.392, blue: 0.286) // coral
    static let over = Color(red: 1.000, green: 0.231, blue: 0.188)   // red
    static let pulse = Color(red: 1.000, green: 0.271, blue: 0.208)
    /// Deep, saturated red for flooding a whole surface. Bright red across
    /// that much area swamps the digits; this keeps them legible through it.
    static let impact = Color(red: 0.460, green: 0.035, blue: 0.030)

    static let primaryText = Color.white.opacity(0.95)
    static let secondaryText = Color.white.opacity(0.55)
    static let tertiaryText = Color.white.opacity(0.35)
}

extension Color {
    /// Linear blend in sRGB. Good enough for the short hops this app makes.
    func blended(with other: Color, amount: Double) -> Color {
        let t = min(1, max(0, amount))
        guard let a = NSColor(self).usingColorSpace(.sRGB),
              let b = NSColor(other).usingColorSpace(.sRGB) else { return self }
        return Color(red: Double(a.redComponent + (b.redComponent - a.redComponent) * CGFloat(t)),
                     green: Double(a.greenComponent + (b.greenComponent - a.greenComponent) * CGFloat(t)),
                     blue: Double(a.blueComponent + (b.blueComponent - a.blueComponent) * CGFloat(t)))
    }
}

enum Theme {

    /// How pressing the remaining time feels, 0…1.
    ///
    /// Blends a proportional sense (how much of the box is gone) with an
    /// absolute one (a minute left is a minute left, whether the timer was
    /// five minutes or two hours).
    static func urgency(remaining: TimeInterval, planned: TimeInterval) -> Double {
        if remaining <= 0 { return 1 }
        let byFraction: Double = {
            guard planned > 0 else { return 0 }
            let frac = remaining / planned
            if frac >= 0.35 { return 0 }
            return min(1, (0.35 - frac) / 0.35)
        }()
        let byClock: Double = {
            let window: TimeInterval = 120
            guard remaining < window else { return 0 }
            return (window - remaining) / window
        }()
        return max(byFraction, byClock)
    }

    /// Ring and digit colour: mint → amber → coral → red as time runs out.
    static func timeColor(remaining: TimeInterval, planned: TimeInterval) -> Color {
        if remaining < 0 { return Palette.over }
        let u = urgency(remaining: remaining, planned: planned)
        if u <= 0.5 {
            return Palette.calm.blended(with: Palette.warn, amount: u / 0.5)
        }
        return Palette.warn.blended(with: Palette.urgent, amount: (u - 0.5) / 0.5)
    }

    /// Colour for a surface caught mid-pulse.
    ///
    /// Routed through amber rather than straight at red. Mint and red sit
    /// nearly opposite each other, so a direct blend spends the whole decay in
    /// muddy browns, and rotating the hue instead parks it in lime. Going by
    /// way of amber keeps every frame a saturated colour and reads the way it
    /// should: heat arriving, then cooling off.
    static func pulseTint(_ base: Color, pulse: Double) -> Color {
        guard pulse > 0.001 else { return base }
        // Steep response, so the peak is unmistakably red rather than orange.
        let a = min(1, pow(pulse, 0.45) * 1.2)
        let mid = base.blended(with: Palette.warn, amount: 0.75)
        return a <= 0.5
            ? base.blended(with: mid, amount: a * 2)
            : mid.blended(with: Palette.pulse, amount: (a - 0.5) * 2)
    }

    /// Tint for the digits themselves.
    ///
    /// The surface behind them floods red on the beat, so matching it would
    /// leave the time unreadable exactly when it is being drawn attention to.
    /// Past the midpoint the digits keep heating past red into white-hot,
    /// which holds contrast against the flood and reads as the hottest thing
    /// on screen.
    static func pulseDigitTint(_ base: Color, pulse: Double) -> Color {
        let hot = pulseTint(base, pulse: pulse)
        let a = min(1, pow(pulse, 0.45) * 1.2)
        guard a > 0.45 else { return hot }
        let whiteHot = Color(red: 1.0, green: 0.95, blue: 0.92)
        return hot.blended(with: whiteHot, amount: (a - 0.45) / 0.55 * 0.88)
    }

    /// Current glow from the once-a-minute pulse, already scaled by the
    /// user's intensity preference. Returns 0 when pulsing is switched off.
    static func pulseIntensity(engine: TimerEngine, settings: AppSettings, now: Date) -> Double {
        guard settings.pulseEnabled, let last = engine.lastPulseAt else { return 0 }
        let raw = PulseEnvelope.intensity(elapsed: now.timeIntervalSince(last))
        return raw * engine.pulseStrength * settings.pulseIntensity
    }

    // Type. Monospaced digits everywhere so nothing jitters as numbers change.
    static func digits(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
    static func label(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

/// Set while rendering documentation images. `ImageRenderer` cannot draw
/// AppKit-backed text fields, so those swap to static text that matches their
/// resting appearance. Nothing else about the layout changes.
private struct SnapshotModeKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    var lobaltSnapshotMode: Bool {
        get { self[SnapshotModeKey.self] }
        set { self[SnapshotModeKey.self] = newValue }
    }
}
