import CryptoKit
import Foundation

enum AppInfo {
    /// Working name; the product name is still open.
    static let name = "WinRunner"
    static let appleDownloads = URL(string: "https://developer.apple.com/download/all/?q=Game%20Porting%20Toolkit")!
}

struct AppError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum Paths {
    static let fm = FileManager.default
    static var home: URL { fm.homeDirectoryForCurrentUser }
    static var support: URL {
        fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(AppInfo.name, isDirectory: true)
    }
    static var settingsFile: URL { support.appendingPathComponent("settings.json") }
    static var libraryFile: URL { support.appendingPathComponent("library.json") }
    static var downloads: URL { support.appendingPathComponent("Downloads", isDirectory: true) }
    static var defaultBottles: URL { support.appendingPathComponent("Bottles", isDirectory: true) }
    static var defaultEngine: URL { support.appendingPathComponent("Engine", isDirectory: true) }
    /// The engine the app carries (scripts/build-engine.sh portable, put in by build-app.sh)
    static var bundledEngine: URL? { Bundle.main.resourceURL?.appendingPathComponent("engine", isDirectory: true) }
    /// Engine built from this repository (scripts/build-engine.sh)
    static var devEngine: URL { home.appendingPathComponent("Developer/win-runner/engine/dist", isDirectory: true) }
    /// D3DMetal as the user imported it from Apple's download; it never ships with the app
    static var d3dmetal: URL { support.appendingPathComponent("D3DMetal", isDirectory: true) }
    static var caches: URL {
        fm.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent(AppInfo.name, isDirectory: true)
    }
    static var logs: URL { home.appendingPathComponent("Library/Logs/\(AppInfo.name)", isDirectory: true) }
    static var shortcuts: URL { home.appendingPathComponent("Applications/\(AppInfo.name) Apps", isDirectory: true) }

    /// Recipes ship inside the app; a development run reads them from the repository.
    static var recipes: URL? {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("recipes", isDirectory: true),
            home.appendingPathComponent("Developer/win-runner/recipes", isDirectory: true),
        ]
        return candidates.compactMap { $0 }.first { fm.fileExists(atPath: $0.path) }
    }

    /// The game compatibility database, the same way as the recipes
    static var compat: URL? {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("compat", isDirectory: true),
            home.appendingPathComponent("Developer/win-runner/compat", isDirectory: true),
        ]
        return candidates.compactMap { $0 }.first { fm.fileExists(atPath: $0.appendingPathComponent("games.json").path) }
    }

    static func ensure(_ url: URL) throws {
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
    }

    static func logFile(_ name: String) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return logs.appendingPathComponent("\(logName(name))-\(formatter.string(from: Date())).log")
    }

    /// The newest log logFile(name) made, also from an earlier session of the app
    static func latestLog(_ name: String) -> URL? {
        let prefix = logName(name) + "-"
        let names = (try? fm.contentsOfDirectory(atPath: logs.path)) ?? []
        return names.filter {
            $0.hasPrefix(prefix) && $0.dropFirst(prefix.count).range(of: "^[0-9]{8}-[0-9]{6}\\.log$", options: .regularExpression) != nil
        }.max().map { logs.appendingPathComponent($0) }
    }

    private static func logName(_ name: String) -> String {
        name.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "_", options: .regularExpression)
    }
}

func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func sha256Hex(of file: URL) throws -> String {
    sha256Hex(try Data(contentsOf: file, options: .mappedIfSafe))
}

struct CommandResult {
    let status: Int32
    let output: String
}

enum Shell {
    /// A short command with its exit status and combined output.
    /// Not for wine: wineserver inherits pipes and would hold them open.
    static func run(_ path: String, _ arguments: [String], environment: [String: String]? = nil) async -> CommandResult {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            if let environment { process.environment = environment }
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.standardInput = FileHandle.nullDevice
            do { try process.run() } catch {
                return CommandResult(status: -1, output: error.localizedDescription)
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return CommandResult(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
        }.value
    }
}
