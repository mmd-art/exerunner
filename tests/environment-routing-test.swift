import AppKit
import Foundation
@main struct RoutingControl {
    @MainActor static func main() async throws {
        let work=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        func makeEngine(_ label:String)throws->Engine {
            let root=work.appendingPathComponent(label,isDirectory:true);try Paths.ensure(root.appendingPathComponent("bin"))
            let script="""
            #!/bin/sh
            if [ "$1" = --version ]; then echo wine-fixture-\(label); exit 0; fi
            printf 'ROUTE=\(label) DLL=%s ARGS=%s\\n' "$WINEDLLPATH" "$*"
            exit 0
            """
            for file in ["wine","wineserver"] { let url=root.appendingPathComponent("bin/"+file);try script.write(to:url,atomically:true,encoding:.utf8);try FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath:url.path) }
            try #"{"wine":"fixture","portable":true}"#.write(to:root.appendingPathComponent("engine.json"),atomically:true,encoding:.utf8)
            return Engine(root:root)
        }
        let a=try makeEngine("A"),b=try makeEngine("B")
        var settings=AppSettings();settings.enginePath=a.root.path;settings.bottlesPath=work.appendingPathComponent("bottles").path;settings.gameBoost=false;settings.language = .english
        var chosen=BottleSettings();chosen.enginePath=b.root.path
        let tag=UUID().uuidString
        let fake=work.appendingPathComponent("generic.exe");try Data("route control".utf8).write(to:fake)
        var first=LibraryItem(id:"routing-\(tag)-a",name:"Control A",kind:.program,bottle:"one",executable:fake.path)
        var second=LibraryItem(id:"routing-\(tag)-b",name:"Control B",kind:.program,bottle:"two",executable:fake.path)
        first.graphics = .wine; second.graphics = .wine
        for name in ["one","two"] {
            let bottle=Bottle(name:name,root:settings.bottlesRoot)
            try Paths.ensure(bottle.driveC.appendingPathComponent("windows/system32"))
            try "WINE REGISTRY Version 2\n\n[Software\\\\Wine\\\\Mac Driver]\n\"RetinaMode\"=\"n\"\n".write(to:bottle.url.appendingPathComponent("user.reg"),atomically:true,encoding:.utf8)
            try "WINE REGISTRY Version 2\n".write(to:bottle.url.appendingPathComponent("system.reg"),atomically:true,encoding:.utf8)
            try Paths.ensure(bottle.url.appendingPathComponent("dosdevices"))
        }
        let state=AppState(managesGameBoost:false,initialSettings:settings,initialItems:[first,second],initialBottleSettings:["two":chosen])
        let defaultStatus=try await state.run(first),customStatus=try await state.run(second)
        guard defaultStatus==0 && customStatus==0 else { fatalError("route run status") }
        for (item,engine,label) in [(first,a,"A"),(second,b,"B")] {
            let log=state.segment(for:item.id)!.url
            let text=try String(contentsOf:log,encoding:.utf8)
            guard text.contains("ROUTE=\(label) DLL=\(engine.root.appendingPathComponent("lib/wine").path) ARGS=\(fake.path)") else { fatalError("Wrong runtime route: \(text)") }
        }
        let env=try state.nativeIdentity(for:second,in:Bottle(name:"two",root:settings.bottlesRoot))
        guard env["WINEDLLPATH"]==b.root.appendingPathComponent("lib/wine").path else { fatalError("identity used global root") }
        print("PASS: default/custom engines reached actual launcher with matching DLL roots")
    }
}
