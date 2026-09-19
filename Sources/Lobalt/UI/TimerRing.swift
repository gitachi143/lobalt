import SwiftUI

/// The depleting progress ring, shared by the main window and the overlay.
struct TimerRing: View {
    var fraction: Double          // 0…1 of the circle to draw
    var color: Color
    var pulse: Double             // 0…1 current glow from the minute pulse
    var lineWidth: CGFloat
    var idle: Bool = false        // dim the arc when nothing is scheduled
    var reduceMotion: Bool = false

    private var tinted: Color { Theme.pulseTint(color, pulse: pulse) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Palette.track, lineWidth: lineWidth)

            // The glow sits behind the arc so the arc itself stays crisp.
            Circle()
                .stroke(Palette.pulse, lineWidth: lineWidth * 1.6)
                .blur(radius: lineWidth * 1.1)
                .opacity(pulse * 0.55)

            Circle()
                .trim(from: 0, to: max(0.0001, fraction))
                .stroke(
                    AngularGradient(
                        colors: [tinted.opacity(0.85), tinted],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .opacity(idle ? 0.35 : 1)
                .shadow(color: tinted.opacity(0.35 + pulse * 0.4), radius: lineWidth * (0.6 + pulse))
        }
        // A barely-there swell. Peripheral vision picks up the motion; you
        // don't notice it when you are looking straight at it.
        .scaleEffect(1 + (reduceMotion ? 0 : pulse * 0.012))
        .animation(.linear(duration: 0.22), value: fraction)
    }
}

/// Red bloom around the inside edge of a surface.
///
/// This is the part you catch out of the corner of your eye while working in
/// another app — no movement, no sound, just the frame warming up for a moment.
struct PulseBackdrop: View {
    var pulse: Double
    var cornerRadius: CGFloat
    var thickness: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [Palette.pulse.opacity(0.95), Palette.pulse.opacity(0.55)],
                    startPoint: .top, endPoint: .bottom
                ),
                lineWidth: thickness
            )
            .blur(radius: thickness * 0.8)
            .opacity(pulse)
            // Adds light rather than painting over — keeps the surface beneath
            // readable instead of turning it brown.
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
    }
}

/// Whole-window version of the pulse.
///
/// The entire surface turns over at once rather than just warming at the
/// edges — that is what makes the minute land as an impact instead of a
/// gradient. A hotter rim on top stops it reading as a flat colour swap.
struct PulseImpact: View {
    var pulse: Double

    var body: some View {
        GeometryReader { geo in
            let reach = max(geo.size.width, geo.size.height) * 0.80
            ZStack {
                Palette.impact.opacity(pulse * 0.80)
                RadialGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: 0.12),
                        .init(color: Palette.pulse.opacity(0.26), location: 0.60),
                        .init(color: Palette.pulse.opacity(0.72), location: 1.0),
                    ]),
                    center: .center,
                    startRadius: 0,
                    endRadius: reach
                )
                .opacity(pulse)
                .blendMode(.plusLighter)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Small state chip: "Paused", "Over", "Ready".
struct StatusChip: View {
    var text: String
    var color: Color
    var size: CGFloat = 11

    var body: some View {
        Text(text.uppercased())
            .font(Theme.label(size, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(color)
            .padding(.horizontal, size * 0.72)
            .padding(.vertical, size * 0.32)
            .background(
                Capsule().fill(color.opacity(0.14))
            )
            .overlay(Capsule().strokeBorder(color.opacity(0.25), lineWidth: 1))
    }
}

/// Circular icon button used across every surface.
struct RoundIconButton: View {
    var systemName: String
    var diameter: CGFloat
    var tint: Color = Palette.primaryText
    var fill: Color = Color.white.opacity(0.09)
    var prominent: Bool = false
    /// Current minute-pulse intensity, 0…1.
    var pulse: Double = 0
    /// How much the button swells at full pulse. 0 opts out entirely.
    var growth: Double = 0
    var help: String = ""
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if pulse > 0.01 {
                    // Bloom spilling out past the edge of the button.
                    Circle()
                        .fill(Palette.pulse)
                        .frame(width: diameter, height: diameter)
                        .blur(radius: diameter * 0.40)
                        .scaleEffect(1.55)
                        .opacity(pulse * 0.85)
                }

                Circle()
                    .fill(prominent ? tint.opacity(hovering ? 1 : 0.9) : fill.opacity(hovering ? 1.9 : 1))

                // Washes the face itself red. Layered rather than blended so
                // the translucency of the resting fill is preserved.
                Circle()
                    .fill(Palette.pulse)
                    .opacity(pulse * 0.62)

                Circle()
                    .strokeBorder(Palette.pulse.opacity(min(1, pulse * 1.3)),
                                  lineWidth: max(1, diameter * 0.045))

                Image(systemName: systemName)
                    .font(.system(size: diameter * 0.38, weight: .semibold))
                    .foregroundStyle(prominent ? Palette.canvas : tint)
            }
            .frame(width: diameter, height: diameter)
            .scaleEffect(1 + pulse * growth)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
