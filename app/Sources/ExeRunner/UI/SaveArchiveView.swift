import AppKit
import SwiftUI

/// Each selection is a real Finder panel; no automatic traversal of Documents or game folders.
struct SaveArchiveView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    let item: LibraryItem
    @State private var saves: URL?
    @State private var archive: URL?
    @State private var busy = false
    @State private var message = ""
    @State private var pending: SaveArchive.Plan?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(t("Копии сохранений")).font(.title2)
            Text(item.name).font(.headline)
            Text(t("Закрой игру и её лаунчер. Выбери только папку сохранений, а не игру целиком. Папку нужно указать вручную; облачная синхронизация не выполняется."))
                .foregroundStyle(.secondary)
            Button(t("Выбрать папку сохранений…")) {
                saves = FilePicker.choose(files: false, folders: true, prompt: t("Выбрать папку сохранений"))
            }
            if let saves { Text(saves.path).font(.caption).textSelection(.enabled) }
            HStack {
                Button(t("Создать копию…")) { export() }.disabled(saves == nil)
                Button(t("Выбрать копию…")) {
                    archive = FilePicker.choose(files: false, folders: true, prompt: t("Выбрать копию"))
                }
            }
            if let archive { Text(archive.path).font(.caption).textSelection(.enabled) }
            Button(t("Проверить восстановление…")) { preview() }.disabled(saves == nil || archive == nil)
            Text(t("До 256 МБ и 10 000 файлов. Ссылки и исполняемые файлы не копируются. При восстановлении лишние файлы не удаляются; перед заменой обязательна отдельная страховочная копия."))
                .font(.callout).foregroundStyle(.secondary)
            if busy { ProgressView().controlSize(.small) }
            if !message.isEmpty { Text(message).font(.callout).textSelection(.enabled) }
            HStack { Spacer(); Button(t("Готово")) { dismiss() }.keyboardShortcut(.cancelAction) }
        }
        .padding(24).frame(width: 620).disabled(busy)
        .alert(t("Восстановить сохранения?"), isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button(t("Отмена"), role: .cancel) { pending = nil }
            Button(t("Восстановить"), role: .destructive) {
                guard let plan = pending else { return }; pending = nil
                guard let parent = FilePicker.choose(files: false, folders: true, prompt: t("Куда сохранить страховочную копию")) else { return }
                perform {
                    let result = try SaveArchive.restore(plan, safetyParent: parent)
                    return t("Восстановлено файлов:") + " \(result.files)\n" + t("Страховочная копия:") + "\n" + result.safetyCopy.path
                }
            }
        } message: {
            if let plan = pending {
                Text(t("Файлов в копии:") + " \(plan.manifest.files.count)\n" + t("Будет заменено файлов:") + " \(plan.replacing)\n" + plan.destination.path)
            }
        }
    }

    private func export() {
        guard let source = saves,
              let parent = FilePicker.choose(files: false, folders: true, prompt: t("Куда сохранить копию")) else { return }
        perform {
            let result = try SaveArchive.create(itemID: item.id, source: source, parent: parent)
            return t("Копия сохранена:") + "\n" + result.path
        }
    }
    private func preview() {
        guard let source = saves, let archive else { return }
        // Preview is read-only and binds file hashes, target and item ID to confirmation.
        busy = true; message = ""
        let id = item.id
        Task { @MainActor in
            defer { busy = false }
            do { pending = try await Task.detached { try SaveArchive.plan(archive: archive, itemID: id, destination: source) }.value }
            catch { message = error.localizedDescription }
        }
    }
    private func perform(_ operation: @escaping () throws -> String) {
        busy = true; message = ""
        Task { @MainActor in
            defer { busy = false }
            do {
                let bottle = Bottle(name: item.bottle, root: state.bottlesRoot)
                // Same cooperative cross-process lock checked by every ExeRunner Wine launch.
                guard !state.isShuttingDown, !state.running.contains(where: { state.item($0)?.bottle == item.bottle }),
                      FileManager.default.fileExists(atPath: bottle.url.path) else {
                    throw AppError(t("Закрой все программы этой Windows-среды перед копированием сохранений."))
                }
                let lease = try PrefixComponentLease.installation(in: bottle.url)
                defer { lease.release() }
                guard !WineProcesses.list(includeServers: true).contains(where: { $0.prefix == bottle.prefixPath }) else {
                    throw AppError(t("Закрой все программы этой Windows-среды перед копированием сохранений."))
                }
                message = try await state.saveOperations.perform(operation)
            } catch { message = error.localizedDescription }
        }
    }
}
