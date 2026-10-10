import Foundation

/// A Wine prefix. The app hides them: each launcher gets its own, programs share one.
struct Bottle {
    let name: String
    let url: URL

    init(name: String, root: URL) {
        self.name = name
        url = root.appendingPathComponent(name, isDirectory: true)
    }

    var exists: Bool { FileManager.default.fileExists(atPath: url.appendingPathComponent("system.reg").path) }
    var driveC: URL { url.appendingPathComponent("drive_c", isDirectory: true) }

    /// C:\Program Files (x86)\Steam\Steam.exe -> <bottle>/drive_c/Program Files (x86)/Steam/Steam.exe.
    /// Other drive letters go through the bottle's dosdevices links (Z: is the Mac's /).
    func hostURL(forWindowsPath path: String) -> URL? {
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        let chars = Array(path)
        guard chars.count >= 3, chars[1] == ":", chars[2] == "\\" || chars[2] == "/" else { return nil }
        let drive = chars[0].lowercased()
        let rest = String(chars.dropFirst(3)).replacingOccurrences(of: "\\", with: "/")
        var base = driveC
        if drive != "c" {
            let link = url.appendingPathComponent("dosdevices/\(drive):")
            guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path) else { return nil }
            base = URL(fileURLWithPath: target, relativeTo: link.deletingLastPathComponent()).standardizedFileURL
        }
        return rest.isEmpty ? base : base.appendingPathComponent(rest)
    }

    /// The bottle as WINEPREFIX names it in a running process's environment
    var prefixPath: String { url.standardizedFileURL.path }
}

enum BottleManager {
    static func ensure(_ bottle: Bottle, engine: Engine, log: URL) async throws {
        if bottle.exists { return }
        try Paths.ensure(bottle.url.deletingLastPathComponent())
        let env = WineEnvironment.make(engine: engine, prefix: bottle.url)
        _ = try await WineProcess.run(engine: engine, arguments: ["wineboot", "--init"], environment: env, log: log)
        await WineProcess.server("-w", engine: engine, environment: env)
        guard bottle.exists else { throw AppError("Не удалось создать бутылку «\(bottle.name)». Подробности в журнале.") }
    }

    static func stop(_ bottle: Bottle, engine: Engine) async {
        await WineProcess.server("-k", engine: engine, environment: WineEnvironment.make(engine: engine, prefix: bottle.url))
    }

    /// DXVK's DLL names (d3d11, d3d10core, ...), which a program set to DXVK loads as native
    static func dxvkLibraries(_ engine: Engine) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: engine.dxvk.appendingPathComponent("x64").path)) ?? [])
            .filter { $0.hasSuffix(".dll") }.map { String($0.dropLast(4)) }.sorted()
    }

    /// DXVK's DLLs inside the bottle; only programs with a native override load them
    static func installDXVK(_ bottle: Bottle, engine: Engine) throws {
        guard engine.hasDXVK else { throw AppError("В движке нет DXVK") }
        for (arch, dir) in [("x64", "system32"), ("x32", "syswow64")] {
            let source = engine.dxvk.appendingPathComponent(arch, isDirectory: true)
            let target = bottle.driveC.appendingPathComponent("windows/\(dir)", isDirectory: true)
            for name in try FileManager.default.contentsOfDirectory(atPath: source.path) where name.hasSuffix(".dll") {
                let from = source.appendingPathComponent(name), to = target.appendingPathComponent(name)
                if FileManager.default.contentsEqual(atPath: from.path, andPath: to.path) { continue }
                try? FileManager.default.removeItem(at: to)
                try FileManager.default.copyItem(at: from, to: to)
            }
        }
    }

    /// Per-program DLL overrides through AppDefaults (program -> dll -> mode). Exactly these stay
    /// in place: overrides of programs dropped since the last call are deleted.
    static func applyOverrides(_ bottle: Bottle, engine: Engine, overrides: [String: [String: String]], log: URL) async throws {
        let stamp = bottle.url.appendingPathComponent(".exerunner-overrides")
        let wanted = overrides.flatMap { exe, dlls in dlls.map { "\(exe)\t\($0.key)=\($0.value)" } }.sorted().joined(separator: "\n")
        let previous = (try? String(contentsOf: stamp, encoding: .utf8)) ?? ""
        if previous == wanted { return }
        // the first version kept only DXVK programs, in another file
        let legacy = bottle.url.appendingPathComponent(".exerunner-dxvk")
        let legacyNames = ((try? String(contentsOf: legacy, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
        let previousNames = Set(previous.split(separator: "\n").compactMap { $0.split(separator: "\t").first.map(String.init) })
            .union(legacyNames)
        var reg = "REGEDIT4\n"
        for exe in previousNames.union(overrides.keys).sorted() {
            reg += "\n[-HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\\(exe)\\DllOverrides]\n"
        }
        for (exe, dlls) in overrides.sorted(by: { $0.key < $1.key }) {
            reg += "\n[HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\\(exe)\\DllOverrides]\n"
            for (dll, mode) in dlls.sorted(by: { $0.key < $1.key }) { reg += "\"\(dll)\"=\"\(mode)\"\n" }
        }
        let regFile = bottle.driveC.appendingPathComponent("exerunner-overrides.reg")
        try reg.write(to: regFile, atomically: true, encoding: .utf8)
        // the change is live for every process once regedit exits; waiting for the bottle to go
        // idle would wait for a running Steam to quit
        let env = WineEnvironment.make(engine: engine, prefix: bottle.url)
        _ = try await WineProcess.run(engine: engine, arguments: ["regedit", "/S", "C:\\exerunner-overrides.reg"], environment: env, log: log)
        try? FileManager.default.removeItem(at: regFile)
        try? FileManager.default.removeItem(at: legacy)
        try wanted.write(to: stamp, atomically: true, encoding: .utf8)
    }

    /// Per-program settings for cxcompatdb.so, which applies them inside each matching process, even
    /// one a launcher started before they changed: variables (program -> name -> value) and the
    /// programs kept off D3DMetal. Written even when empty: a launcher started earlier still points
    /// its programs at this file, and an empty file is what says "nothing" to them.
    static func writeCompatEnvironment(_ bottle: Bottle, perProgram: [String: [String: String]],
                                       d3dmetalOff: Set<String>) throws -> URL {
        let file = compatFile(bottle)
        let lines = (perProgram.flatMap { exe, env in env.map { "\(exe)\t\($0.key)=\($0.value)" } }
            + d3dmetalOff.map { "\($0)\t@d3dmetal=off" }).sorted()
        try lines.map { $0 + "\n" }.joined().write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    static func compatFile(_ bottle: Bottle) -> URL { bottle.url.appendingPathComponent(".exerunner-compat-env") }

    /// DLSS through MetalFX needs nvngx.dll and nvapi64.dll inside the bottle (Apple's Read Me).
    static func installMetalFXFiles(_ bottle: Bottle, engine: Engine) {
        guard engine.d3dmetalVersion != nil else { return }
        let source = engine.gptk.appendingPathComponent("wine/x86_64-windows", isDirectory: true)
        let target = bottle.driveC.appendingPathComponent("windows/system32", isDirectory: true)
        for name in ["nvngx.dll", "nvapi64.dll"] {
            let from = source.appendingPathComponent(name), to = target.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: from.path) else { continue }
            if FileManager.default.contentsEqual(atPath: from.path, andPath: to.path) { continue }
            try? FileManager.default.removeItem(at: to)
            try? FileManager.default.copyItem(at: from, to: to)
        }
    }
}
