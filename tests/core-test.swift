// The app's parsing and matching, outside the app: Steam's VDF files, Windows paths, the crash
// classifier and its log window, the redactor, and reading wine processes from the process table.
// Built and run by tests/core-test.sh together with the app's own source files.
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
let env = Redactor.environment(["STEAM_AUTH": "x", "API_KEY": "y", "HOME": home, "LANG": "en_US.UTF-8"])
check("environment", env.keys.sorted() == ["HOME", "LANG"] && env["HOME"] == "/Users/<redacted>", "\(env)")

// processes: fake wine processes started by tests/core-test.sh, arguments shifted the way wine does
if let expected = ProcessInfo.processInfo.environment["EXPECT_PREFIX"] {
    let prefix = URL(fileURLWithPath: expected).standardizedFileURL.path
    let mine = WineProcesses.list().filter { $0.prefix == prefix }
    check("process found", mine.contains { $0.path == "C:\\Program Files (x86)\\Steam\\steamapps\\common\\Game\\bin\\game.exe" },
          "\(mine.map(\.path))")
    check("process through start.exe", mine.contains { $0.path == "/Users/someone/tool.exe" }, "\(mine.map(\.path))")
    check("process name", mine.contains { $0.name == "game.exe" })
}

try? FileManager.default.removeItem(at: work)
print("core: \(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
