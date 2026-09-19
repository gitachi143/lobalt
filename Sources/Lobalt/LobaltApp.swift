import SwiftUI
import AppKit
import LobaltKit

@main
struct LobaltApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Lobalt", id: "main") {
            MainView()
                .environment(delegate.state)
        }
        .defaultSize(width: 470, height: 600)
        .windowResizability(.contentMinSize)
        .commands { TimerCommands(state: delegate.state) }

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
        // Both developer flags run against scratch state, never the real
        // preferences or session history.
        if let dir = Snapshot.requestedDirectory() {
            Snapshot.run(into: dir, state: Snapshot.scratchState())
            NSApp.terminate(nil)
            return
        }
        if SelfTest.wasRequested {
            exit(Int32(SelfTest.run(state: Snapshot.scratchState())))
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
        claimURLEvents()
        Notifier.requestAuthorization()

        let nc = NotificationCenter.default
        nc.addObserver(forName: .lobaltHotKeysChanged, object: nil, queue: .main) { [weak self] _ in
            self?.installHotKeys()
        }
        nc.addObserver(forName: .lobaltOverlayLayoutChanged, object: nil, queue: .main) { [weak self] _ in
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
        // The window is kept alive through a close, so this always has a
        // target — see `WindowRegistry.adopt`.
        guard let window = WindowRegistry.shared.mainWindow else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        WindowRegistry.moveOnScreenIfNeeded(window)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - URL scheme

    /// `lobalt://` links, so timers can be driven from Shortcuts, Raycast, a
    /// shell script or another app:
    ///
    ///     open "lobalt://start?q=25m%20write%20the%20essay"
    ///     open "lobalt://add?m=5"
    ///     open "lobalt://pause"
    ///
    /// Deliberately limited to timer transport. Any web page can fire a URL
    /// scheme, so there is no action here that opens the microphone or writes
    /// to disk.
    ///
    /// Claimed as a raw Apple Event rather than through
    /// `application(_:open:)`. Routing it the usual way lets SwiftUI see it as
    /// an external event, and a `Window` scene responds to those by closing
    /// itself — so a link would dismiss the timer window as a side effect.
    /// Installing this handler last means SwiftUI never receives the event.
    private func claimURLEvents() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor,
                                      withReplyEvent reply: NSAppleEventDescriptor) {
        guard let text = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: text), url.scheme == "lobalt" else { return }
        handle(url)
    }

    private func handle(_ url: URL) {
        // Both lobalt://start and lobalt:///start reach here as one or the other.
        let action = (url.host?.isEmpty == false ? url.host! : url.lastPathComponent).lowercased()
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }

        switch action {
        case "start":
            // Accepts anything the quick-entry field accepts.
            if let q = value("q") ?? value("t"), !q.isEmpty {
                state.draftEntry = q
                state.submitQuickEntry()
            } else if let m = value("m").flatMap(Int.init) {
                state.startPreset(minutes: m)
            } else {
                state.start(seconds: Int(state.engine.plannedDuration), label: nil)
            }
        case "add":
            state.addMinutes(value("m").flatMap(Int.init) ?? 5)
        case "pause": state.engine.pause()
        case "resume": state.engine.resume()
        case "toggle": state.toggle()
        case "stop": state.stop()
        case "restart": state.restart()
        case "show": showMainWindow()
        default: break
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
