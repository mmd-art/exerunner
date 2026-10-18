import Foundation
import Darwin

extension AppState {
    var recentItems: [LibraryItem] { history.recentIDs.compactMap(item).prefix(10).map { $0 } }

    func historyTarget(_ item: LibraryItem) -> SessionTarget {
        SessionTarget(itemID: item.id, prefix: Bottle(name: item.bottle, root: bottlesRoot).prefixPath,
                      name: item.name, kind: SessionKind(rawValue: item.kind.rawValue) ?? .program)
    }
    func beginHistory(_ item: LibraryItem) async -> UUID? {
        guard managesGameBoost else { return nil } // Snapshots and self-tests never write owner history.
        do {
            pendingHistoryCrashes.subtract(history.sessions.filter { $0.target.itemID == item.id }.map(\.id))
            for _ in 0..<3 {
                let sample = await Task.detached { HistoryProcessSample.capture() }.value
                guard let clock = sample.clock else { throw SessionHistoryError.clock }
                do {
                    let ticket = try await historyStore.begin(historyTarget(item), owner: SessionProcess.current(getpid()), live: Set(sample.identities.values), clock: clock)
                    historyTickets[item.id] = ticket.id
                    return ticket.ownsOutcome ? ticket.id : nil
                } catch SessionHistoryError.staleObservation { continue }
            }
            throw SessionHistoryError.staleObservation
        } catch { historyError = t("Не удалось обновить историю. Запуск программы продолжается."); return nil }
    }
    func finishHistoryAttempt(_ item: LibraryItem, ticket: UUID?, status: Int32?, failed: Bool) async {
        guard let ticket else { return }
        do {
            let wrapper = dockExecutable(for: item, in: Bottle(name: item.bottle, root: bottlesRoot))
            try await historyStore.outcome(ticket, status: status, failed: failed,
                waitForAppearance: item.isSteamGame || wrapper.caseInsensitiveCompare(item.executableName) != .orderedSame,
                clock: SessionClock.current())
        } catch { historyError = t("Не удалось обновить историю. Запуск программы продолжается.") }
    }
    func queueHistoryCrash(_ itemID: String) {
        if let session = history.sessions.first(where: { $0.target.itemID == itemID && $0.status.open && $0.observed != nil }) {
            pendingHistoryCrashes.insert(session.id)
        }
    }
    func markHistoryStop(_ items: [LibraryItem]) async {
        guard managesGameBoost else { return }
        do { try await historyStore.stop(Set(items.map { historyTarget($0).key }), clock: SessionClock.current()) }
        catch { historyError = t("Не удалось обновить историю. Запуск программы продолжается.") }
    }
    func refreshHistory(_ sample: HistoryProcessSample) async {
        guard managesGameBoost else { return }
        do {
            guard let clock = sample.clock else { throw SessionHistoryError.clock }
            let list = sample.entries, identities = sample.identities
            let crashes = pendingHistoryCrashes
            pendingHistoryCrashes.subtract(crashes)
            for id in crashes { try await historyStore.confirmedCrash(id) }
            let observations = allItems.map { item -> SessionObservation in
                let launchers = Set(allItems.filter { $0.kind == .launcher && $0.bottle == item.bottle }.map { $0.executableName.lowercased() })
                let dock = dockExecutable(for: item, in: Bottle(name: item.bottle, root: bottlesRoot))
                let wrapper = dock.caseInsensitiveCompare(item.executableName) == .orderedSame ? nil : item.executableName
                let actual = processes(of: item, in: list).filter {
                    item.kind != .game || SessionProcessFilter.eligibleGameImage($0.name, launcherNames: launchers, wrapper: wrapper)
                }
                return SessionObservation(target: historyTarget(item), processes: Set(actual.compactMap { identities[$0.pid] }))
            }
            let pending = Set(allItems.filter { launching.contains($0.id) || starting.contains($0.id) }.map { historyTarget($0).key })
            history = try await historyStore.tick(observations: observations, live: Set(identities.values), pending: pending, clock: clock)
            historyError = nil
        } catch { historyError = t("Не удалось обновить историю. Запуск программы продолжается.") }
    }
}

/// Clock is sampled before enumeration and remains attached through actor suspension.
struct HistoryProcessSample: Sendable {
    var clock: SessionClock?
    var entries: [WineProcesses.Entry]
    var identities: [pid_t: SessionProcess]
    static func capture() -> Self {
        let clock = try? SessionClock.current()
        let entries = WineProcesses.list()
        var identities: [pid_t: SessionProcess] = [:]
        for e in entries where e.birthSeconds > 0 {
            let image = sha256Hex(Data((e.prefix + "\0" + WindowsPath.normalized(e.path)).utf8))
            identities[e.pid] = SessionProcess(pid: e.pid, seconds: e.birthSeconds, micros: e.birthMicros, image: image)
        }
        return Self(clock: clock, entries: entries, identities: identities)
    }
}
