import Foundation
import Observation

/// Matches windows of one app, optionally narrowed to titles containing a word.
/// Windows have no stable identity across app restarts, so projects are defined by rules.
struct WindowRule: Codable, Hashable {
    var appID: String
    var appName: String
    /// Empty means every window of the app.
    var titleContains: String

    func matches(_ window: WindowItem) -> Bool {
        window.appID == appID
            && (titleContains.isEmpty || window.title.localizedCaseInsensitiveContains(titleContains))
    }

    var label: String {
        titleContains.isEmpty ? "\(appName) · все окна" : "\(appName) · «\(titleContains)»"
    }
}

/// A window or tab kept in a project after it closes, with what it takes to open it again.
struct PinnedItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var appID: String
    var appName: String
    var title: String
    /// Page or document to reopen. Without one, reopening just opens the app.
    var url: URL?

    /// The open window this pin stands for: same address first, since titles drift, then same title.
    /// A window that cannot tell what it shows, like a chat app's single window, may show anything,
    /// so a pin with a link leaves it alone and opens the link instead.
    func window(in windows: [WindowItem]) -> WindowItem? {
        let own = windows.filter { $0.appID == appID }
        guard let url else { return own.first { $0.title == title } }
        if let window = own.first(where: { $0.url == url }) { return window }
        // A Slack thread opens beside its channel; the window's title names only the channel.
        if Slack.isThread(url) { return nil }
        return own.first { $0.title == title && ($0.url != nil || $0.tab != nil) }
    }

    /// Reads a link typed by hand: a web address, a file path, or a custom scheme.
    /// Slack message links become slack:// links to their thread.
    /// For Telegram also @username, a phone number and t.me links, which it opens as tg:// links.
    static func link(_ text: String, appID: String) -> URL? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.hasPrefix("/") || text.hasPrefix("~") {
            return URL(fileURLWithPath: (text as NSString).expandingTildeInPath)
        }
        let isTelegram = appID.localizedCaseInsensitiveContains("telegram")
        if isTelegram, text.hasPrefix("@") {
            return telegram("resolve", ["domain": String(text.dropFirst())])
        }
        let digits = text.filter(\.isNumber)
        if isTelegram, text.hasPrefix("+"), digits.count >= 7,
           text.allSatisfy({ $0.isNumber || " +-()".contains($0) }) {
            return telegram("resolve", ["phone": digits])
        }
        guard let url = URL(string: text.contains(":") ? text : "https://\(text)") else { return nil }
        if let host = url.host(), ["t.me", "telegram.me"].contains(host) {
            return telegramLink(path: url.pathComponents.filter { $0 != "/" }) ?? url
        }
        if url.host()?.hasSuffix("slack.com") == true, url.path().contains("/archives/") {
            return Slack.link(fromPermalink: url) ?? url
        }
        return url
    }

    /// t.me/name, t.me/name/123, t.me/+79991234567 and t.me/+invite as tg:// links.
    private static func telegramLink(path: [String]) -> URL? {
        guard let first = path.first else { return nil }
        if first.hasPrefix("+") {
            let rest = String(first.dropFirst())
            return rest.allSatisfy(\.isNumber)
                ? telegram("resolve", ["phone": rest])
                : telegram("join", ["invite": rest])
        }
        var query = ["domain": first]
        if path.count > 1 { query["post"] = path[1] }
        return telegram("resolve", query)
    }

    private static func telegram(_ action: String, _ query: [String: String]) -> URL? {
        var components = URLComponents()
        components.scheme = "tg"
        components.host = action
        components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url
    }
}

struct Project: Codable, Identifiable, Hashable {
    static let colorCount = 8

    var id = UUID()
    var name: String
    var rules: [WindowRule]
    var pins: [PinnedItem] = []
    /// Index into the UI palette.
    var color: Int

    init(name: String, rules: [WindowRule], color: Int) {
        self.name = name
        self.rules = rules
        self.color = color
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        rules = try container.decode([WindowRule].self, forKey: .rules)
        pins = try container.decodeIfPresent([PinnedItem].self, forKey: .pins) ?? []
        // Projects saved before colors existed get a stable one derived from the ID.
        color = try container.decodeIfPresent(Int.self, forKey: .color) ?? Int(id.uuid.0) % Self.colorCount
    }

    func matches(_ window: WindowItem) -> Bool {
        rules.contains { $0.matches(window) }
    }
}

@MainActor @Observable
final class ProjectStore {
    private(set) var projects: [Project] = []

    private static let defaultsKey = "projects"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode([Project].self, from: data) {
            projects = saved
        }
    }

    var names: [String] { projects.map(\.name) }

    /// Adds the rule to the project with this name, creating the project if needed.
    func add(_ rule: WindowRule, toProjectNamed name: String) {
        if let index = projects.firstIndex(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            guard !projects[index].rules.contains(rule) else { return }
            projects[index].rules.append(rule)
        } else {
            projects.append(Project(name: name, rules: [rule], color: leastUsedColor()))
        }
        save()
    }

    func rename(_ project: Project, to name: String) {
        update(project) { $0.name = name }
    }

    func setColor(_ color: Int, of project: Project) {
        update(project) { $0.color = color }
    }

    func delete(_ project: Project) {
        projects.removeAll { $0.id == project.id }
        save()
    }

    func remove(_ rule: WindowRule, from project: Project) {
        update(project) { $0.rules.removeAll { $0 == rule } }
    }

    /// Drops every rule of the project that matches the window.
    func remove(_ window: WindowItem, from project: Project) {
        update(project) { $0.rules.removeAll { $0.matches(window) } }
    }

    func pin(_ item: PinnedItem, to project: Project) {
        update(project) { $0.pins.append(item) }
    }

    func replace(_ item: PinnedItem, in project: Project) {
        update(project) { project in
            guard let index = project.pins.firstIndex(where: { $0.id == item.id }) else { return }
            project.pins[index] = item
        }
    }

    func unpin(_ item: PinnedItem, from project: Project) {
        update(project) { $0.pins.removeAll { $0.id == item.id } }
    }

    /// Apps with pins, whose windows need their addresses read on refresh.
    var pinnedAppIDs: Set<String> {
        Set(projects.flatMap { $0.pins.map(\.appID) })
    }

    /// Keeps pins current from their open windows: the title follows the page,
    /// and a pin made without an address picks it up from its window.
    /// Links saved before Rail could convert them, like Slack message links, get their working form.
    func refreshPins(from windows: [WindowItem]) {
        var changed = false
        for p in projects.indices {
            for i in projects[p].pins.indices {
                if let url = projects[p].pins[i].url,
                   let link = PinnedItem.link(url.absoluteString, appID: projects[p].pins[i].appID), link != url {
                    projects[p].pins[i].url = link
                    changed = true
                }
                let pin = projects[p].pins[i]
                guard let window = pin.window(in: windows) else { continue }
                if let url = pin.url, window.url == url, window.title != pin.title {
                    projects[p].pins[i].title = window.title
                    changed = true
                } else if pin.url == nil, let url = window.url {
                    projects[p].pins[i].url = url
                    changed = true
                }
            }
        }
        if changed { save() }
    }

    private func leastUsedColor() -> Int {
        (0..<Project.colorCount).min { a, b in
            projects.filter { $0.color == a }.count < projects.filter { $0.color == b }.count
        } ?? 0
    }

    private func update(_ project: Project, _ change: (inout Project) -> Void) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        change(&projects[index])
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}
