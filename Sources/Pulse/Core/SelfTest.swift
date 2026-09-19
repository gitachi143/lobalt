import AppKit
import SwiftUI
import PulseKit
import Speech

/// Developer smoke test: `Pulse --selftest`.
///
/// Exercises the parts that only exist at runtime — the floating panel's
/// auto-sizing and placement, the menu bar item, the engine's ticking — and
/// exits non-zero if anything is off. Static rendering can't catch these.
@MainActor
enum SelfTest {

    static var wasRequested: Bool { CommandLine.arguments.contains("--selftest") }

    private static var failures = 0

    private static func check(_ name: String, _ condition: Bool, _ detail: String = "") {
        if condition {
            print("  ok    \(name)")
        } else {
            failures += 1
            print("  FAIL  \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        }
    }

    private static func spin(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    static func run(state: AppState) -> Int {
        failures = 0
        print("Pulse self-test")

        // --- Engine ------------------------------------------------------
        print("engine")
        state.engine.isDisplayActive = true
        state.start(seconds: 300, label: "Self test")
        check("starts running", state.engine.phase == .running)
        let before = state.engine.remaining
        spin(1.1)
        let after = state.engine.remaining
        check("counts down", after < before - 0.8, "moved \(String(format: "%.2f", before - after))s")

        state.engine.pause()
        let held = state.engine.remaining
        spin(0.4)
        check("pause freezes the clock", abs(state.engine.remaining - held) < 0.01)
        state.engine.resume()
        check("resumes", state.engine.phase == .running)

        state.engine.add(seconds: 60)
        check("add extends", state.engine.remaining > held + 55)

        // --- Pulse -------------------------------------------------------
        print("pulse")
        state.engine.triggerPulse(strength: 0.8)
        spin(PulseEnvelope.attack)
        let peak = state.pulseNow()
        check("glows at peak", peak > 0.3, "intensity \(String(format: "%.2f", peak))")
        spin(PulseEnvelope.duration)
        check("cools back to nothing", state.pulseNow() < 0.02)

        // --- Overtime ----------------------------------------------------
        print("overtime")
        state.engine.start(seconds: 1, label: "Overtime")
        spin(1.6)
        check("crosses into overtime", state.engine.isOvertime)
        check("shows a + time", state.engine.displayTime.hasPrefix("+"), state.engine.displayTime)
        check("ring tracks overrun", state.engine.ringFraction > 0)

        // --- Overlay panel -----------------------------------------------
        print("overlay")
        let overlay = OverlayController(app: state)
        state.engine.start(seconds: 600, label: "Overlay check")
        overlay.update()
        spin(0.6)
        let panel = overlay.debugPanel
        check("panel is on screen", panel.isVisible)
        check("panel sized itself", panel.frame.width > 80 && panel.frame.height > 24,
              "\(Int(panel.frame.width))×\(Int(panel.frame.height))")
        check("panel floats above normal windows", panel.level.rawValue > NSWindow.Level.normal.rawValue)
        check("panel joins every space", panel.collectionBehavior.contains(.canJoinAllSpaces))
        check("panel survives other apps' full screen",
              panel.collectionBehavior.contains(.fullScreenAuxiliary))
        check("panel never steals focus", panel.styleMask.contains(.nonactivatingPanel))

        if let screen = NSScreen.main {
            let v = screen.visibleFrame
            let f = panel.frame
            check("sits inside the visible screen area",
                  f.maxX <= v.maxX + 12 && f.minX >= v.minX - 12
                  && f.maxY <= v.maxY + 12 && f.minY >= v.minY - 12,
                  "panel \(rect(f)) vs screen \(rect(v))")
            check("anchors to the top right by default",
                  abs(f.maxX - v.maxX) < 24 && abs(f.maxY - v.maxY) < 24,
                  "offset x \(Int(v.maxX - f.maxX)), y \(Int(v.maxY - f.maxY))")
        }

        state.engine.stop()
        overlay.update()
        spin(0.5)
        check("hides once nothing is timing", !panel.isVisible)

        // --- Window lifecycle --------------------------------------------
        print("window")
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 400, height: 400),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        WindowRegistry.shared.adopt(window)
        window.makeKeyAndOrderFront(nil)
        spin(0.3)
        check("registry holds the window", WindowRegistry.shared.mainWindow === window)

        // Park it far off every display and confirm it gets rescued.
        window.setFrameOrigin(CGPoint(x: -4000, y: -4000))
        WindowRegistry.moveOnScreenIfNeeded(window)
        if let screen = NSScreen.main {
            let overlap = screen.visibleFrame.intersection(window.frame)
            check("an off-screen window is pulled back into view",
                  overlap.width >= 160 && overlap.height >= 80,
                  "frame \(rect(window.frame))")
        }

        window.performClose(nil)
        spin(0.3)
        check("window survives being closed", WindowRegistry.shared.mainWindow === window)
        check("window is off screen after close", !window.isVisible)
        window.makeKeyAndOrderFront(nil)
        spin(0.3)
        check("reopens on demand", window.isVisible)
        window.orderOut(nil)

        // --- Menu bar ----------------------------------------------------
        print("menu bar")
        let menuBar = MenuBarController(app: state)
        spin(0.3)
        check("idle shows just the icon", menuBar.debugTitle.trimmingCharacters(in: .whitespaces).isEmpty)
        state.start(seconds: 754, label: "Menu bar check")
        spin(0.6)
        check("running shows the countdown", menuBar.debugTitle.contains("12:"),
              "title “\(menuBar.debugTitle)”")

        // --- Speech ------------------------------------------------------
        // Deliberately does not open the microphone: that would fire a
        // permission prompt. This only confirms the machine can do the work.
        print("speech")
        let recognizer = SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        check("a recogniser exists for this locale", recognizer != nil)
        check("recogniser is available", recognizer?.isAvailable == true)
        if let recognizer {
            print("  note  on-device recognition: \(recognizer.supportsOnDeviceRecognition ? "supported" : "server-side only")")
        }
        check("speech starts out idle", state.speech.state == .idle)

        // --- Parsing through the app -------------------------------------
        print("commands")
        state.submitQuickEntry("45m review the deck")
        check("typed command sets the duration", Int(state.engine.plannedDuration) == 2700,
              "\(Int(state.engine.plannedDuration))s")
        check("typed command sets the label", state.engine.label == "Review the deck",
              "“\(state.engine.label)”")
        state.submitQuickEntry("pause")
        check("typed transport command works", state.engine.phase == .paused)

        state.engine.stop()
        print(failures == 0 ? "\nall checks passed" : "\n\(failures) check(s) failed")
        return failures
    }

    private static func rect(_ r: CGRect) -> String {
        "(\(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))×\(Int(r.height)))"
    }
}

