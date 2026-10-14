import Darwin
import Foundation

struct TestObservation: Codable {
    var identity: GameBoostProcessIdentity
    var prefix: String
    var path: String
}

@main
enum GameBoostTests {
    static var passed = 0
    static var children: [Process] = []
    static var roots: [URL] = []

    static func check(_ name: String, _ condition: Bool) {
        guard condition else { fatalError("FAIL: " + name) }
        passed += 1
        print("PASS: " + name)
    }

    static func fixture(_ policy: GameModePolicy = .automatic) throws -> (GameBoostStore, GameModeTool) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("exerunner-boost-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        roots.append(root)
        let source = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("gamepolicy-fixture.sh")
        let tool = root.appendingPathComponent("gamepolicyctl")
        try FileManager.default.copyItem(at: source, to: tool)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: tool.path)
        try (policy.rawValue + "\n").write(to: root.appendingPathComponent("policy"), atomically: true, encoding: .utf8)
        return (GameBoostStore(directory: root), GameModeTool(url: tool))
    }

    static func target(_ id: String = "game", prefix: String = "/test/bottle") -> GameBoostTarget {
        GameBoostTarget(id: id, prefix: prefix, paths: ["C:\\Games\\\(id).exe"], names: [], folder: nil)
    }

    static func seed(_ store: GameBoostStore, tool: GameModeTool, targets: [GameBoostTarget],
                     owner: GameBoostProcessIdentity? = nil, deadline: Date = Date().addingTimeInterval(120)) throws {
        let owner = owner ?? GameBoostProcessIdentity.current(getpid())!
        try store.locked {
            $0.toolPath = tool.url.path
            for target in targets {
                $0.requests[target.id] = GameBoostRequest(owner: owner, target: target, startupDeadline: deadline)
            }
        }
    }

    static func observed(_ target: GameBoostTarget) -> GameBoostObservedProcess {
        GameBoostObservedProcess(prefix: target.prefix, path: target.paths[0])
    }

    static func policy(_ tool: GameModeTool) throws -> GameModePolicy { try tool.status().policy }

    static func sleeper() throws -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sleep")
        p.arguments = ["60"]
        try p.run()
        children.append(p)
        return p
    }

    static func observations(_ store: GameBoostStore, _ values: [TestObservation]) throws {
        try JSONEncoder().encode(values).write(to: store.directory.appendingPathComponent("observed.json"), options: .atomic)
    }

    static func openDescriptorCount() -> Int {
        let needed = proc_pidinfo(getpid(), PROC_PIDLISTFDS, 0, nil, 0)
        precondition(needed > 0)
        var entries = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(needed) / MemoryLayout<proc_fdinfo>.size + 32)
        let bytes = entries.withUnsafeMutableBytes {
            proc_pidinfo(getpid(), PROC_PIDLISTFDS, 0, $0.baseAddress, Int32($0.count))
        }
        precondition(bytes > 0)
        return Int(bytes) / MemoryLayout<proc_fdinfo>.size
    }

    static func wait(_ description: String, timeout: Double = 12, until condition: () throws -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if try condition() { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        fatalError("TIMEOUT: " + description)
    }

    static func main() async throws {
        if CommandLine.arguments.contains("--game-boost-monitor") {
            let root = URL(fileURLWithPath: CommandLine.arguments[2])
            let status = GameBoostMonitor.run(store: GameBoostStore(directory: root), enabled: { true }, observe: {
                guard let data = try? Data(contentsOf: root.appendingPathComponent("observed.json")),
                      let list = try? JSONDecoder().decode([TestObservation].self, from: data) else { return [] }
                return list.filter { $0.identity.isAlive }.map { GameBoostObservedProcess(prefix: $0.prefix, path: $0.path) }
            })
            exit(status)
        }
        if CommandLine.arguments.contains("--crash-owner") {
            let root = URL(fileURLWithPath: CommandLine.arguments[2])
            let tool = GameModeTool(url: root.appendingPathComponent("gamepolicyctl"))
            let coordinator = GameBoostCoordinator(directory: root, helper: URL(fileURLWithPath: CommandLine.arguments[0]),
                                                  locateTool: { tool })
            let result = await coordinator.begin(target())
            guard result.enabled else { exit(1) }
            try Data("ready".utf8).write(to: root.appendingPathComponent("owner-ready"))
            Darwin.kill(getpid(), SIGKILL)
            exit(2)
        }
        setbuf(stdout, nil)
        defer {
            for child in children where child.isRunning { child.terminate(); child.waitUntilExit() }
        }

        check("parse automatic/off", GameModeStatus.parse("Game mode is off. Game mode enablement policy is currently automatic.") ==
              GameModeStatus(policy: .automatic, enabled: false))
        check("parse colored forced on", GameModeStatus.parse("Game mode is \u{1b}[0;32mon\u{1b}[0;0m. Game mode is forced always on.") ==
              GameModeStatus(policy: .on, enabled: true))
        check("parse forced off", GameModeStatus.parse("Game mode is off. Game mode is forced always off.") ==
              GameModeStatus(policy: .off, enabled: false))
        check("reject unsupported status", GameModeStatus.parse("unsupported command") == nil)

        do {
            let (_, tool) = try fixture()
            _ = try tool.status()
            let before = openDescriptorCount()
            for _ in 0..<120 { _ = try tool.status() }
            let after = openDescriptorCount()
            print("Successful poll FDs: \(before) -> \(after)")
            check("repeated successful policy polls keep descriptors bounded", after <= before + 8)
        }
        do {
            let tool = GameModeTool(url: URL(fileURLWithPath: "/usr/bin/false"))
            _ = try? tool.status()
            let before = openDescriptorCount()
            for _ in 0..<120 {
                do { _ = try tool.status(); fatalError("Expected failed backend") }
                catch { }
            }
            let after = openDescriptorCount()
            print("Failed poll FDs: \(before) -> \(after)")
            check("repeated failed policy polls also release descriptors", after <= before + 8)
        }

        let match = GameBoostTarget(id: "game", prefix: "/test/bottle", paths: [], names: ["Game.exe"],
                                    folder: "C:\\Steam\\common\\Game")
        check("Steam game matches its own directory", match.matches(GameBoostObservedProcess(prefix: "/test/bottle", path: "c:/steam/common/game/bin/GAME.exe")))
        check("Steam client alone is not a game", !match.matches(GameBoostObservedProcess(prefix: "/test/bottle", path: "C:\\Steam\\steam.exe")))
        check("foreign bottle is excluded", !match.matches(GameBoostObservedProcess(prefix: "/test/other", path: "C:\\Steam\\common\\Game\\Game.exe")))

        for previous in [GameModePolicy.automatic, .off, .on] {
            let (store, tool) = try fixture(previous)
            let game = target()
            try seed(store, tool: tool, targets: [game])
            _ = try GameBoostMonitor.step(store: store, enabled: true, processes: [observed(game)])
            check("enable from \(previous.rawValue)", try policy(tool) == .on && store.read().previousPolicy == previous)
            let stop = try GameBoostMonitor.step(store: store, enabled: true, processes: [], now: Date().addingTimeInterval(3))
            check("restore \(previous.rawValue) after exit", try stop && policy(tool) == previous && store.read().previousPolicy == nil)
        }

        do {
            let (store, tool) = try fixture()
            let first = target("first"), second = target("second")
            try seed(store, tool: tool, targets: [first, second])
            _ = try GameBoostMonitor.step(store: store, enabled: true, processes: [observed(first), observed(second)])
            _ = try GameBoostMonitor.step(store: store, enabled: true, processes: [observed(second)], now: Date().addingTimeInterval(3))
            check("first game exit keeps second boosted", try policy(tool) == .on && store.read().requests.count == 1)
            _ = try GameBoostMonitor.step(store: store, enabled: true, processes: [], now: Date().addingTimeInterval(6))
            check("last game restores original policy", try policy(tool) == .automatic)
        }
        do {
            let (store, tool) = try fixture()
            try seed(store, tool: tool, targets: [target()])
            _ = try GameBoostMonitor.step(store: store, enabled: true, processes: [])
            try store.locked { for (key, var request) in $0.requests { request.startupDeadline = .distantPast; $0.requests[key] = request } }
            _ = try GameBoostMonitor.step(store: store, enabled: true, processes: [])
            check("failed launch restores without a game", try policy(tool) == .automatic)
        }
        do {
            let (store, tool) = try fixture(.off)
            let game = target()
            try seed(store, tool: tool, targets: [game])
            _ = try GameBoostMonitor.step(store: store, enabled: true, processes: [observed(game)])
            _ = try GameBoostMonitor.step(store: store, enabled: false, processes: [observed(game)])
            check("toggle off restores while game stays alive", try policy(tool) == .off && store.read().requests.isEmpty)
        }
        do {
            let (store, tool) = try fixture()
            let game = target()
            try seed(store, tool: tool, targets: [game])
            _ = try GameBoostMonitor.step(store: store, enabled: true, processes: [observed(game)])
            try tool.set(.off)
            _ = try GameBoostMonitor.step(store: store, enabled: true, processes: [observed(game)])
            check("later manual setting is respected during play", try policy(tool) == .off && store.read().externallyChanged)
            _ = try GameBoostMonitor.step(store: store, enabled: true, processes: [], now: Date().addingTimeInterval(3))
            check("later manual setting is respected after exit", try policy(tool) == .off)
        }
        do {
            let (store, tool) = try fixture(.on)
            try store.locked { $0.toolPath = tool.url.path; $0.previousPolicy = .automatic; $0.previousEnabled = false }
            _ = try GameBoostMonitor.step(store: store, enabled: true, processes: [])
            check("stale journal recovers captured policy", try policy(tool) == .automatic)
        }
        do {
            let (store, tool) = try fixture()
            try Data().write(to: store.directory.appendingPathComponent("partial-enable"))
            try seed(store, tool: tool, targets: [target()])
            _ = try GameBoostMonitor.step(store: store, enabled: true, processes: [])
            check("partial activation retains original journal", try policy(tool) == .on && store.read().previousPolicy == .automatic)
            _ = try GameBoostMonitor.step(store: store, enabled: false, processes: [])
            check("partial activation is rolled back", try policy(tool) == .automatic)
        }
        do {
            let (store, tool) = try fixture(.off)
            let game = target()
            try seed(store, tool: tool, targets: [game])
            _ = try GameBoostMonitor.step(store: store, enabled: true, processes: [observed(game)])
            try Data().write(to: store.directory.appendingPathComponent("fail-restore"))
            _ = try GameBoostMonitor.step(store: store, enabled: false, processes: [])
            check("failed restoration keeps recovery record", try store.read().previousPolicy == .off && store.read().failure == .restoreFailed)
            try FileManager.default.removeItem(at: store.directory.appendingPathComponent("fail-restore"))
            _ = try GameBoostMonitor.step(store: store, enabled: false, processes: [])
            check("restoration retries successfully", try policy(tool) == .off && store.read().previousPolicy == nil)
        }
        do {
            let (store, _) = try fixture()
            let coordinator = GameBoostCoordinator(directory: store.directory, helper: URL(fileURLWithPath: CommandLine.arguments[0]),
                                                  locateTool: { nil })
            let state = await coordinator.begin(target())
            check("missing backend is reported without changing policy", state.failure == .unavailable && !state.available)
        }

        do {
            let (store, tool) = try fixture(.off)
            let game = try sleeper()
            let identity = GameBoostProcessIdentity.current(game.processIdentifier)!
            try observations(store, [TestObservation(identity: identity, prefix: "/test/bottle", path: "C:\\Games\\game.exe")])
            let helper = URL(fileURLWithPath: CommandLine.arguments[0])
            let first = GameBoostCoordinator(directory: store.directory, helper: helper, locateTool: { tool })
            let second = GameBoostCoordinator(directory: store.directory, helper: helper, locateTool: { tool })
            let firstState = await first.begin(target(), alreadyRunning: true)
            let secondState = await second.begin(target(), alreadyRunning: true)
            check("coordinators use one active monitor", firstState.enabled && secondState.enabled)
            _ = await first.reconcile(active: [], pending: [], enabled: false)
            check("one instance releasing does not disable another", try policy(tool) == .on)
            game.terminate(); game.waitUntilExit()
            try await wait("helper game exit restoration") { try policy(tool) == .off && store.read().previousPolicy == nil }
            check("independent helper restores after real child exit", try policy(tool) == .off)
        }
        do {
            let (store, tool) = try fixture()
            let game = try sleeper()
            let identity = GameBoostProcessIdentity.current(game.processIdentifier)!
            try observations(store, [TestObservation(identity: identity, prefix: "/test/bottle", path: "C:\\Games\\game.exe")])
            let owner = Process()
            owner.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            owner.arguments = ["--crash-owner", store.directory.path]
            owner.standardOutput = FileHandle.nullDevice
            owner.standardError = FileHandle.nullDevice
            try owner.run()
            try await wait("crashing owner ready") { FileManager.default.fileExists(atPath: store.directory.appendingPathComponent("owner-ready").path) }
            owner.waitUntilExit()
            check("Force Quit owner leaves active game boosted", try owner.terminationReason == .uncaughtSignal && policy(tool) == .on)
            game.terminate(); game.waitUntilExit()
            try await wait("orphan game cleanup") { try policy(tool) == .automatic && store.read().previousPolicy == nil }
            check("Force Quit owner still restores when its game exits", try policy(tool) == .automatic)
        }
        print("Game Boost: \(passed) checks passed; only fixture policies changed.")
        for root in roots { try? FileManager.default.removeItem(at: root) }
    }
}
