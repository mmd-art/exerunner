import Foundation

/// The interface language: Russian, English, or the Mac's (Russian on a Mac set to Russian,
/// English anywhere else).
enum InterfaceLanguage: String, Codable, CaseIterable, Identifiable {
    case system, russian, english
    var id: String { rawValue }
}

/// The app's texts are written in Russian where they are used; `t("…")` gives the English one
/// from `English.table` when the interface is in English. A text with values in it is looked up
/// with %@ in their place ("Устанавливаю %@…"), and the values go back in after.
enum L10n {
    nonisolated(unsafe) private(set) static var english = false

    static func use(_ language: InterfaceLanguage) {
        switch language {
        case .russian: english = false
        case .english: english = true
        case .system: english = !(Locale.preferredLanguages.first ?? "en").lowercased().hasPrefix("ru")
        }
    }

    /// Puts values into a text: %@ in order, or %1$@, %2$@ … where a translation reorders them
    static func fill(_ format: String, _ values: [String]) -> String {
        guard !values.isEmpty else { return format }
        var result = "", next = 0
        var rest = format[...]
        while let percent = rest.firstIndex(of: "%") {
            result += rest[..<percent]
            let after = rest[rest.index(after: percent)...]
            if after.hasPrefix("@") {
                result += next < values.count ? values[next] : ""
                next += 1
                rest = after.dropFirst()
            } else if let digit = after.first, let n = digit.wholeNumberValue, after.dropFirst().hasPrefix("$@") {
                result += n >= 1 && n <= values.count ? values[n - 1] : ""
                rest = after.dropFirst(3)
            } else {
                result += "%"
                rest = after
            }
        }
        return result + rest
    }
}

/// A text as written in the code, interpolations kept apart from the words around them
struct LocalizedText: ExpressibleByStringInterpolation {
    var key: String
    var values: [String]

    init(stringLiteral value: String) {
        key = value
        values = []
    }

    init(stringInterpolation: StringInterpolation) {
        key = stringInterpolation.key
        values = stringInterpolation.values
    }

    struct StringInterpolation: StringInterpolationProtocol {
        var key = ""
        var values: [String] = []
        init(literalCapacity: Int, interpolationCount: Int) {}
        mutating func appendLiteral(_ literal: String) { key += literal }
        mutating func appendInterpolation<T>(_ value: T) {
            key += "%@"
            values.append("\(value)")
        }
    }
}

/// The text in the interface's language
func t(_ text: LocalizedText) -> String {
    let format = L10n.english ? (English.table[text.key] ?? text.key) : text.key
    return L10n.fill(format, text.values)
}
