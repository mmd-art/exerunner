import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var settings: AppSettings {
        didSet { if settings != oldValue { settings.save() } }
    }
    @Published private(set) var engine: Engine?
    @Published private(set) var engineVersion: String?
    @Published private(set) var recipes: [Recipe] = []
    @Published private(set) var items: [LibraryItem] = []
    @Published private(set) var steamGames: [LibraryItem] = []
    @Published private(set) var bottleSettings: [String: BottleSettings] = [:]
    @Published private(set) var rosettaInstalled = false
    @Published private(set) var system = SystemInfo.current()
    @Published private(set) var gameProfiles: [GameProfile] = []
    private(set) var compatSource = ""
    @Published var activity: String?
    @Published var errorMessage: String?
    private var activityToken = 0
    private var icons: [String: NSImage] = [:]
    private var missingIcons: Set<String> = []

    // MARK: what runs (AppState+Running.swift)

    /// Items whose launch is in progress: the bottle being readied, then the program's own run
    @Published var launching: Set<String> = []
    /// Items with processes in their bottle right now
    @Published var active: Set<String> = []
    /// Games handed to a launcher that have not shown up yet
    @Published var starting: Set<String> = []
    /// The latest finding in each item's output, kept until its next launch
    @Published var diagnoses: [String: CrashDiagnosis] = [:]
    var startingDeadlines: [String: Date] = [:]
    var processTable: [WineProcesses.Entry] = []
    /// Steam games' folders as Windows paths, by item id
    var steamFolders: [String: String] = [:]
    /// Steam games' .exe files found in their folders, by item id
    var steamExecutables: [String: [String]] = [:]
    /// When each item's last launch began, to tell its crash reports from older ones
    var launchTimes: [String: Date] = [:]
    /// Each item's last launch output
    var logSegments: [String: LogSegment] = [:]
    /// Games that write into their launcher's log: launcher item id and where the game began
    var followsClient: [String: (clientID: String, offset: UInt64)] = [:]
    /// Launcher runs started for a game, which a headless launch waits for
    var clientRuns: [String: Task<Int32, Error>] = [:]
    /// Stopped from the app: the end of their run is not a crash
    var stoppedByUser: Set<String> = []
    /// The last audio check in each bottle
    var audioTests: [String: AudioTestResult] = [:]
    /// Launchers being installed: their bottle is set up for them before their installer runs
    var installing: [LibraryItem] = []
    var watcher: Task<Void, Never>?

    var running: Set<String> { launching.union(active).union(starting) }

    init() {
        settings = AppSettings.load()
        recipes = Recipe.loadAll()
        items = LibraryStore.load()
        bottleSettings = BottleSettingsStore.load()
        engine = Engine.locate(settings)
        (compatSource, gameProfiles) = CompatDatabase.load()
    }

    // MARK: library

    var bottlesRoot: URL { settings.bottlesRoot }

    /// Saved items, then Steam games that have no saved settings of their own
    var allItems: [LibraryItem] { items + steamGames.filter { game in !items.contains { $0.id == game.id } } }
    /// What a bottle's settings are made for: the library and what is being installed
    var bottleItems: [LibraryItem] { allItems + installing.filter { new in !items.contains { $0.id == new.id } } }
    var launchers: [LibraryItem] { items.filter { $0.kind == .launcher } }
    var games: [LibraryItem] { allItems.filter { $0.kind == .game } }
    var programs: [LibraryItem] { items.filter { $0.kind == .program } }

    func recipe(_ id: String?) -> Recipe? { id.flatMap { id in recipes.first { $0.id == id } } }
    func isInstalled(_ recipe: Recipe) -> Bool { items.contains { $0.recipeID == recipe.id && $0.kind != .game } }
    func isSaved(_ item: LibraryItem) -> Bool { items.contains { $0.id == item.id } }
    func item(_ id: String) -> LibraryItem? { allItems.first { $0.id == id } }

    func refresh() async {
        system = SystemInfo.current()
        recipes = Recipe.loadAll()
        rosettaInstalled = await Rosetta.isInstalled()
        engine = Engine.locate(settings)
        await engine?.clearQuarantine()
        if rosettaInstalled, let engine {
            engineVersion = await engine.version()
        } else {
            engineVersion = nil
        }
        refreshGames()
    }

    func refreshGames() {
        var found: [LibraryItem] = []
        var folders: [String: String] = [:]
        var executables: [String: [String]] = [:]
        for launcher in steamClients {
            let bottle = Bottle(name: launcher.bottle, root: bottlesRoot)
            for game in SteamLibrary.games(in: bottle) {
                // the same game in a second Steam bottle is an item of its own
                var id = "steam-\(game.appID)"
                if found.contains(where: { $0.id == id }) { id += "@\(launcher.bottle)" }
                folders[id] = game.installDir
                executables[id] = game.executables
                found.append(LibraryItem(id: id, name: game.name, kind: .game, bottle: launcher.bottle,
                                         executable: launcher.executable, arguments: ["steam://rungameid/\(game.appID)"],
                                         recipeID: launcher.recipeID, steamAppID: game.appID, artwork: game.artwork?.path))
            }
        }
        steamGames = found
        steamFolders = folders
        steamExecutables = executables
    }

    func upsert(_ item: LibraryItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = item } else { items.append(item) }
        LibraryStore.save(items)
    }

    func remove(_ item: LibraryItem) {
        items.removeAll { $0.id == item.id }
        Shortcuts.remove(for: item)
        LibraryStore.save(items)
        refreshGames()
    }

    /// Launchers that list Steam games (a saved Steam game carries the same recipe, but is a game)
    var steamClients: [LibraryItem] {
        items.filter { $0.kind == .launcher && recipe($0.recipeID)?.discoversSteamGames == true }
    }

    /// The Steam client that owns a Steam game: the launcher in its bottle that lists games
    func steamClient(for item: LibraryItem) -> LibraryItem? {
        steamClients.first { $0.bottle == item.bottle }
    }

    // MARK: bottles

    func settings(forBottle name: String) -> BottleSettings { bottleSettings[name] ?? BottleSettings() }

    func updateBottle(_ name: String, _ change: (inout BottleSettings) -> Void) {
        var value = settings(forBottle: name)
        change(&value)
        guard value != bottleSettings[name] else { return }
        bottleSettings[name] = value
        BottleSettingsStore.save(bottleSettings)
    }

    /// Recipes whose program settings apply in a bottle: its items' own, and the Rockstar
    /// launcher's where one of its games or its folder is (Steam starts it for those games)
    func recipes(in bottle: String) -> [Recipe] {
        var result: [Recipe] = []
        let inBottle = bottleItems.filter { $0.bottle == bottle }
        for item in inBottle {
            if let recipe = recipe(item.recipeID), !result.contains(recipe) { result.append(recipe) }
        }
        if let rockstar = recipe("rockstar"), !result.contains(rockstar),
           Launchers.runsRockstarLauncher(in: Bottle(name: bottle, root: bottlesRoot), steamAppIDs: inBottle.compactMap(\.steamAppID)) {
            result.append(rockstar)
        }
        return result
    }

    // MARK: per-program settings

    /// The compatibility database's entry: by Steam app id for Steam games, else by .exe name
    func profile(for item: LibraryItem) -> GameProfile? {
        if let appID = item.steamAppID { return gameProfiles.first { $0.steamAppID == appID } }
        let exe = item.executableName.lowercased()
        return gameProfiles.first { $0.exeNames.contains { $0.lowercased() == exe } }
    }

    /// The executables an item covers: its own .exe, or for a Steam game the ones the database
    /// knows and those found in its folder (Steam starts the game itself, so settings have to
    /// find it by name)
    func executables(of item: LibraryItem) -> [String] {
        guard item.isSteamGame else { return [item.executableName] }
        var names = profile(for: item)?.exeNames ?? []
        for name in steamExecutables[item.id] ?? [] where !names.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            names.append(name)
        }
        return names
    }

    func canTargetExecutables(_ item: LibraryItem) -> Bool { !executables(of: item).isEmpty }

    func effectiveGraphics(_ item: LibraryItem) -> LibraryItem.Graphics {
        if item.graphics != .automatic { return item.graphics }
        if item.useRecommended, let profile = profile(for: item) { return profile.recommended.graphics }
        return .automatic
    }

    /// Executables in a bottle that draw through DXVK: the recipes' lists, the Chromium helpers
    /// games ship, and programs set to it
    func dxvkExecutables(in bottle: String) -> Set<String> {
        var names = Set(recipes(in: bottle).flatMap(\.dxvkExecutables) + Launchers.chromiumHelpers)
        for item in bottleItems where item.bottle == bottle && effectiveGraphics(item) == .dxvk {
            names.formUnion(executables(of: item))
        }
        return names
    }

    /// Executables that keep wine's own DLLs instead of D3DMetal
    func skipList(in bottle: String) -> Set<String> {
        var names = dxvkExecutables(in: bottle)
        for item in bottleItems where item.bottle == bottle && effectiveGraphics(item) == .wine {
            names.formUnion(executables(of: item))
        }
        return names
    }

    /// program -> dll -> mode: DXVK's DLLs for programs on DXVK, the recipes' own lines, then
    /// the database's overrides
    func dllOverrides(in bottle: String, engine: Engine) -> [String: [String: String]] {
        var result: [String: [String: String]] = [:]
        let dxvk = BottleManager.dxvkLibraries(engine)
        for exe in dxvkExecutables(in: bottle) {
            for dll in dxvk { result[exe, default: [:]][dll] = "native" }
        }
        for recipe in recipes(in: bottle) {
            for (exe, dlls) in recipe.dllOverrides { result[exe, default: [:]].merge(dlls) { $1 } }
        }
        for exe in Launchers.chromiumHelpers {
            for dll in Launchers.nvidiaLibraries { result[exe, default: [:]][dll] = "" }
        }
        // without DLSS through MetalFX a game does not find NVIDIA's libraries at all, so it does
        // not load NVIDIA Streamline either, whose hooks some games crash in on D3DMetal
        for item in bottleItems where item.bottle == bottle && !item.metalFX {
            for exe in executables(of: item) {
                for dll in Launchers.nvidiaLibraries { result[exe, default: [:]][dll] = "" }
            }
        }
        for item in bottleItems where item.bottle == bottle && item.useRecommended {
            guard let profile = profile(for: item) else { continue }
            for exe in executables(of: item) {
                for (dll, mode) in profile.recommended.dllOverrides { result[exe, default: [:]][dll] = mode }
            }
        }
        for item in bottleItems where item.bottle == bottle && !item.dllOverrides.isEmpty {
            for exe in executables(of: item) { result[exe, default: [:]].merge(item.dllOverrides) { $1 } }
        }
        return result
    }

    /// Variables of one item: the database's recommendation, its switches, then the user's own
    func itemEnvironment(_ item: LibraryItem) -> [String: String] {
        var env: [String: String] = [:]
        if item.useRecommended, let profile = profile(for: item) { env.merge(profile.recommended.environment) { $1 } }
        if !item.metalFX { env["D3DM_ENABLE_METALFX"] = "0" }
        if item.raytracing { env["D3DM_SUPPORT_DXR"] = "1" }
        if item.performanceHUD { env["MTL_HUD_ENABLED"] = "1" }
        env.merge(item.extraEnvironment) { $1 }
        return env
    }

    /// What the launch itself gets: the recipe's variables, the chosen language, the item's own,
    /// and the log level
    func environment(for item: LibraryItem) -> [String: String] {
        var env = recipe(item.recipeID)?.environment ?? [:]
        if let locale = item.locale {
            env["LC_ALL"] = locale
            env["LANG"] = locale
        }
        env.merge(itemEnvironment(item)) { $1 }
        if item.logging != .normal || env["WINEDEBUG"] == nil { env["WINEDEBUG"] = item.logging.wineDebug }
        return env
    }

    /// program -> variables, for cxcompatdb.so to set inside processes a launcher starts
    func perProgramEnvironment(in bottle: String) -> [String: [String: String]] {
        var result: [String: [String: String]] = [:]
        for item in bottleItems where item.bottle == bottle {
            let env = itemEnvironment(item)
            guard !env.isEmpty else { continue }
            for exe in executables(of: item) { result[exe, default: [:]].merge(env) { $1 } }
        }
        return result
    }

    /// Windows components the database asks for, for every program in the bottle
    func winetricksVerbs(in bottle: String) -> [String] {
        var verbs: [String] = []
        for item in bottleItems where item.bottle == bottle && item.useRecommended {
            for verb in profile(for: item)?.recommended.winetricks ?? [] where !verbs.contains(verb) { verbs.append(verb) }
        }
        return verbs
    }

    // MARK: installing

    @discardableResult
    func install(_ recipe: Recipe) async -> Bool {
        guard let engine else { errorMessage = "Движок не найден"; return false }
        let token = beginActivity("Устанавливаю \(recipe.name)…")
        defer { endActivity(token) }
        // installers often start their launcher at the end (EA does): it has to find the bottle
        // ready, its web helpers on DXVK and off D3DMetal, as a launch from the app would
        let pending = Installer.item(for: recipe, executable: recipe.executable ?? "")
        installing.append(pending)
        defer { installing.removeAll { $0.id == pending.id } }
        do {
            let bottle = Bottle(name: recipe.bottle, root: bottlesRoot)
            let log = Paths.logFile("install-\(recipe.id)")
            reporter(token)("Готовлю бутылку «\(recipe.bottle)»…")
            let compat = try await prepareBottle(bottle, log: log, engine: engine, progress: reporter(token))
            let item = try await Installer.install(recipe, engine: engine, bottlesRoot: bottlesRoot, log: log,
                                                   environment: ["EXERUNNER_COMPAT_FILE": compat.path], progress: reporter(token))
            upsert(item)
            refreshGames()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func addPortable(_ file: URL, name: String) {
        upsert(detected(LibraryItem(id: UUID().uuidString, name: name, kind: .program, bottle: "programs", executable: file.path)))
    }

    func runInstaller(_ file: URL, bottle: String) async -> [URL] {
        guard let engine else { errorMessage = "Движок не найден"; return [] }
        let token = beginActivity("Запускаю установщик…")
        defer { endActivity(token) }
        do {
            return try await Installer.runInstaller(file, bottle: Bottle(name: bottle, root: bottlesRoot), engine: engine,
                                                    progress: reporter(token))
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    func addInstalled(_ exe: URL, name: String, bottle: String) {
        let path = Bottle(name: bottle, root: bottlesRoot).windowsPath(for: exe) ?? exe.path
        upsert(detected(LibraryItem(id: UUID().uuidString, name: name, kind: .program, bottle: bottle, executable: path)))
    }

    /// A program the user adds that turns out to be a known launcher gets that launcher's recipe:
    /// its variables, its helpers on DXVK and, for Steam, its games in the library
    private func detected(_ item: LibraryItem) -> LibraryItem {
        guard let id = Launchers.recipeID(forExecutable: item.executable), let recipe = recipe(id) else { return item }
        var item = item
        item.recipeID = recipe.id
        if recipe.kind == .launcher { item.kind = .launcher }
        return item
    }

    /// The launcher an item looks like, when it is not linked to one yet
    func detectedLauncher(for item: LibraryItem) -> Recipe? {
        guard item.recipeID == nil, !item.isSteamGame else { return nil }
        return Launchers.recipeID(forExecutable: item.executable).flatMap(recipe)
    }

    // MARK: setup

    @discardableResult
    func importD3DMetal(from url: URL) async -> String? {
        guard let engine else { errorMessage = "Сначала нужен движок"; return nil }
        let token = beginActivity("Подключаю D3DMetal…")
        defer { endActivity(token) }
        do {
            let version = try await D3DMetalImporter.importPayload(from: url, into: engine, progress: reporter(token))
            self.engine = Engine.locate(settings)
            return version
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Drops the user's own D3DMetal; the app's built-in one takes over again
    func removeImportedD3DMetal() {
        try? FileManager.default.removeItem(at: Paths.d3dmetal)
        engine = Engine.locate(settings)
    }

    func installRosetta() async {
        let token = beginActivity("Устанавливаю Rosetta…")
        defer { endActivity(token) }
        let result = await Rosetta.install()
        rosettaInstalled = await Rosetta.isInstalled()
        if !rosettaInstalled, !result.output.contains("User canceled") {
            errorMessage = "Rosetta не установилась: \(result.output)"
        }
        if rosettaInstalled, let engine { engineVersion = await engine.version() }
    }

    func setEngine(_ url: URL) async {
        guard Engine(root: url).isValid else {
            errorMessage = "В папке «\(url.lastPathComponent)» нет движка (bin/wine)"
            return
        }
        settings.enginePath = url.path
        await refresh()
    }

    func setBottlesRoot(_ url: URL) {
        settings.bottlesPath = url.path
        refreshGames()
    }

    func completeOnboarding() { settings.onboardingCompleted = true }
    func restartOnboarding() { settings.onboardingCompleted = false }

    // MARK: icons, shortcuts and Finder

    /// The program's own icon from its .exe, read once per item
    func icon(for item: LibraryItem) -> NSImage? {
        if let icon = icons[item.id] { return icon }
        if missingIcons.contains(item.id) { return nil }
        let bottle = Bottle(name: item.bottle, root: bottlesRoot)
        guard let exe = bottle.hostURL(forWindowsPath: item.executable), let icon = PEIcon.extract(from: exe) else {
            missingIcons.insert(item.id)
            return nil
        }
        icons[item.id] = icon
        return icon
    }

    func hasShortcut(_ item: LibraryItem) -> Bool { Shortcuts.exists(for: item) }

    func toggleShortcut(_ item: LibraryItem) {
        do {
            if Shortcuts.exists(for: item) {
                Shortcuts.remove(for: item)
            } else {
                try Shortcuts.create(for: item, icon: item.artwork.flatMap(NSImage.init(contentsOfFile:)) ?? icon(for: item))
            }
            objectWillChange.send()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reveal(_ item: LibraryItem) {
        let bottle = Bottle(name: item.bottle, root: bottlesRoot)
        if let folder = steamFolders[item.id].flatMap(bottle.hostURL(forWindowsPath:)),
           FileManager.default.fileExists(atPath: folder.path) {
            NSWorkspace.shared.open(folder)
        } else if let exe = bottle.hostURL(forWindowsPath: item.executable), FileManager.default.fileExists(atPath: exe.path) {
            NSWorkspace.shared.activateFileViewerSelecting([exe])
        } else {
            NSWorkspace.shared.open(bottle.url)
        }
    }

    func openLog(_ item: LibraryItem) {
        if let log = segment(for: item.id)?.url, FileManager.default.fileExists(atPath: log.path) {
            NSWorkspace.shared.open(log)
        } else {
            try? Paths.ensure(Paths.logs)
            NSWorkspace.shared.open(Paths.logs)
        }
    }

    // MARK: activity

    func beginActivity(_ text: String) -> Int {
        activityToken += 1
        activity = text
        return activityToken
    }

    func endActivity(_ token: Int) {
        if token == activityToken { activity = nil }
    }

    func reporter(_ token: Int) -> @Sendable (String) -> Void {
        { text in
            Task { @MainActor in
                if token == self.activityToken { self.activity = text }
            }
        }
    }

    // MARK: self-test

    func report() -> String {
        var lines = ["\(AppInfo.name) self-test"]
        lines.append("mac: \(system.chip), Apple Silicon \(system.isAppleSilicon), macOS \(system.macOS), \(system.memoryGB) GB RAM, \(system.freeDiskGB) GB free")
        lines.append("rosetta: \(rosettaInstalled)")
        if let engine {
            lines.append("engine: \(engine.root.path) \(engineVersion ?? "?")\(engine.isPortable ? " (portable)" : "")")
            lines.append("  d3dmetal from: \(engine.gptk.path)")
            lines.append("  compat \(engine.hasCompatModule), dxvk \(engine.hasDXVK), moltenvk \(engine.hasMoltenVK), mono+gecko \(engine.hasMonoAndGecko), d3dmetal \(engine.d3dmetalVersion ?? "none"), discord bridge \(engine.hasDiscordBridge)")
        } else {
            lines.append("engine: not found")
        }
        lines.append("bottles: \(bottlesRoot.path)")
        lines.append("recipes: " + recipes.map { "\($0.id)[\($0.kind.rawValue), \($0.status.rawValue)]" }.joined(separator: " "))
        lines.append("library: " + items.map { "\($0.name) (\($0.kind.rawValue), bottle \($0.bottle))" }.joined(separator: "; "))
        lines.append("steam games: " + steamGames.map { "\($0.name)\($0.artwork == nil ? "" : " +cover") in \(steamFolders[$0.id] ?? "?")" }.joined(separator: "; "))
        for launcher in steamClients {
            lines.append("steam libraries in \(launcher.bottle): \(SteamLibrary.libraryFolders(in: Bottle(name: launcher.bottle, root: bottlesRoot)))")
        }
        for game in steamGames {
            let report = UnrealCrashReport.latest(in: crashReportRoots(for: game), since: nil)
            lines.append("  \(game.name): exe \(executables(of: game))" + (report.map { ", last Unreal crash \($0.date): \($0.error)" } ?? ""))
        }
        lines.append("compat db: \(gameProfiles.count) games (\(compatSource))")
        lines.append("crash patterns: \(CrashClassifier.shared.count) (\(CrashClassifier.shared.source))")
        for item in allItems {
            guard let profile = profile(for: item) else { continue }
            lines.append("  \(item.name) -> \(profile.title): \(profile.rating), graphics \(effectiveGraphics(item).rawValue), exe \(executables(of: item)), winetricks \(profile.recommended.winetricks)")
        }
        for bottle in Set(allItems.map(\.bottle)).sorted() {
            lines.append("bottle \(bottle): recipes \(recipes(in: bottle).map(\.id)), dxvk \(dxvkExecutables(in: bottle).sorted()), d3dmetal off \(skipList(in: bottle).sorted()), winetricks \(winetricksVerbs(in: bottle)), \(settings(forBottle: bottle))")
            if let engine {
                let disabled = dllOverrides(in: bottle, engine: engine).filter { $0.value.values.contains("") }.keys.sorted()
                lines.append("  dll off for: \(disabled)")
            }
            let problems = PrefixCheck.problems(in: Bottle(name: bottle, root: bottlesRoot))
            lines.append("  prefix: \(problems.isEmpty ? "ok" : problems.map(PrefixCheck.describe).joined(separator: "; "))")
        }
        lines.append("wine processes: \(processTable.count)" + (processTable.isEmpty ? "" : " " + processTable.map { "\($0.name)@\(URL(fileURLWithPath: $0.prefix).lastPathComponent)" }.joined(separator: ", ")))
        lines.append("running items: \(running.sorted())")
        return lines.joined(separator: "\n")
    }
}
