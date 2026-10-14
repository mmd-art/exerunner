import Foundation
let root = FileManager.default.temporaryDirectory.appendingPathComponent("exerunner-guard-" + UUID().uuidString)
defer { try? FileManager.default.removeItem(at: root) }
let prefix = root.appendingPathComponent("isolated-guard")
try Paths.ensure(prefix)
try "marker".write(to: prefix.appendingPathComponent(".exerunner-isolated-v1"), atomically: true, encoding: .utf8)
let foreign = root.appendingPathComponent("host-synthetic")
try Paths.ensure(foreign)
try FileManager.default.createSymbolicLink(at: prefix.appendingPathComponent(".isolation"), withDestinationURL: foreign)
let engine = Engine(root: URL(fileURLWithPath: "/Applications/ExeRunner.app/Contents/Resources/engine"))
let bottle = Bottle(name: "isolated-guard", root: root)
do { _ = try IsolatedWine.environment(bottle: bottle, engine: engine); fatalError("FAIL symlink accepted") }
catch { print("PASS host preparation refuses symlink: \(error)") }
precondition(!FileManager.default.fileExists(atPath: foreign.appendingPathComponent("home").path))
let env = WineEnvironment.make(engine: engine, prefix: prefix)
precondition(env["EXERUNNER_SANDBOX_PROFILE"] == "/nonexistent/exerunner-isolation-refused.sb")
do { _ = try WineProcess.start(engine: engine, arguments: ["cmd", "/c", "echo UNSAFE"], environment: env, log: root.appendingPathComponent("log")) { _ in }; fatalError("FAIL unsafe fallback") }
catch { print("PASS invalid profile refuses process creation: \(error)") }
