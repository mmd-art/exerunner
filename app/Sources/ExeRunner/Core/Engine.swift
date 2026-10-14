import Foundation

enum HostArchitecture {
    static let isAppleSilicon: Bool = {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 && value == 1
    }()
}

/// The engine: our Wine build plus D3DMetal (if imported), DXVK, MoltenVK and the compat module.
struct Engine: Equatable {
    let root: URL
    init(root: URL) { self.root = URL(fileURLWithPath: root.standardizedFileURL.path, isDirectory: true) }

    var wine: URL { root.appendingPathComponent("bin/wine") }
    var wineserver: URL { root.appendingPathComponent("bin/wineserver") }
    var lib: URL { root.appendingPathComponent("lib", isDirectory: true) }
    enum D3DMetalSource { case imported, bundled, engine }

    /// D3DMetal: the newer of what the user imported and what the app carries (a user can put in
    /// Apple's next release without waiting for a new app), else what scripts/deploy-gptk.sh put
    /// into a development engine
    var gptk: URL {
        let found = [Paths.d3dmetal, Paths.bundledD3DMetal].compactMap { $0 }
            .filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("external/libd3dshared.dylib").path) }
        if let newest = found.max(by: { D3DMetalVersion($0) < D3DMetalVersion($1) }) { return newest }
        return lib.appendingPathComponent("apple_gptk", isDirectory: true)
    }

    var d3dmetalSource: D3DMetalSource {
        if gptk.standardizedFileURL == Paths.d3dmetal.standardizedFileURL { return .imported }
        if gptk.standardizedFileURL == Paths.bundledD3DMetal?.standardizedFileURL { return .bundled }
        return .engine
    }
    /// Carries its own libraries instead of Homebrew's (scripts/build-engine.sh portable)
    var isPortable: Bool { FileManager.default.fileExists(atPath: root.appendingPathComponent("engine.json").path) }
    var dxvk: URL { lib.appendingPathComponent("dxvk", isDirectory: true) }
    var dxmt: URL { lib.appendingPathComponent("dxmt", isDirectory: true) }
    var dxmtVersion: String? {
        guard hasDXMT else { return nil }
        return try? String(contentsOf: dxmt.appendingPathComponent("DXMT_VERSION"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    var hasDXMT: Bool {
        let required = ["x86_64-windows/d3d11.dll", "x86_64-windows/dxgi.dll",
                        "x86_64-windows/d3d10core.dll", "x86_64-windows/winemetal.dll",
                        "i386-windows/d3d11.dll", "i386-windows/dxgi.dll",
                        "i386-windows/d3d10core.dll", "i386-windows/winemetal.dll",
                        "x86_64-unix/winemetal.so", "DXMT_VERSION"]
        guard required.allSatisfy({ FileManager.default.isReadableFile(atPath: dxmt.appendingPathComponent($0).path) }),
              let module = try? Data(contentsOf: compatModule, options: .mappedIfSafe),
              let display = try? Data(contentsOf: lib.appendingPathComponent("wine/x86_64-unix/win32u.so"), options: .mappedIfSafe) else { return false }
        let modeset = Data("EXERUNNER_EMULATE_MODESET".utf8)
        return module.range(of: Data("EXERUNNER_DXMT_DIR".utf8)) != nil &&
            module.range(of: modeset) != nil && display.range(of: modeset) != nil
    }
    var hasCursorGuard: Bool {
        let marker = Data("EXERUNNER_CURSOR_GUARD".utf8)
        return ["winemac.so", "win32u.so"].allSatisfy { name in
            guard let module = try? Data(contentsOf: lib.appendingPathComponent("wine/x86_64-unix/\(name)"), options: .mappedIfSafe) else { return false }
            return module.range(of: marker) != nil
        }
    }
    var compatModule: URL { lib.appendingPathComponent("wine/x86_64-unix/cxcompatdb.so") }
    var discordBridge: URL { lib.appendingPathComponent("exerunner/discord-bridge.exe") }
    var audioTest: URL { lib.appendingPathComponent("exerunner/audio-test.exe") }

    var supportsPrinting: Bool { module("winspool.so", contains: "cupsGetDests") }
    var supportsUSB: Bool { module("wineusb.so", contains: "libusb_init") }
    var supportsMIDI: Bool { module("winecoreaudio.so", contains: "MIDIClientCreate") }
    var supportsHID: Bool { module("winebus.so", contains: "IOHIDManagerCreate") }
    var hasXInputMapping: Bool {
        module("winebus.so", contains: "SDL_GameControllerOpen") &&
            FileManager.default.isReadableFile(atPath: lib.appendingPathComponent("libSDL2-2.0.0.dylib").path)
    }
    var supportsOpenCL: Bool { module("opencl.so", contains: "clGetPlatformIDs") }
    var recordedVersion: String? {
        guard let data = try? Data(contentsOf: root.appendingPathComponent("engine.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["wine"] as? String
    }
    private func module(_ name: String, contains symbol: String) -> Bool {
        guard let data = try? Data(contentsOf: lib.appendingPathComponent("wine/x86_64-unix/\(name)"), options: .mappedIfSafe) else { return false }
        return data.range(of: Data(symbol.utf8)) != nil
    }

    var isValid: Bool { FileManager.default.isExecutableFile(atPath: wine.path) }
    var hasCompatModule: Bool { FileManager.default.fileExists(atPath: compatModule.path) }
    var hasDXVK: Bool { FileManager.default.fileExists(atPath: dxvk.appendingPathComponent("x64/d3d11.dll").path) }
    var hasVKD3D: Bool {
        hasMoltenVK && ["x86_64-windows/d3d12core.dll", "i386-windows/d3d12core.dll", "x86_64-unix/winevulkan.so"].allSatisfy {
            FileManager.default.isReadableFile(atPath: lib.appendingPathComponent("wine/" + $0).path)
        }
    }
    var hasDiscordBridge: Bool { FileManager.default.fileExists(atPath: discordBridge.path) }
    var hasMoltenVK: Bool { FileManager.default.fileExists(atPath: lib.appendingPathComponent("libMoltenVK.dylib").path) }
    var hasMonoAndGecko: Bool {
        let share = root.appendingPathComponent("share/wine")
        let mono = (try? FileManager.default.contentsOfDirectory(atPath: share.appendingPathComponent("mono").path)) ?? []
        let gecko = (try? FileManager.default.contentsOfDirectory(atPath: share.appendingPathComponent("gecko").path)) ?? []
        return mono.contains { $0.hasSuffix(".msi") } && gecko.contains { $0.hasSuffix(".msi") }
    }

    var d3dmetalVersion: String? {
        guard HostArchitecture.isAppleSilicon, module("cxcompatdb.so", contains: "EXERUNNER_D3DMETAL_DIR"),
              FileManager.default.fileExists(atPath: gptk.appendingPathComponent("external/libd3dshared.dylib").path) else { return nil }
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
        if let d3dmetal = Paths.bundledD3DMetal, FileManager.default.fileExists(atPath: d3dmetal.path) {
            _ = await Shell.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", d3dmetal.path])
        }
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
        let base = makeBase(engine: engine, prefix: prefix, skip: skip, extra: extra)
        if prefix.lastPathComponent.hasPrefix("isolated-") || FileManager.default.fileExists(atPath: prefix.appendingPathComponent(".exerunner-isolated-v1").path) {
            do { return try IsolatedWine.environment(bottle: Bottle(name: prefix.lastPathComponent, root: prefix.deletingLastPathComponent()), engine: engine, base: base) }
            catch {
                // All existing component/diagnostic paths fail closed too.
                var refused = base
                refused["EXERUNNER_SANDBOX_PROFILE"] = "/nonexistent/exerunner-isolation-refused.sb"
                return refused
            }
        }
        return base
    }

    static func makeBase(engine: Engine, prefix: URL, skip: [String] = [], extra: [String: String] = [:]) -> [String: String] {
        var env = base()
        env["WINEPREFIX"] = prefix.path
        env["WINEDEBUG"] = "-all"
        env["WINEMSYNC"] = "1"
        if engine.hasDXMT { env["EXERUNNER_DXMT_DIR"] = engine.dxmt.path }
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
        // DXVK's pipeline cache (<program>.dxvk-cache) survives between runs here, not in the
        // program's folder or wherever it was started
        env["DXVK_STATE_CACHE_PATH"] = Paths.caches.appendingPathComponent("dxvk", isDirectory: true).path
        try? Paths.ensure(Paths.caches.appendingPathComponent("dxvk", isDirectory: true))
        env["MVK_CONFIG_LOG_LEVEL"] = "1"
        if engine.d3dmetalVersion != nil {
            env["CX_APPLEGPTK_LIBD3DSHARED_PATH"] = engine.gptk.appendingPathComponent("external/libd3dshared.dylib").path
            env["EXERUNNER_D3DMETAL_DIR"] = engine.gptk.appendingPathComponent("wine").path
            env["D3DM_ENABLE_METALFX"] = "1"
            if !skip.isEmpty { env["EXERUNNER_D3DMETAL_SKIP"] = skip.sorted().joined(separator: ",") }
        }
        for (key, value) in extra { env[key] = value }
        return env
    }
}

enum WineProcess {
    /// Starts wine; output goes to `log`. `onExit` gets the exit status. A program starts in
    /// `directory` (its own folder, as Explorer and Steam start them: games open their files
    /// relative to it); without one, in the folder this app was started in.
    static func start(engine: Engine, arguments: [String], environment: [String: String], log: URL,
                      directory: URL? = nil, onExit: @escaping @Sendable (Int32) -> Void) throws -> Process {
        try startLogged(executable: engine.wine, arguments: arguments, environment: environment, log: log,
                        directory: directory, onExit: onExit)
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
                                    directory: URL? = nil, onExit: @escaping @Sendable (Int32) -> Void) throws -> Process {
        try Paths.ensure(log.deletingLastPathComponent())
        // appending: a launcher and what it starts, or a relaunch, may write to one log at once
        let fd = open(log.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard fd >= 0 else { throw AppError(t("Не открывается журнал \(log.path)")) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        let process = Process()
        if let profile = environment["EXERUNNER_SANDBOX_PROFILE"] {
            guard FileManager.default.isReadableFile(atPath: profile) else { throw AppError("Missing isolation profile; launch refused") }
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
            // sandbox-exec is platform-signed and strips DYLD variables. Restore the
            // engine's library search path inside the sandbox through env arguments.
            let dyld = environment["DYLD_FALLBACK_LIBRARY_PATH"] ?? "/usr/lib"
            process.arguments = ["-f", profile, "/usr/bin/env", "DYLD_FALLBACK_LIBRARY_PATH=\(dyld)", executable.path] + arguments
        } else {
            process.executableURL = executable
            process.arguments = arguments
        }
        process.environment = environment
        if let directory, FileManager.default.fileExists(atPath: directory.path) { process.currentDirectoryURL = directory }
        process.standardOutput = handle
        process.standardError = handle
        process.standardInput = FileHandle.nullDevice
        process.terminationHandler = { finished in
            try? handle.close()
            onExit(finished.terminationStatus)
        }
        try PrefixLaunchGate.start(process)
        return process
    }

    static func run(engine: Engine, arguments: [String], environment: [String: String], log: URL,
                    directory: URL? = nil) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            do {
                _ = try start(engine: engine, arguments: arguments, environment: environment, log: log, directory: directory) { status in
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
            if let profile = environment["EXERUNNER_SANDBOX_PROFILE"] {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
                process.arguments = ["-f", profile, "/usr/bin/env", "DYLD_FALLBACK_LIBRARY_PATH=\(environment["DYLD_FALLBACK_LIBRARY_PATH"] ?? "/usr/lib")", engine.wineserver.path, flag]
            } else {
                process.executableURL = engine.wineserver
                process.arguments = [flag]
            }
            process.environment = environment
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return }
            process.waitUntilExit()
        }.value
    }
}

/// A D3DMetal version as Apple numbers them: 3.0, 4.0b2 (a beta comes before its release)
struct D3DMetalVersion: Comparable {
    let parts: [Int]
    let beta: Int?

    init(_ folder: URL) {
        let text = (try? String(contentsOf: folder.appendingPathComponent("D3DMETAL_VERSION"), encoding: .utf8)) ?? ""
        self.init(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    init(_ text: String) {
        let lower = text.lowercased()
        let split = lower.range(of: "b")
        let main = split.map { String(lower[..<$0.lowerBound]) } ?? lower
        parts = main.split(separator: ".").map { Int($0) ?? 0 }
        beta = split.map { Int(lower[$0.upperBound...].filter(\.isNumber)) ?? 0 }
    }

    static func < (a: D3DMetalVersion, b: D3DMetalVersion) -> Bool {
        for i in 0..<max(a.parts.count, b.parts.count) {
            let x = i < a.parts.count ? a.parts[i] : 0, y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        switch (a.beta, b.beta) {
        case let (x?, y?): return x < y
        case (_?, nil): return true
        default: return false
        }
    }

    static func == (a: D3DMetalVersion, b: D3DMetalVersion) -> Bool { !(a < b) && !(b < a) }
}
