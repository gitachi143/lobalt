import Foundation

/// Formatting helpers shared by every surface (main window, overlay, menu bar).
public enum TimeFormat {

    /// `25:00`, `1:05:00`, `+0:23`. Negative values render with a leading `+`
    /// because in Lobalt a negative remainder means "over budget", not "minus".
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
/// Three stages rather than a simple rise and fall: an almost instant hit, a
/// hard drop off the peak, then a long afterglow. That is what makes it land
/// as an impact — a symmetrical swell reads as a slow throb, and a plain
/// exponential decay is gone before you have looked up. The tail is what keeps
/// the timer warm for a second or two after the hit.
public enum PulseEnvelope {
    /// Time to reach full strength. Short enough to feel instantaneous.
    public static let attack: TimeInterval = 0.045
    /// The hard fall away from the peak.
    public static let punch: TimeInterval = 0.28
    /// The afterglow, fading from `plateau` to nothing.
    public static let tail: TimeInterval = 1.9
    /// Level the punch falls to before the slow fade takes over.
    public static let plateau: Double = 0.42

    public static var duration: TimeInterval { attack + punch + tail }

    /// 0…1 intensity for a pulse that began `elapsed` seconds ago.
    public static func intensity(elapsed: TimeInterval) -> Double {
        guard elapsed >= 0, elapsed < duration else { return 0 }

        if elapsed < attack {
            let t = elapsed / attack
            return t * t * (3 - 2 * t)                  // smoothstep up
        }
        if elapsed < attack + punch {
            let t = (elapsed - attack) / punch
            let e = 1 - t
            return plateau + (1 - plateau) * e * e      // peak -> plateau
        }
        let t = (elapsed - attack - punch) / tail
        let e = 1 - t
        return plateau * e * e                          // plateau -> nothing
    }
}
