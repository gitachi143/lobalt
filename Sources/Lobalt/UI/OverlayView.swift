import SwiftUI
import LobaltKit

/// The corner pill: what you see while you're working in something else.
///
/// Collapsed it is a ring, a time, and a task name. Hovering reveals controls
/// so you never have to leave the app you're in to add five minutes.
struct OverlayView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    private var engine: TimerEngine { app.engine }
    private var scale: CGFloat { CGFloat(app.settings.overlayScale) }

    private var expanded: Bool { hovering || app.speech.isListening }

    var body: some View {
        let pulse = app.pulseNow()
        let color = Theme.timeColor(remaining: engine.remaining, planned: engine.plannedDuration)
        let tinted = Theme.pulseDigitTint(color, pulse: pulse)

        VStack(alignment: .leading, spacing: 0) {
            topRow(color: color, tinted: tinted, pulse: pulse)

            if expanded {
                controls
                    .padding(.top, 8 * scale)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if app.speech.isListening || app.speech.previewText != nil {
                voiceLine
                    .padding(.top, 6 * scale)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 12 * scale)
        .padding(.vertical, 9 * scale)
        .background(surface(pulse: pulse))
        .overlay(
            RoundedRectangle(cornerRadius: 14 * scale, style: .continuous)
                .strokeBorder(
                    Color.white.opacity(0.10).blended(with: Palette.pulse, amount: pulse * 0.8),
                    lineWidth: 1
                )
        )
        .overlay(PulseBackdrop(pulse: pulse * 0.85, cornerRadius: 14 * scale, thickness: 14 * scale))
        .clipShape(RoundedRectangle(cornerRadius: 14 * scale, style: .continuous))
        .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
        .shadow(color: Palette.pulse.opacity(pulse * 0.5), radius: 18)
        .scaleEffect(1 + (reduceMotion ? 0 : pulse * 0.02))
        .padding(10)                                  // room for the shadow
        .fixedSize()
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: expanded)
        .preferredColorScheme(.dark)
    }

    // MARK: - Rows

    private func topRow(color: Color, tinted: Color, pulse: Double) -> some View {
        HStack(spacing: 9 * scale) {
            ZStack {
                TimerRing(fraction: engine.ringFraction, color: color, pulse: pulse,
                          lineWidth: 2.5 * scale, idle: engine.phase == .idle,
                          reduceMotion: reduceMotion)
                    .frame(width: 18 * scale, height: 18 * scale)
                if engine.phase == .paused {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 6 * scale, weight: .bold))
                        .foregroundStyle(Palette.warn)
                }
            }

            Text(engine.displayTime)
                .font(Theme.digits(15 * scale, weight: .semibold))
                .foregroundStyle(tinted)
                .contentTransition(.numericText(countsDown: true))

            if !engine.label.isEmpty {
                Text(engine.label)
                    .font(Theme.label(11 * scale))
                    .foregroundStyle(Palette.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 140 * scale, alignment: .leading)
            } else if engine.phase == .idle {
                Text("Lobalt")
                    .font(Theme.label(11 * scale))
                    .foregroundStyle(Palette.tertiaryText)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 6 * scale) {
            switch engine.phase {
            case .idle:
                pill("play.fill", "Start") { app.start(seconds: Int(engine.plannedDuration), label: nil) }
            case .running, .paused:
                pill(engine.phase == .paused ? "play.fill" : "pause.fill",
                     engine.phase == .paused ? "Resume" : "Pause") { app.toggle() }
                pill("goforward.5", "Add five minutes") { app.addMinutes(5) }
                pill("stop.fill", "Stop") { app.stop() }
            case .finished:
                pill("checkmark", "Done") { app.engine.acknowledge() }
                pill("arrow.counterclockwise", "Again") { app.restart() }
            }

            pill(app.speech.isListening ? "waveform" : "mic.fill",
                 "Say a time limit",
                 tint: app.speech.isListening ? Palette.urgent : Palette.secondaryText) {
                app.toggleVoice()
            }

            pill("macwindow", "Open Lobalt") { app.onShowMainWindow?() }
        }
    }

    private var voiceLine: some View {
        HStack(spacing: 5 * scale) {
            if app.speech.isListening { ListeningDots() }
            Text(app.speech.previewText ?? (app.speech.transcript.isEmpty ? "Listening…" : app.speech.transcript))
                .font(Theme.label(10 * scale))
                .foregroundStyle(app.speech.previewText != nil ? Palette.calm : Palette.secondaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: 190 * scale, alignment: .leading)
    }

    private func pill(_ icon: String, _ help: String,
                      tint: Color = Palette.secondaryText,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 9.5 * scale, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22 * scale, height: 18 * scale)
                .background(
                    RoundedRectangle(cornerRadius: 6 * scale, style: .continuous)
                        .fill(Color.white.opacity(0.09))
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func surface(pulse: Double) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14 * scale, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 14 * scale, style: .continuous)
                .fill(Palette.canvas.opacity(0.72))
            RoundedRectangle(cornerRadius: 14 * scale, style: .continuous)
                .fill(Palette.pulse.opacity(pulse * 0.22))
        }
    }
}
