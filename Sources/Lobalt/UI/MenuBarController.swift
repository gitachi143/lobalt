import AppKit
import SwiftUI
import Observation
import LobaltKit

/// The always-there surface: a live countdown in the menu bar that reddens
/// along with everything else on the minute.
@MainActor
final class MenuBarController {

    private let statusItem: NSStatusItem
    private let app: AppState
    private let popover = NSPopover()
    private var observing = false

    init(app: AppState) {
        self.app = app
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: AnyView(MenuPanelView().environment(app))
        )

        refresh()
        observe()
    }

    // MARK: - Live updates

    /// Re-arms itself after every change, so the title tracks the engine's own
    /// tick rate — fast during a pulse, lazy the rest of the time.
    private func observe() {
        withObservationTracking {
            _ = app.engine.remaining
            _ = app.engine.phase
            _ = app.engine.lastPulseAt
            _ = app.engine.label
            _ = app.settings.pulseEnabled
        } onChange: {
            // `onChange` fires synchronously during the mutation, so the work
            // is deferred rather than done here.
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    self?.refresh()
                    self?.observe()
                }
            }
        }
    }

    private func refresh() {
        guard let button = statusItem.button else { return }
        let engine = app.engine
        let pulse = app.pulseNow()

        let symbol: String
        switch engine.phase {
        case .idle: symbol = "timer"
        case .running: symbol = engine.isOvertime ? "exclamationmark.circle" : "timer"
        case .paused: symbol = "pause.circle"
        case .finished: symbol = "bell.fill"
        }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Lobalt")
        button.image?.isTemplate = true

        let base: NSColor = {
            switch engine.phase {
            case .idle: return .labelColor
            case .paused: return NSColor(Palette.warn)
            case .finished: return NSColor(Palette.over)
            case .running:
                return engine.isOvertime
                    ? NSColor(Palette.over)
                    : NSColor(Theme.timeColor(remaining: engine.remaining, planned: engine.plannedDuration))
            }
        }()

        // Blend towards red for the duration of a pulse, then settle back.
        let tint = pulse > 0.01
            ? NSColor(Theme.pulseTint(Color(nsColor: base), pulse: pulse))
            : base
        // A running timer is easier to read in the menu bar's own colour until
        // it starts getting urgent; only then does it earn a tint.
        let useTint = pulse > 0.01 || engine.phase != .running
            || Theme.urgency(remaining: engine.remaining, planned: engine.plannedDuration) > 0.25
        button.contentTintColor = useTint ? tint : nil

        if engine.phase == .idle {
            button.attributedTitle = NSAttributedString(string: "")
            button.toolTip = "Lobalt — no timer running"
        } else {
            button.attributedTitle = NSAttributedString(
                string: " " + TimeFormat.compact(engine.remaining),
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                    .foregroundColor: useTint ? tint : NSColor.labelColor,
                ]
            )
            let name = engine.label.isEmpty ? "Timer" : engine.label
            button.toolTip = "\(name) — \(TimeFormat.clock(engine.remaining)) left"
        }
    }

    /// Exposed for `--selftest`.
    var debugTitle: String { statusItem.button?.attributedTitle.string ?? "" }

    // MARK: - Interaction

    @objc private func clicked(_ sender: Any?) {
        let rightClick = NSApp.currentEvent?.type == .rightMouseUp
            || NSApp.currentEvent?.modifierFlags.contains(.control) == true
        if rightClick {
            showMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func closePopover() { if popover.isShown { popover.performClose(nil) } }

    private func showMenu() {
        let menu = NSMenu()
        let engine = app.engine

        switch engine.phase {
        case .idle:
            menu.addItem(item("Start \(TimeFormat.humane(engine.plannedDuration))", #selector(menuToggle)))
        case .running:
            menu.addItem(item("Pause", #selector(menuToggle)))
            menu.addItem(item("Add 5 minutes", #selector(menuAddFive)))
            menu.addItem(item("Stop", #selector(menuStop)))
        case .paused:
            menu.addItem(item("Resume", #selector(menuToggle)))
            menu.addItem(item("Stop", #selector(menuStop)))
        case .finished:
            menu.addItem(item("Done", #selector(menuStop)))
            menu.addItem(item("Run it again", #selector(menuRestart)))
        }

        menu.addItem(.separator())
        menu.addItem(item("Speak a timer", #selector(menuVoice)))

        let presets = NSMenu()
        for minutes in app.settings.presets {
            let entry = NSMenuItem(title: "\(minutes) minutes", action: #selector(menuPreset(_:)), keyEquivalent: "")
            entry.target = self
            entry.tag = minutes
            presets.addItem(entry)
        }
        let presetItem = NSMenuItem(title: "Start", action: nil, keyEquivalent: "")
        presetItem.submenu = presets
        menu.addItem(presetItem)

        let recent = app.store.recentTasks()
        if !recent.isEmpty {
            let recentMenu = NSMenu()
            for task in recent {
                let entry = NSMenuItem(title: "\(task.label) · \(TimeFormat.humane(task.planned))",
                                       action: #selector(menuRepeat(_:)), keyEquivalent: "")
                entry.target = self
                entry.tag = Int(task.planned)
                entry.representedObject = task.label
                recentMenu.addItem(entry)
            }
            let recentItem = NSMenuItem(title: "Again", action: nil, keyEquivalent: "")
            recentItem.submenu = recentMenu
            menu.addItem(recentItem)
        }

        menu.addItem(.separator())
        menu.addItem(item("Open Lobalt", #selector(menuShow)))
        menu.addItem(item("Settings…", #selector(menuSettings)))
        menu.addItem(.separator())
        menu.addItem(item("Quit Lobalt", #selector(menuQuit)))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil           // restore click-to-popover behaviour
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        return i
    }

    @objc private func menuToggle() { app.toggle() }
    @objc private func menuStop() { app.stop() }
    @objc private func menuRestart() { app.restart() }
    @objc private func menuAddFive() { app.addMinutes(5) }
    @objc private func menuVoice() { app.toggleVoice() }
    @objc private func menuShow() { app.onShowMainWindow?() }
    @objc private func menuSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
    @objc private func menuQuit() { NSApp.terminate(nil) }
    @objc private func menuPreset(_ sender: NSMenuItem) { app.startPreset(minutes: sender.tag) }
    @objc private func menuRepeat(_ sender: NSMenuItem) {
        app.start(seconds: sender.tag, label: sender.representedObject as? String)
    }
}
