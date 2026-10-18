import CryptoKit
import Foundation
import Darwin

/// Manual, selected-folder snapshots. No game detection, prefix copy, cloud sync or pruning.
/// Independent implementation; MacadeKit 0.1.1 was evaluated but no code was imported.
enum SaveArchive {
    struct File: Codable, Equatable {
        var path: String
        var bytes: Int
        var sha256: String
    }
    struct Manifest: Codable, Equatable {
        var format = 1
        var itemID: String
        var created: Date
        var files: [File]
    }
    struct Plan {
        var archive: URL
        var destination: URL
        var manifest: Manifest
        var existing: [File]
        var replacing: Int
    }
    struct RestoreResult { var files: Int; var safetyCopy: URL }
    static let maximumBytes = 256 * 1024 * 1024
    static let maximumEntries = 10_000
    private static let fm = FileManager.default

    static func safeRelative(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("\0") && !name.contains("\\") &&
        !name.contains(":") && !name.hasPrefix("/") &&
        name.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
    /// Fail closed on links at any level, including the selected root and its ancestors.
    static func checkedDirectory(_ url: URL) throws -> URL {
        // Foundation spells the system temporary directory /var even after resolution.
        // Normalize only Apple's fixed aliases; user-controlled symlinks still fail closed.
        var raw = url.path
        if raw == "/var" || raw.hasPrefix("/var/") || raw == "/tmp" || raw.hasPrefix("/tmp/") { raw = "/private" + raw }
        let root = URL(fileURLWithPath: raw)
        var part = root
        while part.path != "/" {
            if let type = try? fm.attributesOfItem(atPath: part.path)[.type] as? FileAttributeType,
               type != .typeDirectory { throw AppError(t("Папка сохранений содержит ссылку или недоступна.")) }
            part.deleteLastPathComponent()
        }
        guard (try fm.attributesOfItem(atPath: root.path)[.type] as? FileAttributeType) == .typeDirectory else {
            throw AppError(t("Папка сохранений содержит ссылку или недоступна."))
        }
        return root
    }
    private static func inside(_ child: URL, _ parent: URL) -> Bool {
        child.path == parent.path || child.path.hasPrefix(parent.path + "/")
    }
    private static func nested(_ a: URL, _ b: URL) -> Bool {
        a.path == b.path || a.path.hasPrefix(b.path + "/") || b.path.hasPrefix(a.path + "/")
    }
    static func inventory(_ folder: URL) throws -> [File] {
        let root = try checkedDirectory(folder)
        guard root.pathExtension.lowercased() != "app" else { throw AppError(t("Выбери папку сохранений, а не установленную игру.")) }
        var result: [File] = [], bytes = 0, entries = 0
        func walk(_ dir: URL, _ prefix: String, _ depth: Int) throws {
            guard depth <= 40 else { throw AppError(t("Выбери только папку сохранений: превышен лимит размера или файлов.")) }
            for name in try fm.contentsOfDirectory(atPath: dir.path).sorted() {
                let relative = prefix + name
                entries += 1
                guard entries <= maximumEntries, safeRelative(relative) else { throw AppError(t("Небезопасный путь в копии сохранений.")) }
                let file = dir.appendingPathComponent(name)
                let attrs = try fm.attributesOfItem(atPath: file.path)
                switch attrs[.type] as? FileAttributeType {
                case .typeDirectory:
                    guard file.pathExtension.lowercased() != "app" else { throw AppError(t("Выбери папку сохранений, а не установленную игру.")) }
                    try walk(file, relative + "/", depth + 1)
                case .typeRegular:
                    // Never mistake an installation folder or app bundle for saved progress.
                    guard !["exe", "dll", "dylib", "so", "app"].contains(file.pathExtension.lowercased()) else {
                        throw AppError(t("Выбери папку сохранений, а не установленную игру."))
                    }
                    let size = (attrs[.size] as? NSNumber)?.intValue ?? maximumBytes + 1
                    guard size <= maximumBytes - bytes else { throw AppError(t("Выбери только папку сохранений: превышен лимит размера или файлов.")) }
                    let data = try boundedRead(file, limit: maximumBytes - bytes)
                    guard data.count == size else { throw AppError(t("Сохранения изменились во время операции. Повтори после выхода из игры.")) }
                    bytes += size
                    result.append(File(path: relative, bytes: size, sha256: hash(data)))
                default: throw AppError(t("Папка сохранений содержит ссылку или недоступна."))
                }
            }
        }
        try walk(root, "", 0)
        try validateAliases(result)
        return result.sorted { $0.path < $1.path }
    }
    /// Portable archives must also be safe on the default case-insensitive Mac filesystem.
    static func validateAliases(_ files: [File]) throws {
        var aliases: [String: String] = [:]
        for file in files {
            var prefix = ""
            for part in file.path.split(separator: "/") {
                prefix += prefix.isEmpty ? String(part) : "/" + part
                let key = prefix.precomposedStringWithCanonicalMapping.lowercased(with: Locale(identifier: "en_US_POSIX"))
                if let previous = aliases[key], previous != prefix { throw AppError(t("В папке восстановления конфликт файлов и папок.")) }
                aliases[key] = prefix
            }
        }
    }
    private static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func boundedRead(_ file: URL, limit: Int) throws -> Data {
        let fd = open(file.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw AppError(t("Небезопасный путь в копии сохранений.")) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_size >= 0, info.st_size <= limit else {
            throw AppError(t("Выбери только папку сохранений: превышен лимит размера или файлов."))
        }
        var result = Data()
        while true {
            let chunk = try handle.read(upToCount: min(1024 * 1024, limit - result.count + 1)) ?? Data()
            if chunk.isEmpty { break }
            guard chunk.count <= limit - result.count else { throw AppError(t("Выбери только папку сохранений: превышен лимит размера или файлов.")) }
            result.append(chunk)
        }
        return result
    }

    @discardableResult
    static func create(itemID: String, source: URL, parent: URL, allowEmpty: Bool = false) throws -> URL {
        let source = try checkedDirectory(source), parent = try checkedDirectory(parent)
        guard !inside(parent, source) else { throw AppError(t("Копия и папка сохранений должны находиться отдельно.")) }
        let files = try inventory(source)
        guard allowEmpty || !files.isEmpty else { throw AppError(t("В выбранной папке нет сохранений.")) }
        let archive = parent.appendingPathComponent("ExeRunner-Saves-" + UUID().uuidString, isDirectory: true)
        // A fresh UUID directory is the only output owned here; never remove an owner's folder.
        try fm.createDirectory(at: archive, withIntermediateDirectories: false)
        let dataRoot = archive.appendingPathComponent("data", isDirectory: true)
        try fm.createDirectory(at: dataRoot, withIntermediateDirectories: false)
        for file in files {
            let input = source.appendingPathComponent(file.path), output = dataRoot.appendingPathComponent(file.path)
            try checkedFile(input, within: source)
            let data = try boundedRead(input, limit: file.bytes)
            guard data.count == file.bytes && hash(data) == file.sha256 else { throw AppError(t("Сохранения изменились во время операции. Повтори после выхода из игры.")) }
            try fm.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: output, options: .withoutOverwriting)
        }
        guard try inventory(source) == files, try inventory(dataRoot) == files else {
            throw AppError(t("Сохранения изменились во время операции. Повтори после выхода из игры."))
        }
        // Manifest is written last: interrupted exports cannot be mistaken for complete backups.
        let manifest = Manifest(itemID: itemID, created: Date(), files: files)
        try JSONEncoder().encode(manifest).write(to: archive.appendingPathComponent("manifest.json"), options: .withoutOverwriting)
        return archive
    }

    private static func checkedFile(_ file: URL, within root: URL) throws {
        _ = try checkedDirectory(file.deletingLastPathComponent())
        guard file.path.hasPrefix(root.path + "/"),
              (try fm.attributesOfItem(atPath: file.path)[.type] as? FileAttributeType) == .typeRegular else {
            throw AppError(t("Небезопасный путь в копии сохранений."))
        }
    }
    static func read(_ archive: URL, itemID: String) throws -> Manifest {
        let archive = try checkedDirectory(archive), file = archive.appendingPathComponent("manifest.json")
        try checkedFile(file, within: archive)
        let size = (try fm.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue ?? Int.max
        guard size <= 4 * 1024 * 1024 else { throw AppError(t("Небезопасный путь в копии сохранений.")) }
        let manifest = try JSONDecoder().decode(Manifest.self, from: boundedRead(file, limit: 4 * 1024 * 1024))
        guard manifest.format == 1, manifest.itemID == itemID, manifest.files.count <= maximumEntries,
              Set(manifest.files.map(\.path)).count == manifest.files.count,
              manifest.files.allSatisfy({ safeRelative($0.path) && $0.bytes >= 0 }),
              manifest.files == (try inventory(archive.appendingPathComponent("data"))) else {
            throw AppError(t("Копия повреждена или относится к другой игре."))
        }
        try validateAliases(manifest.files)
        return manifest
    }
    static func plan(archive: URL, itemID: String, destination: URL) throws -> Plan {
        let archive = try checkedDirectory(archive), destination = try checkedDirectory(destination)
        guard !nested(archive, destination) else { throw AppError(t("Копия и папка сохранений должны находиться отдельно.")) }
        let manifest = try read(archive, itemID: itemID), existing = try inventory(destination)
        let names = Set(existing.map(\.path))
        try validateAliases(existing + manifest.files)
        var listings: [String: [String]] = [:]
        // Reject file/directory conflicts before making any changes.
        for file in manifest.files {
            // Include empty directories: file-only inventories cannot expose their spelling.
            var current = destination
            for component in file.path.split(separator: "/").map(String.init) {
                guard fm.fileExists(atPath: current.path) else { break }
                if listings[current.path] == nil { listings[current.path] = try fm.contentsOfDirectory(atPath: current.path) }
                let key = component.precomposedStringWithCanonicalMapping.lowercased(with: Locale(identifier: "en_US_POSIX"))
                guard listings[current.path]!.allSatisfy({ $0 == component || $0.precomposedStringWithCanonicalMapping.lowercased(with: Locale(identifier: "en_US_POSIX")) != key }) else {
                    throw AppError(t("В папке восстановления конфликт файлов и папок."))
                }
                current.appendPathComponent(component)
            }
            let target = destination.appendingPathComponent(file.path)
            var parent = target.deletingLastPathComponent()
            while parent.path != destination.path {
                if fm.fileExists(atPath: parent.path), (try fm.attributesOfItem(atPath: parent.path)[.type] as? FileAttributeType) != .typeDirectory {
                    throw AppError(t("В папке восстановления конфликт файлов и папок."))
                }
                parent.deleteLastPathComponent()
            }
            if fm.fileExists(atPath: target.path), !names.contains(file.path) { throw AppError(t("В папке восстановления конфликт файлов и папок.")) }
        }
        return Plan(archive: archive, destination: destination, manifest: manifest, existing: existing,
                    replacing: manifest.files.filter { names.contains($0.path) }.count)
    }

    static func restore(_ plan: Plan, safetyParent: URL, permitWrite: (Int) throws -> Void = { _ in }) throws -> RestoreResult {
        let safetyParent = try checkedDirectory(safetyParent)
        guard !inside(safetyParent, plan.archive), !inside(safetyParent, plan.destination) else {
            throw AppError(t("Копия и папка сохранений должны находиться отдельно."))
        }
        guard try read(plan.archive, itemID: plan.manifest.itemID) == plan.manifest,
              try inventory(plan.destination) == plan.existing else {
            throw AppError(t("Сохранения изменились во время операции. Повтори после выхода из игры."))
        }
        // Mandatory verified safety copy. No writes if creation fails, even for an empty folder.
        let safety = try create(itemID: plan.manifest.itemID, source: plan.destination, parent: safetyParent, allowEmpty: true)
        _ = try read(safety, itemID: plan.manifest.itemID)
        guard try inventory(plan.destination) == plan.existing else { throw AppError(t("Сохранения изменились во время операции. Повтори после выхода из игры.")) }
        let journal = safety.appendingPathComponent("restore-result.json")
        try JSONSerialization.data(withJSONObject: ["destination": plan.destination.path, "complete": false], options: .sortedKeys).write(to: journal, options: .atomic)
        do {
            for (index, file) in plan.manifest.files.enumerated() {
                try permitWrite(index)
                let source = plan.archive.appendingPathComponent("data/" + file.path)
                try checkedFile(source, within: plan.archive)
                let data = try boundedRead(source, limit: file.bytes)
                guard data.count == file.bytes && hash(data) == file.sha256 else { throw AppError(t("Копия повреждена или относится к другой игре.")) }
                let output = plan.destination.appendingPathComponent(file.path)
                try fm.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
                _ = try checkedDirectory(output.deletingLastPathComponent())
                if fm.fileExists(atPath: output.path) { try checkedFile(output, within: plan.destination) }
                try data.write(to: output, options: .atomic)
            }
            var expected = Dictionary(uniqueKeysWithValues: plan.existing.map { ($0.path, $0) })
            for file in plan.manifest.files { expected[file.path] = file }
            guard try inventory(plan.destination) == expected.values.sorted(by: { $0.path < $1.path }) else {
                throw AppError(t("Сохранения изменились во время операции. Повтори после выхода из игры."))
            }
            try JSONSerialization.data(withJSONObject: ["destination": plan.destination.path, "complete": true], options: .sortedKeys).write(to: journal, options: .atomic)
        } catch {
            // Preserve both copies, and disclose the exact recovery location on partial failure.
            throw AppError(t("Восстановление не завершено. Исходные файлы сохранены здесь:") + "\n" + safety.path + "\n" + error.localizedDescription)
        }
        return RestoreResult(files: plan.manifest.files.count, safetyCopy: safety)
    }
}
