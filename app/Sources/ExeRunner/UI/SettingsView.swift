import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Form {
            Section(t("Язык интерфейса")) {
                Picker(t("Язык"), selection: $state.settings.language) {
                    Text(t("Как на Mac")).tag(InterfaceLanguage.system)
                    Text(verbatim: "Русский").tag(InterfaceLanguage.russian)  // l10n: own names
                    Text(verbatim: "English").tag(InterfaceLanguage.english)
                }
            }

            Section(t("Во время игры")) {
                Toggle("Game Boost", isOn: $state.settings.gameBoost)
                    .toggleStyle(.switch)
                    .disabled(!state.gameBoostStatus.available)
                    .accessibilityIdentifier("gameBoostToggle")
                    .help(t("Приоритет CPU и GPU для игр. Прежний игровой режим macOS восстановится после выхода из последней игры."))
                Text(state.gameBoostHint).font(.callout).foregroundStyle(.secondary)

                Toggle(t("Удерживать мышь внутри игры"), isOn: $state.settings.cursorConfinement)
                    .toggleStyle(.switch)
                    .accessibilityIdentifier("cursorConfinementToggle")
                    .disabled(state.engine?.hasCursorGuard != true)
                    .help(t("Защищает захваченную игрой мышь от выхода в горячие углы. При переключении приложений мышь освобождается. Изменение применяется при следующем запуске."))
                Toggle(t("Нативное разрешение текущего экрана"), isOn: $state.settings.automaticNativeResolution)
                    .toggleStyle(.switch)
                    .accessibilityIdentifier("automaticNativeResolutionToggle")
                    .help(t("Согласовывает полноэкранное разрешение поддерживаемых игр с монитором при запуске. Качество графики сохраняется; настройки масштабирования Mac не меняются."))

                Toggle(t("Показывать счётчик FPS"), isOn: Binding(
                    get: { state.settings.performanceHUD ?? state.allItems.contains(where: \.performanceHUD) },
                    set: { state.settings.performanceHUD = $0 }
                ))
                Text(t("Для программ с графикой Metal. Изменение применяется при следующем запуске."))
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section(t("Приложения Windows")) {
                Toggle(t("Автоматически готовить библиотеки Windows"), isOn: $state.settings.automaticRuntimeComponents)
                    .help(t("Определяет стандартные зависимости EXE и устанавливает нужные компоненты перед запуском обычных программ. Все программы бутылки должны быть закрыты."))
                Text(t("Дополнительные компоненты доступны в меню программы → Библиотеки Windows."))
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section("Mac") {
                StatusRow(title: state.system.chip, detail: t("macOS \(state.system.macOS) · \(state.system.memoryGB) ГБ памяти · свободно \(state.system.freeDiskGB) ГБ"),
                          level: state.system.supported ? .ok : .missing)
                if !state.system.isAppleSilicon { Text(t("На Intel Mac Rosetta не требуется.")).foregroundStyle(.secondary) }
                else { HStack {
                    StatusRow(title: state.rosettaInstalled ? t("Rosetta установлена") : t("Rosetta не установлена"), detail: "",
                              level: state.rosettaInstalled ? .ok : .missing)
                    if !state.rosettaInstalled {
                        Button(t("Установить")) { Task { await state.installRosetta() } }.buttonStyle(.pill)
                    }
                } }
            }

            Section(t("Движок")) {
                if let engine = state.engine {
                    StatusRow(title: state.engineVersion ?? t("Версия неизвестна"), detail: engine.root.path, level: .ok)
                    StatusRow(title: t("Модуль совместимости"), detail: "", level: engine.hasCompatModule ? .ok : .missing)
                    StatusRow(title: t("DXVK и MoltenVK"), detail: "", level: engine.hasDXVK && engine.hasMoltenVK ? .ok : .warning)
                    StatusRow(title: t("Mono и Gecko"), detail: "", level: engine.hasMonoAndGecko ? .ok : .warning)
                } else {
                    StatusRow(title: t("Движок не найден"), detail: t("Укажи папку собранного движка (engine/dist)"), level: .missing)
                }
                Button(t("Указать папку движка…")) {
                    if let url = FilePicker.choose(files: false, folders: true, prompt: t("Выбрать движок")) {
                        Task { await state.setEngine(url) }
                    }
                }
                .buttonStyle(.pill)
            }

            Section(t("D3DMetal (DirectX 11 и 12)")) {
                if let engine = state.engine, let version = engine.d3dmetalVersion {
                    let source = switch engine.d3dmetalSource {
                    case .bundled: t("встроен в приложение")
                    case .imported: t("подключён из Game Porting Toolkit")
                    case .engine: t("из движка разработки")
                    }
                    StatusRow(title: "D3DMetal \(version), \(source)",
                              detail: t("Включается для каждой программы отдельно; Steam рисует свой интерфейс через DXVK"), level: .ok)
                } else {
                    StatusRow(title: t("Не подключён"), detail: t("Без него не запустятся игры на DirectX 12 и многие на DirectX 11"), level: .warning)
                }
                DropZone(title: t("Обновить или подключить"), subtitle: t("Перетащи Game Porting Toolkit (.dmg) с сайта Apple")) { url in
                    Task { await state.importD3DMetal(from: url) }
                }
                HStack {
                    Button(t("Выбрать файл…")) {
                        if let url = FilePicker.choose(files: true, folders: true, startAt: Paths.home.appendingPathComponent("Downloads")) {
                            Task { await state.importD3DMetal(from: url) }
                        }
                    }
                    Button(t("Страница загрузок Apple")) { NSWorkspace.shared.open(AppInfo.appleDownloads) }
                    if state.engine?.d3dmetalSource == .imported,
                       let bundled = Paths.bundledD3DMetal, FileManager.default.fileExists(atPath: bundled.path) {
                        Button(t("Вернуть встроенный")) { state.removeImportedD3DMetal() }
                    }
                }
                .buttonStyle(.pill)
                .disabled(state.engine == nil || state.activity != nil)
            }

            Section(t("Данные")) {
                folderRow(t("Бутылки"), state.bottlesRoot, change: {
                    if let url = FilePicker.choose(files: false, folders: true, startAt: state.bottlesRoot, prompt: t("Выбрать")) {
                        state.setBottlesRoot(url)
                    }
                })
                folderRow(t("Журналы"), Paths.logs)
                folderRow(t("Ярлыки на Mac"), Paths.shortcuts)
            }

            Section {
                Button(t("Пройти первоначальную настройку заново")) { state.restartOnboarding() }
                    .buttonStyle(.pill)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(t("Настройки"))
    }

    private func folderRow(_ title: String, _ url: URL, change: (() -> Void)? = nil) -> some View {
        LabeledContent(title) {
            HStack {
                Text(url.path).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Button(t("Показать")) {
                    try? Paths.ensure(url)
                    NSWorkspace.shared.open(url)
                }
                if let change { Button(t("Изменить…"), action: change) }
            }
            .buttonStyle(.pill)
        }
    }
}
