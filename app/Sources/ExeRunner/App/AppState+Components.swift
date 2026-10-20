import Foundation

extension AppState {
    func suggestedRuntimeComponents(for item: LibraryItem) -> [String] {
        let bottle = Bottle(name: item.bottle, root: bottlesRoot)
        guard let file = bottle.hostURL(forWindowsPath: item.executable) else { return [] }
        return RuntimeComponent.suggested(for: file, available: engineForItem(item).map { Winetricks.available(in: $0) } ?? [], installed: Winetricks.installed(in: bottle))
    }

    func inferredRuntimeVerbs(in bottle: String) -> [String] {
        guard settings.automaticRuntimeComponents else { return [] }
        // Generic standalone programs; existing launcher/game policies remain explicit.
        return Set(bottleItems.filter { $0.bottle == bottle && $0.kind == .program && $0.recipeID == nil && !$0.isolated }
            .flatMap { suggestedRuntimeComponents(for: $0) }).sorted()
    }

    func ensureRuntimeComponents(_ verbs: [String], in bottle: Bottle, engine: Engine,
                                 log: URL, progress: @escaping (String) -> Void) async throws {
        guard !Winetricks.missing(verbs, in: bottle).isEmpty else { return }
        guard !componentInstalls.contains(bottle.name) else { throw AppError(t("В этой бутылке уже идёт установка компонентов.")) }
        guard WineProcesses.list().filter({ $0.prefix == bottle.prefixPath }).isEmpty else {
            throw AppError(t("Сначала закрой программы этой бутылки, чтобы установить библиотеки Windows."))
        }
        componentInstalls.insert(bottle.name)
        defer { componentInstalls.remove(bottle.name) }
        try await Winetricks.ensure(verbs, in: bottle, engine: engine, log: log, progress: progress)
    }

    @discardableResult
    func installRuntimeComponents(_ verbs: [String], for item: LibraryItem) async -> Bool {
        guard !updateRestartPending else { return false }
        let engine: Engine
        do { engine = try selectedEngine(forBottle: item.bottle) }
        catch { errorMessage = error.localizedDescription; return false }
        guard !item.isolated, !item.bottle.hasPrefix("isolated-") else {
            errorMessage = t("Автоматическая установка компонентов в изолированном прототипе пока недоступна.")
            return false
        }
        guard !bottleItems.contains(where: { $0.bottle == item.bottle && running.contains($0.id) }) else {
            errorMessage = t("Сначала закрой программы этой бутылки, чтобы установить библиотеки Windows.")
            return false
        }
        let token = beginActivity(t("Устанавливаю библиотеки Windows…"))
        defer { endActivity(token) }
        let bottle = Bottle(name: item.bottle, root: bottlesRoot)
        let log = Paths.logFile("\(item.bottle)-components")
        do {
            try await BottleManager.ensure(bottle, engine: engine, log: log)
            try await ensureRuntimeComponents(verbs, in: bottle, engine: engine, log: log, progress: reporter(token))
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }
}
