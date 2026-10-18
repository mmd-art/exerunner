import Foundation
import IOKit.pwr_mgt

struct GameObservationWait {
    private let deadline: Date
    private var seen = false
    init(now: Date, startupSeconds: TimeInterval = 120) { deadline = now.addingTimeInterval(startupSeconds) }
    mutating func finished(observed: Bool, now: Date) -> Bool {
        if observed { seen = true; return false }
        return seen || now >= deadline
    }
}

/// One process-owned idle-display assertion, shared by all observed games in this instance.
/// macOS releases it on process exit/crash. No global power, screen saver or lock policy changes.
final class KeepAwake {
    private var token: IOPMAssertionID?
    private let acquire: () -> IOPMAssertionID?
    private let release: (IOPMAssertionID) -> Void

    init(acquire: @escaping () -> IOPMAssertionID? = {
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                       IOPMAssertionLevel(kIOPMAssertionLevelOn), "ExeRunner game session" as CFString, &id)
        return result == kIOReturnSuccess ? id : nil
    }, release: @escaping (IOPMAssertionID) -> Void = { _ = IOPMAssertionRelease($0) }) {
        self.acquire = acquire; self.release = release
    }
    @discardableResult
    func update(enabled: Bool, activeGameIDs: Set<String>) -> Bool {
        if enabled && !activeGameIDs.isEmpty {
            if token == nil { token = acquire() }
        } else if let old = token {
            release(old); token = nil
        }
        return token != nil
    }
    deinit { if let token { release(token) } }
}
