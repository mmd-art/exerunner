import Foundation

enum Installer {
    /// Installs what a recipe describes into its bottle; does nothing if it is already there.
    static func install(_ recipe: Recipe, engine: Engine, bottlesRoot: URL,
                        progress: @escaping (String) -> Void) async throws -> LibraryItem {
        guard let exe = recipe.executable else { throw AppError("В рецепте «\(recipe.name)» не указано, что запускать") }
        let bottle = Bottle(name: recipe.bottle, root: bottlesRoot)
        let log = Paths.logFile("install-\(recipe.id)")
        progress("Готовлю бутылку «\(recipe.bottle)»…")
        try await BottleManager.ensure(bottle, engine: engine, log: log)
        let target = bottle.hostURL(forWindowsPath: exe)
        if let target, FileManager.default.fileExists(atPath: target.path) {
            progress("\(recipe.name) уже установлен")
        } else {
            guard let url = recipe.installerURL else { throw AppError("Для «\(recipe.name)» пока нет установщика") }
            progress("Скачиваю установщик \(recipe.name)…")
            let file = try await download(url, sha256: recipe.installerSHA256)
            progress("Устанавливаю \(recipe.name)…")
            let env = WineEnvironment.make(engine: engine, prefix: bottle.url, extra: recipe.environment)
            let command = file.pathExtension.lowercased() == "msi" ? ["msiexec", "/i", file.path] : [file.path]
            let status = try await WineProcess.run(engine: engine, arguments: command + recipe.installerArguments,
                                                   environment: env, log: log)
            await WineProcess.server("-w", engine: engine, environment: env)
            guard let target, FileManager.default.fileExists(atPath: target.path) else {
                throw AppError("Установщик «\(recipe.name)» завершился с кодом \(status), но программа не появилась. Журнал: \(log.path)")
            }
        }
        return LibraryItem(id: recipe.id, name: recipe.name, kind: LibraryItem.Kind(rawValue: recipe.kind.rawValue) ?? .program,
                           bottle: recipe.bottle, executable: exe, recipeID: recipe.id)
    }

    static func download(_ url: URL, sha256: String?) async throws -> URL {
        try Paths.ensure(Paths.downloads)
        let installerTypes = ["exe", "msi"]
        var name = url.lastPathComponent
        if let sha256, installerTypes.contains(url.pathExtension.lowercased()) {
            let cached = Paths.downloads.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: cached.path), (try? sha256Hex(of: cached)) == sha256 { return cached }
        }
        let (temp, response) = try await URLSession.shared.download(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AppError("Не удалось скачать \(url.lastPathComponent): HTTP \(http.statusCode)")
        }
        if let sha256, try sha256Hex(of: temp) != sha256 {
            throw AppError("Контрольная сумма \(url.lastPathComponent) не совпала, файл не используется")
        }
        // some download links carry no file name (Battle.net's); wine needs the extension
        if !installerTypes.contains((name as NSString).pathExtension.lowercased()) {
            let suggested = response.suggestedFilename ?? ""
            name = installerTypes.contains((suggested as NSString).pathExtension.lowercased()) ? suggested : name + ".exe"
        }
        let target = Paths.downloads.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: temp, to: target)
        return target
    }

    /// Runs a .exe or .msi installer in the bottle and returns the programs it added,
    /// likeliest first. The installer shows its own window; the user clicks through it.
    static func runInstaller(_ file: URL, bottle: Bottle, engine: Engine,
                             progress: @escaping (String) -> Void) async throws -> [URL] {
        let log = Paths.logFile("install-\(file.deletingPathExtension().lastPathComponent)")
        progress("Готовлю бутылку «\(bottle.name)»…")
        try await BottleManager.ensure(bottle, engine: engine, log: log)
        let before = executables(in: bottle)
        progress("Идёт установка: пройди шаги в окне установщика")
        let env = WineEnvironment.make(engine: engine, prefix: bottle.url)
        let arguments = file.pathExtension.lowercased() == "msi" ? ["msiexec", "/i", file.path] : [file.path]
        // not waiting for the bottle to go idle: many installers start the program at the end
        _ = try await WineProcess.run(engine: engine, arguments: arguments, environment: env, log: log)
        return executables(in: bottle).subtracting(before).map { URL(fileURLWithPath: $0) }
            .sorted { score($0) > score($1) || (score($0) == score($1) && $0.path < $1.path) }
    }

    static func executables(in bottle: Bottle) -> Set<String> {
        var roots = ["Program Files", "Program Files (x86)", "Programs", "ProgramData"].map {
            bottle.driveC.appendingPathComponent($0, isDirectory: true)
        }
        let users = bottle.driveC.appendingPathComponent("users", isDirectory: true)
        for user in (try? FileManager.default.contentsOfDirectory(atPath: users.path)) ?? [] {
            roots.append(users.appendingPathComponent("\(user)/AppData/Local/Programs", isDirectory: true))
        }
        var found = Set<String>()
        for root in roots {
            guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil,
                                                              options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in walker where url.pathExtension.lowercased() == "exe" {
                found.insert(url.path)
            }
        }
        return found
    }

    private static let notPrograms = ["unins", "uninstall", "setup", "install", "update", "crash", "helper",
                                      "redist", "vc_redist", "dxsetup", "dotnet", "report"]

    /// Uninstallers and helpers last, shallow paths first.
    private static func score(_ url: URL) -> Int {
        let name = url.lastPathComponent.lowercased()
        if notPrograms.contains(where: { name.contains($0) }) { return 0 }
        return 20 - min(url.pathComponents.count, 19)
    }
}

extension Bottle {
    /// <bottle>/drive_c/X/Y.exe -> C:\X\Y.exe; nil outside drive_c
    func windowsPath(for url: URL) -> String? {
        let base = driveC.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(base + "/") else { return nil }
        return "C:\\" + path.dropFirst(base.count + 1).replacingOccurrences(of: "/", with: "\\")
    }
}
