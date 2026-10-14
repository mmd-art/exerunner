import Foundation
import Darwin

/// Only ExeRunner-managed links are changed. Other dosdevices entries remain untouched.
enum SerialPortMapper {
    typealias Port = BottleSettings.SerialPort
    private static func record(_ bottle: Bottle) -> URL { bottle.url.appendingPathComponent(".exerunner-serial-ports.json") }
    static func valid(_ port: Port) -> Bool {
        guard (1...255).contains(port.number), port.device.hasPrefix("/dev/") else { return false }
        let leaf = URL(fileURLWithPath: port.device).lastPathComponent
        return port.device == "/dev/" + leaf && !leaf.contains("\n") && !leaf.contains("\r") &&
            (leaf.hasPrefix("cu.") || leaf.hasPrefix("tty.") || leaf.hasPrefix("ttys"))
    }
    static func connected(_ path: String) -> Bool {
        var info = stat()
        return stat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFCHR
    }
    static func validate(_ ports: [Port]) throws {
        guard ports.count <= 255, ports.allSatisfy(valid), Set(ports.map(\.number)).count == ports.count else {
            throw AppError(t("COM-порты должны быть уникальными, от COM1 до COM255, и вести к последовательным устройствам в /dev."))
        }
    }
    static func managed(in bottle: Bottle) throws -> [Port] {
        let file = record(bottle)
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        guard let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 256 * 1024 else {
            throw AppError(t("Запись COM-портов повреждена; существующие подключения сохранены."))
        }
        let ports = try JSONDecoder().decode([Port].self, from: Data(contentsOf: file))
        try validate(ports)
        return ports
    }
    static func link(in bottle: Bottle, number: Int) -> URL {
        bottle.url.appendingPathComponent("dosdevices/com\(number)")
    }
    private static func exists(_ url: URL) -> Bool {
        var info = stat(); return lstat(url.path, &info) == 0
    }
    /// Numbers configured outside this manager, including registry-only mappings.
    static func unmanagedNumbers(in bottle: Bottle) throws -> Set<Int> {
        let previous = Dictionary(uniqueKeysWithValues: try managed(in: bottle).map { ($0.number, $0.device) })
        var reserved: Set<Int> = []
        let nodes = (try? FileManager.default.contentsOfDirectory(atPath: bottle.url.appendingPathComponent("dosdevices").path)) ?? []
        for name in nodes {
            let lower = name.lowercased()
            guard lower.hasPrefix("com"), let number = Int(lower.dropFirst(3)), (1...255).contains(number) else { continue }
            let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: bottle.url.appendingPathComponent("dosdevices/" + name).path)
            if previous[number] == nil || previous[number] != destination { reserved.insert(number) }
        }
        let values = BottleManager.registryValues(in: bottle, hive: "system.reg", key: "Software\\\\Wine\\\\Ports") ?? [:]
        for (name, value) in values {
            guard name.hasPrefix("com"), let number = Int(name.dropFirst(3)), (1...255).contains(number) else { continue }
            if previous[number] == nil || previous[number] != value { reserved.insert(number) }
        }
        return reserved
    }
    private struct Transaction {
        let old: [Port]
        let next: [Int: String]
        let numbers: [Int]
        let current: [Int: String]
    }
    private static func transaction(_ wanted: [Port], in bottle: Bottle) throws -> Transaction {
        try validate(wanted)
        let old = try managed(in: bottle)
        guard FileManager.default.fileExists(atPath: bottle.url.appendingPathComponent("dosdevices").path) else {
            throw AppError(t("Windows-среда ещё не создана."))
        }
        let previous = Dictionary(uniqueKeysWithValues: old.map { ($0.number, $0.device) })
        let next = Dictionary(uniqueKeysWithValues: wanted.map { ($0.number, $0.device) })
        let numbers = Set(previous.keys).union(next.keys).sorted()
        var current: [Int: String] = [:]
        // Validate the whole transaction before touching any link.
        for number in numbers {
            let file = link(in: bottle, number: number)
            if exists(file) {
                guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: file.path),
                      previous[number] == destination else {
                    throw AppError(t("COM\(number) уже настроен вне ExeRunner. Существующее подключение сохранено."))
                }
                current[number] = destination
            }
            if let target = next[number], FileManager.default.fileExists(atPath: target), !connected(target) {
                throw AppError(t("COM-порт должен вести к последовательному устройству, а не к обычному файлу."))
            }
        }
        return Transaction(old: old, next: next, numbers: numbers, current: current)
    }
    static func validateChange(_ wanted: [Port], in bottle: Bottle) throws {
        _ = try transaction(wanted, in: bottle)
    }
    /// Called while the common exclusive configuration lease is held by the caller.
    @discardableResult
    static func apply(_ wanted: [Port], in bottle: Bottle) throws -> [Port] {
        if wanted.isEmpty, try managed(in: bottle).isEmpty { return [] }
        let change = try transaction(wanted, in: bottle)
        let old = change.old, next = change.next, numbers = change.numbers, current = change.current
        var changed: [Int] = []
        do {
            for number in numbers where current[number] != next[number] {
                let file = link(in: bottle, number: number)
                if let target = next[number] {
                    let temporary = file.deletingLastPathComponent().appendingPathComponent(".exerunner-com-\(UUID().uuidString)")
                    try FileManager.default.createSymbolicLink(atPath: temporary.path, withDestinationPath: target)
                    defer { try? FileManager.default.removeItem(at: temporary) }
                    guard rename(temporary.path, file.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                } else if exists(file) { try FileManager.default.removeItem(at: file) }
                changed.append(number)
            }
            try JSONEncoder().encode(wanted.sorted { $0.number < $1.number }).write(to: record(bottle), options: .atomic)
        } catch {
            for number in changed.reversed() {
                let file = link(in: bottle, number: number)
                if exists(file) { try? FileManager.default.removeItem(at: file) }
                if let target = current[number] { try? FileManager.default.createSymbolicLink(atPath: file.path, withDestinationPath: target) }
            }
            throw error
        }
        return old
    }
    static func registry(previous: [Port], desired: [Port]) -> String {
        func escape(_ value: String) -> String { value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }
        let removed = Set(previous.map(\.number)).subtracting(desired.map(\.number)).sorted()
        let current = desired.sorted { $0.number < $1.number }
        var result = "\n[HKEY_LOCAL_MACHINE\\Software\\Wine\\Ports]\n"
        for n in removed { result += "\"COM\(n)\"=-\n" }
        for port in current { result += "\"\(port.name)\"=\"\(escape(port.device))\"\n" }
        result += "\n[HKEY_LOCAL_MACHINE\\Hardware\\DeviceMap\\SerialComm]\n"
        for n in removed { result += "\"\\\\Device\\\\ExeRunnerCOM\(n)\"=-\n" }
        for port in current { result += "\"\\\\Device\\\\ExeRunner\(port.name)\"=\"\(port.name)\"\n" }
        return result
    }
}
