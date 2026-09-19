import SwiftUI
import AppKit
import PulseKit

@main
struct PulseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Pulse", id: "main") {
            MainView()
                .environment(delegate.state)
        }
        .defaultSize(width: 470, height: 600)
        .windowResizability(.contentMinSize)
        .commands { TimerCommands(state: delegate.state) }

        Window("History", id: "history") {
            HistoryView()
                .environment(delegate.state)
        }
        .defaultSize(width: 540, height: 480)

        Settings {
            SettingsView()
                .environment(delegate.state)
        }
    }
}

/// Menu-bar commands, which also give every in-app shortcut a discoverable home.
private struct TimerCommands: Commands {
    let state: AppState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}

        CommandMenu("Timer") {
            Button("Start / Pause") { state.toggle() }
                .keyboardShortcut(.return, modifiers: .command)
            Button("Speak a Timer") { state.toggleVoice() }
                .keyboardShortcut("d", modifiers: .command)
            Divider()
            Button("Add 5 Minutes") { state.addMinutes(5) }
                .keyboardShortcut("=", modifiers: [.command, .shift])
            Button("Run Again") { state.restart() }
                .keyboardShortcut("r", modifiers: .command)
            Button("Stop") { state.stop() }
                .keyboardShortcut(".", modifiers: .command)
            Divider()
            Menu("Quick Start") {
                ForEach(state.settings.presets, id: \.self) { minutes in
                    Button("\(minutes) minutes") { state.startPreset(minutes: minutes) }
                }
            }
        }
    }
}

// MARK: - Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {

    let state = AppState()
    private var menuBar: MenuBarController?
    private var overlay: OverlayController?
    private let hotKeys = HotKeyCenter()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let dir = Snapshot.requestedDirectory() {
            Snapshot.run(into: dir, state: state)
            NSApp.terminate(nil)
            return
        }
        if SelfTest.wasRequested {
            exit(Int32(SelfTest.run(state: state)))
        }
        NSApp.setActivationPolicy(state.settings.showDockIcon ? .regular : .accessory)

        // The menu bar item is always on screen, so the engine should always
        // run at a rate that can animate a pulse.
        state.engine.isDisplayActive = true

        menuBar = MenuBarController(app: state)
        overlay = OverlayController(app: state)

        state.onShowMainWindow = { [weak self] in self?.showMainWindow() }
        state.onFinished = { [weak self] in self?.overlay?.flashToFront() }

        installHotKeys()
        Notifier.requestAuthorization()

        let nc = NotificationCenter.default
        nc.addObserver(forName: .pulseHotKeysChanged, object: nil, queue: .main) { [weak self] _ in
            self?.installHotKeys()
        }
        nc.addObserver(forName: .pulseOverlayLayoutChanged, object: nil, queue: .main) { [weak self] _ in
            self?.overlay?.anchor()
        }
        // A timer that ran while the lid was shut should read correctly the
        // instant the screen comes back.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.state.engine.refresh()
            self?.overlay?.update()
        }

        DispatchQueue.main.async { self.overlay?.update() }
    }

    private func installHotKeys() {
        guard state.settings.hotkeysEnabled else { hotKeys.uninstall(); return }
        hotKeys.install([
            .toggleTimer: { [weak self] in self?.state.toggle() },
            .voice: { [weak self] in self?.state.toggleVoice() },
            .showWindow: { [weak self] in self?.showMainWindow() },
        ])
    }

    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = WindowRegistry.shared.mainWindow {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            // The window was closed outright; ask SwiftUI to build a new one.
            NSApp.sendAction(Selector(("newWindowForTab:")), to: nil, from: nil)
            if WindowRegistry.shared.mainWindow == nil {
                NSApp.windows.first(where: { $0.identifier?.rawValue.contains("main") == true })?
                    .makeKeyAndOrderFront(nil)
            }
        }
    }

    // Clicking the Dock icon with no window open should bring the timer back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeys.uninstall()
    }
}
