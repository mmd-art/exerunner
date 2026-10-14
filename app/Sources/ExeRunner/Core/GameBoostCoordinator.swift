import Darwin
import Foundation

actor GameBoostCoordinator {
    private let store: GameBoostStore
    private let helper: URL
    private let owner: GameBoostProcessIdentity?
    private let locateTool: @Sendable () -> GameModeTool?
    private let namespace = UUID().uuidString
    private var tool: GameModeTool?
    private var helperProcess: Process?
    private var registered: Set<String> = []
    private var failed: Set<String> = []
    private var lastFailure: GameBoostFailure?

    init(directory: URL, helper: URL, locateTool: @escaping @Sendable () -> GameModeTool? = { GameModeTool.locate() }) {
        store = GameBoostStore(directory: directory)
        self.helper = helper
        self.locateTool = locateTool
        owner = GameBoostProcessIdentity.current(getpid())
    }

    func availability() async -> GameBoostSnapshot {
        if tool == nil { tool = await Task.detached { self.locateTool() }.value }
        return await snapshot()
    }

    func begin(_ target: GameBoostTarget, alreadyRunning: Bool = false) async -> GameBoostSnapshot {
        failed.remove(target.id)
        lastFailure = nil
        guard let owner else { return GameBoostSnapshot(failure: .unavailable) }
        if tool == nil { tool = await Task.detached { self.locateTool() }.value }
        guard let tool else { return GameBoostSnapshot(failure: .unavailable) }
        let key = namespace + ":" + target.id
        let store = self.store
        do {
            try await Task.detached {
                try store.locked {
                    $0.toolPath = tool.url.path
                    $0.failure = nil
                    $0.requests[key] = GameBoostRequest(owner: owner, target: target,
                                                      startupDeadline: Date().addingTimeInterval(120),
                                                      lastSeen: alreadyRunning ? Date() : nil)
                }
            }.value
            registered.insert(target.id)
            for _ in 0..<50 {
                try await ensureMonitor()
                let state = try await Task.detached { try store.read() }.value
                if state.enabled || state.externallyChanged { return snapshot(state) }
                if let failure = state.failure {
                    failed.insert(target.id)
                    lastFailure = failure
                    await cancelStart(target.id)
                    return GameBoostSnapshot(available: true, failure: failure)
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            failed.insert(target.id)
            lastFailure = .timeout
            await cancelStart(target.id)
            return GameBoostSnapshot(available: true, failure: .timeout)
        } catch {
            failed.insert(target.id)
            lastFailure = .enableFailed
            await cancelStart(target.id)
            return GameBoostSnapshot(available: true, failure: .enableFailed)
        }
    }

    /// Actual game processes keep their leases after a launcher returns or the GUI is killed.
    func cancelStart(_ id: String, failed: Bool = true) async {
        let store = self.store, key = namespace + ":" + id
        try? await Task.detached {
            try store.locked {
                if var request = $0.requests[key] {
                    request.startupDeadline = failed ? .distantPast : Date().addingTimeInterval(5)
                    $0.requests[key] = request
                }
            }
        }.value
    }

    func finishOwnerStarts() async {
        let store = self.store, prefix = namespace + ":"
        try? await Task.detached {
            try store.locked {
                for (key, var request) in $0.requests where key.hasPrefix(prefix) {
                    request.startupDeadline = .distantPast
                    $0.requests[key] = request
                }
            }
        }.value
        try? await ensureMonitor()
    }

    func reconcile(active: [GameBoostTarget], pending: Set<String>, enabled: Bool) async -> GameBoostSnapshot {
        let store = self.store
        if !enabled {
            try? await Task.detached {
                try store.locked { $0.requests = $0.requests.filter { !$0.key.hasPrefix(self.namespace + ":") } }
            }.value
            registered.removeAll()
            failed.removeAll()
            lastFailure = nil
            try? await ensureMonitor() // A stale journal still needs restoration.
            return await snapshot()
        }
        let activeIDs = Set(active.map(\.id))
        failed.formIntersection(activeIDs.union(pending))
        if failed.isEmpty { lastFailure = nil }
        for target in active where !registered.contains(target.id) && !failed.contains(target.id) {
            _ = await begin(target, alreadyRunning: true)
        }
        let ended = registered.subtracting(activeIDs.union(pending))
        if !ended.isEmpty {
            let keys = Set(ended.map { namespace + ":" + $0 })
            try? await Task.detached {
                try store.locked { $0.requests = $0.requests.filter { !keys.contains($0.key) } }
            }.value
            registered.subtract(ended)
        }
        try? await ensureMonitor()
        return await snapshot()
    }

    /// Read-only: rendering Settings or probing availability must not activate Game Mode.
    private func snapshot() async -> GameBoostSnapshot {
        let store = self.store
        guard let state = try? await Task.detached(operation: { try store.read() }).value else {
            return GameBoostSnapshot(available: tool != nil)
        }
        return snapshot(state)
    }

    private func snapshot(_ state: GameBoostJournal) -> GameBoostSnapshot {
        GameBoostSnapshot(available: tool != nil, activeGames: state.requests.count, enabled: state.enabled,
                          externallyChanged: state.externallyChanged, failure: state.failure ?? lastFailure)
    }

    private func ensureMonitor() async throws {
        let store = self.store
        let state = try await Task.detached { try store.read() }.value
        guard !state.requests.isEmpty || state.previousPolicy != nil else { return }
        if state.guardProcess?.isAlive == true || helperProcess?.isRunning == true { return }
        let process = Process()
        process.executableURL = helper
        process.arguments = ["--game-boost-monitor", store.directory.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        helperProcess = process
    }
}
