import AppKit
let config=NSWorkspace.OpenConfiguration()
config.activates=false
config.createsNewApplicationInstance=true
NSWorkspace.shared.openApplication(at: URL(fileURLWithPath:CommandLine.arguments[1]),configuration:config) { app,error in
    print("LS_OPEN_PID=\(app?.processIdentifier ?? 0) ERROR=\(String(describing:error))")
    exit(error == nil ? 0 : 1)
}
DispatchQueue.main.asyncAfter(deadline:.now()+8){ print("LS_OPEN_TIMEOUT");exit(2) }
RunLoop.main.run()
