import Foundation
let engine = Engine(root: URL(fileURLWithPath: CommandLine.arguments[1]))
let prefix = URL(fileURLWithPath: CommandLine.arguments[2])
let bottle = Bottle(name: prefix.lastPathComponent, root: prefix.deletingLastPathComponent())
let env = try IsolatedWine.environment(bottle: bottle, engine: engine)
let foreign = Process()
foreign.executableURL = URL(fileURLWithPath: "/bin/sleep")
foreign.arguments = ["30"]
foreign.environment = ["WINEPREFIX": "/private/tmp/foreign-exerunner-stop-control"]
try foreign.run()
let otherWine = Set(WineProcesses.list(includeServers: true).filter { $0.prefix != bottle.prefixPath }.map(\.pid))
let process = try WineProcess.start(engine: engine, arguments: ["C:\\stop-probe.exe"], environment: env, log: URL(fileURLWithPath: "/private/tmp/exerunner-isolated-stop-probe.log")) { _ in }
Task {
    try? await Task.sleep(for: .seconds(3))
    precondition(WineProcesses.list().contains { $0.prefix == bottle.prefixPath }, "test program never started")
    await BottleManager.stop(bottle, engine: engine)
    try? await Task.sleep(for: .seconds(1))
    precondition(!process.isRunning, "isolated process survived")
    precondition(WineProcesses.list(includeServers: true).filter { $0.prefix == bottle.prefixPath }.isEmpty, "isolated server survived")
    precondition(foreign.isRunning, "foreign control killed")
    let after = Set(WineProcesses.list(includeServers: true).map(\.pid))
    precondition(otherWine.isSubset(of: after), "foreign Wine process stopped")
    foreign.terminate(); foreign.waitUntilExit()
    print("PASS isolated client and server stopped; foreign control and Wine preserved")
    exit(0)
}
dispatchMain()
