import SwiftUI

struct RuntimeComponentsView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    let item: LibraryItem
    @State private var installed: Set<String> = []
    @State private var available: Set<String> = []
    @State private var suggested: Set<String> = []
    @State private var selected: Set<String> = []
    @State private var busy = false
    @State private var inspection: PEInspection?

    private var bottle: Bottle { Bottle(name: item.bottle, root: state.bottlesRoot) }
    private var outstanding: Set<String> { Set(suggested.filter { !Winetricks.satisfies($0, installed: installed) }) }
    private var blocked: Bool { item.isolated || item.bottle.hasPrefix("isolated-") || state.engine == nil || busy }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(t("Библиотеки Windows")).font(.title2.weight(.semibold))
            Text(t("Общие компоненты для программ в бутылке «\(item.bottle)».")).foregroundStyle(.secondary)
            if let inspection {
                Text("\(item.executableName) · \(inspection.architecture.rawValue)\(inspection.managed ? " · .NET" : "")")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Text(t("Wine, Mono и Gecko входят в движок. Дополнительные библиотеки загружаются при установке и сохраняются для повторного использования."))
                .font(.callout).foregroundStyle(.secondary)
            if item.isolated || item.bottle.hasPrefix("isolated-") {
                Text(t("Автоматическая установка компонентов в изолированном прототипе пока недоступна."))
                    .font(.callout).foregroundStyle(.orange)
            }
            if !outstanding.isEmpty {
                Button(t("Выбрать обнаруженные зависимости")) { selected.formUnion(outstanding.intersection(available)) }
                    .disabled(blocked)
            }
            List {
                ForEach(RuntimeComponent.Group.allCases) { group in
                    Section(group.title) {
                        ForEach(RuntimeComponent.all.filter { $0.group == group }) { component in
                            HStack {
                                Toggle(component.title, isOn: Binding(get: { selected.contains(component.id) }, set: {
                                    if $0 { selected.insert(component.id) } else { selected.remove(component.id) }
                                }))
                                .toggleStyle(.checkbox)
                                .disabled(blocked || Winetricks.satisfies(component.id, installed: installed) || !available.contains(component.id))
                                Spacer()
                                if Winetricks.satisfies(component.id, installed: installed) {
                                    Text(t("Установлено")).font(.caption).foregroundStyle(.green)
                                } else if !available.contains(component.id) {
                                    Text(t("Нет в текущем движке")).font(.caption).foregroundStyle(.secondary)
                                } else if suggested.contains(component.id) {
                                    Text(t("Зависимость EXE")).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
            Text(t("Нативный .NET Framework заменяет Mono в этой бутылке. Выбирай его, если программа требует именно Microsoft .NET Framework."))
                .font(.caption).foregroundStyle(.secondary)
            if busy { Text(state.activity ?? t("Устанавливаю библиотеки Windows…")).font(.callout); ProgressView() }
            HStack {
                Button(t("Обновить")) { reload() }.disabled(busy)
                Spacer()
                Button(t("Закрыть")) { dismiss() }.disabled(busy)
                Button(t("Установить выбранные (\(selected.count))")) {
                    Task {
                        busy = true
                        _ = await state.installRuntimeComponents(selected.sorted(), for: item)
                        reload()
                        busy = false
                    }
                }
                .buttonStyle(.pillProminent)
                .disabled(blocked || selected.isEmpty || state.componentInstalls.contains(item.bottle))
            }
            .buttonStyle(.pill)
        }
        .padding(22)
        .frame(width: 650, height: 740)
        .onAppear(perform: reload)
        .interactiveDismissDisabled(busy)
    }

    private func reload() {
        installed = Winetricks.installed(in: bottle)
        available = state.engine.map { Winetricks.available(in: $0) } ?? []
        if let file = bottle.hostURL(forWindowsPath: item.executable) {
            inspection = PEInspection.read(file)
            suggested = Set(RuntimeComponent.suggested(for: file, available: available, installed: installed))
        }
        selected = Set(selected.filter { !Winetricks.satisfies($0, installed: installed) })
    }
}
