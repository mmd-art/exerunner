import AppKit
let app = URL(fileURLWithPath: CommandLine.arguments[1])
let url = URL(string: CommandLine.arguments[2])!
let config = NSWorkspace.OpenConfiguration()
config.activates = false
config.createsNewApplicationInstance = false
NSWorkspace.shared.open([url], withApplicationAt: app, configuration: config) { app, error in
    print("EXISTING_URL_PID=\(app?.processIdentifier ?? 0) ERROR=\(String(describing: error))")
    exit(error == nil ? 0 : 1)
}
DispatchQueue.main.asyncAfter(deadline: .now() + 8) { print("EXISTING_URL_TIMEOUT"); exit(2) }
RunLoop.main.run()
