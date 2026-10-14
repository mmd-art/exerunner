import Foundation

struct AppSettings: Codable, Equatable {
    var enginePath: String?
    var bottlesPath: String?
    var onboardingCompleted = false
    var language: InterfaceLanguage = .system
    /// nil preserves older per-program choices until the global control is used.
    var performanceHUD: Bool?
    var gameBoost = false
    var cursorConfinement = true
    var automaticNativeResolution = true
    var automaticRuntimeComponents = true

    init() {}

    // settings saved before a field existed keep their other values
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enginePath = try c.decodeIfPresent(String.self, forKey: .enginePath)
        bottlesPath = try c.decodeIfPresent(String.self, forKey: .bottlesPath)
        onboardingCompleted = try c.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? false
        performanceHUD = try c.decodeIfPresent(Bool.self, forKey: .performanceHUD)
        gameBoost = try c.decodeIfPresent(Bool.self, forKey: .gameBoost) ?? false
        cursorConfinement = try c.decodeIfPresent(Bool.self, forKey: .cursorConfinement) ?? true
        automaticNativeResolution = try c.decodeIfPresent(Bool.self, forKey: .automaticNativeResolution) ?? true
        automaticRuntimeComponents = try c.decodeIfPresent(Bool.self, forKey: .automaticRuntimeComponents) ?? true
        // settings from before the choice of language: the interface was Russian then
        language = (try? c.decodeIfPresent(InterfaceLanguage.self, forKey: .language)) ?? .russian
    }

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
