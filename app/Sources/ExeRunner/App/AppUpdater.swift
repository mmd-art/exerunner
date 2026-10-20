import AppKit
import Combine
import Sparkle

/// Manual, signed updates. Merely opening Settings or rendering a snapshot does not start Sparkle.
@MainActor
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = AppUpdater()
    @Published private(set) var ready = false
    @Published private(set) var status: String?
    @Published private(set) var preparingRestart = false
    weak var state: AppState?
    private var stagedInstallation = false
    private var installationAttemptInThisCycle = false
    private let pendingKey = "ExeRunnerPendingUpdateFromBuild"
    private var controller: SPUStandardUpdaterController?
    private var delayedInstall: (() -> Void)?
    private var waiter: Task<Void, Never>?

    func start(state: AppState) {
        self.state = state
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        stagedInstallation = build != nil && UserDefaults.standard.string(forKey: pendingKey) == build
        guard controller == nil else { return }
        let value = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        controller = value
        do { try value.updater.start(); ready = true }
        catch { status = error.localizedDescription }
    }

    var busy: Bool {
        guard let state else { return true }
        if !state.running.isEmpty || state.activity != nil || !state.componentInstalls.isEmpty
            || !state.installing.isEmpty || state.isShuttingDown || state.saveOperations.count > 0 { return true }
        // A shortcut/headless run need not be in the GUI's running set. Match live clients,
        // including wineserver, by prefix and by the engine inside the app being replaced.
        let prefix = state.bottlesRoot.standardizedFileURL.path + "/"
        let bundle = Bundle.main.bundleURL.standardizedFileURL.path + "/"
        return WineProcesses.list(includeServers: true).contains {
            $0.prefix.hasPrefix(prefix) || $0.path.hasPrefix(bundle)
        }
    }

    func check() {
        guard ready, let controller else { return }
        guard !busy else {
            status = t("Закрой Windows-программы и дождись завершения операций перед обновлением.")
            let alert = NSAlert(); alert.messageText = status!; alert.runModal()
            return
        }
        status = nil
        if !controller.updater.sessionInProgress { installationAttemptInThisCycle = false }
        controller.checkForUpdates(nil)
    }

    /// Backstop for all termination paths, including Sparkle's already-staged install path,
    /// which is not guaranteed to call the postpone delegate.
    var mustDeferTermination: Bool { (stagedInstallation || controller?.updater.sessionInProgress == true) && busy }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        if busy { throw NSError(domain: "ExeRunner.Updates", code: 1,
            userInfo: [NSLocalizedDescriptionKey: t("Закрой Windows-программы и дождись завершения операций перед обновлением.")]) }
    }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        if !busy { reserveRestart(); return false }
        delayedInstall = installHandler
        status = t("Обновление загружено. Перезапуск — после закрытия Windows-программ.")
        waiter?.cancel()
        waiter = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                if !self.busy {
                    self.reserveRestart()
                    let handler = self.delayedInstall; self.delayedInstall = nil
                    handler?()
                    return
                }
            }
        }
        return true
    }

    private func markStaged() {
        stagedInstallation = true
        UserDefaults.standard.set(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion"), forKey: pendingKey)
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        installationAttemptInThisCycle = true
        markStaged()
    }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock: @escaping () -> Void) -> Bool {
        markStaged()
        return false
    }

    private func reserveRestart() {
        preparingRestart = true
        state?.updateRestartPending = true
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        waiter?.cancel(); delayedInstall = nil
        // A failed newer check (busy/network/no-update) does not cancel an older
        // install-on-quit. Only Sparkle's confirmed cancellation of this installer does.
        let failure = error as NSError
        if installationAttemptInThisCycle && failure.domain == SUSparkleErrorDomain
            && failure.code == Int(SUError.installationCanceledError.rawValue) {
            stagedInstallation = false
            UserDefaults.standard.removeObject(forKey: pendingKey)
        }
        installationAttemptInThisCycle = false
        preparingRestart = false; state?.updateRestartPending = false
        status = error.localizedDescription
    }
}
