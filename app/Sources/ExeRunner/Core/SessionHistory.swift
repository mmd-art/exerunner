import CryptoKit
import Darwin
import Foundation

struct SessionProcess: Codable, Hashable, Sendable {
    var pid: Int32
    var seconds: UInt64
    var micros: UInt64
    /// Empty for an observer, normalized Windows image + prefix for a Wine process.
    var image = ""
    static func current(_ pid: Int32, image: String = "") -> Self? {
        var info = proc_bsdinfo()
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout.size(ofValue: info))) == MemoryLayout.size(ofValue: info),
              info.pbi_status != 5 else { return nil }
        return Self(pid: pid, seconds: info.pbi_start_tvsec, micros: info.pbi_start_tvusec, image: image)
    }
    var isAlive: Bool { Self.current(pid, image: image) == self }
}

struct SessionClock: Sendable {
    var date: Date
    var uptime: Double
    var boot: String
    static func current() throws -> Self {
        var size = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0, size > 1, size < 256 else { throw SessionHistoryError.clock }
        var boot = [CChar](repeating: 0, count: size)
        var stamp = timespec()
        guard sysctlbyname("kern.bootsessionuuid", &boot, &size, nil, 0) == 0,
              clock_gettime(CLOCK_UPTIME_RAW, &stamp) == 0 else { throw SessionHistoryError.clock }
        return Self(date: Date(), uptime: Double(stamp.tv_sec) + Double(stamp.tv_nsec) / 1e9,
                    boot: String(cString: boot))
    }
}

enum SessionKind: String, Codable, Sendable { case game, program, launcher }
enum SessionStatus: String, Codable, Sendable {
    case starting, running, ended, exited, stopped, crashed, failed, interrupted, unobserved
    var open: Bool { self == .starting || self == .running }
}
struct SessionTarget: Codable, Equatable, Sendable {
    var key: String
    var itemID: String
    var name: String
    var kind: SessionKind
    init(itemID: String, prefix: String, name: String, kind: SessionKind) {
        key = SHA256.hash(data: Data((itemID + "\0" + prefix).utf8)).map { String(format: "%02x", $0) }.joined()
        self.itemID = itemID; self.name = name; self.kind = kind
    }
}
struct SessionObservation: Sendable { var target: SessionTarget; var processes: Set<SessionProcess> }
struct HistorySession: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var target: SessionTarget
    var requested: Date
    var observed: Date?
    var lastSeen: Date?
    var ended: Date?
    var seconds: Double = 0
    var status: SessionStatus = .starting
    var endHint: SessionStatus?
    var processes: Set<SessionProcess> = []
    var lastUptime: Double
    var boot: String
    var owner: SessionProcess?
    var deadline: Double
    var exitCode: Int32?
}
struct SessionHistorySnapshot: Equatable, Sendable {
    var sessions: [HistorySession] = []
    /// Lifetime totals survive bounded history pruning. Only .game intervals enter this map.
    var gameSeconds: [String: Double] = [:]
    var recentIDs: [String] {
        var seen = Set<String>()
        return sessions.filter { $0.observed != nil }.sorted {
            ($0.observed ?? $0.requested) > ($1.observed ?? $1.requested)
        }.compactMap { seen.insert($0.target.itemID).inserted ? $0.target.itemID : nil }
    }
}
enum SessionHistoryError: Error { case unsafePath, corrupt, clock, capacity, staleObservation }
struct HistoryLaunchTicket: Sendable { var id: UUID; var ownsOutcome: Bool }

/// Shared journal; no game files, library.json or settings.json are modified. Every transaction
/// re-reads under flock and publishes atomically, so GUI and headless observers cannot double-charge.
actor SessionHistoryStore {
    struct Document: Codable, Equatable {
        var format = 1
        var sessions: [HistorySession] = []
        var totals: [String: Double] = [:]
        var latestBoot = ""
        var latestUptime: Double = 0
    }
    static let maximumClosed = 2_000
    static let maximumOpen = 256
    let directory: URL
    private let ownerAlive: @Sendable (SessionProcess) -> Bool
    init(directory: URL, ownerAlive: @escaping @Sendable (SessionProcess) -> Bool = { $0.isAlive }) {
        self.directory = directory; self.ownerAlive = ownerAlive
    }
    private func transact<T>(_ body: (inout Document) throws -> T) throws -> T {
        let fm = FileManager.default
        var ancestor = directory
        while ancestor.path != "/" {
            if (try? fm.attributesOfItem(atPath: ancestor.path)[.type] as? FileAttributeType) == .typeSymbolicLink { throw SessionHistoryError.unsafePath }
            ancestor.deleteLastPathComponent()
        }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let lock = directory.appendingPathComponent("history.lock"), file = directory.appendingPathComponent("history.json")
        let fd = open(lock.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK, 0o600)
        guard fd >= 0 else { throw SessionHistoryError.unsafePath }
        defer { flock(fd, LOCK_UN); close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, flock(fd, LOCK_EX) == 0 else { throw SessionHistoryError.unsafePath }
        var document = Document()
        if fm.fileExists(atPath: file.path) {
            let attributes = try fm.attributesOfItem(atPath: file.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= 16 * 1024 * 1024 else { throw SessionHistoryError.unsafePath }
            do { document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: file)) }
            catch { throw SessionHistoryError.corrupt }
            guard document.format == 1, document.sessions.count <= Self.maximumClosed + Self.maximumOpen,
                  document.totals.count <= 10_000, Set(document.sessions.map(\.id)).count == document.sessions.count,
                  document.sessions.allSatisfy({ $0.seconds.isFinite && $0.seconds >= 0 && $0.lastUptime.isFinite }),
                  document.totals.values.allSatisfy({ $0.isFinite && $0 >= 0 }) else { throw SessionHistoryError.corrupt }
        }
        let original = document
        let existed = fm.fileExists(atPath: file.path)
        let value = try body(&document)
        let open = document.sessions.filter { $0.status.open }
        guard open.count <= Self.maximumOpen, document.totals.count <= 10_000 else { throw SessionHistoryError.capacity }
        document.sessions = open + document.sessions.filter { !$0.status.open }.sorted { $0.requested > $1.requested }.prefix(Self.maximumClosed)
        if existed && document == original { return value }
        let bytes = try JSONEncoder().encode(document)
        guard bytes.count <= 16 * 1024 * 1024 else { throw SessionHistoryError.capacity }
        try bytes.write(to: file, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return value
    }
    private static func snapshot(_ d: Document) -> SessionHistorySnapshot {
        SessionHistorySnapshot(sessions: d.sessions.sorted { $0.requested > $1.requested }, gameSeconds: d.totals)
    }
    func snapshot() throws -> SessionHistorySnapshot { try transact { Self.snapshot($0) } }

    func begin(_ target: SessionTarget, owner: SessionProcess?, live: Set<SessionProcess> = [], clock: SessionClock) throws -> HistoryLaunchTicket {
        try transact { d in
            guard d.latestBoot != clock.boot || clock.uptime >= d.latestUptime else { throw SessionHistoryError.staleObservation }
            d.latestBoot = clock.boot; d.latestUptime = clock.uptime
            if let i = d.sessions.firstIndex(where: { $0.target.key == target.key && $0.status.open }) {
                let old = d.sessions[i]
                let observedAlive = old.observed != nil && !old.processes.isDisjoint(with: live)
                let preparingAlive = old.observed == nil && old.deadline > clock.uptime && old.owner.map(ownerAlive) == true
                if old.boot == clock.boot && (observedAlive || preparingAlive) {
                    return HistoryLaunchTicket(id: old.id, ownsOutcome: false)
                }
                d.sessions[i].status = old.endHint ?? (old.observed == nil ? .failed : .interrupted)
                d.sessions[i].ended = old.lastSeen ?? old.requested
            }
            let session = HistorySession(target: target, requested: clock.date, lastUptime: clock.uptime,
                                         boot: clock.boot, owner: owner, deadline: clock.uptime + 120)
            d.sessions.append(session)
            return HistoryLaunchTicket(id: session.id, ownsOutcome: true)
        }
    }
    func outcome(_ id: UUID, status: Int32?, failed: Bool, waitForAppearance: Bool, clock: SessionClock) throws {
        try transact { d in
            guard let index = d.sessions.firstIndex(where: { $0.id == id }) else { return }
            if d.latestBoot != clock.boot || clock.uptime > d.latestUptime {
                d.latestBoot = clock.boot; d.latestUptime = clock.uptime
            }
            d.sessions[index].exitCode = status
            if d.sessions[index].endHint != .stopped && (failed || (status ?? 0) != 0) {
                d.sessions[index].endHint = d.sessions[index].observed == nil ? .failed : .crashed
            } else if d.sessions[index].endHint == nil && !waitForAppearance { d.sessions[index].endHint = .exited }
            if d.sessions[index].observed == nil && (failed || (status ?? 0) != 0 || !waitForAppearance) {
                d.sessions[index].status = d.sessions[index].endHint == .stopped ? .stopped : (failed || (status ?? 0) != 0 ? .failed : .unobserved)
                d.sessions[index].ended = clock.date
            } else if !d.sessions[index].status.open, d.sessions[index].status != .stopped,
                      let hint = d.sessions[index].endHint { d.sessions[index].status = hint }
        }
    }
    func confirmedCrash(_ id: UUID) throws {
        try transact { d in
            guard let i = d.sessions.firstIndex(where: { $0.id == id && $0.observed != nil }),
                  d.sessions[i].endHint != .stopped, d.sessions[i].status != .stopped else { return }
            d.sessions[i].endHint = .crashed
            if !d.sessions[i].status.open { d.sessions[i].status = .crashed }
        }
    }
    func stop(_ keys: Set<String>, clock: SessionClock) throws {
        try transact { d in
            if d.latestBoot != clock.boot || clock.uptime > d.latestUptime {
                d.latestBoot = clock.boot; d.latestUptime = clock.uptime
            }
            for i in d.sessions.indices where keys.contains(d.sessions[i].target.key) && d.sessions[i].status.open {
                d.sessions[i].endHint = .stopped
            }
        }
    }

    func tick(observations: [SessionObservation], live: Set<SessionProcess>, pending: Set<String>,
              clock: SessionClock) throws -> SessionHistorySnapshot {
        try transact { d in
            // An earlier process scan arriving late must not close or re-open newer sessions.
            guard d.latestBoot != clock.boot || clock.uptime >= d.latestUptime else { return Self.snapshot(d) }
            d.latestBoot = clock.boot; d.latestUptime = clock.uptime
            for observation in observations where !observation.processes.isEmpty {
                if let index = d.sessions.firstIndex(where: { $0.target.key == observation.target.key && $0.status.open }) {
                    let old = d.sessions[index]
                    if old.boot != clock.boot || (old.observed != nil && old.processes.isDisjoint(with: observation.processes)) {
                        d.sessions[index].status = old.endHint ?? .interrupted
                        d.sessions[index].ended = old.lastSeen ?? old.requested
                    }
                }
                if !d.sessions.contains(where: { $0.target.key == observation.target.key && $0.status.open }) {
                    d.sessions.append(HistorySession(target: observation.target, requested: clock.date,
                        lastUptime: clock.uptime, boot: clock.boot, deadline: clock.uptime))
                }
            }
            let observed = Dictionary(observations.map { ($0.target.key, $0.processes) }, uniquingKeysWith: { $0.union($1) })
            for i in d.sessions.indices where d.sessions[i].status.open {
                var s = d.sessions[i]
                let current = observed[s.target.key] ?? []
                let continuous = s.boot == clock.boot && !s.processes.isDisjoint(with: live)
                if !current.isEmpty || continuous {
                    if s.observed != nil && continuous {
                        let delta = max(0, clock.uptime - s.lastUptime)
                        if s.target.kind == .game {
                            s.seconds += delta
                            d.totals[s.target.itemID, default: 0] += delta
                        }
                    }
                    s.status = .running; s.observed = s.observed ?? clock.date
                    s.lastSeen = clock.date; s.lastUptime = clock.uptime; s.boot = clock.boot
                    s.processes = current.isEmpty ? s.processes.intersection(live) : current
                } else if s.observed != nil {
                    let gap = s.boot != clock.boot || clock.uptime - s.lastUptime > 10
                    s.status = s.endHint ?? (gap ? .interrupted : .ended)
                    s.ended = s.lastSeen // Unknown exit time is never charged up to the next scan.
                } else if s.boot != clock.boot || s.endHint == .stopped ||
                            (!pending.contains(s.target.key) && (clock.uptime >= s.deadline || s.owner.map { !ownerAlive($0) } == true)) {
                    s.status = s.endHint == .stopped ? .stopped : (s.exitCode == 0 ? .unobserved : .failed)
                    s.ended = clock.date
                } else if pending.contains(s.target.key) { s.deadline = clock.uptime + 120 }
                d.sessions[i] = s
            }
            return Self.snapshot(d)
        }
    }
}

enum SessionProcessFilter {
    static let infrastructure: Set<String> = ["steam.exe", "steamwebhelper.exe", "epicgameslauncher.exe",
        "galaxyclient.exe", "eadesktop.exe", "ubisoftconnect.exe", "upc.exe", "rockstarservice.exe",
        "cef_subprocess.exe", "unitycrashhandler32.exe", "unitycrashhandler64.exe", "crashreportclient.exe", "crashreporter.exe", "werfault.exe",
        "services.exe", "winedevice.exe", "wineboot.exe", "wineserver", "explorer.exe", "taskkill.exe", "start.exe", "rundll32.exe"]
    static func eligibleGameImage(_ name: String, launcherNames: Set<String>, wrapper: String?) -> Bool {
        let name = name.lowercased()
        return !infrastructure.contains(name) && !launcherNames.contains(name) && name != wrapper?.lowercased()
    }
}
