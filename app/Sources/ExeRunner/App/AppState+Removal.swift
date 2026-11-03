import AppKit
import Foundation

extension AppState {
    func removalPlan(_ item: LibraryItem, folder: URL) throws -> GameRemoval.Plan {
        let bottle = Bottle(name: item.bottle, root: bottlesRoot)
        guard !item.isSteamGame, item.kind != .launcher,
              let exe = bottle.hostURL(forWindowsPath: item.executable) else {
            throw AppError(t("Для этой игры используй удаление через лаунчер."))
        }
        let others = allItems.filter { $0.id != item.id }.compactMap {
            Bottle(name: $0.bottle, root: bottlesRoot).hostURL(forWindowsPath: $0.executable)
        }
        return try GameRemoval.plan(folder: folder, driveC: bottle.driveC, executable: exe, otherExecutables: others)
    }

    func trashInstallation(_ item: LibraryItem, plan: GameRemoval.Plan) async throws {
        guard !updateRestartPending, !isShuttingDown, !componentInstalls.contains(item.bottle),
              !stoppingBottles.contains(item.bottle),
              !bottleItems.contains(where: { $0.bottle == item.bottle && running.contains($0.id) }) else {
            throw AppError(t("Сначала закрой все программы этой Windows-среды."))
        }
        let bottle = Bottle(name: item.bottle, root: bottlesRoot)
        let lease = try PrefixComponentLease.installation(in: bottle.url)
        defer { lease.release() }
        guard !WineProcesses.list(includeServers: true).contains(where: { $0.prefix == bottle.prefixPath }) else {
            throw AppError(t("Сначала закрой все программы этой Windows-среды."))
        }
        let current = try removalPlan(item, folder: plan.folder)
        guard current.inode == plan.inode, current.device == plan.device else { throw AppError(t("Папка игры изменилась. Выбери её заново.")) }
        try GameRemoval.validate(plan)
        // macOS moves the selected directory itself; it does not follow internal symlinks.
        try FileManager.default.trashItem(at: plan.folder, resultingItemURL: nil)
        remove(item)
    }

    func openUninstaller(_ item: LibraryItem) async throws {
        guard !updateRestartPending, !isShuttingDown, !componentInstalls.contains(item.bottle),
              !stoppingBottles.contains(item.bottle),
              !bottleItems.contains(where: { $0.bottle == item.bottle && running.contains($0.id) }) else {
            throw AppError(t("Сначала закрой все программы этой Windows-среды."))
        }
        let bottle = Bottle(name: item.bottle, root: bottlesRoot)
        guard !WineProcesses.list(includeServers: true).contains(where: { $0.prefix == bottle.prefixPath }) else {
            throw AppError(t("Сначала закрой все программы этой Windows-среды."))
        }
        let engine = try selectedEngine(forBottle: item.bottle)
        let lease = try PrefixComponentLease.installation(in: bottle.url)
        defer { lease.release() }
        componentInstalls.insert(item.bottle)
        defer { componentInstalls.remove(item.bottle) }
        let args: [String]
        if let appID = item.steamAppID {
            guard let client = steamClient(for: item), appID > 0 else { throw AppError(t("Не удалось определить игру Steam.")) }
            args = [client.executable, "steam://uninstall/\(appID)"]
        } else {
            args = ["uninstaller"]
        }
        var env = WineEnvironment.make(engine: engine, prefix: bottle.url,
            extra: environment(for: item.isSteamGame ? (steamClient(for: item) ?? item) : item))
        env["EXERUNNER_COMPONENT_INSTALL"] = "1" // This operation already holds the exclusive lease.
        let status = try await WineProcess.run(engine: engine, arguments: args,
            environment: env, log: Paths.logFile(item.id + "-uninstall"))
        guard status == 0 else { throw AppError(t("Мастер удаления завершился с ошибкой. Карточка и файлы автоматически не удалены.")) }
        // A dismissed/cancelled wizard is not evidence of uninstallation. Keep the card.
        await refresh()
    }
}
