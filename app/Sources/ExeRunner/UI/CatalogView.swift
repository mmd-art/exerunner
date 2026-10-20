import AppKit
import SwiftUI

struct CatalogView: View {
    @EnvironmentObject private var state: AppState
    @State private var addingProgram = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Card {
                    HStack(spacing: 14) {
                        Image(systemName: "shippingbox").font(.title2).frame(width: 34)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(t("Своя Windows-программа")).font(.headline)
                            Text(t("Установщик .exe или .msi, или программа, которой не нужна установка")).font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(t("Добавить…")) { addingProgram = true }
                            .buttonStyle(.pillProminent)
                            .disabled(state.engine == nil)
                    }
                }
                group(t("Лаунчеры"), kind: .launcher)
                group(t("Программы"), kind: .program)
                CompatibilityList()
            }
            .padding(24)
            .frame(maxWidth: 780, alignment: .leading)
        }
        .navigationTitle(t("Каталог"))
        .sheet(isPresented: $addingProgram) { AddProgramSheet() }
    }

    @ViewBuilder
    private func group(_ title: String, kind: Recipe.Kind) -> some View {
        let list = state.recipes.filter { $0.kind == kind }
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.title3.weight(.semibold))
                ForEach(list) { RecipeRow(recipe: $0) }
            }
        }
    }
}

/// The compatibility database, searchable: check a game before buying it.
struct CompatibilityList: View {
    @EnvironmentObject private var state: AppState
    @State private var query = ""
    @State private var shown: GameProfile?

    private var results: [GameProfile] {
        let all = state.gameProfiles
        return query.isEmpty ? all : all.filter { $0.matches(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(t("Совместимость игр")).font(.title3.weight(.semibold))
                Text(t("\(state.gameProfiles.count) в базе")).foregroundStyle(.secondary)
            }
            Text(t("Проверь игру до покупки. Оценки из базы Whisky, многие ещё не проверены. Игры с античитом уровня ядра не запустятся."))
                .font(.callout).foregroundStyle(.secondary)
            TextField(t("Найти игру"), text: $query)
                .textFieldStyle(.roundedBorder)
            Card {
                VStack(spacing: 0) {
                    ForEach(results.prefix(60)) { profile in
                        Button { shown = profile } label: {
                            HStack {
                                Text(profile.title)
                                Spacer()
                                Text(profile.storeTitle).font(.callout).foregroundStyle(.secondary)
                                VerdictBadge(profile: profile)
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 7)
                        }
                        .buttonStyle(.plain)
                        if profile.id != results.prefix(60).last?.id { Divider() }
                    }
                    if results.isEmpty {
                        Text(t("Такой игры в базе нет. Это не значит, что она не пойдёт: база маленькая."))
                            .foregroundStyle(.secondary).padding(.vertical, 8)
                    }
                }
            }
        }
        .sheet(item: $shown) { profile in
            VStack(alignment: .leading, spacing: 14) {
                Text(profile.title).font(.title2.weight(.semibold))
                ScrollView { GameProfileDetails(profile: profile).frame(maxWidth: .infinity, alignment: .leading) }
                HStack {
                    Spacer()
                    Button(t("Закрыть")) { shown = nil }.buttonStyle(.pillProminent).keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(width: 520, height: 480)
        }
    }
}

struct RecipeRow: View {
    @EnvironmentObject private var state: AppState
    let recipe: Recipe
    @State private var working = false

    var body: some View {
        Card {
            HStack(spacing: 14) {
                Image(systemName: recipe.symbol).font(.title2).frame(width: 34)
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text(recipe.name).font(.headline); RecipeStatusBadge(status: recipe.status) }
                    Text(recipe.localizedAbout).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if state.isInstalled(recipe) {
                    Label(t("Установлено"), systemImage: "checkmark").foregroundStyle(.secondary)
                } else if recipe.status != .planned {
                    Button(working ? t("Устанавливаю…") : t("Установить")) {
                        working = true
                        Task {
                            await state.install(recipe)
                            working = false
                        }
                    }
                    .buttonStyle(.pillProminent)
                    .disabled(working || state.engine == nil)
                }
            }
        }
    }
}

struct AddProgramSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    enum Mode: String, CaseIterable, Identifiable {
        case installer, portable, existing
        var id: String { rawValue }
        var title: String {
            switch self {
            case .installer: return t("Это установщик")
            case .portable: return t("Запускать как есть")
            case .existing: return t("Уже установлена")
            }
        }
    }

    enum Phase { case form, installing, choose }

    @State private var file: URL?
    @State private var name = ""
    @State private var mode: Mode = .installer
    @State private var bottle = "programs"
    @State private var existingBottle = ""
    private var selectedBottle: String { mode == .existing ? existingBottle : bottle }
    @State private var phase: Phase = .form
    @State private var candidates: [URL] = []
    @State private var chosen: URL?
    @State private var fileError: String?
    @State private var environments: [String] = []

    init(initialMode: Mode = .installer) { _mode = State(initialValue: initialMode) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(t("Своя Windows-программа")).font(.title2.weight(.semibold))
            switch phase {
            case .form: form
            case .installing: installing
            case .choose: choose
            }
        }
        .padding(24)
        .frame(width: 600)
        .task {
            let root = state.bottlesRoot
            environments = await Task.detached { InstalledPrograms.environments(root: root) }.value
            if !environments.contains(existingBottle) { existingBottle = environments.first ?? "" }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            DisclosureGroup(t("Как добавить ZIP, игру или приложение")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(t("1. Распакуй архив целиком. Сохрани EXE, DLL и папки с данными вместе."))
                    Text(t("2. Выбери основной EXE. Для готовой программы выбери «Запускать как есть», для setup.exe или MSI — «Это установщик»."))
                    Text(t("3. Укажи название. После установки выбери EXE установленной программы и добавь его в библиотеку."))
                    Text(t("Обычное добавление не изолирует программу от Mac и сети. Изолированный прототип пока требует отдельно подготовленной бутылки; ZIP автоматически не импортируется."))
                }
                .font(.callout).foregroundStyle(.secondary).padding(.top, 8)
            }
            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: mode) { _, value in
                if value == .portable && file?.pathExtension.lowercased() == "msi" { mode = .installer }
            }
            if mode == .existing {
                Text(t("Выбрать уже установленную программу")).font(.headline)
                Picker(t("Окружение"), selection: $existingBottle) {
                    ForEach(environments, id: \.self) { Text($0).tag($0) }
                }
                Text(environments.isEmpty
                     ? t("Установленных окружений пока нет. Сначала установи программу.")
                     : t("Выбери окружение, затем найди EXE по имени или пути. Повторная установка не нужна."))
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                HStack {
                    Button(t("Выбрать файл…")) {
                        if let url = FilePicker.choose(startAt: Paths.home.appendingPathComponent("Downloads")) { pick(url) }
                    }
                    .buttonStyle(.pill)
                    Text(file?.lastPathComponent ?? t("файл .exe или .msi"))
                        .foregroundStyle(file == nil ? .secondary : .primary).lineLimit(1)
                }
            }
            if let fileError { Text(fileError).font(.callout).foregroundStyle(.red) }
            TextField(t("Название в библиотеке"), text: $name)
            if mode == .installer {
                TextField(t("Бутылка"), text: $bottle)
                Text(t("Установщик откроется в своём окне, пройди его шаги. Программы можно держать в одной общей бутылке «programs» или дать программе отдельную."))
                    .font(.callout).foregroundStyle(.secondary)
            } else if mode == .portable {
                Text(t("Программа запускается прямо с того места, где лежит, без копирования. Не перемещай её потом."))
                    .font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button(t("Отмена")) { dismiss() }
                Button(mode == .existing ? t("Найти EXE") : mode == .installer ? t("Установить") : t("Добавить")) { start() }
                    .buttonStyle(.pillProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(mode == .existing ? !environments.contains(existingBottle) : file == nil || name.isEmpty || bottle.isEmpty)
            }
            .buttonStyle(.pill)
        }
    }

    private var installing: some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text(mode == .existing ? t("Поиск установленных программ…") : state.activity ?? t("Идёт установка…")).foregroundStyle(.secondary)
        }
    }

    private var choose: some View {
        ExecutableChooser(candidates: candidates,
                          driveC: Bottle(name: selectedBottle, root: state.bottlesRoot).driveC,
                          chosen: $chosen, error: fileError, browse: {
            let start = Bottle(name: selectedBottle, root: state.bottlesRoot).driveC
            if let url = FilePicker.choose(startAt: start, fileExtensions: ["exe"]) {
                guard ExecutableDiscovery.usable(url) else {
                    fileError = t("Выбери доступный EXE-файл программы.")
                    return
                }
                fileError = nil
                if !candidates.contains(url) { candidates.append(url) }
                chosen = url
            }
        }, cancel: { dismiss() }, add: { if let chosen { finish(chosen) } })

    }

    private func pick(_ url: URL) {
        guard ["exe", "msi"].contains(url.pathExtension.lowercased()) else {
            file = nil
            fileError = t("Выбери EXE или MSI. ZIP сначала распакуй целиком и выбери программу внутри.")
            return
        }
        fileError = nil
        file = url
        if name.isEmpty { name = url.deletingPathExtension().lastPathComponent }
        if url.pathExtension.lowercased() == "msi" { mode = .installer }
    }

    private func start() {
        if mode == .existing {
            phase = .installing
            let root = state.bottlesRoot, environment = existingBottle
            Task {
                candidates = await Task.detached { InstalledPrograms.executables(root: root, environment: environment) }.value
                chosen = nil
                phase = .choose
            }
            return
        }
        guard let file else { return }
        if mode == .portable {
            guard file.pathExtension.lowercased() == "exe" else { return }
            state.addPortable(file, name: name)
            dismiss()
            return
        }
        phase = .installing
        Task {
            candidates = await state.runInstaller(file, bottle: bottle)
            chosen = nil
            phase = .choose
        }
    }

    private func finish(_ exe: URL) {
        guard ExecutableDiscovery.usable(exe) else {
            fileError = t("Выбери доступный EXE-файл программы.")
            return
        }
        if mode == .existing {
            let drive = Bottle(name: selectedBottle, root: state.bottlesRoot).driveC.resolvingSymlinksInPath().path + "/"
            guard InstalledPrograms.environments(root: state.bottlesRoot).contains(existingBottle),
                  exe.resolvingSymlinksInPath().path.hasPrefix(drive) else {
                fileError = t("Выбери EXE внутри выбранного окружения.")
                return
            }
        }
        fileError = nil
        state.addInstalled(exe, name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                           ? exe.deletingPathExtension().lastPathComponent : name, bottle: selectedBottle)
        dismiss()
    }
}
