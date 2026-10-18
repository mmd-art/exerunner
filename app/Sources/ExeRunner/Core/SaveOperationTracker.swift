import Foundation

/// Normal app termination drains restores; a crash still leaves the verified safety snapshot.
@MainActor
final class SaveOperationTracker {
    private var tasks: [UUID: Task<String, Error>] = [:]
    private(set) var isClosing = false
    var count: Int { tasks.count }

    func perform(_ operation: @escaping () throws -> String) async throws -> String {
        guard !isClosing else { throw CancellationError() }
        let id = UUID(), task = Task.detached { try operation() }
        tasks[id] = task
        defer { tasks[id] = nil }
        return try await task.value
    }
    func finish() async {
        isClosing = true
        for task in Array(tasks.values) { _ = try? await task.value }
    }
}
