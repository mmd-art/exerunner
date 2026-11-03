import Foundation

extension AppState {
    var storageModelKey: String {
        allItems.map { [$0.id, $0.bottle, $0.executable, steamFolders[$0.id] ?? ""].joined(separator: "|") }.joined(separator: "\n")
            + bottlesRoot.path + (engine?.root.path ?? "") + bottleItems.map { settings(forBottle: $0.bottle).enginePath ?? "" }.joined(separator: "|")
    }
    func refreshStorage() {
        storageTask?.cancel()
        let entries = allItems.map { item in
            StorageSources.Item(id: item.id, bottle: item.bottle, executable: item.executable,
                steamGame: item.isSteamGame, steamClient: item.kind == .launcher && item.recipeID == "steam",
                gameFolder: steamFolders[item.id], explicitFolder: storageFolders[item.id])
        }
        let owners = Set(entries.map(\.id))
        var unavailable = false
        var engines = Set<URL>()
        for name in Set(bottleItems.map(\.bottle)) {
            do {
                let selected = try selectedEngine(forBottle: name)
                if selected.isPortable { engines.insert(selected.root) } else { unavailable = true }
            } catch { unavailable = true }
        }
        engines.insert(Paths.d3dmetal)
        // The app already contains its bundled engine; nested roots are partitioned, never added twice.
        let shared: [StorageScan.Claim] = [
            .init(id: "runtime", kind: .runtime, owners: owners, roots: [Bundle.main.bundleURL] + Array(engines)),
            .init(id: "runner-cache", kind: .cache, owners: owners, roots: [Paths.caches]),
            .init(id: "runner-data", kind: .data, owners: owners, roots: [Paths.support, Paths.logs])
        ]
        let input = StorageSources.Input(items: entries, bottlesRoot: bottlesRoot, shared: shared, unavailableSources: unavailable)
        let worker = Task.detached(priority: .utility) { StorageSources.measure(input) }
        storageScanning = true
        storageTask = Task { @MainActor [weak self] in
            await withTaskCancellationHandler {
                let snapshot = await worker.value
                guard !Task.isCancelled else { return }
                self?.storage = snapshot; self?.storageScanning = false
            } onCancel: { worker.cancel() }
        }
    }
    func selectStorageFolder(for item: LibraryItem, folder: URL) throws {
        // Explicit user choice is read-only and session-only, never changes library/settings.
        let selected = StorageScan.canonical(folder)
        let bottle = Bottle(name: item.bottle, root: bottlesRoot)
        let target = item.isSteamGame ? steamFolders[item.id] : item.executable
        guard let target, let exe = bottle.hostURL(forWindowsPath: target),
              StorageScan.realDirectory(selected), StorageScan.contains(exe.resolvingSymlinksInPath(), in: selected),
              !StorageScan.contains(bottle.driveC, in: selected),
              !StorageScan.contains(bottlesRoot, in: selected),
              selected.pathComponents.count >= 4 else {
            throw AppError(t("Выбери отдельную папку программы, содержащую её EXE, а не всю Windows-среду."))
        }
        storageFolders[item.id] = selected
        refreshStorage()
    }
}
