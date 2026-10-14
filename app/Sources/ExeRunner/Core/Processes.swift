import Darwin
import Foundation

/// Windows paths compare without regard to case or slash direction.
enum WindowsPath {
    static func normalized(_ path: String) -> String {
        var path = path.replacingOccurrences(of: "/", with: "\\").lowercased()
        if path.hasPrefix("\\\\?\\") { path.removeFirst(4) }
        while path.hasSuffix("\\") { path.removeLast() }
        return path
    }

    static func same(_ a: String, _ b: String) -> Bool { normalized(a) == normalized(b) }

    /// `path` is `folder` or anything inside it
    static func isInside(_ path: String, folder: String) -> Bool {
        let path = normalized(path), folder = normalized(folder)
        return path == folder || path.hasPrefix(folder + "\\")
    }

    static func name(_ path: String) -> String {
        path.split(whereSeparator: { $0 == "\\" || $0 == "/" }).last.map(String.init) ?? path
    }
}

/// Windows programs running under wine, read from the Mac's process table. Wine shifts each
/// process's arguments in place so the first is the program's Windows path (rebuild_argv in
/// ntdll), and the environment the process started with names its bottle in WINEPREFIX.
/// Only processes of this user are readable, which is all of wine's.
enum WineProcesses {
    struct Entry: Hashable, Sendable {
        let pid: pid_t
        /// The program as its parent started it: C:\Program Files (x86)\Steam\steam.exe, or a
        /// Mac path for a program the app started by one
        let path: String
        /// WINEPREFIX, standardized
        let prefix: String

        var name: String { WindowsPath.name(path) }
    }

    static func list(includeServers: Bool = false, copiedLoaderImages: [Data]? = nil) -> [Entry] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let found = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.stride))
        guard found > 0 else { return [] }

        var argmax: Int32 = 0
        var size = MemoryLayout<Int32>.size
        var mib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        guard sysctl(&mib, 2, &argmax, &size, nil, 0) == 0, argmax > 0 else { return [] }
        var buffer = [UInt8](repeating: 0, count: Int(argmax))
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        var loaderImages = copiedLoaderImages
        var verifiedCopies: [String: Bool] = [:]

        return pids.prefix(Int(found)).compactMap { pid in
            guard pid > 0, proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return nil }
            let executable = URL(fileURLWithPath: String(cString: path))
            let binary = executable.lastPathComponent
            let conventional = binary == "wine" || binary == "wine64" || binary.hasSuffix("-preloader") || (includeServers && binary == "wineserver")
            if !conventional {
                // Wine can relaunch with a renamed copy of its Unix loader (CEF, for example).
                // Its name alone is insufficient: require Wine's temp folder and exact bytes
                // of the selected engine. Cache each candidate only within this process scan.
                guard executable.deletingLastPathComponent().lastPathComponent.hasPrefix("winetemp-") else { return nil }
                if loaderImages == nil { loaderImages = selectedWineLoaderImages() }
                let verified = verifiedCopies[executable.path] ?? matchesCopiedLoader(executable, images: loaderImages ?? [])
                verifiedCopies[executable.path] = verified
                guard verified else { return nil }
            }
            return entry(pid, buffer: &buffer)
        }
    }

    private static func selectedWineLoaderImages() -> [Data] {
        guard let engine = Engine.locate(AppSettings.load()) else { return [] }
        let loaders = [engine.wine] + ["x86_64-unix", "aarch64-unix", "i386-unix"].map {
            engine.lib.appendingPathComponent("wine/\($0)/wine")
        }
        return loaders.compactMap { url in
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  size > 0, size <= 1_048_576 else { return nil }
            return try? Data(contentsOf: url)
        }
    }

    private static func matchesCopiedLoader(_ url: URL, images: [Data]) -> Bool {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              images.contains(where: { $0.count == size }),
              let bytes = try? Data(contentsOf: url) else { return false }
        return images.contains(bytes)
    }

    /// KERN_PROCARGS2: argc, the executable's path, then NUL-terminated arguments and environment.
    /// Wine's shift leaves zero bytes behind the arguments, so empty strings are skipped.
    private static func entry(_ pid: pid_t, buffer: inout [UInt8]) -> Entry? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = buffer.count
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var strings: [String] = []
        var start = MemoryLayout<Int32>.size
        for index in start..<size where buffer[index] == 0 {
            if index > start { strings.append(String(decoding: buffer[start..<index], as: UTF8.self)) }
            start = index + 1
        }
        // strings[0] is the executable's Mac path
        guard strings.count > 1,
              let prefix = strings.last(where: { $0.hasPrefix("WINEPREFIX=") })?.dropFirst("WINEPREFIX=".count)
        else { return nil }
        // C:\...\game.exe as a parent passed it, or the Mac path a program was started with
        var program = strings[1]
        // what wine cannot map directly runs as start.exe /exec <program>
        if WindowsPath.name(program).lowercased() == "start.exe", strings.count > 3, strings[2].lowercased() == "/exec" {
            program = strings[3]
        }
        return Entry(pid: pid, path: program, prefix: URL(fileURLWithPath: String(prefix)).standardizedFileURL.path)
    }

    /// Ends processes at once, the way TerminateProcess does; wineserver notices them gone.
    static func kill(_ entries: [Entry]) {
        for entry in entries { Darwin.kill(entry.pid, SIGKILL) }
    }
}
