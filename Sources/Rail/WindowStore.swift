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

    /// Splits "file.swift — Rail" into a headline and a quieter context line.
    var titleParts: (primary: String, secondary: String?) {
        for separator in [" — ", " – "] {
            if let range = title.range(of: separator) {
                return (String(title[..<range.lowerBound]), String(title[range.upperBound...]))
            }
        }
        return (title, nil)
    }

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

struct ProjectSection: Identifiable {
    var id: UUID { project.id }
    let project: Project
    let windows: [WindowItem]
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

    init(projects: ProjectStore) {
        self.projects = projects
    }

    var windowCount: Int { Set(apps.flatMap { $0.windows.map(\.windowID) }).count }

    /// Each window lands in the first project with a matching rule; the rest stay grouped by app.
    var layout: SidebarLayout {
        var claimed = Set<String>()
        let all = apps.flatMap(\.windows)
        let sections = projects.projects.map { project in
            let windows = all.filter { !claimed.contains($0.id) && project.matches($0) }
            claimed.formUnion(windows.map(\.id))
            return ProjectSection(project: project, windows: windows)
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

        var groups: [AppGroup] = []
        var idle: [NSRunningApplication] = []
        for app in running {
            let pid = app.processIdentifier
            let group = group(for: app, serverWindows: serverWindows[pid] ?? [], isFrontmost: pid == frontmost)
            if group.windows.isEmpty { idle.append(app) } else { groups.append(group) }
        }
        apps = groups
        idleApps = idle

        let live = Set(serverWindows.values.joined())
        offSpace = offSpace.filter { live.contains($0.key) }
        scanned.formIntersection(live)
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

    /// Activates an app with no windows; the reopen event makes most apps open a new one.
    func open(_ app: NSRunningApplication) {
        guard let url = app.bundleURL else {
            app.activate()
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func group(for app: NSRunningApplication, serverWindows: [CGWindowID], isFrontmost: Bool) -> AppGroup {
        let pid = app.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)
        // A hung app must not freeze the sidebar.
        AXUIElementSetMessagingTimeout(axApp, 0.25)

        let name = app.localizedName ?? "Без названия"
        let focused: AXUIElement? = isFrontmost ? axApp.value(kAXFocusedWindowAttribute) : nil
        var elements: [AXUIElement] = axApp.value(kAXWindowsAttribute) ?? []
        elements.append(contentsOf: otherSpaceWindows(of: pid, serverWindows: serverWindows, listed: elements))

        let isBrowser = app.bundleIdentifier.map(BrowserTabs.bundleIDs.contains) ?? false
        let windows = elements.enumerated().flatMap { index, element -> [WindowItem] in
            guard element.value(kAXSubroleAttribute) as String? == kAXStandardWindowSubrole else { return [] }
            let title: String = element.value(kAXTitleAttribute) ?? ""
            let number = PrivateAPI.windowNumber(element)
            let windowID = number.map { "\(pid)-w\($0)" } ?? "\(pid)-\(index)"
            let window = WindowItem(
                id: windowID,
                windowID: windowID,
                app: app,
                title: title.isEmpty ? name : title,
                isMinimized: element.value(kAXMinimizedAttribute) ?? false,
                isFocused: focused.map { CFEqual($0, element) } ?? false,
                element: element,
                number: number
            )
            let tabs = isBrowser ? BrowserTabs.tabs(of: element) : []
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
                    tab: tab.element
                )
            }
        }
        return AppGroup(app: app, name: name, icon: app.icon, windows: windows)
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
