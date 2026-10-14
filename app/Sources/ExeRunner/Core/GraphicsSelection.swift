import Foundation

/// A deterministic recommendation, not an unmeasured automatic benchmark.
enum GraphicsSelection {
    static func profile(for item: LibraryItem, in profiles: [GameProfile]) -> GameProfile? {
        // Imported legacy records are game profiles. A common Launcher.exe filename
        // must not apply an unrelated game's overrides to a standalone app or store client.
        let candidates = profiles.filter { ($0.kind ?? .game) == item.kind }
        if let appID = item.steamAppID { return candidates.first { $0.steamAppID == appID } }
        return candidates.first { $0.exeNames.contains { $0.caseInsensitiveCompare(item.executableName) == .orderedSame } }
    }
    static func resolve(_ item: LibraryItem, profile: GameProfile?, hasD3DMetal: Bool) -> LibraryItem.Graphics {
        if item.graphics != .automatic { return item.graphics }
        if item.useRecommended, let choice = profile?.recommended.graphics, choice != .automatic { return choice }
        return hasD3DMetal ? .d3dmetal : .wine
    }
    static func explanation(_ item: LibraryItem, profile: GameProfile?, hasD3DMetal: Bool) -> String {
        let choice = resolve(item, profile: profile, hasD3DMetal: hasD3DMetal)
        if item.graphics != .automatic { return t("Выбран вручную: \(choice.title).") }
        if item.useRecommended, let profile {
            return t("Авто: \(choice.title). Профиль: \(profile.title).")
        }
        return t("Авто: \(choice.title). Проверенного профиля для программы нет; это запасной вариант.")
    }
    static func allowsMetalFX(graphics: LibraryItem.Graphics, profile: GameProfile?, hasD3DMetal: Bool) -> Bool {
        hasD3DMetal && [.automatic, .d3dmetal].contains(graphics) && profile?.features?.dlss != false
    }
    static func supportsDXMT(profile: GameProfile?) -> Bool {
        !["d3d9", "d3d12"].contains(profile?.graphicsAPI ?? "")
    }
    static func allowsDXR(graphics: LibraryItem.Graphics, profile: GameProfile?, hasD3DMetal: Bool) -> Bool {
        hasD3DMetal && [.automatic, .d3dmetal].contains(graphics) &&
        profile?.graphicsAPI != "d3d11" && profile?.graphicsAPI != "d3d10" &&
        profile?.graphicsAPI != "d3d9" && profile?.features?.dxr != false
    }
}
