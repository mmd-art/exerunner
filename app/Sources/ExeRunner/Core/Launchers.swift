import Foundation

/// Knowledge about game launchers that is not a recipe line. Ported from frankea/Whisky's
/// LauncherDetector.swift and LauncherPresets.swift (GPL-3.0-or-later).
enum Launchers {
    /// Which launcher an executable belongs to, by file name and path, as our recipe id.
    /// Games inside a Steam library are not the Steam client: they fall through to the other
    /// checks (a Rockstar title bought on Steam still detects as Rockstar).
    static func recipeID(forExecutable path: String) -> String? {
        let normalized = path.replacingOccurrences(of: "\\", with: "/").lowercased()
        let name = normalized.split(separator: "/").last.map(String.init) ?? normalized
        let isSteamLibraryGame = normalized.contains("steamapps/common")
        if !isSteamLibraryGame, name.contains("steam") || normalized.contains("/steam/") { return "steam" }
        if name.contains("rockstar") || name.contains("launcherpatcher") || normalized.contains("rockstar games")
            || (name == "launcher.exe" && (normalized.contains("rockstar games") || normalized.contains("social club"))) {
            return "rockstar"
        }
        if name.contains("eadesktop") || name.contains("eaapp") || name.contains("origin.exe")
            || normalized.contains("/ea app/") || normalized.contains("/origin/") || normalized.contains("/electronic arts/ea desktop/") {
            return "ea"
        }
        if name.contains("epicgames") || name.contains("epiclauncher") || name.contains("epicwebhelper")
            || normalized.contains("/epic games/launcher/") {
            return "epic-launcher"
        }
        if name.contains("ubisoft") || name.contains("uplay") || name == "upc.exe" || normalized.contains("/ubisoft") {
            return "ubisoft"
        }
        if name.contains("battle.net") || name.contains("battlenet") || normalized.contains("/battle.net/") {
            return "battlenet"
        }
        return nil
    }

    /// Chromium helpers that games and their engines ship (Unreal's web browser, CefSharp, Qt
    /// WebEngine). Like Steam's helper they draw through DXVK and must not see NVIDIA's libraries,
    /// which pull D3DMetal into them.
    static let chromiumHelpers = ["EpicWebHelper.exe", "UnrealCEFSubProcess.exe", "CefSharp.BrowserSubprocess.exe",
                                  "QtWebEngineProcess.exe"]

    /// The libraries DLSS through MetalFX puts in system32; off for programs that must not use them
    static let nvidiaLibraries = ["nvngx", "nvapi64", "nvapi"]

    /// Steam app ids of Rockstar titles that start the Rockstar Games Launcher inside the Steam
    /// session: Red Dead Redemption 2, Grand Theft Auto V (Legacy and Enhanced), L.A. Noire and
    /// its VR Case Files, Max Payne 3, Grand Theft Auto IV, Bully: Scholarship Edition, Red Dead
    /// Redemption, and the three Definitive Editions of the GTA trilogy.
    static let rockstarSteamAppIDs: Set<Int> = [
        1_174_180, 271_590, 3_240_220, 110_800, 722_230, 204_100,
        12_210, 12_200, 2_668_510, 1_546_990, 1_546_970, 1_547_000,
    ]

    /// The Rockstar launcher runs in a bottle when one of its titles is installed through Steam
    /// or its own folder is there; the bottle then gets the rockstar recipe's program settings.
    static func runsRockstarLauncher(in bottle: Bottle, steamAppIDs: [Int]) -> Bool {
        if steamAppIDs.contains(where: rockstarSteamAppIDs.contains) { return true }
        return ["Program Files/Rockstar Games", "Program Files (x86)/Rockstar Games"].contains {
            FileManager.default.fileExists(atPath: bottle.driveC.appendingPathComponent($0).path)
        }
    }
}
