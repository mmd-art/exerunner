import AppKit
import Foundation

/// Without arguments the app opens its window. `--launch <id>` starts one library item without
/// UI (the shortcuts in ~/Applications call this); `--install <recipe>` installs a catalog entry
/// headless; `--stop <id>` stops one the way its Stop button does; `--report <id>` saves the
/// helper's report zip; `--components <bottle> <verb,verb>` installs Windows components;
/// `--import-d3dmetal <dmg or
/// folder>` imports D3DMetal from Apple's download;
/// `--self-test` prints a status report; `--snapshot <dir>` renders screens to PNG.
@main
enum Entry {
    static func main() {
        Migration.run()
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--launch"), index + 1 < args.count {
            Headless.launch(itemID: args[index + 1])
        } else if let index = args.firstIndex(of: "--install"), index + 1 < args.count {
            Headless.install(recipeID: args[index + 1])
        } else if let index = args.firstIndex(of: "--report"), index + 1 < args.count {
            Headless.report(itemID: args[index + 1])
        } else if let index = args.firstIndex(of: "--components"), index + 2 < args.count {
            Headless.components(bottle: args[index + 1], verbs: args[index + 2].split(separator: ",").map(String.init))
        } else if let index = args.firstIndex(of: "--stop"), index + 1 < args.count {
            Headless.stop(itemID: args[index + 1])
        } else if let index = args.firstIndex(of: "--import-d3dmetal"), index + 1 < args.count {
            Headless.importD3DMetal(from: URL(fileURLWithPath: args[index + 1]))
        } else if args.contains("--self-test") {
            Headless.selfTest()
        } else if let index = args.firstIndex(of: "--snapshot"), index + 1 < args.count {
            Headless.snapshot(to: URL(fileURLWithPath: args[index + 1], isDirectory: true))
        } else {
            ExeRunnerApp.main()
        }
    }
}

enum Headless {
    static func launch(itemID: String) -> Never {
        Task { @MainActor in
            let state = AppState()
            await state.refresh()
            guard let item = state.allItems.first(where: { $0.id == itemID }) else {
                FileHandle.standardError.write(Data("no library item \(itemID)\n".utf8))
                exit(1)
            }
            do {
                let status = try await state.run(item)
                // a Steam client started for the game stays ours until it quits (and restarts after updates)
                await state.waitForClients()
                exit(status)
            } catch {
                FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
                exit(1)
            }
        }
        dispatchMain()
    }

    static func install(recipeID: String) -> Never {
        Task { @MainActor in
            let state = AppState()
            await state.refresh()
            guard let recipe = state.recipe(recipeID) else {
                FileHandle.standardError.write(Data("no recipe \(recipeID)\n".utf8))
                exit(1)
            }
            let ok = await state.install(recipe)
            if let message = state.errorMessage { FileHandle.standardError.write(Data("\(message)\n".utf8)) }
            print(state.report())
            exit(ok ? 0 : 1)
        }
        dispatchMain()
    }

    /// The helper's report zip for one item, with the checks of every area, into Downloads
    static func report(itemID: String) -> Never {
        Task { @MainActor in
            let state = AppState()
            await state.refresh()
            guard let item = state.allItems.first(where: { $0.id == itemID }) else {
                FileHandle.standardError.write(Data("no library item \(itemID)\n".utf8))
                exit(1)
            }
            var checks: [Check] = []
            for symptom in Symptom.allCases { checks += await state.checks(for: symptom, item: item) }
            guard let zip = await state.exportReport(for: item, checks: checks) else {
                FileHandle.standardError.write(Data("\(state.errorMessage ?? "no report")\n".utf8))
                exit(1)
            }
            print(zip.path)
            exit(0)
        }
        dispatchMain()
    }

    /// Windows components into a bottle through winetricks, the way a launch installs them
    static func components(bottle name: String, verbs: [String]) -> Never {
        Task { @MainActor in
            let state = AppState()
            await state.refresh()
            guard let engine = state.engine else { FileHandle.standardError.write(Data("no engine\n".utf8)); exit(1) }
            let bottle = Bottle(name: name, root: state.bottlesRoot)
            let log = Paths.logFile("\(name)-components")
            do {
                try await BottleManager.ensure(bottle, engine: engine, log: log)
                try await BottleManager.applyDefaults(bottle, engine: engine, log: log)
                try await Winetricks.ensure(verbs, in: bottle, engine: engine, log: log) { print($0) }
                print("installed \(verbs.joined(separator: ", ")) in \(name): \(Winetricks.installed(in: bottle).sorted())")
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
                exit(1)
            }
        }
        dispatchMain()
    }

    /// The same as the item's Stop button: a game alone, a launcher with its bottle
    static func stop(itemID: String) -> Never {
        Task { @MainActor in
            let state = AppState()
            await state.refresh()
            await state.refreshProcesses()
            guard let item = state.allItems.first(where: { $0.id == itemID }) else {
                FileHandle.standardError.write(Data("no library item \(itemID)\n".utf8))
                exit(1)
            }
            await state.stop(item)
            print("running after stop: \(state.running.sorted())")
            exit(0)
        }
        dispatchMain()
    }

    static func importD3DMetal(from url: URL) -> Never {
        Task { @MainActor in
            let state = AppState()
            await state.refresh()
            let version = await state.importD3DMetal(from: url)
            if let message = state.errorMessage { FileHandle.standardError.write(Data("\(message)\n".utf8)) }
            print(version.map { "D3DMetal \($0) imported into \(Paths.d3dmetal.path)" } ?? "D3DMetal not imported")
            exit(version == nil ? 1 : 0)
        }
        dispatchMain()
    }

    static func snapshot(to dir: URL) -> Never {
        // an app object without a window: views need NSApplication, nothing shows on screen
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        Task { @MainActor in
            await Snapshots.render(to: dir)
            exit(0)
        }
        app.run()
        exit(0)
    }

    static func selfTest() -> Never {
        Task { @MainActor in
            let state = AppState()
            await state.refresh()
            await state.refreshProcesses()
            print(state.report())
            exit(0)
        }
        dispatchMain()
    }
}
