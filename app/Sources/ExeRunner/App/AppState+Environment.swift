import Foundation

extension AppState {
    func selectedEngine(forBottle name: String, proposed: BottleSettings? = nil) throws -> Engine {
        try EngineSelection.resolve(defaultEngine: engine, path: (proposed ?? settings(forBottle: name)).enginePath)
    }
    func engineForItem(_ item: LibraryItem) -> Engine? { try? selectedEngine(forBottle: item.bottle) }

    func validateEnvironmentChange(_ wanted: BottleSettings, for name: String) throws {
        let previous = settings(forBottle: name)
        try SerialPortMapper.validate(wanted.serialPorts)
        let chosen = try selectedEngine(forBottle: name, proposed: wanted)
        if wanted.controllerMode == .xinput && !chosen.hasXInputMapping { throw AppError(t("Выбранный движок не поддерживает преобразование контроллеров в XInput.")) }
        guard wanted.enginePath != previous.enginePath || wanted.serialPorts != previous.serialPorts || wanted.controllerMode != previous.controllerMode else { return }
        guard !name.hasPrefix("isolated-") else { throw AppError(t("Настройка движка и устройств в изолированном прототипе пока недоступна.")) }
        guard !componentInstalls.contains(name), !WineProcesses.list(includeServers: true).contains(where: {
            $0.prefix == Bottle(name: name, root: bottlesRoot).prefixPath
        }), !bottleItems.contains(where: { $0.bottle == name && running.contains($0.id) }) else {
            throw AppError(t("Сначала останови все программы этой Windows-среды, чтобы сменить движок или устройства."))
        }
        let reserved = try SerialPortMapper.unmanagedNumbers(in: Bottle(name: name, root: bottlesRoot))
        if let port = wanted.serialPorts.first(where: { reserved.contains($0.number) }) {
            throw AppError(t("COM\(port.number) уже настроен вне ExeRunner. Существующее подключение сохранено."))
        }
        let old = previous.serialPorts.reduce(into: [Int: String]()) { $0[$1.number] = $1.device }
        for port in wanted.serialPorts where old[port.number] != port.device {
            guard SerialPortMapper.connected(port.device) else { throw AppError(t("Выбранный последовательный порт сейчас не подключён.")) }
        }
    }

    func saveEnvironment(_ wanted: BottleSettings, for name: String) throws {
        try validateEnvironmentChange(wanted, for: name)
        let bottle = Bottle(name: name, root: bottlesRoot)
        let lease = bottle.exists ? try PrefixComponentLease.installation(in: bottle.url) : nil
        defer { lease?.release() }
        try validateEnvironmentChange(wanted, for: name)
        var normalized = wanted
        normalized.serialPorts.sort { $0.number < $1.number }
        updateBottle(name) { $0 = normalized }
    }

    func prepareSerialPorts(_ bottle: Bottle, engine: Engine, log: URL) async throws {
        let wanted = settings(forBottle: bottle.name).serialPorts.sorted { $0.number < $1.number }
        let previous = try SerialPortMapper.managed(in: bottle)
        if wanted.isEmpty && previous.isEmpty { return }
        let values = BottleManager.registryValues(in: bottle, hive: "system.reg", key: "Software\\\\Wine\\\\Ports") ?? [:]
        // An unchanged environment can launch another program without writes or helper restarts.
        if wanted == previous, wanted.allSatisfy({ values[$0.name.lowercased()] == $0.device &&
            (try? FileManager.default.destinationOfSymbolicLink(atPath: SerialPortMapper.link(in: bottle, number: $0.number).path)) == $0.device }) { return }
        guard !WineProcesses.list().contains(where: { $0.prefix == bottle.prefixPath }) else {
            throw AppError(t("Сначала останови все программы этой Windows-среды, чтобы сменить движок или устройства."))
        }
        let lease = try PrefixComponentLease.installation(in: bottle.url)
        defer { lease.release() }
        guard !WineProcesses.list().contains(where: { $0.prefix == bottle.prefixPath }) else {
            throw AppError(t("Сначала останови все программы этой Windows-среды, чтобы сменить движок или устройства."))
        }
        let configured = BottleManager.registryValues(in: bottle, hive: "system.reg", key: "Software\\\\Wine\\\\Ports") ?? [:]
        let owned = Set(previous.map(\.number))
        for port in previous {
            if let value = configured[port.name.lowercased()], value != port.device {
                throw AppError(t("COM\(port.number) уже настроен вне ExeRunner. Существующее подключение сохранено."))
            }
        }
        for port in wanted where !owned.contains(port.number) && configured[port.name.lowercased()] != nil {
            throw AppError(t("COM\(port.number) уже настроен вне ExeRunner. Существующее подключение сохранено."))
        }
        try SerialPortMapper.validateChange(wanted, in: bottle)
        do {
            // mountmgr recreates the old registry mapping when regedit starts Wine.
            // Flush and stop only this idle environment's helpers, then reconcile its links.
            try await BottleManager.importRegistry(SerialPortMapper.registry(previous: previous, desired: wanted), into: bottle,
                 engine: engine, log: log, extra: ["EXERUNNER_COMPONENT_INSTALL": "1"])
            await BottleManager.stop(bottle, engine: engine)
            await WineProcess.server("-w", engine: engine, environment: WineEnvironment.make(engine: engine, prefix: bottle.url))
            try SerialPortMapper.apply(wanted, in: bottle)
        } catch {
            try? await BottleManager.importRegistry(SerialPortMapper.registry(previous: wanted, desired: previous), into: bottle,
                 engine: engine, log: log, extra: ["EXERUNNER_COMPONENT_INSTALL": "1"])
            await BottleManager.stop(bottle, engine: engine)
            await WineProcess.server("-w", engine: engine, environment: WineEnvironment.make(engine: engine, prefix: bottle.url))
            _ = try? SerialPortMapper.apply(previous, in: bottle)
            throw error
        }
    }

    func openPrintingSettings(for item: LibraryItem) async {
        let token = beginActivity(t("Открываю настройки печати Windows…"))
        defer { endActivity(token) }
        do {
            let engine = try selectedEngine(forBottle: item.bottle)
            guard !item.isolated, !item.bottle.hasPrefix("isolated-"), engine.supportsPrinting else {
                throw AppError(t("В выбранном движке нет поддержки печати. Выбери движок с CUPS."))
            }
            let bottle = Bottle(name: item.bottle, root: bottlesRoot)
            let log = Paths.logFile("\(item.bottle)-printers")
            try await BottleManager.ensure(bottle, engine: engine, log: log)
            let status = try await WineProcess.run(engine: engine, arguments: ["control", "printers"],
                                                    environment: WineEnvironment.make(engine: engine, prefix: bottle.url), log: log)
            guard status == 0 else { throw AppError(t("Не удалось открыть настройки печати Windows (код \(status)). Подробности в журнале.")) }
        } catch { errorMessage = error.localizedDescription }
    }
}
