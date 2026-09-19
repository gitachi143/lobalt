import Foundation
import Observation

/// The timer itself.
///
/// Time is derived from a wall-clock `deadline` rather than accumulated from
/// ticks, so the countdown stays correct across display sleep, app nap, and a
/// laptop lid being shut for an hour. Ticks only exist to refresh the UI.
@Observable
public final class TimerEngine {

    public enum Phase: String, Sendable {
        case idle       // nothing scheduled
        case running    // counting (down, or up past zero when overtime is on)
        case paused
        case finished   // hit zero and stopped there, awaiting acknowledgement
    }

    // MARK: - Observable state

    public private(set) var phase: Phase = .idle
    public private(set) var plannedDuration: TimeInterval = 25 * 60
    public private(set) var remaining: TimeInterval = 25 * 60
    public var label: String = ""

    /// When the most recent minute pulse fired. Views read this each frame and
    /// run it through `PulseEnvelope` to get the current glow.
    public private(set) var lastPulseAt: Date?
    /// 0…1 — how insistent that pulse should be, rising as the deadline nears.
    public private(set) var pulseStrength: Double = 0.55

    public private(set) var startedAt: Date?

    // MARK: - Configuration

    /// Keep counting upward after zero instead of stopping, so you can see how
    /// far over your estimate you ran.
    public var continueIntoOvertime = true
    /// Set by the app when any window or the overlay is on screen; drives how
    /// often we tick so a background timer costs essentially nothing.
    public var isDisplayActive = false {
        didSet { if isDisplayActive != oldValue { rescheduleIfNeeded(force: true) } }
    }

    // MARK: - Callbacks (owned by the app layer)

    public var onFinish: (() -> Void)?
    public var onMinutePulse: (() -> Void)?
    /// Fired whenever a stretch of timed work ends, for the history log.
    public var onSessionEnd: ((Session) -> Void)?

    // MARK: - Private

    private var deadline: Date?
    private var pausedRemaining: TimeInterval?
    private var hasFiredFinish = false
    private var ticker: Timer?
    private var currentInterval: TimeInterval = 0
    private var lastBucket: Int = .max

    public init() {}

    // MARK: - Derived

    public var isOvertime: Bool { remaining < 0 }
    public var isActive: Bool { phase == .running || phase == .paused }

    /// 0…1 fraction of the planned time consumed. Clamped, so overtime sits at 1.
    public var progress: Double {
        guard plannedDuration > 0 else { return 0 }
        return min(1, max(0, 1 - remaining / plannedDuration))
    }

    /// Fraction of the circle the ring should draw.
    ///
    /// Counting down it is the time left, so the ring empties. Past zero it
    /// flips to the overtime accrued as a share of the estimate, so the ring
    /// fills back up — a full second lap means you have taken twice as long
    /// as you gave yourself.
    public var ringFraction: Double {
        guard plannedDuration > 0 else { return 0 }
        if remaining >= 0 { return min(1, max(0, remaining / plannedDuration)) }
        return min(1, max(0, -remaining / plannedDuration))
    }

    /// How long this stretch has actually been going, overtime included.
    public var elapsed: TimeInterval { plannedDuration - remaining }

    public var displayTime: String { TimeFormat.clock(remaining) }

    // MARK: - Transport

    public func start(seconds: Int, label: String? = nil) {
        guard seconds > 0 else { return }
        // A timer that had already run past zero counts as completed, even
        // though it is being replaced rather than acknowledged.
        recordSessionIfWorthKeeping(completed: remaining <= 0 && phase != .idle)
        plannedDuration = TimeInterval(seconds)
        remaining = TimeInterval(seconds)
        if let label { self.label = label }
        deadline = Date().addingTimeInterval(TimeInterval(seconds))
        startedAt = Date()
        pausedRemaining = nil
        hasFiredFinish = false
        lastPulseAt = nil
        lastBucket = bucket(for: remaining)
        phase = .running
        rescheduleIfNeeded(force: true)
    }

    public func pause() {
        guard phase == .running else { return }
        pausedRemaining = remaining
        deadline = nil
        phase = .paused
        rescheduleIfNeeded(force: true)
    }

    public func resume() {
        guard phase == .paused, let held = pausedRemaining else { return }
        deadline = Date().addingTimeInterval(held)
        pausedRemaining = nil
        phase = .running
        rescheduleIfNeeded(force: true)
    }

    public func toggle() {
        switch phase {
        case .running: pause()
        case .paused: resume()
        case .finished: restart()
        case .idle: start(seconds: Int(plannedDuration))
        }
    }

    /// Ends the current stretch and clears the label.
    public func stop() {
        recordSessionIfWorthKeeping(completed: remaining <= 0)
        deadline = nil
        pausedRemaining = nil
        startedAt = nil
        remaining = plannedDuration
        hasFiredFinish = false
        lastPulseAt = nil
        phase = .idle
        label = ""
        rescheduleIfNeeded(force: true)
    }

    /// Runs the same duration and label again from the top.
    public func restart() {
        let keep = label
        start(seconds: Int(plannedDuration), label: keep)
    }

    /// Extend (or, with a negative value, trim) the running timer.
    public func add(seconds: Int) {
        let delta = TimeInterval(seconds)
        switch phase {
        case .running:
            deadline = (deadline ?? Date()).addingTimeInterval(delta)
            plannedDuration += delta
            hasFiredFinish = false
            tick()
        case .paused:
            pausedRemaining = (pausedRemaining ?? 0) + delta
            plannedDuration += delta
            remaining = pausedRemaining ?? 0
        case .finished:
            // "give me five more" after the bell — pick straight back up.
            plannedDuration += delta
            deadline = Date().addingTimeInterval(delta)
            hasFiredFinish = false
            phase = .running
            rescheduleIfNeeded(force: true)
        case .idle:
            plannedDuration = max(1, plannedDuration + delta)
            remaining = plannedDuration
        }
        lastBucket = bucket(for: remaining)
    }

    /// Acknowledge a finished timer without logging a new session.
    public func acknowledge() {
        guard phase == .finished || isOvertime else { return }
        recordSessionIfWorthKeeping(completed: true)
        deadline = nil
        remaining = plannedDuration
        startedAt = nil
        hasFiredFinish = false
        phase = .idle
        label = ""
        rescheduleIfNeeded(force: true)
    }

    /// Fire a pulse right now, regardless of where the minute boundary is.
    /// Backs the "show me" button in Settings and the snapshot tooling.
    public func triggerPulse(strength: Double = 0.7) {
        pulseStrength = strength
        lastPulseAt = Date()
        onMinutePulse?()
        rescheduleIfNeeded(force: true)
    }

    /// Recompute immediately — used on wake from sleep, where the ticker has
    /// been frozen and the UI would otherwise show a stale time for a moment.
    public func refresh() { tick() }

    // MARK: - Ticking

    private func bucket(for r: TimeInterval) -> Int { Int(ceil(r / 60)) }

    private var desiredInterval: TimeInterval {
        guard phase == .running else { return 1 }
        guard isDisplayActive else { return 0.5 }
        if let last = lastPulseAt, Date().timeIntervalSince(last) < PulseEnvelope.duration + 0.05 {
            return 1.0 / 60.0            // smooth glow, ~1.7s per minute
        }
        if remaining <= 10.5, remaining > -0.5 { return 1.0 / 30.0 }   // final seconds
        return 0.2                        // digits and ring only
    }

    private func rescheduleIfNeeded(force: Bool = false) {
        let want = desiredInterval
        guard force || abs(want - currentInterval) > 0.0001 else { return }
        ticker?.invalidate()
        currentInterval = want
        guard phase == .running else { ticker = nil; return }
        let t = Timer(timeInterval: want, repeats: true) { [weak self] _ in self?.tick() }
        // Let the system coalesce the slow ticks; keep the pulse frames tight.
        t.tolerance = want > 0.1 ? want * 0.2 : 0
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func tick() {
        guard phase == .running, let deadline else { return }
        let next = deadline.timeIntervalSinceNow
        let previousBucket = lastBucket
        remaining = next

        var firedFinishThisTick = false
        if next <= 0, !hasFiredFinish {
            hasFiredFinish = true
            firedFinishThisTick = true
            onFinish?()
            if !continueIntoOvertime {
                remaining = 0
                phase = .finished
                recordSessionIfWorthKeeping(completed: true)
                rescheduleIfNeeded(force: true)
                return
            }
        }

        // One pulse per minute boundary. The zero crossing is skipped because
        // the finish alert is already a much louder signal.
        let nowBucket = bucket(for: next)
        if nowBucket != previousBucket {
            lastBucket = nowBucket
            if !firedFinishThisTick {
                pulseStrength = strength(for: next)
                lastPulseAt = Date()
                onMinutePulse?()
            }
        }
        rescheduleIfNeeded()
    }

    private func strength(for remaining: TimeInterval) -> Double {
        if remaining < 0 { return 1.0 }        // over budget: make it obvious
        if remaining <= 60 { return 1.0 }
        if remaining <= 300 { return 0.9 }
        return 0.75
    }

    // MARK: - History

    private func recordSessionIfWorthKeeping(completed: Bool) {
        guard let startedAt, let cb = onSessionEnd else { return }
        let actual = Date().timeIntervalSince(startedAt)
        // Ignore accidental starts — a few seconds isn't a session.
        guard actual >= 20 else { self.startedAt = nil; return }
        cb(Session(id: UUID(),
                   label: label.isEmpty ? "Untitled" : label,
                   planned: plannedDuration,
                   actual: actual,
                   startedAt: startedAt,
                   endedAt: Date(),
                   completed: completed))
        self.startedAt = nil
    }

    /// Restore a duration without starting — used when the app relaunches.
    public func preset(seconds: Int, label: String = "") {
        guard phase == .idle else { return }
        plannedDuration = TimeInterval(max(1, seconds))
        remaining = plannedDuration
        self.label = label
    }

    deinit { ticker?.invalidate() }
}
