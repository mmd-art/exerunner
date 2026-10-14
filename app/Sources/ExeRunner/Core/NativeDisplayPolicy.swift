import AppKit
import CoreGraphics
import CryptoKit
import Foundation

/// Physical pixels of the screen chosen at launch; macOS scaling is only read.
struct NativeDisplayTarget: Equatable {
    var displayID: UInt32
    var outputIndex: Int
    var width: Int
    var height: Int
    var refreshRate: Double

    @MainActor static func current() -> NativeDisplayTarget? {
        let screens = NSScreen.screens
        guard let screen = NSApp?.keyWindow?.screen ?? NSScreen.main ?? screens.first,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let mode = CGDisplayCopyDisplayMode(number.uint32Value) else { return nil }
        var online = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &online, &count) == .success else { return nil }
        let screenIDs = screens.compactMap { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value }
        // Same ordering as winemac.drv: online displays, with the primary swapped to zero.
        var outputs = online.prefix(Int(count)).filter { screenIDs.contains($0) || screenIDs.contains(CGDisplayMirrorsDisplay($0)) }
        if let primary = screenIDs.first, let index = outputs.firstIndex(where: { $0 == primary || CGDisplayMirrorsDisplay($0) == primary }), index != 0 {
            outputs.swapAt(0, index)
        }
        let index = outputs.firstIndex(where: { $0 == number.uint32Value || CGDisplayMirrorsDisplay($0) == number.uint32Value }) ?? 0
        guard mode.pixelWidth > 0, mode.pixelHeight > 0 else { return nil }
        return NativeDisplayTarget(displayID: number.uint32Value, outputIndex: index,
                                   width: mode.pixelWidth, height: mode.pixelHeight, refreshRate: mode.refreshRate)
    }
}

/// Safe profile adapters behind one launch policy. Unknown formats are left alone.
/// Only display attributes change; quality, saves, windowed choices and other games survive.
enum NativeDisplayPolicy {
    struct InvalidProfile: Error {}
    struct Update { var profile: URL; var backup: URL; var target: NativeDisplayTarget }

    static func patchedPrimal(_ original: Data, target: NativeDisplayTarget) throws -> Data? {
        guard target.width > 0, target.height > 0, target.outputIndex >= 0,
              let source = String(data: original, encoding: .utf8) else { throw InvalidProfile() }
        let parser = XMLParser(data: original)
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else { throw InvalidProfile() }
        let tag = try NSRegularExpression(pattern: #"<VideoMode\b[^>]*>"#)
        let matches = tag.matches(in: source, range: NSRange(source.startIndex..., in: source))
        guard matches.count == 1, let range = Range(matches[0].range, in: source) else { throw InvalidProfile() }
        var video = String(source[range])
        guard try attribute("windowMode", in: video) == "0" else { return nil }
        video = try replacing("width", with: String(target.width), in: video)
        video = try replacing("height", with: String(target.height), in: video)
        video = try replacing("displayIndex", with: String(target.outputIndex), in: video, required: false)
        if target.refreshRate > 0, target.refreshRate.isFinite,
           try attribute("refreshRateNumerator", in: video) != nil,
           try attribute("refreshRateDenominator", in: video) != nil {
            let numerator = Int((target.refreshRate * 1000).rounded())
            let divisor = gcd(numerator, 1000)
            video = try replacing("refreshRateNumerator", with: String(numerator / divisor), in: video)
            video = try replacing("refreshRateDenominator", with: String(1000 / divisor), in: video)
        }
        var updated = source.replacingCharacters(in: range, with: video)
        // Primal's render profile uses the same zero-based output selector.
        let render = try NSRegularExpression(pattern: #"<RenderProfile\b[^>]*>"#)
        let renderMatches = render.matches(in: updated, range: NSRange(updated.startIndex..., in: updated))
        if renderMatches.count == 1, let renderRange = Range(renderMatches[0].range, in: updated) {
            let replacement = try replacing("MainMonitor", with: String(target.outputIndex), in: String(updated[renderRange]), required: false)
            updated.replaceSubrange(renderRange, with: replacement)
        }
        let result = Data(updated.utf8)
        return result == original ? nil : result
    }

    static func prepare(adapter: String?, documents: URL, target: NativeDisplayTarget,
                        backups: URL) throws -> Update? {
        guard adapter == "farcry-primal" else { return nil }
        let profile = documents.appendingPathComponent("My Games/Far Cry Primal/GamerProfile.xml").resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: profile.path) else { return nil }
        let original = try Data(contentsOf: profile)
        guard original.count <= 512 * 1024, let updated = try patchedPrimal(original, target: target) else { return nil }
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        let hash = SHA256.hash(data: original).map { String(format: "%02x", $0) }.joined()
        let backup = backups.appendingPathComponent("farcry-primal-\(hash).xml")
        if !FileManager.default.fileExists(atPath: backup.path) { try original.write(to: backup, options: .atomic) }
        // Refuse a stale write if the owner/game changed the file during preparation.
        guard try Data(contentsOf: profile) == original else { throw InvalidProfile() }
        let permissions = try FileManager.default.attributesOfItem(atPath: profile.path)[.posixPermissions]
        try updated.write(to: profile, options: .atomic)
        if let permissions { try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: profile.path) }
        return Update(profile: profile, backup: backup, target: target)
    }

    private static func attribute(_ name: String, in source: String) throws -> String? {
        let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: name) + #"\s*=\s*["']([^"']*)["']"#
        let regex = try NSRegularExpression(pattern: pattern)
        let matches = regex.matches(in: source, range: NSRange(source.startIndex..., in: source))
        guard matches.count <= 1 else { throw InvalidProfile() }
        guard let match = matches.first, let range = Range(match.range(at: 1), in: source) else { return nil }
        return String(source[range])
    }

    private static func replacing(_ name: String, with value: String, in source: String, required: Bool = true) throws -> String {
        let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: name) + #"\s*=\s*["']([^"']*)["']"#
        let regex = try NSRegularExpression(pattern: pattern)
        let matches = regex.matches(in: source, range: NSRange(source.startIndex..., in: source))
        guard matches.count <= 1 else { throw InvalidProfile() }
        guard let match = matches.first, let range = Range(match.range(at: 1), in: source) else {
            if required { throw InvalidProfile() }; return source
        }
        return source.replacingCharacters(in: range, with: value)
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        var x = a, y = b
        while y != 0 { (x, y) = (y, x % y) }
        return max(1, x)
    }
}
