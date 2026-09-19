import Foundation

/// Formatting helpers shared by every surface (main window, overlay, menu bar).
public enum TimeFormat {

    /// `25:00`, `1:05:00`, `+0:23`. Negative values render with a leading `+`
    /// because in Pulse a negative remainder means "over budget", not "minus".
    public static func clock(_ seconds: TimeInterval) -> String {
        let over = seconds < -0.0001
        // Round *up* so a timer set to 25:00 reads "25:00" for its whole first
        // second instead of flicking to 24:59 immediately.
        let total = Int(over ? floor(-seconds) : ceil(max(0, seconds)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        let body: String
        if h > 0 {
            body = String(format: "%d:%02d:%02d", h, m, s)
        } else {
            body = String(format: "%d:%02d", m, s)
        }
        return over ? "+" + body : body
    }

    /// Menu-bar variant: drops seconds once past an hour so the title stays narrow.
    public static func compact(_ seconds: TimeInterval) -> String {
        let over = seconds < -0.0001
        let total = Int(over ? floor(-seconds) : ceil(max(0, seconds)))
        if total >= 3600 {
            let h = total / 3600
            let m = (total % 3600) / 60
            return (over ? "+" : "") + String(format: "%d:%02d", h, m)
        }
        return clock(seconds)
    }

    /// `25 min`, `1h 30m`, `45s` — for history rows and spoken-back confirmation.
    public static func humane(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds.rounded()))
        if total < 60 { return "\(total)s" }
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return m == 0 ? "\(h)h" : "\(h)h \(m)m" }
        return "\(m) min"
    }

    /// Wall-clock time a timer of this length would end at: "ends 3:47 PM".
    public static func endsAt(_ seconds: TimeInterval, from now: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = DateFormatter.dateFormat(fromTemplate: "jmm", options: 0, locale: .current)
        return f.string(from: now.addingTimeInterval(max(0, seconds)))
    }
}

/// The shape of the once-a-minute red pulse.
///
/// Deliberately asymmetric — a fast rise catches peripheral vision, a long soft
/// decay reads as ambient rather than as an alarm. Nothing moves or resizes
/// much; the signal is carried almost entirely by colour, which is what keeps
/// it visible without pulling you out of what you are doing.
public enum PulseEnvelope {
    public static let attack: TimeInterval = 0.16
    public static let decay: TimeInterval = 1.6
    public static var duration: TimeInterval { attack + decay }

    /// 0…1 intensity for a pulse that began `elapsed` seconds ago.
    public static func intensity(elapsed: TimeInterval) -> Double {
        guard elapsed >= 0, elapsed < duration else { return 0 }
        if elapsed < attack {
            let t = elapsed / attack
            return t * t * (3 - 2 * t)          // smoothstep up
        }
        let t = (elapsed - attack) / decay
        let e = 1 - t
        return e * e * e                         // cubic ease-out down
    }
}
