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
    @State private var troubleshooting: Symptom?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            cover
            Text(item.name).font(.headline).lineLimit(2, reservesSpace: true)
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
        .sheet(item: $troubleshooting) { TroubleshootView(itemID: item.id, symptom: $0) }
    }

    private var cover: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(.quaternary)
            if let path = item.artwork, let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image).resizable().scaledToFill()
            } else if let icon = state.icon(for: item) {
                Image(nsImage: icon).resizable().interpolation(.high).scaledToFit().frame(width: 76, height: 76)
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
                            ForEach(LibraryItem.Graphics.allCases) { Text($0.title).tag($0) }
                        }
                    }
                    Toggle(t("DLSS через MetalFX"), isOn: $item.metalFX)
                    Toggle(t("Трассировка лучей (DXR)"), isOn: $item.raytracing)
                    Toggle(t("Счётчик FPS (Metal HUD)"), isOn: $item.performanceHUD)
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
                    .disabled(state.engine?.hasDiscordBridge != true)
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
                Button(t("Отмена")) { dismiss() }
                Button(t("Сохранить")) { save(); dismiss() }
                    .buttonStyle(.pillProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .buttonStyle(.pill)
            .padding(16)
        }
        .frame(width: 540, height: 700)
        .onAppear(perform: load)
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

    private func save() {
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
        state.upsert(item)
        let bottle = bottle
        state.updateBottle(item.bottle) { $0 = bottle }
        state.refreshGames()
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
