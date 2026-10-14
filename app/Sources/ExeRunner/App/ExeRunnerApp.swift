import SwiftUI

struct ExeRunnerApp: App {
    @StateObject private var state = AppState()
    @NSApplicationDelegateAdaptor(ExeRunnerDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup(AppInfo.name) {
            RootView()
                .environmentObject(state)
                .onAppear { delegate.state = state }
                .frame(minWidth: 940, minHeight: 640)
        }
        .windowToolbarStyle(.unified)
        .commands { CommandGroup(replacing: .newItem) {} }
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
                NSApplication.shared.windows.first(where: { $0.styleMask.contains(.titled) })?.performClose(nil)
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
    enum Section: Hashable { case library, catalog, settings }
    @State private var section: Section?

    init(section: Section = .library) {
        _section = State(initialValue: CommandLine.arguments.contains("--settings") ? .settings : section)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                Label(t("Библиотека"), systemImage: "square.grid.2x2").tag(Section.library)
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
