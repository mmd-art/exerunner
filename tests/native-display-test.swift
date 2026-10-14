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
try! FileManager.default.removeItem(at: temp)
print("\(checks) native resolution, screen switch, quality preservation, backups and settings compatibility checks passed")
