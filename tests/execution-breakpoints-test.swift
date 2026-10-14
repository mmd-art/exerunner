import Foundation

@main
enum CompatibilityCheck {
    static func main() async throws {
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--quote" {
            print(ExecutionBreakpointCompatibility.commandLine([CommandLine.arguments[2], "", "hello world", "quote\"inside", "C:\\Games\\trailing\\", "Юникод 😀", "mix\\\\\"end\\"]))
            return
        }
        let work = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let unknown = work.appendingPathComponent("FCPrimal.exe")
        try Data("different executable revision".utf8).write(to: unknown)
        let env = ["WINEPREFIX": "/own/prefix", "MTL_HUD_ENABLED": "1"]
        let exe = "C:\\Games\\Far Cry Primal\\bin\\FCPrimal.exe"
        let args = ["-windowed", "argument with spaces"]
        var checks = 0
        func unchanged(_ plan: ExecutionBreakpointCompatibility.Plan) {
            precondition(!plan.applied && plan.arguments == [exe] + args && plan.environment == env)
            checks += 1
        }
        unchanged(try await ExecutionBreakpointCompatibility.plan(executable: exe, arguments: args, file: unknown,
            isolated: false, environment: env, compatibilityDirectory: nil, onAppleSilicon: false))
        unchanged(try await ExecutionBreakpointCompatibility.plan(executable: exe, arguments: args, file: unknown,
            isolated: true, environment: env, compatibilityDirectory: nil, onAppleSilicon: true))
        unchanged(try await ExecutionBreakpointCompatibility.plan(executable: exe, arguments: args, file: nil,
            isolated: false, environment: env, compatibilityDirectory: nil, onAppleSilicon: true))
        unchanged(try await ExecutionBreakpointCompatibility.plan(executable: exe, arguments: args, file: unknown,
            isolated: false, environment: env, compatibilityDirectory: nil, onAppleSilicon: true))
        let wot = "C:\\Games\\World_of_Tanks_EU\\win64\\WorldOfTanks.exe"
        let normal = try await ExecutionBreakpointCompatibility.plan(executable: wot, arguments: args, file: unknown,
            isolated: false, environment: env, compatibilityDirectory: nil, onAppleSilicon: true)
        precondition(!normal.applied && normal.arguments == [wot] + args && normal.environment == env)
        checks += 1
        if CommandLine.arguments.count == 3 {
            // Optional integration fixture: inspect the owner's supported EXE read-only.
            let file = URL(fileURLWithPath: CommandLine.arguments[1])
            let compat = URL(fileURLWithPath: CommandLine.arguments[2])
            let plan = try await ExecutionBreakpointCompatibility.plan(executable: exe, arguments: args, file: file,
                isolated: false, environment: env, compatibilityDirectory: compat, onAppleSilicon: true)
            precondition(plan.applied && plan.arguments.count == 1)
            precondition(plan.environment["WINEPREFIX"] == env["WINEPREFIX"] && plan.environment["MTL_HUD_ENABLED"] == "1")
            precondition(plan.environment["EXERUNNER_COMPAT_TARGET"] == exe)
            precondition(plan.environment["EXERUNNER_COMPAT_COMMAND_LINE"] == ExecutionBreakpointCompatibility.commandLine([exe] + args))
            checks += 1
            do {
                _ = try await ExecutionBreakpointCompatibility.plan(executable: exe, arguments: args, file: file,
                    isolated: false, environment: env, compatibilityDirectory: work, onAppleSilicon: true)
                fatalError("Supported revision must report missing compatibility assets")
            } catch is AppError { checks += 1 }
        }
        print("execution-breakpoint launch selection: \(checks) checks passed")
    }
}
