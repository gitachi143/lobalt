import SwiftUI
import PulseKit

struct MainView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Environment(\.openWindow) private var openWindow
    @State private var quickEntry = ""
    @State private var chromeVisible = true
    @State private var chromeTimer: Timer?
    @FocusState private var quickFocused: Bool
    @FocusState private var labelFocused: Bool

    private var engine: TimerEngine { app.engine }

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.height < 460 || geo.size.width < 420
            let ring = min(geo.size.width * 0.62, geo.size.height * (compact ? 0.52 : 0.55))
            let ringSize = max(150, min(ring, 520))
            let pulse = app.pulseNow()

            ZStack {
                background(pulse: pulse)

                VStack(spacing: 0) {
                    header
                        .opacity(chromeVisible ? 1 : 0)
                        .allowsHitTesting(chromeVisible)

                    Spacer(minLength: 8)

                    TimerFace(ringSize: ringSize, pulse: pulse, reduceMotion: reduceMotion,
                              labelFocused: $labelFocused)

                    Spacer(minLength: 8)

                    VStack(spacing: compact ? 10 : 16) {
                        ControlRow(compact: compact)

                        if engine.phase == .idle && !compact {
                            PresetRow()
                        }
                        if !compact {
                            QuickEntryField(text: $quickEntry, focused: $quickFocused)
                        }
                        MessageLine()
                    }
                    .opacity(chromeVisible ? 1 : 0)
                    .allowsHitTesting(chromeVisible)

                    if !compact {
                        StatsFooter()
                            .opacity(chromeVisible ? 0.85 : 0)
                            .padding(.top, 10)
                    }
                }
                .padding(.horizontal, compact ? 16 : 28)
                .padding(.top, compact ? 10 : 14)
                .padding(.bottom, compact ? 12 : 18)
            }
            .animation(.easeInOut(duration: 0.35), value: chromeVisible)
            .animation(.easeOut(duration: 0.2), value: engine.phase)
        }
        .frame(minWidth: 360, minHeight: 380)
        .preferredColorScheme(.dark)
        .onContinuousHover { phase in
            if case .active = phase { wakeChrome() }
        }
        .onKeyPress(.space) {
            guard !quickFocused, !labelFocused else { return .ignored }
            app.toggle()
            return .handled
        }
        .background(KeyWindowAccessor())
    }

    // MARK: - Pieces

    private func background(pulse: Double) -> some View {
        ZStack {
            Palette.canvas
            RadialGradient(
                colors: [Color.white.opacity(0.055), .clear],
                center: .center, startRadius: 0, endRadius: 520
            )
            // Warm wash across the whole canvas, strongest at the edges.
            PulseVignette(pulse: pulse * 0.62)
            if app.finishFlash {
                Palette.over.opacity(0.10)
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.4), value: app.finishFlash)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(app.statusColor)
                .frame(width: 8, height: 8)
                .shadow(color: app.statusColor.opacity(0.8), radius: 4)
            Text("Pulse")
                .font(Theme.label(15, weight: .semibold))
                .foregroundStyle(Palette.primaryText)

            Spacer()

            RoundIconButton(systemName: "clock.arrow.circlepath", diameter: 28,
                            tint: Palette.secondaryText, help: "History") {
                openWindow(id: "history")
            }
            RoundIconButton(systemName: "gearshape", diameter: 28,
                            tint: Palette.secondaryText, help: "Settings") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        }
        .padding(.bottom, 6)
    }

    private func wakeChrome() {
        if !chromeVisible { chromeVisible = true }
        chromeTimer?.invalidate()
        // Only auto-hide when the window is filling the screen; in a normal
        // window the controls staying put is less jarring than them vanishing.
        guard NSApp.keyWindow?.styleMask.contains(.fullScreen) == true else { return }
        chromeTimer = Timer.scheduledTimer(withTimeInterval: 2.8, repeats: false) { _ in
            DispatchQueue.main.async { chromeVisible = false }
        }
    }
}

// MARK: - Timer face

private struct TimerFace: View {
    @Environment(AppState.self) private var app
    var ringSize: CGFloat
    var pulse: Double
    var reduceMotion: Bool
    @FocusState.Binding var labelFocused: Bool

    private var engine: TimerEngine { app.engine }

    var body: some View {
        let color = Theme.timeColor(remaining: engine.remaining, planned: engine.plannedDuration)
        let tinted = Theme.pulseTint(color, pulse: pulse)

        ZStack {
            TimerRing(fraction: engine.ringFraction,
                      color: color,
                      pulse: pulse,
                      lineWidth: max(6, ringSize * 0.038),
                      idle: engine.phase == .idle,
                      reduceMotion: reduceMotion)
                .frame(width: ringSize, height: ringSize)

            VStack(spacing: ringSize * 0.028) {
                if engine.phase != .running || engine.isOvertime {
                    StatusChip(text: app.statusText, color: app.statusColor,
                               size: max(9, ringSize * 0.032))
                }

                Text(engine.displayTime)
                    .font(Theme.digits(ringSize * 0.255, weight: .semibold))
                    .foregroundStyle(tinted)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.easeOut(duration: 0.18), value: engine.displayTime)

                if engine.phase == .running, !engine.isOvertime {
                    Text("ends \(TimeFormat.endsAt(engine.remaining))")
                        .font(Theme.label(max(9, ringSize * 0.042)))
                        .foregroundStyle(Palette.tertiaryText)
                } else if engine.phase == .idle {
                    Text(TimeFormat.humane(engine.plannedDuration))
                        .font(Theme.label(max(9, ringSize * 0.042)))
                        .foregroundStyle(Palette.tertiaryText)
                }

                LabelField(focused: $labelFocused, fontSize: max(11, ringSize * 0.055))
                    .frame(maxWidth: ringSize * 0.78)
                    .padding(.top, ringSize * 0.012)
            }
            .frame(width: ringSize * 0.82)
        }
        .frame(width: ringSize, height: ringSize)
    }
}

/// The task name. Reads as plain text until you click it.
private struct LabelField: View {
    @Environment(AppState.self) private var app
    @FocusState.Binding var focused: Bool
    var fontSize: CGFloat
    @State private var hovering = false

    @Environment(\.pulseSnapshotMode) private var snapshotMode

    var body: some View {
        @Bindable var engine = app.engine
        Group {
            if snapshotMode {
                Text(engine.label.isEmpty ? "What are you timing?" : engine.label)
                    .frame(maxWidth: .infinity)
            } else {
                TextField("What are you timing?", text: $engine.label)
                    .textFieldStyle(.plain)
                    .focused($focused)
            }
        }
            .multilineTextAlignment(.center)
            .font(Theme.label(fontSize, weight: .medium))
            .foregroundStyle(engine.label.isEmpty ? Palette.tertiaryText : Palette.secondaryText)
            .lineLimit(1)
            .padding(.vertical, 3)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(focused ? 0.08 : (hovering ? 0.05 : 0)))
            )
            .onHover { hovering = $0 }
            .onSubmit { focused = false }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

// MARK: - Controls

private struct ControlRow: View {
    @Environment(AppState.self) private var app
    var compact: Bool

    private var engine: TimerEngine { app.engine }
    private var big: CGFloat { compact ? 42 : 54 }
    private var small: CGFloat { compact ? 32 : 38 }

    var body: some View {
        HStack(spacing: compact ? 10 : 14) {
            switch engine.phase {
            case .idle:
                VoiceButton(diameter: small)
                RoundIconButton(systemName: "play.fill", diameter: big,
                                tint: Palette.calm, prominent: true,
                                help: "Start (Space)") {
                    app.start(seconds: Int(engine.plannedDuration), label: nil)
                }
                RoundIconButton(systemName: "minus", diameter: small,
                                tint: Palette.secondaryText, help: "Five minutes less") {
                    app.engine.add(seconds: -300)
                }
                RoundIconButton(systemName: "plus", diameter: small,
                                tint: Palette.secondaryText, help: "Five minutes more") {
                    app.engine.add(seconds: 300)
                }

            case .running, .paused:
                VoiceButton(diameter: small)
                RoundIconButton(systemName: engine.phase == .paused ? "play.fill" : "pause.fill",
                                diameter: big,
                                tint: engine.phase == .paused ? Palette.calm : Palette.primaryText,
                                prominent: engine.phase == .paused,
                                help: engine.phase == .paused ? "Resume (Space)" : "Pause (Space)") {
                    app.toggle()
                }
                RoundIconButton(systemName: "goforward.5", diameter: small,
                                tint: Palette.secondaryText, help: "Add five minutes") {
                    app.addMinutes(5)
                }
                RoundIconButton(systemName: "stop.fill", diameter: small,
                                tint: Palette.secondaryText, help: "Stop (⌘.)") {
                    app.stop()
                }

            case .finished:
                RoundIconButton(systemName: "checkmark", diameter: big,
                                tint: Palette.calm, prominent: true, help: "Done") {
                    app.engine.acknowledge()
                }
                RoundIconButton(systemName: "arrow.counterclockwise", diameter: small,
                                tint: Palette.secondaryText, help: "Run it again (⌘R)") {
                    app.restart()
                }
                RoundIconButton(systemName: "goforward.5", diameter: small,
                                tint: Palette.secondaryText, help: "Five more minutes") {
                    app.addMinutes(5)
                }
            }
        }
    }
}

private struct PresetRow: View {
    @Environment(AppState.self) private var app

    var body: some View {
        HStack(spacing: 7) {
            ForEach(app.settings.presets, id: \.self) { minutes in
                Button {
                    app.startPreset(minutes: minutes)
                } label: {
                    Text("\(minutes)")
                        .font(Theme.digits(13, weight: .medium))
                        .foregroundStyle(Palette.secondaryText)
                        .frame(minWidth: 34)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.white.opacity(0.07))
                        )
                }
                .buttonStyle(.plain)
                .help("Start a \(minutes) minute timer")
            }
        }
    }
}

// MARK: - Quick entry

private struct QuickEntryField: View {
    @Environment(AppState.self) private var app
    @Binding var text: String
    @FocusState.Binding var focused: Bool
    @Environment(\.pulseSnapshotMode) private var snapshotMode

    /// Live read-back so you can see it understood before hitting return.
    private var hint: String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        switch DurationParser.intent(trimmed) {
        case .start(let s, let label):
            let t = TimeFormat.clock(TimeInterval(s))
            return label.map { "\(t) · \($0)" } ?? t
        case .add(let s): return "+\(TimeFormat.humane(TimeInterval(s)))"
        case .pause: return "Pause"
        case .resume: return "Resume"
        case .stop: return "Stop"
        case .restart: return "Restart"
        case .unrecognized: return nil
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.cursor")
                .font(.system(size: 11))
                .foregroundStyle(Palette.tertiaryText)

            if snapshotMode {
                Text(text.isEmpty ? "25m write the essay" : text)
                    .font(Theme.label(13))
                    .foregroundStyle(text.isEmpty ? Palette.tertiaryText : Palette.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField("25m write the essay", text: $text)
                    .textFieldStyle(.plain)
                    .font(Theme.label(13))
                    .foregroundStyle(Palette.primaryText)
                    .focused($focused)
                    .onSubmit {
                        app.submitQuickEntry(text)
                        text = ""
                    }
            }

            if let hint {
                Text(hint)
                    .font(Theme.label(11, weight: .medium))
                    .foregroundStyle(Palette.calm)
                    .lineLimit(1)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.055))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(focused ? Palette.calm.opacity(0.45) : Palette.hairline, lineWidth: 1)
                )
        )
        .frame(maxWidth: 420)
        .animation(.easeOut(duration: 0.15), value: hint)
        .animation(.easeOut(duration: 0.15), value: focused)
    }
}

// MARK: - Feedback and stats

private struct MessageLine: View {
    @Environment(AppState.self) private var app

    var body: some View {
        Group {
            if app.speech.isListening {
                HStack(spacing: 7) {
                    ListeningDots()
                    Text(app.speech.transcript.isEmpty ? "Listening…" : app.speech.transcript)
                        .foregroundStyle(Palette.secondaryText)
                        .lineLimit(1)
                    if let p = app.speech.previewText {
                        Text("→ \(p)")
                            .foregroundStyle(Palette.calm)
                            .lineLimit(1)
                    }
                }
            } else if case .denied(let message) = app.speech.state {
                HStack(spacing: 6) {
                    Text(message).foregroundStyle(Palette.warn)
                    Button("Open Settings") { app.speech.openPrivacySettings() }
                        .buttonStyle(.link)
                        .font(Theme.label(11, weight: .medium))
                }
            } else if case .unavailable(let message) = app.speech.state {
                Text(message).foregroundStyle(Palette.warn)
            } else if let problem = app.problem {
                Text(problem).foregroundStyle(Palette.warn)
            } else if let echo = app.echo {
                Text(echo).foregroundStyle(Palette.secondaryText)
            } else {
                Text(" ")
            }
        }
        .font(Theme.label(11))
        .frame(height: 16)
        .animation(.easeOut(duration: 0.18), value: app.echo)
        .animation(.easeOut(duration: 0.18), value: app.problem)
    }
}

struct ListeningDots: View {
    @State private var phase = 0.0
    var tint: Color = Palette.urgent

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(tint)
                        .frame(width: 4, height: 4)
                        .opacity(0.35 + 0.65 * (0.5 + 0.5 * sin(t * 4 + Double(i) * 0.7)))
                }
            }
        }
    }
}

private struct StatsFooter: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let today = app.store.today
        HStack(spacing: 14) {
            stat("\(today.count)", "today")
            divider
            stat(TimeFormat.humane(today.totalTime), "timed")
            if today.hasOverrunData {
                divider
                stat(today.overrunDescription, "estimate")
            }
            let streak = app.store.dayStreak
            if streak > 1 {
                divider
                stat("\(streak)d", "streak")
            }
        }
        .font(Theme.label(10))
    }

    private var divider: some View {
        Rectangle().fill(Palette.hairline).frame(width: 1, height: 10)
    }

    private func stat(_ value: String, _ caption: String) -> some View {
        HStack(spacing: 4) {
            Text(value).foregroundStyle(Palette.secondaryText).fontWeight(.semibold)
            Text(caption).foregroundStyle(Palette.tertiaryText)
        }
    }
}

// MARK: - Voice button

struct VoiceButton: View {
    @Environment(AppState.self) private var app
    var diameter: CGFloat

    var body: some View {
        let listening = app.speech.isListening
        ZStack {
            if listening {
                Circle()
                    .stroke(Palette.urgent.opacity(0.5), lineWidth: 2)
                    .scaleEffect(1.25)
                    .blur(radius: 3)
            }
            RoundIconButton(systemName: listening ? "waveform" : "mic.fill",
                            diameter: diameter,
                            tint: listening ? Palette.urgent : Palette.secondaryText,
                            help: listening ? "Stop listening" : "Say a time limit (⌃⌥⌘V)") {
                app.toggleVoice()
            }
        }
        .animation(.easeOut(duration: 0.15), value: listening)
    }
}

/// Publishes the hosting `NSWindow` so the overlay can tell whether the timer
/// is already in front, and so "Open Pulse" can bring it back.
private struct KeyWindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // The view isn't in a window yet when this runs, and there may be no
        // further update to piggyback on, so poll briefly rather than taking
        // one shot at it.
        register(from: view, attempt: 0)
        return view
    }

    private func register(from view: NSView, attempt: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0 : 0.05)) {
            if let window = view.window {
                WindowRegistry.shared.adopt(window)
            } else if attempt < 20 {
                register(from: view, attempt: attempt + 1)
            }
        }
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window {
            WindowRegistry.shared.adopt(window)
        }
    }
}
