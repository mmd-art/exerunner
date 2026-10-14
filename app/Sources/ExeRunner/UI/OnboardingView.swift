import AppKit
import SwiftUI

/// First run, step by step: the Mac, Rosetta, the engine, D3DMetal, launchers, installing.
struct OnboardingView: View {
    @EnvironmentObject private var state: AppState

    enum Step: Int, CaseIterable {
        case welcome, mac, rosetta, engine, d3dmetal, launchers, install, done

        var title: String {
            switch self {
            case .welcome: t("Добро пожаловать")
            case .mac: t("Проверяем Mac")
            case .rosetta: "Rosetta"
            case .engine: t("Движок")
            case .d3dmetal: t("D3DMetal для DirectX 11 и 12")
            case .launchers: t("Что поставить")
            case .install: t("Установка")
            case .done: t("Готово")
            }
        }
    }

    @State private var step: Step
    @State private var selected: Set<String> = ["steam"]
    @State private var progress: [(name: String, state: String)] = []
    @State private var installing = false

    init(step: Step = .welcome) {
        _step = State(initialValue: step)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                content
                    .frame(maxWidth: 620, alignment: .leading)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 32)
                    .frame(maxWidth: .infinity)
            }
            ActivityBar()
            Divider()
            footer
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(Step.allCases.filter { state.system.isAppleSilicon || ![.rosetta, .d3dmetal].contains($0) }, id: \.self) { item in
                    Capsule()
                        .fill(item.rawValue <= step.rawValue ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(width: item == step ? 26 : 10, height: 6)
                }
            }
            Text(step.title).font(.title2.weight(.semibold))
        }
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcome
        case .mac: macCheck
        case .rosetta: rosetta
        case .engine: engineStep
        case .d3dmetal: d3dmetal
        case .launchers: launchers
        case .install: installStep
        case .done: done
        }
    }

    // MARK: steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(t("Windows-программы и игры на Mac")).font(.largeTitle.weight(.semibold))
            Text(t("\(AppInfo.name) запускает Windows-программы без виртуальной машины и без Windows. Настройка займёт пару минут."))
                .font(.title3).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) {
                if state.system.isAppleSilicon {
                    Label(t("Проверим Mac и поставим Rosetta"), systemImage: "checkmark.seal")
                    Label(t("Подключим D3DMetal от Apple для DirectX 11 и 12"), systemImage: "cube.transparent")
                } else { Label(t("На Intel Mac доступны Wine и Vulkan; поддержка пока экспериментальная."), systemImage: "cpu") }
                Label(t("Поставим лаунчеры: Steam и другие"), systemImage: "gamecontroller")
                Label(t("Игры и программы запускаются из библиотеки или прямо из папки «Программы»"), systemImage: "square.grid.2x2")
            }
            .font(.body)
        }
    }

    private var macCheck: some View {
        let s = state.system
        return VStack(alignment: .leading, spacing: 14) {
            StatusRow(title: t("Процессор"), detail: s.isAppleSilicon ? s.chip : t("\(s.chip): Intel Mac, экспериментальная поддержка"),
                      level: s.isAppleSilicon ? .ok : .warning)
            StatusRow(title: "macOS \(s.macOS)", detail: s.macOSMajor >= 15 ? "" : t("Нужна macOS 15 Sequoia или новее"),
                      level: s.macOSMajor >= 15 ? .ok : .missing)
            StatusRow(title: t("Память: \(s.memoryGB) ГБ"),
                      detail: s.memoryGB >= 16 ? "" : t("Программы пойдут, тяжёлым играм может не хватить (Apple советует от 16 ГБ)"),
                      level: s.memoryGB >= 16 ? .ok : .warning)
            StatusRow(title: t("Свободно на диске: \(s.freeDiskGB) ГБ"),
                      detail: s.freeDiskGB >= 30 ? "" : t("Лаунчерам хватит, но современные игры весят по 30–100 ГБ"),
                      level: s.freeDiskGB >= 30 ? .ok : .warning)
        }
    }

    private var rosetta: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(t("Windows-программы написаны для процессоров Intel. Rosetta от Apple переводит их на Apple Silicon. Устанавливается один раз, macOS спросит пароль."))
                .foregroundStyle(.secondary)
            StatusRow(title: state.rosettaInstalled ? t("Rosetta установлена") : t("Rosetta не установлена"),
                      detail: "", level: state.rosettaInstalled ? .ok : .missing)
            if !state.rosettaInstalled {
                Button(t("Установить Rosetta")) { Task { await state.installRosetta() } }
                    .buttonStyle(.pillProminent)
                    .disabled(state.activity != nil)
            }
        }
    }

    private var engineStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let engine = state.engine {
                if engine.root.standardizedFileURL == Paths.bundledEngine?.standardizedFileURL {
                    StatusRow(title: t("Движок встроен в приложение"),
                              detail: t("\(state.engineVersion ?? t("версия неизвестна")), со всеми своими библиотеками: ставить ничего не нужно"),
                              level: .ok)
                } else {
                    StatusRow(title: t("Движок найден"), detail: t("\(state.engineVersion ?? t("версия неизвестна")) · \(engine.root.path)"), level: .ok)
                }
                StatusRow(title: t("Модуль совместимости"), detail: t("включает D3DMetal для каждой программы отдельно"),
                          level: engine.hasCompatModule ? .ok : .missing)
                StatusRow(title: t("DXVK и MoltenVK"), detail: t("DirectX 9–11 через Vulkan, на нём рисует интерфейс Steam"),
                          level: engine.hasDXVK && engine.hasMoltenVK ? .ok : .warning)
                StatusRow(title: t("Mono и Gecko"), detail: t(".NET-программы и встроенные веб-страницы"),
                          level: engine.hasMonoAndGecko ? .ok : .warning)
            } else {
                StatusRow(title: t("Движок не найден"),
                          detail: t("Он лежит внутри ExeRunner.app; если его там нет, приложение скачано не целиком. Можно указать папку движка вручную."),
                          level: .missing)
            }
            Button(state.engine == nil ? t("Указать папку движка…") : t("Указать другую папку…")) {
                if let url = FilePicker.choose(files: false, folders: true, prompt: t("Выбрать движок")) {
                    Task { await state.setEngine(url) }
                }
            }
            .buttonStyle(.pill)
        }
    }

    private var d3dmetal: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(t("D3DMetal от Apple переводит DirectX 11 и 12 в Metal: без него большинство современных игр не запустится."))
                .foregroundStyle(.secondary)
            if let engine = state.engine, let version = engine.d3dmetalVersion {
                StatusRow(title: engine.d3dmetalSource == .bundled ? t("D3DMetal \(version) уже в приложении") : t("D3DMetal \(version) подключён"),
                          detail: engine.d3dmetalSource == .bundled ? t("Можно идти дальше. Новую версию от Apple можно подключить ниже.") : "",
                          level: .ok)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(t("Свой или более новый D3DMetal:")).font(.headline)
                Text(t("1. Открой страницу загрузок Apple и войди под своим Apple ID (бесплатно)"))
                Text(t("2. Скачай Game Porting Toolkit, файл .dmg, обычно он попадает в «Загрузки»"))
                Text(t("3. Перетащи его сюда: \(AppInfo.name) сам достанет D3DMetal из образа и положит к себе"))
            }
            Button(t("Открыть страницу загрузок Apple")) { NSWorkspace.shared.open(AppInfo.appleDownloads) }
                .buttonStyle(.pill)
            DropZone(title: "Game Porting Toolkit", subtitle: t("Перетащи .dmg или папку, или выбери файл кнопкой ниже")) { url in
                Task { await state.importD3DMetal(from: url) }
            }
            Button(t("Выбрать файл…")) {
                if let url = FilePicker.choose(files: true, folders: true, startAt: Paths.home.appendingPathComponent("Downloads")) {
                    Task { await state.importD3DMetal(from: url) }
                }
            }
            .buttonStyle(.pill)
            .disabled(state.activity != nil)
        }
    }

    private var launchers: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t("Игры ставятся и запускаются через лаунчеры. Выбери нужные, остальное можно добавить потом в «Каталоге»."))
                .foregroundStyle(.secondary)
            ForEach(state.recipes.filter { $0.kind == .launcher }) { recipe in
                Card {
                    HStack(spacing: 14) {
                        Image(systemName: recipe.symbol).font(.title2).frame(width: 34)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack { Text(recipe.name).font(.headline); RecipeStatusBadge(status: recipe.status) }
                            Text(recipe.localizedAbout).font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { selected.contains(recipe.id) },
                            set: { on in if on { selected.insert(recipe.id) } else { selected.remove(recipe.id) } }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .disabled(recipe.status == .planned)
                    }
                }
            }
        }
    }

    private var installStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            if progress.isEmpty {
                Text(t("Ничего не выбрано: лаунчеры можно поставить позже в «Каталоге».")).foregroundStyle(.secondary)
            }
            ForEach(progress, id: \.name) { entry in
                HStack {
                    Text(entry.name).font(.headline)
                    Spacer()
                    Text(entry.state).foregroundStyle(.secondary)
                }
            }
        }
        .task { await runInstalls() }
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(t("Всё готово")).font(.largeTitle.weight(.semibold))
            Text(t("В библиотеке появятся лаунчеры, их игры и твои программы. Любую из них можно вынести в папку «Программы» на Mac: правый клик и «Добавить в Программы»."))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: navigation

    private var footer: some View {
        HStack {
            if step != .welcome, step != .install, step != .done {
                Button(t("Назад")) { go(-1) }.buttonStyle(.pill)
            }
            Spacer()
            if step == .d3dmetal, state.engine?.d3dmetalVersion == nil {
                Button(t("Пропустить")) { go(1) }.buttonStyle(.pill)
            }
            Button(nextTitle) { next() }
                .buttonStyle(.pillProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canContinue)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var nextTitle: String {
        switch step {
        case .welcome: t("Начать")
        case .launchers: t("Установить")
        case .done: t("Открыть библиотеку")
        default: t("Дальше")
        }
    }

    private var canContinue: Bool {
        guard state.activity == nil else { return false }
        switch step {
        case .mac: return state.system.supported
        case .rosetta: return state.rosettaInstalled
        case .engine: return state.engine != nil
        case .d3dmetal: return state.engine?.d3dmetalVersion != nil
        case .install: return !installing
        default: return true
        }
    }

    private func next() {
        if step == .done { state.completeOnboarding() } else { go(1) }
    }

    private func go(_ delta: Int) {
        var raw = step.rawValue + delta
        while let target = Step(rawValue: raw), !state.system.isAppleSilicon, [.rosetta, .d3dmetal].contains(target) { raw += delta }
        if let target = Step(rawValue: raw) { step = target }
    }

    private func runInstalls() async {
        let chosen = state.recipes.filter { selected.contains($0.id) && $0.status != .planned }
        progress = chosen.map { (name: $0.name, state: t("ждёт")) }
        installing = true
        for (index, recipe) in chosen.enumerated() {
            progress[index].state = t("устанавливается…")
            let ok = await state.install(recipe)
            progress[index].state = ok ? t("готово") : t("не удалось")
        }
        installing = false
        step = .done
    }
}
