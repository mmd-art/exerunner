import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct StatusRow: View {
    enum Level { case ok, warning, missing, info }
    let title: String
    let detail: String
    let level: Level

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if !detail.isEmpty {
                    Text(detail).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var symbol: String {
        switch level {
        case .ok: "checkmark.circle"
        case .warning: "exclamationmark.triangle"
        case .missing: "xmark.circle"
        case .info: "info.circle"
        }
    }

    private var color: Color {
        switch level {
        case .ok: .green
        case .warning: .orange
        case .missing: .red
        case .info: .secondary
        }
    }
}

struct Badge: View {
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.14)))
            .foregroundStyle(tint)
    }
}

struct RecipeStatusBadge: View {
    let status: Recipe.Status

    var body: some View {
        switch status {
        case .tested: Badge(text: "Проверено", tint: .green)
        case .experimental: Badge(text: "Экспериментально", tint: .orange)
        case .planned: Badge(text: "Скоро")
        }
    }
}

struct VerdictBadge: View {
    let profile: GameProfile

    var body: some View {
        switch profile.verdict {
        case .good: Badge(text: profile.ratingTitle, tint: .green)
        case .caution: Badge(text: profile.antiCheat.map { "Античит \($0)" } ?? profile.ratingTitle, tint: .orange)
        case .bad: Badge(text: profile.ratingTitle, tint: .red)
        case .unknown: Badge(text: profile.ratingTitle)
        }
    }
}

/// Everything the compatibility database says about one game.
struct GameProfileDetails: View {
    let profile: GameProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                VerdictBadge(profile: profile)
                if let antiCheat = profile.antiCheat, profile.verdict != .caution { Badge(text: "Античит \(antiCheat)", tint: .orange) }
                Badge(text: profile.storeTitle)
            }
            if let label = profile.recommended.label {
                Text(label).font(.headline)
            }
            if let when = profile.recommended.whenToUse { Text(when).foregroundStyle(.secondary) }
            Text("Графика: \(profile.recommended.graphics.title)")
            if !profile.recommended.winetricks.isEmpty {
                Text("Компоненты Windows: \(profile.recommended.winetricks.joined(separator: ", "))")
            }
            if !profile.recommended.environment.isEmpty {
                Text("Переменные: " + profile.recommended.environment.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
                    .font(.callout.monospaced())
            }
            if !profile.notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(profile.notes, id: \.self) { Text("· \($0)").foregroundStyle(.secondary) }
                }
            }
            if !profile.issues.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Известные проблемы").font(.headline)
                    ForEach(profile.issues, id: \.self) { issue in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(issue.text ?? "")
                            if let fix = issue.workaround { Text("Что делать: \(fix)").font(.callout).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            Text("Источник: база игр Whisky (frankea/Whisky, GPL-3). Оценки там во многом не проверены.")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .textSelection(.enabled)
    }
}

struct DropZone: View {
    let title: String
    let subtitle: String
    let onDrop: (URL) -> Void
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(subtitle).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 140)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .foregroundStyle(targeted ? Color.accentColor : Color.secondary.opacity(0.45))
        )
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            onDrop(url)
            return true
        } isTargeted: { targeted = $0 }
    }
}

struct ActivityBar: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        if let text = state.activity {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(text).font(.callout)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }
}

/// Actions are pills: a filled one for the main action, a tinted one for the rest.
struct PillButtonStyle: ButtonStyle {
    var prominent = false
    var compact = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? .callout.weight(.medium) : .body.weight(.medium))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, compact ? 11 : 16)
            .padding(.vertical, compact ? 4 : 7)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background(Capsule().fill(prominent ? Color.accentColor : Color.secondary.opacity(0.16)))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
            .contentShape(Capsule())
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle { PillButtonStyle() }
    static var pillProminent: PillButtonStyle { PillButtonStyle(prominent: true) }
    static var pillCompact: PillButtonStyle { PillButtonStyle(compact: true) }
    static var pillCompactProminent: PillButtonStyle { PillButtonStyle(prominent: true, compact: true) }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(nsColor: .separatorColor).opacity(0.6)))
    }
}

/// NSOpenPanel instead of SwiftUI's fileImporter: several pickers per screen, and a start folder.
@MainActor
enum FilePicker {
    static func choose(files: Bool = true, folders: Bool = false, startAt: URL? = nil, prompt: String = "Выбрать") -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = files
        panel.canChooseDirectories = folders
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        if let startAt { panel.directoryURL = startAt }
        return panel.runModal() == .OK ? panel.url : nil
    }
}
