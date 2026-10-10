import Foundation

struct AppSettings: Codable, Equatable {
    var enginePath: String?
    var bottlesPath: String?
    var onboardingCompleted = false

    var bottlesRoot: URL {
        bottlesPath.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? Paths.defaultBottles
    }

    static func load() -> AppSettings {
        guard let data = try? Data(contentsOf: Paths.settingsFile),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return settings
    }

    func save() {
        do {
            try Paths.ensure(Paths.support)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(self).write(to: Paths.settingsFile, options: .atomic)
        } catch {
            NSLog("settings not saved: \(error)")
        }
    }
}
