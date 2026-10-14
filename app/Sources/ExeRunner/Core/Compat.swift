import Foundation

/// A game in the compatibility database (compat/games.json, converted from frankea/Whisky's
/// GameDB by tools/import-whisky-gamedb.py): how to recognise it and what it needs.
struct GameProfile: Codable, Identifiable, Hashable {
    struct Variant: Codable, Hashable {
        var label: String?
        var whenToUse: String?
        var graphics: LibraryItem.Graphics
        var environment: [String: String]
        var dllOverrides: [String: String]
        var winetricks: [String]
    }

    struct Issue: Codable, Hashable {
        var severity: String?
        var text: String?
        var workaround: String?
        /// English beside this app's own entries, which are written in Russian
        var textEn: String?
        var workaroundEn: String?

        var localizedText: String? { L10n.english ? (textEn ?? text) : text }
        var localizedWorkaround: String? { L10n.english ? (workaroundEn ?? workaround) : workaround }
    }

    enum Verdict { case good, caution, bad, unknown }

    struct Features: Codable, Hashable {
        var dlss: Bool?
        var dxr: Bool?
    }
    struct Verification: Codable, Hashable {
        var date: String
        var machine: String
        var macOS: String
        var wine: String
        var translator: String
        var level: String
    }
    /// Validated display-file adapter used by the shared automatic screen policy.
    var nativeDisplayProfile: String? = nil
    var profileVersion: Int?
    var source: String?
    var kind: LibraryItem.Kind?
    var graphicsAPI: String?
    var features: Features?
    var verification: Verification?
    var id: String
    var title: String
    var aliases: [String]
    var store: String?
    var steamAppID: Int?
    var exeNames: [String]
    var rating: String
    var antiCheat: String?
    var notes: [String]
    var notesEn: [String]?
    var issues: [Issue]
    var recommended: Variant
    var alternatives: [Variant]

    var localizedNotes: [String] { L10n.english ? (notesEn ?? notes) : notes }

    var verdict: Verdict {
        switch rating {
        case "playable", "works": antiCheat == nil ? .good : .caution
        case "broken", "notSupported": .bad
        default: antiCheat == nil ? .unknown : .caution
        }
    }

    var ratingTitle: String {
        switch rating {
        case "playable": t("Играбельно")
        case "works": t("Работает")
        case "broken": t("Не работает")
        case "notSupported": t("Не поддерживается")
        default: t("Не проверено")
        }
    }

    var storeTitle: String {
        switch store {
        case "steam": "Steam"
        case "epic": "Epic"
        case "gog": "GOG"
        case "battlenet": "Battle.net"
        default: t("другой магазин")
        }
    }

    func matches(_ query: String) -> Bool {
        let q = query.lowercased()
        return title.lowercased().contains(q) || aliases.contains { $0.lowercased().contains(q) }
    }
}

enum CompatDatabase {
    private struct File: Codable {
        var source: String
        var games: [GameProfile]
    }

    /// Whisky's database, then this app's own entries (games-exerunner.json), which replace
    /// Whisky's for the same game
    static func load() -> (source: String, games: [GameProfile]) {
        guard let dir = Paths.compat else { return ("", []) }
        var sources: [String] = []
        var games: [GameProfile] = []
        for name in ["games.json", "games-exerunner.json"] {
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(name)) else { continue }
            do {
                let file = try JSONDecoder().decode(File.self, from: data)
                sources.append(file.source)
                for game in file.games {
                    games.removeAll { $0.id == game.id || ($0.steamAppID != nil && $0.steamAppID == game.steamAppID) }
                    var sourced = game
                    if sourced.source == nil { sourced.source = file.source }
                    games.append(sourced)
                }
            } catch {
                NSLog("\(name): \(error)")
            }
        }
        return (sources.joined(separator: "; "), games)
    }
}
