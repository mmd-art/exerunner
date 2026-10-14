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
    /// Other drive letters go through the bottle's dosdevices links (Z: is the Mac's /), and Windows
    /// links inside the bottle are followed (EA's installer links EA Desktop\EA Desktop to the
    /// folder of the current version).
    func hostURL(forWindowsPath path: String) -> URL? { hostURL(forWindowsPath: path, depth: 0) }

    private func hostURL(forWindowsPath path: String, depth: Int) -> URL? {
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        let chars = Array(path)
        guard chars.count >= 3, chars[1] == ":", chars[2] == "\\" || chars[2] == "/" else { return nil }
        let drive = chars[0].lowercased()
        let rest = String(chars.dropFirst(3)).split(whereSeparator: { $0 == "\\" || $0 == "/" }).map(String.init)
        var base = driveC
        if drive != "c" {
            let link = url.appendingPathComponent("dosdevices/\(drive):")
            guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path) else { return nil }
            base = URL(fileURLWithPath: target, relativeTo: link.deletingLastPathComponent()).standardizedFileURL
        }
        return following(rest, from: base, depth: depth)
    }

    /// Appends the parts of a path, going through the Windows links on the way. Wine keeps such a
    /// link as an entry named "<name>?" with the target in its user.WINEREPARSE attribute
    /// (server/fd.c); the Mac sees only that entry.
    private func following(_ parts: [String], from base: URL, depth: Int) -> URL {
        var current = base
        for (index, name) in parts.enumerated() {
            let next = current.appendingPathComponent(name)
            guard depth < 8, !FileManager.default.fileExists(atPath: next.path),
                  let link = WindowsLink(at: current.appendingPathComponent(name + "?")) else {
                current = next
                continue
            }
            let target = link.relative
                ? following(link.target.split(separator: "\\").map(String.init), from: current, depth: depth + 1).standardizedFileURL
                : hostURL(forWindowsPath: link.target, depth: depth + 1)
            guard let target else { current = next; continue }
            return following(Array(parts[(index + 1)...]), from: target, depth: depth + 1)
        }
        return current
    }

    /// The bottle as WINEPREFIX names it in a running process's environment
    var prefixPath: String { url.standardizedFileURL.path }
}

/// A Windows symbolic link or junction as wine stores it: the reparse data buffer
/// (REPARSE_DATA_BUFFER) of the link in the user.WINEREPARSE attribute.
struct WindowsLink {
    let target: String
    let relative: Bool

    init?(at url: URL) {
        let name = "user.WINEREPARSE"
        let size = getxattr(url.path, name, nil, 0, 0, 0)
        guard size >= 20 else { return nil }
        var data = [UInt8](repeating: 0, count: size)
        guard getxattr(url.path, name, &data, size, 0, 0) == size else { return nil }
        func u16(_ at: Int) -> Int { Int(data[at]) | Int(data[at + 1]) << 8 }
        let tag = UInt32(u16(0)) | UInt32(u16(2)) << 16
        let names: Int
        switch tag {
        case 0xA000_000C: names = 20; relative = u16(16) & 1 != 0   // IO_REPARSE_TAG_SYMLINK
        case 0xA000_0003: names = 16; relative = false              // IO_REPARSE_TAG_MOUNT_POINT
        default: return nil
        }
        let start = names + u16(8), length = u16(10)
        guard length > 0, start + length <= data.count,
              var target = String(bytes: data[start..<start + length], encoding: .utf16LittleEndian) else { return nil }
        if target.hasPrefix("\\??\\") { target.removeFirst(4) }
        self.target = target
    }
}

enum BottleManager {
    static func ensure(_ bottle: Bottle, engine: Engine, log: URL) async throws {
        if bottle.exists { return }
        try Paths.ensure(bottle.url.deletingLastPathComponent())
        let env = WineEnvironment.make(engine: engine, prefix: bottle.url)
        _ = try await WineProcess.run(engine: engine, arguments: ["wineboot", "--init"], environment: env, log: log)
        await WineProcess.server("-w", engine: engine, environment: env)
        guard bottle.exists else { throw AppError(t("Не удалось создать бутылку «\(bottle.name)». Подробности в журнале.")) }
    }

    static func stop(_ bottle: Bottle, engine: Engine) async {
        if bottle.name.hasPrefix("isolated-") {
            // Separate sandbox invocations cannot signal each other. The host
            // stops only processes whose own WINEPREFIX identifies this bottle.
            WineProcesses.kill(WineProcesses.list(includeServers: true).filter { $0.prefix == bottle.prefixPath })
            return
        }
        await WineProcess.server("-k", engine: engine, environment: WineEnvironment.make(engine: engine, prefix: bottle.url))
    }

    /// DXVK's DLL names (d3d11, d3d10core, ...), which a program set to DXVK loads as native
    static func dxvkLibraries(_ engine: Engine) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: engine.dxvk.appendingPathComponent("x64").path)) ?? [])
            .filter { $0.hasSuffix(".dll") }.map { String($0.dropLast(4)) }.sorted()
    }

    /// DXVK's DLLs inside the bottle; only programs with a native override load them
    static func installDXVK(_ bottle: Bottle, engine: Engine) throws {
        guard engine.hasDXVK else { throw AppError(t("В движке нет DXVK")) }
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

    /// DXMT's builtin bridge must also exist in the Windows namespace.
    /// Renderer DLLs stay outside the bottle and are selected per process.
    static func installDXMTBridge(_ bottle: Bottle, engine: Engine) throws {
        guard engine.hasDXMT else { throw AppError(t("В движке нет DXMT")) }
        for (arch, dir) in [("x86_64-windows", "system32"), ("i386-windows", "syswow64")] {
            let source = engine.dxmt.appendingPathComponent("\(arch)/winemetal.dll")
            let target = bottle.driveC.appendingPathComponent("windows/\(dir)/winemetal.dll")
            if FileManager.default.contentsEqual(atPath: source.path, andPath: target.path) { continue }
            try Data(contentsOf: source).write(to: target, options: .atomic)
        }
    }

    /// Per-program DLL overrides through AppDefaults (program -> dll -> mode), and wine's Direct3D
    /// settings for programs that draw through it (program -> name -> value). Exactly these stay
    /// in place: those of programs dropped since the last call are deleted.
    static func applyOverrides(_ bottle: Bottle, engine: Engine, overrides: [String: [String: String]],
                               direct3D: [String: [String: String]] = [:], log: URL) async throws {
        let stamp = bottle.url.appendingPathComponent(".exerunner-overrides")
        let wanted = (overrides.flatMap { exe, dlls in dlls.map { "\(exe)\t\($0.key)=\($0.value)" } }
            + direct3D.flatMap { exe, values in values.map { "\(exe)\t@d3d \($0.key)=\($0.value)" } })
            .sorted().joined(separator: "\n")
        let previous = (try? String(contentsOf: stamp, encoding: .utf8)) ?? ""
        if previous == wanted { return }
        // the first version kept only DXVK programs, in another file
        let legacy = bottle.url.appendingPathComponent(".exerunner-dxvk")
        let legacyNames = ((try? String(contentsOf: legacy, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
        let previousNames = Set(previous.split(separator: "\n").compactMap { $0.split(separator: "\t").first.map(String.init) })
            .union(legacyNames)
        var reg = "REGEDIT4\n"
        for exe in previousNames.union(overrides.keys).union(direct3D.keys).sorted() {
            reg += "\n[-HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\\(exe)\\DllOverrides]\n"
            reg += "\n[-HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\\(exe)\\Direct3D]\n"
        }
        for (key, settings) in [("DllOverrides", overrides), ("Direct3D", direct3D)] {
            for (exe, values) in settings.sorted(by: { $0.key < $1.key }) {
                reg += "\n[HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\\(exe)\\\(key)]\n"
                for (name, value) in values.sorted(by: { $0.key < $1.key }) { reg += "\"\(name)\"=\"\(value)\"\n" }
            }
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
                                       d3dmetalOff: Set<String>, dxmt: Set<String> = []) throws -> URL {
        let file = compatFile(bottle)
        let lines = (perProgram.flatMap { exe, env in env.map { "\(exe)\t\($0.key)=\($0.value)" } }
            + d3dmetalOff.map { "\($0)\t@d3dmetal=off" }
            + dxmt.map { "\($0)\t@dxmt=on" }).sorted()
        try lines.map { $0 + "\n" }.joined().write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    /// The recipes' links, each to the newest folder matching its pattern (EA keeps its app in
    /// <version>\EA Desktop and expects EA Desktop\EA Desktop to be a junction to it). A real
    /// folder at the link's place is left alone.
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
