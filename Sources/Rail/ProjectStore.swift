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

struct Project: Codable, Identifiable, Hashable {
    static let colorCount = 8

    var id = UUID()
    var name: String
    var rules: [WindowRule]
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
