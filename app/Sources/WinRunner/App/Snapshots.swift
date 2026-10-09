import AppKit
import SwiftUI

/// `--snapshot <dir>` renders the main screens to PNG offscreen, without opening a window, so the
/// layout can be checked headless.
@MainActor
enum Snapshots {
    static func render(to dir: URL) async {
        let state = AppState()
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
            state.diagnoses[game.id] = nil
        }
    }

    private static func capture(_ name: String, _ view: AnyView, state: AppState, to dir: URL) async {
        let size = NSSize(width: 1100, height: 720)
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
