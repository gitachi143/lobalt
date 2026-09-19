import SwiftUI
import LobaltKit

struct MainView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var chromeVisible = true
    @State private var chromeTimer: Timer?
    @State private var isFullScreen = false
    @State private var controlsHovered = false
    @Environment(\.lobaltSnapshotMode) private var snapshotMode
    @Environment(\.lobaltSnapshotFullScreen) private var forcedFullScreen
    @Environment(\.lobaltSnapshotHoverControls) private var forcedHover

    private var fullScreen: Bool { isFullScreen || forcedFullScreen }
    private var controlsExpanded: Bool { controlsHovered || forcedHover }
    @FocusState private var quickFocused: Bool
    @FocusState private var labelFocused: Bool

    private var engine: TimerEngine { app.engine }

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.height < 460 || geo.size.width < 420
            let ringSize = ringSize(for: geo.size, compact: compact)
            let pulse = app.pulseNow()

            ZStack {
                background(pulse: pulse)

                if fullScreen {
                    fullScreenLayout(ringSize: ringSize, pulse: pulse)
                } else {
                    windowedLayout(geo: geo, compact: compact, ringSize: ringSize, pulse: pulse)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: chromeVisible)
            .animation(.easeInOut(duration: 0.4), value: fullScreen)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: controlsExpanded)
            .animation(.easeOut(duration: 0.2), value: engine.phase)
        }
        .frame(minWidth: 360, minHeight: 380)
        .preferredColorScheme(.dark)
        .onContinuousHover { phase in
            if case .active = phase { wakeChrome() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { note in
            if (note.object as? NSWindow) === WindowRegistry.shared.mainWindow { isFullScreen = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { note in
            if (note.object as? NSWindow) === WindowRegistry.shared.mainWindow {
                isFullScreen = false
                chromeVisible = true
            }
        }
        .onKeyPress(.space) {
            guard !quickFocused, !labelFocused else { return .ignored }
            app.toggle()
            return .handled
        }
        .background(KeyWindowAccessor())
    }

    // MARK: - Layouts

    /// Normal window: the timer fills the view, with history one scroll below
    /// it. A separate window for the log meant remembering it existed.
    private func windowedLayout(geo: GeometryProxy, compact: Bool,
                                ringSize: CGFloat, pulse: Double) -> some View {
        Group {
            if snapshotMode {
                // ImageRenderer can't draw the contents of a ScrollView, so
                // documentation images render the page on its own.
                timerPage(geo: geo, compact: compact, ringSize: ringSize, pulse: pulse)
            } else {
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        timerPage(geo: geo, compact: compact, ringSize: ringSize, pulse: pulse)
                            .frame(height: geo.size.height)
                        HistorySection()
                    }
                }
                .scrollIndicators(.never)
            }
        }
    }

    private func timerPage(geo: GeometryProxy, compact: Bool,
                           ringSize: CGFloat, pulse: Double) -> some View {
        VStack(spacing: 0) {
            header
                .opacity(chromeVisible ? 1 : 0)
                .allowsHitTesting(chromeVisible)

            Spacer(minLength: 8)

            TimerFace(ringSize: ringSize, pulse: pulse, reduceMotion: reduceMotion,
                      labelFocused: $labelFocused)

            Spacer(minLength: 8)

            VStack(spacing: compact ? 10 : 16) {
                ControlRow(compact: compact, pulse: pulse,
                           scale: geo.size.width >= 1000 && geo.size.height >= 760 ? 1.3 : 1)

                if engine.phase == .idle && !compact {
                    PresetRow(quickFocused: $quickFocused)
                }
                if !compact {
                    QuickEntryField(focused: $quickFocused)
                }
                MessageLine()
            }
            .opacity(chromeVisible ? 1 : 0)
            .allowsHitTesting(chromeVisible)

            if !compact {
                VStack(spacing: 3) {
                    StatsFooter()
                    // Quiet hint that the log is a scroll away.
                    Image(systemName: "chevron.compact.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.tertiaryText)
                }
                .opacity(chromeVisible ? 0.85 : 0)
                .padding(.top, 8)
            }
        }
        .padding(.horizontal, compact ? 16 : 28)
        .padding(.top, compact ? 10 : 14)
        .padding(.bottom, compact ? 12 : 18)
    }

    /// Full screen: the ring is the point, so it keeps a constant, large size
    /// and the controls float over it. Laying them out in the flow would mean
    /// the timer shrank every time you moved the mouse.
    private func fullScreenLayout(ringSize: CGFloat, pulse: Double) -> some View {
        ZStack {
            // Nudged up so the task name clears the control bar that floats
            // over the bottom. Constant rather than tied to the bar being
            // visible, so nothing jumps when it fades in.
            TimerFace(ringSize: ringSize, pulse: pulse, reduceMotion: reduceMotion,
                      labelFocused: $labelFocused)
                // A nudge up, so the task name inside the ring clears the bar
                // floating over the bottom. Constant, so nothing jumps when
                // the bar fades in.
                .offset(y: -ringSize * 0.03)

            VStack(spacing: 0) {
                header
                Spacer(minLength: 0)
                floatingControls(pulse: pulse)
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 22)
            .opacity(chromeVisible ? 1 : 0)
            .allowsHitTesting(chromeVisible)
        }
    }

    /// The control bar that hovers over the bottom of the full-screen timer.
    /// Pointing at it makes everything in it grow.
    private func floatingControls(pulse: Double) -> some View {
        let scale: CGFloat = controlsExpanded ? 1.9 : 1.5

        // Two rows rather than three: every extra row pushes the bar further
        // up the screen and eats into how big the ring is allowed to be.
        return VStack(spacing: 14) {
            ControlRow(compact: false, pulse: pulse, scale: scale)

            HStack(spacing: 12) {
                if engine.phase == .idle {
                    PresetRow(quickFocused: $quickFocused, scale: controlsExpanded ? 1.3 : 1.1)
                }
                QuickEntryField(focused: $quickFocused)
                    .frame(width: 260)
            }

            MessageLine()
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Palette.canvas.opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(Palette.hairline, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.4), radius: 24, y: 10)
        )
        .fixedSize()
        .onHover { controlsHovered = $0 }
    }

    // MARK: - Pieces

    /// Full screen exists to make the timer the only thing on the display, so
    /// the ring takes as much of it as the visible controls allow, then grows
    /// again once the chrome fades out. A merely very large window gets the
    /// same treatment — the space is there either way.
    private func ringSize(for size: CGSize, compact: Bool) -> CGFloat {
        if fullScreen {
            // Deliberately independent of whether the controls are showing —
            // they float above rather than competing for the space.
            return max(300, min(min(size.width * 0.66, size.height * 0.88), 1250))
        }
        if size.width >= 1000 && size.height >= 760 {
            return max(300, min(min(size.width * 0.74, size.height * 0.62), 1100))
        }
        let candidate = min(size.width * 0.62, size.height * (compact ? 0.52 : 0.55))
        return max(150, min(candidate, 560))
    }

    private func background(pulse: Double) -> some View {
        ZStack {
            Palette.canvas
            RadialGradient(
                colors: [Color.white.opacity(0.055), .clear],
                center: .center, startRadius: 0, endRadius: 520
            )
            // The whole surface turns over on the beat.
            PulseImpact(pulse: pulse)
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
            Text("Lobalt")
                .font(Theme.label(15, weight: .semibold))
                .foregroundStyle(Palette.primaryText)

            Spacer()

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
            DispatchQueue.main.async {
                // Never pull the controls out from under the pointer.
                guard !controlsHovered, !quickFocused, !labelFocused else { return }
                chromeVisible = false
            }
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

    /// One line under the clock: where it lands, or how long it is set for.
    private var subtitle: String {
        if engine.phase == .running, !engine.isOvertime {
            return "ends \(TimeFormat.endsAt(engine.remaining))"
        }
        if engine.phase == .idle { return TimeFormat.humane(engine.plannedDuration) }
        return ""
    }

    var body: some View {
        let color = Theme.timeColor(remaining: engine.remaining, planned: engine.plannedDuration)
        let tinted = Theme.pulseDigitTint(color, pulse: pulse)

        ZStack {
            TimerRing(fraction: engine.ringFraction,
                      color: color,
                      pulse: pulse,
                      lineWidth: max(6, ringSize * 0.038),
                      idle: engine.phase == .idle,
                      reduceMotion: reduceMotion)
                .frame(width: ringSize, height: ringSize)

            // Every row is always present, hidden with opacity rather than
            // an `if`. A changing child list re-identifies the text field at
            // the bottom, which drops the name you were part-way through
            // typing the moment the timer starts or crosses into overtime.
            VStack(spacing: ringSize * 0.028) {
                StatusChip(text: app.statusText, color: app.statusColor,
                           size: max(9, ringSize * 0.032))
                    .opacity(engine.phase != .running || engine.isOvertime ? 1 : 0)

                Text(engine.displayTime)
                    .font(Theme.digits(ringSize * 0.255, weight: .semibold))
                    .foregroundStyle(tinted)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.easeOut(duration: 0.18), value: engine.displayTime)

                Text(subtitle)
                    .font(Theme.label(max(9, ringSize * 0.042)))
                    .foregroundStyle(Palette.tertiaryText)
                    .opacity(subtitle.isEmpty ? 0 : 1)

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

    @Environment(\.lobaltSnapshotMode) private var snapshotMode

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
    var pulse: Double = 0
    /// Multiplier on the control sizes. Full screen runs them large, and
    /// larger again while the pointer is over them.
    var scale: CGFloat = 1

    private var engine: TimerEngine { app.engine }
    private var primary: CGFloat { (compact ? 42 : 54) * scale }
    private var secondary: CGFloat { (compact ? 32 : 38) * scale }

    /// The primary control swells hardest; the rest just lean in.
    private let primaryGrowth = 0.26
    private let secondaryGrowth = 0.12

    var body: some View {
        HStack(spacing: (compact ? 10 : 14) * scale) {
            switch engine.phase {
            case .idle:
                VoiceButton(diameter: secondary, pulse: pulse, growth: secondaryGrowth)
                RoundIconButton(systemName: "play.fill", diameter: primary,
                                tint: Palette.calm, prominent: true,
                                pulse: pulse, growth: primaryGrowth,
                                help: "Start (Space)") {
                    app.start(seconds: Int(engine.plannedDuration), label: nil)
                }
                RoundIconButton(systemName: "minus", diameter: secondary,
                                tint: Palette.secondaryText, pulse: pulse, growth: secondaryGrowth,
                                help: "Five minutes less") {
                    app.engine.add(seconds: -300)
                }
                RoundIconButton(systemName: "plus", diameter: secondary,
                                tint: Palette.secondaryText, pulse: pulse, growth: secondaryGrowth,
                                help: "Five minutes more") {
                    app.engine.add(seconds: 300)
                }

            case .running, .paused:
                VoiceButton(diameter: secondary, pulse: pulse, growth: secondaryGrowth)
                RoundIconButton(systemName: engine.phase == .paused ? "play.fill" : "pause.fill",
                                diameter: primary,
                                tint: engine.phase == .paused ? Palette.calm : Palette.primaryText,
                                prominent: engine.phase == .paused,
                                pulse: pulse, growth: primaryGrowth,
                                help: engine.phase == .paused ? "Resume (Space)" : "Pause (Space)") {
                    app.toggle()
                }
                RoundIconButton(systemName: "goforward.5", diameter: secondary,
                                tint: Palette.secondaryText, pulse: pulse, growth: secondaryGrowth,
                                help: "Add five minutes") {
                    app.addMinutes(5)
                }
                RoundIconButton(systemName: "stop.fill", diameter: secondary,
                                tint: Palette.secondaryText, pulse: pulse, growth: secondaryGrowth,
                                help: "Stop (⌘.)") {
                    app.stop()
                }

            case .finished:
                RoundIconButton(systemName: "checkmark", diameter: primary,
                                tint: Palette.calm, prominent: true, pulse: pulse, growth: primaryGrowth,
                                help: "Done") {
                    app.engine.acknowledge()
                }
                RoundIconButton(systemName: "arrow.counterclockwise", diameter: secondary,
                                tint: Palette.secondaryText, pulse: pulse, growth: secondaryGrowth,
                                help: "Run it again (⌘R)") {
                    app.restart()
                }
                RoundIconButton(systemName: "goforward.5", diameter: secondary,
                                tint: Palette.secondaryText, pulse: pulse, growth: secondaryGrowth,
                                help: "Five more minutes") {
                    app.addMinutes(5)
                }
            }
        }
    }
}

private struct PresetRow: View {
    @Environment(AppState.self) private var app
    /// Focused by the "custom" chip, which is just a shortcut to typing.
    @FocusState.Binding var quickFocused: Bool
    var scale: CGFloat = 1

    var body: some View {
        HStack(spacing: 5 * scale) {
            ForEach(app.settings.presets, id: \.self) { minutes in
                chip(String(minutes), help: "Start a \(minutes) minute timer") {
                    app.startPreset(minutes: minutes)
                }
            }
            chip("custom", help: "Type any length, e.g. 7m or 1h30") {
                quickFocused = true
            }
        }
    }

    private func chip(_ text: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(Theme.digits(12.5 * scale, weight: .medium))
                .foregroundStyle(Palette.secondaryText)
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: 22 * scale)
                .padding(.horizontal, 5 * scale)
                .padding(.vertical, 6 * scale)
                .background(
                    RoundedRectangle(cornerRadius: 8 * scale, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Quick entry

private struct QuickEntryField: View {
    @Environment(AppState.self) private var app
    @FocusState.Binding var focused: Bool
    @Environment(\.lobaltSnapshotMode) private var snapshotMode

    private var text: String { app.draftEntry }

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
        @Bindable var app = app
        return HStack(spacing: 8) {
            Image(systemName: "text.cursor")
                .font(.system(size: 11))
                .foregroundStyle(Palette.tertiaryText)

            if snapshotMode {
                Text(text.isEmpty ? "name it, or 25m write the essay" : text)
                    .font(Theme.label(13))
                    .foregroundStyle(text.isEmpty ? Palette.tertiaryText : Palette.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField("name it, or 25m write the essay", text: $app.draftEntry)
                    .textFieldStyle(.plain)
                    .font(Theme.label(13))
                    .foregroundStyle(Palette.primaryText)
                    .focused($focused)
                    .onSubmit { app.submitQuickEntry() }
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
    var pulse: Double = 0
    var growth: Double = 0

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
                            pulse: pulse, growth: growth,
                            help: listening ? "Stop listening" : "Say a time limit (⌃⌥⌘V)") {
                app.toggleVoice()
            }
        }
        .animation(.easeOut(duration: 0.15), value: listening)
    }
}

/// Publishes the hosting `NSWindow` so the overlay can tell whether the timer
/// is already in front, and so "Open Lobalt" can bring it back.
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
