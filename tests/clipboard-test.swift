import AppKit
import Foundation

let work = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let engine = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let board = NSPasteboard.general
// Retain all existing representations in memory; do not print or save their contents.
let original = (board.pasteboardItems ?? []).map { item in
    Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
}
let incoming = "ExeRunner \(UUID().uuidString) · 日本語 · Кириллица"
let outgoing = "ExeRunner \(UUID().uuidString) · MIDI · Ω"
func restore() {
    // Preserve anything the owner copied while this short check was running.
    guard let current = board.string(forType: .string), current == incoming || current == outgoing else { return }
    board.clearContents()
    let items = original.map { values in
        let item = NSPasteboardItem()
        for (type, data) in values { item.setData(data, forType: type) }
        return item
    }
    if !items.isEmpty { board.writeObjects(items) }
}
defer { restore() }
board.clearContents(); board.setString(incoming, forType: .string)
var environment = ProcessInfo.processInfo.environment.filter { ["HOME","USER","LOGNAME","SHELL","TMPDIR","LANG","TERM","PATH"].contains($0.key) || $0.key.hasPrefix("LC_") }
environment["WINEPREFIX"] = work.appendingPathComponent("prefix").path
// Use this already initialized test-owned prefix. No owner bottle is opened.
environment["WINEDEBUG"] = "-all"
environment["DYLD_FALLBACK_LIBRARY_PATH"] = engine.appendingPathComponent("lib").path + ":/usr/lib"
let process = Process(), pipe = Pipe()
process.executableURL = engine.appendingPathComponent("bin/wine")
process.arguments = [work.appendingPathComponent("clipboard-probe.exe").path, incoming, outgoing]
process.environment = environment
process.standardInput = FileHandle.nullDevice
process.standardOutput = pipe; process.standardError = pipe
try process.run()
let deadline = Date().addingTimeInterval(30)
while process.isRunning, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
if process.isRunning { process.terminate(); throw NSError(domain: "clipboard timed out", code: 1) }
process.waitUntilExit()
let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
guard process.terminationStatus == 0 && output.contains("PASS:") else { throw NSError(domain: "Windows clipboard control failed: " + output, code: 1) }
for _ in 0..<20 where board.string(forType: .string) != outgoing { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
guard board.string(forType: .string) == outgoing else { throw NSError(domain: "Windows-to-Mac Unicode clipboard failed", code: 1) }
restore()
let restored = (board.pasteboardItems ?? []).map { item in
    Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
}
guard restored == original else { throw NSError(domain: "Clipboard restoration changed concurrently", code: 1) }
print("PASS: Unicode clipboard in both directions; previous clipboard restored")
