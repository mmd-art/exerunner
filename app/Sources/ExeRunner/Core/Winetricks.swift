import Foundation

/// Windows components are installed on demand, recorded individually and cached by winetricks.
enum Winetricks {
    typealias Runner = @Sendable (URL, [String], [String: String], URL) async throws -> Int32
    static func script(in engine: Engine) -> URL { engine.root.appendingPathComponent("bin/winetricks") }
    private static func stamp(_ bottle: Bottle) -> URL { bottle.url.appendingPathComponent(".exerunner-winetricks") }

    private static func unverified(_ bottle: Bottle) -> URL { bottle.url.appendingPathComponent(".exerunner-winetricks-unverified") }

    static func validVerb(_ verb: String) -> Bool {
        !verb.isEmpty && verb.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 95 }
    }

    static func available(in engine: Engine) -> Set<String> {
        guard let text = try? String(contentsOf: script(in: engine), encoding: .utf8) else { return [] }
        return Set(text.split(separator: "\n").compactMap { line in
            let words = line.split(whereSeparator: \.isWhitespace)
            guard words.count >= 2, words[0] == "w_metadata", validVerb(String(words[1])) else { return nil }
            return String(words[1])
        })
    }

    private static func records(at file: URL) -> Set<String> {
        Set(((try? String(contentsOf: file, encoding: .utf8)) ?? "")
            .split(whereSeparator: \.isWhitespace).map(String.init).filter(validVerb))
    }

    static func installed(in bottle: Bottle) -> Set<String> {
        // Upstream logs a verb before final verification. Never treat an interrupted or
        // failed ExeRunner-managed install as successful solely because that log exists.
        records(at: stamp(bottle)).union(records(at: bottle.url.appendingPathComponent("winetricks.log"))
            .subtracting(records(at: unverified(bottle))))
    }

    static func satisfies(_ verb: String, installed: Set<String>) -> Bool {
        if installed.contains(verb) { return true }
        if verb == "vcrun2022", installed.contains("vcrun2026") { return true }
        for major in ["8", "9", "10"] where verb == "dotnet\(major)" {
            if installed.contains("dotnetdesktop\(major)") { return true }
        }
        return false
    }

    static func missing(_ verbs: [String], in bottle: Bottle) -> [String] {
        let done = installed(in: bottle)
        var result: [String] = []
        for verb in verbs where !satisfies(verb, installed: done) && !result.contains(verb) { result.append(verb) }
        return result
    }

    /// Each successful package is committed before the next begins. A later failure does not
    /// erase progress or mark the failed package installed. Never implicitly force conflicts.
    static func ensure(_ verbs: [String], in bottle: Bottle, engine: Engine, log: URL, progress: (String) -> Void,
                       runner: Runner = { try await WineProcess.runLogged(executable: $0, arguments: $1, environment: $2, log: $3) }) async throws {
        let pending = missing(verbs, in: bottle)
        guard !pending.isEmpty else { return }
        guard !bottle.name.hasPrefix("isolated-"),
              !FileManager.default.fileExists(atPath: bottle.url.appendingPathComponent(".exerunner-isolated-v1").path) else {
            throw AppError(t("Автоматическая установка компонентов в изолированном прототипе пока недоступна."))
        }
        let script = script(in: engine), supported = available(in: engine)
        guard pending.allSatisfy({ validVerb($0) && supported.contains($0) }) else {
            throw AppError(t("В текущем движке нет запрошенных компонентов: \(pending.filter { !supported.contains($0) }.joined(separator: ", "))"))
        }
        let lease = try PrefixComponentLease.installation(in: bottle.url)
        defer { lease.release() }
        guard !WineProcesses.list().contains(where: { $0.prefix == bottle.prefixPath }) else {
            throw AppError(t("Сначала закрой программы этой бутылки, чтобы установить библиотеки Windows."))
        }
        var env = WineEnvironment.make(engine: engine, prefix: bottle.url)
        env["EXERUNNER_COMPONENT_INSTALL"] = "1"
        env["EXERUNNER_WINE"] = engine.wine.path
        env["EXERUNNER_DYLD_FALLBACK_LIBRARY_PATH"] = env["DYLD_FALLBACK_LIBRARY_PATH"]
        env["WINE"] = try wineWrapper().path
        env["WINE_BIN"] = engine.wine.path
        env["WINESERVER"] = engine.wineserver.path
        env["WINETRICKS_LATEST_VERSION_CHECK"] = "disabled"
        env["PATH"] = "\(engine.root.appendingPathComponent("bin").path):/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"
        for verb in pending {
            try Task.checkCancellation()
            // Earlier entries in the same batch may now satisfy this requirement.
            guard !missing([verb], in: bottle).isEmpty else { continue }
            var uncertain = records(at: unverified(bottle))
            uncertain.insert(verb)
            try uncertain.sorted().joined(separator: "\n").write(to: unverified(bottle), atomically: true, encoding: .utf8)
            progress(t("Устанавливаю компонент \(verb)…"))
            let status = try await runner(URL(fileURLWithPath: "/bin/sh"), [script.path, "-q", verb], env, log)
            guard status == 0 else { throw AppError(t("winetricks не поставил \(verb) (код \(status)). Журнал: \(log.path)")) }
            var done = installed(in: bottle)
            done.insert(verb)
            try done.sorted().joined(separator: "\n").write(to: stamp(bottle), atomically: true, encoding: .utf8)
            uncertain.remove(verb)
            try uncertain.sorted().joined(separator: "\n").write(to: unverified(bottle), atomically: true, encoding: .utf8)
        }
    }

    static func wineWrapper() throws -> URL {
        let wrapper = Paths.caches.appendingPathComponent("winetricks-wine")
        let script = """
            #!/bin/sh
            export DYLD_FALLBACK_LIBRARY_PATH="$EXERUNNER_DYLD_FALLBACK_LIBRARY_PATH"
            exec "$EXERUNNER_WINE" "$@"

            """
        try Paths.ensure(Paths.caches)
        if (try? String(contentsOf: wrapper, encoding: .utf8)) != script {
            try script.write(to: wrapper, atomically: true, encoding: .utf8)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapper.path)
        return wrapper
    }
}
