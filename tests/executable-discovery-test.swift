import Foundation

@main enum Test {
    static func main() throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let drive = root.appendingPathComponent("drive_c")
        var checks = 0
        func check(_ value: Bool, _ name: String) { if !value { FileHandle.standardError.write(Data(("FAIL: " + name + "\n").utf8)); exit(1) }; checks += 1 }
        func file(_ path: String) throws -> URL {
            let url = drive.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("synthetic EXE fixture, never executed".utf8).write(to: url)
            return url
        }
        let cad = try file("Vendor CAD/Version 10/bin/ugraf.EXE")
        let local = try file("users/test/AppData/Local/OtherVendor/start.exe")
        let roaming = try file("users/test/AppData/Roaming/Portable/main.exe")
        let standard = try file("Program Files/Another/main.exe")
        let rootEXE = try file("root.exe")
        let helper = try file("Vendor CAD/Version 10/bin/crash-helper.exe")
        _ = try file("Windows/System32/not-an-app.exe")
        _ = try file(".hidden/hidden.exe")
        try fm.createDirectory(at: drive.appendingPathComponent("directory.exe"), withIntermediateDirectories: true)
        let outside = root.appendingPathComponent("outside")
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("must not be discovered".utf8).write(to: outside.appendingPathComponent("private.exe"))
        try fm.createSymbolicLink(at: drive.appendingPathComponent("MacFiles"), withDestinationURL: outside)
        try fm.createSymbolicLink(at: drive.appendingPathComponent("linked.exe"), withDestinationURL: outside.appendingPathComponent("private.exe"))
        for i in 0..<2000 { _ = try file("Vendor CAD/Version 10/bin/tool\(i).exe") }
        let found = ExecutableDiscovery.scan(driveC: drive)
        check(found.count == 2006, "all EXEs with no arbitrary count cap")
        check(found.contains(cad) && found.contains(local) && found.contains(roaming), "nonstandard and complete AppData paths")
        check(found.contains(standard) && found.contains(rootEXE), "standard and root install")
        check(!found.contains { $0.lastPathComponent == "private.exe" || $0.lastPathComponent == "linked.exe" }, "no Mac link traversal/files")
        check(!found.contains { $0.path.contains("Windows/") || $0.path.contains(".hidden/") || $0.lastPathComponent == "directory.exe" }, "system/hidden/non-files excluded")
        let again = ExecutableDiscovery.scan(driveC: drive)
        check(again.contains(cad), "repair/reinstall still returns an unchanged main path")
        let matches = ExecutableDiscovery.groups(found, driveC: drive, query: "VERSION 10 UGRAF")
        check(matches.count == 1 && matches[0].files == [cad], "case-insensitive multi-term name and path search")
        let groups = ExecutableDiscovery.groups(found, driveC: drive, query: "")
        let cadGroup = groups.first { $0.files.contains(cad) }!
        check(cadGroup.files.count == 2002, "large app grouped below install folder")
        check(cadGroup.additional == [helper] && cadGroup.primary.contains(cad), "additional helpers are nested, never hidden")
        check(ExecutableDiscovery.groups(found, driveC: drive, query: "crash helper").first?.files == [helper], "helper discoverable by search")
        check(ExecutableDiscovery.groups(found, driveC: drive, query: "no such program").isEmpty, "empty search")
        check(ExecutableDiscovery.groups([cad,cad], driveC: drive, query: "").count == 1, "duplicate path grouped once")
        check(ExecutableDiscovery.path(rootEXE, driveC: drive) == "C:\\root.exe", "Windows display path")
        check(groups.first { $0.files.contains(rootEXE) }?.title == "C:\\", "root group Windows path")
        let linkedRoot = root.appendingPathComponent("linked_c")
        try fm.createSymbolicLink(at: linkedRoot, withDestinationURL: outside)
        check(ExecutableDiscovery.scan(driveC: linkedRoot).isEmpty, "linked drive root not followed")
        check(ExecutableDiscovery.usable(cad), "regular readable EXE accepted")
        check(!ExecutableDiscovery.usable(drive.appendingPathComponent("directory.exe")), "directory EXE rejected")
        try fm.removeItem(at: cad)
        check(!ExecutableDiscovery.usable(cad), "stale removed selection rejected before Add")
        print("executable-discovery: \(checks) passed, 2000 helper-sized fixture files")
    }
}
