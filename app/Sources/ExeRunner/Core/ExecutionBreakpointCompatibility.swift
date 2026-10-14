import Foundation

/// A measured workaround for one executable revision on Apple Silicon.
/// Other programs keep their original command, environment and Wine engine.
enum ExecutionBreakpointCompatibility {
    static let supportedSHA256 = "027ab9613ae28224b8e743b71d9537d624a27eff54cd76998b1376d07cfaec14"

    struct Plan {
        var arguments: [String]
        var environment: [String: String]
        var applied: Bool
    }

    static func commandLine(_ arguments: [String]) -> String {
        arguments.map { value in
            // Windows CommandLineToArgvW/CRT quoting: double runs of backslashes
            // before quotes and before the closing quote; preserve empty args.
            var result = "\"", slashes = 0
            for character in value {
                if character == "\\" { slashes += 1; continue }
                if character == "\"" {
                    result += String(repeating: "\\", count: slashes * 2 + 1) + "\""
                } else {
                    result += String(repeating: "\\", count: slashes) + String(character)
                }
                slashes = 0
            }
            result += String(repeating: "\\", count: slashes * 2) + "\""
            return result
        }.joined(separator: " ")
    }

    static var appleSilicon: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    static func plan(executable: String, arguments: [String], file: URL?, isolated: Bool,
                     environment: [String: String], compatibilityDirectory: URL?,
                     onAppleSilicon: Bool = appleSilicon) async throws -> Plan {
        let unchanged = Plan(arguments: [executable] + arguments, environment: environment, applied: false)
        let basename = executable.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last?.lowercased()
        guard onAppleSilicon, !isolated, basename == "fcprimal.exe", let file else { return unchanged }
        let digest = try await Task.detached { try sha256Hex(of: file) }.value
        guard digest == supportedSHA256 else { return unchanged }
        guard let folder = compatibilityDirectory?.appendingPathComponent("windows", isDirectory: true) else {
            throw AppError("Far Cry Primal: missing execution-breakpoint compatibility files")
        }
        let loader = folder.appendingPathComponent("compat-launcher.exe")
        let adapter = folder.appendingPathComponent("execution-breakpoints.dll")
        for resource in [loader, adapter] {
            guard FileManager.default.isReadableFile(atPath: resource.path) else {
                throw AppError("Far Cry Primal: missing compatibility resource \(resource.lastPathComponent)")
            }
        }
        let windowsPath: (URL) -> String = { "Z:" + $0.path.replacingOccurrences(of: "/", with: "\\") }
        var env = environment
        env["EXERUNNER_COMPAT_TARGET"] = executable
        env["EXERUNNER_COMPAT_COMMAND_LINE"] = commandLine([executable] + arguments)
        env["EXERUNNER_COMPAT_DLL"] = windowsPath(adapter)
        return Plan(arguments: [windowsPath(loader)], environment: env, applied: true)
    }
}
