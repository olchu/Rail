import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = WindowStore(projects: ProjectStore())
    private let edge = EdgeMonitor()
    private var sidebar: SidebarController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let sidebar = SidebarController(store: store)
        self.sidebar = sidebar
        edge.onEdgeEnter = { [weak sidebar] screen in sidebar?.peek(on: screen) }
        edge.onEdge = { [weak sidebar] screen in sidebar?.show(on: screen) }
        edge.onEdgeLeave = { [weak sidebar] in sidebar?.cancelPeek() }
        edge.onMove = { [weak sidebar] point in sidebar?.mouseMoved(to: point) }
        edge.start()
        setUpStatusItem()
        if !Accessibility.isTrusted { Accessibility.requestAccess() }
        // The first refresh scans for windows on other Spaces; better at launch than on first reveal.
        store.refresh()
        // Debug aid for design work: RAIL_PREVIEW=1 opens the sidebar at launch and keeps it open.
        if ProcessInfo.processInfo.environment["RAIL_PREVIEW"] == "1", let screen = NSScreen.main {
            sidebar.isPinnedForPreview = true
            sidebar.show(on: screen)
        }
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Rail")
        let menu = NSMenu()
        menu.addItem(withTitle: "Показать сайдбар", action: #selector(showSidebar), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Доступ к Accessibility…", action: #selector(openAccessibility), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Выйти", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func showSidebar() {
        guard let screen = NSScreen.main else { return }
        sidebar?.show(on: screen)
    }

    @objc private func openAccessibility() {
        Accessibility.requestAccess()
    }
}
