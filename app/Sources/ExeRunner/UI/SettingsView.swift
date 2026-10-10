import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Form {
            Section("Mac") {
                StatusRow(title: state.system.chip, detail: "macOS \(state.system.macOS) · \(state.system.memoryGB) ГБ памяти · свободно \(state.system.freeDiskGB) ГБ",
                          level: state.system.supported ? .ok : .missing)
                HStack {
                    StatusRow(title: state.rosettaInstalled ? "Rosetta установлена" : "Rosetta не установлена", detail: "",
                              level: state.rosettaInstalled ? .ok : .missing)
                    if !state.rosettaInstalled {
                        Button("Установить") { Task { await state.installRosetta() } }.buttonStyle(.pill)
                    }
                }
            }

            Section("Движок") {
                if let engine = state.engine {
                    StatusRow(title: state.engineVersion ?? "Версия неизвестна", detail: engine.root.path, level: .ok)
                    StatusRow(title: "Модуль совместимости", detail: "", level: engine.hasCompatModule ? .ok : .missing)
                    StatusRow(title: "DXVK и MoltenVK", detail: "", level: engine.hasDXVK && engine.hasMoltenVK ? .ok : .warning)
                    StatusRow(title: "Mono и Gecko", detail: "", level: engine.hasMonoAndGecko ? .ok : .warning)
                } else {
                    StatusRow(title: "Движок не найден", detail: "Укажи папку собранного движка (engine/dist)", level: .missing)
                }
                Button("Указать папку движка…") {
                    if let url = FilePicker.choose(files: false, folders: true, prompt: "Выбрать движок") {
                        Task { await state.setEngine(url) }
                    }
                }
                .buttonStyle(.pill)
            }

            Section("D3DMetal (DirectX 11 и 12)") {
                if let engine = state.engine, let version = engine.d3dmetalVersion {
                    let source = switch engine.d3dmetalSource {
                    case .bundled: "встроен в приложение"
                    case .imported: "подключён из Game Porting Toolkit"
                    case .engine: "из движка разработки"
                    }
                    StatusRow(title: "D3DMetal \(version), \(source)",
                              detail: "Включается для каждой программы отдельно; Steam рисует свой интерфейс через DXVK", level: .ok)
                } else {
                    StatusRow(title: "Не подключён", detail: "Без него не запустятся игры на DirectX 12 и многие на DirectX 11", level: .warning)
                }
                DropZone(title: "Обновить или подключить", subtitle: "Перетащи Game Porting Toolkit (.dmg) с сайта Apple") { url in
                    Task { await state.importD3DMetal(from: url) }
                }
                HStack {
                    Button("Выбрать файл…") {
                        if let url = FilePicker.choose(files: true, folders: true, startAt: Paths.home.appendingPathComponent("Downloads")) {
                            Task { await state.importD3DMetal(from: url) }
                        }
                    }
                    Button("Страница загрузок Apple") { NSWorkspace.shared.open(AppInfo.appleDownloads) }
                    if state.engine?.d3dmetalSource == .imported,
                       let bundled = Paths.bundledD3DMetal, FileManager.default.fileExists(atPath: bundled.path) {
                        Button("Вернуть встроенный") { state.removeImportedD3DMetal() }
                    }
                }
                .buttonStyle(.pill)
                .disabled(state.engine == nil || state.activity != nil)
            }

            Section("Данные") {
                folderRow("Бутылки", state.bottlesRoot, change: {
                    if let url = FilePicker.choose(files: false, folders: true, startAt: state.bottlesRoot, prompt: "Выбрать") {
                        state.setBottlesRoot(url)
                    }
                })
                folderRow("Журналы", Paths.logs)
                folderRow("Ярлыки на Mac", Paths.shortcuts)
            }

            Section {
                Button("Пройти первоначальную настройку заново") { state.restartOnboarding() }
                    .buttonStyle(.pill)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Настройки")
    }

    private func folderRow(_ title: String, _ url: URL, change: (() -> Void)? = nil) -> some View {
        LabeledContent(title) {
            HStack {
                Text(url.path).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Button("Показать") {
                    try? Paths.ensure(url)
                    NSWorkspace.shared.open(url)
                }
                if let change { Button("Изменить…", action: change) }
            }
            .buttonStyle(.pill)
        }
    }
}
