import ApplicationServices

/// Tabs of a browser window, read from the tab strip in its accessibility tree.
/// Limited to browsers: elsewhere a tab group is usually a settings pane, not something to switch to.
enum BrowserTabs {
    struct Tab {
        let element: AXUIElement
        let title: String
        let isSelected: Bool
    }

    static let bundleIDs: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary", "org.chromium.Chromium",
        "com.brave.Browser", "com.microsoft.edgemac", "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
        "com.apple.Safari", "com.apple.SafariTechnologyPreview", "org.mozilla.firefox",
    ]

    /// Branches that never hold the tab strip; page content in particular can be huge.
    private static let skippedRoles: Set<String> = [
        "AXWebArea", "AXToolbar", "AXScrollArea", "AXTextField", "AXTextArea", "AXTable", "AXOutline", "AXList",
    ]

    /// Breadth-first, since the strip sits a few groups below the window, before the page.
    static func tabs(of window: AXUIElement) -> [Tab] {
        var queue = [window]
        var visited = 0
        while !queue.isEmpty, visited < 200 {
            let element = queue.removeFirst()
            visited += 1
            let role: String? = element.value(kAXRoleAttribute)
            if role == kAXTabGroupRole {
                let tabs = (element.value(kAXChildrenAttribute) as [AXUIElement]? ?? []).compactMap(tab)
                if !tabs.isEmpty { return tabs }
                continue
            }
            if let role, skippedRoles.contains(role) { continue }
            queue.append(contentsOf: element.value(kAXChildrenAttribute) as [AXUIElement]? ?? [])
        }
        return []
    }

    private static func tab(_ element: AXUIElement) -> Tab? {
        guard element.value(kAXRoleAttribute) as String? == kAXRadioButtonRole else { return nil }
        let title: String = element.value(kAXTitleAttribute) ?? element.value(kAXDescriptionAttribute) ?? ""
        return Tab(element: element, title: clean(title), isSelected: element.value(kAXValueAttribute) as Int? == 1)
    }

    /// Chrome appends its hover-card details: "Jira - Memory usage - 519 MB".
    private static func clean(_ title: String) -> String {
        title.replacing(/\s-\s(?:[^-]+\s-\s)?[^-]*?\d[\d.,\s]*(KB|MB|GB|КБ|МБ|ГБ)$/, with: "")
    }
}
