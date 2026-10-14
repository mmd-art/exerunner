import AppKit
import CoreGraphics
import Foundation

/// One launch handoff. No window manipulation, Accessibility access, or focus watchdog.
@MainActor enum NativeGameForeground {
    static func present(prefix: String, executableNames: Set<String>) async {
        let initiatingPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let parentPID = ProcessInfo.processInfo.processIdentifier
        let names = Set(executableNames.map { $0.lowercased() })
        for _ in 0..<100 {
            guard !Task.isCancelled else { return }
            let processes = WineProcesses.list().filter { process in
                process.prefix == prefix && names.contains(process.path.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last?.lowercased() ?? "")
            }
            let foreground = NSWorkspace.shared.frontmostApplication?.processIdentifier
            // A deliberate switch during startup cancels the handoff. After activation it ends.
            let prefixPIDs = Set(WineProcesses.list().filter { $0.prefix == prefix }.map(\.pid))
            if let foreground, foreground != initiatingPID, foreground != parentPID, !prefixPIDs.contains(foreground) { return }
            for process in processes {
                guard let app = NSRunningApplication(processIdentifier: process.pid), !app.isTerminated else { continue }
                if app.isActive { return }
                let windows = (CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
                let ready = windows.contains { window in
                    guard (window[kCGWindowOwnerPID as String] as? Int32) == process.pid,
                          let bounds = window[kCGWindowBounds as String] as? [String: Any],
                          let width = bounds["Width"] as? Double, let height = bounds["Height"] as? Double,
                          let alpha = window[kCGWindowAlpha as String] as? Double else { return false }
                    return width >= 320 && height >= 240 && alpha > 0
                }
                guard ready else { continue }
                if let parent = NSApp, parent.isActive { parent.yieldActivation(to: app) }
                _ = app.activate(options: [.activateAllWindows])
                return
            }
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
        }
    }
}
