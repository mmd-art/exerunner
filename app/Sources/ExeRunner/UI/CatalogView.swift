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
        case installer, portable
        var id: String { rawValue }
        var title: String { self == .installer ? t("Это установщик") : t("Запускать как есть") }
    }

    enum Phase { case form, installing, choose }

    @State private var file: URL?
    @State private var name = ""
    @State private var mode: Mode = .installer
    @State private var bottle = "programs"
    @State private var phase: Phase = .form
    @State private var candidates: [URL] = []
    @State private var chosen: URL?

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
        .frame(width: 540)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button(t("Выбрать файл…")) {
                    if let url = FilePicker.choose(startAt: Paths.home.appendingPathComponent("Downloads")) { pick(url) }
                }
                .buttonStyle(.pill)
                Text(file?.lastPathComponent ?? t("файл .exe или .msi")).foregroundStyle(file == nil ? .secondary : .primary).lineLimit(1)
            }
            TextField(t("Название в библиотеке"), text: $name)
            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(file?.pathExtension.lowercased() == "msi")
            if mode == .installer {
                TextField(t("Бутылка"), text: $bottle)
                Text(t("Установщик откроется в своём окне, пройди его шаги. Программы можно держать в одной общей бутылке «programs» или дать программе отдельную."))
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text(t("Программа запускается прямо с того места, где лежит, без копирования. Не перемещай её потом."))
                    .font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button(t("Отмена")) { dismiss() }
                Button(mode == .installer ? t("Установить") : t("Добавить")) { start() }
                    .buttonStyle(.pillProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(file == nil || name.isEmpty || bottle.isEmpty)
            }
            .buttonStyle(.pill)
        }
    }

    private var installing: some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text(state.activity ?? t("Идёт установка…")).foregroundStyle(.secondary)
        }
    }

    private var choose: some View {
        VStack(alignment: .leading, spacing: 14) {
            if candidates.isEmpty {
                Text(t("Установщик закончил, но новых программ я не нашёл. Укажи файл программы вручную."))
                    .foregroundStyle(.secondary)
            } else {
                Text(t("Какой файл запускать?")).font(.headline)
                Picker("", selection: $chosen) {
                    ForEach(candidates, id: \.self) { url in
                        Text(url.lastPathComponent + "  ·  " + url.deletingLastPathComponent().lastPathComponent).tag(Optional(url))
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }
            HStack {
                Button(t("Выбрать вручную…")) {
                    let start = Bottle(name: bottle, root: state.bottlesRoot).driveC
                    if let url = FilePicker.choose(startAt: start) { finish(url) }
                }
                Spacer()
                Button(t("Отмена")) { dismiss() }
                Button(t("Добавить в библиотеку")) { if let chosen { finish(chosen) } }
                    .buttonStyle(.pillProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(chosen == nil)
            }
            .buttonStyle(.pill)
        }
    }

    private func pick(_ url: URL) {
        file = url
        if name.isEmpty { name = url.deletingPathExtension().lastPathComponent }
        if url.pathExtension.lowercased() == "msi" { mode = .installer }
    }

    private func start() {
        guard let file else { return }
        if mode == .portable {
            state.addPortable(file, name: name)
            dismiss()
            return
        }
        phase = .installing
        Task {
            candidates = await state.runInstaller(file, bottle: bottle)
            chosen = candidates.first
            phase = .choose
        }
    }

    private func finish(_ exe: URL) {
        state.addInstalled(exe, name: name, bottle: bottle)
        dismiss()
    }
}
