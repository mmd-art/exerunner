#!/usr/bin/env python3
"""Actual native first launch with verified Foundation redirection and write guard."""
import argparse,hashlib,json,os,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
if not os.environ.get('EXERUNNER_ARTIFACT_SESSION'):
    os.execv(sys.executable,[sys.executable,'-I',str(ROOT/'tools/artifacts.py'),'run','--label','fresh-profile','--',sys.executable,'-I',__file__,*sys.argv[1:]])
p=argparse.ArgumentParser();p.add_argument('--app',type=Path,required=True);p.add_argument('--report',type=Path,required=True);a=p.parse_args()
app=a.app.resolve();exe=app/'Contents/MacOS/ExeRunner';work=Path(os.environ['EXERUNNER_WORK_ROOT']);home=work/'fresh-home';home.mkdir()
report=a.report.resolve();report.mkdir(parents=True,exist_ok=True)
env=dict(os.environ,HOME=str(home),CFFIXED_USER_HOME=str(home))
# Verify the exact production Paths implementation before invoking Migration/GUI.
probe=work/'probe.swift';probe.write_text('import Foundation\n@main struct Probe { static func main() throws { print(String(data:try JSONSerialization.data(withJSONObject:["home":Paths.home.path,"support":Paths.support.path,"caches":Paths.caches.path,"logs":Paths.logs.path,"shortcuts":Paths.shortcuts.path]),encoding:.utf8)!) } }\n')
subprocess.run(['swiftc','-parse-as-library',str(ROOT/'app/Sources/ExeRunner/Core/Basics.swift'),str(probe),'-o',str(work/'probe')],check=True,capture_output=True)
paths=json.loads(subprocess.check_output([str(work/'probe')],env=env,text=True));assert all(Path(v).is_relative_to(home) for v in paths.values()),paths
(report/'paths.json').write_text(json.dumps(paths,indent=2)+'\n')
assert not Path(paths['support']).exists()
owner=Path.home().resolve();profile=work/'first-launch.sb'
# Owner home is read-only except this job and the disposable candidate app (quarantine metadata).
profile.write_text('(version 1)\n(allow default)\n(deny file-write* (require-all (subpath '+json.dumps(str(owner))+') (require-not (subpath '+json.dumps(str(work))+')) (require-not (subpath '+json.dumps(str(app))+'))))\n'+''.join('(deny file-read* (subpath '+json.dumps(str(owner/'Library/Application Support'/name))+'))\n' for name in ['ExeRunner','WinRunner']))
command=['/usr/bin/sandbox-exec','-f',str(profile),str(exe)]
try:
    for name,complete in [('first-launch',False),('empty-library',True)]:
        if complete:
            folder=Path(paths['support']);folder.mkdir(parents=True,exist_ok=True)
            (folder/'settings.json').write_text(json.dumps({'onboardingCompleted':True,'language':'en'}))
        target=work/(name+'.json')
        run=subprocess.run([*command,'--verify-close',str(target)],env=env,cwd=work,capture_output=True,text=True,timeout=90)
        (report/(name+'.log')).write_text(run.stdout+run.stderr)
        assert run.returncode==0,(name,run.returncode,run.stderr[-1000:])
        proof=json.loads(target.read_text());assert proof['terminationDelegateReached'] and proof['libraryItemCount']==0 and proof['bottleSettingsCount']==0 and proof['runningItems']==[],proof
        assert proof['onboardingCompleted']==complete and Path(proof['engine'])==app/'Contents/Resources/engine',proof
        assert all(Path(proof[k]).is_relative_to(home) for k in paths),proof
        assert target.with_suffix('.png').is_file(),'actual window export missing'
        (report/(name+'.json')).write_text(json.dumps(proof,indent=2)+'\n')
        (report/(name+'.png')).write_bytes(target.with_suffix('.png').read_bytes())
    # Native version detection and app self-check use the same blank local profile.
    check=subprocess.run([*command,'--self-test'],env=env,cwd=work,capture_output=True,text=True,timeout=60)
    (report/'self-test.log').write_text(check.stdout+check.stderr);assert check.returncode==0
    assert any(line=='library: ' or line=='library:' for line in check.stdout.splitlines()),check.stdout
    print('PASS: actual welcome, empty library, bundled engine, native close and verified isolated paths')
finally:
    cleanup=subprocess.run([sys.executable,'-I',str(ROOT/'tools/search-privacy.py'),'unregister-build',str(app)],capture_output=True,text=True)
    if cleanup.returncode:raise RuntimeError('Candidate search-registration cleanup failed: '+cleanup.stderr)
