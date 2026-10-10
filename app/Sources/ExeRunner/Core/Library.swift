import Foundation

struct LibraryItem: Codable, Identifiable, Hashable {
    enum Kind: String, Codable { case launcher, program, game }

    enum Graphics: String, Codable, CaseIterable, Identifiable {
        case automatic, dxvk, wine
        var id: String { rawValue }
        var title: String {
            switch self {
            case .automatic: t("Авто (D3DMetal)")
            case .dxvk: "DXVK (Vulkan)"
            case .wine: t("Встроенная в Wine")
            }
        }
    }

    /// WINEDEBUG for a launch, that is what wine writes to the log. Presets from frankea/Whisky's
    /// WineDebugPreset.swift (GPL-3.0-or-later).
    enum Logging: String, Codable, CaseIterable, Identifiable {
        case normal, crash, dllLoad, verbose
        var id: String { rawValue }
        var title: String {
            switch self {
            case .normal: t("Обычный (ошибки)")
            case .crash: t("Вылеты: исключения и потоки")
            case .dllLoad: t("Загрузка DLL")
            case .verbose: t("Всё подряд (медленно, огромный)")
            }
        }
        var wineDebug: String {
            switch self {
            case .normal: "fixme-all"
            case .crash: "+seh,+tid,+pid,+timestamp,fixme-all"
            case .dllLoad: "+loaddll,+module,+tid,+pid,fixme-all"
            case .verbose: "+all"
            }
        }
    }

    var id: String
    var name: String
    var kind: Kind
    var bottle: String
    /// A Windows path inside the bottle (C:\...) or a Mac path run as is
    var executable: String
    var arguments: [String] = []
    var recipeID: String?
    var steamAppID: Int?
    var artwork: String?
    var graphics: Graphics = .automatic
    /// Apply what the compatibility database recommends for this game
    var useRecommended = true
    var metalFX = true
    var raytracing = false
    var performanceHUD = false
    var extraEnvironment: [String: String] = [:]
    /// LC_ALL and LANG for the program, such as ru_RU.UTF-8; nil leaves the recipe's or the Mac's
    var locale: String?
    var logging = Logging.normal
    /// The user's own DLL overrides for the item's programs (dll -> mode; empty disables)
    var dllOverrides: [String: String] = [:]

    init(id: String, name: String, kind: Kind, bottle: String, executable: String,
         arguments: [String] = [], recipeID: String? = nil, steamAppID: Int? = nil, artwork: String? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.bottle = bottle
        self.executable = executable
        self.arguments = arguments
        self.recipeID = recipeID
        self.steamAppID = steamAppID
        self.artwork = artwork
    }

    /// Fields added later decode to their defaults instead of failing old files.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decode(Kind.self, forKey: .kind)
        bottle = try c.decode(String.self, forKey: .bottle)
        executable = try c.decode(String.self, forKey: .executable)
        arguments = try c.decodeIfPresent([String].self, forKey: .arguments) ?? []
        recipeID = try c.decodeIfPresent(String.self, forKey: .recipeID)
        steamAppID = try c.decodeIfPresent(Int.self, forKey: .steamAppID)
        artwork = try c.decodeIfPresent(String.self, forKey: .artwork)
        graphics = try c.decodeIfPresent(Graphics.self, forKey: .graphics) ?? .automatic
        useRecommended = try c.decodeIfPresent(Bool.self, forKey: .useRecommended) ?? true
        metalFX = try c.decodeIfPresent(Bool.self, forKey: .metalFX) ?? true
        raytracing = try c.decodeIfPresent(Bool.self, forKey: .raytracing) ?? false
        performanceHUD = try c.decodeIfPresent(Bool.self, forKey: .performanceHUD) ?? false
        extraEnvironment = try c.decodeIfPresent([String: String].self, forKey: .extraEnvironment) ?? [:]
        locale = try c.decodeIfPresent(String.self, forKey: .locale)
        logging = try c.decodeIfPresent(Logging.self, forKey: .logging) ?? .normal
        dllOverrides = try c.decodeIfPresent([String: String].self, forKey: .dllOverrides) ?? [:]
    }

    var executableName: String {
        executable.split(whereSeparator: { $0 == "\\" || $0 == "/" }).last.map(String.init) ?? executable
    }

    var isSteamGame: Bool { steamAppID != nil }
}

enum LibraryStore {
    static func load() -> [LibraryItem] {
        guard let data = try? Data(contentsOf: Paths.libraryFile) else { return [] }
        return (try? JSONDecoder().decode([LibraryItem].self, from: data)) ?? []
    }

    static func save(_ items: [LibraryItem]) {
        do {
            try Paths.ensure(Paths.support)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(items).write(to: Paths.libraryFile, options: .atomic)
        } catch {
            NSLog("library not saved: \(error)")
        }
    }
}

/// Games installed by the Windows Steam client in a bottle, read from its manifests in every
/// library folder the client knows.
enum SteamLibrary {
    struct Game {
        let appID: Int
        let name: String
        /// The game's folder as Windows sees it: <library>\steamapps\common\<installdir>
        let installDir: String
        let artwork: URL?
        /// Its .exe files, found in its folder
        let executables: [String]
    }

    /// Steamworks Common Redistributables and the Steam Linux Runtimes: tools, not games
    static let ignored: Set<Int> = [228980, 1_070_560, 1_391_110, 1_628_350]

    static let windowsRoot = "C:\\Program Files (x86)\\Steam"

    static func root(in bottle: Bottle) -> URL {
        bottle.driveC.appendingPathComponent("Program Files (x86)/Steam", isDirectory: true)
    }

    /// Library folders as Windows paths, Steam's own first. libraryfolders.vdf lists them: under
    /// "0" { "path" ... } now, as "1" "D:\\Games" in older clients.
    static func libraryFolders(in bottle: Bottle) -> [String] {
        var folders = [windowsRoot]
        for file in ["steamapps/libraryfolders.vdf", "config/libraryfolders.vdf"] {
            guard let text = try? String(contentsOf: root(in: bottle).appendingPathComponent(file), encoding: .utf8) else { continue }
            for (key, entry) in VDF.parse(text)["libraryfolders"]?.entries ?? [] where Int(key) != nil {
                guard var path = entry["path"]?.string ?? entry.string, path.contains(":") else { continue }
                while path.hasSuffix("\\") { path.removeLast() }
                if !folders.contains(where: { WindowsPath.same($0, path) }) { folders.append(path) }
            }
        }
        return folders
    }

    static func games(in bottle: Bottle) -> [Game] {
        let steam = root(in: bottle)
        var games: [Game] = []
        for library in libraryFolders(in: bottle) {
            guard let steamapps = bottle.hostURL(forWindowsPath: library + "\\steamapps"),
                  let names = try? FileManager.default.contentsOfDirectory(atPath: steamapps.path) else { continue }
            for name in names where name.hasPrefix("appmanifest_") && name.hasSuffix(".acf") {
                guard let text = try? String(contentsOf: steamapps.appendingPathComponent(name), encoding: .utf8),
                      let manifest = VDF.parse(text)["AppState"],
                      let appID = manifest["appid"]?.string.flatMap(Int.init), !ignored.contains(appID),
                      !games.contains(where: { $0.appID == appID }),
                      let state = manifest["StateFlags"]?.string.flatMap(Int.init), state & 4 != 0,
                      let title = manifest["name"]?.string,
                      let folder = manifest["installdir"]?.string, isFolderName(folder) else { continue }
                let installDir = "\(library)\\steamapps\\common\\\(folder)"
                var isDirectory: ObjCBool = false
                guard let host = bottle.hostURL(forWindowsPath: installDir),
                      FileManager.default.fileExists(atPath: host.path, isDirectory: &isDirectory), isDirectory.boolValue
                else { continue }
                games.append(Game(appID: appID, name: title, installDir: installDir, artwork: artwork(appID: appID, steam: steam),
                                  executables: executables(in: host)))
            }
        }
        return games.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// A game's own programs, so settings can find them by name when Steam starts them: .exe files
    /// near the top of its folder and in Unreal's <Project>/Binaries/Win64, leaving out installers,
    /// crash reporters, redistributables and the engine's own helpers
    static func executables(in folder: URL) -> [String] {
        let skippedFolders: Set<String> = ["engine", "_commonredist", "commonredist", "redist", "redistributables", "directx",
                                           "dotnet", "vcredist", "support", "__installer", "installer", "installers",
                                           "content", "paks", "movies", "saved", "logs", "crashes", "shadercache"]
        let skippedNames = ["unins", "setup", "redist", "crashreport", "crashhandler", "crashpad", "prereq", "dxweb", "dotnetfx"]
        guard let walk = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isDirectoryKey],
                                                        options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var names: [String] = []
        for case let url as URL in walk {
            let name = url.lastPathComponent
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                if walk.level >= 4 || skippedFolders.contains(name.lowercased()) { walk.skipDescendants() }
                continue
            }
            let lower = name.lowercased()
            guard lower.hasSuffix(".exe"), !skippedNames.contains(where: lower.contains),
                  !names.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { continue }
            names.append(name)
            if names.count >= 12 { break }
        }
        return names
    }

    /// Repacks ship forged manifests: installdir has to name one folder, nothing that climbs out
    static func isFolderName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains { $0 == "/" || $0 == "\\" || $0 == "\0" }
    }

    /// The vertical cover Steam caches for its own library, or failing that a header. Current
    /// clients keep them in librarycache/<appid>/<hash>/, older ones as librarycache/<appid>_*.jpg.
    static func artwork(appID: Int, steam: URL) -> URL? {
        let cache = steam.appendingPathComponent("appcache/librarycache", isDirectory: true)
        var files = FileManager.default.enumerator(at: cache.appendingPathComponent("\(appID)", isDirectory: true),
                                                   includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
        files += ["\(appID)_library_600x900.jpg", "\(appID)_header.jpg"].map { cache.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        files = files.filter { ["jpg", "png"].contains($0.pathExtension.lowercased()) }
        for wanted in ["library_600x900", "library_capsule", "header", "library_hero"] {
            if let hit = files.first(where: { $0.lastPathComponent.contains(wanted) }) { return hit }
        }
        return nil
    }
}
