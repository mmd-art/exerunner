// winlist: list on-screen windows whose owner name matches a substring, with their window IDs,
// so a single app window can be captured with `screencapture -l <id>` (never the whole screen).
//
// build: swiftc -O -o winlist winlist.swift
// run:   ./winlist steam          windows on the current Space
//        ./winlist --all steam    windows on every Space, including hidden ones
import CoreGraphics
import Foundation

var args = Array(CommandLine.arguments.dropFirst())
let all = args.first == "--all"
if all { args.removeFirst() }
let needle = (args.first ?? "wine").lowercased()
let options: CGWindowListOption = all ? [.optionAll, .excludeDesktopElements]
                                      : [.optionOnScreenOnly, .excludeDesktopElements]
guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
    exit(1)
}
for w in windows {
    let owner = (w[kCGWindowOwnerName as String] as? String) ?? ""
    // Foundation's contains("") is false, so an empty filter has to mean "everything" explicitly
    guard needle.isEmpty || owner.lowercased().contains(needle) else { continue }
    let id = w[kCGWindowNumber as String] as? Int ?? 0
    let pid = w[kCGWindowOwnerPID as String] as? Int ?? 0
    let name = (w[kCGWindowName as String] as? String) ?? ""
    let layer = w[kCGWindowLayer as String] as? Int ?? 0
    let b = w[kCGWindowBounds as String] as? [String: Double] ?? [:]
    print("\(id)\tpid \(pid)\tlayer \(layer)\t\(Int(b["Width"] ?? 0))x\(Int(b["Height"] ?? 0))\t\(owner)\t\(name)")
}
