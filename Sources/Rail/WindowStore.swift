import AppKit
import ApplicationServices
import Observation

/// A window, or one tab of a browser window: tabs are listed and matched to projects like windows.
struct WindowItem: Identifiable {
    let id: String
    /// Same for every tab of one window.
    let windowID: String
    let app: NSRunningApplication
    let title: String
    let isMinimized: Bool
    let isFocused: Bool
    let element: AXUIElement
    /// Window server number; nil only if the private lookup is unavailable.
    let number: CGWindowID?
    /// The tab button to press after raising the window.
    var tab: AXUIElement? = nil
    /// Page or document shown. Read only for apps with pins, and only for a window's selected tab.
    var url: URL? = nil

    /// Bundle ID, or the app name for the rare app without one.
    var appID: String { app.bundleIdentifier ?? appName }
    var appName: String { app.localizedName ?? "Без названия" }
}

struct AppGroup: Identifiable {
    var id: pid_t { app.processIdentifier }
    let app: NSRunningApplication
    let name: String
    let icon: NSImage?
    var windows: [WindowItem]
}

/// A pin with its window, if that is open.
struct PinnedEntry: Identifiable {
    var id: UUID { pin.id }
    let pin: PinnedItem
    let window: WindowItem?
    let icon: NSImage?
}

struct ProjectSection: Identifiable {
    var id: UUID { project.id }
    let project: Project
    let pins: [PinnedEntry]
    let windows: [WindowItem]

    var openCount: Int { windows.count + pins.count { $0.window != nil } }

    /// One icon per app, pins first.
    var icons: [NSImage] {
        var seen = Set<String>()
        let items = pins.map { ($0.pin.appID, $0.icon) } + windows.map { ($0.appID, $0.app.icon) }
        return items.compactMap { appID, icon in seen.insert(appID).inserted ? icon : nil }
    }
}

struct SidebarLayout {
    let sections: [ProjectSection]
    let ungrouped: [AppGroup]
}

/// Snapshot of every standard window of every regular app on every Space.
/// AX lists only windows on the current Space for most apps; the window server lists all of
/// them, so windows it knows about and AX does not are looked up with `PrivateAPI.scanWindows`.
@MainActor @Observable
final class WindowStore {
    let projects: ProjectStore
    private(set) var apps: [AppGroup] = []
    /// Running apps with no windows anywhere, so the sidebar can still reach them.
    private(set) var idleApps: [NSRunningApplication] = []
    private(set) var isTrusted = Accessibility.isTrusted

    /// Windows on other Spaces found by a scan. A scan is slow and AX will not list them,
    /// so each element is kept until its window closes.
    @ObservationIgnored private var offSpace: [CGWindowID: AXUIElement] = [:]
    /// Window numbers already scanned for. Not every window-server window is a real window,
    /// and those must not trigger a new scan on every refresh.
    @ObservationIgnored private var scanned: Set<CGWindowID> = []
    /// Whether each app is a browser, by bundle ID; the Launch Services lookup is not free.
    @ObservationIgnored private var browsers: [String: Bool] = [:]
    /// Browsers already asked to build their accessibility tree.
    @ObservationIgnored private var revealed: Set<pid_t> = []
    /// Icons of pinned apps by bundle ID, for pins whose app is not running.
    @ObservationIgnored private var appIcons: [String: NSImage] = [:]

    init(projects: ProjectStore) {
        self.projects = projects
    }

    var windowCount: Int { Set(apps.flatMap { $0.windows.map(\.windowID) }).count }

    /// Pins claim their windows first, so a pinned window stays put even when another project's
    /// rules match it. Then each window lands in the first project with a matching rule;
    /// the rest stay grouped by app.
    var layout: SidebarLayout {
        var claimed = Set<String>()
        let all = apps.flatMap(\.windows)
        let pins = projects.projects.map { project in
            project.pins.map { pin in
                let window = pin.window(in: all.filter { !claimed.contains($0.id) })
                if let window { claimed.insert(window.id) }
                return PinnedEntry(pin: pin, window: window, icon: window?.app.icon ?? appIcon(pin.appID))
            }
        }
        let sections = zip(projects.projects, pins).map { project, pins in
            let windows = all.filter { !claimed.contains($0.id) && project.matches($0) }
            claimed.formUnion(windows.map(\.id))
            return ProjectSection(project: project, pins: pins, windows: windows)
        }
        let ungrouped = apps.compactMap { group -> AppGroup? in
            var rest = group
            rest.windows.removeAll { claimed.contains($0.id) }
            return rest.windows.isEmpty ? nil : rest
        }
        return SidebarLayout(sections: sections, ungrouped: ungrouped)
    }

    func refresh() {
        isTrusted = Accessibility.isTrusted
        guard isTrusted else {
            apps = []
            idleApps = []
            return
        }
        let me = ProcessInfo.processInfo.processIdentifier
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let serverWindows = Self.serverWindowNumbers()
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != me }
            .sorted { ($0.localizedName ?? "").localizedStandardCompare($1.localizedName ?? "") == .orderedAscending }

        let pinnedApps = projects.pinnedAppIDs
        var groups: [AppGroup] = []
        var idle: [NSRunningApplication] = []
        for app in running {
            let pid = app.processIdentifier
            let group = group(for: app, serverWindows: serverWindows[pid] ?? [], isFrontmost: pid == frontmost,
                              readsURLs: pinnedApps.contains(app.bundleIdentifier ?? ""))
            if group.windows.isEmpty { idle.append(app) } else { groups.append(group) }
        }
        apps = groups
        idleApps = idle
        projects.refreshPins(from: groups.flatMap(\.windows))

        let live = Set(serverWindows.values.joined())
        offSpace = offSpace.filter { live.contains($0.key) }
        scanned.formIntersection(live)
        revealed.formIntersection(running.map(\.processIdentifier))
    }

    func focus(_ window: WindowItem) {
        if window.app.isHidden { window.app.unhide() }
        if window.isMinimized { window.element.set(kAXMinimizedAttribute, kCFBooleanFalse) }
        // The private call also switches Spaces; plain AX cannot reach a window on another one.
        let switched = window.number.map { PrivateAPI.bringToFront(window.app.processIdentifier, window: $0) } ?? false
        if !switched {
            AXUIElementCreateApplication(window.app.processIdentifier).set(kAXFrontmostAttribute, kCFBooleanTrue)
        }
        window.element.set(kAXMainAttribute, kCFBooleanTrue)
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        if let tab = window.tab { AXUIElementPerformAction(tab, kAXPressAction as CFString) }
    }

    /// Address of a window or tab to pin, so it can be reopened once closed.
    func url(of window: WindowItem) -> URL? {
        if let url = window.url { return url }
        if isBrowser(window.app) {
            guard let tab = window.tab else { return Tabs.pageURL(of: window.element) }
            return Tabs.pageURL(of: window.element, tab: tab)
        }
        // A system tab bar shows the document of its front tab only.
        if let tab = window.tab, tab.value(kAXValueAttribute) as Int? != 1 { return nil }
        return Self.documentURL(of: window.element, appID: window.appID)
    }

    /// Opens a closed pin in the app it was pinned from: the page or document if known, else the app.
    func open(_ pin: PinnedItem) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: pin.appID) else { return }
        if let url = pin.url {
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    private func appIcon(_ appID: String) -> NSImage? {
        if let icon = appIcons[appID] { return icon }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        appIcons[appID] = icon
        return icon
    }

    /// File or folder of a document window, if the app reports one.
    private static func documentURL(of window: AXUIElement, appID: String) -> URL? {
        if appID == Finder.bundleID { return Finder.folderURL(of: window) }
        guard let path: String = window.value(kAXDocumentAttribute), !path.isEmpty else { return nil }
        return URL(string: path)
    }

    /// Activates an app with no windows; the reopen event makes most apps open a new one.
    func open(_ app: NSRunningApplication) {
        guard let url = app.bundleURL else {
            app.activate()
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func group(for app: NSRunningApplication, serverWindows: [CGWindowID], isFrontmost: Bool,
                       readsURLs: Bool) -> AppGroup {
        let pid = app.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)
        // A hung app must not freeze the sidebar.
        AXUIElementSetMessagingTimeout(axApp, 0.25)

        let name = app.localizedName ?? "Без названия"
        let focused: AXUIElement? = isFrontmost ? axApp.value(kAXFocusedWindowAttribute) : nil
        var elements: [AXUIElement] = axApp.value(kAXWindowsAttribute) ?? []
        elements.append(contentsOf: otherSpaceWindows(of: pid, serverWindows: serverWindows, listed: elements))

        let isBrowser = isBrowser(app)
        let standard = elements.filter { $0.value(kAXSubroleAttribute) as String? == kAXStandardWindowSubrole }
        if isBrowser, !revealed.contains(pid), let first = standard.first {
            Tabs.revealTree(of: axApp, window: first)
            revealed.insert(pid)
        }
        let tabsByWindow = standard.map { isBrowser ? Tabs.browserTabs(of: $0) : Tabs.windowTabs(of: $0) }
        let hiddenTabs = isBrowser ? [] : Self.hiddenTabWindows(standard, tabs: tabsByWindow)

        let windows = zip(standard, tabsByWindow).enumerated().flatMap { index, pair -> [WindowItem] in
            let (element, tabs) = pair
            if hiddenTabs.contains(index) { return [] }
            let title: String = element.value(kAXTitleAttribute) ?? ""
            let number = PrivateAPI.windowNumber(element)
            let windowID = number.map { "\(pid)-w\($0)" } ?? "\(pid)-\(index)"
            let url = readsURLs ? (isBrowser ? Tabs.pageURL(of: element) : Self.documentURL(of: element, appID: app.bundleIdentifier ?? "")) : nil
            let window = WindowItem(
                id: windowID,
                windowID: windowID,
                app: app,
                title: title.isEmpty ? name : title,
                isMinimized: element.value(kAXMinimizedAttribute) ?? false,
                isFocused: focused.map { CFEqual($0, element) } ?? false,
                element: element,
                number: number,
                url: url
            )
            guard !tabs.isEmpty else { return [window] }
            return tabs.enumerated().map { tabIndex, tab in
                WindowItem(
                    id: "\(windowID)-t\(tabIndex)",
                    windowID: windowID,
                    app: app,
                    title: tab.title.isEmpty ? window.title : tab.title,
                    isMinimized: window.isMinimized,
                    isFocused: window.isFocused && tab.isSelected,
                    element: element,
                    number: number,
                    tab: tab.element,
                    url: tab.isSelected ? url : nil
                )
            }
        }
        return AppGroup(app: app, name: name, icon: app.icon, windows: windows)
    }

    private func isBrowser(_ app: NSRunningApplication) -> Bool {
        let id = app.bundleIdentifier ?? ""
        if let known = browsers[id] { return known }
        let result = Tabs.isBrowser(app)
        browsers[id] = result
        return result
    }

    /// Indices of windows that are background tabs of a system tab bar. AX lists only the
    /// front tab's window, but a scan finds the others once they have been shown. They share
    /// the front window's frame and belong to no Space; without the Space lookup, a tab's
    /// title has to do, though Terminal titles its tabs and windows differently.
    private static func hiddenTabWindows(_ windows: [AXUIElement], tabs: [[Tabs.Tab]]) -> Set<Int> {
        let bars = zip(windows, tabs).compactMap { window, tabs -> (frame: CGRect, titles: Set<String>)? in
            guard !tabs.isEmpty, let frame = window.frame else { return nil }
            return (frame, Set(tabs.map(\.title)))
        }
        guard !bars.isEmpty else { return [] }
        return Set(windows.indices.filter { index in
            guard tabs[index].isEmpty, let frame = windows[index].frame,
                  let bar = bars.first(where: { $0.frame == frame }) else { return false }
            if let number = PrivateAPI.windowNumber(windows[index]), let onSpace = PrivateAPI.isOnSpace(number) {
                return !onSpace
            }
            return bar.titles.contains(windows[index].value(kAXTitleAttribute) ?? "")
        })
    }

    /// Elements for the app's windows that the window server has and AX did not list.
    private func otherSpaceWindows(of pid: pid_t, serverWindows: [CGWindowID], listed: [AXUIElement]) -> [AXUIElement] {
        let known = Set(listed.compactMap(PrivateAPI.windowNumber))
        let missing = serverWindows.filter { !known.contains($0) }
        let unscanned = Set(missing.filter { offSpace[$0] == nil && !scanned.contains($0) })
        if !unscanned.isEmpty {
            offSpace.merge(PrivateAPI.scanWindows(of: pid, wanted: unscanned)) { $1 }
            scanned.formUnion(unscanned)
        }
        return missing.compactMap { offSpace[$0] }
    }

    /// Normal-level windows of every app on every Space, by owner. Window numbers and owners
    /// need no Screen Recording permission; titles would. Tiny and transparent windows are
    /// helpers, not something a person would want to switch to.
    private static func serverWindowNumbers() -> [pid_t: [CGWindowID]] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [:] }
        var result: [pid_t: [CGWindowID]] = [:]
        for info in list {
            guard info[kCGWindowLayer as String] as? Int == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let number = info[kCGWindowNumber as String] as? CGWindowID,
                  (info[kCGWindowAlpha as String] as? Double ?? 0) > 0,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary),
                  bounds.width >= 50, bounds.height >= 50 else { continue }
            result[pid, default: []].append(number)
        }
        return result
    }
}
