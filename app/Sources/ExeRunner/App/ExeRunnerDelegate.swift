import AppKit

@MainActor
final class ExeRunnerDelegate: NSObject, NSApplicationDelegate {
    weak var state: AppState?
    private var terminationPending = false

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let state else { return .terminateNow }
        guard !terminationPending else { return .terminateLater }
        terminationPending = true
        Task { @MainActor in
            await state.shutdown()
            if let index = CommandLine.arguments.firstIndex(of: "--verify-close"),
               index + 1 < CommandLine.arguments.count {
                let proof: [String: Any] = ["terminationDelegateReached": true,
                                           "remainingWineProcesses": WineProcesses.list().count,
                                           "runningItems": state.running.sorted(),
                                           "libraryItemCount": state.allItems.count,
                                           "bottleSettingsCount": state.bottleSettings.count,
                                           "onboardingCompleted": state.settings.onboardingCompleted,
                                           "home": Paths.home.path,
                                           "support": Paths.support.path,
                                           "caches": Paths.caches.path,
                                           "logs": Paths.logs.path,
                                           "shortcuts": Paths.shortcuts.path,
                                           "engine": state.engine?.root.path ?? "",
                                           "engineVersion": state.engineVersion ?? ""]
                if let data = try? JSONSerialization.data(withJSONObject: proof, options: [.sortedKeys]) {
                    try? data.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
                }
            }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
