import AppKit
import Foundation

/// Reads the main icon out of a Windows executable's resources, so programs show their own icon
/// in the library and on their Mac shortcut.
enum PEIcon {
    static func extract(from url: URL) -> NSImage? {
        if let data = try? Data(contentsOf: url, options: .mappedIfSafe),
           let pe = PEFile(data), let icon = pe.mainIcon() { return icon }
        // Some launchers have no resources; Windows shortcuts use a sibling ICO
        // or the actual program's resources instead. Never execute the program.
        let folder = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        var stems = [stem]
        if stem.lowercased().hasPrefix("launch"), stem.count > 6 {
            stems.append(String(stem.dropFirst(6)))
        }
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for candidate in stems {
            if let ico = files.first(where: { $0.lastPathComponent.lowercased() == (candidate + ".ico").lowercased() }),
               let image = NSImage(contentsOf: ico) { return image }
        }
        for candidate in stems.dropFirst() {
            if let exe = files.first(where: { $0.lastPathComponent.lowercased() == (candidate + ".exe").lowercased() }),
               let data = try? Data(contentsOf: exe, options: .mappedIfSafe),
               let pe = PEFile(data), let icon = pe.mainIcon() { return icon }
        }
        let icoFiles = files.filter { $0.pathExtension.lowercased() == "ico" }
        return icoFiles.count == 1 ? NSImage(contentsOf: icoFiles[0]) : nil
    }
}

private struct PEFile {
    private let data: Data
    private let sections: [(virtualAddress: Int, virtualSize: Int, rawOffset: Int, rawSize: Int)]
    private let resourceBase: Int

    private static let iconType = 3, groupIconType = 14

    init?(_ data: Data) {
        self.data = data
        guard data.count > 0x40, data.u16(0) == 0x5A4D else { return nil }          // MZ
        let pe = Int(data.u32(0x3C))
        guard pe + 24 <= data.count, data.u32(pe) == 0x0000_4550 else { return nil } // PE\0\0
        let coff = pe + 4
        let sectionCount = Int(data.u16(coff + 2))
        let optionalSize = Int(data.u16(coff + 16))
        let optional = coff + 20
        // data directories start after the standard fields; entry 2 is the resource table
        let directories = optional + (data.u16(optional) == 0x20B ? 112 : 96)
        guard directories + 24 <= data.count else { return nil }
        let resourceRVA = Int(data.u32(directories + 16))
        var table = optional + optionalSize
        var list: [(Int, Int, Int, Int)] = []
        for _ in 0..<sectionCount where table + 40 <= data.count {
            list.append((Int(data.u32(table + 12)), Int(data.u32(table + 8)), Int(data.u32(table + 20)), Int(data.u32(table + 16))))
            table += 40
        }
        sections = list.map { (virtualAddress: $0.0, virtualSize: $0.1, rawOffset: $0.2, rawSize: $0.3) }
        guard resourceRVA != 0, let base = PEFile.offset(of: resourceRVA, in: sections) else { return nil }
        resourceBase = base
    }

    private static func offset(of rva: Int, in sections: [(virtualAddress: Int, virtualSize: Int, rawOffset: Int, rawSize: Int)]) -> Int? {
        for s in sections where rva >= s.virtualAddress && rva < s.virtualAddress + max(s.virtualSize, s.rawSize) {
            return rva - s.virtualAddress + s.rawOffset
        }
        return nil
    }

    /// (numeric id or nil for a named entry, offset from the resource base, points at a subdirectory)
    private func entries(_ directory: Int) -> [(id: Int?, target: Int, isDirectory: Bool)] {
        let at = resourceBase + directory
        guard at + 16 <= data.count else { return [] }
        let count = Int(data.u16(at + 12)) + Int(data.u16(at + 14))
        return (0..<count).compactMap { index in
            let entry = at + 16 + index * 8
            guard entry + 8 <= data.count else { return nil }
            let name = data.u32(entry), offset = data.u32(entry + 4)
            return (id: name & 0x8000_0000 != 0 ? nil : Int(name), target: Int(offset & 0x7FFF_FFFF),
                    isDirectory: offset & 0x8000_0000 != 0)
        }
    }

    /// Data of type/name in its first language; the first entry of that type when name is nil.
    private func resource(type: Int, name: Int?) -> Data? {
        guard let typeDir = entries(0).first(where: { $0.id == type && $0.isDirectory }) else { return nil }
        let names = entries(typeDir.target)
        guard let nameDir = (name == nil ? names.first : names.first { $0.id == name }), nameDir.isDirectory,
              let language = entries(nameDir.target).first, !language.isDirectory else { return nil }
        let leaf = resourceBase + language.target
        guard leaf + 8 <= data.count, let start = PEFile.offset(of: Int(data.u32(leaf)), in: sections) else { return nil }
        let size = Int(data.u32(leaf + 4))
        guard start >= 0, size > 0, start + size <= data.count else { return nil }
        return data.subdata(in: data.startIndex + start ..< data.startIndex + start + size)
    }

    /// The largest image of the first icon group, which Explorer shows for the file.
    func mainIcon() -> NSImage? {
        guard let group = resource(type: PEFile.groupIconType, name: nil), group.count >= 6 else { return nil }
        var best: (size: Int, bits: Int, id: Int)?
        for index in 0..<Int(group.u16(4)) {
            let entry = 6 + index * 14
            guard entry + 14 <= group.count else { break }
            let width = group.u8(entry) == 0 ? 256 : Int(group.u8(entry))
            let bits = Int(group.u16(entry + 6)), id = Int(group.u16(entry + 12))
            if best == nil || (width, bits) > (best!.size, best!.bits) { best = (width, bits, id) }
        }
        guard let best, let image = resource(type: PEFile.iconType, name: best.id) else { return nil }
        if image.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return NSImage(data: image) }
        // a bare DIB: wrap it in a one-image .ico, which ImageIO reads
        var ico = Data([0, 0, 1, 0, 1, 0])
        let side = UInt8(best.size >= 256 ? 0 : best.size)
        ico.append(contentsOf: [side, side, 0, 0])
        ico.appendLE(UInt16(1))
        ico.appendLE(UInt16(best.bits))
        ico.appendLE(UInt32(image.count))
        ico.appendLE(UInt32(22))
        ico.append(image)
        return NSImage(data: ico)
    }
}

private extension Data {
    func u8(_ offset: Int) -> UInt8 { self[startIndex + offset] }
    func u16(_ offset: Int) -> UInt16 { UInt16(u8(offset)) | UInt16(u8(offset + 1)) << 8 }
    func u32(_ offset: Int) -> UInt32 { UInt32(u16(offset)) | UInt32(u16(offset + 2)) << 16 }

    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
