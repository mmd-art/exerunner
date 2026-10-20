import SwiftUI

struct ExeRunnerApp: App {
    @StateObject private var state = AppState()
    @StateObject private var updater = AppUpdater.shared
    @NSApplicationDelegateAdaptor(ExeRunnerDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup(AppInfo.name) {
            RootView()
                .environmentObject(state)
                .disabled(state.updateRestartPending)
                .onAppear {
                    delegate.state = state
                    updater.start(state: state)
                }
                .frame(minWidth: 940, minHeight: 640)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button(t("Проверить обновления…")) { updater.check() }.disabled(!updater.ready)
            }
            CommandMenu(t("Недавние приложения")) {
                if state.recentItems.isEmpty { Text(t("Пока нет запусков")) }
                ForEach(state.recentItems) { item in
                    Button(item.name) { state.launch(item) }.disabled(state.running.contains(item.id) || state.isShuttingDown)
                }
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Group {
            if state.settings.onboardingCompleted { MainView() } else { OnboardingView() }
        }
        .task {
            await state.refresh()
            state.watchProcesses()
            // Native lifecycle diagnostic: close our actual main window, exercising the
            // last-window callback and the same termination path as a user click.
            if CommandLine.arguments.contains("--verify-close") {
                try? await Task.sleep(for: .seconds(1))
                if let window = NSApplication.shared.windows.first(where: { $0.styleMask.contains(.titled) }) {
                    if let index = CommandLine.arguments.firstIndex(of: "--verify-close"),
                       index + 1 < CommandLine.arguments.count,
                       let view = window.contentView,
                       let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                        view.cacheDisplay(in: view.bounds, to: bitmap)
                        let path = URL(fileURLWithPath: CommandLine.arguments[index + 1])
                            .deletingPathExtension().appendingPathExtension("png")
                        try? bitmap.representation(using: .png, properties: [:])?.write(to: path)
                    }
                    window.performClose(nil)
                }
            }
        }
        .alert(t("Что-то пошло не так"), isPresented: Binding(
            get: { state.errorMessage != nil },
            set: { if !$0 { state.errorMessage = nil } }
        )) {
            Button(t("Понятно")) { state.errorMessage = nil }
        } message: {
            Text(state.errorMessage ?? "")
        }
    }
}

struct MainView: View {
    @EnvironmentObject private var state: AppState
    enum Section: Hashable { case library, catalog, history, settings }
    @State private var section: Section?

    init(section: Section = .library) {
        _section = State(initialValue: CommandLine.arguments.contains("--settings") ? .settings : section)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                Label(t("Библиотека"), systemImage: "square.grid.2x2").tag(Section.library)
                Label(t("История"), systemImage: "clock.arrow.circlepath").tag(Section.history)
                Label(t("Каталог"), systemImage: "bag").tag(Section.catalog)
                Label(t("Настройки"), systemImage: "gearshape").tag(Section.settings)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            .safeAreaInset(edge: .bottom) { EngineFooter().padding(14) }
        } detail: {
            VStack(spacing: 0) {
                switch section ?? .library {
                case .library: LibraryView(openCatalog: { section = .catalog })
                case .catalog: CatalogView()
                case .history: HistoryView()
                case .settings: SettingsView()
                }
                ActivityBar()
            }
            // every text is read again in the new language
            .id(state.settings.language)
        }
    }
}

private struct EngineFooter: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(state.engine == nil ? t("Движок не найден") : (state.engineVersion ?? t("Движок")), systemImage: "cpu")
            Label(state.engine?.d3dmetalVersion.map { "D3DMetal \($0)" } ?? t("D3DMetal не подключён"), systemImage: "cube.transparent")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
