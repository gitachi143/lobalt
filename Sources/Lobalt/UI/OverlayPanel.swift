import AppKit
import SwiftUI
import LobaltKit

/// Shared handle on the main timer window so the overlay can tell whether you
/// are already looking at the timer, and so "Open Lobalt" always has something
/// to bring back.
final class WindowRegistry {
    static let shared = WindowRegistry()
    var mainWindow: NSWindow?

    /// Held strongly, with release-on-close switched off, so closing the
    /// window only hides it. Reopening is then an order-front away and the
    /// view keeps running — the timer carries on either way.
    func adopt(_ window: NSWindow) {
        guard mainWindow !== window else { return }
        window.isReleasedWhenClosed = false
        mainWindow = window
        Self.moveOnScreenIfNeeded(window)
    }

    /// Drags the window back onto a display if it has ended up outside every
    /// one of them.
    ///
    /// Restoring a saved frame after a display change, or a cascade from an
    /// odd origin, can put it somewhere unreachable — and an app that opens
    /// with nothing visible looks broken rather than misplaced.
    static func moveOnScreenIfNeeded(_ window: NSWindow) {
        let frame = window.frame
        // A sliver poking onto a display isn't enough to grab hold of.
        let reachable = NSScreen.screens.contains { screen in
            let overlap = screen.visibleFrame.intersection(frame)
            return overlap.width >= 160 && overlap.height >= 80
        }
        guard !reachable, let screen = NSScreen.main ?? NSScreen.screens.first else { return }

        let visible = screen.visibleFrame
        let size = CGSize(width: min(frame.width, visible.width),
                          height: min(frame.height, visible.height))
        window.setFrame(CGRect(x: visible.midX - size.width / 2,
                               y: visible.midY - size.height / 2,
                               width: size.width,
                               height: size.height),
                        display: true)
    }

    /// True when the user can already see the big timer, which is the only
    /// time the corner pill is redundant.
    ///
    /// Deliberately not a key-window check: the overlay is itself a panel that
    /// can take key, so asking "is the main window key" leaves the pill stuck
    /// on screen after you click it and then come back. `isOnActiveSpace`
    /// covers the case where the window is open but parked on another desktop.
    var isMainWindowFront: Bool {
        guard NSApp.isActive,
              let w = mainWindow,
              w.isVisible,
              !w.isMiniaturized,
              w.isOnActiveSpace
        else { return false }
        return true
    }
}

/// Borderless, non-activating, floats above everything — including other
/// apps' full-screen spaces — and never takes focus away from your work.
final class OverlayPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 220, height: 60),
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false                 // SwiftUI paints its own, softer shadow
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        animationBehavior = .none
        alphaValue = 0
    }

    // Borderless panels refuse key status by default, which would stop the
    // buttons inside from responding.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Decides when the overlay is on screen and where it sits.
final class OverlayController {

    private let panel = OverlayPanel()
    private let app: AppState
    private var hosting: NSHostingController<AnyView>!

    private var shown = false
    private var movingProgrammatically = false
    private var poll: Timer?

    init(app: AppState) {
        self.app = app

        hosting = NSHostingController(rootView: AnyView(
            OverlayView().environment(app)
        ))
        hosting.sizingOptions = [.preferredContentSize]
        panel.contentViewController = hosting

        let nc = NotificationCenter.default
        for name: NSNotification.Name in [
            NSApplication.didBecomeActiveNotification,
            NSApplication.didResignActiveNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
            NSWindow.willCloseNotification,
        ] {
            nc.addObserver(self, selector: #selector(stateChanged), name: name, object: nil)
        }
        nc.addObserver(self, selector: #selector(panelMoved),
                       name: NSWindow.didMoveNotification, object: panel)
        nc.addObserver(self, selector: #selector(panelResized),
                       name: NSWindow.didResizeNotification, object: panel)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(stateChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

        // Window-state notifications miss a few edge cases (space swipes while
        // full screen, in particular), so a cheap poll keeps things honest.
        poll = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            self?.update()
        }
        poll?.tolerance = 0.25
    }

    @objc private func stateChanged() {
        DispatchQueue.main.async { [weak self] in self?.update() }
    }

    // MARK: - Visibility

    private var shouldShow: Bool {
        let s = app.settings
        guard s.overlayMode != .never else { return false }
        if WindowRegistry.shared.isMainWindowFront { return false }
        switch s.overlayMode {
        case .always: return true
        case .whileTiming: return app.engine.isActive || app.engine.phase == .finished
        case .never: return false
        }
    }

    func update() {
        setVisible(shouldShow)
        // Only burn frames on the pulse animation when something can see it.
        app.engine.isDisplayActive = shown || WindowRegistry.shared.isMainWindowFront
    }

    /// Bring the overlay up immediately, e.g. the moment a timer finishes.
    func flashToFront() {
        guard app.settings.overlayMode != .never else { return }
        setVisible(true)
        panel.orderFrontRegardless()
    }

    private func setVisible(_ visible: Bool) {
        guard visible != shown else { return }
        shown = visible
        if visible {
            anchor()
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                panel.animator().alphaValue = 1
            }
        } else {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.16
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak self, panel] in
                // The panel is captured strongly on purpose: if the controller
                // has been torn down mid-fade, the overlay must still leave the
                // screen rather than sitting there at zero alpha forever.
                guard self?.shown != true else { return }
                panel.orderOut(nil)
            })
        }
    }

    // MARK: - Placement

    @objc private func panelResized() {
        guard shown else { return }
        anchor()          // keep the top edge pinned as hover expands the pill
    }

    @objc private func panelMoved() {
        guard !movingProgrammatically, shown else { return }
        // Remember where they put it, anchored by the top-left corner so the
        // pill grows downward rather than drifting when it expands.
        let f = panel.frame
        app.settings.overlayOrigin = CGPoint(x: f.minX, y: f.maxY)
    }

    private func targetScreen() -> NSScreen? {
        if let saved = app.settings.overlayOrigin {
            if let match = NSScreen.screens.first(where: { $0.frame.contains(saved) }) { return match }
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    func anchor() {
        guard let screen = targetScreen() else { return }
        let size = panel.frame.size
        let visible = screen.visibleFrame
        let margin: CGFloat = 2        // the pill itself already insets 10pt

        var origin: CGPoint
        if let saved = app.settings.overlayOrigin {
            origin = CGPoint(x: saved.x, y: saved.y - size.height)
        } else {
            switch app.settings.overlayCorner {
            case .topRight:
                origin = CGPoint(x: visible.maxX - size.width - margin,
                                 y: visible.maxY - size.height - margin)
            case .topLeft:
                origin = CGPoint(x: visible.minX + margin,
                                 y: visible.maxY - size.height - margin)
            case .bottomRight:
                origin = CGPoint(x: visible.maxX - size.width - margin,
                                 y: visible.minY + margin)
            case .bottomLeft:
                origin = CGPoint(x: visible.minX + margin, y: visible.minY + margin)
            }
        }

        // Never let it wander off the edge of a display.
        origin.x = min(max(origin.x, visible.minX - 8), visible.maxX - size.width + 8)
        origin.y = min(max(origin.y, visible.minY - 8), visible.maxY - size.height + 8)

        movingProgrammatically = true
        panel.setFrameOrigin(origin)
        movingProgrammatically = false
    }

    /// Exposed for `--selftest`, which inspects the real panel's geometry.
    var debugPanel: OverlayPanel { panel }

    deinit {
        poll?.invalidate()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}

