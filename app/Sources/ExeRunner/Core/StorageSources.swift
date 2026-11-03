import Foundation

/// Immutable model input; discovery and scanning never refresh Wine, change settings or write caches.
enum StorageSources {
    struct Item: Sendable {
        var id: String
        var bottle: String
        var executable: String
        var steamGame: Bool
        var steamClient: Bool
        var gameFolder: String?
        var explicitFolder: URL?
    }
    struct Input: Sendable {
        var items: [Item]
        var bottlesRoot: URL
        var shared: [StorageScan.Claim]
        var unavailableSources = false
    }
    struct Plan { var claims: [StorageScan.Claim]; var unknown: Set<String>; var folders: [String: String]; var incomplete: Bool }

    /// Only real C directories are automatic sources. No Z drive, junctions or home links.
    static func windowsURL(_ path: String, in drive: URL, cancelled: () -> Bool = { Task.isCancelled }) -> URL? {
        let normalized = path.replacingOccurrences(of: "/", with: "\\")
        guard normalized.lowercased().hasPrefix("c:\\"), !normalized.contains("\0") else { return nil }
        let parts = String(normalized.dropFirst(3)).split(separator: "\\", omittingEmptySubsequences: true).map(String.init)
        guard !parts.isEmpty, parts.allSatisfy({ $0 != "." && $0 != ".." && !$0.contains(":") }) else { return nil }
        var current = StorageScan.canonical(drive)
        guard StorageScan.realDirectory(current) else { return nil }
        for (i, part) in parts.enumerated() {
            guard !cancelled(), StorageScan.realDirectory(current), let names = StorageScan.names(in: current, cancelled: cancelled) else { return nil }
            let matches = names.filter { $0.caseInsensitiveCompare(part) == .orderedSame }
            guard let actual = names.first(where: { $0 == part }) ?? (matches.count == 1 ? matches.first : nil) else { return nil }
            current.appendPathComponent(actual)
            if i < parts.count - 1 && !StorageScan.realDirectory(current) { return nil }
        }
        return current
    }
    /// Quoted Wine registry strings only. No expansion or execution of registry commands.
    static func installLocations(_ text: String, limit: Int = 512, cancelled: () -> Bool = { Task.isCancelled }) -> [String] {
        var inside = false, result: [String] = []
        for raw in text.split(separator: "\n") {
            if cancelled() || result.count >= limit { break }
            let line = String(raw)
            if line.hasPrefix("[") {
                let key = line.lowercased().replacingOccurrences(of: "\\\\", with: "\\")
                inside = key.contains("\\currentversion\\uninstall\\")
            } else if inside && line.lowercased().hasPrefix("\"installlocation\"=") {
                let value = String(line.dropFirst("\"InstallLocation\"=".count))
                guard value.hasPrefix("\""), value.hasSuffix("\""), value.count < 4096 else { continue }
                let path = String(value.dropFirst().dropLast()).replacingOccurrences(of: "\\\\", with: "\\")
                if path.lowercased().hasPrefix("c:\\"), !path.contains("%") { result.append(path) }
            }
        }
        return result
    }
    static func plan(_ input: Input, deadline: Date = Date().addingTimeInterval(30)) -> Plan {
        var claims = input.shared, unknown = Set<String>(), folders: [String: String] = [:]
        let expired = { Task.isCancelled || Date() >= deadline }
        var incomplete = input.unavailableSources || input.items.count > 2000
        var pending = Set(input.items.map(\.id))
        let groups = Dictionary(grouping: Array(input.items.prefix(2000)), by: \.bottle)
        for (name, items) in groups.sorted(by: { $0.key < $1.key }) {
            if expired() { incomplete = true; break }
            guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\") else {
                unknown.formUnion(items.map(\.id)); continue
            }
            let prefix = input.bottlesRoot.appendingPathComponent(name), drive = prefix.appendingPathComponent("drive_c")
            let owners = Set(items.map(\.id))
            claims.append(.init(id: "environment:" + prefix.path, kind: .environment, owners: owners, roots: [prefix]))
            var registered: [URL] = []
            for hive in ["system.reg", "user.reg"] {
                if expired() { incomplete = true; break }
                let file = prefix.appendingPathComponent(hive)
                if let text = StorageScan.text(file, limit: 32 * 1024 * 1024) {
                    let locations = installLocations(text, cancelled: expired)
                    if locations.count >= 512 { incomplete = true }
                    for location in locations {
                        if expired() { incomplete = true; break }
                        if let url = windowsURL(location, in: drive, cancelled: expired) { registered.append(url) }
                    }
                }
            }
            for item in items {
                if expired() { incomplete = true; break }
                pending.remove(item.id)
                let exe = windowsURL(item.executable, in: drive, cancelled: expired)
                var root: URL?
                if let explicit = item.explicitFolder, StorageScan.realDirectory(explicit) { root = explicit }
                else if item.steamGame { root = item.gameFolder.flatMap { windowsURL($0, in: drive, cancelled: expired) } }
                else if let exe {
                    root = registered.filter { candidate in
                        StorageScan.realDirectory(candidate) && StorageScan.contains(exe, in: candidate) &&
                        candidate.pathComponents.count > drive.pathComponents.count + 1 &&
                        !String(candidate.path.dropFirst(drive.path.count + 1)).lowercased().hasPrefix("windows/")
                    }.max { $0.path.count < $1.path.count }
                    if root == nil && item.steamClient { root = exe.deletingLastPathComponent() }
                    // A direct Games/<name> installation is an explicit container, not an EXE-parent guess.
                    if root == nil, let gameContainer = StorageScan.names(in: drive, cancelled: expired)?.first(where: { $0.caseInsensitiveCompare("Games") == .orderedSame }) {
                        let games = drive.appendingPathComponent(gameContainer)
                        if StorageScan.contains(exe, in: games) {
                            let parts = String(exe.path.dropFirst(games.path.count + 1)).split(separator: "/")
                            if parts.count >= 2 { root = games.appendingPathComponent(String(parts[0])) }
                        }
                    }
                }
                guard let folder = root, StorageScan.realDirectory(folder) else { unknown.insert(item.id); continue }
                folders[item.id] = folder.path
                claims.append(.init(id: "application:" + StorageScan.canonical(folder).path, kind: .application, owners: [item.id], roots: [folder]))
                if item.steamClient {
                    claims.append(.init(id: "steam-data:" + item.id, kind: .data, owners: [item.id],
                        roots: [folder.appendingPathComponent("steamapps"), folder.appendingPathComponent("userdata")]))
                    var caches = [folder.appendingPathComponent("appcache"), folder.appendingPathComponent("depotcache")]
                    let users = drive.appendingPathComponent("users")
                    if StorageScan.realDirectory(users), let names = StorageScan.names(in: users, cancelled: expired) {
                        for user in names { caches.append(users.appendingPathComponent(user + "/AppData/Local/Steam/htmlcache")) }
                    }
                    claims.append(.init(id: "cache:" + item.id, kind: .cache, owners: [item.id], roots: caches))
                }
            }
        }
        // Prefixes can survive removal of their last card. Count them once in the overview,
        // without pretending the remaining files belong to a different installed program.
        if let names = StorageScan.names(in: input.bottlesRoot, cancelled: expired) {
            if names.count > 2000 { incomplete = true }
            for name in names.prefix(2000) where groups[name] == nil {
                if expired() { incomplete = true; break }
                let prefix = input.bottlesRoot.appendingPathComponent(name)
                if StorageScan.realDirectory(prefix.appendingPathComponent("drive_c")),
                   StorageScan.regularFileExists(prefix.appendingPathComponent("system.reg")) {
                    claims.append(.init(id: "environment:" + prefix.path, kind: .environment, owners: [], roots: [prefix]))
                }
            }
        } else if FileManager.default.fileExists(atPath: input.bottlesRoot.path) {
            incomplete = true
        }
        unknown.formUnion(pending)
        return Plan(claims: claims, unknown: unknown, folders: folders, incomplete: incomplete || expired())
    }
    static func measure(_ input: Input) -> StorageScan.Snapshot {
        let deadline = Date().addingTimeInterval(30)
        let plan = plan(input, deadline: deadline)
        var result = StorageScan.run(plan.claims, maxSeconds: max(0, deadline.timeIntervalSinceNow))
        result.incomplete = result.incomplete || plan.incomplete
        result.unknownItems = plan.unknown
        result.selectedFolders = plan.folders
        return result
    }
}
