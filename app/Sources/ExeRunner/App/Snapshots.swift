import AppKit
import SwiftUI

/// `--snapshot <dir>` renders the main screens to PNG offscreen, without opening a window, so the
/// layout can be checked headless.
@MainActor
enum Snapshots {
    static func renderExecutableChoice(to dir: URL) async {
        var settings = AppSettings(); settings.language = .english
        let state = AppState(managesGameBoost: false, initialSettings: settings,
                             initialItems: [], initialBottleSettings: [:])
        let drive = URL(fileURLWithPath: "/synthetic/drive_c")
        let target = drive.appendingPathComponent("Vendor CAD/Version 10/bin/main.exe")
        let candidates = (0..<800).map { drive.appendingPathComponent("Vendor CAD/Version 10/bin/tool\($0).exe") }
            + [target, drive.appendingPathComponent("Vendor CAD/Version 10/bin/crash-helper.exe"),
               drive.appendingPathComponent("Program Files/Another program/main.exe")]
        try? Paths.ensure(dir)
        for (name, query) in [("exe-groups", ""), ("exe-search", "version 10 main"), ("exe-no-match", "missing-program") ] {
            await capture(name, AnyView(VStack(alignment: .leading, spacing: 18) {
                Text(t("Своя Windows-программа")).font(.title2.weight(.semibold))
                ExecutableChooser(candidates: candidates, driveC: drive,
                    chosen: .constant(query.isEmpty ? nil : target), browse: {}, cancel: {}, add: {}, query: query)
            }.padding(24)), state: state, to: dir, size: NSSize(width: 648, height: 530))
        }
    }

    static func renderHistory(to dir: URL) async {
        var settings = AppSettings(); settings.language = .english
        let game = LibraryItem(id: "preview-game", name: "Example game (synthetic)", kind: .game,
                               bottle: "preview", executable: "C:\\Game\\game.exe")
        let state = AppState(managesGameBoost: false, initialSettings: settings,
                             initialItems: [game], initialBottleSettings: [:])
        let now = Date()
        let target = SessionTarget(itemID: game.id, prefix: "/synthetic", name: game.name, kind: .game)
        var stopped = HistorySession(target: target, requested: now.addingTimeInterval(-3600),
            observed: now.addingTimeInterval(-3590), lastSeen: now.addingTimeInterval(-90),
            seconds: 3500, status: .stopped, lastUptime: 0, boot: "preview", deadline: 0)
        stopped.ended = stopped.lastSeen
        var crashed = stopped; crashed.id = UUID(); crashed.status = .crashed; crashed.seconds = 42
        crashed.requested = now.addingTimeInterval(-7200)
        state.history = SessionHistorySnapshot(sessions: [stopped, crashed], gameSeconds: [game.id: 3542])
        try? Paths.ensure(dir)
        await capture("history", AnyView(MainView(section: .history)), state: state, to: dir,
                      size: NSSize(width: 1160, height: 780))
        await capture("history-library", AnyView(MainView(section: .library)), state: state, to: dir,
                      size: NSSize(width: 1160, height: 780))
    }

    static func renderSaveBackups(to dir: URL) async {
        var settings = AppSettings()
        settings.language = .english
        let state = AppState(managesGameBoost: false, initialSettings: settings,
                             initialItems: [], initialBottleSettings: [:])
        let item = LibraryItem(id: "save-preview", name: "Example game", kind: .game,
                               bottle: "preview", executable: "C:\\Game\\game.exe")
        try? Paths.ensure(dir)
        await capture("save-backups", AnyView(SaveArchiveView(item: item)), state: state, to: dir,
                      size: NSSize(width: 720, height: 570))
    }

    static func renderEnvironment(to dir: URL) async {
        let state = AppState(managesGameBoost: false)
        await state.refresh()
        try? Paths.ensure(dir)
        let item = LibraryItem(id: "environment-preview", name: "Windows applications", kind: .program,
                               bottle: "programs", executable: "C:\\Programs\\app.exe")
        L10n.use(.english)
        var devices = DeviceInventory.current()
        // The export preserves printer discovery without publishing configured queue names or IDs.
        devices.printers = devices.printers.indices.map { "Mac printer \($0 + 1)" }
        await capture("windows-environment", AnyView(EnvironmentView(item: item, inventory: devices)), state: state, to: dir,
                      size: NSSize(width: 1100, height: 850))
    }

    static func renderComponents(to dir: URL) async {
        let state = AppState(managesGameBoost: false)
        await state.refresh()
        guard let item = state.programs.first ?? state.launchers.first else { return }
        try? Paths.ensure(dir)
        await capture("windows-components", AnyView(RuntimeComponentsView(item: item)), state: state, to: dir,
                      size: NSSize(width: 1100, height: 800))
    }

    static func renderSettings(to dir: URL, language: InterfaceLanguage? = nil) async {
        let state = AppState(managesGameBoost: false)
        await state.refresh()
        if let language { L10n.use(language) }
        try? Paths.ensure(dir)
        await capture("settings-gameboost", AnyView(MainView(section: .settings)), state: state, to: dir)
    }

    static func render(to dir: URL, language: InterfaceLanguage? = nil) async {
        let state = AppState(managesGameBoost: false)
        if let language { L10n.use(language) }
        await state.refresh()
        try? Paths.ensure(dir)
        let screens: [(String, AnyView)] = [
            ("1-welcome", AnyView(OnboardingView(step: .welcome))),
            ("2-mac", AnyView(OnboardingView(step: .mac))),
            ("3-rosetta", AnyView(OnboardingView(step: .rosetta))),
            ("4-engine", AnyView(OnboardingView(step: .engine))),
            ("5-d3dmetal", AnyView(OnboardingView(step: .d3dmetal))),
            ("6-launchers", AnyView(OnboardingView(step: .launchers))),
            ("7-library", AnyView(MainView(section: .library))),
            ("8-catalog", AnyView(MainView(section: .catalog))),
            ("9-settings", AnyView(MainView(section: .settings))),
            ("10-compat", AnyView(ScrollView { CompatibilityList().padding(24).frame(maxWidth: 780) })),
        ]
            + state.gameProfiles.filter { $0.steamAppID == 990080 }.map { profile in
                ("11-profile", AnyView(GameProfileDetails(profile: profile).padding(24).frame(maxWidth: 600, alignment: .leading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)))
            }
        for (name, view) in screens { await capture(name, view, state: state, to: dir) }

        // Imported games may be below the initial library viewport.
        for item in state.games where !item.isSteamGame {
            await capture("17-imported-game-" + item.id, AnyView(ItemTile(item: item).frame(width: 280).padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)), state: state, to: dir)
        }

        // the helper and the settings sheet, on the Steam launcher and its first game
        guard let steam = state.launchers.first(where: { state.recipe($0.recipeID)?.discoversSteamGames == true }) else { return }
        await capture("12-settings-sheet", AnyView(ItemSettingsView(item: steam)), state: state, to: dir)
        let launcherChecks = await state.checks(for: .launcher, item: steam)
        await capture("13-helper-launcher", AnyView(TroubleshootView(itemID: steam.id, symptom: .launcher, checks: launcherChecks)),
                      state: state, to: dir)
        let audioChecks = await state.checks(for: .audio, item: steam)
        await capture("14-helper-audio", AnyView(TroubleshootView(itemID: steam.id, symptom: .audio, checks: audioChecks)),
                      state: state, to: dir)
        // a crash finding as the library shows it, from a made-up line (not saved anywhere)
        if let game = state.games.first {
            state.diagnoses[game.id] = CrashClassifier.shared.classify(
                "err:module:import_dll Library MSVCP140_ATOMIC_WAIT.dll (which is needed by L\"game.exe\") not found")
            await capture("15-library-finding", AnyView(MainView(section: .library)), state: state, to: dir)
            // the card itself, which the library may show below the fold
            await capture("16-card-finding", AnyView(ItemTile(item: game).frame(width: 240).padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)), state: state, to: dir)
            state.diagnoses[game.id] = nil
        }
    }

    private static func capture(_ name: String, _ view: AnyView, state: AppState, to dir: URL,
                                size: NSSize = NSSize(width: 1100, height: 720)) async {
        let host = NSHostingView(rootView: view
            .environmentObject(state)
            .frame(width: size.width, height: size.height)
            // a real window paints this behind the content
            .background(Color(nsColor: .windowBackgroundColor)))
        // an ordinary window that is never ordered in: tables and lists only draw inside a
        // window, and nothing appears on screen
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        // give SwiftUI a turn to lay out lazily loaded content
        try? await Task.sleep(for: .milliseconds(400))
        host.layoutSubtreeIfNeeded()
        defer { window.contentView = nil }
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: dir.appendingPathComponent("\(name).png"))
            print("rendered \(name)")
        }
    }
}
