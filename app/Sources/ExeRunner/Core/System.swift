import Foundation

enum Rosetta {
    static func isInstalled() async -> Bool {
        await Shell.run("/usr/bin/arch", ["-x86_64", "/usr/bin/true"]).status == 0
    }

    /// macOS asks for an administrator password.
    static func install() async -> CommandResult {
        let script = "do shell script \"/usr/sbin/softwareupdate --install-rosetta --agree-to-license\" with administrator privileges"
        return await Shell.run("/usr/bin/osascript", ["-e", script])
    }
}

struct SystemInfo: Equatable {
    var chip: String
    var isAppleSilicon: Bool
    var macOS: String
    var macOSMajor: Int
    var memoryGB: Int
    var freeDiskGB: Int

    var supported: Bool { macOSMajor >= 15 }

    static func current() -> SystemInfo {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let values = try? Paths.home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let free = values?.volumeAvailableCapacityForImportantUsage ?? 0
        return SystemInfo(
            chip: sysctlString("machdep.cpu.brand_string") ?? "?",
            isAppleSilicon: HostArchitecture.isAppleSilicon,
            macOS: "\(version.majorVersion).\(version.minorVersion)",
            macOSMajor: version.majorVersion,
            memoryGB: Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824),
            freeDiskGB: Int(free / 1_000_000_000)
        )
    }
}

private func sysctlString(_ name: String) -> String? {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
    var buffer = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
    return String(cString: buffer)
}
