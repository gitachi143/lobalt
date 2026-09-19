import AppKit
import SwiftUI
import Observation
import PulseKit

/// Single place the UI talks to. Owns the engine and every side effect that
/// hangs off it — sound, notifications, history, sleep prevention, voice.
@Observable
final class AppState {

    let engine = TimerEngine()
    let store: SessionStore
    let settings: AppSettings
    let speech = SpeechController()

    /// Transient confirmation line shown after a voice or quick-entry command.
    private(set) var echo: String?
    /// Transient problem line ("didn't catch a duration").
    private(set) var problem: String?

    /// Raised for a moment when a timer ends, so surfaces can flash.
    private(set) var finishFlash = false

    /// Installed by the app delegate.
    @ObservationIgnored var onFinished: (() -> Void)?
    @ObservationIgnored var onShowMainWindow: (() -> Void)?

    @ObservationIgnored private let awake = DisplayAwakeAssertion()
    @ObservationIgnored private var echoTimer: Timer?
    @ObservationIgnored private var flashTimer: Timer?

    /// `defaults` and `storeURL` are overridable so the developer tooling can
    /// run against throwaway state instead of the real preferences and history.
    init(defaults: UserDefaults = .standard, storeURL: URL? = nil) {
        self.settings = AppSettings(defaults: defaults)
        self.store = SessionStore(url: storeURL)

        engine.preset(seconds: settings.lastDuration)
        syncSettings()

        engine.onFinish = { [weak self] in self?.handleFinish() }
        engine.onMinutePulse = { [weak self] in
            guard let self, self.settings.pulseSound else { return }
            SoundPlayer.play("Tink", volume: 0.25)
        }
        engine.onSessionEnd = { [weak self] session in self?.store.add(session) }

        speech.onResult = { [weak self] intent, transcript in
            self?.handle(intent, source: transcript)
        }
    }

    /// Push preference values into the engine and the system.
    func syncSettings() {
        engine.continueIntoOvertime = settings.continueIntoOvertime
        awake.setHeld(settings.keepDisplayAwake && engine.phase == .running)
    }

    // MARK: - Transport

    func start(seconds: Int, label: String?) {
        syncSettings()
        engine.start(seconds: seconds, label: label ?? engine.label)
        settings.lastDuration = seconds
        awake.setHeld(settings.keepDisplayAwake)
        var line = "Started \(TimeFormat.humane(TimeInterval(seconds)))"
        if let label, !label.isEmpty { line += " · \(label)" }
        show(echo: line)
    }

    func startPreset(minutes: Int) { start(seconds: minutes * 60, label: nil) }

    func toggle() {
        engine.toggle()
        awake.setHeld(settings.keepDisplayAwake && engine.phase == .running)
    }

    func stop() {
        engine.stop()
        awake.setHeld(false)
    }

    func addMinutes(_ minutes: Int) {
        engine.add(seconds: minutes * 60)
        show(echo: "\(minutes > 0 ? "+" : "")\(minutes) min")
    }

    func restart() {
        engine.restart()
        awake.setHeld(settings.keepDisplayAwake)
    }

    // MARK: - Voice and typed commands

    func toggleVoice() { speech.toggle() }

    /// Shared by the microphone and the type-to-start field.
    func handle(_ intent: VoiceIntent, source: String) {
        problem = nil
        switch intent {
        case .start(let seconds, let label):
            start(seconds: seconds, label: label)
        case .add(let seconds):
            guard engine.isActive || engine.phase == .finished else {
                start(seconds: seconds, label: nil); return
            }
            engine.add(seconds: seconds)
            show(echo: "+\(TimeFormat.humane(TimeInterval(seconds)))")
        case .pause:
            engine.pause(); show(echo: "Paused")
        case .resume:
            if engine.phase == .paused { engine.resume(); show(echo: "Resumed") }
            else if engine.phase == .idle { start(seconds: Int(engine.plannedDuration), label: nil) }
        case .stop:
            stop(); show(echo: "Stopped")
        case .restart:
            restart(); show(echo: "Restarted")
        case .unrecognized(let text):
            show(problem: text.isEmpty ? "Didn't catch that." : "No duration in “\(text)”")
        }
    }

    func submitQuickEntry(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        handle(DurationParser.intent(trimmed), source: trimmed)
    }

    // MARK: - Finishing

    private func handleFinish() {
        SoundPlayer.playFinish(settings.finishSound)
        if settings.notifyOnFinish {
            Notifier.timerFinished(label: engine.label,
                                   planned: TimeFormat.humane(engine.plannedDuration))
        }
        NSApp.requestUserAttention(.informationalRequest)
        awake.setHeld(false)
        onFinished?()

        finishFlash = true
        flashTimer?.invalidate()
        flashTimer = Timer.scheduledTimer(withTimeInterval: 2.4, repeats: false) { [weak self] _ in
            self?.finishFlash = false
        }
    }

    // MARK: - Transient messages

    private func show(echo text: String) {
        echo = text
        problem = nil
        scheduleClear()
    }

    private func show(problem text: String) {
        problem = text
        echo = nil
        scheduleClear(after: 4)
    }

    private func scheduleClear(after seconds: TimeInterval = 2.6) {
        echoTimer?.invalidate()
        echoTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            self?.echo = nil
            self?.problem = nil
        }
    }

    // MARK: - Convenience for views

    var statusText: String {
        switch engine.phase {
        case .idle: return "Ready"
        case .running: return engine.isOvertime ? "Over" : "Running"
        case .paused: return "Paused"
        case .finished: return "Done"
        }
    }

    var statusColor: Color {
        switch engine.phase {
        case .idle: return Palette.secondaryText
        case .running: return engine.isOvertime ? Palette.over
                                                : Theme.timeColor(remaining: engine.remaining,
                                                                  planned: engine.plannedDuration)
        case .paused: return Palette.warn
        case .finished: return Palette.over
        }
    }

    /// Current pulse glow, 0…1. Reading `engine.remaining` here is deliberate:
    /// it subscribes the caller to the engine's tick so the glow animates.
    func pulseNow() -> Double {
        _ = engine.remaining
        return Theme.pulseIntensity(engine: engine, settings: settings, now: Date())
    }
}
