import AppKit
import Foundation

/// Tiny .app bundles in ~/Applications/<App> Apps that start one library item through this app,
/// so Windows programs show up in Launchpad, Spotlight and the Dock like Mac ones.
enum Shortcuts {
    static func url(for item: LibraryItem) -> URL {
        let safe = item.name.replacingOccurrences(of: "[/:]", with: "-", options: .regularExpression)
        return Paths.shortcuts.appendingPathComponent("\(safe).app", isDirectory: true)
    }

    static func exists(for item: LibraryItem) -> Bool {
        FileManager.default.fileExists(atPath: url(for: item).path)
    }

    @discardableResult
    static func create(for item: LibraryItem, icon: NSImage?) throws -> URL {
        guard Bundle.main.bundleURL.pathExtension == "app", let app = Bundle.main.executablePath else {
            throw AppError(t("Ярлыки создаёт только собранное приложение (\(AppInfo.name).app)"))
        }
        let bundle = url(for: item)
        try? FileManager.default.removeItem(at: bundle)
        let macOS = bundle.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try Paths.ensure(macOS)
        let id = item.id.replacingOccurrences(of: "[^A-Za-z0-9.-]", with: "-", options: .regularExpression)
        let plist: [String: Any] = [
            "CFBundleExecutable": "launch",
            "CFBundleIdentifier": "local.exerunner.shortcut.\(id)",
            "CFBundleName": item.name,
            "CFBundleDisplayName": item.name,
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0",
            "LSMinimumSystemVersion": "15.0",
            // the Windows program gets its own Dock icon; the shortcut itself stays out of it
            "LSUIElement": true,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        let launcher = macOS.appendingPathComponent("launch")
        try "#!/bin/sh\nexec \(quoted(app)) --launch \(quoted(item.id))\n".write(to: launcher, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher.path)
        if let icon { NSWorkspace.shared.setIcon(icon, forFile: bundle.path, options: []) }
        return bundle
    }

    static func remove(for item: LibraryItem) {
        try? FileManager.default.removeItem(at: url(for: item))
    }

    private static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
