import Foundation

extension AppState {
    var gameBoostHint: String {
        if !gameBoostStatus.available {
            return t("Game Boost недоступен: требуется системная утилита Game Mode из Xcode.")
        }
        if gameBoostStatus.failure != nil {
            return t("Не удалось изменить игровой режим. Игра продолжает работать; подробности в журнале.")
        }
        if gameBoostStatus.externallyChanged {
            return t("Сохранён игровой режим, который ты изменил в macOS.")
        }
        if gameBoostStatus.enabled { return t("Игровой режим macOS включён.") }
        return t("Игровой режим включается при запуске игры и возвращается к прежнему состоянию после выхода.")
    }

    func refreshGameBoostAvailability() async {
        gameBoostStatus = await gameBoost.availability()
    }

    func gameBoostTarget(_ item: LibraryItem) -> GameBoostTarget {
        GameBoostTarget(id: item.id, prefix: Bottle(name: item.bottle, root: bottlesRoot).prefixPath,
                        paths: item.isSteamGame ? [] : [item.executable],
                        names: executables(of: item),
                        folder: item.isSteamGame ? steamFolders[item.id] : nil)
    }

    func syncGameBoost() async {
        guard managesGameBoost else { return }
        if isShuttingDown {
            await gameBoost.finishOwnerStarts()
            gameBoostStatus = await gameBoost.availability()
            return
        }
        let targets = allItems.filter { $0.kind == .game && active.contains($0.id) }.map(gameBoostTarget)
        gameBoostStatus = await gameBoost.reconcile(active: targets, pending: launching.union(starting),
                                                   enabled: settings.gameBoost)
    }

    /// Optimization failure must never prevent an otherwise working game from launching.
    func withGameBoost(_ item: LibraryItem, operation: () async throws -> Int32) async throws -> Int32 {
        if settings.gameBoost && item.kind == .game && !isShuttingDown {
            gameBoostStatus = await gameBoost.begin(gameBoostTarget(item))
            if let failure = gameBoostStatus.failure { NSLog("Game Boost: %@", failure.rawValue) }
        }
        do {
            try Task.checkCancellation()
            guard !isShuttingDown else { throw CancellationError() }
            let status = try await operation()
            // Steam's URI launcher returns before the actual game arrives.
            if !item.isSteamGame || status != 0 {
                await gameBoost.cancelStart(item.id, failed: status != 0)
            }
            return status
        } catch {
            await gameBoost.cancelStart(item.id)
            throw error
        }
    }
}
