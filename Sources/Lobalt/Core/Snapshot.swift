import SwiftUI
import AppKit
import LobaltKit

/// Renders the app's surfaces to PNGs without needing a display or any screen
/// recording permission. Invoked with `Lobalt --snapshot <directory>`; used to
/// review layout and the pulse treatment while developing.
@MainActor
enum Snapshot {

    static func requestedDirectory() -> String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// An `AppState` backed by in-memory preferences and a throwaway session
    /// log, so the tooling never reads or writes the real ones.
    ///
    /// A named `UserDefaults` suite isn't good enough here: the process writes
    /// it back out as it exits, leaving a plist behind on every run.
    static func scratchState() -> AppState {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lobalt-scratch-\(UUID().uuidString).json")
        return AppState(defaults: MemorySettingsStore(), storeURL: url)
    }

    static func run(into directory: String, state: AppState) {
        let dir = URL(fileURLWithPath: directory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let engine = state.engine

        // Seed a plausible day so the footer stats read like real use rather
        // than a fresh install. Written to a throwaway store, not the real one.
        if state.store.sessions.isEmpty {
            let now = Date()
            let sample: [(String, Double, Double, Bool)] = [
                ("Inbox and triage", 900, 870, true),
                ("Write the launch post", 1500, 1730, true),
                ("Untitled", 300, 4, false),          // thought better of it
                ("Review the parser PR", 1800, 1680, true),
                ("Standup notes", 600, 640, true),
            ]
            var offset: TimeInterval = -5 * 3600
            for (label, planned, actual, done) in sample {
                let start = now.addingTimeInterval(offset)
                state.store.add(Session(label: label, planned: planned, actual: actual,
                                        startedAt: start, endedAt: start.addingTimeInterval(actual),
                                        completed: done))
                offset += actual + 900
            }
        }

        // 1 — the log that sits under the timer, before this run's own
        // throwaway timers land in it
        write(HistorySection().environment(state).frame(width: 470).background(Palette.canvas),
              dir, "history")

        // 2 — idle
        engine.stop()
        engine.preset(seconds: 25 * 60)
        write(MainView().environment(state).frame(width: 470, height: 600), dir, "main-idle")

        // 3 — running, part-way through, caught mid-pulse
        engine.start(seconds: 25 * 60, label: "Write the launch post")
        engine.triggerPulse(strength: 0.75)
        holdUntilPeak()
        write(MainView().environment(state).frame(width: 470, height: 600), dir, "main-pulse")

        // 4 — the same moment in the corner overlay
        write(OverlayView().environment(state), dir, "overlay-pulse")

        // 5 — overlay at rest
        engine.start(seconds: 25 * 60, label: "Write the launch post")
        write(OverlayView().environment(state), dir, "overlay-calm")

        // 6 — the full-screen layout, caught on the beat
        func fullScreen(hovering: Bool) -> some View {
            MainView()
                .environment(state)
                .environment(\.lobaltSnapshotFullScreen, true)
                .environment(\.lobaltSnapshotHoverControls, hovering)
                .frame(width: 1440, height: 900)
        }

        engine.start(seconds: 25 * 60, label: "Write the launch post")
        engine.triggerPulse(strength: 1.0)
        holdUntilPeak()
        write(fullScreen(hovering: false), dir, "fullscreen-pulse")

        engine.start(seconds: 25 * 60, label: "Write the launch post")
        write(fullScreen(hovering: false), dir, "fullscreen-calm")
        write(fullScreen(hovering: true), dir, "fullscreen-hover")

        engine.stop()
        engine.preset(seconds: 25 * 60)
        write(fullScreen(hovering: true), dir, "fullscreen-idle-hover")

        // 7 — menu bar popover
        write(MenuPanelView().environment(state), dir, "menu-panel")

        // 8 — past the estimate
        engine.start(seconds: 1, label: "Review the PR")
        Thread.sleep(forTimeInterval: 1.4)
        engine.refresh()
        engine.triggerPulse(strength: 1.0)
        holdUntilPeak()
        write(MainView().environment(state).frame(width: 470, height: 600), dir, "main-overtime")
        write(OverlayView().environment(state), dir, "overlay-overtime")

        print("snapshots written to \(dir.path)")
    }

    /// The glow ramps up over `PulseEnvelope.attack`; rendering any earlier
    /// captures the pulse before it has visibly started.
    private static func holdUntilPeak() {
        Thread.sleep(forTimeInterval: PulseEnvelope.attack)
    }

    private static func write(_ view: some View, _ dir: URL, _ name: String) {
        let renderer = ImageRenderer(content: view
            .environment(\.lobaltSnapshotMode, true)
            .preferredColorScheme(.dark))
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            print("failed to render \(name)")
            return
        }
        try? png.write(to: dir.appendingPathComponent("\(name).png"))
    }
}
