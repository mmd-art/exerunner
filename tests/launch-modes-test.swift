import Foundation
import Darwin

setbuf(stdout, nil)
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let fm = FileManager.default
func require(_ ok: @autoclosure () throws -> Bool, _ name: String) throws {
    guard try ok() else { throw AppError("FAIL: " + name) }
    print("PASS: " + name)
}
func refused(_ name: String, _ body: () throws -> Void) throws {
    do { try body() } catch { print("PASS: " + name); return }
    throw AppError("FAIL: " + name)
}
let original = Bottle(name: "isolated-original", root: root)
try Paths.ensure(original.driveC)
try Data("registry".utf8).write(to: original.url.appendingPathComponent("system.reg"))
try Data("prepared".utf8).write(to: original.url.appendingPathComponent(".exerunner-isolated-v1"))
try Data("original game bytes".utf8).write(to: original.driveC.appendingPathComponent("game.exe"))
try Data("protected save".utf8).write(to: original.driveC.appendingPathComponent("save.txt"))
let outside = root.appendingPathComponent("outside")
try Paths.ensure(outside)
let canary = outside.appendingPathComponent("canary.txt")
try Data("host canary".utf8).write(to: canary)
try fm.createSymbolicLink(atPath: original.driveC.appendingPathComponent("external").path, withDestinationPath: outside.path)
var protected = LibraryItem(id: "mode-check", name: "Controlled app", kind: .program, bottle: original.name, executable: "C:\\game.exe")
protected.isolated = true
var ordinary = protected; ordinary.isolated = false
ordinary = try LaunchModes.change(ordinary, from: protected, root: root)
let unrestricted = Bottle(name: ordinary.bottle, root: root)
try require(ordinary.bottle != original.name && !ordinary.bottle.hasPrefix("isolated-"), "ordinary launch gets a separate disk")
try require(fm.fileExists(atPath: original.url.appendingPathComponent(".exerunner-isolated-v1").path) && !fm.fileExists(atPath: original.url.appendingPathComponent(".exerunner-unrestricted").path), "protected disk keeps its original marker")
try require(!fm.fileExists(atPath: unrestricted.url.appendingPathComponent(".exerunner-isolated-v1").path) && fm.fileExists(atPath: unrestricted.url.appendingPathComponent(".exerunner-unrestricted").path), "ordinary disk cannot masquerade as isolated")
try require(fm.destinationOfSymbolicLink(atPath: unrestricted.driveC.appendingPathComponent("external").path) == outside.path, "mode copy preserves an external link without traversing it")
try Data("ordinary changed save".utf8).write(to: unrestricted.driveC.appendingPathComponent("save.txt"))
try require(Data(contentsOf: original.driveC.appendingPathComponent("save.txt")) == Data("protected save".utf8), "ordinary changes do not alter the protected copy")
protected = ordinary; protected.isolated = true
protected = try LaunchModes.change(protected, from: ordinary, root: root)
try require(protected.bottle == original.name && (try Data(contentsOf: original.driveC.appendingPathComponent("save.txt"))) == Data("protected save".utf8), "returning to isolation reuses the original disk without merging changes")
var again = protected; again.isolated = false
again = try LaunchModes.change(again, from: protected, root: root)
try require(again.bottle == ordinary.bottle && (try Data(contentsOf: unrestricted.driveC.appendingPathComponent("save.txt"))) == Data("ordinary changed save".utf8), "ordinary mode retains its own changes across toggles")
var external = protected; external.executable = canary.path; external.isolated = false
try refused("external EXE cannot be switched by cloning only its bottle") { _ = try LaunchModes.change(external, from: protected, root: root) }
var steam = protected; steam.steamAppID = 123; steam.isolated = false
try refused("Steam launch cannot silently bypass isolation") { _ = try LaunchModes.change(steam, from: protected, root: root) }
let icon = Data("controlled image".utf8)
let asset = try NativeAssets.write(icon, named: "icon.png", in: original)
try require(Data(contentsOf: asset) == icon, "native icon is written inside the bottle")
try fm.removeItem(at: asset.deletingLastPathComponent())
try fm.createSymbolicLink(atPath: asset.deletingLastPathComponent().path, withDestinationPath: outside.path)
try refused("guest icon-directory symlink cannot redirect a host write") { _ = try NativeAssets.write(Data("escape".utf8), named: "canary.txt", in: original) }
try require(Data(contentsOf: canary) == Data("host canary".utf8), "host canary remains unchanged")
try fm.removeItem(at: asset.deletingLastPathComponent())
try Paths.ensure(asset.deletingLastPathComponent())
try fm.linkItem(at: canary, to: asset)
_ = try NativeAssets.write(icon, named: "icon.png", in: original)
try require(Data(contentsOf: canary) == Data("host canary".utf8), "publishing an icon replaces a hard link without changing its target")
print("PASS: mode switching and hostile native-asset paths")
