import Foundation

/// Read-only discovery inside C:. Never descend through Wine's links to Mac folders.
enum ExecutableDiscovery {
    static func scan(driveC: URL) -> [URL] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        guard (try? driveC.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false,
              let walker = fm.enumerator(at: driveC, includingPropertiesForKeys: keys,
                                         options: [.skipsHiddenFiles]) else { return [] }
        let excluded = Set(["windows", "$recycle.bin", "system volume information"])
        var found = Set<URL>()
        for case let url as URL in walker {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { if url.hasDirectoryPath { walker.skipDescendants() }; continue }
            // DirectoryEnumerator does not descend into symbolic links. Calling
            // skipDescendants on a link can instead skip the following real directory.
            if values.isSymbolicLink == true { continue }
            if values.isDirectory == true {
                if url.deletingLastPathComponent().standardizedFileURL.path == driveC.standardizedFileURL.path,
                   excluded.contains(url.lastPathComponent.lowercased()) { walker.skipDescendants() }
            } else if values.isRegularFile == true && url.pathExtension.lowercased() == "exe" {
                found.insert(url.standardizedFileURL)
            }
        }
        return found.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    static func path(_ url: URL, driveC: URL) -> String {
        let base = driveC.standardizedFileURL.path + "/"
        let path = url.standardizedFileURL.path
        if path == driveC.standardizedFileURL.path { return "C:\\" }
        return path.hasPrefix(base) ? "C:\\" + path.dropFirst(base.count).replacingOccurrences(of: "/", with: "\\") : path
    }

    static func usable(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "exe" &&
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true &&
        FileManager.default.isReadableFile(atPath: url.path)
    }

    static func additional(_ url: URL) -> Bool {
        let name = url.deletingPathExtension().lastPathComponent.lowercased()
        return ["unins", "uninstall", "setup", "install", "update", "crash", "helper", "redist", "report"].contains { name.contains($0) }
    }

    struct Group: Identifiable {
        let id: String
        let title: String
        let files: [URL]
        var primary: [URL] { files.filter { !ExecutableDiscovery.additional($0) } }
        var additional: [URL] { files.filter { ExecutableDiscovery.additional($0) } }
    }

    static func groups(_ urls: [URL], driveC: URL, query: String) -> [Group] {
        let terms = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let base = driveC.standardizedFileURL.path + "/"
        let matches = Set(urls).filter { url in
            terms.allSatisfy { path(url, driveC: driveC).localizedCaseInsensitiveContains($0) }
        }
        let grouped = Dictionary(grouping: matches) { url -> String in
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(base) else { return url.deletingLastPathComponent().path }
            let parts = String(path.dropFirst(base.count)).split(separator: "/").map(String.init)
            let lower = parts.map { $0.lowercased() }
            var depth = 1
            if ["program files", "program files (x86)", "programdata"].contains(lower.first ?? "") { depth = 2 }
            if lower.first == "users", lower.count > 4, lower[2] == "appdata" {
                depth = lower[4] == "programs" ? 6 : 5
            }
            return driveC.appendingPathComponent(parts.prefix(min(depth, max(0, parts.count - 1))).joined(separator: "/")).path
        }
        return grouped.map { directory, files in
            Group(id: directory, title: path(URL(fileURLWithPath: directory), driveC: driveC),
                  files: files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending })
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}
