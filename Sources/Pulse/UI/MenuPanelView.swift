import SwiftUI
import PulseKit

/// The popover behind the menu bar item — a full set of controls without
/// having to open the window.
struct MenuPanelView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var quickEntry = ""
    @FocusState private var quickFocused: Bool

    private var engine: TimerEngine { app.engine }

    var body: some View {
        let pulse = app.pulseNow()
        let color = Theme.timeColor(remaining: engine.remaining, planned: engine.plannedDuration)

        VStack(spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    TimerRing(fraction: engine.ringFraction, color: color, pulse: pulse,
                              lineWidth: 4, idle: engine.phase == .idle, reduceMotion: reduceMotion)
                        .frame(width: 54, height: 54)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(engine.displayTime)
                        .font(Theme.digits(26, weight: .semibold))
                        .foregroundStyle(Theme.pulseTint(color, pulse: pulse))
                        .contentTransition(.numericText(countsDown: true))
                    Text(engine.label.isEmpty ? app.statusText : engine.label)
                        .font(Theme.label(11))
                        .foregroundStyle(Palette.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                switch engine.phase {
                case .idle:
                    action("play.fill", "Start", prominent: true) {
                        app.start(seconds: Int(engine.plannedDuration), label: nil)
                    }
                case .running, .paused:
                    action(engine.phase == .paused ? "play.fill" : "pause.fill",
                           engine.phase == .paused ? "Resume" : "Pause",
                           prominent: engine.phase == .paused) { app.toggle() }
                    action("goforward.5", "+5") { app.addMinutes(5) }
                    action("stop.fill", "Stop") { app.stop() }
                case .finished:
                    action("checkmark", "Done", prominent: true) { app.engine.acknowledge() }
                    action("arrow.counterclockwise", "Again") { app.restart() }
                }
                action(app.speech.isListening ? "waveform" : "mic.fill", "Speak",
                       tint: app.speech.isListening ? Palette.urgent : Palette.primaryText) {
                    app.toggleVoice()
                }
            }

            if app.speech.isListening || app.speech.previewText != nil {
                HStack(spacing: 6) {
                    if app.speech.isListening { ListeningDots() }
                    Text(app.speech.previewText
                         ?? (app.speech.transcript.isEmpty ? "Listening…" : app.speech.transcript))
                        .font(Theme.label(11))
                        .foregroundStyle(app.speech.previewText != nil ? Palette.calm : Palette.secondaryText)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }

            TextField("25m write the essay", text: $quickEntry)
                .textFieldStyle(.roundedBorder)
                .font(Theme.label(12))
                .focused($quickFocused)
                .onSubmit {
                    app.submitQuickEntry(quickEntry)
                    quickEntry = ""
                }

            HStack(spacing: 6) {
                ForEach(app.settings.presets, id: \.self) { minutes in
                    Button("\(minutes)") { app.startPreset(minutes: minutes) }
                        .buttonStyle(.plain)
                        .font(Theme.digits(11, weight: .medium))
                        .foregroundStyle(Palette.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
                }
            }

            Divider().overlay(Palette.hairline)

            HStack {
                let today = app.store.today
                Text("\(today.count) today · \(TimeFormat.humane(today.totalTime))")
                    .font(Theme.label(10))
                    .foregroundStyle(Palette.tertiaryText)
                Spacer()
                Button("Open") { app.onShowMainWindow?() }
                    .buttonStyle(.link).font(Theme.label(11))
            }
        }
        .padding(16)
        .frame(width: 320)
        .background(Palette.canvas)
        .preferredColorScheme(.dark)
    }

    private func action(_ icon: String, _ title: String, prominent: Bool = false,
                        tint: Color = Palette.primaryText,
                        run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(Theme.label(11, weight: .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(prominent ? Palette.canvas : tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(prominent ? Palette.calm : Color.white.opacity(0.09))
            )
        }
        .buttonStyle(.plain)
    }
}
