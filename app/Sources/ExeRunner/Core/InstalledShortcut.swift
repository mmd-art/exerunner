import Foundation

/// Direct EXE shortcuts only. No Shell execution, COM, network paths or external drive access.
struct InstalledShortcut: Identifiable {
    let name: String
    let executable: URL
    let shortcut: URL
    var id: String { shortcut.path }

    static func scan(driveC: URL, candidates: [URL]) -> [InstalledShortcut] {
        let fm = FileManager.default
        let base = driveC.standardizedFileURL
        guard (try? base.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false else { return [] }
        let known = Dictionary(candidates.map { (ExecutableDiscovery.path($0, driveC: base).lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let walker = fm.enumerator(at: base, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else { return [] }
        var result: [InstalledShortcut] = []
        for case let file as URL in walker {
            guard let v = try? file.resourceValues(forKeys: keys), v.isSymbolicLink != true else { continue }
            if v.isDirectory == true {
                if file.deletingLastPathComponent().standardizedFileURL == base,
                   !["users", "programdata"].contains(file.lastPathComponent.lowercased()) { walker.skipDescendants() }
                continue
            }
            let path = ExecutableDiscovery.path(file, driveC: base).lowercased()
            guard file.pathExtension.lowercased() == "lnk", v.isRegularFile == true,
                  (v.fileSize ?? Int.max) <= 1_048_576,
                  path.contains("\\start menu\\programs\\") || path.contains("\\desktop\\"),
                  let data = try? Data(contentsOf: file), let link = ShellLink.read(data),
                  link.arguments.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let windowsParent = ExecutableDiscovery.path(file.deletingLastPathComponent(), driveC: base)
            let target = normalize(link.target, relativeTo: windowsParent)
            guard let exe = known[target.lowercased()],
                  !ExecutableTree.systemUtility(exe, driveC: base), !ExecutableDiscovery.additional(exe),
                  exe.resolvingSymlinksInPath().path.hasPrefix(base.resolvingSymlinksInPath().path + "/") else { continue }
            // An EXE import cannot preserve a distinct shortcut working directory yet.
            if !link.workingDirectory.isEmpty,
               normalize(link.workingDirectory, relativeTo: windowsParent).lowercased() != ExecutableDiscovery.path(exe.deletingLastPathComponent(), driveC: base).lowercased() { continue }
            result.append(InstalledShortcut(name: file.deletingPathExtension().lastPathComponent, executable: exe, shortcut: file))
        }
        // Public/user Start Menu and Desktop often contain copies of the same shortcut.
        var seen = Set<String>()
        return result.sorted { $0.shortcut.path.localizedStandardCompare($1.shortcut.path) == .orderedAscending }
            .filter { seen.insert($0.name.lowercased() + "\n" + $0.executable.path.lowercased()).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func normalize(_ value: String, relativeTo parent: String) -> String {
        let path = value.replacingOccurrences(of: "/", with: "\\")
        guard !path.hasPrefix("\\\\"), !path.contains("%") else { return "" }
        let absolute = path.count >= 3 && path.dropFirst().hasPrefix(":\\")
        let joined = absolute ? path : parent + "\\" + path
        guard joined.lowercased().hasPrefix("c:\\") else { return "" }
        var parts: [String] = []
        for part in joined.dropFirst(3).split(separator: "\\") {
            if part == ".." { guard !parts.isEmpty else { return "" }; parts.removeLast() }
            else if part != "." { parts.append(String(part)) }
        }
        return "C:\\" + parts.joined(separator: "\\")
    }
}

/// Bounded subset of MS-SHLLINK LinkInfo/StringData. Unsupported/invalid links stay in All EXEs.
/// https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-shllink/6813269d-0cc8-4be2-933f-e96e8e3412dc
struct ShellLink {
    let target: String
    let arguments: String
    let workingDirectory: String

    static func read(_ data: Data) -> ShellLink? {
        let b = [UInt8](data)
        func number(_ offset: Int, _ width: Int) -> Int? {
            guard offset >= 0, offset <= b.count - width else { return nil }
            return (0..<width).reduce(0) { $0 | (Int(b[offset + $1]) << ($1 * 8)) }
        }
        func text(_ start: Int, limit: Int, unicode: Bool) -> String? {
            guard start >= 0, start < limit, limit <= b.count else { return nil }
            let step = unicode ? 2 : 1
            var end = start
            while end + step <= limit {
                if b[end] == 0 && (!unicode || b[end + 1] == 0) {
                    return String(data: Data(b[start..<end]), encoding: unicode ? .utf16LittleEndian : .windowsCP1252)
                }
                end += step
            }
            return nil
        }
        let clsid: [UInt8] = [1,0x14,2,0,0,0,0,0,0xc0,0,0,0,0,0,0,0x46]
        guard b.count >= 76, b.count <= 1_048_576, number(0,4) == 76, Array(b[4..<20]) == clsid,
              let flags = number(20,4) else { return nil }
        var cursor = 76
        if flags & 1 != 0 {
            guard let size = number(cursor,2), cursor + 2 + size <= b.count else { return nil }
            cursor += 2 + size
        }
        var target = ""
        if flags & 2 != 0 {
            let start = cursor
            guard let size = number(start,4), let header = number(start+4,4), size >= 28,
                  header >= 28, header <= size, size <= b.count - start,
                  let localFlags = number(start+8,4) else { return nil }
            if localFlags & 1 != 0 {
                let unicode = header >= 36 && (number(start+28,4) ?? 0) != 0
                guard let offset = number(start + (unicode ? 28 : 16),4), offset >= header,
                      let local = text(start+offset, limit: start+size, unicode: unicode),
                      let suffixOffset = number(start + (unicode ? 32 : 24),4), suffixOffset >= header,
                      let suffix = text(start+suffixOffset, limit: start+size, unicode: unicode) else { return nil }
                target = local
                if !suffix.isEmpty && !local.lowercased().hasSuffix(suffix.lowercased()) {
                    target += (local.hasSuffix("\\") || suffix.hasPrefix("\\") ? "" : "\\") + suffix
                }
            }
            cursor += size
        }
        var strings: [Int: String] = [:]
        for bit in [4,8,16,32,64] where flags & bit != 0 {
            guard let count = number(cursor,2) else { return nil }
            cursor += 2
            let size = count * (flags & 128 != 0 ? 2 : 1)
            guard size <= b.count - cursor,
                  let value = String(data: Data(b[cursor..<cursor+size]), encoding: flags & 128 != 0 ? .utf16LittleEndian : .windowsCP1252) else { return nil }
            strings[bit] = value; cursor += size
        }
        if target.isEmpty { target = strings[8] ?? "" }
        guard !target.isEmpty else { return nil }
        return ShellLink(target: target, arguments: strings[32] ?? "", workingDirectory: strings[16] ?? "")
    }
}
