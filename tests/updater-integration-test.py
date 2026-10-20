"""Local signed feed, disposable app bundles, actual Sparkle replacement and relaunch.
Never installs into /Applications or uses the production signing key.
"""
import functools,http.server,json,os,plistlib,re,shutil,subprocess,sys,threading,time,uuid
from pathlib import Path
work,framework,root=map(Path,sys.argv[1:]); tools=work/'sparkle/bin'
def run(*args,**kw): return subprocess.run(list(map(str,args)),check=True,**kw)
public=(work/'test-public-key').read_text().strip()
server=http.server.ThreadingHTTPServer(('127.0.0.1',0),functools.partial(http.server.SimpleHTTPRequestHandler,directory=str(work)))
threading.Thread(target=server.serve_forever,daemon=True).start(); base=f'http://127.0.0.1:{server.server_port}'
identifier='local.exerunner.updater-test.'+uuid.uuid4().hex
old=work/'installed/ExeRunner.app'; new=work/'archive/ExeRunner.app'
for app,version in [(old,'1'),(new,'2')]:
 (app/'Contents/MacOS').mkdir(parents=True); (app/'Contents/Frameworks').mkdir()
 shutil.copy2(work/'host',app/'Contents/MacOS/UpdaterFixture')
 run('ditto',framework/'Sparkle.framework',app/'Contents/Frameworks/Sparkle.framework')
 info={'CFBundleIdentifier':identifier,'CFBundleExecutable':'UpdaterFixture','CFBundleName':'UpdaterFixture','CFBundlePackageType':'APPL','CFBundleVersion':version,'CFBundleShortVersionString':version,'SUPublicEDKey':public,'SUFeedURL':base+'/appcast.xml','SUEnableAutomaticChecks':False,'SUAutomaticallyUpdate':False,'SUVerifyUpdateBeforeExtraction':True,'SURequireSignedFeed':True,'SUEnableInstallerLauncherService':True,'SUSendProfileInfo':False,'FixtureRoot':str(work),'NSAppTransportSecurity':{'NSAllowsLocalNetworking':True}}
 (app/'Contents/Info.plist').write_bytes(plistlib.dumps(info));run('codesign','--force','--sign','-',app)
archive=work/'update.dmg';run('hdiutil','create','-volname','ExeRunner update fixture','-srcfolder',new.parent,'-format','ULFO','-ov',archive)
sign=subprocess.check_output([str(tools/'sign_update'),'--ed-key-file',str(work/'test-key'),'-p',str(archive)],text=True).strip()
feed=f'''<?xml version="1.0" encoding="utf-8"?><rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><title>Disposable updater fixture</title><item><title>Fixture 2</title><sparkle:version>2</sparkle:version><sparkle:shortVersionString>2</sparkle:shortVersionString><enclosure url="{base}/update.dmg" sparkle:edSignature="{sign}" length="{archive.stat().st_size}" type="application/octet-stream"/></item></channel></rss>'''
(work/'appcast.xml').write_text(feed)
run(tools/'sign_update','--ed-key-file',work/'test-key',work/'appcast.xml')
run(tools/'sign_update','--ed-key-file',work/'test-key','--verify',archive,sign)
# A signature must reject tampered data; production also requires it before extraction.
tamper=work/'tampered.dmg';tamper.write_bytes(archive.read_bytes()+b'bad')
assert subprocess.run([str(tools/'sign_update'),'--ed-key-file',str(work/'test-key'),'--verify',str(tamper),sign],capture_output=True).returncode!=0
home=work/'home';home.mkdir();env=os.environ.copy();env.update(HOME=str(home),CFFIXED_USER_HOME=str(home))
proof=work/'update-proof.txt';log=(work/'host.log').open('w');process=None
try:
 process=subprocess.Popen([str(old/'Contents/MacOS/UpdaterFixture')],env=env,stdout=log,stderr=subprocess.STDOUT)
 until=time.monotonic()+100
 while time.monotonic()<until:
  text=proof.read_text() if proof.exists() else ''
  if 'error:' in text: raise AssertionError(text+'\n'+(work/'host.log').read_text())
  if 'relaunched-version-2' in text: break
  if process.poll() not in (None,0): raise AssertionError(text+'\n'+(work/'host.log').read_text())
  time.sleep(.25)
 else: raise AssertionError('Updater timed out: '+(proof.read_text() if proof.exists() else '')+'\n'+(work/'host.log').read_text())
 text=proof.read_text()
 for stage in ['busy-policy-passed','staged-termination-policy-passed','preparing-verification-extraction','busy-install-wait-passed','termination-allowed','relaunched-version-2']:assert stage in text,text
 assert plistlib.loads((old/'Contents/Info.plist').read_bytes())['CFBundleVersion']=='2'
 # Exercise the native downloader's verification gate too, not just the signing CLI.
 process.wait(timeout=15)
 archive.write_bytes(tamper.read_bytes())
 info=plistlib.loads((old/'Contents/Info.plist').read_bytes());info['CFBundleVersion']='1'
 info['SUFeedURL']=base+'/appcast.xml?tampered=1'
 (old/'Contents/Info.plist').write_bytes(plistlib.dumps(info));run('codesign','--force','--sign','-',old)
 proof.unlink()
 process=subprocess.Popen([str(old/'Contents/MacOS/UpdaterFixture')],env=env,stdout=log,stderr=subprocess.STDOUT)
 until=time.monotonic()+45
 while time.monotonic()<until:
  rejected=proof.read_text() if proof.exists() else ''
  if 'error:' in rejected:break
  if process.poll() is not None:raise AssertionError('No native signature error: '+rejected)
  time.sleep(.25)
 else:raise AssertionError('No native tamper rejection: '+rejected)
 assert 'ready' not in rejected and 'installing' not in rejected and 'relaunched-version-2' not in rejected,rejected
 assert plistlib.loads((old/'Contents/Info.plist').read_bytes())['CFBundleVersion']=='1'
 report={'passed':True,'actual_replacement':True,'actual_relaunch':True,'tamper_rejected':True,'native_tamper_rejected_without_installation':True,'stages':text.splitlines()}
 dest=root/'build/updater-integration-report.json';dest.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
finally:
 if process and process.poll() is None:process.terminate();process.wait(timeout=10)
 log.close(); server.shutdown()
 for app in [old,new]:
  if app.exists():
   assert app.resolve().is_relative_to(work.resolve()) and app.stat().st_uid==os.getuid()
   ls='/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
   check=subprocess.run([ls,'-u',str(app)],capture_output=True,text=True)
   assert check.returncode==0 or '-10814' in check.stdout+check.stderr
   dump=subprocess.check_output([ls,'-dump'],text=True)
   registered=re.findall(r'^path:\s+(.*?)\s+\(0x[0-9a-f]+\)\s*$',dump,re.MULTILINE)
   assert str(app) not in registered,'test app remains registered: '+str(app)

