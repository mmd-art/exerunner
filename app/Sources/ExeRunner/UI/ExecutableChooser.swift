import SwiftUI

/// Application names first; a bounded, searchable tree for technical EXE selection.
struct ExecutableChooser: View {
    let candidates: [URL]
    let driveC: URL
    var shortcuts: [InstalledShortcut] = []
    @Binding var chosen: URL?
    var error: String? = nil
    let browse: () -> Void
    let cancel: () -> Void
    let add: () -> Void
    var selectProgram: ((InstalledShortcut) -> Void)? = nil
    @State var query = ""
    @State private var expanded = Set<String>()

    private var searching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var programs: [InstalledShortcut] {
        shortcuts.filter { app in
            query.split(whereSeparator: { $0.isWhitespace }).allSatisfy {
                (app.name + " " + ExecutableDiscovery.path(app.executable, driveC: driveC)).localizedCaseInsensitiveContains($0)
            }
        }
    }
    private var ordinary: [URL] { candidates.filter { !ExecutableTree.systemUtility($0, driveC: driveC) } }
    private var system: [URL] { candidates.filter { ExecutableTree.systemUtility($0, driveC: driveC) } }
    private struct Row: Identifiable {
        let id: String
        let title: String
        let url: URL?
        let depth: Int
        let count: Int
        let helper: Bool
    }
    private var rows: [Row] {
        var result: [Row] = []
        func walk(_ nodes: [ExecutableTree.Node], depth: Int) {
            let helpers = nodes.filter { $0.executable && ExecutableDiscovery.additional($0.url) }
            for node in nodes where !node.executable || !ExecutableDiscovery.additional(node.url) {
                result.append(Row(id: node.id, title: node.url.lastPathComponent, url: node.url,
                                  depth: depth, count: node.executable ? 0 : node.count, helper: false))
                if !node.executable && (searching || expanded.contains(node.id)) { walk(node.children, depth: depth + 1) }
            }
            if let first = helpers.first {
                let id = "helpers:" + first.url.deletingLastPathComponent().path
                result.append(Row(id: id, title: t("Дополнительные EXE"), url: nil, depth: depth, count: helpers.count, helper: true))
                if searching || expanded.contains(id) {
                    for node in helpers {
                        result.append(Row(id: node.id, title: node.url.lastPathComponent, url: node.url,
                                          depth: depth + 1, count: 0, helper: true))
                    }
                }
            }
        }
        func section(_ id: String, _ title: String, _ files: [URL], defaultOpen: Bool) {
            let matching = files.filter { ExecutableTree.matches($0, driveC: driveC, query: query) }
            guard !matching.isEmpty else { return }
            result.append(Row(id: id, title: title, url: nil, depth: 0, count: matching.count, helper: false))
            if searching || expanded.contains(id) || (defaultOpen && !expanded.contains("closed:" + id)) {
                walk(ExecutableTree.roots(matching, driveC: driveC, query: query), depth: 1)
            }
        }
        section("all", t("Все EXE"), ordinary, defaultOpen: shortcuts.isEmpty)
        section("system", t("Системные утилиты Wine"), system, defaultOpen: false)
        return result
    }
    private func open(_ row: Row) -> Bool {
        searching || expanded.contains(row.id) || (row.id == "all" && shortcuts.isEmpty && !expanded.contains("closed:all"))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t("Какую программу добавить?")).font(.headline)
            Text(t("Выбери программу по ярлыку или раскрой папки в «Все EXE». Поиск работает по названию и полному пути."))
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                TextField(t("Поиск по имени или пути"), text: $query).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("executable-search")
                if !query.isEmpty { Button(t("Очистить")) { query = "" } }
                Text("\(Set(candidates.filter { ExecutableTree.matches($0, driveC: driveC, query: query) }).union(programs.map(\.executable)).count) / \(Set(candidates).count)")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            List {
                Section(t("Найденные программы")) {
                    ForEach(programs) { app in
                        Button {
                            chosen = app.executable
                            selectProgram?(app)
                        } label: {
                            HStack {
                                Image(systemName: "app")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.name).lineLimit(1)
                                    pathText(app.executable)
                                }
                                Spacer()
                                if chosen == app.executable { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain).help(ExecutableDiscovery.path(app.shortcut, driveC: driveC))
                    }
                    if programs.isEmpty {
                        Text(searching ? t("Ярлыки не найдены по запросу.") : t("Подходящих ярлыков нет. Выбери EXE в папках ниже."))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                ForEach(rows) { row in
                    if row.count > 0 {
                        Button {
                            if open(row) { expanded.remove(row.id); expanded.insert("closed:" + row.id) }
                            else { expanded.insert(row.id); expanded.remove("closed:" + row.id) }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: open(row) ? "chevron.down" : "chevron.right").font(.caption).frame(width: 12)
                                Image(systemName: row.helper ? "gearshape" : "folder")
                                Text(row.title).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text("\(row.count)").monospacedDigit().foregroundStyle(.secondary)
                            }.padding(.leading, CGFloat(row.depth * 12)).contentShape(Rectangle())
                        }.buttonStyle(.plain).help(row.url.map { ExecutableDiscovery.path($0, driveC: driveC) } ?? row.title)
                    } else if let url = row.url {
                        Button { chosen = url } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.title).lineLimit(1)
                                    pathText(url)
                                }
                                Spacer()
                                if chosen == url { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                            }.padding(.leading, CGFloat(row.depth * 12 + 18)).contentShape(Rectangle())
                        }.buttonStyle(.plain).help(ExecutableDiscovery.path(url, driveC: driveC))
                    }
                }
                if rows.isEmpty && programs.isEmpty {
                    Text(candidates.isEmpty ? t("EXE не найдены. Выбери файл вручную.") : t("Совпадений нет. Измени поиск или выбери файл вручную."))
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.inset).frame(height: 260)
            .accessibilityIdentifier("executable-list")
            Text(chosen.map { ExecutableDiscovery.path($0, driveC: driveC) } ?? t("Файл не выбран"))
                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                .help(chosen.map { ExecutableDiscovery.path($0, driveC: driveC) } ?? "")
            if let error { Text(error).font(.caption).foregroundStyle(.red).lineLimit(2) }
            HStack {
                Button(t("Выбрать EXE вручную…"), action: browse).accessibilityIdentifier("executable-browse")
                Spacer()
                Button(t("Отмена"), action: cancel).keyboardShortcut(.cancelAction)
                Button(t("Добавить в библиотеку"), action: add)
                    .buttonStyle(.pillProminent).keyboardShortcut(.defaultAction)
                    .disabled(chosen == nil).accessibilityIdentifier("executable-add")
            }.buttonStyle(.pill)
        }
    }

    private func pathText(_ url: URL) -> some View {
        Text(ExecutableDiscovery.path(url, driveC: driveC)).font(.caption).foregroundStyle(.secondary)
            .lineLimit(1).truncationMode(.middle)
    }
}

/// Shared with the installation sheet's screenshot fixture: same leading edge, no HStack centering.
struct InstallationProgress: View {
    let message: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ProgressView().progressViewStyle(.linear).frame(maxWidth: .infinity)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
