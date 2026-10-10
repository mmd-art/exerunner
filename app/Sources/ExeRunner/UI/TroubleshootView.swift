import AppKit
import SwiftUI

/// The helper: pick what is wrong, the app checks what it can and offers what it can do about
/// it; a report for someone else to look at is one button away.
struct TroubleshootView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    let itemID: String
    @State private var selection: Symptom?
    @State private var checks: [Check]
    @State private var loading = false
    @State private var working: Remedy?
    @State private var report: URL?

    /// `checks` shows results right away instead of running the checks (snapshots)
    init(itemID: String, symptom: Symptom = .launch, checks: [Check]? = nil) {
        self.itemID = itemID
        _selection = State(initialValue: symptom)
        _checks = State(initialValue: checks ?? [])
        preset = checks != nil
    }

    private let preset: Bool
    private var item: LibraryItem? { state.item(itemID) }
    private var symptom: Symptom { selection ?? .launch }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                List(Symptom.allCases, selection: $selection) { symptom in
                    Label(symptom.title, systemImage: symptom.symbol).tag(symptom)
                }
                .listStyle(.sidebar)
                .frame(width: 250)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(symptom.title).font(.title2.weight(.semibold))
                            Text(item.map { t("«\($0.name)», бутылка «\($0.bottle)»") } ?? "").foregroundStyle(.secondary)
                        }
                        .padding(.bottom, 6)
                        if loading && checks.isEmpty {
                            ProgressView(t("Проверяю…")).frame(maxWidth: .infinity).padding(.top, 60)
                        }
                        ForEach(checks) { check in
                            CheckRow(check: check, working: working) { remedy in Task { await apply(remedy) } }
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Divider()
            HStack(spacing: 10) {
                Button { Task { await saveReport() } } label: { Label(t("Сохранить отчёт для помощи"), systemImage: "doc.zipper") }
                if let report {
                    Button(t("Показать в Finder")) { NSWorkspace.shared.activateFileViewerSelecting([report]) }
                    Text(report.lastPathComponent).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Button(t("Проверить снова")) { Task { await load() } }.disabled(loading)
                Button(t("Готово")) { dismiss() }
                    .buttonStyle(.pillProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .buttonStyle(.pill)
            .padding(16)
        }
        .frame(width: 860, height: 600)
        .task(id: selection) {
            if preset && !checks.isEmpty { return }
            await load()
        }
    }

    private func load() async {
        guard let item else { return }
        loading = true
        checks = await state.checks(for: symptom, item: item)
        loading = false
    }

    private func apply(_ remedy: Remedy) async {
        working = remedy
        await state.apply(remedy, to: itemID)
        working = nil
        await load()
    }

    private func saveReport() async {
        guard let item else { return }
        report = await state.exportReport(for: item, checks: checks)
    }
}

private struct CheckRow: View {
    let check: Check
    let working: Remedy?
    let apply: (Remedy) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 6) {
                Text(check.title).font(.headline)
                Text(check.detail).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(notes, id: \.self) { note in
                    Label(note, systemImage: "lightbulb").font(.callout).fixedSize(horizontal: false, vertical: true)
                }
                if !actions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(actions) { remedy in
                            Button {
                                apply(remedy)
                            } label: {
                                HStack(spacing: 6) {
                                    if working == remedy { ProgressView().controlSize(.small) }
                                    Text(remedy.action ?? "")
                                }
                            }
                            .buttonStyle(.pillCompact)
                            .disabled(working != nil)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor).opacity(0.6)))
    }

    private var actions: [Remedy] { check.remedies.filter { $0.action != nil } }

    private var notes: [String] {
        check.remedies.compactMap { if case .note(let text) = $0 { return text } else { return nil } }
    }

    private var symbol: String {
        switch check.status {
        case .ok: "checkmark.circle.fill"
        case .info: "info.circle"
        case .warning: "exclamationmark.triangle.fill"
        case .problem: "xmark.octagon.fill"
        }
    }

    private var tint: Color {
        switch check.status {
        case .ok: .green
        case .info: .secondary
        case .warning: .orange
        case .problem: .red
        }
    }
}
