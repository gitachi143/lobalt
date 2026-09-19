import Foundation
import Speech
import AVFoundation
import AppKit
import Observation
import LobaltKit

/// Microphone → text → `VoiceIntent`.
///
/// Recognition runs on-device whenever the machine supports it, so dictating a
/// timer works offline and nothing leaves the Mac.
@Observable
final class SpeechController {

    enum State: Equatable {
        case idle
        case listening
        case denied(String)
        case unavailable(String)
    }

    private(set) var state: State = .idle
    /// Live partial transcript, shown while you talk.
    private(set) var transcript: String = ""
    /// What we would do if you stopped talking right now.
    private(set) var preview: VoiceIntent?

    var isListening: Bool { state == .listening }

    /// Delivered once listening ends with something usable.
    @ObservationIgnored var onResult: ((VoiceIntent, String) -> Void)?

    @ObservationIgnored private let audio = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private lazy var recognizer: SFSpeechRecognizer? = {
        SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }()

    @ObservationIgnored private var silenceTimer: Timer?
    @ObservationIgnored private var hardStopTimer: Timer?

    /// Stop this long after the transcript stops changing.
    @ObservationIgnored private let silenceWindow: TimeInterval = 1.2
    /// Longer fuse before the first word — you need a moment to think.
    @ObservationIgnored private let openingWindow: TimeInterval = 3.5
    @ObservationIgnored private var heardSomething = false
    /// Never hold the mic open longer than this.
    @ObservationIgnored private let maxListen: TimeInterval = 12

    // MARK: - Permissions

    /// Ask up front (on first launch) so the prompt isn't a surprise mid-task.
    func primeAuthorization() {
        SFSpeechRecognizer.requestAuthorization { _ in }
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
    }

    private func authorize(_ done: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    AVCaptureDevice.requestAccess(for: .audio) { granted in
                        DispatchQueue.main.async {
                            if !granted {
                                self.state = .denied("Lobalt needs microphone access.")
                            }
                            done(granted)
                        }
                    }
                case .denied, .restricted:
                    self.state = .denied("Speech recognition is turned off for Lobalt.")
                    done(false)
                case .notDetermined:
                    done(false)
                @unknown default:
                    done(false)
                }
            }
        }
    }

    func openPrivacySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Control

    func toggle() {
        isListening ? finish(commit: true) : start()
    }

    func start() {
        guard !isListening else { return }
        transcript = ""
        preview = nil
        heardSomething = false

        guard let recognizer, recognizer.isAvailable else {
            state = .unavailable("Speech recognition isn't available right now.")
            return
        }
        authorize { [weak self] ok in
            guard let self, ok else { return }
            self.beginCapture(with: recognizer)
        }
    }

    private func beginCapture(with recognizer: SFSpeechRecognizer) {
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        // Nudges the recogniser towards timer vocabulary over similar-sounding words.
        req.contextualStrings = ["minutes", "minute", "seconds", "hours", "pomodoro",
                                 "timer", "pause", "resume", "stop", "restart", "half an hour"]
        request = req

        let input = audio.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            state = .unavailable("No microphone input is available.")
            return
        }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            req.append(buffer)
        }

        audio.prepare()
        do {
            try audio.start()
        } catch {
            state = .unavailable("Couldn't start the microphone: \(error.localizedDescription)")
            teardownAudio()
            return
        }

        state = .listening
        armHardStop()
        armSilenceTimer()

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            DispatchQueue.main.async {
                if let result {
                    let text = result.bestTranscription.formattedString
                    if text != self.transcript {
                        self.transcript = text
                        self.heardSomething = !text.isEmpty
                        self.preview = text.isEmpty ? nil : DurationParser.intent(text)
                        self.armSilenceTimer()     // keep listening while they talk
                    }
                    if result.isFinal { self.finish(commit: true) }
                }
                if error != nil, self.isListening {
                    // A recogniser error after we have words is still usable.
                    self.finish(commit: !self.transcript.isEmpty)
                }
            }
        }
    }

    /// Ends the session. `commit` decides whether the result is acted on.
    func finish(commit: Bool) {
        silenceTimer?.invalidate(); silenceTimer = nil
        hardStopTimer?.invalidate(); hardStopTimer = nil

        let text = transcript
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        teardownAudio()

        if state == .listening { state = .idle }

        guard commit, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        onResult?(DurationParser.intent(text), text)
    }

    func cancel() { finish(commit: false) }

    private func teardownAudio() {
        if audio.isRunning { audio.stop() }
        audio.inputNode.removeTap(onBus: 0)
    }

    private func armSilenceTimer() {
        silenceTimer?.invalidate()
        let window = heardSomething ? silenceWindow : openingWindow
        silenceTimer = Timer.scheduledTimer(withTimeInterval: window, repeats: false) { [weak self] _ in
            self?.finish(commit: true)
        }
    }

    private func armHardStop() {
        hardStopTimer?.invalidate()
        hardStopTimer = Timer.scheduledTimer(withTimeInterval: maxListen, repeats: false) { [weak self] _ in
            self?.finish(commit: true)
        }
    }

    /// Human-readable echo of `preview`, e.g. "25:00 · Write essay".
    var previewText: String? {
        guard let preview else { return nil }
        switch preview {
        case .start(let s, let label):
            let time = TimeFormat.clock(TimeInterval(s))
            return label.map { "\(time) · \($0)" } ?? time
        case .add(let s): return "+\(TimeFormat.humane(TimeInterval(s)))"
        case .pause: return "Pause"
        case .resume: return "Resume"
        case .stop: return "Stop"
        case .restart: return "Restart"
        case .unrecognized: return nil
        }
    }
}
