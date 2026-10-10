import Foundation

/// What belongs to a bottle rather than to one program in it: Windows audio, the Discord bridge.
/// Stored in bottles.json next to the library, by bottle name.
struct BottleSettings: Codable, Equatable {
    /// HKCU\Software\Wine\Drivers "Audio"
    enum AudioDriver: String, Codable, CaseIterable, Identifiable {
        case automatic, coreaudio, disabled
        var id: String { rawValue }
        var title: String {
            switch self {
            case .automatic: "Автоматически"
            case .coreaudio: "CoreAudio"
            case .disabled: "Выключен"
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
            case .standard: "Обычный"
            case .low: "Низкая задержка"
            case .stable: "Большой, без треска"
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

    var audioDriver = AudioDriver.automatic
    var audioLatency = AudioLatency.standard
    /// Relay games' Discord activity to the Discord app on the Mac
    var discordBridge = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
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
    /// Imports a REGEDIT4 file into the bottle. The values are live for every process once
    /// regedit exits; wineserver writes them to user.reg and system.reg a little later.
    static func importRegistry(_ text: String, into bottle: Bottle, engine: Engine, log: URL) async throws {
        let name = "exerunner-\(UUID().uuidString.prefix(8)).reg"
        let file = bottle.driveC.appendingPathComponent(name)
        try ("REGEDIT4\n" + text).write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let env = WineEnvironment.make(engine: engine, prefix: bottle.url)
        _ = try await WineProcess.run(engine: engine, arguments: ["regedit", "/S", "C:\\\(name)"], environment: env, log: log)
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
        case .missingPrefix: "Бутылка ещё не создана или не дописана (нет system.reg)"
        case .missingDriveC: "В бутылке нет диска C:"
        case .missingUsers: "В бутылке нет папки пользователей"
        case .missingUserProfile: "В бутылке нет профиля пользователя"
        case .missingAppData(let path): "В профиле нет папки \(path.replacingOccurrences(of: "/", with: "\\"))"
        }
    }
}
