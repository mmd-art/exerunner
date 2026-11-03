import SwiftUI

struct GameRemovalView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    let item: LibraryItem
    @State private var saves = false
    @State private var wizardConfirmation = false
    @State private var plan: GameRemoval.Plan?
    @State private var busy = false
    @State private var message = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(t("Удалить установленную игру или программу")).font(.title2.bold())
            Text(item.name).font(.headline)
            Text(t("Убрать карточку — не значит удалить файлы. Здесь можно открыть штатный мастер удаления или переместить отдельную папку игры в корзину."))
            Button(t("Сначала сохранить копию сейвов…")) { saves = true }
            Text(t("Штатный мастер может предложить удалить настройки и сейвы. Сохрани копию перед продолжением. Отмена мастера не удаляет карточку."))
                .font(.callout).foregroundStyle(.secondary)
            Button(t("Открыть мастер удаления…")) { wizardConfirmation = true }
            if !item.isSteamGame && item.kind != .launcher {
                Divider()
                Text(t("Игра без установщика")).font(.headline)
                Button(t("Выбрать папку игры для корзины…")) { chooseFolder() }
                Text(t("Папку выбираешь ты. Сейвы внутри неё тоже попадут в корзину; сейвы вне папки останутся. Место освободится только после очистки корзины macOS."))
                    .font(.callout).foregroundStyle(.secondary)
            }
            if busy { ProgressView() }
            if !message.isEmpty { Text(message).textSelection(.enabled).font(.callout) }
            HStack { Spacer(); Button(t("Готово")) { dismiss() }.keyboardShortcut(.cancelAction) }
        }
        .padding(24).frame(width: 600).disabled(busy)
        .sheet(isPresented: $saves) { SaveArchiveView(item: item).environmentObject(state) }
        .alert(t("Открыть мастер удаления?"), isPresented: $wizardConfirmation) {
            Button(t("Отмена"), role: .cancel) {}
            Button(t("Открыть мастер удаления"), role: .destructive) {
                perform { try await state.openUninstaller(item); message = t("Мастер закрыт. Проверь результат; отмена не считается удалением.") }
            }
        } message: {
            Text(item.isSteamGame ? t("Steam запросит подтверждение удаления выбранной игры.") : t("Откроется список установленных Windows-программ этой среды. Выбери нужную программу; другие программы не удаляй."))
        }
        .alert(t("Переместить папку игры в корзину?"), isPresented: Binding(get: { plan != nil }, set: { if !$0 { plan = nil } })) {
            Button(t("Отмена"), role: .cancel) { plan = nil }
            Button(t("Переместить в корзину"), role: .destructive) {
                guard let selected = plan else { return }; plan = nil
                perform { try await state.trashInstallation(item, plan: selected); dismiss() }
            }
        } message: {
            Text((plan?.folder.path ?? "") + "\n\n" + t("Будут перемещены все файлы этой папки, включая сейвы внутри неё, и убрана карточка. Сейвы вне папки не затрагиваются. Для освобождения места потребуется очистить корзину macOS."))
        }
    }
    private func chooseFolder() {
        guard let folder = FilePicker.choose(files: false, folders: true, prompt: t("Выбрать папку игры")) else { return }
        do { plan = try state.removalPlan(item, folder: folder) }
        catch { message = error.localizedDescription }
    }
    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        busy = true; message = ""
        Task { @MainActor in
            defer { busy = false }
            do { try await action() } catch { message = error.localizedDescription }
        }
    }
}
