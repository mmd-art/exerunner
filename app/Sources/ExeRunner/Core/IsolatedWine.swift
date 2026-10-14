import Darwin
import Foundation

/// Experimental Seatbelt boundary around the complete Wine process tree. No unrestricted retry.
/// System runtime/graphics services remain shared: this is not a VM or a malware safety verdict.
enum IsolatedWine {
    static func canonical(_ url: URL) -> URL {
        guard let resolved = realpath(url.path, nil) else { return url.standardizedFileURL }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved))
    }
    static func inside(_ child: URL, _ parent: URL) -> Bool {
        let c = canonical(child).path, p = canonical(parent).path
        return c.hasPrefix(p + "/")
    }
    static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static func profile(prefix: URL, engine: Engine) throws -> String {
        let prefix = canonical(prefix)
        var info = stat()
        guard stat(prefix.path, &info) == 0 else { throw AppError("Isolation prefix does not exist") }
        let server = "/tmp/.wine-\(getuid())/server-\(String(UInt64(info.st_dev), radix: 16))-\(String(UInt64(info.st_ino), radix: 16))"
        let read = ["/System/Library", "/System/iOSSupport", "/System/Cryptexes", "/Library/Apple", "/private/var/db/oah", "/private/var/db/dyld", "/private/var/db/CVMS", "/usr/lib", "/usr/share", "/usr/bin", "/bin", prefix.path, canonical(engine.root).path, canonical(engine.gptk).path]
        let readable = read.map { "(subpath \(quoted($0)))" }.joined(separator: " ")
        return """
        (version 1)
        (deny default)
        (import "dyld-support.sb")
        (allow syscall*)
        (allow mach-bootstrap)
        (allow process-fork process-exec)
        (allow signal (target same-sandbox))
        (allow sysctl-read)
        (allow file-read* \(readable))
        (allow file-read-metadata)
        (allow file-map-executable \(readable))
        (allow file-write* (subpath \(quoted(prefix.path))))
        (allow file-read* file-write* (literal "/dev/null") (literal "/dev/urandom") (literal "/dev/random"))
        (allow file-read* file-write* (subpath \(quoted("/private" + server))))
        (allow network* (local unix-socket (subpath \(quoted("/private" + server)))))
        (allow mach-register (local-name-prefix ""))
        (allow mach-lookup mach-register (global-name \(quoted(server))) (global-name \(quoted("/private" + server))))
        (allow mach-lookup (global-name "com.apple.windowserver.active") (global-name "com.apple.logd") (global-name "com.apple.audio.coreaudiod") (global-name "com.apple.audio.audiohald") (global-name "com.apple.audio.AudioComponentRegistrar") (global-name "com.apple.CARenderServer") (global-name "com.apple.dock.fullscreen") (global-name "com.apple.FontObjectsServer") (global-name "com.apple.fonts") (global-name "com.apple.cvmsServ") (global-name "com.apple.MTLCompilerService") (xpc-service-name "com.apple.MTLCompilerService"))
        ; Dock icon updates need this service; native launch brokers stay denied below.
        (allow mach-lookup (global-name "com.apple.dock.server"))
        ; Window Manager must attach the native window to the current desktop.
        (allow mach-lookup (global-name "com.apple.windowmanager.server"))
        ; AppKit process registration is required for native mouse/keyboard focus.
        (allow mach-lookup (global-name "com.apple.coreservices.launchservicesd"))
        ; Keep native application launch brokers blocked as the GUI allowlist evolves.
        (deny lsopen)
        (deny mach-lookup (global-name "com.apple.runningboard") (xpc-service-name "com.apple.runningboard"))
        ; Class filters permit offscreen rendering but not the OpenGL drawable in a Mac window.
        (allow iokit-open-user-client (iokit-connection "IOAccelerator"))
        (allow iokit-open (iokit-user-client-class "AGXDeviceUserClient") (iokit-user-client-class "AGXSharedUserClient") (iokit-user-client-class "IOSurfaceRootUserClient") (iokit-user-client-class "IOSurfaceAcceleratorClient") (iokit-user-client-class "IOHIDParamUserClient") (iokit-user-client-class "AppleGraphicsControlClient"))
        """
    }

    /// Prefixes opt in only after explicit provisioning, never reuse a normal launcher bottle.
    static func environment(bottle: Bottle, engine: Engine, base: [String: String]? = nil) throws -> [String: String] {
        let root = canonical(bottle.url)
        guard bottle.name.hasPrefix("isolated-"),
              !FileManager.default.fileExists(atPath: root.appendingPathComponent(".exerunner-unrestricted").path),
              FileManager.default.fileExists(atPath: root.appendingPathComponent(".exerunner-isolated-v1").path),
              FileManager.default.isExecutableFile(atPath: "/usr/bin/sandbox-exec"),
              FileManager.default.fileExists(atPath: "/System/Library/Sandbox/Profiles/dyld-support.sb") else {
            throw AppError(t("Изолированная бутылка не подготовлена или системная песочница недоступна. Обычный запуск не выполнен."))
        }
        let work = root.appendingPathComponent(".isolation", isDirectory: true)
        // The guest can create symlinks in its writable disk. Host preparation must
        // never follow one into Documents or another bottle on the next launch.
        for part in ["", "home", "tmp", "cache", "cache/dxvk"] {
            let directory = part.isEmpty ? work : work.appendingPathComponent(part)
            var info = stat()
            if lstat(directory.path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFLNK {
                throw AppError("Isolation work directory is a symlink; launch refused")
            }
            guard inside(directory, root) else { throw AppError("Isolation work directory escapes bottle") }
            try Paths.ensure(directory)
        }
        let profiles = Paths.support.appendingPathComponent("IsolationProfiles", isDirectory: true)
        try Paths.ensure(profiles)
        let file = profiles.appendingPathComponent(sha256Hex(Data(root.path.utf8)) + ".sb")
        try profile(prefix: root, engine: engine).write(to: file, atomically: true, encoding: .utf8)
        var env = base ?? WineEnvironment.makeBase(engine: engine, prefix: root)
        env["WINEPREFIX"] = root.path
        env["HOME"] = work.appendingPathComponent("home").path
        env["TMPDIR"] = work.appendingPathComponent("tmp").path
        env["PATH"] = "/usr/bin:/bin"
        env["USER"] = "isolated"
        env["LOGNAME"] = "isolated"
        env["WINEMSYNC"] = "0"
        env["GST_REGISTRY_1_0"] = work.appendingPathComponent("cache/gstreamer.bin").path
        env["DXVK_STATE_CACHE_PATH"] = work.appendingPathComponent("cache/dxvk").path
        env["EXERUNNER_SANDBOX_PROFILE"] = file.path
        let overrides = (env["WINEDLLOVERRIDES"] ?? "").split(separator: ";").filter { !$0.lowercased().hasPrefix("winemenubuilder") }.joined(separator: ";")
        env["WINEDLLOVERRIDES"] = "winemenubuilder.exe=d" + (overrides.isEmpty ? "" : ";" + overrides)
        return env
    }

    static func run(_ item: LibraryItem, bottle: Bottle, engine: Engine, log: URL, extra: [String: String] = [:]) async throws -> Int32 {
        guard let executable = bottle.hostURL(forWindowsPath: item.executable),
              inside(executable, bottle.driveC), FileManager.default.fileExists(atPath: executable.path) else {
            throw AppError(t("Для изоляции программа должна находиться внутри отдельной бутылки."))
        }
        // Refuse to attach to a pre-existing server, even one with no remaining Windows clients.
        var info = stat()
        guard stat(bottle.url.path, &info) == 0 else { throw AppError("Missing isolated bottle") }
        let socket = "/private/tmp/.wine-\(getuid())/server-\(String(UInt64(info.st_dev), radix: 16))-\(String(UInt64(info.st_ino), radix: 16))/socket"
        let fd = socketDescriptor()
        if fd >= 0 {
            defer { close(fd) }
            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
            let bytes = Array(socket.utf8) + [0]
            withUnsafeMutableBytes(of: &address.sun_path) { destination in
                for (i, b) in bytes.prefix(destination.count).enumerated() { destination[i] = b }
            }
            let connected = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0 }
            }
            guard !connected else { throw AppError(t("Изолированная бутылка уже запущена. Останови её перед новым запуском.")) }
        }
        let base = WineEnvironment.makeBase(engine: engine, prefix: bottle.url, extra: extra)
        let env = try environment(bottle: bottle, engine: engine, base: base)
        if !bottle.exists {
            let boot = try await WineProcess.run(engine: engine, arguments: ["wineboot", "--init"], environment: env, log: log)
            await WineProcess.server("-w", engine: engine, environment: env)
            guard boot == 0, bottle.exists else { throw AppError(t("Не удалось подготовить изолированную бутылку. Подробности в журнале.")) }
        }
        try Task.checkCancellation()
        let status = try await WineProcess.run(engine: engine, arguments: [item.executable] + item.arguments,
                                              environment: env, log: log, directory: executable.deletingLastPathComponent())
        await WineProcess.server("-w", engine: engine, environment: env)
        return status
    }
    private static func socketDescriptor() -> Int32 { Darwin.socket(AF_UNIX, SOCK_STREAM, 0) }
}
