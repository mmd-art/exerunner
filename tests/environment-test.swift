import Foundation
var passed=0
func check(_ value: Bool,_ title: String) { guard value else { fatalError("FAIL "+title) };passed+=1 }
let work=URL(fileURLWithPath: ProcessInfo.processInfo.environment["EXPECT_WORK"]!)
let old=try JSONDecoder().decode(BottleSettings.self,from:Data(#"{"highResolution":true,"audioDriver":"coreaudio"}"#.utf8))
check(old.enginePath == nil && old.serialPorts.isEmpty && old.controllerMode == .automatic && old.highResolution == true && old.audioDriver == .coreaudio,"old settings preserve display/audio and default runtime")
func engine(_ name:String)throws->Engine {
    let root=work.appendingPathComponent(name);try Paths.ensure(root.appendingPathComponent("bin"))
    for file in ["wine","wineserver"] { let path=root.appendingPathComponent("bin/"+file);try "#!/bin/sh\nexit 0\n".write(to:path,atomically:true,encoding:.utf8);try FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath:path.path) }
    return Engine(root:root)
}
let base=try engine("default"),selected=try engine("chosen")
check(try EngineSelection.resolve(defaultEngine:base,path:nil)==base,"default engine inherited")
check(try EngineSelection.resolve(defaultEngine:base,path:selected.root.path)==selected,"environment override chosen")
do { _=try EngineSelection.resolve(defaultEngine:base,path:work.appendingPathComponent("missing").path);fatalError("missing engine silently fell back") }
catch { check(true,"missing explicit engine fails closed") }
var config=old;config.enginePath=selected.root.path;config.controllerMode = .xinput;config.serialPorts=[.init(number:22,device:"/dev/cu.exerunner-offline")]
check(try JSONDecoder().decode(BottleSettings.self,from:JSONEncoder().encode(config))==config,"engine and serial settings roundtrip")
let store=work.appendingPathComponent("bottles.json")
try JSONEncoder().encode(["alpha":config,"beta":config,"games":old]).write(to:store)
let engines=EngineSelection.configuredEngines(defaultEngine:base,store:store)
check(Set(engines.map(\.root))==[base.root,selected.root],"process ownership scans each selected engine once")
for port in [BottleSettings.SerialPort(number:0,device:"/dev/cu.a"),.init(number:257,device:"/dev/cu.a"),.init(number:1,device:"/dev/null"),.init(number:1,device:"/dev/../tmp/a"),.init(number:1,device:"/tmp/cu.a")] {
    check(!SerialPortMapper.valid(port),"invalid COM mapping rejected")
}
do { try SerialPortMapper.validate([.init(number:1,device:"/dev/cu.a"),.init(number:1,device:"/dev/cu.b")]);fatalError("duplicate COM permitted") }
catch { check(true,"duplicate port numbers rejected") }
let bottle=Bottle(name:"programs",root:work);try Paths.ensure(bottle.url.appendingPathComponent("dosdevices"))
try SerialPortMapper.apply([],in:bottle)
check(!(try FileManager.default.contentsOfDirectory(atPath:bottle.url.path)).contains(".exerunner-serial-ports.json"),"unconfigured environments are untouched")
let first=BottleSettings.SerialPort(number:22,device:"/dev/cu.exerunner-offline")
try SerialPortMapper.apply([first],in:bottle)
check(try FileManager.default.destinationOfSymbolicLink(atPath:SerialPortMapper.link(in:bottle,number:22).path)==first.device,"persistent disconnected mapping represented")
check(try SerialPortMapper.managed(in:bottle)==[first],"managed ownership recorded")
let foreign=SerialPortMapper.link(in:bottle,number:23)
try FileManager.default.createSymbolicLink(atPath:foreign.path,withDestinationPath:"/dev/cu.manual")
do { try SerialPortMapper.apply([.init(number:22,device:"/dev/cu.new"),.init(number:23,device:"/dev/cu.exerunner")],in:bottle);fatalError("manual mapping overwritten") }
catch { check(true,"all links checked before transaction") }
check(try FileManager.default.destinationOfSymbolicLink(atPath:SerialPortMapper.link(in:bottle,number:22).path)==first.device,"failed batch preserved earlier mapping")
try SerialPortMapper.apply([],in:bottle)
check(try FileManager.default.destinationOfSymbolicLink(atPath:foreign.path)=="/dev/cu.manual","removal preserves foreign links")
check(try SerialPortMapper.managed(in:bottle).isEmpty,"only managed mapping removed")
let registry=SerialPortMapper.registry(previous:[first],desired:[.init(number:24,device:"/dev/cu.test")])
check(registry.contains("\"COM22\"=-") && registry.contains("\"COM24\"=\"/dev/cu.test\""),"registry reconciliation removes only prior owned port values")
check(registry.contains("ExeRunnerCOM24"),"serial discovery keys have explicit ownership")
check(try SerialPortMapper.unmanagedNumbers(in: bottle).contains(23),"manual COM numbers reserved in UI")
check(!SerialPortMapper.valid(.init(number:256,device:"/dev/cu.test")),"Wine explicit-port upper bound respected")
let policy=ControllerMapping.policy(.xinput)!
check(policy["disablehidraw"]=="dword:00000001" && policy["enable sdl"]=="dword:00000001","XInput uses mapped SDL backend")
check(ControllerMapping.policy(.native)!["enable sdl"]=="dword:00000000","native mode keeps raw HID backend")
check(ControllerMapping.policy(.automatic)==nil,"automatic restores captured original policy")
check(ControllerMapping.valid(policy) && !ControllerMapping.valid(["other":"dword:00000001"]),"only owned driver options admitted")
check(!ControllerMapping.valid(["enable sdl":"dword:0000000x"]),"malformed original registry value rejected")
let restoration=ControllerMapping.registry(["enable sdl":"dword:00000000"])
check(restoration.contains("\"Map Controllers\"=-") && !restoration.contains("DisableInput"),"restore deletes only owned absent values")
try "WINE REGISTRY Version 2\n\n[System\\\\Select]\n\"Current\"=dword:00000003\n\n[System\\\\ControlSet003\\\\Services\\\\WineBus]\n\"Enable SDL\"=dword:00000001\n".write(to: bottle.url.appendingPathComponent("system.reg"), atomically: true, encoding: .utf8)
check(ControllerMapping.values(in: bottle)["enable sdl"]=="dword:00000001","CurrentControlSet registry link resolves to selected control set")
print("environments: \(passed) passed")
