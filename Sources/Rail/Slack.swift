import AppKit
import ApplicationServices

/// Slack is a web page inside Electron. Its page address names the workspace and channel,
/// and the thread pane links to the thread's first message. Slack opens only slack:// links,
/// and those need the workspace ID, which its message links ("Copy link") lack.
enum Slack {
    static let bundleID = "com.tinyspeck.slackmacgap"

    /// Workspace of the last Slack window read, kept across launches. Slack's window can be out of
    /// reach for a long time: AX lists windows on the current Space only, and the scan for other
    /// Spaces does not find Electron windows, so a message link may need it while Slack is elsewhere.
    private static var lastTeam: String? {
        get { UserDefaults.standard.string(forKey: "slackTeam") }
        set { UserDefaults.standard.set(newValue, forKey: "slackTeam") }
    }

    /// The channel shown, or the thread open beside it, as a slack:// link.
    static func location(of window: AXUIElement, includingThread: Bool) -> URL? {
        revealTree(of: window)
        guard let (team, channel) = page(of: window) else { return nil }
        lastTeam = team
        if includingThread, let message = threadPermalink(in: window), let link = link(fromPermalink: message, team: team) {
            return link
        }
        return link(team: team, channel: channel)
    }

    /// A message link, https://acme.slack.com/archives/C123/p1700000000123456, as a slack:// link
    /// that opens its thread. The workspace is the one Slack shows now.
    static func link(fromPermalink url: URL) -> URL? {
        guard let team = currentTeam() ?? lastTeam else { return nil }
        return link(fromPermalink: url, team: team)
    }

    /// "payments (Channel) - Acme - Slack" → "payments".
    static func channelName(fromTitle title: String) -> String {
        let end = title.range(of: " (")?.lowerBound ?? title.range(of: " - ")?.lowerBound ?? title.endIndex
        return String(title[..<end])
    }

    static func isThread(_ url: URL) -> Bool {
        url.scheme == "slack" && url.query()?.contains("thread_ts=") == true
    }

    // MARK: Links

    private static func link(team: String, channel: String, message: String? = nil, thread: String? = nil) -> URL? {
        var components = URLComponents()
        components.scheme = "slack"
        components.host = "channel"
        components.queryItems = [
            URLQueryItem(name: "team", value: team),
            URLQueryItem(name: "id", value: channel),
        ]
        if let message { components.queryItems?.append(URLQueryItem(name: "message", value: message)) }
        if let thread { components.queryItems?.append(URLQueryItem(name: "thread_ts", value: thread)) }
        return components.url
    }

    /// A reply's link carries its thread in the query; a first message is its own thread.
    private static func link(fromPermalink url: URL, team: String) -> URL? {
        let path = url.pathComponents
        guard url.host()?.hasSuffix("slack.com") == true, path.count >= 4, path[1] == "archives",
              path[3].hasPrefix("p"), path[3].count > 7 else { return nil }
        let digits = path[3].dropFirst()
        let message = "\(digits.dropLast(6)).\(digits.suffix(6))"
        let thread = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "thread_ts" }?.value
        return link(team: team, channel: path[2], message: message, thread: thread ?? message)
    }

    // MARK: Accessibility

    /// Electron builds its tree only for assistive apps that ask this way; the first time takes a moment.
    private static func revealTree(of window: AXUIElement) {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success else { return }
        AXUIElementCreateApplication(pid).set("AXManualAccessibility", kCFBooleanTrue)
    }

    /// Workspace and channel from the page address, https://app.slack.com/client/T123/C456.
    private static func page(of window: AXUIElement) -> (team: String, channel: String)? {
        guard let url = Tabs.pageURL(of: window) else { return nil }
        let path = url.pathComponents
        guard path.count >= 4, path[1] == "client" else { return nil }
        return (path[2], path[3])
    }

    private static func currentTeam() -> String? {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) else {
            return nil
        }
        let windows: [AXUIElement] = AXUIElementCreateApplication(app.processIdentifier).value(kAXWindowsAttribute) ?? []
        return windows.lazy.compactMap { window in
            revealTree(of: window)
            return page(of: window)?.team
        }.first
    }

    /// The first message link in the thread pane: the message the thread hangs off.
    private static func threadPermalink(in window: AXUIElement) -> URL? {
        guard let pane = first(in: window, limit: 4000, where: {
            ($0.value("AXDOMClassList") as [String]? ?? []).contains("p-threads_flexpane")
        }) else { return nil }
        let link = first(in: pane, limit: 1000) { element in
            (element.value("AXURL") as URL?)?.path().contains("/archives/") == true
        }
        return link?.value("AXURL")
    }

    private static func first(in root: AXUIElement, limit: Int, where matches: (AXUIElement) -> Bool) -> AXUIElement? {
        var queue = [root]
        var visited = 0
        while !queue.isEmpty, visited < limit {
            let element = queue.removeFirst()
            visited += 1
            if matches(element) { return element }
            let children: [AXUIElement] = element.value(kAXChildrenAttribute) ?? []
            queue.append(contentsOf: children)
        }
        return nil
    }
}
