import Foundation

/// The app was called WinRunner until 10/10/2026. Its settings, library, imported D3DMetal, logs
/// and shortcuts move to the new name once; a bottle's bookkeeping files are renamed when it is
/// next used.
enum Migration {
    private static let oldName = "WinRunner"

    static func run() {
        let fm = FileManager.default
        let moves: [(URL, URL)] = [
            (Paths.support.deletingLastPathComponent().appendingPathComponent(oldName, isDirectory: true), Paths.support),
            (Paths.logs.deletingLastPathComponent().appendingPathComponent(oldName, isDirectory: true), Paths.logs),
            (Paths.shortcuts.deletingLastPathComponent().appendingPathComponent("\(oldName) Apps", isDirectory: true), Paths.shortcuts),
        ]
        for (old, new) in moves where fm.fileExists(atPath: old.path) && !fm.fileExists(atPath: new.path) {
            try? fm.moveItem(at: old, to: new)
        }
    }

    /// .winrunner-overrides, .winrunner-compat-env and the rest become .exerunner-…
    static func renameStamps(in bottle: Bottle) {
        let fm = FileManager.default
        let old = ".winrunner-"
        guard let names = try? fm.contentsOfDirectory(atPath: bottle.url.path) else { return }
        for name in names where name.hasPrefix(old) {
            let target = bottle.url.appendingPathComponent(".exerunner-" + name.dropFirst(old.count))
            if !fm.fileExists(atPath: target.path) { try? fm.moveItem(at: bottle.url.appendingPathComponent(name), to: target) }
        }
    }
}
