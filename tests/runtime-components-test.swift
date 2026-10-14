import Foundation

actor InstallerCalls {
    private var verbs: [String] = []
    var fail: String?
    init(fail: String? = nil) { self.fail = fail }
    func call(_ args: [String]) -> Int32 {
        let verb = args.last ?? ""
        verbs.append(verb)
        return verb == fail ? 17 : 0
    }
    func recorded() -> [String] { verbs }
}

@main struct RuntimeTestMain {
    static func main() async throws {
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--lease-probe" {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
            process.environment = ["WINEPREFIX": CommandLine.arguments[2]]
            do { try PrefixLaunchGate.start(process); process.waitUntilExit(); exit(process.terminationStatus) }
            catch { exit(23) }
        }
        try await RuntimeTests.run()
    }
}

@MainActor enum RuntimeTests {
    static var passed = 0
    static func check(_ value: Bool, _ title: String) {
        guard value else { fatalError("FAIL: \(title)") }
        passed += 1
    }

    // Independent PE fixture from the Microsoft file-layout contract.
    static func fixture(wide: Bool = false, delayedVA: Bool = false) -> Data {
        var data = Data(repeating: 0, count: 0x800)
        func u16(_ at: Int, _ value: UInt16) { for i in 0..<2 { data[at + i] = UInt8((value >> (i * 8)) & 255) } }
        func u32(_ at: Int, _ value: UInt32) { for i in 0..<4 { data[at + i] = UInt8((value >> (i * 8)) & 255) } }
        func string(_ at: Int, _ text: String) { data.replaceSubrange(at..<at + text.utf8.count, with: text.utf8) }
        let opt = 0x98, start = wide ? 112 : 96, size = wide ? 240 : 224
        u16(0, 0x5a4d); u32(0x3c, 0x80); u32(0x80, 0x4550)
        u16(0x84, wide ? 0x8664 : 0x14c); u16(0x86, 1); u16(0x94, UInt16(size))
        u16(opt, wide ? 0x20b : 0x10b); u32(opt + 60, 0x200); u32(opt + start - 4, 16)
        if wide { u32(opt + 24, 0x40000000); u32(opt + 28, 1) }
        else { u32(opt + 28, 0x400000) }
        let section = opt + size
        u32(section + 12, 0x1000); u32(section + 16, 0x600); u32(section + 20, 0x200)
        u32(opt + start + 8, 0x1000); u32(opt + start + 12, 40)
        u32(0x200 + 12, 0x1080); string(0x280, "MSVCR120.dll")
        u32(opt + start + 13 * 8, 0x1100); u32(opt + start + 13 * 8 + 4, 64)
        u32(0x300, delayedVA ? 0 : 1); u32(0x304, delayedVA ? 0x401180 : 0x1180)
        string(0x380, "D3DCOMPILER_47.dll")
        return data
    }

    static func run() async throws {
        let work = URL(fileURLWithPath: ProcessInfo.processInfo.environment["EXPECT_WORK"]!)
        check(WindowsInstaller.succeeded(0, isMSI: false), "EXE success status")
        check(WindowsInstaller.succeeded(3010 & 255, isMSI: true), "MSI reboot-required transport success")
        check(WindowsInstaller.succeeded(1641 & 255, isMSI: true), "MSI reboot-initiated transport success")
        check(!WindowsInstaller.succeeded(1603 & 255, isMSI: true), "MSI failure transport refused")
        check(!WindowsInstaller.succeeded(3010 & 255, isMSI: false), "EXE exit not inferred to be MSI success")
        let msi = work.appendingPathComponent("setup with spaces.MSI")
        check(WindowsInstaller.arguments(for: msi) == ["msiexec", "/i", msi.path], "MSI path remains one argument")
        let legacy = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"language":"english"}"#.utf8))
        check(legacy.automaticRuntimeComponents, "legacy settings adopt automatic runtime preparation")
        let optOut = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"automaticRuntimeComponents":false,"cursorConfinement":false}"#.utf8))
        check(!optOut.automaticRuntimeComponents && !optOut.cursorConfinement, "runtime opt-out preserves other settings")
        let f32 = fixture(), f64 = fixture(wide: true)
        check(PEInspection.parse(f32)?.architecture == .x86, "PE32 architecture")
        check(PEInspection.parse(f64)?.architecture == .x64, "PE32+ architecture")
        check(PEInspection.parse(f32)?.imports == ["d3dcompiler_47.dll", "msvcr120.dll"], "regular and delayed imports normalized")
        check(PEInspection.parse(fixture(delayedVA: true))?.imports == PEInspection.parse(f32)?.imports, "legacy VA delay imports")
        check(PEInspection.parse(f32)?.managed == false, "native image is not managed")
        var managed = f32
        managed[0x98 + 96 + 14 * 8] = 0; managed[0x98 + 96 + 14 * 8 + 1] = 0x14
        managed[0x98 + 96 + 14 * 8 + 4] = 72
        check(PEInspection.parse(managed)?.managed == true, "CLR directory recognized")
        check(PEInspection.parse(Data("not a PE".utf8)) == nil, "non-PE input")
        for end in stride(from: 0, to: f32.count, by: 19) {
            check(PEInspection.parse(Data(f32.prefix(end))) == nil, "truncated PE rejected at \(end)")
        }
        var corrupt = f32
        corrupt[0x3c] = 255; corrupt[0x3d] = 255; corrupt[0x3e] = 255; corrupt[0x3f] = 255
        check(PEInspection.parse(corrupt) == nil, "overflowing PE offset")
        corrupt = f32; corrupt[0x98] = 0
        check(PEInspection.parse(corrupt) == nil, "unknown optional-header format")
        corrupt = f32; corrupt[0x20c] = 255; corrupt[0x20d] = 255; corrupt[0x20e] = 255
        check(PEInspection.parse(corrupt) == nil, "unmapped name RVA")
        corrupt = f32
        for i in 0..<260 { corrupt[0x380 + i] = 65 }
        check(PEInspection.parse(corrupt) == nil, "unterminated import name")
        let app = work.appendingPathComponent("generic.exe")
        try f32.write(to: app)
        check(PEInspection.read(app)?.imports == PEInspection.parse(f32)?.imports, "file read agrees with fixture")
        check(RuntimeComponent.suggested(for: app) == ["d3dcompiler_47", "vcrun2013"], "library inference without app profile")
        try Data().write(to: work.appendingPathComponent("MSVCR120.dll"))
        check(RuntimeComponent.suggested(for: app) == ["d3dcompiler_47"], "adjacent DLL case-insensitive")
        let config = work.appendingPathComponent("generic.runtimeconfig.json")
        try Data(#"{"runtimeOptions":{"frameworks":[{"name":"Microsoft.NETCore.App","version":"8.0.2"},{"name":"Microsoft.WindowsDesktop.App","version":"8.0.2"}]}}"#.utf8).write(to: config)
        check(RuntimeComponent.suggested(for: app) == ["d3dcompiler_47", "dotnetdesktop8"], "modern .NET framework inferred and deduplicated")
        try Data(#"{"runtimeOptions":{"framework":{"name":"Microsoft.WindowsDesktop.App","version":"9.0.1"}}}"#.utf8).write(to: config)
        check(RuntimeComponent.suggested(for: app).contains("dotnetdesktop9"), "single framework syntax")
        try Data(#"{"runtimeOptions":{"framework":{"name":"Unknown.Framework","version":"8.0.0"}}}"#.utf8).write(to: config)
        check(RuntimeComponent.suggested(for: app) == ["d3dcompiler_47"], "unknown framework not guessed")
        try Data(#"{"runtimeOptions":{"framework":{"name":"Microsoft.WindowsDesktop.App","version":"10.0.0"}}}"#.utf8).write(to: config)
        check(RuntimeComponent.suggested(for: app).contains("dotnetdesktop10"), "current .NET 10 framework inferred")
        check(Set(RuntimeComponent.all.map(\.id)).count == RuntimeComponent.all.count, "unique package catalog IDs")
        check(RuntimeComponent.all.allSatisfy { Winetricks.validVerb($0.id) }, "safe catalog verbs")
        let locked = work.appendingPathComponent("lease-bottle")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        let lease = try PrefixComponentLease.installation(in: locked)
        do {
            _ = try PrefixComponentLease.installation(in: locked)
            fatalError("parallel component installation accepted")
        } catch { check(true, "concurrent component installers refused") }
        func launchProbe(_ prefix: URL) throws -> Int32 {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            process.arguments = ["--lease-probe", prefix.path]
            try process.run(); process.waitUntilExit()
            return process.terminationStatus
        }
        let blockedLaunch = try launchProbe(locked)
        check(blockedLaunch == 23, "another ExeRunner process cannot launch into a bottle being updated")
        let foreign = work.appendingPathComponent("other-bottle")
        try FileManager.default.createDirectory(at: foreign, withIntermediateDirectories: true)
        let unrelatedLaunch = try launchProbe(foreign)
        check(unrelatedLaunch == 0, "another bottle remains launchable during installation")
        lease.release()
        let resumedLaunch = try launchProbe(locked)
        check(resumedLaunch == 0, "normal launch resumes after component installer exits")
        let newer = Bottle(name: "newer-v14", root: work)
        try FileManager.default.createDirectory(at: newer.url, withIntermediateDirectories: true)
        try "vcrun2026\n".write(to: newer.url.appendingPathComponent(".exerunner-winetricks"), atomically: true, encoding: .utf8)
        check(Winetricks.missing(["vcrun2022"], in: newer).isEmpty, "latest v14 does not downgrade to older package")
        check(Winetricks.satisfies("dotnet10", installed: ["dotnetdesktop10"]), "desktop runtime covers base runtime")
        check(!Winetricks.satisfies("dotnet9", installed: ["dotnetdesktop10"]), "different .NET major is not assumed compatible")
        for invalid in ["", "--force", "vcrun2022;echo", "../../app", "x y"] {
            check(!Winetricks.validVerb(invalid), "unsafe verb refused: \(invalid)")
        }
        let engineRoot = work.appendingPathComponent("engine")
        try FileManager.default.createDirectory(at: engineRoot.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try "w_metadata corefonts fonts \\\nw_metadata vcrun2013 dlls \\\nw_metadata msxml6 dlls \\\n".write(to: engineRoot.appendingPathComponent("bin/winetricks"), atomically: true, encoding: .utf8)
        let engine = Engine(root: engineRoot)
        check(Winetricks.available(in: engine) == ["corefonts", "vcrun2013", "msxml6"], "available packages parsed from actual script")
        let bottle = Bottle(name: "programs", root: work)
        try FileManager.default.createDirectory(at: bottle.url, withIntermediateDirectories: true)
        try "msxml6\n".write(to: bottle.url.appendingPathComponent("winetricks.log"), atomically: true, encoding: .utf8)
        check(Winetricks.installed(in: bottle) == ["msxml6"], "existing winetricks installations recognized")
        let calls = InstallerCalls(fail: "vcrun2013")
        do {
            try await Winetricks.ensure(["corefonts", "vcrun2013"], in: bottle, engine: engine, log: work.appendingPathComponent("install.log"), progress: { _ in },
                runner: { _, args, env, _ in
                    // Upstream writes this before its final verification can fail.
                    let file = URL(fileURLWithPath: env["WINEPREFIX"]!).appendingPathComponent("winetricks.log")
                    let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
                    try (text + (args.last ?? "") + "\n").write(to: file, atomically: true, encoding: .utf8)
                    return await calls.call(args)
                })
            fatalError("installer failure not surfaced")
        } catch { check(!(error is CancellationError), "package failure surfaced") }
        check(Winetricks.installed(in: bottle) == ["msxml6", "corefonts"], "successful package survives later failure")
        let failedLog = try String(contentsOf: bottle.url.appendingPathComponent("winetricks.log"), encoding: .utf8)
        check(failedLog.contains("vcrun2013"), "failure fixture carries an upstream install record")
        check(Winetricks.missing(["corefonts", "vcrun2013", "vcrun2013"], in: bottle) == ["vcrun2013"], "only missing packages retried")
        let retry = InstallerCalls()
        try await Winetricks.ensure(["corefonts", "vcrun2013", "vcrun2013"], in: bottle, engine: engine, log: work.appendingPathComponent("install.log"), progress: { _ in },
            runner: { _, args, _, _ in await retry.call(args) })
        let retried = await retry.recorded()
        check(retried == ["vcrun2013"], "retry skipped successful installation")
        check(Winetricks.installed(in: bottle) == ["msxml6", "corefonts", "vcrun2013"], "progress merged with previous installs")
        let paused = Bottle(name: "interrupted", root: work)
        try FileManager.default.createDirectory(at: paused.url, withIntermediateDirectories: true)
        try "corefonts\n".write(to: paused.url.appendingPathComponent("winetricks.log"), atomically: true, encoding: .utf8)
        try "corefonts\n".write(to: paused.url.appendingPathComponent(".exerunner-winetricks-unverified"), atomically: true, encoding: .utf8)
        check(Winetricks.missing(["corefonts"], in: paused) == ["corefonts"], "interrupted install remains retryable after restart")
        let completeThenInterrupted = paused.url.appendingPathComponent(".exerunner-winetricks")
        try "corefonts\n".write(to: completeThenInterrupted, atomically: true, encoding: .utf8)
        check(Winetricks.missing(["corefonts"], in: paused).isEmpty, "committed success survives interruption during marker cleanup")
        let current = try String(contentsOf: engineRoot.appendingPathComponent("bin/winetricks"), encoding: .utf8)
        try (current + "w_metadata vcrun2026 dlls\n" + "w_metadata vcrun2022 dlls\n").write(to: engineRoot.appendingPathComponent("bin/winetricks"), atomically: true, encoding: .utf8)
        let batch = Bottle(name: "fresh-v14-batch", root: work)
        try FileManager.default.createDirectory(at: batch.url, withIntermediateDirectories: true)
        let batchCalls = InstallerCalls()
        try await Winetricks.ensure(["vcrun2026", "vcrun2022"], in: batch, engine: engine, log: work.appendingPathComponent("install.log"), progress: { _ in },
            runner: { _, args, _, _ in await batchCalls.call(args) })
        check(await batchCalls.recorded() == ["vcrun2026"], "batch does not downgrade after installing newer v14")
        let isolated = Bottle(name: "isolated-test", root: work)
        do {
            try await Winetricks.ensure(["corefonts"], in: isolated, engine: engine, log: work.appendingPathComponent("install.log"), progress: { _ in },
                runner: { _, args, _, _ in await retry.call(args) })
            fatalError("isolated component install allowed")
        } catch { check(true, "isolation rejected before process start") }
        check(await retry.recorded() == retried, "isolation never invokes installer")
        print("runtime components: \(passed) passed")
    }
}
