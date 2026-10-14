import AppKit
import Foundation

extension AppState {
    func saveLaunchSettings(_ proposed: LibraryItem, bottleSettings: BottleSettings) async throws {
        let previous = item(proposed.id) ?? proposed
        guard !running.contains(proposed.id) || proposed.isolated == previous.isolated else {
            throw AppError(t("Сначала останови программу, чтобы сменить режим."))
        }
        launching.insert(proposed.id)
        defer { launching.remove(proposed.id) }
        let root = bottlesRoot
        let saved = try await Task.detached {
            try LaunchModes.change(proposed, from: previous, root: root)
        }.value
        upsert(saved)
        updateBottle(saved.bottle) { $0 = bottleSettings }
        refreshGames()
    }

    /// LaunchFoo.exe commonly starts Foo.exe. Both receive settings; only the
    /// actual program owns a Dock icon. Catalog/Steam executables cover other cases.
    func dockExecutable(for item: LibraryItem, in bottle: Bottle) -> String {
        if item.isSteamGame { return executables(of: item).first ?? item.executableName }
        let name = item.executableName
        guard name.lowercased().hasPrefix("launch"), name.count > 10,
              let executable = bottle.hostURL(forWindowsPath: item.executable) else { return name }
        let expected = String(name.dropFirst(6))
        let files = (try? FileManager.default.contentsOfDirectory(at: executable.deletingLastPathComponent(), includingPropertiesForKeys: nil)) ?? []
        return files.first { $0.lastPathComponent.caseInsensitiveCompare(expected) == .orderedSame }?.lastPathComponent ?? name
    }

    func nativeIdentity(for item: LibraryItem, in bottle: Bottle) throws -> [String: String] {
        let owner = dockExecutable(for: item, in: bottle)
        var env = ["WINE_APP_DISPLAY_NAME": item.name, "WINE_APP_DOCK_EXE": owner, "WINE_APP_IDENTITY_EXE": owner]
        env["WINE_APP_GAME"] = item.kind == .game ? "1" : "0"
        if let engine { env["WINEDLLPATH"] = engine.root.appendingPathComponent("lib/wine").path }
        if item.isolated || item.bottle.hasPrefix("isolated-") {
            guard let executable = bottle.hostURL(forWindowsPath: item.executable), IsolatedWine.inside(executable, bottle.driveC) else {
                throw AppError(t("Для изоляции программа должна находиться внутри отдельной бутылки."))
            }
        }
        if let image = icon(for: item), let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) {
            let name = sha256Hex(Data(item.id.utf8)) + ".png"
            env["WINE_APP_ICON_PATH"] = try NativeAssets.write(png, named: name, in: bottle).path
        }
        return env
    }
}
