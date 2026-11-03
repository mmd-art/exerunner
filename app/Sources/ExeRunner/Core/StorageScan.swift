import Darwin
import Foundation

/// Read-only logical file sizes. File identity de-duplicates hardlinks, not APFS clone extents.
enum StorageScan {
    enum Kind: String, Sendable { case application, cache, environment, runtime, data, shared }
    struct Claim: Sendable {
        var id: String
        var kind: Kind
        var owners: Set<String>
        var roots: [URL]
    }
    struct Bucket: Sendable {
        var id: String
        var kind: Kind
        var owners: Set<String>
        var bytes: Int64 = 0
        var files = 0
    }
    struct Snapshot: Sendable {
        var buckets: [String: Bucket] = [:]
        var totalBytes: Int64 { buckets.values.reduce(0) { $0 + $1.bytes } }
        var incomplete = false
        var skippedLinks = 0
        var failures = 0
        var date = Date()
        var unknownItems: Set<String> = []
        var selectedFolders: [String: String] = [:]
        func exclusive(_ id: String, _ kind: Kind) -> Int64 {
            buckets.values.filter { $0.kind == kind && $0.owners == [id] && $0.id != "runner-cache" }.reduce(0) { $0 + $1.bytes }
        }
        func ownBytes(_ id: String) -> Int64 { exclusive(id, .application) + exclusive(id, .cache) }
        func shared(for id: String) -> [Bucket] {
            buckets.values.filter { $0.owners.contains(id) && !([Kind.application, .cache].contains($0.kind) && $0.owners == [id] && $0.id != "runner-cache") }
                .sorted { $0.id < $1.id }
        }
    }
    struct Identity: Hashable { let device: Int32; let inode: UInt64 }
    private struct Record { var bytes: Int64; var targets: Set<String> }
    static func canonical(_ url: URL) -> URL {
        var path = url.standardizedFileURL.path
        if path == "/tmp" || path.hasPrefix("/tmp/") || path == "/var" || path.hasPrefix("/var/") { path = "/private" + path }
        return URL(fileURLWithPath: path)
    }
    /// All ancestors must be real directories. Never traverse user links or Wine reparse entries.
    private static func openDirectory(_ url: URL) -> Int32 {
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { return -1 }
        for part in canonical(url).pathComponents.dropFirst() {
            let next = openat(fd, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            close(fd)
            if next < 0 { return -1 }
            fd = next
        }
        return fd
    }
    static func realDirectory(_ url: URL) -> Bool {
        let fd = openDirectory(url)
        guard fd >= 0 else { return false }
        close(fd); return true
    }
    static func names(in url: URL, cancelled: () -> Bool = { Task.isCancelled }) -> [String]? {
        let fd = openDirectory(url)
        guard fd >= 0, let dir = fdopendir(fd) else { if fd >= 0 { close(fd) }; return nil }
        defer { closedir(dir) }
        var names: [String] = []
        while true {
            errno = 0
            guard let entry = readdir(dir) else { return errno == 0 ? names : nil }
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: 1024) { String(cString: $0) }
            }
            if name != "." && name != ".." { names.append(name) }
            if names.count > 250_000 || cancelled() { return nil }
        }
    }
    static func regularFileExists(_ url: URL) -> Bool {
        let parent = openDirectory(url.deletingLastPathComponent())
        guard parent >= 0 else { return false }
        defer { close(parent) }
        var st = stat()
        return fstatat(parent, url.lastPathComponent, &st, AT_SYMLINK_NOFOLLOW) == 0 && st.st_mode & S_IFMT == S_IFREG
    }
    static func text(_ url: URL, limit: Int) -> String? {
        let parent = openDirectory(url.deletingLastPathComponent())
        guard parent >= 0 else { return nil }
        defer { close(parent) }
        let fd = openat(parent, url.lastPathComponent, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var st = stat()
        guard fstat(fd, &st) == 0, st.st_mode & S_IFMT == S_IFREG, st.st_size <= limit,
              let data = try? handle.read(upToCount: limit + 1), data.count <= limit else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func contains(_ file: URL, in root: URL) -> Bool {
        let f = canonical(file).path, r = canonical(root).path
        return f == r || f.hasPrefix(r + "/")
    }
    static func run(_ claims: [Claim], maxEntries: Int = 250_000, maxSeconds: Double = 30,
                    cancelled: () -> Bool = { Task.isCancelled }) -> Snapshot {
        var result = Snapshot(), records: [Identity: Record] = [:]
        var entries = 0, stopped = false
        let started = Date()
        var roots: [(URL, String)] = []
        for claim in claims {
            if var existing = result.buckets[claim.id] { existing.owners.formUnion(claim.owners); result.buckets[claim.id] = existing }
            else { result.buckets[claim.id] = Bucket(id: claim.id, kind: claim.kind, owners: claim.owners) }
            for raw in claim.roots {
                let root = canonical(raw)
                guard realDirectory(root) else {
                    if FileManager.default.fileExists(atPath: root.path) { result.incomplete = true; result.failures += 1 }
                    continue
                }
                roots.append((root, claim.id))
            }
        }
        // Enumerate only outer roots; classification still uses every nested claim.
        let unique = Set(roots.map { $0.0.path }).sorted { $0.count < $1.count }
        var outer: [URL] = []
        for path in unique {
            let url = URL(fileURLWithPath: path)
            if !outer.contains(where: { contains(url, in: $0) }) { outer.append(url) }
        }
        var visitedDirectories = Set<Identity>()
        let classification = roots.map { (path: $0.0.path, id: $0.1) }
        func targets(for file: URL) -> Set<String> {
            let path = file.path
            var longest = -1, ids = Set<String>()
            for root in classification where path == root.path || path.hasPrefix(root.path + "/") {
                if root.path.count > longest { longest = root.path.count; ids = [root.id] }
                else if root.path.count == longest { ids.insert(root.id) }
            }
            return ids
        }
        func walk(_ fd: Int32, path: URL, device: Int32, depth: Int) {
            guard let directory = fdopendir(fd) else { close(fd); result.incomplete = true; result.failures += 1; return }
            defer { closedir(directory) }
            if stopped { return }
            if cancelled() || Date().timeIntervalSince(started) > maxSeconds || depth > 64 || entries >= maxEntries {
                result.incomplete = true; stopped = true; return
            }
            var ds = stat()
            guard fstat(dirfd(directory), &ds) == 0, ds.st_dev == device else {
                result.incomplete = true; result.failures += 1; return
            }
            guard visitedDirectories.insert(Identity(device: ds.st_dev, inode: ds.st_ino)).inserted else { return }
            while true {
                if stopped { return }
                errno = 0
                guard let entry = readdir(directory) else {
                    if errno != 0 { result.incomplete = true; result.failures += 1 }
                    break
                }
                let name = withUnsafePointer(to: &entry.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: 1024) { String(cString: $0) }
                }
                if name == "." || name == ".." { continue }
                entries += 1
                if entries > maxEntries || cancelled() || Date().timeIntervalSince(started) > maxSeconds {
                    result.incomplete = true; stopped = true; return
                }
                let file = path.appendingPathComponent(name)
                var st = stat()
                guard fstatat(dirfd(directory), name, &st, AT_SYMLINK_NOFOLLOW) == 0 else { result.incomplete = true; result.failures += 1; continue }
                switch st.st_mode & S_IFMT {
                case S_IFDIR:
                    let child = openat(dirfd(directory), name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                    if child >= 0 { walk(child, path: file, device: device, depth: depth + 1) }
                    else { result.incomplete = true; result.failures += 1 }
                case S_IFREG:
                    guard st.st_dev == device else { result.incomplete = true; continue }
                    let key = Identity(device: st.st_dev, inode: st.st_ino), assignment = targets(for: file)
                    if var previous = records[key] {
                        if previous.bytes != st.st_size { result.incomplete = true }
                        previous.targets.formUnion(assignment); previous.bytes = max(previous.bytes, st.st_size); records[key] = previous
                    } else { records[key] = Record(bytes: st.st_size, targets: assignment) }
                case S_IFLNK: result.skippedLinks += 1
                default: result.incomplete = true; result.failures += 1
                }
            }
        }
        for root in outer {
            let fd = openDirectory(root)
            var st = stat()
            if fd >= 0 {
                if fstat(fd, &st) == 0 { walk(fd, path: root, device: st.st_dev, depth: 0) }
                else { close(fd); result.incomplete = true; result.failures += 1 }
            } else { result.incomplete = true; result.failures += 1 }
        }
        for record in records.values {
            let ids = record.targets.sorted()
            guard !ids.isEmpty else { continue }
            let id: String
            if ids.count == 1 { id = ids[0] }
            else {
                id = "shared:" + ids.map { Data($0.utf8).base64EncodedString() }.joined(separator: "|")
                if result.buckets[id] == nil {
                    result.buckets[id] = Bucket(id: id, kind: .shared,
                        owners: Set(ids.flatMap { result.buckets[$0]?.owners ?? [] }))
                }
            }
            result.buckets[id]?.bytes += record.bytes
            result.buckets[id]?.files += 1
        }
        for id in Array(result.buckets.keys) {
            if result.buckets[id]?.kind == .application && (result.buckets[id]?.owners.count ?? 0) > 1 { result.buckets[id]?.kind = .shared }
        }
        return result
    }
}
