/// Both the process watcher and the launch callback may report the same exit.
/// Stop belongs to the completed session, until a new launch is observed.
struct StopIntent {
    private var stopped: Set<String> = []
    mutating func mark(_ id: String) { stopped.insert(id) }
    mutating func begin(_ id: String) { stopped.remove(id) }
    mutating func observeLaunch(_ id: String, duringStop: Bool) {
        if !duringStop { begin(id) }
    }
    func ignoresExit(_ id: String) -> Bool { stopped.contains(id) }
}
