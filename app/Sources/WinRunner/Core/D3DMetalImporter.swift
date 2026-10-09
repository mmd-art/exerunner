import Foundation

/// Imports Apple's D3DMetal from the user's own Game Porting Toolkit download into the engine
/// (engine/lib/apple_gptk). Nothing of Apple's ships with the app. Takes the outer GPTK disk
/// image, the evaluation environment image inside it, a mounted volume or a folder.
enum D3DMetalImporter {
    static let required = [
        "external/libd3dshared.dylib", "external/D3DMetal.framework",
        "wine/x86_64-windows/d3d11.dll", "wine/x86_64-windows/d3d12.dll", "wine/x86_64-windows/dxgi.dll",
        "wine/x86_64-unix/d3d12.so",
    ]

    static func importPayload(from source: URL, into engine: Engine, progress: @escaping (String) -> Void) async throws -> String {
        guard engine.hasCompatModule else {
            throw AppError("В движке нет модуля совместимости (cxcompatdb.so), без него D3DMetal не включится")
        }
        var mounts: [URL] = []
        do {
            progress("Ищу D3DMetal в «\(source.lastPathComponent)»…")
            guard let lib = try await findRedist(in: source, mounts: &mounts, depth: 0) else {
                throw AppError("Не нашёл D3DMetal. Нужен файл Game Porting Toolkit с сайта Apple: Game_Porting_Toolkit_*.dmg")
            }
            let version = try await deploy(lib, into: engine, progress: progress)
            await detach(mounts)
            return version
        } catch {
            await detach(mounts)
            throw error
        }
    }

    private static func findRedist(in url: URL, mounts: inout [URL], depth: Int) async throws -> URL? {
        let fm = FileManager.default
        if url.pathExtension.lowercased() == "dmg" {
            let mountpoint = try await mount(url)
            mounts.append(mountpoint)
            return try await findRedist(in: mountpoint, mounts: &mounts, depth: depth + 1)
        }
        for candidate in [url.appendingPathComponent("redist/lib"), url.appendingPathComponent("lib"), url]
        where fm.fileExists(atPath: candidate.appendingPathComponent("external/libd3dshared.dylib").path) {
            return candidate
        }
        guard depth < 3, let names = try? fm.contentsOfDirectory(atPath: url.path) else { return nil }
        // Apple's outer image carries the evaluation environment as a nested image
        let images = names.filter { $0.lowercased().hasSuffix(".dmg") }
            .sorted { $0.contains("Evaluation") && !$1.contains("Evaluation") }
        for name in images {
            if let found = try await findRedist(in: url.appendingPathComponent(name), mounts: &mounts, depth: depth + 1) { return found }
        }
        return nil
    }

    private static func mount(_ image: URL) async throws -> URL {
        let mountpoint = FileManager.default.temporaryDirectory
            .appendingPathComponent("winrunner-gptk-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try Paths.ensure(mountpoint)
        let result = await Shell.run("/usr/bin/hdiutil",
                                     ["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mountpoint.path, image.path])
        guard result.status == 0 else { throw AppError("Не удалось открыть образ \(image.lastPathComponent): \(result.output)") }
        return mountpoint
    }

    private static func detach(_ mounts: [URL]) async {
        for mountpoint in mounts.reversed() {
            _ = await Shell.run("/usr/bin/hdiutil", ["detach", mountpoint.path, "-quiet"])
            try? FileManager.default.removeItem(at: mountpoint)
        }
    }

    private static func deploy(_ lib: URL, into engine: Engine, progress: (String) -> Void) async throws -> String {
        let fm = FileManager.default
        for path in required where !fm.fileExists(atPath: lib.appendingPathComponent(path).path) {
            throw AppError("В найденном D3DMetal не хватает \(path)")
        }
        // the unix modules are symlinks to ../../external/libd3dshared.dylib, which finds the
        // framework through @loader_path; copies of them would not load
        let unix = lib.appendingPathComponent("wine/x86_64-unix/d3d12.so")
        guard (try? fm.attributesOfItem(atPath: unix.path)[.type] as? FileAttributeType) == .typeSymbolicLink else {
            throw AppError("Файлы D3DMetal скопированы без символических ссылок. Возьми их прямо из DMG Apple.")
        }
        progress("Копирую D3DMetal…")
        // outside the engine, which may sit inside the signed app
        let target = Paths.d3dmetal
        try? fm.removeItem(at: target)
        try Paths.ensure(target)
        for part in ["external", "wine"] {
            let result = await Shell.run("/usr/bin/ditto", [lib.appendingPathComponent(part).path, target.appendingPathComponent(part).path])
            guard result.status == 0 else { throw AppError("Не удалось скопировать D3DMetal: \(result.output)") }
        }
        // DLSS through MetalFX: the payload ships the bridge under another name (Apple's Read Me)
        let windows = target.appendingPathComponent("wine/x86_64-windows")
        let nvngxSO = target.appendingPathComponent("wine/x86_64-unix/nvngx.so")
        if fm.fileExists(atPath: windows.appendingPathComponent("nvngx-on-metalfx.dll").path) {
            try? fm.removeItem(at: nvngxSO)
            try fm.createSymbolicLink(atPath: nvngxSO.path, withDestinationPath: "../../external/libd3dshared.dylib")
            try? fm.removeItem(at: windows.appendingPathComponent("nvngx.dll"))
            try fm.copyItem(at: windows.appendingPathComponent("nvngx-on-metalfx.dll"), to: windows.appendingPathComponent("nvngx.dll"))
        }
        let info = NSDictionary(contentsOf: target.appendingPathComponent("external/D3DMetal.framework/Resources/Info.plist"))
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        try version.write(to: target.appendingPathComponent("D3DMETAL_VERSION"), atomically: true, encoding: .utf8)
        return version
    }
}
