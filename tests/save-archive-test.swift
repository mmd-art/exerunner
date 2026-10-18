import Foundation
import IOKit.pwr_mgt

struct AppError: LocalizedError { let message: String; init(_ message: String) { self.message = message }; var errorDescription: String? { message } }
struct LocalizedText: ExpressibleByStringLiteral { var key: String; init(stringLiteral: String) { key = stringLiteral } }
func t(_ value: LocalizedText) -> String { value.key }
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }; checks += 1
}
func rejects(_ name: String, _ body: () throws -> Void) {
    do { try body(); fatalError("Accepted: " + name) } catch { checks += 1 }
}
let fm = FileManager.default
let scratch = ProcessInfo.processInfo.environment["EXERUNNER_WORK_ROOT"]!
let root = URL(fileURLWithPath: scratch).appendingPathComponent(UUID().uuidString)
try fm.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: root) }
func dir(_ name: String) throws -> URL {
    let d = root.appendingPathComponent(name); try fm.createDirectory(at: d, withIntermediateDirectories: true); return d
}
func write(_ text: String, _ url: URL) throws { try Data(text.utf8).write(to: url) }
func content(_ url: URL) -> String { (try? String(contentsOf: url, encoding: .utf8)) ?? "MISSING" }
let original = try dir("original"), exported = try dir("exported"), target = try dir("target"), safety = try dir("safety")
try fm.createDirectory(at: original.appendingPathComponent("slot"), withIntermediateDirectories: true)
try write("progress one", original.appendingPathComponent("slot/one.sav"))
try write("progress two", original.appendingPathComponent("two.sav"))
try write("older target", target.appendingPathComponent("two.sav"))
try write("unrelated", target.appendingPathComponent("keep.sav"))
let archive = try SaveArchive.create(itemID: "game-a", source: original, parent: exported)
let manifest = try SaveArchive.read(archive, itemID: "game-a")
check(manifest.files.count == 2, "manifest files")
check(content(original.appendingPathComponent("two.sav")) == "progress two", "source unchanged")
let plan = try SaveArchive.plan(archive: archive, itemID: "game-a", destination: target)
check(plan.replacing == 1, "preview existing replacements")
check(content(target.appendingPathComponent("two.sav")) == "older target", "preview read only")
let restored = try SaveArchive.restore(plan, safetyParent: safety)
check(restored.files == 2, "restored count")
check(content(target.appendingPathComponent("slot/one.sav")) == "progress one", "nested restored")
check(content(target.appendingPathComponent("two.sav")) == "progress two", "replaced")
check(content(target.appendingPathComponent("keep.sav")) == "unrelated", "unrelated retained")
check(content(restored.safetyCopy.appendingPathComponent("data/two.sav")) == "older target", "mandatory safety data")
let safetyManifest = try SaveArchive.read(restored.safetyCopy, itemID: "game-a")
check(safetyManifest.files.count == 2, "safety verifies")
for path in ["../evil", "/absolute", "a//b", "a/./b", "a/../b", "C:\\evil", "a\0b", ""] {
    check(!SaveArchive.safeRelative(path), "unsafe relative rejected")
}
rejects("wrong game") { _ = try SaveArchive.read(archive, itemID: "game-b") }
rejects("inside source") { _ = try SaveArchive.create(itemID: "a", source: original, parent: original) }
rejects("restore archive into itself") { _ = try SaveArchive.plan(archive: archive, itemID: "game-a", destination: archive) }
let changedPlan = try SaveArchive.plan(archive: archive, itemID: "game-a", destination: target)
try write("changed after preview", target.appendingPathComponent("two.sav"))
rejects("changed destination") { _ = try SaveArchive.restore(changedPlan, safetyParent: safety) }
check(content(target.appendingPathComponent("two.sav")) == "changed after preview", "new data untouched")
let invalidSafetyPlan = try SaveArchive.plan(archive: archive, itemID: "game-a", destination: target)
rejects("safety failure") { _ = try SaveArchive.restore(invalidSafetyPlan, safetyParent: root.appendingPathComponent("missing")) }
check(content(target.appendingPathComponent("two.sav")) == "changed after preview", "safety failure no overwrite")
rejects("nested safety") { _ = try SaveArchive.restore(invalidSafetyPlan, safetyParent: target) }
let empty = try dir("empty")
rejects("empty export") { _ = try SaveArchive.create(itemID: "a", source: empty, parent: exported) }
let emptyPlan = try SaveArchive.plan(archive: archive, itemID: "game-a", destination: empty)
let emptyResult = try SaveArchive.restore(emptyPlan, safetyParent: safety)
let emptyManifest = try SaveArchive.read(emptyResult.safetyCopy, itemID: "game-a")
check(emptyManifest.files.isEmpty, "empty safety recorded")
let linkRoot = root.appendingPathComponent("link")
try fm.createSymbolicLink(at: linkRoot, withDestinationURL: original)
rejects("source root symlink") { _ = try SaveArchive.inventory(linkRoot) }
try fm.createSymbolicLink(at: original.appendingPathComponent("link.sav"), withDestinationURL: target.appendingPathComponent("keep.sav"))
rejects("source child symlink") { _ = try SaveArchive.create(itemID: "a", source: original, parent: exported) }
let executable = try dir("game-install")
try write("executable", executable.appendingPathComponent("game.exe"))
rejects("installation tree") { _ = try SaveArchive.inventory(executable) }
let conflict = try dir("conflict")
try write("file where folder expected", conflict.appendingPathComponent("slot"))
rejects("file-directory conflict") { _ = try SaveArchive.plan(archive: archive, itemID: "game-a", destination: conflict) }
try write("tampered", archive.appendingPathComponent("data/two.sav"))
rejects("archive hash mismatch") { _ = try SaveArchive.read(archive, itemID: "game-a") }
// Restore failure after one write still preserves the complete previous target tree.
let cleanSource = try dir("clean")
try write("first new", cleanSource.appendingPathComponent("a.sav")); try write("second new", cleanSource.appendingPathComponent("b.sav"))
let second = try SaveArchive.create(itemID: "game-a", source: cleanSource, parent: exported)
let partialTarget = try dir("partial-target")
try write("first old", partialTarget.appendingPathComponent("a.sav")); try write("second old", partialTarget.appendingPathComponent("b.sav"))
let partialPlan = try SaveArchive.plan(archive: second, itemID: "game-a", destination: partialTarget)
var failure = ""
do { _ = try SaveArchive.restore(partialPlan, safetyParent: safety, permitWrite: { if $0 == 1 { throw AppError("injected I/O failure") } }) }
catch { failure = error.localizedDescription }
check(failure.contains("ExeRunner-Saves-"), "failure discloses recovery copy")
let safetyCopies = try fm.contentsOfDirectory(at: safety, includingPropertiesForKeys: nil)
check(safetyCopies.contains { content($0.appendingPathComponent("data/b.sav")) == "second old" && content($0.appendingPathComponent("data/a.sav")) == "first old" }, "complete recovery after partial write")
// Tamper the manifest path, not only its payload.
var badManifest = try SaveArchive.read(second, itemID: "game-a")
badManifest.files[0].path = "../escape"
try JSONEncoder().encode(badManifest).write(to: second.appendingPathComponent("manifest.json"))
rejects("manifest traversal") { _ = try SaveArchive.read(second, itemID: "game-a") }
// Alias checks include the merge and existing empty directories.
let aliasSource = try dir("alias-source/Dir")
try write("new", aliasSource.appendingPathComponent("new.sav"))
let aliasBackup = try SaveArchive.create(itemID: "alias", source: aliasSource.deletingLastPathComponent(), parent: exported)
let aliasEmpty = try dir("alias-target/dir")
rejects("empty directory alias preflight") { _ = try SaveArchive.plan(archive: aliasBackup, itemID: "alias", destination: aliasEmpty.deletingLastPathComponent()) }
check(!fm.fileExists(atPath: aliasEmpty.appendingPathComponent("new.sav").path), "alias preview did not write")
try write("keep", aliasEmpty.appendingPathComponent("keep.sav"))
rejects("populated directory alias preflight") { _ = try SaveArchive.plan(archive: aliasBackup, itemID: "alias", destination: aliasEmpty.deletingLastPathComponent()) }
let unsafeParent = root.appendingPathComponent("ancestor-link")
try fm.createSymbolicLink(at: unsafeParent, withDestinationURL: target)
rejects("target ancestor link") { _ = try SaveArchive.plan(archive: aliasBackup, itemID: "alias", destination: unsafeParent) }
let large = try dir("large"), sparse = large.appendingPathComponent("huge.sav")
fm.createFile(atPath: sparse.path, contents: Data())
let handle = try FileHandle(forWritingTo: sparse)
try handle.truncate(atOffset: UInt64(SaveArchive.maximumBytes + 1)); try handle.close()
rejects("oversize sparse save") { _ = try SaveArchive.inventory(large) }
let malformed = try SaveArchive.create(itemID: "format", source: cleanSource, parent: exported)
var invalid = try SaveArchive.read(malformed, itemID: "format")
invalid.format = 99
try JSONEncoder().encode(invalid).write(to: malformed.appendingPathComponent("manifest.json"))
rejects("unsupported format") { _ = try SaveArchive.read(malformed, itemID: "format") }
invalid.format = 1; invalid.files.append(invalid.files[0])
try JSONEncoder().encode(invalid).write(to: malformed.appendingPathComponent("manifest.json"))
rejects("duplicate manifest file") { _ = try SaveArchive.read(malformed, itemID: "format") }
let sharedExportParent = try dir("shared-export")
let childSaves = sharedExportParent.appendingPathComponent("Saves")
try fm.createDirectory(at: childSaves, withIntermediateDirectories: false)
try write("child progress", childSaves.appendingPathComponent("slot.sav"))
let siblingArchive = try SaveArchive.create(itemID: "shared", source: childSaves, parent: sharedExportParent)
check(content(childSaves.appendingPathComponent("slot.sav")) == "child progress", "ancestor export makes a sibling without modifying saves")
let siblingTarget = try dir("sibling-target")
let siblingPlan = try SaveArchive.plan(archive: siblingArchive, itemID: "shared", destination: siblingTarget)
let siblingResult = try SaveArchive.restore(siblingPlan, safetyParent: sharedExportParent)
check(siblingResult.safetyCopy.deletingLastPathComponent() == siblingArchive.deletingLastPathComponent(), "backup and safety snapshots may be siblings")
// Assertion lifecycle: launcher-only/launching lists are never fed as observed games.
var acquired = 0, released: [IOPMAssertionID] = []
var awake: KeepAwake? = KeepAwake(acquire: { acquired += 1; return 7 }, release: { released.append($0) })
check(awake!.update(enabled: true, activeGameIDs: []) == false, "no game no assertion")
check(awake!.update(enabled: true, activeGameIDs: ["game-a"]), "game gets assertion")
_ = awake!.update(enabled: true, activeGameIDs: ["game-a", "game-b"])
_ = awake!.update(enabled: true, activeGameIDs: ["game-b"])
check(acquired == 1 && released.isEmpty, "overlap shares assertion")
check(!awake!.update(enabled: false, activeGameIDs: ["game-b"]), "toggle off releases")
check(released == [7], "single release")
_ = awake!.update(enabled: true, activeGameIDs: ["game-a"])
_ = awake!.update(enabled: true, activeGameIDs: [])
check(released.count == 2, "crash or Stop releases after process disappears")
_ = awake!.update(enabled: true, activeGameIDs: ["game-a"]); awake = nil
check(released.count == 3, "owner deinit releases")
let unavailable = KeepAwake(acquire: { nil }, release: { _ in fatalError("invalid release") })
check(!unavailable.update(enabled: true, activeGameIDs: ["a"]), "unavailable assertion safe")
rejects("portable case collision") { try SaveArchive.validateAliases([.init(path: "A.sav", bytes: 1, sha256: "a"), .init(path: "a.sav", bytes: 1, sha256: "b")]) }
rejects("directory case alias") { try SaveArchive.validateAliases([.init(path: "Dir/a.sav", bytes: 1, sha256: "a"), .init(path: "dir/b.sav", bytes: 1, sha256: "b")]) }
let startedAt = Date()
var observation = GameObservationWait(now: startedAt)
check(!observation.finished(observed: false, now: startedAt.addingTimeInterval(1)), "Steam helper return is not game exit")
check(!observation.finished(observed: true, now: startedAt.addingTimeInterval(5)), "game observed")
check(!observation.finished(observed: true, now: startedAt.addingTimeInterval(300)), "game continues past startup deadline")
check(observation.finished(observed: false, now: startedAt.addingTimeInterval(301)), "game exit ends shortcut wait")
var timeout = GameObservationWait(now: startedAt)
check(timeout.finished(observed: false, now: startedAt.addingTimeInterval(121)), "failed game start bounded")
let operations = await MainActor.run { SaveOperationTracker() }
let releaseWrite = DispatchSemaphore(value: 0)
let operation = Task { try await operations.perform { releaseWrite.wait(); return "restored" } }
while operations.count == 0 { try await Task.sleep(for: .milliseconds(5)) }
let finishing = Task { await operations.finish() }
while !operations.isClosing { try await Task.sleep(for: .milliseconds(5)) }
let drainingCount = operations.count
check(drainingCount == 1, "shutdown drains suspended restore")
do { _ = try await operations.perform { "must not start" }; fatalError("start during shutdown") } catch { checks += 1 }
releaseWrite.signal()
let value = try await operation.value
await finishing.value
check(value == "restored", "restore completed before shutdown")
let remainingCount = operations.count
check(remainingCount == 0, "restore deregistered")
if CommandLine.arguments.contains("--native") {
    var nativeID: IOPMAssertionID = 0
    let native = KeepAwake(acquire: {
        let code = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn), "ExeRunner isolated keep-awake control" as CFString, &nativeID)
        return code == kIOReturnSuccess ? nativeID : nil
    }, release: { _ = IOPMAssertionRelease($0) })
    check(native.update(enabled: true, activeGameIDs: ["synthetic-game"]), "native IOPM acquisition")
    check(IOPMAssertionCopyProperties(nativeID) != nil, "native assertion exists")
    check(!native.update(enabled: true, activeGameIDs: []), "native IOPM release")
    check(IOPMAssertionCopyProperties(nativeID) == nil, "native assertion removed")
}
print("save archive and keep-awake: \(checks) checks passed")
