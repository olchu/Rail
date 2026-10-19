import AppKit

/// Watches the mouse and reports when it rests against the outer left edge of a screen.
/// Global mouse monitors need no permissions. They never see events while Rail itself is
/// active, so each one is paired with a local monitor.
@MainActor
final class EdgeMonitor {
    /// The pointer touched the edge: time to hint that something is there.
    var onEdgeEnter: ((NSScreen) -> Void)?
    /// The pointer stayed long enough: open.
    var onEdge: ((NSScreen) -> Void)?
    var onEdgeLeave: (() -> Void)?
    var onMove: ((NSPoint) -> Void)?

    /// How long the pointer must stay at the edge, so passing through does not open the sidebar.
    private let dwell: TimeInterval = 0.18
    private var dwellTimer: Timer?
    private var edgeScreen: NSScreen?
    private var monitors: [Any] = []

    func start() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { _ in
            MainActor.assumeIsolated { self.handleMove() }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { event in
            MainActor.assumeIsolated { self.handleMove() }
            return event
        }) {
            monitors.append(local)
        }
    }

    private func handleMove() {
        let point = NSEvent.mouseLocation
        onMove?(point)

        let screen = NSEvent.pressedMouseButtons == 0 ? Self.leftEdgeScreen(at: point) : nil
        guard let screen else {
            guard edgeScreen != nil else { return }
            edgeScreen = nil
            dwellTimer?.invalidate()
            dwellTimer = nil
            onEdgeLeave?()
            return
        }
        guard edgeScreen == nil else { return }
        edgeScreen = screen
        onEdgeEnter?(screen)
        dwellTimer = Timer.scheduledTimer(withTimeInterval: dwell, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let screen = self.edgeScreen else { return }
                self.onEdge?(screen)
            }
        }
    }

    /// The screen whose left edge the point touches, unless another screen continues to the left.
    private static func leftEdgeScreen(at point: NSPoint) -> NSScreen? {
        let screens = NSScreen.screens
        guard let screen = screens.first(where: { NSMouseInRect(point, $0.frame, false) }),
              point.x <= screen.frame.minX + 1 else { return nil }
        let beyond = NSPoint(x: screen.frame.minX - 2, y: point.y)
        return screens.contains(where: { NSMouseInRect(beyond, $0.frame, false) }) ? nil : screen
    }
}
