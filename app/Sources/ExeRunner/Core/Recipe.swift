import Foundation

/// A catalog entry: how to install and run one launcher or program. Same line format that
/// scripts/run.sh reads, one directive per line:
///
///   name Steam                      kind launcher|program|game    status tested|experimental|planned
///   about <one line for the catalog>  symbol <SF Symbol>          bottle <bottle name>
///   installer <url> [args...]       sha256 <hex>                  exe <Windows path>
///   games steam                     env NAME=value                dxvk program.exe
///   dll program.exe name=mode,...   (an empty mode disables; msvcp140=native,builtin keeps wine's order)
///   shutdown <args to quit the client>
struct Recipe: Identifiable, Hashable {
    enum Kind: String { case launcher, program, game }
    enum Status: String { case tested, experimental, planned }

    let id: String
    var name: String
    var kind: Kind = .program
    var status: Status = .experimental
    var about = ""
    var symbol = "app"
    var bottle: String
    var installerURL: URL?
    var installerArguments: [String] = []
    var installerSHA256: String?
    var executable: String?
    var discoversSteamGames = false
    var environment: [String: String] = [:]
    var dxvkExecutables: [String] = []
    /// program -> dll -> mode, on top of DXVK's
    var dllOverrides: [String: [String: String]] = [:]
    /// Arguments that make a running client quit by itself (Steam's -shutdown)
    var shutdownArguments: [String] = []

    static func == (a: Recipe, b: Recipe) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    static func parse(id: String, text: String) throws -> Recipe {
        var recipe = Recipe(id: id, name: id, bottle: id)
        for (number, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            let key = parts[0], value = parts.count > 1 ? parts[1] : ""
            func bad() -> AppError { AppError("\(id).recipe, строка \(number + 1): не понимаю «\(line)»") }
            switch key {
            case "name": recipe.name = value
            case "kind": guard let kind = Kind(rawValue: value) else { throw bad() }; recipe.kind = kind
            case "status": guard let status = Status(rawValue: value) else { throw bad() }; recipe.status = status
            case "about": recipe.about = value
            case "symbol": recipe.symbol = value
            case "bottle": recipe.bottle = value
            case "installer":
                let words = value.split(separator: " ").map(String.init)
                guard let first = words.first, let url = URL(string: first) else { throw bad() }
                recipe.installerURL = url
                recipe.installerArguments = Array(words.dropFirst())
            case "sha256": recipe.installerSHA256 = value.lowercased()
            case "exe": recipe.executable = value
            case "games": guard value == "steam" else { throw bad() }; recipe.discoversSteamGames = true
            case "env":
                guard let eq = value.firstIndex(of: "="), eq != value.startIndex else { throw bad() }
                recipe.environment[String(value[..<eq])] = String(value[value.index(after: eq)...])
            case "dxvk": recipe.dxvkExecutables.append(value)
            case "dll":
                // the program's name may hold spaces; the overrides are the last word
                guard let space = value.lastIndex(of: " ") else { throw bad() }
                let exe = String(value[..<space])
                // pairs are split on commas, as wine writes a load order with them: a word
                // without "=" continues the mode before it (msvcp140=native,builtin)
                var last: String?
                for pair in value[value.index(after: space)...].split(separator: ",", omittingEmptySubsequences: false) {
                    guard let eq = pair.firstIndex(of: "=") else {
                        guard let dll = last, !pair.isEmpty else { throw bad() }
                        recipe.dllOverrides[exe]![dll]! += "," + pair
                        continue
                    }
                    guard eq != pair.startIndex else { throw bad() }
                    last = String(pair[..<eq])
                    recipe.dllOverrides[exe, default: [:]][last!] = String(pair[pair.index(after: eq)...])
                }
            case "shutdown": recipe.shutdownArguments = value.split(separator: " ").map(String.init)
            default: throw bad()
            }
        }
        return recipe
    }

    static func loadAll() -> [Recipe] {
        guard let dir = Paths.recipes,
              let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        let order: [Status] = [.tested, .experimental, .planned]
        return names.filter { $0.hasSuffix(".recipe") }.compactMap { name in
            let id = String(name.dropLast(".recipe".count))
            do {
                return try parse(id: id, text: String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8))
            } catch {
                NSLog("\(error.localizedDescription)")
                return nil
            }
        }.sorted {
            (order.firstIndex(of: $0.status)!, $0.name) < (order.firstIndex(of: $1.status)!, $1.name)
        }
    }
}
