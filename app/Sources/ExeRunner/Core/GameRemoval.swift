import Foundation

/// A user-selected installation, never inferred from an EXE's parent. No permanent deletion.
enum GameRemoval {
    struct Plan {
        let folder: URL
        let device: UInt64
        let inode: UInt64
        let executable: URL
    }
    static func plan(folder: URL, driveC: URL, executable: URL, otherExecutables: [URL]) throws -> Plan {
        let root = try SaveArchive.checkedDirectory(driveC)
        let selected = try SaveArchive.checkedDirectory(folder)
        let prefix = root.path + "/"
        guard selected.path.hasPrefix(prefix) else { throw AppError(t("Выбери отдельную папку игры внутри диска C этой Windows-среды.")) }
        let parts = String(selected.path.dropFirst(prefix.count)).split(separator: "/").map(String.init)
        let container = parts.first?.lowercased() ?? ""
        // Only explicit installation containers; never Windows, users, ProgramData or all Games.
        guard ["games", "program files", "program files (x86)"].contains(container), parts.count >= 2 else {
            throw AppError(t("Выбери отдельную папку игры внутри диска C этой Windows-среды."))
        }
        func contains(_ file: URL) -> Bool {
            var path = file.resolvingSymlinksInPath().path
            if path.hasPrefix("/var/") || path.hasPrefix("/tmp/") { path = "/private" + path }
            return path.hasPrefix(selected.path + "/")
        }
        guard contains(executable), FileManager.default.fileExists(atPath: executable.path),
              !otherExecutables.contains(where: contains) else {
            throw AppError(t("Папка не содержит EXE этой игры или используется другой карточкой. Удаление отменено."))
        }
        let attrs = try FileManager.default.attributesOfItem(atPath: selected.path)
        return Plan(folder: selected, device: (attrs[.systemNumber] as? NSNumber)?.uint64Value ?? 0,
                    inode: (attrs[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0, executable: executable)
    }
    static func validate(_ plan: Plan) throws {
        let root = try SaveArchive.checkedDirectory(plan.folder)
        let attrs = try FileManager.default.attributesOfItem(atPath: root.path)
        guard plan.device != 0, plan.inode != 0,
              (attrs[.systemNumber] as? NSNumber)?.uint64Value == plan.device,
              (attrs[.systemFileNumber] as? NSNumber)?.uint64Value == plan.inode,
              FileManager.default.fileExists(atPath: plan.executable.path) else {
            throw AppError(t("Папка игры изменилась. Выбери её заново."))
        }
    }
}
