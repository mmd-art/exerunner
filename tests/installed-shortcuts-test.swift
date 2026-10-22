import Foundation

@main enum Test {
    static func main() throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
        let drive = root.appendingPathComponent("drive_c")
        try fm.createDirectory(at: drive, withIntermediateDirectories: true)
        var checks = 0
        func check(_ value: Bool, _ message: String) {
            guard value else { print("FAIL: \(message)"); exit(1) }; checks += 1
        }
        func file(_ path: String, _ data: Data = Data("fixture, never executed".utf8)) throws -> URL {
            let url = drive.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url); return url
        }
        func link(_ target: String, args: String = "", work: String = "", unicode: Bool = true, local: Bool = false) -> Data {
            var d = Data(repeating: 0, count: 76)
            func set(_ value: Int, at index: Int, width: Int = 4) {
                for i in 0..<width { d[index+i] = UInt8(truncatingIfNeeded: value >> (i*8)) }
            }
            set(76, at: 0)
            d.replaceSubrange(4..<20, with: [1,0x14,2,0,0,0,0,0,0xc0,0,0,0,0,0,0,0x46])
            set((unicode ? 128 : 0) | (local ? 2 : 8) | (args.isEmpty ? 0 : 32) | (work.isEmpty ? 0 : 16), at: 20)
            if local {
                let text = Data(target.utf8)+Data([0]); let start = d.count
                d.append(Data(repeating: 0, count: 28)); d.append(text); d.append(0)
                set(d.count-start, at: start);set(28, at: start+4);set(1, at: start+8)
                set(28, at: start+16);set(28+text.count, at: start+24)
            }
            for value in [local ? "" : target, work, args] where !value.isEmpty {
                let text = unicode ? Data(value.utf16.flatMap { [UInt8(truncatingIfNeeded: $0), UInt8(truncatingIfNeeded: $0 >> 8)] }) : Data(value.utf8)
                let length = unicode ? text.count/2 : text.count
                d.append(UInt8(truncatingIfNeeded: length));d.append(UInt8(truncatingIfNeeded: length >> 8));d.append(text)
            }
            d.append(Data(repeating: 0, count: 4));return d
        }
        let cad = try file("Program Files/Siemens/NX 10.0/NXBIN/ugraf.exe")
        let tool = try file("Program Files/Siemens/NX 10.0/CATIAV5/converter/bin/convert.exe")
        let helper = try file("Program Files/Siemens/NX 10.0/NXBIN/crash-helper.exe")
        let system = try file("Program Files/Internet Explorer/iexplore.exe")
        let other = try file("Program Files/My Internet Explorer Tools/main.exe")
        let menu = "ProgramData/Microsoft/Windows/Start Menu/Programs/Siemens/"
        let target = "C:\\Program Files\\Siemens\\NX 10.0\\NXBIN\\ugraf.exe"
        let good = link(target)
        _ = try file(menu+"NX 10.0.lnk",good)
        _ = try file("users/test/Desktop/NX 10.0.lnk",good)
        _ = try file(menu+"NX ANSI.lnk",link(target,unicode:false,local:true))
        _ = try file(menu+"NX arguments.lnk",link(target,args:"-special"))
        _ = try file(menu+"NX workdir.lnk",link(target,work:"C:\\Other"))
        _ = try file(menu+"NX external.lnk",link("Z:\\Users\\test\\private.exe"))
        _ = try file(menu+"NX network.lnk",link("\\\\server\\share\\app.exe"))
        _ = try file(menu+"NX missing.lnk",link("C:\\not-installed.exe"))
        _ = try file(menu+"NX bad.lnk",Data([0,1,2]))
        _ = try file(menu+"System.lnk",link("C:\\Program Files\\Internet Explorer\\iexplore.exe"))
        _ = try file(menu+"Uninstall.lnk",link("C:\\Program Files\\Siemens\\NX 10.0\\NXBIN\\crash-helper.exe"))
        _ = try file("Program Files/not-in-menu.lnk",good)
        try fm.createSymbolicLink(at: drive.appendingPathComponent(menu+"Alias.lnk"), withDestinationURL: drive.appendingPathComponent(menu+"NX 10.0.lnk"))
        let candidates = [cad,tool,helper,system,other]
        let found = InstalledShortcut.scan(driveC: drive, candidates: candidates)
        check(found.map(\.name) == ["NX 10.0", "NX ANSI"], "friendly names; duplicate targets with identical names deduplicated; unsupported links not mislaunched")
        check(found.allSatisfy { $0.executable == cad }, "only existing allowlisted EXE targets")
        check(try Data(contentsOf: drive.appendingPathComponent(menu+"NX 10.0.lnk")) == good, "read-only scan preserves shortcut")
        check(ShellLink.read(good)?.target == target, "UTF16 StringData target")
        check(ShellLink.read(link(target,unicode:false,local:true))?.target == target, "ANSI LocalBasePath target")
        check(ShellLink.read(link(target,args:"--test"))?.arguments == "--test", "arguments parsed rather than silently discarded")
        for count in 0..<good.count { check(ShellLink.read(good.prefix(count)) == nil || count >= good.count-4, "truncated link rejected \(count)") }
        var bad = good;bad[4]=0xff;check(ShellLink.read(bad)==nil,"wrong CLSID rejected")
        check(InstalledShortcut.normalize("..\\NXBIN\\ugraf.exe", relativeTo: "C:\\Program Files\\Siemens\\NX 10.0\\temp") == target,"relative path normalization")
        check(InstalledShortcut.normalize("..\\..\\x.exe",relativeTo:"C:\\a").isEmpty,"C drive escape rejected")
        check(InstalledShortcut.normalize("%USERPROFILE%\\x.exe",relativeTo:"C:\\").isEmpty,"unresolved environment target rejected")
        check(ExecutableTree.systemUtility(system,driveC:drive) && !ExecutableTree.systemUtility(other,driveC:drive),"system utilities exact folder classification")
        let tree = ExecutableTree.roots(candidates,driveC:drive)
        let programFiles = tree.first { $0.url.lastPathComponent == "Program Files" }!
        let siemens = programFiles.children.first { $0.url.lastPathComponent == "Siemens" }!
        check(siemens.children.count==1 && siemens.children[0].url.lastPathComponent=="NX 10.0","vendor disclosure contains folders, not flattened EXEs")
        check(siemens.children[0].children.map { $0.url.lastPathComponent } == ["CATIAV5","NXBIN"],"actual nested installation folders")
        check(siemens.count==3,"descendant EXE counts")
        let search = ExecutableTree.roots(candidates,driveC:drive,query:"nx 10 UGRAF")
        check(search.count==1 && search[0].count==1,"search retains only matching hierarchy")
        check(ExecutableTree.roots(candidates,driveC:drive,query:"missing").isEmpty,"no-match tree")
        let linkedDrive=root.appendingPathComponent("linked_c")
        try fm.createSymbolicLink(at:linkedDrive,withDestinationURL:drive)
        check(InstalledShortcut.scan(driveC:linkedDrive,candidates:candidates).isEmpty,"symlink drive rejected")
        print("installed-shortcuts/tree: \(checks) checks passed")
    }
}
