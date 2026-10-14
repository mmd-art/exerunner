import Foundation

let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
let owned = root.appendingPathComponent("owned").path
let foreign = root.appendingPathComponent("foreign").path
func sleeper(_ prefix: String) -> Process {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sleep")
    p.arguments = ["30"]
    p.environment = ["WINEPREFIX": prefix]
    return p
}
let mine = sleeper(owned), other = sleeper(foreign)
try PrefixLaunchGate.start(mine)
try PrefixLaunchGate.start(other)
PrefixLaunchGate.close([owned])
mine.waitUntilExit()
assert(!mine.isRunning, "owned process survived")
assert(other.isRunning, "foreign prefix was stopped")
let late = sleeper(owned)
do { try PrefixLaunchGate.start(late); fatalError("late restart permitted") }
catch is CancellationError { }
assert(!late.isRunning)
PrefixLaunchGate.close([owned])
assert(other.isRunning, "repeat close touched foreign prefix")
other.terminate(); other.waitUntilExit()
print("PASS: owned process stopped, late restart rejected, foreign prefix preserved, repeat close safe")
