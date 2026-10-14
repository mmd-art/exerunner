import Darwin
import Foundation

/// Protected and unrestricted sessions keep separate disks. Changes are never
/// copied from an unrestricted session back into its protected counterpart.
enum LaunchModes {
    static func change(_ proposed: LibraryItem, from previous: LibraryItem, root: URL) throws -> LibraryItem {
        var item = proposed
        let wasIsolated = previous.isolated || previous.bottle.hasPrefix("isolated-")
        guard proposed.isolated != wasIsolated else {
            item.bottle = previous.bottle
            item.isolatedBottle = previous.isolatedBottle
            item.ordinaryBottle = previous.ordinaryBottle
            return item
        }
        guard !item.isSteamGame, item.kind != .launcher else {
            throw AppError(t("Изоляция пока недоступна для лаунчеров и игр, запускаемых через Steam."))
        }
        let source = try checked(previous.bottle, root: root)
        guard let executable = source.hostURL(forWindowsPath: item.executable),
              IsolatedWine.inside(executable, source.driveC), FileManager.default.fileExists(atPath: executable.path) else {
            throw AppError(t("Для смены режима программа должна находиться внутри бутылки. Добавь установленный EXE из неё."))
        }
        try requireStopped(source)
        let digest = String(sha256Hex(Data(item.id.utf8)).prefix(16))
        if item.isolated {
            item.ordinaryBottle = previous.ordinaryBottle ?? previous.bottle
            if let name = previous.isolatedBottle {
                let destination = try checked(name, root: root)
                try requireProtected(destination)
                try requireStopped(destination)
                item.bottle = name
            } else {
                let destination = try copy(source, name: "isolated-" + digest, root: root, isolated: true, id: item.id)
                item.bottle = destination.name
                item.isolatedBottle = destination.name
            }
        } else {
            try requireProtected(source)
            item.isolatedBottle = previous.isolatedBottle ?? previous.bottle
            if let name = previous.ordinaryBottle {
                let destination = try checked(name, root: root)
                guard !name.hasPrefix("isolated-"), !exists(destination, ".exerunner-isolated-v1") else {
                    throw AppError(t("Защищённая бутылка не может использоваться для обычного запуска."))
                }
                try requireStopped(destination)
                item.bottle = name
            } else {
                let destination = try copy(source, name: "ordinary-" + digest, root: root, isolated: false, id: item.id)
                item.bottle = destination.name
                item.ordinaryBottle = destination.name
            }
        }
        return item
    }
    private static func checked(_ name: String, root: URL) throws -> Bottle {
        guard !name.isEmpty, name != ".", SteamLibrary.isFolderName(name) else { throw AppError("Invalid bottle name") }
        let bottle = Bottle(name: name, root: IsolatedWine.canonical(root))
        var info = stat()
        guard lstat(bottle.url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR,
              IsolatedWine.inside(bottle.url, root), bottle.exists else {
            throw AppError(t("Бутылка не найдена или её путь небезопасен."))
        }
        return bottle
    }
    private static func exists(_ bottle: Bottle, _ name: String) -> Bool {
        var info = stat()
        return lstat(bottle.url.appendingPathComponent(name).path, &info) == 0
    }
    private static func requireProtected(_ bottle: Bottle) throws {
        guard bottle.name.hasPrefix("isolated-"), exists(bottle, ".exerunner-isolated-v1"),
              !exists(bottle, ".exerunner-unrestricted") else {
            throw AppError(t("Изолированная бутылка не подготовлена. Обычный запуск не выполнен."))
        }
    }
    private static func requireStopped(_ bottle: Bottle) throws {
        guard !WineProcesses.list(includeServers: true).contains(where: { IsolatedWine.canonical(URL(fileURLWithPath: $0.prefix)).path == bottle.url.path }) else {
            throw AppError(t("Сначала останови программы этой бутылки, чтобы сменить режим."))
        }
    }
    private static func copy(_ source: Bottle, name: String, root: URL, isolated: Bool, id: String) throws -> Bottle {
        let destination = Bottle(name: name, root: IsolatedWine.canonical(root))
        let fm = FileManager.default
        let origin = Data((id + "\n" + source.url.path + "\n").utf8)
        if fm.fileExists(atPath: destination.url.path) {
            let existing = try checked(name, root: root)
            let validMarker = isolated ? exists(existing, ".exerunner-isolated-v1") && !exists(existing, ".exerunner-unrestricted") :
                                        exists(existing, ".exerunner-unrestricted") && !exists(existing, ".exerunner-isolated-v1")
            guard (try? Data(contentsOf: existing.url.appendingPathComponent(".exerunner-mode-origin"))) == origin, validMarker else {
                throw AppError(t("Папка для выбранного режима уже занята другой бутылкой."))
            }
            try requireStopped(existing)
            return existing
        }
        let staging = destination.url.deletingLastPathComponent().appendingPathComponent(".mode-copy-" + UUID().uuidString)
        defer { if fm.fileExists(atPath: staging.path) { try? fm.removeItem(at: staging) } }
        // APFS copy-on-write; -P copies links themselves, never external targets.
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/cp")
        process.arguments = ["-cR", "-P", source.url.path, staging.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = output
        try process.run()
        let error = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw AppError(t("Не удалось создать отдельную копию бутылки. Требуется диск APFS.") + " " + String(decoding: error.prefix(400), as: UTF8.self))
        }
        for marker in [".exerunner-isolated-v1", ".exerunner-unrestricted", ".exerunner-mode-origin"] {
            let file = staging.appendingPathComponent(marker)
            var info = stat()
            if lstat(file.path, &info) == 0 { try fm.removeItem(at: file) }
        }
        try Data("ExeRunner mode copy\n".utf8).write(to: staging.appendingPathComponent(isolated ? ".exerunner-isolated-v1" : ".exerunner-unrestricted"), options: .atomic)
        try origin.write(to: staging.appendingPathComponent(".exerunner-mode-origin"), options: .atomic)
        try fm.moveItem(at: staging, to: destination.url)
        return try checked(name, root: root)
    }
}

/// Pin directory descriptors so a guest-created link cannot redirect host writes.
enum NativeAssets {
    static func write(_ data: Data, named name: String, in bottle: Bottle) throws -> URL {
        guard !name.isEmpty, !name.contains("/"), name != ".", name != ".." else { throw AppError("Invalid native asset name") }
        let base = open(bottle.url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard base >= 0 else { throw AppError("Native asset bottle is missing or is a link") }
        defer { close(base) }
        if mkdirat(base, ".exerunner-native", 0o700) != 0 && errno != EEXIST { throw AppError("Cannot create native asset directory") }
        let folder = openat(base, ".exerunner-native", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard folder >= 0 else { throw AppError("Native asset directory is a symlink; launch refused") }
        defer { close(folder) }
        let temporary = ".icon-" + UUID().uuidString
        let file = openat(folder, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard file >= 0 else { throw AppError("Cannot create native icon") }
        defer { close(file); unlinkat(folder, temporary, 0) }
        try data.withUnsafeBytes { bytes in
            guard let pointer = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(file, pointer.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw AppError("Cannot write native icon") }
                offset += count
            }
        }
        guard renameat(folder, temporary, folder, name) == 0 else { throw AppError("Cannot publish native icon") }
        return bottle.url.appendingPathComponent(".exerunner-native/" + name)
    }
}
