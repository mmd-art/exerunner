#!/usr/bin/env python3
"""Read-only physical gamepad XInput/WinMM acceptance in a test-owned prefix."""
import argparse,os,pathlib,subprocess,tempfile,json
p=argparse.ArgumentParser();p.add_argument('--engine',type=pathlib.Path,required=True);p.add_argument('--seconds',type=int,default=3);p.add_argument('--prefix',type=pathlib.Path);p.add_argument('--mode',choices=['automatic','native','xinput']);a=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[1];engine=a.engine.resolve()
if a.prefix:
 a.prefix=a.prefix.resolve()
 if a.prefix.name!='prefix' or not str(a.prefix.parent).startswith('/private/tmp/exerunner-controller-check-'):p.error('--prefix must be a test-owned controller prefix')
work=a.prefix.parent if a.prefix else pathlib.Path(tempfile.mkdtemp(prefix='exerunner-controller-check-',dir='/private/tmp'));prefix=a.prefix or work/'prefix'
env={k:v for k,v in os.environ.items() if k in {'HOME','USER','LOGNAME','SHELL','TMPDIR','LANG','TERM','PATH'} or k.startswith('LC_')}
env.update(WINEPREFIX=str(prefix),WINEDEBUG='fixme-all',WINEMSYNC='1',DYLD_FALLBACK_LIBRARY_PATH=str(engine/'lib')+':/usr/lib')
try:
 if not (prefix/'system.reg').is_file():
  subprocess.run([str(engine/'bin/wine'),'wineboot','--init'],env=env,check=True,capture_output=True,timeout=90)
  subprocess.run([str(engine/'bin/wineserver'),'-w'],env=env,check=True,timeout=30)
 if a.mode:
  helper=work/'environment-helper'
  if not helper.is_file():subprocess.run(['bash',str(root/'tests/environment-native-helper.sh'),str(helper)],check=True)
  subprocess.run([str(helper),str(engine),str(prefix),'controller:'+a.mode],env=env,check=True,timeout=45)
 exe=work/'controller-probe.exe';subprocess.run(['x86_64-w64-mingw32-gcc','-O2','-static','-municode',str(root/'tests/controller-probe.c'),'-lwinmm','-lxinput','-o',str(exe)],check=True)
 process=subprocess.Popen([str(engine/'bin/wine'),str(exe),str(a.seconds)],env=env,stdout=subprocess.PIPE,stderr=(work/'wine.log').open('a'),text=True)
 lines=[]
 for line in process.stdout:
  print(line,end='',flush=True);lines.append(line)
 status=process.wait(timeout=a.seconds+30)
 result={'status':status,'output':''.join(lines),'work':str(work),'mode':'read-only; no rumble'};(work/'result.json').write_text(json.dumps(result,indent=2))
 if status:raise RuntimeError('No XInput controller detected')
finally:
 subprocess.run([str(engine/'bin/wineserver'),'-k'],env=env,capture_output=True,timeout=15)
 print('Evidence:',work,flush=True)
