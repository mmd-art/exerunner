import Foundation
let prefix = URL(fileURLWithPath: CommandLine.arguments[2])
let engine = Engine(root: URL(fileURLWithPath: CommandLine.arguments[3]))
if CommandLine.arguments[1] == "profile" {
    try IsolatedWine.profile(prefix: prefix, engine: engine).write(toFile: CommandLine.arguments[4], atomically: true, encoding: .utf8)
} else {
    Task {
        let bottle = Bottle(name: prefix.lastPathComponent, root: prefix.deletingLastPathComponent())
        var item = LibraryItem(id: "isolation-probe", name: "Isolation probe", kind: .program, bottle: bottle.name,
                               executable: "C:\\isolation-probe.exe", arguments: Array(CommandLine.arguments.dropFirst(4)))
        item.isolated = true
        do {
            let status = try await IsolatedWine.run(item, bottle: bottle, engine: engine, log: prefix.appendingPathComponent("probe.log"))
            let text = (try? String(contentsOf: prefix.appendingPathComponent("probe.log"), encoding: .utf8)) ?? ""
            print(text)
            print("ISOLATED_INTEGRATION_STATUS=\(status)")
            exit(status)
        } catch { print(error); exit(1) }
    }
    dispatchMain()
}
