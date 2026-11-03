import SwiftUI

struct StorageButton: View {
    @EnvironmentObject private var state: AppState
    let item: LibraryItem?
    @State private var showing = false
    var body: some View {
        Button { showing = true } label: {
            if state.storageScanning { ProgressView().controlSize(.mini).frame(width: 60) }
            else if let snapshot = state.storage {
                if let item {
                    Text(snapshot.unknownItems.contains(item.id) ? t("Размер…") :
                        snapshot.ownBytes(item.id) == 0 && snapshot.shared(for: item.id).contains(where: { $0.kind == .shared && $0.bytes > 0 }) ? t("Общие файлы") :
                        (snapshot.incomplete ? "≈ " : "") + StorageDetails.bytes(snapshot.ownBytes(item.id)))
                } else { Label((snapshot.incomplete ? "≈ " : "") + StorageDetails.bytes(snapshot.totalBytes), systemImage: "internaldrive") }
            } else { Text(t("Размер…")) }
        }
        .buttonStyle(.plain).foregroundStyle(.secondary).monospacedDigit()
        .help(t("Размер файлов и разбивка. Общие файлы не прибавляются к каждой программе."))
        .popover(isPresented: $showing) { StorageDetails(item: item).environmentObject(state) }
    }
}

struct StorageDetails: View {
    @EnvironmentObject private var state: AppState
    let item: LibraryItem?
    @State private var message = ""
    static func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .file) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(t("Размер файлов")).font(.headline)
                Spacer()
                Button { state.refreshStorage() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).disabled(state.storageScanning).help(t("Пересчитать размер"))
            }
            if state.storageScanning { ProgressView(t("Подсчёт размера…")).controlSize(.small) }
            if let snapshot = state.storage {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if let item {
                            Text(item.name).font(.subheadline.bold())
                            if snapshot.unknownItems.contains(item.id) {
                                Text(t("Папка установки неизвестна. По одному EXE нельзя определить полный размер программы."))
                            } else {
                                row(t("Файлы программы"), snapshot.exclusive(item.id, .application))
                                row(t("Кэш программы"), snapshot.exclusive(item.id, .cache))
                                Divider()
                                row(t("Размер карточки"), snapshot.ownBytes(item.id))
                            }
                            if let folder = snapshot.selectedFolders[item.id] {
                                Text(folder).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(3)
                            }
                            Button(t("Указать папку программы…")) { choose(item) }
                            let games = Set(state.allItems.filter { $0.isSteamGame && $0.bottle == item.bottle }.map(\.id))
                            if item.kind == .launcher && item.recipeID == "steam" {
                                let gameBytes = snapshot.buckets.values.filter { $0.kind == .application && !$0.owners.isDisjoint(with: games) }.reduce(Int64(0)) { $0 + $1.bytes }
                                row(t("Игры Steam — отдельно"), gameBytes)
                            }
                            let shared = snapshot.shared(for: item.id).filter { $0.bytes > 0 }
                            if !shared.isEmpty {
                                Divider()
                                Text(t("Отдельно — не включено в размер карточки")).font(.caption.bold())
                                ForEach(shared, id: \.id) { bucket in row(title(bucket), bucket.bytes) }
                            }
                        } else {
                            Text(t("Всего в учтённых папках")).font(.subheadline)
                            row(t("Всего, без повторов"), snapshot.totalBytes)
                            Divider()
                            ForEach([StorageScan.Kind.application, .cache, .environment, .runtime, .data, .shared], id: \.rawValue) { kind in
                                row(title(.init(id: "", kind: kind, owners: [])), snapshot.buckets.values.filter { $0.kind == kind }.reduce(0) { $0 + $1.bytes })
                            }
                            if !snapshot.unknownItems.isEmpty { Text(t("У некоторых программ папка установки неизвестна. Их файлы внутри учтённой Windows-среды остаются в категории общих данных.")) }
                        }
                        if snapshot.incomplete {
                            Label(t("Неполный замер: часть папок недоступна или достигнут лимит. Это не полный размер."), systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                        if snapshot.skippedLinks > 0 { Text(t("Ссылки на другие папки не раскрываются. Внешние установки можно указать явно.")) }
                        Text(t("Общие файлы учтены один раз. Размер файлов не равен месту, которое освободится при удалении; APFS, снимки и корзина влияют на результат."))
                        Text(snapshot.date, style: .time).foregroundStyle(.secondary)
                    }
                    .font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 440)
            }
            if !message.isEmpty { Text(message).font(.callout).foregroundStyle(.orange) }
        }.padding(18).frame(width: 380)
    }
    private func row(_ name: String, _ amount: Int64) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 14)
            Text(Self.bytes(amount)).monospacedDigit().fixedSize()
        }
    }
    private func title(_ bucket: StorageScan.Bucket) -> String {
        if bucket.id.hasPrefix("steam-data:") { return t("Данные и загрузки Steam") }
        if bucket.id == "runner-cache" { return t("Общий кэш ExeRunner") }
        switch bucket.kind {
        case .application: return t("Файлы программ и игр")
        case .cache: return t("Кэш")
        case .environment: return t("Windows-среда и прочие файлы")
        case .runtime: return t("ExeRunner и движки")
        case .data: return t("Другие данные и журналы")
        case .shared: return t("Общие файлы программ")
        }
    }
    private func choose(_ item: LibraryItem) {
        guard let folder = FilePicker.choose(files: false, folders: true, prompt: t("Выбрать папку программы")) else { return }
        do { try state.selectStorageFolder(for: item, folder: folder); message = "" }
        catch { message = error.localizedDescription }
    }
}
