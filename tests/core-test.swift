// The app's parsing and matching, outside the app: Steam's VDF files, Windows paths, the crash
// classifier and its log window, the redactor, and reading wine processes from the process table.
// Built and run by tests/core-test.sh together with the app's own source files.
import Darwin
import Foundation

var passed = 0, failed = 0
func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    if ok { passed += 1 } else { failed += 1; print("FAIL \(name) \(detail())") }
}

// VDF: current and old library lists, a manifest, escapes, comments, platform conditions
let folders = VDF.parse("""
"libraryfolders"
{
\t"0"
\t{
\t\t"path"\t\t"C:\\\\Program Files (x86)\\\\Steam"
\t\t"apps"\t\t{ "3132990"\t"123" }
\t}
\t"1"\t{ "path" "D:\\\\SteamLibrary" }  // a second drive
\t"contentstatsid"\t"-123"
}
""")
let entries = folders["LibraryFolders"]?.entries ?? []
check("vdf block count", entries.count == 3, "\(entries.count)")
check("vdf escaped path", entries.first?.value["path"]?.string == "C:\\Program Files (x86)\\Steam", "\(String(describing: entries.first?.value["path"]?.string))")
check("vdf nested", entries.first?.value["apps"]?["3132990"]?.string == "123")
check("vdf after comment", entries[1].value["path"]?.string == "D:\\SteamLibrary")
let old = VDF.parse("\"LibraryFolders\" { \"TimeNextStatsReport\" \"1\" \"1\" \"E:\\\\Games\" }")
check("vdf old format", old["libraryfolders"]?["1"]?.string == "E:\\Games")
let manifest = VDF.parse("""
"AppState"
{
\t"appid"\t\t"3132990"
\t"name"\t\t"Black Myth: Wukong \\"Benchmark\\""
\t"StateFlags"\t\t"4"
\t"installdir"\t\t"Black Myth Wukong Benchmark Tool"
\t"UserConfig" { "language" "english" } [$WIN32]
}
""")["AppState"]
check("vdf quotes", manifest?["name"]?.string == "Black Myth: Wukong \"Benchmark\"", "\(String(describing: manifest?["name"]?.string))")
check("vdf case-insensitive keys", manifest?["stateflags"]?.string == "4")
check("vdf condition skipped", manifest?["installdir"]?.string == "Black Myth Wukong Benchmark Tool" && manifest?.entries.count == 5,
      "\(manifest?.entries.map(\.key) ?? [])")
check("folder name safe", SteamLibrary.isFolderName("Black Myth Wukong Benchmark Tool"))
check("folder name climbs", !SteamLibrary.isFolderName("..") && !SteamLibrary.isFolderName("a\\..\\b") && !SteamLibrary.isFolderName("a/b"))

// HiDPI migration: physical modes for game bottles, preserve working legacy choices.
let legacyDisplay = try! JSONDecoder().decode(BottleSettings.self, from: Data(#"{"audioDriver":"coreaudio","audioLatency":"low","discordBridge":true}"#.utf8))
check("display migration keeps other settings", legacyDisplay.highResolution == nil && legacyDisplay.audioDriver == .coreaudio && legacyDisplay.audioLatency == .low && legacyDisplay.discordBridge)
check("new game sees physical display", legacyDisplay.desiredHighResolution(hasGames: true, existing: nil) == true)
check("ordinary program keeps display default", legacyDisplay.desiredHighResolution(hasGames: false, existing: nil) == nil)
check("working WoT retina choice preserved", legacyDisplay.desiredHighResolution(hasGames: true, existing: "y") == true)
check("existing cursor workaround preserved", legacyDisplay.desiredHighResolution(hasGames: true, existing: "n") == false)
var displayChoice = legacyDisplay
displayChoice.highResolution = false
check("owner can disable physical display", displayChoice.desiredHighResolution(hasGames: true, existing: "y") == false)
displayChoice.highResolution = true
check("owner can enable physical display", displayChoice.desiredHighResolution(hasGames: false, existing: "n") == true)
let displayRoundtrip = try! JSONDecoder().decode(BottleSettings.self, from: JSONEncoder().encode(displayChoice))
check("display choice roundtrip", displayRoundtrip == displayChoice)

// Windows paths
check("path same", WindowsPath.same("C:/Program Files (x86)/Steam/", "c:\\program files (x86)\\steam"))
check("path inside", WindowsPath.isInside("C:\\Program Files (x86)\\Steam\\steamapps\\common\\Game\\bin\\game.exe",
                                          folder: "c:\\program files (x86)\\steam\\steamapps\\common\\game"))
check("path not a prefix match", !WindowsPath.isInside("C:\\Games\\GameTwo\\x.exe", folder: "C:\\Games\\Game"))
check("path name", WindowsPath.name("C:\\a\\B.exe") == "B.exe" && WindowsPath.name("/Users/x/tool.exe") == "tool.exe")

// classifier
let classifier = CrashClassifier.shared
check("patterns loaded", classifier.count >= 24, "\(classifier.count)")
let log = """
fixme:ntdll:something
err:module:import_dll Library MSVCP140_ATOMIC_WAIT.dll (which is needed by L"C:\\\\game.exe") not found
wine: Unhandled page fault on read access to 0000000000000000 at address 0000000140001000 (thread 0024), starting debugger...
err:d3d:something DXGI_ERROR_DEVICE_REMOVED
"""
let diagnosis = classifier.classify(log)
check("primary is the page fault", diagnosis.primary?.pattern.id == "page-fault", "\(diagnosis.matches.map(\.pattern.id))")
check("missing library captured", diagnosis.missingLibraries == ["msvcp140_atomic_wait.dll"], "\(diagnosis.missingLibraries)")
check("device lost without its old prefilter", diagnosis.matches.contains { $0.pattern.id == "gpu-device-lost-dxvk" })
check("remedies ordered", diagnosis.remedies.first == "switch-graphics", "\(diagnosis.remedies)")
check("crash marker", CrashClassifier.looksLikeCrash(log) && !CrashClassifier.looksLikeCrash("all fine\n"))
check("verb for dll", MissingLibrary.verb(for: "MSVCP140_ATOMIC_WAIT.dll") == "vcrun2022" && MissingLibrary.verb(for: "d3dx9_43.dll") == "d3dx9"
      && MissingLibrary.verb(for: "xaudio2_7.dll") == "xact" && MissingLibrary.verb(for: "foo.dll") == nil)
check("clean log", classifier.classify("fixme:x\nhello\n").isEmpty)

// Silent nonzero exits must remain visible even when Wine has no known crash signature.
let silentExit = classifier.classify("", exitStatus: 10)
check("silent nonzero exit is an error", silentExit.primary?.pattern.id == "process-exit"
      && silentExit.primary?.pattern.severity == .error && silentExit.primary?.captures.contains(where: { $0.contains("10") }) == true)
check("silent exit does not invent a missing component", silentExit.missingLibraries.isEmpty
      && silentExit.remedies == ["logging-crash"] && silentExit.primary?.lineNumber == 0)
check("clean zero and absent status are not failures", classifier.classify("", exitStatus: 0).isEmpty
      && classifier.classify("").isEmpty)
check("known crash diagnosis is retained", classifier.classify(log, exitStatus: 10).primary?.pattern.id == "page-fault")

// log window: short logs whole, long ones as their first 200 and last 500 lines, from an offset
let work = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("core-test-\(getpid())")
try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
let long = work.appendingPathComponent("long.log")
try! (0..<2000).map { "line \($0)" }.joined(separator: "\n").write(to: long, atomically: true, encoding: .utf8)
let window = LogSegment(url: long).window()!.split(separator: "\n", omittingEmptySubsequences: false)
check("window size", window.count == 701 && window.first == "line 0" && window.last == "line 1999", "\(window.count)")
let short = work.appendingPathComponent("short.log")
try! "before\nafter\n".write(to: short, atomically: true, encoding: .utf8)
check("window from offset", LogSegment(url: short, offset: 7).window() == "after\n")
check("window past the end", LogSegment(url: short, offset: 100).window() == "")

// redactor
let home = NSHomeDirectory(), user = NSUserName()
let secret = Redactor.text("""
open \(home)/Library/x C:\\users\\\(user)\\AppData Z:\\Users\\\(user)\\Downloads
game.exe -AUTH_PASSWORD=abcdef123 -AUTH_TYPE=exchangecode --token 0123456789
Authorization: Bearer abcdefghijklmnop https://name:pass@example.com/a?sig=xyz&x=1 eyJhbGciOiJIUzI1.eyJzdWIiOiIxMjM0.SflKxwRJSMeKKF2QT4
""")
check("home path", !secret.contains(home) && secret.contains("/Users/<redacted>/Library/x"), secret)
check("windows user", !secret.lowercased().contains("\\users\\\(user.lowercased())\\"), secret)
check("epic password", secret.contains("-AUTH_PASSWORD=<redacted>") && !secret.contains("abcdef123"), secret)
check("flag value", secret.contains("--token <redacted>"), secret)
check("bearer", secret.contains("Bearer <redacted>"), secret)
check("url credentials", secret.contains("https://<redacted>@example.com"), secret)
check("query signature", secret.contains("?sig=<redacted>&x=1"), secret)
check("jwt", !secret.contains("eyJhbGciOiJIUzI1"), secret)
let env = Redactor.environment(["STEAM_AUTH": "x", "API_KEY": "y", "HOME": home, "LANG": "en_US.UTF-8", "USER": user])
check("environment", env.keys.sorted() == ["HOME", "LANG", "USER"] && env["HOME"] == "/Users/<redacted>"
      && env["USER"] == "<redacted>", "\(env)")

// recipes: a load order with a comma stays one mode
if let recipe = try? Recipe.parse(id: "t", text: "dll Some Game.exe nvapi64=,msvcp140=native,builtin,vcruntime140=n,b,d3d11=native") {
    check("dll modes", recipe.dllOverrides == ["Some Game.exe": ["nvapi64": "", "msvcp140": "native,builtin",
                                                                  "vcruntime140": "n,b", "d3d11": "native"]],
          "\(recipe.dllOverrides)")
} else { check("recipe parses", false) }
check("dll mode without a name", (try? Recipe.parse(id: "t", text: "dll a.exe native,builtin")) == nil)
if let recipe = try? Recipe.parse(id: "t", text: "d3d Launcher.exe renderer=gl,csmt=enabled") {
    check("d3d settings", recipe.direct3D == ["Launcher.exe": ["renderer": "gl", "csmt": "enabled"]] && recipe.dllOverrides.isEmpty,
          "\(recipe.direct3D)")
} else { check("d3d parses", false) }

// Windows links as wine keeps them: "<name>?" with the reparse data in user.WINEREPARSE
func reparseData(tag: UInt32, target: String, relative: Bool) -> [UInt8] {
    let name = Array(target.utf16).flatMap { [UInt8($0 & 0xff), UInt8($0 >> 8)] }
    func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xff), UInt8(v >> 8)] }
    let symlink = tag == 0xA000_000C
    var body = le16(0) + le16(name.count) + le16(name.count) + le16(name.count)   // substitute, then print name
    if symlink { body += [relative ? 1 : 0, 0, 0, 0] }
    body += name + name
    return [UInt8(tag & 0xff), UInt8((tag >> 8) & 0xff), UInt8((tag >> 16) & 0xff), UInt8(tag >> 24)] + le16(body.count) + [0, 0] + body
}
let linkBottle = Bottle(name: "links", root: work)
let versioned = linkBottle.driveC.appendingPathComponent("Program Files/Vendor/1.2.3/App")
try? FileManager.default.createDirectory(at: versioned, withIntermediateDirectories: true)
FileManager.default.createFile(atPath: versioned.appendingPathComponent("app.exe").path, contents: Data())
for (name, data) in [("App", reparseData(tag: 0xA000_000C, target: "1.2.3\\App", relative: true)),
                     ("Junction", reparseData(tag: 0xA000_0003, target: "\\??\\C:\\Program Files\\Vendor\\1.2.3\\App", relative: false))] {
    let entry = linkBottle.driveC.appendingPathComponent("Program Files/Vendor/\(name)?")
    try? FileManager.default.createDirectory(at: entry, withIntermediateDirectories: true)
    _ = data.withUnsafeBufferPointer { setxattr(entry.path, "user.WINEREPARSE", $0.baseAddress, $0.count, 0, 0) }
}
let viaLink = linkBottle.hostURL(forWindowsPath: "C:\\Program Files\\Vendor\\App\\app.exe")?.standardizedFileURL.path
check("relative windows link", viaLink == versioned.appendingPathComponent("app.exe").standardizedFileURL.path, viaLink ?? "nil")
let viaJunction = linkBottle.hostURL(forWindowsPath: "C:\\Program Files\\Vendor\\Junction\\app.exe")?.standardizedFileURL.path
check("junction", viaJunction == versioned.appendingPathComponent("app.exe").standardizedFileURL.path, viaJunction ?? "nil")
check("plain path unchanged", linkBottle.hostURL(forWindowsPath: "C:\\Program Files\\Vendor\\Other\\x.exe")?.path
      == linkBottle.driveC.appendingPathComponent("Program Files/Vendor/Other/x.exe").path)

// interface language: texts written in Russian, values kept apart for the English lookup
L10n.use(.english)
check("english text", t("Устанавливаю \("Steam")…") == "Installing Steam…", t("Устанавливаю \("Steam")…"))
check("text without english", t("Такого текста нет \(1)") == "Такого текста нет 1")
check("reordered values", L10n.fill("%2$@ then %1$@", ["a", "b"]) == "b then a")
L10n.use(.russian)
check("russian text", t("Устанавливаю \("Steam")…") == "Устанавливаю Steam…")
let saved = try? JSONDecoder().decode(AppSettings.self, from: Data(#"{"onboardingCompleted":true}"#.utf8))
check("settings from before keep russian", saved?.language == .russian && saved?.onboardingCompleted == true)
check("new settings follow the mac", AppSettings().language == .system)

// processes: fake wine processes started by tests/core-test.sh, arguments shifted the way wine does
if let expected = ProcessInfo.processInfo.environment["EXPECT_PREFIX"] {
    let prefix = URL(fileURLWithPath: expected).standardizedFileURL.path
    let mine = WineProcesses.list().filter { $0.prefix == prefix }
    check("process found", mine.contains { $0.path == "C:\\Program Files (x86)\\Steam\\steamapps\\common\\Game\\bin\\game.exe" },
          "\(mine.map(\.path))")
    check("process through start.exe", mine.contains { $0.path == "/Users/someone/tool.exe" }, "\(mine.map(\.path))")
    check("process name", mine.contains { $0.name == "game.exe" })
    check("process birth identity captured", !mine.isEmpty && mine.allSatisfy { $0.birthSeconds > 0 && $0.birthMicros < 1_000_000 })
    // A display-mode migration must refuse before writing or stopping a live program.
    let displayBottle = Bottle(name: URL(fileURLWithPath: prefix).lastPathComponent, root: URL(fileURLWithPath: prefix).deletingLastPathComponent())
    let registry = displayBottle.url.appendingPathComponent("user.reg")
    let originalRegistry = "[Software\\\\Wine\\\\Mac Driver]\n\"RetinaMode\"=\"n\"\n"
    try! originalRegistry.write(to: registry, atomically: true, encoding: .utf8)
    var explicitDisplay = BottleSettings(); explicitDisplay.highResolution = true
    do {
        try await BottleManager.applyHighResolution(explicitDisplay, to: displayBottle, hasGames: true,
            engine: Engine(root: URL(fileURLWithPath: "/nonexistent/exerunner-display-test")), log: work.appendingPathComponent("display-refusal.log"))
        check("display mode refuses a live program", false)
    } catch let error as AppError {
        check("display mode refuses a live program", error.message == t("Сначала останови программы этой бутылки, чтобы применить HiDPI."), error.message)
    } catch { check("display mode refuses a live program", false, String(describing: error)) }
    check("refused display migration keeps registry", (try? String(contentsOf: registry, encoding: .utf8)) == originalRegistry)
    check("refused display migration keeps programs alive", WineProcesses.list().contains { $0.prefix == prefix && $0.name == "game.exe" })

    if let loader = ProcessInfo.processInfo.environment["EXPECT_COPIED_LOADER"] {
        for key in ["EXPECT_UNRELATED_CEF_PID", "EXPECT_OUTSIDE_CEF_PID"] {
            let pid = ProcessInfo.processInfo.environment[key].flatMap(Int32.init)
            check("excluded CEF fixture is alive", pid.map { Darwin.kill($0, 0) == 0 } ?? false, key)
        }
        let images = [try Data(contentsOf: URL(fileURLWithPath: loader))]
        let copied = WineProcesses.list(copiedLoaderImages: images).filter { $0.prefix == prefix }
        check("renamed copied Wine loader keeps game identity", copied.contains { $0.path == "C:\\Games\\WorldOfTanks.exe" }, "\(copied.map(\.path))")
        check("unrelated CEF with Wine prefix is excluded", !copied.contains { $0.path == "C:\\Games\\unrelated-cef.exe" })
        check("copy outside Wine temp folder is excluded", !copied.contains { $0.path == "C:\\Games\\outside-temp.exe" })
        check("regular Wine processes remain tracked", copied.contains { $0.name == "game.exe" })
    }
}

try? FileManager.default.removeItem(at: work)
print("core: \(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
