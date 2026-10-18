import Foundation
var checks = 0
func check(_ label: String, _ value: @autoclosure () -> Bool) {
    checks += 1
    if !value() { fatalError(label) }
}
let original = Data(#"<?xml version="1.0"?><GamerProfile><RenderProfile Quality="custom" MotionBlur="0" MainMonitor="0"><VideoMode adapterIndex="0" displayIndex="0" windowMode="0" width="3840" height="2160" refreshRateNumerator="60" refreshRateDenominator="1" /></RenderProfile><Quality Textures="ultra" Shadow="normal" /><Audio Name="Речь 🎮" Volume="0.8" /></GamerProfile>"#.utf8)
let laptop = NativeDisplayTarget(displayID: 1, outputIndex: 0, width: 3456, height: 2234, refreshRate: 120)
let dell = NativeDisplayTarget(displayID: 3, outputIndex: 1, width: 3840, height: 2160, refreshRate: 120)
let changed = try! NativeDisplayPolicy.patchedPrimal(original, target: laptop)!
let text = String(data: changed, encoding: .utf8)!
check("physical laptop pixels", text.contains(#"width="3456" height="2234""#))
check("refresh is the current screen", text.contains(#"refreshRateNumerator="120" refreshRateDenominator="1""#))
check("all quality and audio bytes preserved", text.contains(#"<Quality Textures="ultra" Shadow="normal" /><Audio Name="Речь 🎮" Volume="0.8" />"#))
check("fullscreen mode retained", text.contains(#"windowMode="0""#))
check("native idempotent", try! NativeDisplayPolicy.patchedPrimal(changed, target: laptop) == nil)
let external = try! NativeDisplayPolicy.patchedPrimal(changed, target: dell)!
let externalText = String(data: external, encoding: .utf8)!
check("external physical pixels", externalText.contains(#"width="3840" height="2160""#))
check("selected output", externalText.contains(#"MainMonitor="1""#) && externalText.contains(#"displayIndex="1""#))
let fractional = NativeDisplayTarget(displayID: 3, outputIndex: 0, width: 3840, height: 2160, refreshRate: 59.94)
let fractionalText = String(data: try! NativeDisplayPolicy.patchedPrimal(original, target: fractional)!, encoding: .utf8)!
check("fractional refresh", fractionalText.contains(#"refreshRateNumerator="2997" refreshRateDenominator="50""#))
let windowed = Data(String(data: original, encoding: .utf8)!.replacingOccurrences(of: #"windowMode="0""#, with: #"windowMode="1""#).utf8)
check("windowed choice preserved", try! NativeDisplayPolicy.patchedPrimal(windowed, target: laptop) == nil)
var rejected = false
do { _ = try NativeDisplayPolicy.patchedPrimal(Data("<invalid>".utf8), target: laptop) } catch { rejected = true }
check("malformed XML refused", rejected)
let temp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("native-display-test-\(UUID().uuidString)")
let documents = temp.appendingPathComponent("Documents"), backups = temp.appendingPathComponent("Backups")
let profile = documents.appendingPathComponent("My Games/Far Cry Primal/GamerProfile.xml")
try! FileManager.default.createDirectory(at: profile.deletingLastPathComponent(), withIntermediateDirectories: true)
try! original.write(to: profile)
try! FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: profile.path)
let update = try! NativeDisplayPolicy.prepare(adapter: "farcry-primal", documents: documents, target: laptop, backups: backups)!
check("original exact backup", try! Data(contentsOf: update.backup) == original)
check("only profile write", try! Data(contentsOf: profile) == changed)
check("permissions preserved", (try! FileManager.default.attributesOfItem(atPath: profile.path)[.posixPermissions] as! NSNumber).intValue == 0o640)
check("repeat launch does not rewrite", try! NativeDisplayPolicy.prepare(adapter: "farcry-primal", documents: documents, target: laptop, backups: backups) == nil)
check("unknown adapter cannot write", try! NativeDisplayPolicy.prepare(adapter: "unknown", documents: documents, target: dell, backups: backups) == nil)
check("unknown adapter left file exact", try! Data(contentsOf: profile) == changed)
let userSettings = try! JSONDecoder().decode(AppSettings.self, from: Data(#"{"gameBoost":true,"performanceHUD":true,"bottlesPath":"/test/bottles"}"#.utf8))
check("old settings enable safeguards", userSettings.cursorConfinement && userSettings.automaticNativeResolution)
check("old settings preserve choices", userSettings.gameBoost && userSettings.performanceHUD == true && userSettings.bottlesPath == "/test/bottles")
let disabled = try! JSONDecoder().decode(AppSettings.self, from: Data(#"{"cursorConfinement":false,"automaticNativeResolution":false}"#.utf8))
check("explicit policy opt-out", !disabled.cursorConfinement && !disabled.automaticNativeResolution)
// Generic templates preserve stored metadata and change only the launch-time arguments.
let tokens = ["-fullscreen", "-width", "{display.width}", "-height", "{display.height}"]
let laptopArguments = try! DisplayLaunchArguments.resolve(tokens, target: laptop)
let dellArguments = try! DisplayLaunchArguments.resolve(tokens, target: dell)
check("laptop pixels resolved", laptopArguments == ["-fullscreen", "-width", "3456", "-height", "2234"])
check("external pixels resolved afresh", dellArguments == ["-fullscreen", "-width", "3840", "-height", "2160"])
check("stored templates unchanged", tokens[2] == "{display.width}" && tokens[4] == "{display.height}")
check("generic app inline argument", try! DisplayLaunchArguments.resolve(["--size={display.width}x{display.height}", "--output={display.index}"], target: dell) == ["--size=3840x2160", "--output=1"])
check("explicit manual settings preserved", try! DisplayLaunchArguments.resolve(["-windowed", "-width", "1280", "literal;$HOME"], target: nil) == ["-windowed", "-width", "1280", "literal;$HOME"])
var unavailable = false
do { _ = try DisplayLaunchArguments.resolve(tokens, target: nil) } catch { unavailable = true }
check("missing display fails without guessing", unavailable)
var unknown = false
do { _ = try DisplayLaunchArguments.resolve(["{display.wdith}"], target: laptop) } catch { unknown = true }
check("unknown display token refused", unknown)
let invalidDisplay = NativeDisplayTarget(displayID: 3, outputIndex: 0, width: 0, height: 2160, refreshRate: 60)
var invalidRejected = false
do { _ = try DisplayLaunchArguments.resolve(tokens, target: invalidDisplay) } catch { invalidRejected = true }
check("invalid physical mode refused", invalidRejected)
let frames = [CGRect(x: 0, y: 0, width: 1728, height: 1117), CGRect(x: -1920, y: 0, width: 1920, height: 1080)]
check("GUI initiating window beats pointer", NativeDisplayTarget.preferredScreenIndex(window: 1, frames: frames, pointer: CGPoint(x: 100, y: 100)) == 1)
check("shortcut follows external pointer", NativeDisplayTarget.preferredScreenIndex(window: nil, frames: frames, pointer: CGPoint(x: -100, y: 100)) == 1)
check("shortcut follows laptop pointer", NativeDisplayTarget.preferredScreenIndex(window: nil, frames: frames, pointer: CGPoint(x: 100, y: 100)) == 0)
check("removed window screen falls back safely", NativeDisplayTarget.preferredScreenIndex(window: 4, frames: [frames[0]], pointer: CGPoint(x: -100, y: 100)) == 0)
check("no displays refuses selection", NativeDisplayTarget.preferredScreenIndex(window: nil, frames: [], pointer: .zero) == nil)
try! FileManager.default.removeItem(at: temp)
print("\(checks) native resolution, screen switch, quality preservation, backups and settings compatibility checks passed")
