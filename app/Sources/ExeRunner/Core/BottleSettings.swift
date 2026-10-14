import Foundation

/// Shared environment choices: runtime, serial devices, display, audio and the Discord bridge.
/// Stored in bottles.json next to the library, by bottle name.
struct BottleSettings: Codable, Equatable {
    /// HKCU\Software\Wine\Drivers "Audio"
    enum AudioDriver: String, Codable, CaseIterable, Identifiable {
        case automatic, coreaudio, disabled
        var id: String { rawValue }
        var title: String {
            switch self {
            case .automatic: t("Автоматически")
            case .coreaudio: "CoreAudio"
            case .disabled: t("Выключен")
            }
        }
    }

    /// DirectSound's software buffer, HKCU\Software\Wine\DirectSound "HelBuflen". The values are
    /// frankea/Whisky's (BottleAudioConfig.swift, GPL-3.0-or-later); wine's own is 65536.
    enum AudioLatency: String, Codable, CaseIterable, Identifiable {
        case standard, low, stable
        var id: String { rawValue }
        var title: String {
            switch self {
            case .standard: t("Обычный")
            case .low: t("Низкая задержка")
            case .stable: t("Большой, без треска")
            }
        }
        var bufferLength: Int? {
            switch self {
            case .standard: nil
            case .low: 512
            case .stable: 131_072
            }
        }
    }

    /// nil adopts an existing Wine display choice, otherwise enables HiDPI for game bottles.
    /// A user choice always wins. Wine requires one display coordinate system per bottle.
    var highResolution: Bool?
    /// nil follows the application default. Existing environments retain that behavior.
    var enginePath: String?
    struct SerialPort: Codable, Equatable, Identifiable {
        var number: Int
        var device: String
        var id: Int { number }
        var name: String { "COM\(number)" }
    }
    var serialPorts: [SerialPort] = []
    enum ControllerMode: String, Codable, CaseIterable, Identifiable {
        case automatic, xinput, native
        var id: String { rawValue }
        var title: String {
            switch self {
            case .automatic: t("Автоматически")
            case .xinput: t("Xbox / XInput")
            case .native: t("Нативный HID")
            }
        }
    }
    var controllerMode = ControllerMode.automatic

    func desiredHighResolution(hasGames: Bool, existing: String?) -> Bool? {
        if let highResolution { return highResolution }
        if let existing { return ["y", "t", "1"].contains(String(existing.prefix(1)).lowercased()) }
        return hasGames ? true : nil
    }

    var audioDriver = AudioDriver.automatic
    var audioLatency = AudioLatency.standard
    /// Relay games' Discord activity to the Discord app on the Mac
    var discordBridge = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        highResolution = try c.decodeIfPresent(Bool.self, forKey: .highResolution)
        enginePath = try c.decodeIfPresent(String.self, forKey: .enginePath)
        serialPorts = try c.decodeIfPresent([SerialPort].self, forKey: .serialPorts) ?? []
        controllerMode = try c.decodeIfPresent(ControllerMode.self, forKey: .controllerMode) ?? .automatic
        audioDriver = try c.decodeIfPresent(AudioDriver.self, forKey: .audioDriver) ?? .automatic
        audioLatency = try c.decodeIfPresent(AudioLatency.self, forKey: .audioLatency) ?? .standard
        discordBridge = try c.decodeIfPresent(Bool.self, forKey: .discordBridge) ?? false
    }
}

enum BottleSettingsStore {
    static var file: URL { Paths.support.appendingPathComponent("bottles.json") }

    static func load() -> [String: BottleSettings] {
        guard let data = try? Data(contentsOf: file) else { return [:] }
        return (try? JSONDecoder().decode([String: BottleSettings].self, from: data)) ?? [:]
    }

    static func save(_ settings: [String: BottleSettings]) {
        do {
            try Paths.ensure(Paths.support)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(settings).write(to: file, options: .atomic)
        } catch {
            NSLog("bottle settings not saved: \(error)")
        }
    }
}

extension BottleManager {
    /// Imports a Unicode registry file into the bottle. The values are live for every process once
    /// regedit exits; wineserver writes them to user.reg and system.reg a little later.
    static func importRegistry(_ text: String, into bottle: Bottle, engine: Engine, log: URL,
                               extra: [String: String] = [:]) async throws {
        let name = "exerunner-\(UUID().uuidString.prefix(8)).reg"
        let file = bottle.driveC.appendingPathComponent(name)
        var data = Data([0xff, 0xfe])
        data.append(("Windows Registry Editor Version 5.00\r\n" + text).data(using: .utf16LittleEndian)!)
        try data.write(to: file, options: .atomic)
        defer { try? FileManager.default.removeItem(at: file) }
        let env = WineEnvironment.make(engine: engine, prefix: bottle.url, extra: extra)
        let status = try await WineProcess.run(engine: engine, arguments: ["regedit", "/S", "C:\\\(name)"], environment: env, log: log)
        guard status == 0 else { throw AppError(t("Не удалось обновить реестр Windows. Журнал: \(log.path)")) }
    }

    /// Settings every bottle gets once. Wine's crash debugger is off: its console and "Program
    /// Error" windows mean nothing to the user, and a program it holds stays half alive, which
    /// keeps Chromium-based launchers waiting on a renderer that never answers. The crash still
    /// reaches the log ("wine: Unhandled exception ..."), where the app reads it.
    static func applyDefaults(_ bottle: Bottle, engine: Engine, log: URL) async throws {
        let stamp = bottle.url.appendingPathComponent(".exerunner-defaults")
        let version = "1"
        if (try? String(contentsOf: stamp, encoding: .utf8)) == version { return }
        try await importRegistry("""

            [HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows NT\\CurrentVersion\\AeDebug]
            "Debugger"=""
            "Auto"="0"

            [HKEY_CURRENT_USER\\Software\\Wine\\WineDbg]
            "ShowCrashDialog"=dword:00000000

            """, into: bottle, engine: engine, log: log)
        try version.write(to: stamp, atomically: true, encoding: .utf8)
    }

    /// HiDPI is a bottle-wide Wine setting; it never changes macOS display scaling.
    /// Existing hand-configured values are retained until the owner uses the UI switch.
    /// Restart only bootstrap services after a change; refuse if a real program is alive.
    static func applyHighResolution(_ settings: BottleSettings, to bottle: Bottle, hasGames: Bool,
                                    engine: Engine, log: URL) async throws {
        let key = "Software\\\\Wine\\\\Mac Driver"
        guard let values = registryValues(in: bottle, hive: "user.reg", key: key) else {
            throw AppError(t("Не удалось прочитать настройки экрана бутылки."))
        }
        let current = values["retinamode"]
        guard let enabled = settings.desiredHighResolution(hasGames: hasGames, existing: current) else { return }
        if let current, ["y", "t", "1"].contains(String(current.prefix(1)).lowercased()) == enabled { return }
        let bootstrap: Set<String> = ["wineserver", "wineboot.exe", "services.exe", "svchost.exe", "rpcss.exe",
                                      "plugplay.exe", "winedevice.exe", "explorer.exe", "conhost.exe", "regedit.exe"]
        let active = WineProcesses.list().filter { $0.prefix == bottle.prefixPath && !bootstrap.contains($0.name.lowercased()) }
        guard active.isEmpty else { throw AppError(t("Сначала останови программы этой бутылки, чтобы применить HiDPI.")) }
        try await importRegistry("""

            [HKEY_CURRENT_USER\\Software\\Wine\\Mac Driver]
            "RetinaMode"="\(enabled ? "y" : "n")"

            """, into: bottle, engine: engine, log: log)
        // Existing driver instances have already cached the monitor coordinate system.
        await stop(bottle, engine: engine)
        await WineProcess.server("-w", engine: engine, environment: WineEnvironment.make(engine: engine, prefix: bottle.url))
        let saved = registryValues(in: bottle, hive: "user.reg", key: key)?["retinamode"]
        guard saved == (enabled ? "y" : "n") else { throw AppError(t("Не удалось применить HiDPI к бутылке.")) }
    }

    /// The audio driver and buffer, written only when they changed since the last launch. From
    /// frankea/Whisky's WineAudioRegistry.swift (GPL-3.0-or-later).
    static func applyAudio(_ settings: BottleSettings, to bottle: Bottle, engine: Engine, log: URL) async throws {
        let stamp = bottle.url.appendingPathComponent(".exerunner-audio")
        let wanted = "driver=\(settings.audioDriver.rawValue) latency=\(settings.audioLatency.rawValue)"
        let previous = try? String(contentsOf: stamp, encoding: .utf8)
        if previous == wanted { return }
        // a bottle that never had other values needs no registry change for the defaults
        if previous != nil || settings.audioDriver != .automatic || settings.audioLatency != .standard {
            let driver = switch settings.audioDriver {
            case .automatic: "-"
            case .coreaudio: "\"coreaudio\""
            case .disabled: "\"\""
            }
            let buffer = settings.audioLatency.bufferLength.map { "\"\($0)\"" } ?? "-"
            try await importRegistry("""

                [HKEY_CURRENT_USER\\Software\\Wine\\Drivers]
                "Audio"=\(driver)

                [HKEY_CURRENT_USER\\Software\\Wine\\DirectSound]
                "HelBuflen"=\(buffer)

                """, into: bottle, engine: engine, log: log)
        }
        try wanted.write(to: stamp, atomically: true, encoding: .utf8)
    }

    /// Forgets the audio devices Windows remembered, then stops the bottle so they are found again
    static func resetAudio(_ bottle: Bottle, engine: Engine, log: URL) async throws {
        try await importRegistry("""

            [-HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows\\CurrentVersion\\MMDevices]

            """, into: bottle, engine: engine, log: log)
        await stop(bottle, engine: engine)
    }

    /// Fonts Windows programs expect. Unity titles with dynamic font fallback miss glyphs without
    /// Arial and Tahoma, so the Mac's copies go into the bottle. When winetricks installed Source
    /// Han Sans (cjkfonts and friends), DirectWrite still asks for the Noto names, and Chromium
    /// draws Chinese, Japanese and Korean as boxes until they are aliased. Both from frankea/Whisky
    /// (BottleFontBootstrap.swift, WineFontReplacements.swift; GPL-3.0-or-later).
    static func applyFonts(_ bottle: Bottle, engine: Engine, log: URL) async throws {
        let fonts = bottle.driveC.appendingPathComponent("windows/Fonts", isDirectory: true)
        let copies: [(String, [String])] = [
            ("Arial Unicode.ttf", ["/Library/Fonts/Arial Unicode.ttf"]),
            ("Arial.ttf", ["/Library/Fonts/Arial.ttf", "/System/Library/Fonts/Supplemental/Arial.ttf"]),
            ("Tahoma.ttf", ["/Library/Fonts/Tahoma.ttf", "/System/Library/Fonts/Supplemental/Tahoma.ttf"]),
        ]
        if FileManager.default.fileExists(atPath: fonts.path) {
            for (name, sources) in copies where !FileManager.default.fileExists(atPath: fonts.appendingPathComponent(name).path) {
                guard let source = sources.first(where: FileManager.default.fileExists(atPath:)) else { continue }
                try? FileManager.default.copyItem(atPath: source, toPath: fonts.appendingPathComponent(name).path)
            }
        }

        guard FileManager.default.fileExists(atPath: fonts.appendingPathComponent("sourcehansans.ttc").path) else { return }
        let aliases = [("Noto Sans CJK SC", "Source Han Sans SC"), ("Noto Sans CJK TC", "Source Han Sans TC"),
                       ("Noto Sans CJK JP", "Source Han Sans"), ("Noto Sans CJK KR", "Source Han Sans K")]
        guard let existing = registryValueNames(in: bottle, hive: "user.reg", key: "Software\\\\Wine\\\\Fonts\\\\Replacements")
        else { return }
        let missing = aliases.filter { !existing.contains($0.0.lowercased()) }
        guard !missing.isEmpty else { return }
        var text = "\n[HKEY_CURRENT_USER\\Software\\Wine\\Fonts\\Replacements]\n"
        for (name, target) in missing { text += "\"\(name)\"=\"\(target)\"\n" }
        try await importRegistry(text, into: bottle, engine: engine, log: log)
    }

    /// Value names under one key of a hive file as wine saves it ([Software\\Wine\\...] sections
    /// with doubled backslashes), lowercased; nil when the file cannot be read. Reading the file
    /// needs no wine process; what changed in the last seconds may not be saved yet.
    static func registryValueNames(in bottle: Bottle, hive: String, key: String) -> Set<String>? {
        registryValues(in: bottle, hive: hive, key: key).map { Set($0.keys) }
    }

    /// name (lowercased) -> raw value text ("coreaudio" with quotes removed, dword:00000001 as is)
    static func registryValues(in bottle: Bottle, hive: String, key: String) -> [String: String]? {
        guard let text = try? String(contentsOf: bottle.url.appendingPathComponent(hive), encoding: .utf8) else { return nil }
        var values: [String: String] = [:]
        var inside = false
        let header = "[\(key.lowercased())]"
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("[") {
                inside = line.lowercased().hasPrefix(header)
                continue
            }
            guard inside, line.hasPrefix("\""), let close = line.dropFirst().firstIndex(of: "\""),
                  line[line.index(after: close)...].hasPrefix("=") else { continue }
            var value = String(line[line.index(close, offsetBy: 2)...])
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 { value = String(value.dropFirst().dropLast()) }
            values[String(line[line.index(after: line.startIndex)..<close]).lowercased()] = value
        }
        return values
    }

    /// Starts the Discord bridge in the bottle (it lives until the bottle stops; a second copy
    /// quits at once). Games publish activity to the pipe; the bridge passes it to the Mac app.
    static func startDiscordBridge(_ bottle: Bottle, engine: Engine, environment: [String: String]) {
        guard engine.hasDiscordBridge else { return }
        _ = try? WineProcess.start(engine: engine,
                                   arguments: ["start", "/unix", engine.discordBridge.path, "--dir", NSTemporaryDirectory()],
                                   environment: environment, log: Paths.logFile("\(bottle.name)-discord")) { _ in }
    }
}

/// A bottle that wine created completely: frankea/Whisky's WinePrefixValidation (GPL-3.0-or-later)
enum PrefixCheck {
    enum Problem: Equatable {
        case missingPrefix, missingDriveC, missingUsers, missingUserProfile, missingAppData(String)
    }

    static func problems(in bottle: Bottle) -> [Problem] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: bottle.url.appendingPathComponent("system.reg").path) else { return [.missingPrefix] }
        guard fm.fileExists(atPath: bottle.driveC.path) else { return [.missingDriveC] }
        let users = bottle.driveC.appendingPathComponent("users", isDirectory: true)
        guard let names = try? fm.contentsOfDirectory(atPath: users.path) else { return [.missingUsers] }
        let candidates = names.filter { !$0.hasPrefix(".") && $0 != "Public" }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        guard let user = candidates.first(where: { $0 != "crossover" }) ?? candidates.first else { return [.missingUserProfile] }
        let profile = users.appendingPathComponent(user, isDirectory: true)
        return ["AppData", "AppData/Roaming", "AppData/Local"]
            .filter { !fm.fileExists(atPath: profile.appendingPathComponent($0).path) }
            .map { .missingAppData($0) }
    }

    static func describe(_ problem: Problem) -> String {
        switch problem {
        case .missingPrefix: t("Бутылка ещё не создана или не дописана (нет system.reg)")
        case .missingDriveC: t("В бутылке нет диска C:")
        case .missingUsers: t("В бутылке нет папки пользователей")
        case .missingUserProfile: t("В бутылке нет профиля пользователя")
        case .missingAppData(let path): t("В профиле нет папки \(path.replacingOccurrences(of: "/", with: "\\"))")
        }
    }
}
