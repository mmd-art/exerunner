#!/usr/bin/env python3
"""Fresh-prefix clipboard acceptance. Swift preserves all owner pasteboard data in memory."""
import argparse, os, pathlib, subprocess, tempfile
parser=argparse.ArgumentParser(); parser.add_argument('--engine',type=pathlib.Path,required=True);args=parser.parse_args()
root=pathlib.Path(__file__).resolve().parents[1];engine=args.engine.resolve()
work=pathlib.Path(tempfile.mkdtemp(prefix='exerunner-clipboard-check-',dir='/private/tmp'))
env={k:v for k,v in os.environ.items() if k in {'HOME','USER','LOGNAME','SHELL','TMPDIR','LANG','TERM','PATH'} or k.startswith('LC_')}
env.update(WINEPREFIX=str(work/'prefix'),WINEDEBUG='-all',DYLD_FALLBACK_LIBRARY_PATH=str(engine/'lib')+':/usr/lib')
try:
 subprocess.run([str(engine/'bin/wine'),'wineboot','--init'],env=env,check=True,capture_output=True,timeout=90)
 subprocess.run([str(engine/'bin/wineserver'),'-w'],env=env,check=True,timeout=30)
 subprocess.run(['x86_64-w64-mingw32-gcc','-O2','-static','-municode',str(root/'tests/clipboard-probe.c'),'-luser32','-o',str(work/'clipboard-probe.exe')],check=True)
 subprocess.run(['swiftc',str(root/'tests/clipboard-test.swift'),'-o',str(work/'clipboard-helper')],check=True)
 subprocess.run([str(work/'clipboard-helper'),str(work),str(engine)],check=True,timeout=40)
finally:
 subprocess.run([str(engine/'bin/wineserver'),'-k'],env=env,capture_output=True,timeout=15)
 print('Evidence:',work)
