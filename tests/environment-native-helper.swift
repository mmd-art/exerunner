import Foundation

/// Exercises the same COM preparation/import path as AppState.run in a test-owned prefix.
@main struct EnvironmentNativeControl {
    @MainActor static func main() async throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 4 else { fatalError("engine prefix device-or-empty") }
        let engine = Engine(root: URL(fileURLWithPath: arguments[1], isDirectory: true))
        let prefix = URL(fileURLWithPath: arguments[2], isDirectory: true)
        var settings = AppSettings()
        settings.enginePath = engine.root.path; settings.bottlesPath = prefix.deletingLastPathComponent().path
        settings.language = .english; settings.gameBoost = false
        var configuration = BottleSettings()
        if !arguments[3].isEmpty { configuration.serialPorts = [.init(number: 22, device: arguments[3])] }
        let state = AppState(managesGameBoost: false, initialSettings: settings, initialItems: [],
            initialBottleSettings: [prefix.lastPathComponent: configuration])
        let bottle = Bottle(name: prefix.lastPathComponent, root: prefix.deletingLastPathComponent())
        if arguments[3].hasPrefix("controller:"), let mode = BottleSettings.ControllerMode(rawValue: String(arguments[3].dropFirst(11))) {
            try await ControllerMapping.apply(mode, in: bottle, engine: engine, log: prefix.deletingLastPathComponent().appendingPathComponent("controller-policy.log"))
            print("PASS: native controller policy " + mode.rawValue)
            return
        }
        try await state.prepareSerialPorts(bottle, engine: engine, log: prefix.deletingLastPathComponent().appendingPathComponent("mapper.log"))
        await WineProcess.server("-w", engine: engine, environment: WineEnvironment.make(engine: engine, prefix: prefix))
        let values = BottleManager.registryValues(in: bottle, hive: "system.reg", key: "Software\\\\Wine\\\\Ports") ?? [:]
        let managed = try SerialPortMapper.managed(in: bottle)
        if configuration.serialPorts.isEmpty {
            guard values["com22"] == nil && managed.isEmpty else { fatalError("managed COM removal failed") }
        } else {
            guard values["com22"] == arguments[3] && managed == configuration.serialPorts else { fatalError("managed COM setup failed") }
        }
        guard values["com23"] == "/dev/cu.exerunner-manual-canary" else { fatalError("manual COM registry value changed") }
        print("PASS: native app COM preparation, Unicode registry import and manual-port preservation")
    }
}
