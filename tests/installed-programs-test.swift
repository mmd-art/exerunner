import Foundation
@main struct Check {
 static func main() throws {
    let root = URL(fileURLWithPath: CommandLine.arguments[1])
    let fm = FileManager.default
    func file(_ path: String) throws { let u = root.appendingPathComponent(path); try fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true); try Data("fixture".utf8).write(to: u) }
    try file("cad/system.reg"); try file("cad/drive_c/Siemens/NX 10.0/NXBIN/ugraf.exe")
    try file("cad/drive_c/Siemens/NX 10.0/NXBIN/helper.exe")
    try file("games/system.reg"); try file("games/drive_c/Other/game.exe")
    try file("partial/drive_c/setup.exe")
    try fm.createSymbolicLink(atPath: root.appendingPathComponent("linked").path, withDestinationPath: root.appendingPathComponent("games").path)
    precondition(InstalledPrograms.environments(root: root) == ["cad", "games"])
    let before = try Data(contentsOf: root.appendingPathComponent("cad/system.reg"))
    let found = InstalledPrograms.executables(root: root, environment: "cad")
    precondition(found.count == 2 && found.contains { $0.lastPathComponent == "ugraf.exe" })
    precondition(!found.contains { $0.lastPathComponent == "game.exe" })
    precondition(ExecutableDiscovery.groups(found, driveC: root.appendingPathComponent("cad/drive_c"), query: "ugraf").count == 1)
    precondition(InstalledPrograms.executables(root: root, environment: "../games").isEmpty)
    precondition(InstalledPrograms.executables(root: root, environment: "linked").isEmpty)
    precondition(InstalledPrograms.executables(root: root, environment: "missing").isEmpty)
    precondition(!fm.fileExists(atPath: root.appendingPathComponent("missing").path))
    let after = try Data(contentsOf: root.appendingPathComponent("cad/system.reg"))
    precondition(after == before)
    try fm.removeItem(at: root.appendingPathComponent("cad"))
    precondition(InstalledPrograms.executables(root: root, environment: "cad").isEmpty)
    print("Installed-program import: 10 read-only environment/discovery checks passed")
 }
}
