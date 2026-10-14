import Foundation
import Darwin

/// Serialize process creation against app shutdown. Applies only to this app's launches;
/// other Wine prefixes and native applications are never stopped here.
enum PrefixLaunchGate {
    private static let lock = NSLock()
    private static var closed: Set<String> = []
    private static var processes: [String: [Process]] = [:]

    static func start(_ process: Process) throws {
        guard let raw = process.environment?["WINEPREFIX"] else { try process.run(); return }
        let prefix = URL(fileURLWithPath: raw).standardizedFileURL.path
        lock.lock()
        defer { lock.unlock() }
        guard !closed.contains(prefix) else { throw CancellationError() }
        let componentLease = process.environment?["EXERUNNER_COMPONENT_INSTALL"] == "1" ? nil :
            try PrefixComponentLease.launch(in: URL(fileURLWithPath: prefix))
        defer { componentLease?.release() }
        try process.run()
        processes[prefix, default: []].removeAll { !$0.isRunning }
        processes[prefix, default: []].append(process)
    }

    static func close(_ prefixes: Set<String>) {
        lock.lock()
        defer { lock.unlock() }
        closed.formUnion(prefixes)
        // Includes a still-running installer/winetricks parent that could spawn more Wine.
        // wineserver -k, called next, also stops descendants in each selected prefix.
        for prefix in prefixes {
            for process in processes.removeValue(forKey: prefix) ?? [] where process.isRunning {
                process.terminate()
            }
        }
    }
}

/// Cooperative cross-process guard for common-component installation. OS file locks release
/// after a crash; no stale "busy" flag can permanently block a bottle or require user cleanup.
final class PrefixComponentLease {
    private var descriptor: Int32
    private init(descriptor: Int32) { self.descriptor = descriptor }
    deinit { release() }

    static func installation(in prefix: URL) throws -> PrefixComponentLease {
        try acquire(in: prefix, mode: LOCK_EX)
    }

    static func launch(in prefix: URL) throws -> PrefixComponentLease? {
        // wineboot creates a new prefix; there cannot yet be an install lease inside it.
        guard FileManager.default.fileExists(atPath: prefix.path) else { return nil }
        return try acquire(in: prefix, mode: LOCK_SH)
    }

    private static func acquire(in prefix: URL, mode: Int32) throws -> PrefixComponentLease {
        let file = prefix.appendingPathComponent(".exerunner-components.lock")
        let fd = open(file.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw AppError(t("Не удалось открыть блокировку установки компонентов Windows.")) }
        guard flock(fd, mode | LOCK_NB) == 0 else {
            close(fd)
            throw AppError(t("В этой бутылке уже идёт установка компонентов."))
        }
        return PrefixComponentLease(descriptor: fd)
    }

    func release() {
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN); close(descriptor); descriptor = -1
    }
}
