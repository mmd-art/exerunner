import SwiftUI

/// Bounded, searchable installed-file selection. Paths disambiguate duplicate EXE names.
struct ExecutableChooser: View {
    let candidates: [URL]
    let driveC: URL
    @Binding var chosen: URL?
    var error: String? = nil
    let browse: () -> Void
    let cancel: () -> Void
    let add: () -> Void
    @State var query = ""
    @State private var expanded = Set<String>()
    @State private var moreExpanded = Set<String>()

    private var groups: [ExecutableDiscovery.Group] {
        ExecutableDiscovery.groups(candidates, driveC: driveC, query: query)
    }
    private var searching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t("Какой файл запускать?")).font(.headline)
            Text(t("Файлы сгруппированы по папкам установки. Выбери основной EXE или укажи его вручную."))
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                TextField(t("Поиск по имени или пути"), text: $query).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("executable-search")
                if !query.isEmpty { Button(t("Очистить")) { query = "" } }
                Text("\(groups.reduce(0) { $0 + $1.files.count }) / \(Set(candidates).count)")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            List(selection: $chosen) {
                ForEach(groups) { group in
                    DisclosureGroup(isExpanded: expansion(group.id, in: $expanded)) {
                        ForEach(group.primary, id: \.self) { url in row(url).tag(url) }
                        if !group.additional.isEmpty {
                            DisclosureGroup(isExpanded: expansion(group.id, in: $moreExpanded)) {
                                ForEach(group.additional, id: \.self) { url in row(url).tag(url) }
                            } label: {
                                Text(t("Дополнительные EXE")).foregroundStyle(.secondary)
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "folder")
                            Text(group.title).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text("\(group.files.count)").foregroundStyle(.secondary)
                        }.help(group.title)
                    }
                }
                if groups.isEmpty {
                    Text(candidates.isEmpty ? t("EXE не найдены. Выбери файл вручную.") : t("Совпадений нет. Измени поиск или выбери файл вручную."))
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.inset).frame(height: 240)
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
        .onAppear { if let first = groups.first { expanded.insert(first.id) } }
    }

    private func expansion(_ id: String, in values: Binding<Set<String>>) -> Binding<Bool> {
        Binding(get: { searching || values.wrappedValue.contains(id) }, set: { value in
            if value { values.wrappedValue.insert(id) } else { values.wrappedValue.remove(id) }
        })
    }

    private func row(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(url.lastPathComponent).lineLimit(1)
            Text(ExecutableDiscovery.path(url, driveC: driveC)).font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
        }.help(ExecutableDiscovery.path(url, driveC: driveC))
    }
}
