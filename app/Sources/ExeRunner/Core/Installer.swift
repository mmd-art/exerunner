import Foundation

enum Installer {
    /// Installs what a recipe describes into its bottle; does nothing if it is already there.
    /// `environment` comes on top of the recipe's, for the installer and what it starts.
    static func install(_ recipe: Recipe, engine: Engine, bottlesRoot: URL, log: URL? = nil, environment: [String: String] = [:],
                        progress: @escaping (String) -> Void) async throws -> LibraryItem {
        guard let exe = recipe.executable else { throw AppError(t("В рецепте «\(recipe.name)» не указано, что запускать")) }
        let bottle = Bottle(name: recipe.bottle, root: bottlesRoot)
        let log = log ?? Paths.logFile("install-\(recipe.id)")
        progress(t("Готовлю бутылку «\(recipe.bottle)»…"))
        try await BottleManager.ensure(bottle, engine: engine, log: log)
        guard !bottle.name.hasPrefix("isolated-") else { throw AppError("Installer unsupported in isolation prototype") }
        try await BottleManager.applyDefaults(bottle, engine: engine, log: log)
        if let found = installedPath(exe, in: bottle) {
            progress(t("\(recipe.name) уже установлен"))
            return item(for: recipe, executable: found)
        }
        guard let url = recipe.installerURL else { throw AppError(t("Для «\(recipe.name)» пока нет установщика")) }
        progress(t("Скачиваю установщик \(recipe.name)…"))
        let file = try await download(url, sha256: recipe.installerSHA256)
        progress(t("Устанавливаю \(recipe.name)…"))
        let env = WineEnvironment.make(engine: engine, prefix: bottle.url, extra: recipe.environment.merging(environment) { $1 })
        let command = file.pathExtension.lowercased() == "msi" ? ["msiexec", "/i", file.path] : [file.path]
        let status = try await WineProcess.run(engine: engine, arguments: command + recipe.installerArguments,
                                               environment: env, log: log)
        // Installers hand the work to child processes and often start the launcher at the end, so
        // the bottle may never go idle: the program appearing is what counts, ten minutes at most
        for _ in 0..<300 {
            if let found = installedPath(exe, in: bottle) { return item(for: recipe, executable: found) }
            if WineProcesses.list().allSatisfy({ $0.prefix != bottle.prefixPath }) { break }
            try? await Task.sleep(for: .seconds(2))
        }
        if let found = installedPath(exe, in: bottle) { return item(for: recipe, executable: found) }
        throw AppError(t("Установщик «\(recipe.name)» завершился с кодом \(status), но программа не появилась. Журнал: \(log.path)"))
    }

    /// The recipe's program where the installer put it: 64-bit installers use Program Files,
    /// 32-bit ones Program Files (x86), and a recipe names one of them
    static func installedPath(_ exe: String, in bottle: Bottle) -> String? {
        var candidates = [exe]
        if exe.contains("\\Program Files (x86)\\") {
            candidates.append(exe.replacingOccurrences(of: "\\Program Files (x86)\\", with: "\\Program Files\\"))
        } else if exe.contains("\\Program Files\\") {
            candidates.append(exe.replacingOccurrences(of: "\\Program Files\\", with: "\\Program Files (x86)\\"))
        }
        return candidates.first { bottle.hostURL(forWindowsPath: $0).map { FileManager.default.fileExists(atPath: $0.path) } ?? false }
    }

    static func item(for recipe: Recipe, executable: String) -> LibraryItem {
        LibraryItem(id: recipe.id, name: recipe.name, kind: LibraryItem.Kind(rawValue: recipe.kind.rawValue) ?? .program,
                    bottle: recipe.bottle, executable: executable, recipeID: recipe.id)
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
            throw AppError(t("Не удалось скачать \(url.lastPathComponent): HTTP \(http.statusCode)"))
        }
        if let sha256, try sha256Hex(of: temp) != sha256 {
            throw AppError(t("Контрольная сумма \(url.lastPathComponent) не совпала, файл не используется"))
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
        progress(t("Готовлю бутылку «\(bottle.name)»…"))
        try await BottleManager.ensure(bottle, engine: engine, log: log)
        guard !bottle.name.hasPrefix("isolated-") else { throw AppError("Installer unsupported in isolation prototype") }
        try await BottleManager.applyDefaults(bottle, engine: engine, log: log)
        let before = executables(in: bottle)
        progress(t("Идёт установка: пройди шаги в окне установщика"))
        let env = WineEnvironment.make(engine: engine, prefix: bottle.url)
        let arguments = WindowsInstaller.arguments(for: file)
        // not waiting for the bottle to go idle: many installers start the program at the end
        let status = try await WineProcess.run(engine: engine, arguments: arguments, environment: env, log: log,
                                               directory: file.deletingLastPathComponent())
        guard WindowsInstaller.succeeded(status, isMSI: file.pathExtension.lowercased() == "msi") else {
            throw AppError(t("Установщик завершился с кодом \(status). Подробности: \(log.path)"))
        }
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
