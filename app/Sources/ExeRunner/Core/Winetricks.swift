import Foundation

/// Windows components (Visual C++ runtimes, .NET, fonts, ...) through winetricks, which the
/// engine ships in bin/. What a bottle already has is remembered in it.
enum Winetricks {
    static func script(in engine: Engine) -> URL { engine.root.appendingPathComponent("bin/winetricks") }

    static func installed(in bottle: Bottle) -> Set<String> {
        Set(((try? String(contentsOf: stamp(bottle), encoding: .utf8)) ?? "").split(separator: "\n").map(String.init))
    }

    private static func stamp(_ bottle: Bottle) -> URL { bottle.url.appendingPathComponent(".exerunner-winetricks") }

    static func missing(_ verbs: [String], in bottle: Bottle) -> [String] {
        let done = installed(in: bottle)
        var missing: [String] = []
        for verb in verbs where !done.contains(verb) && !missing.contains(verb) { missing.append(verb) }
        return missing
    }

    /// Winetricks waits for the bottle to go idle between components, so nothing else may run in
    /// it meanwhile (the app stops the bottle first)
    static func ensure(_ verbs: [String], in bottle: Bottle, engine: Engine, log: URL, progress: (String) -> Void) async throws {
        let done = installed(in: bottle)
        let missing = missing(verbs, in: bottle)
        guard !missing.isEmpty else { return }
        let script = script(in: engine)
        guard FileManager.default.fileExists(atPath: script.path) else {
            throw AppError("В движке нет winetricks, а он нужен для: \(missing.joined(separator: ", "))")
        }
        progress("Ставлю компоненты Windows: \(missing.joined(separator: ", "))… Первый раз это несколько минут.")
        var env = WineEnvironment.make(engine: engine, prefix: bottle.url)
        env["WINE"] = engine.wine.path
        env["WINESERVER"] = engine.wineserver.path
        env["WINETRICKS_LATEST_VERSION_CHECK"] = "disabled"
        // cabextract comes with a portable engine, a development Mac has it from Homebrew; unzip
        // and curl are the system's
        env["PATH"] = "\(engine.root.appendingPathComponent("bin").path):/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"
        let status = try await WineProcess.runLogged(executable: URL(fileURLWithPath: "/bin/sh"),
                                                     arguments: [script.path, "-q"] + missing, environment: env, log: log)
        guard status == 0 else {
            throw AppError("winetricks не поставил \(missing.joined(separator: ", ")) (код \(status)). Журнал: \(log.path)")
        }
        try done.union(missing).sorted().joined(separator: "\n").write(to: stamp(bottle), atomically: true, encoding: .utf8)
    }
}
