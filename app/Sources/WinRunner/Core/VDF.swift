import Foundation

/// Valve's KeyValues text format ("key" "value" and "key" { ... }), which Steam uses for its
/// manifests and library list. Keys match without regard to case, as in Steam.
enum VDF {
    case string(String)
    case block([(key: String, value: VDF)])

    static func parse(_ text: String) -> VDF {
        var tokens = Tokenizer(text)
        return .block(entries(&tokens))
    }

    subscript(key: String) -> VDF? {
        entries.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value
    }

    var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var entries: [(key: String, value: VDF)] {
        if case .block(let entries) = self { return entries }
        return []
    }

    private static func entries(_ tokens: inout Tokenizer) -> [(key: String, value: VDF)] {
        var result: [(key: String, value: VDF)] = []
        while let token = tokens.next() {
            guard case .text(let key) = token else {
                if case .close = token { break }
                continue
            }
            // platform conditions such as [$WIN32] follow a value; they are not keys
            if key.hasPrefix("[") { continue }
            guard let value = tokens.next() else { break }
            switch value {
            case .open: result.append((key, .block(entries(&tokens))))
            case .text(let text): result.append((key, .string(text)))
            case .close: return result
            }
        }
        return result
    }

    private struct Tokenizer {
        enum Token { case open, close, text(String) }

        private let bytes: [UInt8]
        private var index = 0

        init(_ text: String) { bytes = Array(text.utf8) }

        mutating func next() -> Token? {
            while index < bytes.count {
                let byte = bytes[index]
                switch byte {
                case UInt8(ascii: " "), UInt8(ascii: "\t"), UInt8(ascii: "\n"), UInt8(ascii: "\r"):
                    index += 1
                case UInt8(ascii: "/") where index + 1 < bytes.count && bytes[index + 1] == UInt8(ascii: "/"):
                    while index < bytes.count, bytes[index] != UInt8(ascii: "\n") { index += 1 }
                case UInt8(ascii: "{"):
                    index += 1
                    return .open
                case UInt8(ascii: "}"):
                    index += 1
                    return .close
                case UInt8(ascii: "\""):
                    return .text(quoted())
                default:
                    let start = index
                    while index < bytes.count, !Self.delimiters.contains(bytes[index]) { index += 1 }
                    return .text(String(decoding: bytes[start..<index], as: UTF8.self))
                }
            }
            return nil
        }

        private static let delimiters: Set<UInt8> = [UInt8(ascii: " "), UInt8(ascii: "\t"), UInt8(ascii: "\n"),
                                                     UInt8(ascii: "\r"), UInt8(ascii: "{"), UInt8(ascii: "}"),
                                                     UInt8(ascii: "\"")]

        /// A quoted string; \\ \" \n \t are escapes (Steam writes C:\\Program Files)
        private mutating func quoted() -> String {
            var out: [UInt8] = []
            index += 1
            while index < bytes.count, bytes[index] != UInt8(ascii: "\"") {
                if bytes[index] == UInt8(ascii: "\\"), index + 1 < bytes.count {
                    switch bytes[index + 1] {
                    case UInt8(ascii: "n"): out.append(UInt8(ascii: "\n"))
                    case UInt8(ascii: "t"): out.append(UInt8(ascii: "\t"))
                    default: out.append(bytes[index + 1])
                    }
                    index += 2
                } else {
                    out.append(bytes[index])
                    index += 1
                }
            }
            index += 1
            return String(decoding: out, as: UTF8.self)
        }
    }
}
