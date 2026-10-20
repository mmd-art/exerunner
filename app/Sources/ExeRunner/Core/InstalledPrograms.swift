import Foundation

/// Read-only discovery. Importing an installed EXE never runs Wine or changes a prefix.
enum InstalledPrograms {
    static func environments(root: URL) -> [String] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let values = try? root.resourceValues(forKeys: keys),
              values.isDirectory == true, values.isSymbolicLink != true else { return [] }
        return ((try? FileManager.default.contentsOfDirectory(at: root,
            includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])) ?? [])
            .filter { url in
                guard let value = try? url.resourceValues(forKeys: keys),
                      value.isDirectory == true, value.isSymbolicLink != true else { return false }
                let registry = url.appendingPathComponent("system.reg")
                let drive = url.appendingPathComponent("drive_c")
                return FileManager.default.fileExists(atPath: registry.path)
                    && (try? drive.resourceValues(forKeys: keys).isDirectory) == true
                    && (try? drive.resourceValues(forKeys: keys).isSymbolicLink) != true
            }.map(\.lastPathComponent).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static func executables(root: URL, environment: String) -> [URL] {
        // Revalidate selection, including removal while a sheet was open; never create a prefix.
        guard environments(root: root).contains(environment) else { return [] }
        return ExecutableDiscovery.scan(driveC: root.appendingPathComponent(environment).appendingPathComponent("drive_c"))
    }
}
