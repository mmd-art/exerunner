import Darwin
import Foundation

enum GameModePolicy: String, Codable, Sendable {
    case automatic = "auto", on, off
}

struct GameModeStatus: Equatable, Sendable {
    var policy: GameModePolicy
    var enabled: Bool

    static func parse(_ output: String) -> Self? {
        let text = output.replacingOccurrences(of: "\u{1b}\\[[0-9;]*m", with: "", options: .regularExpression).lowercased()
        let enabled: Bool
        if text.contains("game mode is on.") { enabled = true }
        else if text.contains("game mode is off.") { enabled = false }
        else { return nil }
        if text.contains("forced always on") { return Self(policy: .on, enabled: enabled) }
        if text.contains("forced always off") { return Self(policy: .off, enabled: enabled) }
        if text.contains("policy is currently automatic") { return Self(policy: .automatic, enabled: enabled) }
        return nil
    }
}

enum GameBoostFailure: String, Error {
    case unavailable, commandFailed, invalidStatus, enableFailed, restoreFailed, timeout
}

struct GameModeTool: Sendable {
    let url: URL

    /// These developer tools remain Apple's installed files, never copied into the app.
    static func locate() -> Self? {
        let candidates = ["/usr/bin/gamepolicyctl", "/usr/sbin/gamepolicyctl",
                          "/Applications/Xcode.app/Contents/Developer/usr/bin/gamepolicyctl",
                          "/Library/Developer/CommandLineTools/usr/bin/gamepolicyctl"]
        if let path = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) {
            return Self(url: URL(fileURLWithPath: path))
        }
        guard let output = try? command(URL(fileURLWithPath: "/usr/bin/xcrun"), ["--find", "gamepolicyctl"]) else { return nil }
        let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard path.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return Self(url: URL(fileURLWithPath: path))
    }

    func status() throws -> GameModeStatus {
        guard let status = GameModeStatus.parse(try Self.command(url, ["game-mode", "status"])) else {
            throw GameBoostFailure.invalidStatus
        }
        return status
    }

    func set(_ policy: GameModePolicy) throws {
        _ = try Self.command(url, ["game-mode", "set", policy.rawValue])
        guard try status().policy == policy else { throw GameBoostFailure.commandFailed }
    }

    private static func command(_ url: URL, _ arguments: [String]) throws -> String {
        let process = Process(), pipe = Pipe()
        defer {
            try? pipe.fileHandleForReading.close()
            try? pipe.fileHandleForWriting.close()
        }
        process.executableURL = url
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let deadline = Date().addingTimeInterval(4)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning {
            process.terminate()
            let end = Date().addingTimeInterval(0.5)
            while process.isRunning, Date() < end { Thread.sleep(forTimeInterval: 0.02) }
            if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            throw GameBoostFailure.timeout
        }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else { throw GameBoostFailure.commandFailed }
        return output
    }
}

/// PID plus birth time prevents PID reuse from extending a game or parent lifetime.
struct GameBoostProcessIdentity: Codable, Hashable, Sendable {
    var pid: pid_t
    var seconds: UInt64
    var microseconds: UInt64

    static func current(_ pid: pid_t) -> Self? {
        var info = proc_bsdinfo()
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout.size(ofValue: info))) == MemoryLayout.size(ofValue: info),
              info.pbi_status != 5 else { return nil } // SZOMB
        return Self(pid: pid, seconds: info.pbi_start_tvsec, microseconds: info.pbi_start_tvusec)
    }

    var isAlive: Bool { Self.current(pid) == self }
}

struct GameBoostObservedProcess: Sendable {
    var prefix: String
    var path: String
}

struct GameBoostTarget: Codable, Hashable, Sendable {
    var id: String
    var prefix: String
    var paths: [String]
    var names: [String]
    var folder: String?

    func matches(_ process: GameBoostObservedProcess) -> Bool {
        guard URL(fileURLWithPath: process.prefix).standardizedFileURL.path ==
                URL(fileURLWithPath: prefix).standardizedFileURL.path else { return false }
        let path = Self.normalized(process.path)
        if paths.contains(where: { Self.normalized($0) == path }) { return true }
        if let folder {
            let root = Self.normalized(folder)
            if path == root || path.hasPrefix(root + "\\") { return true }
        }
        let name = path.split(separator: "\\").last.map(String.init) ?? path
        return names.contains { $0.lowercased() == name }
    }

    private static func normalized(_ value: String) -> String {
        var value = value.replacingOccurrences(of: "/", with: "\\").lowercased()
        if value.hasPrefix("\\\\?\\") { value.removeFirst(4) }
        while value.hasSuffix("\\") { value.removeLast() }
        return value
    }
}

struct GameBoostRequest: Codable, Sendable {
    var owner: GameBoostProcessIdentity
    var target: GameBoostTarget
    var startupDeadline: Date
    var lastSeen: Date?
    var ownerExitedAt: Date?
}

struct GameBoostJournal: Codable, Sendable {
    var requests: [String: GameBoostRequest] = [:]
    var previousPolicy: GameModePolicy?
    var previousEnabled: Bool?
    var toolPath: String?
    var guardProcess: GameBoostProcessIdentity?
    var enabled = false
    var externallyChanged = false
    var failure: GameBoostFailure?
}

extension GameBoostFailure: Codable {}

/// All GUI/shortcut instances share one journal and one monitor for the user's system policy.
struct GameBoostStore: Sendable {
    let directory: URL
    var journalFile: URL { directory.appendingPathComponent("session.json") }

    func locked<T>(_ operation: (inout GameBoostJournal) throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let fd = open(directory.appendingPathComponent("session.lock").path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { throw GameBoostFailure.commandFailed }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw GameBoostFailure.commandFailed }
        defer { flock(fd, LOCK_UN) }
        var state: GameBoostJournal
        if FileManager.default.fileExists(atPath: journalFile.path) {
            state = try JSONDecoder().decode(GameBoostJournal.self, from: Data(contentsOf: journalFile))
        } else { state = GameBoostJournal() }
        let result = try operation(&state)
        try save(state)
        return result
    }

    func save(_ state: GameBoostJournal) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(state).write(to: journalFile, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: journalFile.path)
    }

    func read() throws -> GameBoostJournal { try locked { $0 } }
}

struct GameBoostSnapshot: Equatable, Sendable {
    var available = false
    var activeGames = 0
    var enabled = false
    var externallyChanged = false
    var failure: GameBoostFailure?
}

/// Runs outside the GUI so Force Quit does not strand a forced global policy.
enum GameBoostMonitor {
    static func run(store: GameBoostStore, enabled: () -> Bool,
                    observe: () -> [GameBoostObservedProcess]) -> Int32 {
        try? FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        let lock = open(store.directory.appendingPathComponent("monitor.lock").path, O_CREAT | O_RDWR, 0o600)
        guard lock >= 0 else { return 1 }
        defer { close(lock) }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { return 0 }
        defer { flock(lock, LOCK_UN) }
        do {
            try store.locked { $0.guardProcess = GameBoostProcessIdentity.current(getpid()) }
            while true {
                let finished = try autoreleasepool {
                    let processes = observe()
                    return try step(store: store, enabled: enabled(), processes: processes)
                }
                if finished { return 0 }
                Thread.sleep(forTimeInterval: 1)
            }
        } catch { return 1 } // Journal is retained for recovery on the next application start.
    }

    /// Holding the journal lock through policy changes serializes simultaneous first/last games.
    static func step(store: GameBoostStore, enabled: Bool, processes: [GameBoostObservedProcess],
                     now: Date = Date()) throws -> Bool {
        try store.locked { state in
            for (key, var request) in state.requests {
                if !enabled { state.requests[key] = nil; continue }
                if processes.contains(where: request.target.matches) {
                    request.lastSeen = now
                    state.requests[key] = request
                } else if let seen = request.lastSeen {
                    // Allow a brief launcher-to-game process handover.
                    if now.timeIntervalSince(seen) >= 2 { state.requests[key] = nil }
                } else if now >= request.startupDeadline {
                    state.requests[key] = nil
                } else if !request.owner.isAlive {
                    // A shortcut may exit just before its game finishes spawning.
                    if let gone = request.ownerExitedAt, now.timeIntervalSince(gone) >= 5 {
                        state.requests[key] = nil
                    } else {
                        request.ownerExitedAt = request.ownerExitedAt ?? now
                        state.requests[key] = request
                    }
                }
            }
            guard let path = state.toolPath else { return state.requests.isEmpty }
            let tool = GameModeTool(url: URL(fileURLWithPath: path))
            if state.requests.isEmpty {
                if let previous = state.previousPolicy {
                    do {
                        let current = try tool.status()
                        if !state.externallyChanged && current.policy == .on {
                            try tool.set(previous)
                        }
                        state.previousPolicy = nil
                        state.previousEnabled = nil
                        state.enabled = false
                        state.externallyChanged = false
                        state.failure = nil
                    } catch { state.failure = .restoreFailed; return false }
                }
                state.guardProcess = nil
                return true
            }
            do {
                let current = try tool.status()
                if state.previousPolicy == nil {
                    state.previousPolicy = current.policy
                    state.previousEnabled = current.enabled
                    state.externallyChanged = false
                    // Persist BEFORE changing system policy, including a crash during set.
                    try store.save(state)
                    try tool.set(.on)
                } else if current.policy != .on {
                    // Preserve a user's later system setting instead of repeatedly overriding it.
                    state.externallyChanged = true
                }
                let actual = try tool.status()
                state.enabled = actual.enabled && actual.policy == .on && !state.externallyChanged
                state.failure = nil
                if !state.enabled && !state.externallyChanged { state.failure = .enableFailed }
            } catch { state.failure = .enableFailed }
            return false
        }
    }
}
