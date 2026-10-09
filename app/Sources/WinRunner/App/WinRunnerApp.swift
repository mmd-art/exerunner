import SwiftUI

struct WinRunnerApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup(AppInfo.name) {
            RootView()
                .environmentObject(state)
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
        }
        .alert("Что-то пошло не так", isPresented: Binding(
            get: { state.errorMessage != nil },
            set: { if !$0 { state.errorMessage = nil } }
        )) {
            Button("Понятно") { state.errorMessage = nil }
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
        _section = State(initialValue: section)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                Label("Библиотека", systemImage: "square.grid.2x2").tag(Section.library)
                Label("Каталог", systemImage: "bag").tag(Section.catalog)
                Label("Настройки", systemImage: "gearshape").tag(Section.settings)
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
        }
    }
}

private struct EngineFooter: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(state.engine == nil ? "Движок не найден" : (state.engineVersion ?? "Движок"), systemImage: "cpu")
            Label(state.engine?.d3dmetalVersion.map { "D3DMetal \($0)" } ?? "D3DMetal не подключён", systemImage: "cube.transparent")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
