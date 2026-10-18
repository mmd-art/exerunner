import AppKit
import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var state: AppState
    var openCatalog: () -> Void
    @State private var addingProgram = false

    private let columns = [GridItem(.adaptive(minimum: 170, maximum: 230), spacing: 18, alignment: .top)]

    var body: some View {
        ScrollView {
            if state.allItems.isEmpty {
                empty
            } else {
                VStack(alignment: .leading, spacing: 30) {
                    section(t("Лаунчеры"), state.launchers)
                    section(t("Игры"), state.games)
                    section(t("Программы"), state.programs)
                }
                .padding(24)
            }
        }
        .navigationTitle(t("Библиотека"))
        .toolbar {
            ToolbarItemGroup {
                Button { addingProgram = true } label: { Label(t("Добавить программу"), systemImage: "plus") }
                Button { Task { await state.refresh() } } label: { Label(t("Обновить"), systemImage: "arrow.clockwise") }
            }
        }
        .sheet(isPresented: $addingProgram) { AddProgramSheet() }
    }

    private var empty: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.grid.2x2").font(.system(size: 44, weight: .light)).foregroundStyle(.secondary)
            Text(t("Библиотека пока пустая")).font(.title2.weight(.semibold))
            Text(t("Поставь лаунчер или добавь свою программу")).foregroundStyle(.secondary)
            HStack {
                Button(t("Открыть каталог"), action: openCatalog).buttonStyle(.pillProminent)
                Button(t("Добавить программу…")) { addingProgram = true }
            }
            .buttonStyle(.pill)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [LibraryItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.title3.weight(.semibold))
                LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                    ForEach(items) { ItemTile(item: $0) }
                }
            }
        }
    }
}

struct ItemTile: View {
    @EnvironmentObject private var state: AppState
    let item: LibraryItem
    @State private var editing = false
    @State private var managingComponents = false
    @State private var managingEnvironment = false
    @State private var managingSaves = false
    @State private var troubleshooting: Symptom?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            cover
            Text(item.name).font(.headline).lineLimit(2, reservesSpace: true)
            if item.isolated {
                Label(t("Изолировано · без сети"), systemImage: "shield.lefthalf.filled")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let profile = state.profile(for: item) {
                HStack(spacing: 6) {
                    VerdictBadge(profile: profile)
                    if !profile.recommended.winetricks.isEmpty, item.useRecommended {
                        Badge(text: t("+ компоненты"))
                    }
                }
            }
            if let diagnosis = state.diagnoses[item.id] {
                Button { troubleshooting = .launch } label: {
                    Label(diagnosis.primary?.pattern.category.shortTitle ?? t("Ошибка"), systemImage: "exclamationmark.triangle.fill")
                        .lineLimit(1)
                }
                .buttonStyle(PillButtonStyle(compact: true, tint: .orange))
                .help(t("\(diagnosis.headline). Открыть помощника"))
            }
            HStack(spacing: 8) {
                if state.running.contains(item.id) {
                    let active = state.active.contains(item.id)
                    Button { Task { await state.stop(item) } } label: {
                        Label(active ? t("Остановить") : t("Запускается…"), systemImage: active ? "stop.fill" : "hourglass")
                    }
                    .buttonStyle(.pillCompact)
                    .help(active ? (item.kind == .launcher ? t("Закрыть лаунчер и всё, что он запустил") : t("Закрыть только эту программу"))
                                 : t("Отменить запуск"))
                } else {
                    Button { state.launch(item) } label: {
                        Label(item.kind == .game ? t("Играть") : t("Открыть"), systemImage: "play.fill")
                    }
                    .buttonStyle(.pillCompactProminent)
                }
                Spacer()
                Menu { menuItems } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
            }
            .buttonStyle(.pill)
            .controlSize(.small)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(nsColor: .separatorColor).opacity(0.6)))
        .contextMenu { menuItems }
        .sheet(isPresented: $editing) { ItemSettingsView(item: item) }
        .sheet(isPresented: $managingComponents) { RuntimeComponentsView(item: item) }
        .sheet(isPresented: $managingEnvironment) { EnvironmentView(item: item) }
        .sheet(isPresented: $managingSaves) { SaveArchiveView(item: item).environmentObject(state) }
        .sheet(item: $troubleshooting) { TroubleshootView(itemID: item.id, symptom: $0) }
    }

    private var cover: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(.quaternary)
            if let path = item.artwork, let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image).resizable().scaledToFill()
            } else if let icon = state.icon(for: item) {
                Image(nsImage: icon).resizable().interpolation(.high).scaledToFit().frame(width: item.kind == .game ? 144 : 76, height: item.kind == .game ? 144 : 76)
            } else {
                Image(systemName: symbol).font(.system(size: 40, weight: .light)).foregroundStyle(.secondary)
            }
        }
        .aspectRatio(item.kind == .game ? 2.0 / 3.0 : 16.0 / 10.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var symbol: String {
        if let recipe = state.recipe(item.recipeID), item.kind != .game { return recipe.symbol }
        return item.kind == .game ? "gamecontroller" : "app.dashed"
    }

    @ViewBuilder
    private var menuItems: some View {
        Button(t("Настройки запуска…")) { editing = true }
        if item.kind == .game { Button(t("Копии сохранений…")) { managingSaves = true } }
        Button(t("Библиотеки Windows…")) { managingComponents = true }
        Button(t("Windows-среда, движок и устройства…")) { managingEnvironment = true }
        Button(t("Помощник по проблемам…")) { troubleshooting = state.diagnoses[item.id] == nil ? (item.kind == .launcher ? .launcher : .launch) : .launch }
        Button(state.hasShortcut(item) ? t("Убрать из Программ на Mac") : t("Добавить в Программы на Mac")) { state.toggleShortcut(item) }
        Button(t("Показать в Finder")) { state.reveal(item) }
        Button(t("Открыть журнал")) { state.openLog(item) }
        Divider()
        Button(t("Остановить всё в бутылке «\(item.bottle)»")) { Task { await state.stopBottle(item) } }
        if state.isSaved(item) {
            Divider()
            Button(item.isSteamGame ? t("Сбросить настройки игры") : t("Убрать из библиотеки"), role: .destructive) { state.remove(item) }
        }
    }
}

struct ItemSettingsView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State var item: LibraryItem
    @State private var argumentsText = ""
    @State private var environmentText = ""
    @State private var overridesText = ""
    @State private var bottle = BottleSettings()
    @State private var saving = false
    @State private var saveError: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField(t("Название"), text: $item.name)
                    if item.recipeID == nil, let detected = state.detectedLauncher(for: item) {
                        HStack {
                            Text(t("Похоже на \(detected.name), но его настройки не применены.")).foregroundStyle(.secondary)
                            Spacer()
                            Button(t("Применить")) {
                                item.recipeID = detected.id
                                item.kind = .launcher
                            }
                            .buttonStyle(.pillCompact)
                        }
                    }
                }
                if let profile = state.profile(for: item) {
                    Section(t("База совместимости")) {
                        Toggle(t("Применять рекомендованные настройки"), isOn: $item.useRecommended)
                        GameProfileDetails(profile: profile)
                    }
                }
                Section(t("Графика")) {
                    if state.canTargetExecutables(item) {
                        Picker("DirectX", selection: $item.graphics) {
                            ForEach(LibraryItem.Graphics.allCases) { option in
                                Text(option.title).tag(option).help(option.help)
                                    .disabled((option == .d3dmetal && state.engineForItem(item)?.d3dmetalVersion == nil) ||
                                        (option == .vkd3d && (state.engineForItem(item)?.hasVKD3D != true || item.isolated || item.bottle.hasPrefix("isolated-"))) || option == .dxmt && (state.engineForItem(item)?.hasDXMT != true || item.isolated ||
                                        !GraphicsSelection.supportsDXMT(profile: state.profile(for: item))))
                            }
                        }
                        .help(item.graphics.help)
                        Text(GraphicsSelection.explanation(item, profile: state.profile(for: item),
                                                           hasD3DMetal: state.engineForItem(item)?.d3dmetalVersion != nil))
                            .font(.callout).foregroundStyle(.secondary)
                        if state.effectiveGraphics(item) == .dxmt {
                            Text(state.engineForItem(item)?.dxmtVersion.map { "DXMT " + $0 } ?? t("В движке нет DXMT"))
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        Text(item.graphics.help)
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Toggle(t("DLSS через MetalFX"), isOn: $item.metalFX)
                        .disabled(!GraphicsSelection.allowsMetalFX(graphics: state.effectiveGraphics(item),
                                  profile: state.profile(for: item), hasD3DMetal: state.engineForItem(item)?.d3dmetalVersion != nil))
                        .help(t("Переводит существующий в игре DLSS в MetalFX через D3DMetal. DLSS нужно также включить в самой игре. Может повысить FPS за счёт рендера в меньшем разрешении; для игр без DLSS не нужен."))
                    Toggle(t("Трассировка лучей (DXR)"), isOn: $item.raytracing)
                        .disabled(!GraphicsSelection.allowsDXR(graphics: state.effectiveGraphics(item),
                                  profile: state.profile(for: item), hasD3DMetal: state.engineForItem(item)?.d3dmetalVersion != nil))
                        .help(t("Разрешает DXR через D3DMetal для игр на DirectX 12, которые поддерживают трассировку лучей. Эффект нужно включить в самой игре; нагрузка и требования к GPU возрастают."))
                    if state.profile(for: item)?.features?.dlss == false {
                        Text(t("В этой программе нет DLSS; переключатель MetalFX не увеличит FPS."))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    if state.profile(for: item)?.features?.dxr == false || state.profile(for: item)?.graphicsAPI == "d3d11" {
                        Text(t("Эта программа не использует DXR."))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Text(t("Счётчик FPS включается в общих настройках ExeRunner."))
                        .font(.callout).foregroundStyle(.secondary)
                }
                Section(t("Изоляция")) {
                    Toggle(t("Изолированный запуск (экспериментальный)"), isOn: $item.isolated)
                        .disabled(item.isSteamGame || item.kind == .launcher || state.running.contains(item.id) || saving)
                    Text(t("Включено: без интернета и доступа к личным папкам Mac. Выключено: обычный Wine с доступом к Mac и сети. Режимы используют отдельные копии; их сохранения и изменения не объединяются. Это экспериментальная песочница, не виртуальная машина."))
                        .font(.callout).foregroundStyle(.secondary)
                    if state.running.contains(item.id) {
                        Text(t("Сначала останови программу, чтобы сменить режим."))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                Section(t("Запуск")) {
                    TextField(item.isSteamGame ? t("Параметры запуска игры") : t("Аргументы"), text: $argumentsText,
                              prompt: Text(t("например -dx12")))
                    TextField(t("Переменные окружения"), text: $environmentText,
                              prompt: Text(t("ИМЯ=значение, по одной на строку")), axis: .vertical)
                        .lineLimit(3...6)
                    TextField(t("Переопределения DLL"), text: $overridesText,
                              prompt: Text(t("dll=native, builtin или пусто, чтобы выключить")), axis: .vertical)
                        .lineLimit(1...4)
                    Picker(t("Язык программы"), selection: $item.locale) {
                        Text(t("По умолчанию")).tag(String?.none)
                        ForEach(ProgramLocale.all, id: \.id) { Text($0.title).tag(String?.some($0.id)) }
                    }
                    Picker(t("Журнал"), selection: $item.logging) {
                        ForEach(LibraryItem.Logging.allCases) { Text($0.title).tag($0) }
                    }
                }
                Section {
                    Toggle(t("Высокое разрешение (HiDPI)"), isOn: Binding(
                        get: { bottle.highResolution ?? state.highResolutionEnabled(forBottle: item.bottle) },
                        set: { bottle.highResolution = $0 }
                    ))
                    .disabled(item.isolated || item.bottle.hasPrefix("isolated-"))
                    .help(t("Открывает физические разрешения монитора, включая 2K и 4K. Для игр включается по умолчанию; ранее выбранный режим сохраняется. Выключи при проблемах с размером интерфейса или курсором. Масштабирование Mac не меняется."))
                    Text(t("HiDPI применяется после остановки всех программ этой бутылки и нового запуска."))
                        .font(.callout).foregroundStyle(.secondary)
                    Picker(t("Звук"), selection: $bottle.audioDriver) {
                        ForEach(BottleSettings.AudioDriver.allCases) { Text($0.title).tag($0) }
                    }
                    Picker(t("Буфер звука"), selection: $bottle.audioLatency) {
                        ForEach(BottleSettings.AudioLatency.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle(isOn: $bottle.discordBridge) {
                        Text(t("Статус игры в Discord"))
                        Text(t("Игра сможет показывать в Discord на Mac, во что ты играешь."))
                    }
                    .disabled(state.engineForItem(item)?.hasDiscordBridge != true)
                } header: {
                    Text(t("Бутылка «\(item.bottle)»"))
                } footer: {
                    Text(t("Эти настройки общие для всех программ этой бутылки.")).foregroundStyle(.secondary)
                }
                if item.isSteamGame {
                    Section {
                        Text(state.canTargetExecutables(item)
                             ? t("Графика, переменные и DLL доходят до игры, даже если её запускает уже открытый Steam: приложение знает её .exe из базы. Параметры запуска действуют при запуске отсюда. Язык и подробный журнал Wine читает при старте, поэтому они действуют, когда Steam запускается вместе с игрой.")
                             : t("Этой игры нет в базе, её .exe неизвестен. Настройки дойдут до неё, если Steam запускается вместе с игрой: закрой Steam и запусти игру отсюда."))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button(t("Отмена")) { dismiss() }.disabled(saving)
                if saving { ProgressView().controlSize(.small) }
                Button(t("Сохранить")) { Task { await save() } }
                    .buttonStyle(.pillProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(saving)
            }
            .buttonStyle(.pill)
            .padding(16)
        }
        .frame(width: 540, height: 700)
        .onAppear(perform: load)
        .interactiveDismissDisabled(saving)
        .alert(t("Не удалось сохранить настройки"), isPresented: Binding(
            get: { saveError != nil }, set: { if !$0 { saveError = nil } }
        )) { Button("OK") { saveError = nil } } message: { Text(saveError ?? "") }
    }

    private func load() {
        if let appID = item.steamAppID {
            let prefix = "steam://run/\(appID)//"
            argumentsText = item.arguments.first.flatMap { $0.hasPrefix(prefix) ? String($0.dropFirst(prefix.count).dropLast()) : nil } ?? ""
        } else {
            argumentsText = item.arguments.joined(separator: " ")
        }
        environmentText = item.extraEnvironment.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
        bottle = state.settings(forBottle: item.bottle)
        overridesText = item.dllOverrides.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
    }

    private func save() async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        let words = argumentsText.split(separator: " ").map(String.init)
        if let appID = item.steamAppID {
            // steam://run/<id>//<launch options>/ hands options to the game through Steam
            item.arguments = words.isEmpty ? ["steam://rungameid/\(appID)"] : ["steam://run/\(appID)//\(words.joined(separator: " "))/"]
        } else {
            item.arguments = words
        }
        var env: [String: String] = [:]
        for line in environmentText.split(separator: "\n") {
            guard let eq = line.firstIndex(of: "="), eq != line.startIndex else { continue }
            env[line[..<eq].trimmingCharacters(in: .whitespaces)] = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
        }
        item.extraEnvironment = env
        var overrides: [String: String] = [:]
        for line in overridesText.split(whereSeparator: { $0 == "\n" || $0 == "," }) {
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let dll = parts[0].trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: ".dll", with: "")
            guard !dll.isEmpty else { continue }
            overrides[dll] = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
        }
        item.dllOverrides = overrides
        do {
            let currentEnvironment = state.settings(forBottle: item.bottle)
            bottle.enginePath = currentEnvironment.enginePath
            bottle.serialPorts = currentEnvironment.serialPorts
            bottle.controllerMode = currentEnvironment.controllerMode
            try await state.saveLaunchSettings(item, bottleSettings: bottle)
            dismiss()
        } catch { saveError = error.localizedDescription }
    }
}

/// Locales a program can be started in; Wine takes the Windows language from LC_ALL
enum ProgramLocale {
    static let all: [(id: String, title: String)] = [
        ("en_US.UTF-8", "English"), ("ru_RU.UTF-8", "Русский"), ("uk_UA.UTF-8", "Українська"),  // l10n: own names
        ("de_DE.UTF-8", "Deutsch"), ("fr_FR.UTF-8", "Français"), ("es_ES.UTF-8", "Español"),
        ("it_IT.UTF-8", "Italiano"), ("pt_BR.UTF-8", "Português (Brasil)"), ("pl_PL.UTF-8", "Polski"),
        ("tr_TR.UTF-8", "Türkçe"), ("ja_JP.UTF-8", "日本語"), ("ko_KR.UTF-8", "한국어"),
        ("zh_CN.UTF-8", "简体中文"), ("zh_TW.UTF-8", "繁體中文"),
    ]
}
