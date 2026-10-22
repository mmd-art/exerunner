import Foundation

/// A view of already-discovered EXEs, not a second filesystem crawler.
enum ExecutableTree {
    struct Node: Identifiable {
        let url: URL
        let children: [Node]
        let executable: Bool
        var id: String { url.path }
        var count: Int { executable ? 1 : children.reduce(0) { $0 + $1.count } }
    }

    static func systemUtility(_ url: URL, driveC: URL) -> Bool {
        let path = ExecutableDiscovery.path(url, driveC: driveC).lowercased()
        return ["program files", "program files (x86)"].contains { root in
            ["internet explorer", "windows media player", "windows nt"].contains {
                path.hasPrefix("c:\\\(root)\\\($0)\\")
            }
        }
    }

    static func matches(_ url: URL, driveC: URL, query: String) -> Bool {
        query.split(whereSeparator: { $0.isWhitespace }).allSatisfy {
            ExecutableDiscovery.path(url, driveC: driveC).localizedCaseInsensitiveContains($0)
        }
    }

    static func roots(_ urls: [URL], driveC: URL, query: String = "") -> [Node] {
        let base = driveC.standardizedFileURL.path + "/"
        let files = Set(urls.map(\.standardizedFileURL)).filter { $0.path.hasPrefix(base) && matches($0, driveC: driveC, query: query) }
        func children(_ directory: URL, _ files: [URL]) -> [Node] {
            let prefix = directory.path + "/"
            var subdirectories: [String: [URL]] = [:]
            var result: [Node] = []
            for file in files {
                let rest = file.path.dropFirst(prefix.count)
                if let slash = rest.firstIndex(of: "/") {
                    subdirectories[String(rest[..<slash]), default: []].append(file)
                } else { result.append(Node(url: file, children: [], executable: true)) }
            }
            for (name, descendants) in subdirectories {
                let folder = directory.appendingPathComponent(name)
                result.append(Node(url: folder, children: children(folder, descendants), executable: false))
            }
            return result.sorted {
                if $0.executable != $1.executable { return !$0.executable }
                return $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
            }
        }
        return children(driveC.standardizedFileURL, Array(files))
    }
}
