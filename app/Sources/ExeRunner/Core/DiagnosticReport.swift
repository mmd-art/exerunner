import Foundation

/// A zip to hand to whoever helps: the Mac, the engine, the bottle and the program's settings,
/// what the helper found, and the last launch's log, with the user's name and anything that looks
/// like a secret taken out. Its contents follow frankea/Whisky's DiagnosticExporter
/// (GPL-3.0-or-later); the JSON here goes through JSONSerialization, so any text is valid in it.
enum DiagnosticReport {
    struct Input {
        var item: LibraryItem
        var effectiveGraphics: LibraryItem.Graphics
        var recipe: Recipe?
        var profile: GameProfile?
        var bottle: Bottle
        var bottleSettings: BottleSettings
        var system: SystemInfo
        var rosetta: Bool
        var engine: [String: String]
        var environment: [String: String]
        var diagnosis: CrashDiagnosis?
        var checks: [Check]
        var log: LogSegment?
        var prefixProblems: [String]
        var winetricks: [String]
        /// Programs running in the bottle when the report was made
        var processes: [String]
    }

    /// A log up to this size goes in whole, a larger one as its first and last lines
    static let fullLogLimit: UInt64 = 4 * 1024 * 1024

    static func export(_ input: Input, to folder: URL) async throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "\(AppInfo.name)-Report-\(safe(input.item.name))-\(formatter.string(from: Date()))"
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let work = scratch.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        try markdown(input).write(to: work.appendingPathComponent("report.md"), atomically: true, encoding: .utf8)
        try json(settings(input), to: work.appendingPathComponent("settings.json"))
        try json(system(input), to: work.appendingPathComponent("system.json"))
        try json(Redactor.environment(input.environment), to: work.appendingPathComponent("environment.json"))
        try json(input.checks.map { ["title": $0.title, "status": $0.status.label, "detail": Redactor.text($0.detail)] },
                 to: work.appendingPathComponent("checks.json"))
        if let diagnosis = input.diagnosis { try json(diagnosisJSON(diagnosis), to: work.appendingPathComponent("diagnosis.json")) }
        if let log = input.log, let text = logText(log) {
            try Redactor.text(text).write(to: work.appendingPathComponent("wine.log"), atomically: true, encoding: .utf8)
        }

        let zip = folder.appendingPathComponent(name + ".zip")
        try? FileManager.default.removeItem(at: zip)
        // no AppleDouble files: the zip goes to people on other systems
        let result = await Shell.run("/usr/bin/ditto", ["-c", "-k", "--norsrc", "--noextattr", "--noqtn", "--keepParent", work.path, zip.path])
        guard result.status == 0 else { throw AppError("ditto: \(result.output)") }
        return zip
    }

    private static func safe(_ name: String) -> String {
        var result = name.replacingOccurrences(of: "[^A-Za-z0-9]+", with: "-", options: .regularExpression)
        while result.hasPrefix("-") { result.removeFirst() }
        while result.hasSuffix("-") { result.removeLast() }
        return result.isEmpty ? "program" : result
    }

    private static func json(_ value: Any, to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url)
    }

    /// The launch's part of the log: whole when it is small enough, else the classifier's window
    private static func logText(_ log: LogSegment) -> String? {
        let size = log.size
        guard size > log.offset else { return nil }
        if size - log.offset <= fullLogLimit, let handle = try? FileHandle(forReadingFrom: log.url) {
            defer { try? handle.close() }
            try? handle.seek(toOffset: log.offset)
            return String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)
        }
        return log.window().map { "(first 200 and last 500 lines of \(size - log.offset) bytes)\n" + $0 }
    }

    private static func settings(_ input: Input) -> [String: Any] {
        let item = input.item
        var program: [String: Any] = [
            "name": item.name,
            "kind": item.kind.rawValue,
            "bottle": item.bottle,
            "executable": Redactor.homePaths(item.executable),
            "arguments": item.arguments.map(Redactor.text),
            "graphics": item.graphics.rawValue,
            "effectiveGraphics": input.effectiveGraphics.rawValue,
            "useRecommended": item.useRecommended,
            "metalFX": item.metalFX,
            "raytracing": item.raytracing,
            "performanceHUD": item.performanceHUD,
            "logging": item.logging.rawValue,
            "locale": item.locale ?? "default",
            "extraEnvironment": Redactor.environment(item.extraEnvironment),
        ]
        if let appID = item.steamAppID { program["steamAppID"] = appID }
        var result: [String: Any] = [
            "program": program,
            "bottle": [
                "name": input.bottle.name,
                "audioDriver": input.bottleSettings.audioDriver.rawValue,
                "audioLatency": input.bottleSettings.audioLatency.rawValue,
                "discordBridge": input.bottleSettings.discordBridge,
                "winetricks": input.winetricks,
                "prefixProblems": input.prefixProblems,
                "runningPrograms": input.processes,
            ] as [String: Any],
        ]
        if let recipe = input.recipe { result["recipe"] = ["id": recipe.id, "status": recipe.status.rawValue] }
        if let profile = input.profile {
            result["compatibility"] = ["id": profile.id, "title": profile.title, "rating": profile.rating,
                                       "recommendedGraphics": profile.recommended.graphics.rawValue,
                                       "winetricks": profile.recommended.winetricks]
        }
        return result
    }

    private static func system(_ input: Input) -> [String: Any] {
        ["macOS": input.system.macOS, "chip": input.system.chip, "appleSilicon": input.system.isAppleSilicon,
         "memoryGB": input.system.memoryGB, "freeDiskGB": input.system.freeDiskGB, "rosetta": input.rosetta,
         "engine": input.engine.mapValues(Redactor.homePaths)]
    }

    private static func diagnosisJSON(_ diagnosis: CrashDiagnosis) -> [String: Any] {
        var result: [String: Any] = [
            "headline": diagnosis.headline,
            "matchCount": diagnosis.matches.count,
            "remedies": diagnosis.remedies,
            "categoryCounts": Dictionary(uniqueKeysWithValues: diagnosis.categoryCounts.map { ($0.category.rawValue, $0.count) }),
            "topMatches": diagnosis.matches.prefix(20).map { match in
                ["pattern": match.pattern.id, "category": match.pattern.category.rawValue,
                 "severity": match.pattern.severity.rawValue, "confidence": match.pattern.confidence,
                 "line": match.lineNumber, "captures": match.captures.map(Redactor.text)] as [String: Any]
            },
        ]
        if let primary = diagnosis.primary {
            result["primaryCategory"] = primary.pattern.category.rawValue
            result["primaryConfidence"] = primary.pattern.confidence
        }
        return result
    }

    private static func markdown(_ input: Input) -> String {
        let item = input.item
        var lines = [
            "# \(AppInfo.name) diagnostic report",
            "",
            "Generated: \(ISO8601DateFormatter().string(from: Date()))",
            "",
            "## System",
            "- macOS \(input.system.macOS), \(input.system.chip), \(input.system.memoryGB) GB RAM, \(input.system.freeDiskGB) GB free",
            "- Rosetta: \(input.rosetta ? "installed" : "missing")",
            "- Engine: \(input.engine["version"] ?? "?"), D3DMetal \(input.engine["d3dmetal"] ?? "none")",
            "",
            "## Program",
            "- \(item.name) (\(item.kind.rawValue)) in bottle \(item.bottle)",
            "- Executable: \(Redactor.homePaths(item.executable))",
            "- Graphics: \(input.effectiveGraphics.rawValue) (set to \(item.graphics.rawValue)), log level \(item.logging.rawValue)",
        ]
        if let recipe = input.recipe { lines.append("- Recipe: \(recipe.id) (\(recipe.status.rawValue))") }
        if let profile = input.profile { lines.append("- Compatibility database: \(profile.title), \(profile.rating)") }
        if !input.prefixProblems.isEmpty { lines.append("- Bottle problems: \(input.prefixProblems.joined(separator: "; "))") }
        if let diagnosis = input.diagnosis, let primary = diagnosis.primary {
            lines += ["", "## Last launch",
                      "- \(primary.pattern.category.rawValue): \(primary.captures.map(Redactor.text).joined(separator: ", ")) (confidence \(primary.pattern.confidence))",
                      "- Matches: " + diagnosis.categoryCounts.map { "\($0.category.rawValue) \($0.count)" }.joined(separator: ", ")]
            for match in diagnosis.matches.prefix(5) {
                lines.append("  - `\(match.pattern.id)` line \(match.lineNumber): `\(Redactor.text(String(match.line.prefix(200))))`")
            }
        } else if input.log != nil {
            lines += ["", "## Last launch", "- No known error patterns in the log"]
        }
        if !input.checks.isEmpty {
            lines += ["", "## Checks"]
            for check in input.checks { lines.append("- [\(check.status.label)] \(check.title): \(Redactor.text(check.detail))") }
        }
        lines += ["", "## Environment keys", Redactor.environment(input.environment).keys.sorted().joined(separator: ", "), ""]
        return lines.joined(separator: "\n")
    }
}
