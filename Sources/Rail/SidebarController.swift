import AppKit
import SwiftUI

/// Borderless panel that never activates Rail, so the app you were in keeps keyboard focus.
private final class SidebarPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor @Observable
final class SidebarModel {
    enum Phase {
        case hidden
        /// A sliver of glass at the screen edge while the pointer dwells there.
        case peeking
        case shown
    }

    var phase: Phase = .hidden
}

enum SidebarMetrics {
    static let width: CGFloat = 300
    /// Same as a standard window corner.
    static let cornerRadius: CGFloat = 16
    static let peekWidth: CGFloat = 5
}

@MainActor
final class SidebarController {
    private let store: WindowStore
    private let model = SidebarModel()
    private let panel: SidebarPanel
    /// Keeps the panel out while a dialog is up, since the pointer travels to the dialog.
    private var isHeldOpen = false
    var isPinnedForPreview = false
    private var hideTimer: Timer?

    /// How far the pointer may stray past the card before it starts to hide.
    private let slack: CGFloat = 24

    init(store: WindowStore) {
        self.store = store
        panel = SidebarPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // The card draws its own shadow; a window shadow would not follow the spring.
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false

        let hosting = NSHostingView(rootView: SidebarView(store: store, model: model, actions: makeActions()))
        hosting.sizingOptions = []
        panel.contentView = hosting
    }

    // MARK: Presentation

    func peek(on screen: NSScreen) {
        guard model.phase == .hidden else { return }
        place(on: screen)
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()
        transition(to: .peeking)
    }

    func cancelPeek() {
        guard model.phase == .peeking else { return }
        transition(to: .hidden)
    }

    func show(on screen: NSScreen) {
        store.refresh()
        hideTimer?.invalidate()
        hideTimer = nil
        if model.phase == .hidden || panel.screen != screen { place(on: screen) }
        panel.ignoresMouseEvents = false
        panel.orderFrontRegardless()
        transition(to: .shown)
    }

    func hide() {
        guard model.phase != .hidden, !isPinnedForPreview else { return }
        hideTimer?.invalidate()
        hideTimer = nil
        panel.ignoresMouseEvents = true
        transition(to: .hidden)
    }

    /// Hides the panel once the pointer has left the card for a moment.
    func mouseMoved(to point: NSPoint) {
        guard model.phase == .shown, !isHeldOpen else { return }
        if cardFrame.insetBy(dx: -slack, dy: -slack).contains(point) || point.x <= cardFrame.minX {
            hideTimer?.invalidate()
            hideTimer = nil
        } else if hideTimer == nil {
            hideTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.hide() }
            }
        }
    }

    private var cardFrame: NSRect {
        NSRect(x: panel.frame.minX, y: panel.frame.minY, width: SidebarMetrics.width, height: panel.frame.height)
    }

    /// The window never moves; the card springs inside it, so animations stay interruptible.
    /// It spans from the bottom of the screen to the menu bar, which stays visible.
    private func place(on screen: NSScreen) {
        let frame = screen.frame
        panel.setFrame(NSRect(x: frame.minX, y: frame.minY,
                              width: SidebarMetrics.width,
                              height: screen.visibleFrame.maxY - frame.minY), display: false)
    }

    private func transition(to phase: SidebarModel.Phase) {
        let animation: Animation = switch phase {
        case .peeking: .spring(response: 0.25, dampingFraction: 1)
        case .shown: .spring(response: 0.34, dampingFraction: 0.86)
        case .hidden: .spring(response: 0.26, dampingFraction: 1)
        }
        withAnimation(animation) {
            model.phase = phase
        } completion: { [weak self] in
            guard let self, self.model.phase == .hidden else { return }
            self.panel.orderOut(nil)
        }
    }

    // MARK: Actions

    private func makeActions() -> SidebarActions {
        SidebarActions(
            select: { [weak self] window in
                self?.store.focus(window)
                self?.hide()
            },
            open: { [weak self] app in
                self?.store.open(app)
                self?.hide()
            },
            addToProject: { [weak self] window in
                guard let self else { return }
                let projects = store.projects
                guard let answer = holdingOpen({ Dialogs.addToProject(window, projectNames: projects.names) }) else { return }
                let rule = WindowRule(appID: window.appID, appName: window.appName, titleContains: answer.titleContains)
                projects.add(rule, toProjectNamed: answer.projectName)
            },
            removeFromProject: { [weak self] window, project in
                self?.store.projects.remove(window, from: project)
            },
            renameProject: { [weak self] project in
                guard let self, let name = holdingOpen({ Dialogs.rename(project) }) else { return }
                store.projects.rename(project, to: name)
            },
            setColor: { [weak self] color, project in
                self?.store.projects.setColor(color, of: project)
            },
            deleteProject: { [weak self] project in
                self?.store.projects.delete(project)
            },
            removeRule: { [weak self] rule, project in
                self?.store.projects.remove(rule, from: project)
            }
        )
    }

    private func holdingOpen<T>(_ dialog: () -> T) -> T {
        isHeldOpen = true
        hideTimer?.invalidate()
        hideTimer = nil
        defer {
            isHeldOpen = false
            store.refresh()
        }
        return dialog()
    }
}
