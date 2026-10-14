import Foundation

/// Owns only the three WineBus controller-policy values, with a recoverable original snapshot.
/// Default environments have no writes. Changing mode requires an idle, exclusively leased prefix.
enum ControllerMapping {
    typealias Mode = BottleSettings.ControllerMode
    static let names = ["enable sdl": "Enable SDL", "map controllers": "Map Controllers", "disablehidraw": "DisableHidraw"]
    struct Record: Codable {
        var original: [String: String]
        var applied: [String: String]
        var pending: [String: String]?
        var mode: Mode
    }
    static func policy(_ mode: Mode) -> [String: String]? {
        switch mode {
        case .automatic: nil
        case .xinput: ["enable sdl": "dword:00000001", "map controllers": "dword:00000001", "disablehidraw": "dword:00000001"]
        case .native: ["enable sdl": "dword:00000000", "map controllers": "dword:00000001", "disablehidraw": "dword:00000000"]
        }
    }
    static func valid(_ values: [String: String]) -> Bool {
        values.allSatisfy { name, value in
            names[name] != nil && value.hasPrefix("dword:") && value.count == 14 && UInt32(value.dropFirst(6), radix: 16) != nil
        }
    }
    static func registry(_ values: [String: String]) -> String {
        "\n[HKEY_LOCAL_MACHINE\\System\\CurrentControlSet\\Services\\WineBus]\n" + names.sorted { $0.key < $1.key }.map {
            "\"\($0.value)\"=\(values[$0.key] ?? "-")\n"
        }.joined()
    }
    static func values(in bottle: Bottle) -> [String: String] {
        // CurrentControlSet is a registry link; Wine stores the values under ControlSetNNN.
        let select = BottleManager.registryValues(in: bottle, hive: "system.reg", key: "System\\\\Select")?["current"] ?? "dword:00000001"
        let number = select.hasPrefix("dword:") ? UInt32(select.dropFirst(6), radix: 16) ?? 1 : 1
        let key = String(format: "System\\\\ControlSet%03u\\\\Services\\\\WineBus", number)
        return (BottleManager.registryValues(in: bottle, hive: "system.reg", key: key) ?? [:]).filter { names[$0.key] != nil }
    }
    static func apply(_ mode: Mode, in bottle: Bottle, engine: Engine, log: URL) async throws {
        let file = bottle.url.appendingPathComponent(".exerunner-controller-policy.json")
        let exists = FileManager.default.fileExists(atPath: file.path)
        if mode == .automatic && !exists { return }
        if mode == .xinput && !engine.hasXInputMapping { throw AppError(t("Выбранный движок не поддерживает преобразование контроллеров в XInput.")) }
        let current = values(in: bottle)
        var record: Record
        if exists {
            guard let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 16_384,
                  let saved = try? JSONDecoder().decode(Record.self, from: Data(contentsOf: file)),
                  valid(saved.original), valid(saved.applied), saved.pending.map(valid) ?? true else {
                throw AppError(t("Запись настроек контроллера повреждена. Существующие настройки сохранены."))
            }
            record = saved
            guard current == record.applied || current == record.pending else {
                throw AppError(t("Настройки контроллера изменены вне ExeRunner. Существующие значения сохранены."))
            }
        } else {
            guard valid(current) else { throw AppError(t("Настройки WineBus имеют неизвестный формат. Существующие значения сохранены.")) }
            record = Record(original: current, applied: current, mode: .automatic)
        }
        let desired = policy(mode) ?? record.original
        let lease = current != desired ? try PrefixComponentLease.installation(in: bottle.url) : nil
        defer { lease?.release() }
        if current != desired {
            guard !WineProcesses.list().contains(where: { $0.prefix == bottle.prefixPath }) else {
                throw AppError(t("Сначала останови все программы этой Windows-среды, чтобы сменить движок или устройства."))
            }
            record.pending = desired
            try JSONEncoder().encode(record).write(to: file, options: .atomic)
            do {
                try await BottleManager.importRegistry(registry(desired), into: bottle, engine: engine, log: log,
                                                       extra: ["EXERUNNER_COMPONENT_INSTALL": "1"])
                await BottleManager.stop(bottle, engine: engine)
                await WineProcess.server("-w", engine: engine, environment: WineEnvironment.make(engine: engine, prefix: bottle.url))
                let saved = values(in: bottle)
                guard saved == desired else { throw AppError(t("Не удалось применить режим контроллера.")) }
            } catch {
                try? await BottleManager.importRegistry(registry(current), into: bottle, engine: engine, log: log,
                                                       extra: ["EXERUNNER_COMPONENT_INSTALL": "1"])
                await BottleManager.stop(bottle, engine: engine)
                await WineProcess.server("-w", engine: engine, environment: WineEnvironment.make(engine: engine, prefix: bottle.url))
                throw error
            }
        }
        if mode == .automatic { if exists || FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) } }
        else {
            record.applied = desired; record.pending = nil; record.mode = mode
            try JSONEncoder().encode(record).write(to: file, options: .atomic)
        }
    }
}
