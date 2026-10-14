import Foundation

extension AppState {
    func launch(_ item: LibraryItem) {
        guard !isShuttingDown, !running.contains(item.id) else { return }
        Task {
            do { _ = try await run(item) } catch { errorMessage = error.localizedDescription }
        }
    }

    /// Starts `item` and returns once wine is done with it: a program when it exits, a Steam game
    /// once its Steam client has it (the game itself is then followed in the process table).
    func run(_ item: LibraryItem) async throws -> Int32 {
        guard !isShuttingDown else { throw CancellationError() }
        guard !componentInstalls.contains(item.bottle) else { throw AppError(t("В этой бутылке уже идёт установка компонентов.")) }
        try Task.checkCancellation()
        guard let engine else { throw AppError(t("Движок не найден. Укажи его папку в настройках.")) }
        if effectiveGraphics(item) == .dxmt {
            guard engine.hasDXMT else { throw AppError(t("DXMT отсутствует или движок не поддерживает его загрузку. Выберите другой графический режим.")) }
            guard GraphicsSelection.supportsDXMT(profile: profile(for: item)) else {
                throw AppError(LibraryItem.Graphics.dxmt.help)
            }
            guard !item.isolated, !item.bottle.hasPrefix("isolated-") else {
                throw AppError(t("DXMT пока недоступен в изолированном режиме. Обычный запуск автоматически не выполняется."))
            }
        }
        if item.isolated || item.bottle.hasPrefix("isolated-") {
            guard !item.isSteamGame, item.kind != .launcher,
                  !allItems.contains(where: { $0.id != item.id && $0.bottle == item.bottle }) else {
                throw AppError(t("Изолированный режим требует отдельную бутылку без лаунчера и других игр."))
            }
            launching.insert(item.id)
            defer { launching.remove(item.id) }
            let bottle = Bottle(name: item.bottle, root: bottlesRoot)
            let log = Paths.logFile(item.id)
            logSegments[item.id] = LogSegment(url: log)
            launchTimes[item.id] = Date()
            stoppedByUser.remove(item.id)
            var extra = environment(for: item)
            extra.merge(try nativeIdentity(for: item, in: bottle)) { $1 }
            handoffGameForeground(item)
            let status = try await withGameBoost(item) {
                try await IsolatedWine.run(item, bottle: bottle, engine: engine, log: log, extra: extra)
            }
            finished(item.id, status: status)
            return status
        }
        if item.isSteamGame, let client = steamClient(for: item) {
            return try await runThroughSteam(item, client: client, engine: engine)
        }
        launching.insert(item.id)
        defer { launching.remove(item.id) }
        stoppedByUser.remove(item.id)
        let (env, log) = try await prepare(item, engine: engine)
        try Task.checkCancellation()
        guard !isShuttingDown else { throw CancellationError() }
        let file = Bottle(name: item.bottle, root: bottlesRoot).hostURL(forWindowsPath: item.executable)
        let plan = try await ExecutionBreakpointCompatibility.plan(executable: item.executable, arguments: item.arguments,
                                                                  file: file, isolated: item.isolated, environment: env,
                                                                  compatibilityDirectory: Paths.compat)
        try Task.checkCancellation()
        guard !isShuttingDown else { throw CancellationError() }
        let arguments = plan.arguments
        let folder = file?.deletingLastPathComponent()
        handoffGameForeground(item)
        var status = try await withGameBoost(item) {
            try await WineProcess.run(engine: engine, arguments: arguments, environment: plan.environment, log: log, directory: folder)
        }
        // Steam exits with 42 after applying an update and expects to be started again
        if status == 42, !isShuttingDown, !Task.isCancelled, recipe(item.recipeID)?.discoversSteamGames == true {
            status = try await WineProcess.run(engine: engine, arguments: arguments, environment: env, log: log, directory: folder)
        }
        finished(item.id, status: status)
        return status
    }

    /// Readies the bottle for `item`: created, Windows components, DLL overrides, fonts, audio,
    /// and the per-program settings cxcompatdb.so applies. Returns the launch's environment and
    /// its new log; starts the Discord bridge last, right before the program.
    func prepare(_ item: LibraryItem, engine: Engine) async throws -> (environment: [String: String], log: URL) {
        let bottle = Bottle(name: item.bottle, root: bottlesRoot)
        Migration.renameStamps(in: bottle)
        let log = Paths.logFile(item.id)
        logSegments[item.id] = LogSegment(url: log)
        followsClient[item.id] = nil
        diagnoses[item.id] = nil
        launchTimes[item.id] = Date()
        let token = beginActivity(t("Готовлю «\(item.name)»…"))
        defer { endActivity(token) }

        // Capture the initiating window's screen before any Wine helper changes focus.
        if settings.automaticNativeResolution, item.kind == .game, !item.isolated, highResolutionEnabled(forBottle: item.bottle),
           !WineProcesses.list().contains(where: { $0.path.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last?.lowercased() == item.executableName.lowercased() }),
           let display = NativeDisplayTarget.current() {
            do {
                if let update = try NativeDisplayPolicy.prepare(adapter: profile(for: item)?.nativeDisplayProfile,
                        documents: Paths.home.appendingPathComponent("Documents", isDirectory: true),
                        target: display, backups: Paths.support.appendingPathComponent("DisplayBackups", isDirectory: true)) {
                    let line = "EXERUNNER_DISPLAY native \(display.width)x\(display.height) output=\(display.outputIndex) backup=\(update.backup.path)\n"
                    try Paths.ensure(log.deletingLastPathComponent())
                    if !FileManager.default.fileExists(atPath: log.path) { FileManager.default.createFile(atPath: log.path, contents: Data()) }
                    let handle = try FileHandle(forWritingTo: log)
                    defer { try? handle.close() }
                    try handle.seekToEnd(); try handle.write(contentsOf: Data(line.utf8))
                }
            } catch { throw AppError(t("Не удалось согласовать разрешение игры с текущим экраном. Исходные настройки сохранены в резервной копии, если изменение уже началось.")) }
        }
        let compat = try await prepareBottle(bottle, log: log, engine: engine, progress: reporter(token))
        var extra = environment(for: item)
        extra.merge(try nativeIdentity(for: item, in: bottle)) { $1 }
        extra["EXERUNNER_COMPAT_FILE"] = compat.path
        let env = WineEnvironment.make(engine: engine, prefix: bottle.url, extra: extra)
        if settings(forBottle: item.bottle).discordBridge { BottleManager.startDiscordBridge(bottle, engine: engine, environment: env) }
        return (env, log)
    }

    /// What every program of a bottle shares: the bottle itself, Windows components, DXVK and
    /// DLL overrides, fonts, audio and the per-program file cxcompatdb.so reads, returned
    func prepareBottle(_ bottle: Bottle, log: URL, engine: Engine, progress: @escaping (String) -> Void) async throws -> URL {
        guard !bottle.name.hasPrefix("isolated-") else { throw AppError(t("Автоматическая установка компонентов в изолированном прототипе пока недоступна.")) }
        try await BottleManager.ensure(bottle, engine: engine, log: log)
        try await BottleManager.applyHighResolution(settings(forBottle: bottle.name), to: bottle,
                                                    hasGames: bottleItems.contains { $0.bottle == bottle.name && $0.kind == .game },
                                                    engine: engine, log: log)
        try await BottleManager.applyDefaults(bottle, engine: engine, log: log)
        let verbs = Array(Set(winetricksVerbs(in: bottle.name) + inferredRuntimeVerbs(in: bottle.name))).sorted()
        try await ensureRuntimeComponents(verbs, in: bottle, engine: engine, log: log, progress: progress)
        if !dxvkExecutables(in: bottle.name).isEmpty { try BottleManager.installDXVK(bottle, engine: engine) }
        if !dxmtExecutables(in: bottle.name).isEmpty { try BottleManager.installDXMTBridge(bottle, engine: engine) }
        try await BottleManager.applyOverrides(bottle, engine: engine, overrides: dllOverrides(in: bottle.name, engine: engine),
                                               direct3D: direct3D(in: bottle.name), log: log)
        BottleManager.installMetalFXFiles(bottle, engine: engine)
        try await BottleManager.applyFonts(bottle, engine: engine, log: log)
        try await BottleManager.applyAudio(settings(forBottle: bottle.name), to: bottle, engine: engine, log: log)
        return try BottleManager.writeCompatEnvironment(bottle, perProgram: perProgramEnvironment(in: bottle.name),
                                                        d3dmetalOff: skipList(in: bottle.name), dxmt: dxmtExecutables(in: bottle.name))
    }

    /// A Steam game goes through its bottle's Steam client. A running client is handed the game;
    /// one that is not running starts with it, as the client's own run, which also restarts it
    /// after an update. The game counts as starting until its process shows up (two minutes at
    /// most) and writes its output into the client's log.
    private func runThroughSteam(_ item: LibraryItem, client: LibraryItem, engine: Engine) async throws -> Int32 {
        launching.insert(item.id)
        defer { launching.remove(item.id) }
        stoppedByUser.remove(item.id)
        // the bottle and the game's settings; the client keeps its own environment
        let (_, log) = try await prepare(item, engine: engine)
        handoffGameForeground(item)
        await refreshProcesses()
        expectStart(item.id)

        return try await withGameBoost(item) {
        if processes(of: client, in: processTable).isEmpty {
            var started = client
            started.arguments = client.arguments + item.arguments
            // wine reads its log level once, when the client starts; the game inherits it
            if item.logging != .normal { started.logging = item.logging }
            followsClient[item.id] = (client.id, 0)
            clientRuns[client.id] = Task {
                defer { self.clientRuns[client.id] = nil }
                return try await self.run(started)
            }
            return 0
        }

        let bottle = Bottle(name: item.bottle, root: bottlesRoot)
        let clientLog = currentLog(of: client)
        followsClient[item.id] = (client.id, clientLog?.size ?? 0)
        var extra = environment(for: client)
        extra["EXERUNNER_COMPAT_FILE"] = BottleManager.compatFile(bottle).path
        let env = WineEnvironment.make(engine: engine, prefix: bottle.url, extra: extra)
        return try await WineProcess.run(engine: engine, arguments: [client.executable] + item.arguments, environment: env, log: log)
        }
    }

    /// Waits for the launcher runs this process started for games (a headless launch keeps the
    /// launcher's restart after an update this way)
    func waitForClients() async {
        while let task = clientRuns.values.first {
            _ = try? await task.value
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    // MARK: stopping

    /// A launcher stops with everything in its bottle; one that can quit by itself is asked to
    /// first. A game or program stops alone: its windows are asked to close, what is left after
    /// a few seconds is ended, and the rest of the bottle (Steam, say) keeps running.
    func stop(_ item: LibraryItem) async {
        cancelForegroundHandoff(item)
        guard let engine else { return }
        let bottle = Bottle(name: item.bottle, root: bottlesRoot)
        stoppedByUser.insert(item.id)
        startingDeadlines[item.id] = nil
        starting.remove(item.id)
        let log = segment(for: item.id)?.url ?? Paths.logFile(item.id)
        if item.isolated || item.bottle.hasPrefix("isolated-") {
            await BottleManager.stop(bottle, engine: engine)
        } else if item.kind == .launcher {
            if let recipe = recipe(item.recipeID), !recipe.shutdownArguments.isEmpty,
               !processes(of: item, in: WineProcesses.list()).isEmpty {
                let env = WineEnvironment.make(engine: engine, prefix: bottle.url, extra: environment(for: item))
                _ = try? await WineProcess.run(engine: engine, arguments: [item.executable] + recipe.shutdownArguments,
                                               environment: env, log: log)
                _ = await waitForExit(of: item, seconds: 20)
            }
            await BottleManager.stop(bottle, engine: engine)
        } else {
            let targets = processes(of: item, in: WineProcesses.list())
            if !targets.isEmpty {
                let env = WineEnvironment.make(engine: engine, prefix: bottle.url)
                for name in Set(targets.map(\.name)) {
                    _ = try? await WineProcess.run(engine: engine, arguments: ["taskkill", "/im", name], environment: env, log: log)
                }
                if !(await waitForExit(of: item, seconds: 8)) {
                    WineProcesses.kill(processes(of: item, in: WineProcesses.list()))
                }
            }
        }
        await refreshProcesses()
    }

    /// Closes a bottle the way its launcher likes (Steam's -shutdown), then whatever is left
    func quitBottle(_ name: String) async {
        let list = WineProcesses.list()
        if let launcher = items.first(where: { $0.bottle == name && $0.kind == .launcher && !processes(of: $0, in: list).isEmpty }) {
            await stop(launcher)
        } else if let engine {
            await BottleManager.stop(Bottle(name: name, root: bottlesRoot), engine: engine)
        }
    }

    /// Everything in the item's bottle, at once
    func stopBottle(_ item: LibraryItem) async {
        guard let engine else { return }
        for other in allItems where other.bottle == item.bottle { stoppedByUser.insert(other.id) }
        await BottleManager.stop(Bottle(name: item.bottle, root: bottlesRoot), engine: engine)
        await refreshProcesses()
    }

    private func waitForExit(of item: LibraryItem, seconds: Int) async -> Bool {
        for _ in 0..<(seconds * 2) {
            let list = await Task.detached { WineProcesses.list() }.value
            if processes(of: item, in: list).isEmpty { return true }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return false
    }

    /// Quitting the runner also ends its Windows sessions. Block new launches first so
    /// a pending preparation or Steam update cannot recreate a session during teardown.
    func shutdown() async {
        cancelAllForegroundHandoffs()
        guard !isShuttingDown else { return }
        isShuttingDown = true
        await gameBoost.finishOwnerStarts()
        watcher?.cancel()
        watcher = nil
        for task in clientRuns.values { task.cancel() }
        let bottles = Set(bottleItems.map(\.bottle)).map { Bottle(name: $0, root: bottlesRoot) }
        for item in allItems { stoppedByUser.insert(item.id) }
        PrefixLaunchGate.close(Set(bottles.map(\.prefixPath)))
        guard let engine else { return }
        for bottle in bottles {
            await BottleManager.stop(bottle, engine: engine)
        }
        await refreshProcesses()
    }

    // MARK: watching

    /// Every two seconds while the window is open: which items have processes in their bottles
    func watchProcesses() {
        guard watcher == nil else { return }
        watcher = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshProcesses()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func refreshProcesses() async {
        let list = await Task.detached { WineProcesses.list() }.value
        processTable = list
        var found = Set<String>()
        for item in allItems where !processes(of: item, in: list).isEmpty { found.insert(item.id) }

        let now = Date()
        for (id, deadline) in startingDeadlines where found.contains(id) || deadline < now { startingDeadlines[id] = nil }
        let waiting = Set(startingDeadlines.keys)
        if waiting != starting { starting = waiting }

        // a game started inside Steam: its output starts where the client's log is now
        for id in found.subtracting(active) where followsClient[id] == nil && !launching.contains(id) {
            guard let game = item(id), game.isSteamGame, let client = steamClient(for: game) else { continue }
            followsClient[id] = (client.id, currentLog(of: client)?.size ?? 0)
            launchTimes[id] = launchTimes[id] ?? now
        }
        // games a launcher ran have no run of their own to report their end
        for id in active.subtracting(found) where !launching.contains(id) { finished(id, status: nil) }
        if found != active { active = found }
        await syncGameBoost()
    }

    func expectStart(_ id: String) {
        startingDeadlines[id] = Date().addingTimeInterval(120)
        starting.insert(id)
    }

    /// An item's processes: for a Steam game anything inside its folder, else its program by
    /// path or name. Only the item's bottle counts.
    func processes(of item: LibraryItem, in list: [WineProcesses.Entry]) -> [WineProcesses.Entry] {
        let prefix = Bottle(name: item.bottle, root: bottlesRoot).prefixPath
        let names = Set(executables(of: item).map { $0.lowercased() })
        let folder = steamFolders[item.id]
        let path = item.isSteamGame ? nil : item.executable
        return list.filter { entry in
            guard entry.prefix == prefix else { return false }
            if item.isolated || item.bottle.hasPrefix("isolated-") { return true }
            if let folder, WindowsPath.isInside(entry.path, folder: folder) { return true }
            if let path, WindowsPath.same(entry.path, path) { return true }
            return names.contains(entry.name.lowercased())
        }
    }

    // MARK: output

    /// The client's log as it is now: the one this app started it with, or its newest on disk
    func currentLog(of client: LibraryItem) -> LogSegment? {
        if let segment = logSegments[client.id], FileManager.default.fileExists(atPath: segment.url.path) {
            return LogSegment(url: segment.url)
        }
        return Paths.latestLog(client.id).map { LogSegment(url: $0) }
    }

    /// Where an item's last launch wrote, as far as the app knows
    func segment(for id: String) -> LogSegment? {
        if let follow = followsClient[id], let client = item(follow.clientID), let log = currentLog(of: client) {
            // the client may have started a new log since; then all of it is the game's time
            return LogSegment(url: log.url, offset: follow.offset <= log.size ? follow.offset : 0)
        }
        if let segment = logSegments[id], FileManager.default.fileExists(atPath: segment.url.path) { return segment }
        return Paths.latestLog(id).map { LogSegment(url: $0) }
    }

    /// After a run: its output is read for a crash when the exit was not clean or the log says
    /// so. A finding that names at least an error stays until the next launch.
    func finished(_ id: String, status: Int32?) {
        if stoppedByUser.remove(id) != nil { return }
        // Unreal catches its own crashes and says so in a report of its own
        if let game = item(id), let report = UnrealCrashReport.latest(in: crashReportRoots(for: game), since: launchTimes[id]) {
            diagnoses[id] = UnrealCrashReport.diagnosis(report)
            return
        }
        guard let text = segment(for: id)?.window() else { return }
        guard (status ?? 0) != 0 || CrashClassifier.looksLikeCrash(text) else { return }
        let diagnosis = CrashClassifier.shared.classify(text, exitStatus: status)
        if let primary = diagnosis.primary, primary.pattern.severity >= .error { diagnoses[id] = diagnosis }
    }

    /// Where an item's game engine leaves crash reports: its own folder (for a program, the
    /// folders above its .exe) and the bottle's AppData\Local
    func crashReportRoots(for item: LibraryItem) -> [URL] {
        let bottle = Bottle(name: item.bottle, root: bottlesRoot)
        var roots: [URL] = []
        if let folder = steamFolders[item.id].flatMap(bottle.hostURL(forWindowsPath:)) {
            roots.append(folder)
        } else if let exe = bottle.hostURL(forWindowsPath: item.executable) {
            // Unreal keeps the program in <Project>/Binaries/Win64
            roots.append(exe.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())
        }
        let users = bottle.driveC.appendingPathComponent("users", isDirectory: true)
        for user in (try? FileManager.default.contentsOfDirectory(atPath: users.path)) ?? [] where !user.hasPrefix(".") {
            roots.append(users.appendingPathComponent("\(user)/AppData/Local", isDirectory: true))
        }
        return roots.filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}
