import Foundation

/// A crash signature: a line of wine's output that says what went wrong. The set comes from
/// frankea/Whisky's patterns.json (GPL-3.0-or-later), converted into compat/crash-patterns.json.
struct CrashPattern: Decodable {
    enum Category: String, Decodable, CaseIterable {
        case coreCrashFatal, graphics, dependenciesLoading, prefixFilesystem, networkingLaunchers, antiCheatUnsupported,
             otherUnknown

        var title: String {
            switch self {
            case .coreCrashFatal: t("Вылет")
            case .graphics: t("Графика")
            case .dependenciesLoading: t("Не хватает компонентов")
            case .prefixFilesystem: t("Бутылка или файлы")
            case .networkingLaunchers: t("Сеть или лаунчер")
            case .antiCheatUnsupported: t("Античит")
            case .otherUnknown: t("Другое")
            }
        }

        /// For a tile's badge, where the full headline does not fit
        var shortTitle: String {
            switch self {
            case .coreCrashFatal: t("Вылет")
            case .graphics: t("Ошибка графики")
            case .dependenciesLoading: t("Нет компонента")
            case .prefixFilesystem: t("Ошибка бутылки")
            case .networkingLaunchers: t("Ошибка сети")
            case .antiCheatUnsupported: t("Античит")
            case .otherUnknown: t("Ошибка")
            }
        }
    }

    enum Severity: String, Decodable, Comparable {
        case info, warning, error, critical
        static func < (a: Severity, b: Severity) -> Bool {
            let order: [Severity] = [.info, .warning, .error, .critical]
            return order.firstIndex(of: a)! < order.firstIndex(of: b)!
        }
    }

    let id: String
    let category: Category
    let severity: Severity
    let confidence: Double
    /// A plain substring every match contains, checked before the expression
    let prefilter: String?
    let regex: String
    /// What the app can offer: install-missing-dll, switch-graphics, raytracing-off, logging-crash,
    /// info:<topic>
    let remedies: [String]
}

struct CrashDiagnosis {
    struct Match {
        let pattern: CrashPattern
        /// 1-based, within the part of the log that was read
        let lineNumber: Int
        let line: String
        let captures: [String]
    }

    /// Strongest first: by the pattern's confidence, then its severity
    let matches: [Match]

    var primary: Match? { matches.first }
    var isEmpty: Bool { matches.isEmpty }

    var confidenceTitle: String {
        guard let confidence = primary?.pattern.confidence else { return "" }
        return confidence >= 0.8 ? t("уверенно") : confidence >= 0.5 ? t("вероятно") : t("возможно")
    }

    var headline: String {
        guard let primary else { return t("В журнале нет известных ошибок") }
        let detail = primary.captures.isEmpty ? "" : ": " + primary.captures.joined(separator: ", ")
        return primary.pattern.category.title + detail
    }

    var categoryCounts: [(category: CrashPattern.Category, count: Int)] {
        let counts = Dictionary(grouping: matches, by: \.pattern.category).mapValues(\.count)
        return counts.map { ($0.key, $0.value) }.sorted { $0.count > $1.count }
    }

    /// Remedy ids of all matches, best match's first, each once
    var remedies: [String] {
        var seen: [String] = []
        for match in matches { for remedy in match.pattern.remedies where !seen.contains(remedy) { seen.append(remedy) } }
        return seen
    }

    /// DLL names the program could not load, from the captures of loading failures
    var missingLibraries: [String] {
        var names: [String] = []
        for match in matches where match.pattern.category == .dependenciesLoading {
            for name in match.captures where name.lowercased().hasSuffix(".dll") && !names.contains(name.lowercased()) {
                names.append(name.lowercased())
            }
        }
        return names
    }
}

final class CrashClassifier: @unchecked Sendable {
    private struct File: Decodable {
        let source: String
        let patterns: [CrashPattern]
    }

    let source: String
    private let compiled: [(pattern: CrashPattern, regex: NSRegularExpression)]

    static let shared = CrashClassifier()

    private init() {
        var source = ""
        var compiled: [(CrashPattern, NSRegularExpression)] = []
        if let dir = Paths.compat, let data = try? Data(contentsOf: dir.appendingPathComponent("crash-patterns.json")) {
            do {
                let file = try JSONDecoder().decode(File.self, from: data)
                source = file.source
                for pattern in file.patterns {
                    // an expression that does not compile never matches, as in Whisky
                    guard let regex = try? NSRegularExpression(pattern: pattern.regex) else { continue }
                    compiled.append((pattern, regex))
                }
            } catch {
                NSLog("crash-patterns.json: \(error)")
            }
        }
        self.source = source
        self.compiled = compiled
    }

    var count: Int { compiled.count }

    /// Every line against every pattern; nothing is merged, the strongest match leads
    func classify(_ text: String) -> CrashDiagnosis {
        classify(text, exitStatus: nil)
    }

    func classify(_ text: String, exitStatus: Int32?) -> CrashDiagnosis {
        var matches: [CrashDiagnosis.Match] = []
        for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = String(line)
            for (pattern, regex) in compiled {
                if let prefilter = pattern.prefilter, !line.contains(prefilter) { continue }
                let range = NSRange(line.startIndex..., in: line)
                guard let hit = regex.firstMatch(in: line, range: range) else { continue }
                let captures: [String] = (1..<max(hit.numberOfRanges, 1)).compactMap {
                    Range(hit.range(at: $0), in: line).map { String(line[$0]) }
                }
                matches.append(.init(pattern: pattern, lineNumber: index + 1, line: line, captures: captures))
            }
        }
        // stable: equal matches keep the order of the log
        let ordered = matches.enumerated().sorted { a, b in
            if a.element.pattern.confidence != b.element.pattern.confidence {
                return a.element.pattern.confidence > b.element.pattern.confidence
            }
            if a.element.pattern.severity != b.element.pattern.severity {
                return a.element.pattern.severity > b.element.pattern.severity
            }
            return a.offset < b.offset
        }.map(\.element)
        // Some applications deliberately exit with an error and leave no explanatory log line.
        // Preserve a known diagnosis; otherwise surface the observed exit without guessing a cause.
        if let exitStatus, exitStatus != 0, (ordered.first?.pattern.severity ?? .info) < .error {
            let pattern = CrashPattern(id: "process-exit", category: .otherUnknown, severity: .error,
                                       confidence: 1, prefilter: nil, regex: "", remedies: ["logging-crash"])
            let match = CrashDiagnosis.Match(pattern: pattern, lineNumber: 0,
                line: t("Приложение завершилось с кодом \(exitStatus), но журнал не объясняет причину."),
                captures: [t("код завершения \(exitStatus)")])
            return CrashDiagnosis(matches: [match] + ordered)
        }
        return CrashDiagnosis(matches: ordered)
    }

    /// Whisky's trigger for looking at a run that exited normally
    static func looksLikeCrash(_ text: String) -> Bool {
        let tail = text.suffix(64 * 1024)
        return ["Unhandled exception", "page fault", "device lost", "DEVICE_REMOVED", "DEVICE_HUNG", "Fatal error", "import_dll"]
            .contains { tail.contains($0) }
    }
}

/// A launch's output: the log file and where in it the launch began. A game a running Steam
/// starts writes into Steam's log, so its part starts at the offset where Steam was handed it.
struct LogSegment {
    let url: URL
    var offset: UInt64 = 0

    /// What the classifier reads: everything when short, else the first 200 and last 500 lines
    /// (frankea/Whisky's window in Wine.classifyLastRun)
    func window() -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return nil }
        guard end > offset else { return "" }
        let size = end - offset
        if size <= 320 * 1024 {
            try? handle.seek(toOffset: offset)
            let text = String(decoding: (try? handle.read(upToCount: Int(size))) ?? Data(), as: UTF8.self)
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            guard lines.count > 700 else { return text }
            return (Array(lines.prefix(200)) + ["…"] + Array(lines.suffix(500))).joined(separator: "\n")
        }
        try? handle.seek(toOffset: offset)
        var head = String(decoding: (try? handle.read(upToCount: 64 * 1024)) ?? Data(), as: UTF8.self)
        if let cut = head.lastIndex(of: "\n") { head = String(head[..<cut]) }
        try? handle.seek(toOffset: end - 256 * 1024)
        var tail = String(decoding: (try? handle.read(upToCount: 256 * 1024)) ?? Data(), as: UTF8.self)
        if let cut = tail.firstIndex(of: "\n") { tail = String(tail[tail.index(after: cut)...]) }
        let headLines = head.split(separator: "\n", omittingEmptySubsequences: false).prefix(200)
        let tailLines = tail.split(separator: "\n", omittingEmptySubsequences: false).suffix(500)
        return (Array(headLines) + ["…"] + Array(tailLines)).joined(separator: "\n")
    }

    var size: UInt64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.uint64Value ?? 0
    }
}

/// The winetricks component that provides a Windows library a program failed to load
enum MissingLibrary {
    private static let providers: [(prefix: String, verb: String)] = [
        ("msvcp140", "vcrun2022"), ("vcruntime140", "vcrun2022"), ("concrt140", "vcrun2022"), ("vcomp140", "vcrun2022"),
        ("mfc140", "vcrun2022"), ("vccorlib140", "vcrun2022"),
        ("msvcp120", "vcrun2013"), ("msvcr120", "vcrun2013"), ("vcomp120", "vcrun2013"), ("mfc120", "vcrun2013"),
        ("msvcp110", "vcrun2012"), ("msvcr110", "vcrun2012"), ("mfc110", "vcrun2012"),
        ("msvcp100", "vcrun2010"), ("msvcr100", "vcrun2010"), ("mfc100", "vcrun2010"), ("atl100", "vcrun2010"),
        ("msvcp90", "vcrun2008"), ("msvcr90", "vcrun2008"),
        ("msvcp80", "vcrun2005"), ("msvcr80", "vcrun2005"),
        ("d3dcompiler_43", "d3dcompiler_43"), ("d3dcompiler_", "d3dcompiler_47"),
        ("d3dx9_", "d3dx9"), ("d3dx10_", "d3dx10"), ("d3dx11_", "d3dx11_43"),
        ("xinput", "xinput"), ("xaudio2_", "xact"), ("x3daudio", "xact"), ("xapofx", "xact"),
        ("mscoree", "dotnet48"), ("mscorlib", "dotnet48"), ("fusion", "dotnet48"),
        ("physxloader", "physx"), ("physx3", "physx"),
        ("msxml3", "msxml3"), ("msxml6", "msxml6"),
    ]

    static func verb(for dll: String) -> String? {
        let name = dll.lowercased()
        return providers.first { name.hasPrefix($0.prefix) }?.verb
    }
}

/// Takes the user out of what leaves the Mac: the home folder and user name, and anything that
/// looks like a secret. Rules from frankea/Whisky's Redactor.swift (GPL-3.0-or-later); the user
/// name in Windows paths (wine names the profile C:\users\<Mac user>) is ours.
enum Redactor {
    static let placeholder = "<redacted>"

    static func text(_ text: String) -> String { secrets(homePaths(text)) }

    static func homePaths(_ text: String) -> String {
        var home = NSHomeDirectory()
        while home.hasSuffix("/") { home.removeLast() }
        var result = text.replacingOccurrences(of: home, with: "/Users/\(placeholder)")
        let user = NSUserName()
        if !user.isEmpty {
            result = result.replacingOccurrences(of: "\\users\\\(user)", with: "\\users\\\(placeholder)", options: .caseInsensitive)
        }
        return result
    }

    private static let word = "(?:token|secret|password|passwd|pwd|pass|auth|credential|api[_-]?key|access[_-]?key|private[_-]?key|key)"
    private static let rules: [(NSRegularExpression, String)] = [
        ("\\b([\\w.-]*\(word))(\\s*(?::=|[:=])\\s*)(\"[^\"]*\"|'[^']*'|[^\\s\"'&]+)", "$1$2\(placeholder)"),
        ("(?<![\\w-])(--?[\\w-]*\(word))(\\s+)([^\\s\"'-][^\\s\"']*)", "$1$2\(placeholder)"),
        ("\\b(Bearer|Basic)(\\s+)[A-Za-z0-9._~+/=-]{8,}", "$1$2\(placeholder)"),
        ("([a-z][a-z0-9+.-]*://)[^/\\s:@]+(?::[^/\\s@]*)?@", "$1\(placeholder)@"),
        ("([?&][\\w-]*(?:\(word)|sig|signature)=)([^&\\s\"']+)", "$1\(placeholder)"),
        ("\\beyJ[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}", placeholder),
    ].compactMap { pattern, template in
        (try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)).map { ($0, template) }
    }

    static func secrets(_ text: String) -> String {
        var result = text
        for (regex, template) in rules {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result),
                                                    withTemplate: template)
        }
        return result
    }

    /// Names that hint at a secret are dropped; the rest keep their values, with the home folder
    /// and the account name (USER, LOGNAME) hidden
    static func environment(_ env: [String: String]) -> [String: String] {
        let sensitive = ["TOKEN", "KEY", "SECRET", "PASSWORD", "AUTH"]
        let user = NSUserName()
        return env.filter { key, _ in !sensitive.contains { key.uppercased().contains($0) } }
            .mapValues { $0 == user ? placeholder : homePaths($0) }
    }
}

/// Unreal Engine games catch their own crashes: wine's log stays clean, and the game writes
/// <Project>/Saved/Crashes/<id>/CrashContext.runtime-xml, in its folder or in the user's
/// AppData\Local, with the error, the thread and the renderer.
enum UnrealCrashReport {
    struct Report {
        let error: String
        let thread: String?
        let renderer: String?
        let adapter: String?
        let date: Date
        let file: URL
    }

    /// The newest report written after `since` (a little slack for clocks), under any of `roots`
    static func latest(in roots: [URL], since: Date?) -> Report? {
        let fm = FileManager.default
        var newest: (Date, URL)?
        for root in roots {
            guard let walk = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                           options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in walk {
                guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                if url.lastPathComponent.caseInsensitiveCompare("Crashes") == .orderedSame,
                   url.deletingLastPathComponent().lastPathComponent.caseInsensitiveCompare("Saved") == .orderedSame {
                    walk.skipDescendants()
                    for report in (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? [] {
                        let context = report.appendingPathComponent("CrashContext.runtime-xml")
                        guard let date = (try? fm.attributesOfItem(atPath: context.path))?[.modificationDate] as? Date else { continue }
                        if let since, date < since.addingTimeInterval(-5) { continue }
                        if newest == nil || date > newest!.0 { newest = (date, context) }
                    }
                } else if walk.level >= 4 || ["content", "paks", "movies", "binaries"].contains(url.lastPathComponent.lowercased()) {
                    walk.skipDescendants()
                }
            }
        }
        guard let (date, file) = newest, let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        func field(_ name: String) -> String? {
            guard let range = text.range(of: "<\(name)>(.*?)</\(name)>", options: .regularExpression) else { return nil }
            let value = text[range].dropFirst(name.count + 2).dropLast(name.count + 3)
            return value.isEmpty ? nil : String(value)
        }
        let thread = text.range(of: "<IsCrashed>true</IsCrashed>\\s*<ThreadID>[0-9]+</ThreadID>\\s*<ThreadName>[^<]+</ThreadName>",
                                options: .regularExpression)
            .flatMap { match in text[match].range(of: "(?<=<ThreadName>)[^<]+", options: .regularExpression).map { String(text[$0]) } }
        return Report(error: field("ErrorMessage") ?? t("без описания"), thread: thread, renderer: field("RHI.RHIName"),
                      adapter: field("RHI.AdapterName"), date: date, file: file)
    }

    static let pattern = CrashPattern(id: "unreal-crash", category: .coreCrashFatal, severity: .critical, confidence: 0.9,
                                      prefilter: nil, regex: "",
                                      remedies: ["info:frame-generation", "metalfx-off", "switch-graphics", "logging-crash"])

    static func diagnosis(_ report: Report) -> CrashDiagnosis {
        var line = report.error
        if let thread = report.thread { line += t(" (поток \(thread))") }
        if let renderer = report.renderer { line += ", \(renderer)" + (report.adapter.map { t(" на «\($0)»") } ?? "") }
        return CrashDiagnosis(matches: [.init(pattern: pattern, lineNumber: 0, line: line, captures: [report.error])])
    }
}
