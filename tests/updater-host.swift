// Disposable integration host: drives Sparkle's real download/install/relaunch path.
// It links the production AppUpdater delegate, with synthetic launch/process state only.
import AppKit
import Combine
import Sparkle

func t(_ value: String) -> String { value }
@MainActor final class AppState {
 var running = Set<String>(); var activity: String?; var componentInstalls = Set<String>()
 var installing: [String] = []; var isShuttingDown = false; var updateRestartPending = false
 var saveOperations = SaveOperations()
 var bottlesRoot = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("FixturePrefixes")
}
struct SaveOperations { var count = 0 }
enum WineProcesses {
 struct Entry { var path: String; var prefix: String }
 static var entries: [Entry] = []
 static func list(includeServers: Bool) -> [Entry] { entries }
}
@MainActor final class Driver: NSObject, SPUUserDriver {
 weak var state: AppState?
 var updaterForPolicy: SPUUpdater?
 func show(_ error: Error) { receipt("error: \(error.localizedDescription)"); exit(3) }
 func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) { fatalError("No automatic update permission expected") }
 func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) { receipt("checking") }
 func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) { receipt("found")
  let policy = AppUpdater.shared
  policy.updater(updaterForPolicy!, willInstallUpdate: appcastItem)
  self.state?.running = ["synthetic-game"]
  precondition(policy.mustDeferTermination, "Staged update must guard quit even without active check session")
  self.state?.running = []
  policy.updater(updaterForPolicy!, didAbortWithError: NSError(domain: "ExeRunner.Updates", code: 1))
  self.state?.running = ["synthetic-game"]
  precondition(policy.mustDeferTermination, "An aborted check cleared an existing staged installation")
  policy.updater(updaterForPolicy!, willInstallUpdate: appcastItem)
  policy.updater(updaterForPolicy!, didAbortWithError: NSError(domain: SUSparkleErrorDomain, code: Int(SUError.installationCanceledError.rawValue)))
  precondition(!policy.mustDeferTermination, "Confirmed install cancellation should release the staged guard")
  self.state?.running = []
  policy.updater(updaterForPolicy!, willInstallUpdate: appcastItem)
  receipt("staged-termination-policy-passed")
  reply(.install) }
 func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
 func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) { show(error) }
 func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) { show(error) }
 func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) { show(error) }
 func showDownloadInitiated(cancellation: @escaping () -> Void) { receipt("downloading") }
 func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
 func showDownloadDidReceiveData(ofLength length: UInt64) {}
 func showDownloadDidStartExtractingUpdate() { receipt("preparing-verification-extraction") }
 func showExtractionReceivedProgress(_ progress: Double) { receipt("extracting") }
 func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
  receipt("ready")
  self.state?.running = ["synthetic-game"]
  Task { @MainActor in
   try? await Task.sleep(for: .seconds(3))
   precondition(self.state?.updateRestartPending == false, "Restart reserved while game still active")
   receipt("busy-install-wait-passed")
   self.state?.running = []
  }
  reply(.install)
 }
 func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) { receipt("installing") }
 func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { receipt("installed"); acknowledgement() }
 func dismissUpdateInstallation() {}
}
func receipt(_ value: String) {
 let path = URL(fileURLWithPath: Bundle.main.object(forInfoDictionaryKey: "FixtureRoot") as! String).appendingPathComponent("update-proof.txt")
 let previous = (try? String(contentsOf: path, encoding: .utf8)) ?? ""
 try! (previous + value + "\n").write(to: path, atomically: true, encoding: .utf8)
}
@MainActor final class Host: NSObject, NSApplicationDelegate {
 let state = AppState(); let driver = Driver(); var updater: SPUUpdater!
 func applicationDidFinishLaunching(_ notification: Notification) {
  if Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String == "2" { receipt("relaunched-version-2"); exit(0) }
  let policy = AppUpdater.shared; policy.state = state
  updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: policy)
  driver.state = state; driver.updaterForPolicy = updater
  do {
   state.running = ["synthetic-game"]
   precondition(policy.busy)
   do { try policy.updater(updater, mayPerform: .updates); fatalError("Busy check allowed") } catch {}
   state.running = []
   state.activity = "installer"; precondition(policy.busy); state.activity = nil
   state.componentInstalls = ["fixture"]; precondition(policy.busy); state.componentInstalls = []
   WineProcesses.entries = [.init(path: "C:\\game.exe", prefix: state.bottlesRoot.appendingPathComponent("fixture").path)]
   precondition(policy.busy); WineProcesses.entries = []
   state.saveOperations.count = 1; precondition(policy.busy); state.saveOperations.count = 0
   precondition(!policy.busy)
   receipt("busy-policy-passed")
   try updater.start()
   updater.checkForUpdates()
  } catch { driver.show(error) }
 }
 func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
  if AppUpdater.shared.mustDeferTermination { receipt("termination-deferred"); return .terminateCancel }
  receipt("termination-allowed"); return .terminateNow
 }
}
@main struct Main {
 @MainActor static func main() {
  let app = NSApplication.shared
  app.setActivationPolicy(.prohibited)
  let host = Host(); app.delegate = host
  withExtendedLifetime(host) { app.run() }
 }
}
