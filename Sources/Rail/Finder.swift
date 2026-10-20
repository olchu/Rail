import AppKit
import ApplicationServices

/// Finder reports no document for its windows, but its file views give every item's URL.
/// The folder shown is the one among the items' parents, or the items themselves in column view,
/// that is named like the window. An empty folder in list or icon view has no items to go by.
enum Finder {
    static let bundleID = "com.apple.finder"

    static func folderURL(of window: AXUIElement) -> URL? {
        guard let title = folderName(of: window) else { return nil }
        var candidates = Set<URL>()
        for item in itemURLs(in: window) {
            candidates.insert(item.deletingLastPathComponent().standardizedFileURL)
            if item.hasDirectoryPath { candidates.insert(item.standardizedFileURL) }
        }
        let fileManager = FileManager.default
        // In column view each column is a parent; the deepest one named like the window is the current one.
        return candidates
            .filter { fileManager.displayName(atPath: $0.path) == title || $0.lastPathComponent == title }
            .max { $0.pathComponents.count < $1.pathComponents.count }
    }

    /// Window title without what Finder adds when two folders share a name:
    /// "⁨Documents⁩ — Local", with the name between directional isolates.
    private static func folderName(of window: AXUIElement) -> String? {
        guard let title: String = window.value(kAXTitleAttribute) else { return nil }
        let isolated = title.firstRange(of: /\u{2068}(.*?)\u{2069}/).map { String(title[$0].dropFirst().dropLast()) }
        let name = isolated ?? title
        return name.isEmpty ? nil : name
    }

    /// File URLs of items in the window's file views. Finder hands out file reference URLs.
    private static func itemURLs(in window: AXUIElement) -> [URL] {
        var urls: [URL] = []
        var queue = [window]
        var visited = 0
        while !queue.isEmpty, visited < 800, urls.count < 40 {
            let element = queue.removeFirst()
            visited += 1
            if let url: URL = element.value("AXURL"), url.isFileURL {
                urls.append((url as NSURL).filePathURL ?? url)
                continue
            }
            let children: [AXUIElement] = element.value(kAXChildrenAttribute) ?? []
            queue.append(contentsOf: children)
        }
        return urls
    }
}
