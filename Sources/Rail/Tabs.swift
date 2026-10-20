import AppKit
import ApplicationServices

/// Tabs of a window, read from its tab strip in the accessibility tree. Browsers draw their own
/// strip, often a few groups deep; other apps count only with the system tab bar macOS adds
/// to merged windows (Finder, Terminal), since elsewhere a tab group is usually a settings pane.
enum Tabs {
    struct Tab {
        let element: AXUIElement
        let title: String
        let isSelected: Bool
    }

    /// Any app that opens web links: covers Firefox forks, Tor and the rest without a list to keep.
    static func isBrowser(_ app: NSRunningApplication) -> Bool {
        guard let url = app.bundleURL, let web = URL(string: "https://example.com") else { return false }
        return NSWorkspace.shared.urlsForApplications(toOpen: web).contains(url)
    }

    /// Branches that never hold the tab strip; page content in particular can be huge.
    private static let skippedRoles: Set<String> = [
        "AXWebArea", "AXScrollArea", "AXTextField", "AXTextArea", "AXTable", "AXOutline", "AXList",
    ]

    /// Breadth-first, since the strip sits a few groups below the window, before the page.
    /// Safari's strip is not a tab group but a plain list of tab buttons; Firefox keeps it in a toolbar.
    static func browserTabs(of window: AXUIElement) -> [Tab] {
        var queue = [window]
        var visited = 0
        while !queue.isEmpty, visited < 200 {
            let element = queue.removeFirst()
            visited += 1
            let role: String? = element.value(kAXRoleAttribute)
            let children: [AXUIElement] = element.value(kAXChildrenAttribute) ?? []
            let tabs = children.compactMap(tab)
            if !tabs.isEmpty { return tabs }
            if role == kAXTabGroupRole { continue }
            if let role, skippedRoles.contains(role) { continue }
            queue.append(contentsOf: children)
        }
        return []
    }

    /// The system tab bar is a direct child of the window. Unlike a settings pane's tabs,
    /// its tabs carry close buttons.
    static func windowTabs(of window: AXUIElement) -> [Tab] {
        let children: [AXUIElement] = window.value(kAXChildrenAttribute) ?? []
        for child in children where child.value(kAXRoleAttribute) as String? == kAXTabGroupRole {
            let buttons: [AXUIElement] = child.value(kAXChildrenAttribute) ?? []
            let closable = buttons.contains { button in
                (button.value(kAXChildrenAttribute) as [AXUIElement]? ?? [])
                    .contains { $0.value(kAXRoleAttribute) as String? == kAXButtonRole }
            }
            if closable { return buttons.compactMap(tab) }
        }
        return []
    }

    /// Firefox builds its tree only for assistive apps that ask for it this way;
    /// until then a window shows nothing but its title bar buttons.
    static func revealTree(of app: AXUIElement, window: AXUIElement) {
        let children: [AXUIElement] = window.value(kAXChildrenAttribute) ?? []
        guard children.allSatisfy({ $0.value(kAXRoleAttribute) as String? == kAXButtonRole }) else { return }
        app.set("AXEnhancedUserInterface", kCFBooleanTrue)
    }

    /// Address of the page the window shows. Chrome and its kin report it as the window's document;
    /// otherwise it is on the web area, which only the selected tab has.
    static func pageURL(of window: AXUIElement) -> URL? {
        if let document: String = window.value(kAXDocumentAttribute), let url = URL(string: document) {
            return url
        }
        var queue = [window]
        var visited = 0
        while !queue.isEmpty, visited < 300 {
            let element = queue.removeFirst()
            visited += 1
            let role: String? = element.value(kAXRoleAttribute)
            if role == "AXWebArea" {
                if let url: URL = element.value("AXURL") { return url }
                return (element.value("AXURL") as String?).flatMap(URL.init(string:))
            }
            if let role, role != "AXScrollArea", skippedRoles.contains(role) { continue }
            let children: [AXUIElement] = element.value(kAXChildrenAttribute) ?? []
            queue.append(contentsOf: children)
        }
        return nil
    }

    /// Address of any tab. A background tab has no page in the tree, so it is selected
    /// for a moment, until its page shows up, and the previous tab is selected again.
    static func pageURL(of window: AXUIElement, tab: AXUIElement) -> URL? {
        let tabs = browserTabs(of: window)
        let previous = tabs.first(where: \.isSelected)
        if let previous, CFEqual(previous.element, tab) { return pageURL(of: window) }
        let before = pageURL(of: window)
        AXUIElementPerformAction(tab, kAXPressAction as CFString)
        defer {
            if let previous { AXUIElementPerformAction(previous.element, kAXPressAction as CFString) }
        }
        let clock = ContinuousClock()
        let deadline = clock.now + .milliseconds(600)
        while clock.now < deadline {
            if let url = pageURL(of: window), url != before { return url }
            Thread.sleep(forTimeInterval: 0.03)
        }
        // Two tabs on the same page look unchanged.
        return pageURL(of: window)
    }

    private static func tab(_ element: AXUIElement) -> Tab? {
        guard element.value(kAXRoleAttribute) as String? == kAXRadioButtonRole,
              element.value(kAXSubroleAttribute) as String? == "AXTabButton" else { return nil }
        let title: String = element.value(kAXTitleAttribute) ?? element.value(kAXDescriptionAttribute) ?? ""
        return Tab(element: element, title: clean(title), isSelected: element.value(kAXValueAttribute) as Int? == 1)
    }

    /// Chrome appends its hover-card details: "Jira - Memory usage - 519 MB".
    private static func clean(_ title: String) -> String {
        title.replacing(/\s-\s(?:[^-]+\s-\s)?[^-]*?\d[\d.,\s]*(KB|MB|GB|КБ|МБ|ГБ)$/, with: "")
    }
}
