import Foundation
struct AppError: LocalizedError { let message: String; init(_ message: String) { self.message = message }; var errorDescription: String? { message } }
func t(_ s: String) -> String { s }
enum Paths { static var compat: URL? { URL(fileURLWithPath: ProcessInfo.processInfo.environment["TEST_COMPAT"]!) } }
@main struct Tests {
 static func main() throws {
  let fm = FileManager.default, base = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TMPDIR"]!).appendingPathComponent("removal-fixture")
  try fm.createDirectory(at: base, withIntermediateDirectories: true)
  let c = base.appendingPathComponent("drive_c"), folder = c.appendingPathComponent("Games/Example"), exe = folder.appendingPathComponent("bin/game.exe")
  try fm.createDirectory(at: exe.deletingLastPathComponent(), withIntermediateDirectories: true)
  try Data([1]).write(to: exe)
  var checks = 0
  func reject(_ label: String, _ action: () throws -> Void) { do { try action(); fatalError("accepted: \(label)") } catch { checks += 1 } }
  let plan = try GameRemoval.plan(folder: folder, driveC: c, executable: exe, otherExecutables: [])
  try GameRemoval.validate(plan); checks += 1
  reject("C root") { _ = try GameRemoval.plan(folder: c, driveC: c, executable: exe, otherExecutables: []) }
  reject("all Games") { _ = try GameRemoval.plan(folder: folder.deletingLastPathComponent(), driveC: c, executable: exe, otherExecutables: []) }
  reject("shared card") { _ = try GameRemoval.plan(folder: folder, driveC: c, executable: exe, otherExecutables: [exe]) }
  reject("external folder") { _ = try GameRemoval.plan(folder: base, driveC: c, executable: exe, otherExecutables: []) }
  let user = c.appendingPathComponent("users/me/Example")
  try fm.createDirectory(at: user, withIntermediateDirectories: true)
  reject("user data") { _ = try GameRemoval.plan(folder: user, driveC: c, executable: exe, otherExecutables: []) }
  let link = c.appendingPathComponent("Games/Alias")
  try fm.createSymbolicLink(at: link, withDestinationURL: folder)
  reject("symlink") { _ = try GameRemoval.plan(folder: link, driveC: c, executable: exe, otherExecutables: []) }
  let bin = exe.deletingLastPathComponent()
  try fm.moveItem(at: folder, to: c.appendingPathComponent("Games/Moved"))
  try fm.createDirectory(at: bin, withIntermediateDirectories: true); try Data([2]).write(to: exe)
  reject("changed identity") { try GameRemoval.validate(plan) }
  let classifier = CrashClassifier.shared
  let helper = #"0220:err:module:import_dll Library SDL2.dll (which is needed by L"C:\\Program Files (x86)\\Steam\\bin\\gldriverquery.exe") not found"#
  let optional = classifier.classify(helper, exitStatus: 0, steamClient: true)
  assert(optional.primary?.pattern.id == "steam-gpu-probe" && optional.primary?.pattern.severity == .warning); checks += 1
  assert(classifier.classify(helper, exitStatus: nil).primary?.pattern.severity == .error); checks += 1
  let main = helper.replacingOccurrences(of: "bin\\\\gldriverquery.exe", with: "Steam.exe")
  assert(classifier.classify(main, exitStatus: nil, steamClient: true).primary?.pattern.severity == .error); checks += 1
  assert(classifier.classify(helper, exitStatus: 9, steamClient: true).primary?.pattern.id == "process-exit"); checks += 1
  let unrelated = helper.replacingOccurrences(of: "Steam\\\\bin", with: "OtherApp\\\\bin")
  assert(classifier.classify(unrelated, exitStatus: nil, steamClient: true).primary?.pattern.severity == .error); checks += 1
  var intents = StopIntent()
  intents.mark("steam"); intents.mark("game")
  assert(intents.ignoresExit("steam")); checks += 1
  assert(intents.ignoresExit("steam")); checks += 1 // duplicate callback must also be ignored
  intents.observeLaunch("game", duringStop: true)
  assert(intents.ignoresExit("game")); checks += 1 // shutdown helper is not a new session
  intents.observeLaunch("game", duringStop: false)
  assert(!intents.ignoresExit("game")); checks += 1 // fresh Steam UI launch may report real crashes
  assert(intents.ignoresExit("steam")); checks += 1 // does not reset unrelated client
  intents.begin("steam")
  assert(!intents.ignoresExit("steam")); checks += 1
  print("Removal/Steam: \(checks) safety and diagnostic regression checks passed")
 }
}
