import Foundation

/// The engine: our Wine build plus D3DMetal (if imported), DXVK, MoltenVK and the compat module.
struct Engine: Equatable {
    let root: URL

    var wine: URL { root.appendingPathComponent("bin/wine") }
    var wineserver: URL { root.appendingPathComponent("bin/wineserver") }
    var lib: URL { root.appendingPathComponent("lib", isDirectory: true) }
    /// D3DMetal: what the user imported, or for a development engine what scripts/deploy-gptk.sh
    /// put into it
    var gptk: URL {
        if FileManager.default.fileExists(atPath: Paths.d3dmetal.appendingPathComponent("external/libd3dshared.dylib").path) {
            return Paths.d3dmetal
        }
        return lib.appendingPathComponent("apple_gptk", isDirectory: true)
    }
    /// Carries its own libraries instead of Homebrew's (scripts/build-engine.sh portable)
    var isPortable: Bool { FileManager.default.fileExists(atPath: root.appendingPathComponent("engine.json").path) }
    var dxvk: URL { lib.appendingPathComponent("dxvk", isDirectory: true) }
    var compatModule: URL { lib.appendingPathComponent("wine/x86_64-unix/cxcompatdb.so") }
    var discordBridge: URL { lib.appendingPathComponent("winrunner/discord-bridge.exe") }

    var isValid: Bool { FileManager.default.isExecutableFile(atPath: wine.path) }
    var hasCompatModule: Bool { FileManager.default.fileExists(atPath: compatModule.path) }
    var hasDXVK: Bool { FileManager.default.fileExists(atPath: dxvk.appendingPathComponent("x64/d3d11.dll").path) }
    var hasDiscordBridge: Bool { FileManager.default.fileExists(atPath: discordBridge.path) }
    var hasMoltenVK: Bool { FileManager.default.fileExists(atPath: lib.appendingPathComponent("libMoltenVK.dylib").path) }
    var hasMonoAndGecko: Bool {
        let share = root.appendingPathComponent("share/wine")
        let mono = (try? FileManager.default.contentsOfDirectory(atPath: share.appendingPathComponent("mono").path)) ?? []
        let gecko = (try? FileManager.default.contentsOfDirectory(atPath: share.appendingPathComponent("gecko").path)) ?? []
        return mono.contains { $0.hasSuffix(".msi") } && gecko.contains { $0.hasSuffix(".msi") }
    }

    var d3dmetalVersion: String? {
        guard FileManager.default.fileExists(atPath: gptk.appendingPathComponent("external/libd3dshared.dylib").path) else { return nil }
        let text = try? String(contentsOf: gptk.appendingPathComponent("D3DMETAL_VERSION"), encoding: .utf8)
        return text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "?"
    }

    /// The user's choice first, then the engine inside the app, then one in the support folder,
    /// then a development build.
    static func locate(_ settings: AppSettings) -> Engine? {
        let candidates = [settings.enginePath.map { URL(fileURLWithPath: $0, isDirectory: true) },
                          Paths.bundledEngine, Paths.defaultEngine, Paths.devEngine]
        return candidates.compactMap { $0 }.map(Engine.init(root:)).first { $0.isValid }
    }

    /// An app that came as a download carries the quarantine mark into every file of its engine,
    /// and macOS would stop wine from starting; once the user has opened the app, the engine is
    /// trusted along with it.
    func clearQuarantine() async {
        guard getxattr(wine.path, "com.apple.quarantine", nil, 0, 0, 0) >= 0 else { return }
        _ = await Shell.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", root.path])
    }

    func version() async -> String? {
        let result = await Shell.run(wine.path, ["--version"], environment: WineEnvironment.base())
        guard result.status == 0 else { return nil }
        return result.output.split(separator: "\n").last { $0.hasPrefix("wine-") }.map(String.init)
    }
}

/// Wine hands the whole Unix environment to every Windows program, so a program could read
/// tokens and keys from wherever the app was started. Only these pass through.
enum WineEnvironment {
    static let passthrough: Set<String> = ["HOME", "USER", "LOGNAME", "SHELL", "TMPDIR", "LANG", "TERM", "PATH"]

    static func base() -> [String: String] {
        ProcessInfo.processInfo.environment.filter { passthrough.contains($0.key) || $0.key.hasPrefix("LC_") }
    }

    /// - skip: executables that keep wine's own DLLs instead of D3DMetal (read by cxcompatdb.so)
    static func make(engine: Engine, prefix: URL, skip: [String] = [], extra: [String: String] = [:]) -> [String: String] {
        var env = base()
        env["WINEPREFIX"] = prefix.path
        env["WINEDEBUG"] = "-all"
        env["WINEMSYNC"] = "1"
        if engine.isPortable {
            // everything wine opens by name and GStreamer's plugins are inside the engine
            env["DYLD_FALLBACK_LIBRARY_PATH"] = "\(engine.lib.path):/usr/lib"
            env["GST_PLUGIN_SYSTEM_PATH_1_0"] = engine.lib.appendingPathComponent("gstreamer-1.0").path
            env["GST_PLUGIN_SCANNER_1_0"] = engine.root.appendingPathComponent("libexec/gstreamer-1.0/gst-plugin-scanner").path
            env["GST_REGISTRY_1_0"] = Paths.caches.appendingPathComponent("gstreamer-registry-x86_64.bin").path
        } else {
            // MoltenVK from the engine, then x86_64 Homebrew libraries a development engine links by soname
            env["DYLD_FALLBACK_LIBRARY_PATH"] = "\(engine.lib.path):/usr/local/lib:/usr/lib"
            env["GST_PLUGIN_SYSTEM_PATH_1_0"] = "/usr/local/lib/gstreamer-1.0"
        }
        // games that probe cpuid before using AVX/AVX2
        env["ROSETTA_ADVERTISE_AVX"] = "1"
        env["MVK_CONFIG_LOG_LEVEL"] = "1"
        if engine.d3dmetalVersion != nil {
            env["CX_APPLEGPTK_LIBD3DSHARED_PATH"] = engine.gptk.appendingPathComponent("external/libd3dshared.dylib").path
            env["WINRUNNER_D3DMETAL_DIR"] = engine.gptk.appendingPathComponent("wine").path
            env["D3DM_ENABLE_METALFX"] = "1"
            if !skip.isEmpty { env["WINRUNNER_D3DMETAL_SKIP"] = skip.sorted().joined(separator: ",") }
        }
        for (key, value) in extra { env[key] = value }
        return env
    }
}

enum WineProcess {
    /// Starts wine; output goes to `log`. `onExit` gets the exit status.
    static func start(engine: Engine, arguments: [String], environment: [String: String], log: URL,
                      onExit: @escaping @Sendable (Int32) -> Void) throws -> Process {
        try startLogged(executable: engine.wine, arguments: arguments, environment: environment, log: log, onExit: onExit)
    }

    /// Any program with its output appended to `log` (winetricks, for one)
    static func runLogged(executable: URL, arguments: [String], environment: [String: String], log: URL) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            do {
                _ = try startLogged(executable: executable, arguments: arguments, environment: environment, log: log) { status in
                    continuation.resume(returning: status)
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func startLogged(executable: URL, arguments: [String], environment: [String: String], log: URL,
                                    onExit: @escaping @Sendable (Int32) -> Void) throws -> Process {
        try Paths.ensure(log.deletingLastPathComponent())
        // appending: a launcher and what it starts, or a relaunch, may write to one log at once
        let fd = open(log.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard fd >= 0 else { throw AppError("Не открывается журнал \(log.path)") }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = handle
        process.standardError = handle
        process.standardInput = FileHandle.nullDevice
        process.terminationHandler = { finished in
            try? handle.close()
            onExit(finished.terminationStatus)
        }
        try process.run()
        return process
    }

    static func run(engine: Engine, arguments: [String], environment: [String: String], log: URL) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            do {
                _ = try start(engine: engine, arguments: arguments, environment: environment, log: log) { status in
                    continuation.resume(returning: status)
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// wineserver -w (wait for the bottle to go idle) or -k (stop everything in it)
    static func server(_ flag: String, engine: Engine, environment: [String: String]) async {
        await Task.detached {
            let process = Process()
            process.executableURL = engine.wineserver
            process.arguments = [flag]
            process.environment = environment
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return }
            process.waitUntilExit()
        }.value
    }
}
