import Foundation
var passed = 0
func check(_ name: String, _ value: Bool) {
    guard value else { fatalError("FAIL: " + name) }
    passed += 1
}
let database = CompatDatabase.load()
check("legacy and own database remains readable", database.games.count >= 88)
var primal = LibraryItem(id: "fixture", name: "Primal", kind: .game, bottle: "fixture", executable: "C:\\Games\\FCPrimal.exe")
let profile = GraphicsSelection.profile(for: primal, in: database.games)!
check("executable matching and owner evidence", profile.id == "farcry-primal" && profile.verification?.wine == "11.16")
check("existing Auto keeps proven Metal", GraphicsSelection.resolve(primal, profile: profile, hasD3DMetal: true) == .d3dmetal)
for graphics in LibraryItem.Graphics.allCases where graphics != .automatic {
    primal.graphics = graphics
    check("explicit user renderer wins \(graphics)", GraphicsSelection.resolve(primal, profile: profile, hasD3DMetal: true) == graphics)
}
primal.graphics = .automatic; primal.useRecommended = false
check("disabled profile retains fallback", GraphicsSelection.resolve(primal, profile: profile, hasD3DMetal: true) == .d3dmetal)
var recommended = primal; recommended.useRecommended = true
check("unavailable Metal recommendation uses fallback", GraphicsSelection.resolve(recommended, profile: profile, hasD3DMetal: false) == .wine)
check("no Metal has honest Wine fallback", GraphicsSelection.resolve(primal, profile: nil, hasD3DMetal: false) == .wine)
check("Primal does not advertise DLSS", !GraphicsSelection.allowsMetalFX(graphics: .d3dmetal, profile: profile, hasD3DMetal: true))
check("DX11 does not advertise DXR", !GraphicsSelection.allowsDXR(graphics: .d3dmetal, profile: profile, hasD3DMetal: true))
check("DXMT does not advertise D3DMetal DLSS", !GraphicsSelection.allowsMetalFX(graphics: .dxmt, profile: nil, hasD3DMetal: true))
check("DXVK does not advertise D3DMetal DXR", !GraphicsSelection.allowsDXR(graphics: .dxvk, profile: nil, hasD3DMetal: true))
var launcher = primal; launcher.kind = .launcher
check("a game profile cannot match a launcher", GraphicsSelection.profile(for: launcher, in: database.games) == nil)
var wgc = launcher; wgc.executable = "C:\\GameCenter\\WGC.EXE"
check("launcher profile has its own status", GraphicsSelection.profile(for: wgc, in: database.games)?.id == "wargaming-game-center")
let imported = database.games.first { $0.kind == nil && !$0.exeNames.isEmpty }!
var generic = primal; generic.executable = "C:\\Apps\\" + imported.exeNames[0]
generic.kind = .launcher
check("untyped legacy game profile cannot alter a launcher", GraphicsSelection.profile(for: generic, in: [imported]) == nil)
generic.kind = .program
check("untyped legacy game profile cannot alter a general program", GraphicsSelection.profile(for: generic, in: [imported]) == nil)
generic.kind = .game
check("legacy game profile remains available for games", GraphicsSelection.profile(for: generic, in: [imported])?.id == imported.id)
let legacy = try JSONDecoder().decode(LibraryItem.self, from: Data(#"{"id":"old","name":"Old","kind":"program","bottle":"old","executable":"C:\\old.exe","graphics":"automatic"}"#.utf8))
check("old library record still decodes", legacy.graphics == .automatic && legacy.kind == .program)
check("roundtrip renderer settings", try JSONDecoder().decode(LibraryItem.self, from: JSONEncoder().encode(primal)) == primal)
check("DXMT can run the known DX11 profile", GraphicsSelection.supportsDXMT(profile: profile))
let wukong = database.games.first { $0.graphicsAPI == "d3d12" }!
check("DXMT cannot run the known DX12 profile", !GraphicsSelection.supportsDXMT(profile: wukong))
check("unknown API can be tested explicitly", GraphicsSelection.supportsDXMT(profile: nil))
let work = URL(fileURLWithPath: ProcessInfo.processInfo.environment["EXPECT_WORK"]!)
let bottle = Bottle(name: "fixture", root: work)
try Paths.ensure(bottle.url)
let compat = try BottleManager.writeCompatEnvironment(bottle, perProgram: ["game.exe": ["FOO":"bar"]],
    d3dmetalOff: ["launcher.exe", "game.exe"], dxmt: ["game.exe"])
let lines = try String(contentsOf: compat, encoding: .utf8)
check("only selected executable gets DXMT", lines.contains("game.exe\t@dxmt=on") && !lines.contains("launcher.exe\t@dxmt=on"))
let next = try BottleManager.writeCompatEnvironment(bottle, perProgram: [:], d3dmetalOff: [])
check("switching back removes stale renderer", try String(contentsOf: next, encoding: .utf8) == "")
let engineRoot = work.appendingPathComponent("engine")
let engine = Engine(root: engineRoot)
let required = ["x86_64-windows/d3d11.dll", "x86_64-windows/dxgi.dll", "x86_64-windows/d3d10core.dll", "x86_64-windows/winemetal.dll",
    "i386-windows/d3d11.dll", "i386-windows/dxgi.dll", "i386-windows/d3d10core.dll", "i386-windows/winemetal.dll", "x86_64-unix/winemetal.so", "DXMT_VERSION"]
for name in required {
    let url = engine.dxmt.appendingPathComponent(name)
    try Paths.ensure(url.deletingLastPathComponent())
    try Data("0.80".utf8).write(to: url)
}
try Paths.ensure(engine.compatModule.deletingLastPathComponent())
try Data("EXERUNNER_DXMT_DIR EXERUNNER_EMULATE_MODESET".utf8).write(to: engine.compatModule)
check("old Wine cannot offer unsafe DXMT display mode", !engine.hasDXMT)
let display = engine.lib.appendingPathComponent("wine/x86_64-unix/win32u.so")
try Data("EXERUNNER_EMULATE_MODESET".utf8).write(to: display)
check("complete DXMT with display guard is available", engine.hasDXMT && engine.dxmtVersion == "0.80")
try FileManager.default.removeItem(at: engine.dxmt.appendingPathComponent("i386-windows/dxgi.dll"))
check("partial 32 bit install is not advertised", !engine.hasDXMT)
print("graphics: \(passed) passed")
