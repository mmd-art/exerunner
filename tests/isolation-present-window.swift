import Foundation
import AppKit
import CoreGraphics
import ImageIO
import Darwin

func canonical(_ path: String) -> String {
    guard let value = realpath(path, nil) else { return path }
    defer { free(value) }
    return String(cString: value)
}

let args = CommandLine.arguments
if args[1] == "stop" {
    let prefix = canonical(args[2])
    let owned = WineProcesses.list(includeServers: true).filter { canonical($0.prefix) == prefix }
    WineProcesses.kill(owned)
    print("STOPPED_OWN_PROBE_PROCESSES=\(owned.count)")
    exit(0)
}
if args[1] == "window" || args[1] == "onscreen" {
    let prefix = canonical(args[2])
    let pids = Set(WineProcesses.list().filter { canonical($0.prefix) == prefix }.map { $0.pid })
    let scope: CGWindowListOption = args[1] == "onscreen" ? [.optionOnScreenOnly, .excludeDesktopElements] : [.optionAll, .excludeDesktopElements]
    let windows = CGWindowListCopyWindowInfo(scope, kCGNullWindowID) as? [[String: Any]] ?? []
    for w in windows {
        let pid = w[kCGWindowOwnerPID as String] as? Int32 ?? 0
        let title = w[kCGWindowName as String] as? String ?? ""
        let bounds = w[kCGWindowBounds as String] as? [String: Double] ?? [:]
        if pids.contains(pid), title == "ExeRunner controlled Direct3D9 check", (bounds["Width"] ?? 0) > 200, (bounds["Height"] ?? 0) > 200 {
            print(w[kCGWindowNumber as String] as? Int ?? 0)
            exit(0)
        }
    }
    exit(1)
}
// Opt-in real native input check, restricted to the owned synthetic window.
if args[1] == "input" {
    guard CGPreflightPostEventAccess() else { print("FAIL: native event permission unavailable"); exit(5) }
    let prefix = canonical(args[2])
    let pids = Set(WineProcesses.list().filter { canonical($0.prefix) == prefix }.map { $0.pid })
    let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
    guard let w = windows.first(where: {
        pids.contains($0[kCGWindowOwnerPID as String] as? Int32 ?? 0) &&
        ($0[kCGWindowName as String] as? String) == "ExeRunner controlled Direct3D9 check"
    }), let pid = w[kCGWindowOwnerPID as String] as? Int32,
    let bounds = w[kCGWindowBounds as String] as? [String: Double],
    let x = bounds["X"], let y = bounds["Y"], let width = bounds["Width"], let height = bounds["Height"] else { exit(6) }
    guard let application = NSRunningApplication(processIdentifier: pid) else { print("FAIL: own native app is unregistered"); exit(9) }
    print("INPUT_TARGET_POLICY=\(application.activationPolicy.rawValue) ACTIVATION=\(application.activate(options: [.activateAllWindows]))")
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))
    let original = CGEvent(source: nil)!.location
    defer { CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: original, mouseButton: .left)?.post(tap: .cghidEventTap) }
    func click(_ p: CGPoint) {
        for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        }
    }
    click(CGPoint(x: x + width / 2, y: y + height / 2))
    for _ in 0..<30 {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid { break }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
    }
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { print("FAIL: synthetic window cannot obtain native focus"); exit(7) }
    for point in [CGPoint(x: x + width * 0.25, y: y + height * 0.3), CGPoint(x: x + width * 0.75, y: y + height * 0.7)] {
        print("EXPECTED_MOUSE=\(Int(point.x.rounded(.down))),\(Int(point.y.rounded(.down)))")
        click(point)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.25))
    }
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { exit(8) }
    for down in [true, false] {
        CGEvent(keyboardEventSource: nil, virtualKey: 40, keyDown: down)?.post(tap: .cghidEventTap) // K, only the test window is active.
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
    }
    print("NATIVE_INPUT_FOCUS_PID=\(pid)")
    exit(0)
}
if args[1] == "pixel" {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                  bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
          let data = context.data else { exit(2) }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let pixel = data.assumingMemoryBound(to: UInt8.self) + ((image.height / 2) * image.width + image.width / 2) * 4
    let r = Int(pixel[0]), g = Int(pixel[1]), b = Int(pixel[2])
    print("NATIVE_WINDOW_RGB=\(r),\(g),\(b)")
    let blue = b > 70 && b > r + 35 && g > r + 15
    let orange = r > 100 && r > g + 30 && g > b + 20
    exit(blue || orange ? 0 : 3)
}
exit(4)
