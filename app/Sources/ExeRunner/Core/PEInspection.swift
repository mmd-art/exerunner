import Foundation

/// Read-only PE32/PE32+ inspection. No DLL or executable is loaded or executed.
/// Layout: https://learn.microsoft.com/en-us/windows/win32/debug/pe-format
struct PEInspection: Equatable {
    enum Architecture: String { case x86, x64, arm64, other }
    let architecture: Architecture
    let imports: [String]
    let managed: Bool

    static func read(_ url: URL) -> PEInspection? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 0, size <= 512 * 1024 * 1024,
              let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return parse(data)
    }

    static func parse(_ data: Data) -> PEInspection? {
        let r = Reader(data: data)
        guard r.u16(0) == 0x5a4d, let offset = r.u32(0x3c) else { return nil }
        let pe = Int(offset), coff = pe + 4, optional = coff + 20
        guard r.u32(pe) == 0x4550, let machine = r.u16(coff), let sections = r.u16(coff + 2),
              sections > 0, sections <= 96, let optionalSize = r.u16(coff + 16),
              r.has(optional, Int(optionalSize)), let magic = r.u16(optional),
              magic == 0x10b || magic == 0x20b else { return nil }
        let start = magic == 0x20b ? 112 : 96
        guard Int(optionalSize) >= start, let declared = r.u32(optional + start - 4),
              let headers = r.u32(optional + 60) else { return nil }
        let count = min(Int(declared), 16, (Int(optionalSize) - start) / 8)
        let sectionStart = optional + Int(optionalSize)
        guard r.has(sectionStart, Int(sections) * 40) else { return nil }
        var maps: [(rva: Int, raw: Int, size: Int)] = []
        for i in 0..<Int(sections) {
            let p = sectionStart + i * 40
            guard let rva = r.u32(p + 12), let raw = r.u32(p + 20), let size = r.u32(p + 16),
                  r.has(Int(raw), Int(size)) else { return nil }
            maps.append((Int(rva), Int(raw), Int(size)))
        }
        func fileOffset(_ rva: UInt32, length: Int) -> Int? {
            let at = Int(rva)
            if at < Int(headers), length <= Int(headers) - at, r.has(at, length) { return at }
            for s in maps where at >= s.rva && at - s.rva < s.size {
                let delta = at - s.rva
                if length <= s.size - delta, r.has(s.raw + delta, length) { return s.raw + delta }
            }
            return nil
        }
        func directory(_ index: Int) -> (UInt32, Int)? {
            guard index < count, let rva = r.u32(optional + start + index * 8),
                  let size = r.u32(optional + start + index * 8 + 4), rva > 0, size > 0 else { return nil }
            return (rva, Int(size))
        }
        func names(_ index: Int, stride: Int, nameAt: Int) -> [String]? {
            guard let (rva, size) = directory(index) else { return [] }
            guard size >= stride, let first = fileOffset(rva, length: min(size, 512 * stride)) else { return nil }
            var result: [String] = []
            for i in 0..<min(size / stride, 512) {
                let p = first + i * stride
                guard r.has(p, stride) else { return nil }
                if data[p..<p + stride].allSatisfy({ $0 == 0 }) { return result }
                guard let name = r.u32(p + nameAt) else { return nil }
                var nameRVA = UInt64(name)
                if index == 13, r.u32(p).map({ $0 & 1 == 0 }) == true {
                    let imageBase = magic == 0x20b ? r.u64(optional + 24) : r.u32(optional + 28).map(UInt64.init)
                    guard let imageBase, nameRVA >= imageBase else { return nil }
                    nameRVA -= imageBase
                }
                guard nameRVA <= UInt32.max, let nameOffset = fileOffset(UInt32(nameRVA), length: 1),
                      let name = r.ascii(nameOffset), !name.isEmpty,
                      name.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45,46,95].contains($0) }) else { return nil }
                result.append(name.lowercased())
            }
            return nil
        }
        guard let regular = names(1, stride: 20, nameAt: 12), let delayed = names(13, stride: 32, nameAt: 4) else { return nil }
        let arch: Architecture
        switch machine { case 0x14c: arch = .x86; case 0x8664: arch = .x64; case 0xaa64: arch = .arm64; default: arch = .other }
        let managed = directory(14).flatMap { fileOffset($0.0, length: min($0.1, 24)) } != nil
        return .init(architecture: arch, imports: Set(regular + delayed).sorted(), managed: managed)
    }

    private struct Reader {
        let data: Data
        func has(_ at: Int, _ size: Int) -> Bool { at >= 0 && size >= 0 && at <= data.count && size <= data.count - at }
        func u16(_ at: Int) -> UInt16? { has(at, 2) ? UInt16(data[at]) | UInt16(data[at + 1]) << 8 : nil }
        func u32(_ at: Int) -> UInt32? { guard let low = u16(at), let high = u16(at + 2) else { return nil }; return UInt32(low) | UInt32(high) << 16 }
        func u64(_ at: Int) -> UInt64? { guard let low = u32(at), let high = u32(at + 4) else { return nil }; return UInt64(low) | UInt64(high) << 32 }
        func ascii(_ at: Int) -> String? {
            guard has(at, 1) else { return nil }
            let end = min(data.count, at + 260)
            guard let zero = data[at..<end].firstIndex(of: 0) else { return nil }
            return String(data: data[at..<zero], encoding: .ascii)
        }
    }
}
