import Foundation
@main struct Tests {
 static func main() throws {
  let fm = FileManager.default, root = StorageScan.canonical(URL(fileURLWithPath:ProcessInfo.processInfo.environment["TMPDIR"]!)).appendingPathComponent("storage-fixture-" + UUID().uuidString)
  try fm.createDirectory(at:root,withIntermediateDirectories:true)
  var checks = 0
  func file(_ path:String,_ count:Int) throws -> URL { let p=root.appendingPathComponent(path);try fm.createDirectory(at:p.deletingLastPathComponent(),withIntermediateDirectories:true);try Data(repeating:1,count:count).write(to:p);return p }
  let app = try file("prefix/drive_c/Program Files/Steam/Steam.exe",10)
  let cache = try file("prefix/drive_c/Program Files/Steam/appcache/cache.bin",20)
  let game = try file("prefix/drive_c/Program Files/Steam/steamapps/common/Game/game.exe",30)
  _ = try file("prefix/drive_c/Program Files/Steam/steamapps/downloading/partial",40)
  _ = try file("prefix/drive_c/windows/system32/base.dll",50)
  let prefix=root.appendingPathComponent("prefix"),folder=app.deletingLastPathComponent()
  let claims:[StorageScan.Claim] = [
   .init(id:"env",kind:.environment,owners:["steam","game"],roots:[prefix,prefix]),
   .init(id:"steam",kind:.application,owners:["steam"],roots:[folder]),
   .init(id:"cache",kind:.cache,owners:["steam"],roots:[cache.deletingLastPathComponent()]),
   .init(id:"steam-data:steam",kind:.data,owners:["steam"],roots:[folder.appendingPathComponent("steamapps")]),
   .init(id:"game",kind:.application,owners:["game"],roots:[game.deletingLastPathComponent()])]
  var s=StorageScan.run(claims)
  assert(s.totalBytes==150 && s.ownBytes("steam")==30 && s.ownBytes("game")==30 && s.buckets["env"]?.bytes==50);checks += 1
  _ = try file("prefix/.hidden",7)
  s=StorageScan.run(claims);assert(s.totalBytes==157);checks += 1
  let external = try file("outside/private.bin",500)
  try fm.createSymbolicLink(at:prefix.appendingPathComponent("external"),withDestinationURL:external.deletingLastPathComponent())
  s=StorageScan.run(claims);assert(s.totalBytes==157 && s.skippedLinks==1);checks += 1
  try fm.linkItem(at:app,to:game.deletingLastPathComponent().appendingPathComponent("shared.dll"))
  s=StorageScan.run(claims);assert(s.totalBytes==157 && s.ownBytes("steam")==20 && s.ownBytes("game")==30 && s.buckets.values.contains{$0.kind == .shared && $0.bytes==10 && $0.owners==["steam","game"]});checks += 1
  let alias=root.appendingPathComponent("prefix-alias");try fm.createSymbolicLink(at:alias,withDestinationURL:prefix)
  assert(!StorageScan.realDirectory(alias));checks += 1
  let unsafe=StorageScan.run([.init(id:"bad",kind:.application,owners:["bad"],roots:[alias])]);assert(unsafe.totalBytes==0 && unsafe.incomplete);checks += 1
  assert(StorageScan.run(claims,maxEntries:1).incomplete);checks += 1
  assert(StorageScan.run(claims,cancelled:{true}).incomplete);checks += 1
  let duplicate=StorageScan.run(claims+[.init(id:"steam",kind:.application,owners:["other"],roots:[folder])]);assert(duplicate.totalBytes==157 && duplicate.exclusive("steam",.application)==0);checks += 1
  let input=StorageSources.Input(items:[.init(id:"steam",bottle:"prefix",executable:"C:\\Program Files\\Steam\\Steam.exe",steamGame:false,steamClient:true),.init(id:"game",bottle:"prefix",executable:"C:\\Program Files\\Steam\\Steam.exe",steamGame:true,steamClient:false,gameFolder:"C:\\Program Files\\Steam\\steamapps\\common\\Game")],bottlesRoot:root,shared:[])
  let measured=StorageSources.measure(input);assert(measured.totalBytes==157 && measured.exclusive("game",.application)==30 && measured.exclusive("steam",.application)==0);checks += 1 // hardlinked executable is shared
  assert(StorageSources.windowsURL("Z:\\Users\\person",in:prefix.appendingPathComponent("drive_c"))==nil);checks += 1
  assert(StorageSources.windowsURL("C:\\..\\outside",in:prefix.appendingPathComponent("drive_c"))==nil);checks += 1
  assert(StorageSources.windowsURL("C:\\program files\\steam\\Steam.exe",in:prefix.appendingPathComponent("drive_c"))==app);checks += 1
  let text=#"[Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Example]"#+"\n"+#""InstallLocation"="C:\\Games\\Example""#
  assert(StorageSources.installLocations(text)==["C:\\Games\\Example"]);checks += 1
  let unknownInput=StorageSources.Input(items:[.init(id:"u",bottle:"prefix",executable:"C:\\Program Files\\Steam\\Steam.exe",steamGame:false,steamClient:false)],bottlesRoot:root,shared:[])
  assert(StorageSources.measure(unknownInput).unknownItems==["u"]);checks += 1
  assert(StorageSources.plan(input,deadline:Date(timeIntervalSince1970:0)).incomplete); checks += 1
  assert(StorageSources.installLocations(text + "\n" + text,limit:1).count==1); checks += 1
  let registry=try file("prefix/system.reg",2)
  assert(StorageScan.text(registry,limit:1)==nil);checks += 1
  let regAlias=prefix.appendingPathComponent("user.reg")
  try fm.createSymbolicLink(at:regAlias,withDestinationURL:external)
  assert(StorageScan.text(regAlias,limit:1024)==nil);checks += 1
  assert(StorageScan.names(in:alias)==nil);checks += 1
  let oneSharedCache=StorageScan.run([.init(id:"runner-cache",kind:.cache,owners:["only"],roots:[cache.deletingLastPathComponent()])])
  assert(oneSharedCache.ownBytes("only")==0 && oneSharedCache.shared(for:"only").count==1);checks += 1
  _ = try file("orphan/drive_c/windows/base.dll",13)
  _ = try file("orphan/system.reg",3)
  let withOrphan=StorageSources.measure(unknownInput)
  assert(withOrphan.buckets.values.contains{$0.kind == .environment && $0.owners.isEmpty && $0.bytes==16});checks += 1
  let unavailable=try file("not-a-root",1)
  assert(StorageSources.measure(.init(items:[],bottlesRoot:unavailable,shared:[])).incomplete);checks += 1
  assert(!StorageSources.measure(.init(items:[],bottlesRoot:root.appendingPathComponent("absent"),shared:[])).incomplete);checks += 1
  print("Storage: \(checks) attribution, identity, traversal and cancellation checks passed")
 }
}
