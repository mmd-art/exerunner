#!/usr/bin/env python3
"""Windows networking and host-adapter inventory; only ephemeral loopback sockets are used."""
import argparse,os,pathlib,socket,subprocess,tempfile,threading

# Direct invocation also gets an owned workspace and automatic cleanup.
import os as _artifact_os, sys as _artifact_sys
from pathlib import Path as _ArtifactPath
if not _artifact_os.environ.get('EXERUNNER_ARTIFACT_SESSION'):
    _artifact_os.execv(_artifact_sys.executable, [_artifact_sys.executable, '-I',
        str(_ArtifactPath(__file__).resolve().parents[1] / 'tools/artifacts.py'),
        'run', '--label', 'test-network-test', '--', _artifact_sys.executable, __file__, *_artifact_sys.argv[1:]])
p=argparse.ArgumentParser();p.add_argument('--engine',type=pathlib.Path,required=True);a=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[1];engine=a.engine.resolve();work=pathlib.Path(tempfile.mkdtemp(prefix='exerunner-network-check-',dir=os.environ.get('TMPDIR', '/private/tmp')))
env={k:v for k,v in os.environ.items() if k in {'HOME','USER','LOGNAME','SHELL','TMPDIR','LANG','TERM','PATH'} or k.startswith('LC_')};env.update(WINEPREFIX=str(work/'prefix'),WINEDEBUG='-all',DYLD_FALLBACK_LIBRARY_PATH=str(engine/'lib')+':/usr/lib')
udp=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);tcp=socket.socket(socket.AF_INET,socket.SOCK_STREAM)
for server in [udp,tcp]:server.bind(('127.0.0.1',0));server.settimeout(10)
tcp.listen(1)
def udp_echo():
 for _ in range(3):payload,address=udp.recvfrom(1024);udp.sendto(payload,address)
def tcp_echo():
 peer,_=tcp.accept()
 with peer:
  payload=peer.recv(1024);peer.sendall(payload)
try:
 subprocess.run([str(engine/'bin/wine'),'wineboot','--init'],env=env,check=True,capture_output=True,timeout=90)
 subprocess.run([str(engine/'bin/wineserver'),'-w'],env=env,check=True,timeout=30)
 exe=work/'network-probe.exe';subprocess.run(['x86_64-w64-mingw32-gcc','-O2','-static',str(root/'tests/network-probe.c'),'-liphlpapi','-lws2_32','-o',str(exe)],check=True)
 threads=[threading.Thread(target=udp_echo),threading.Thread(target=tcp_echo)]
 for thread in threads:thread.start()
 r=subprocess.run([str(engine/'bin/wine'),str(exe),str(udp.getsockname()[1]),str(tcp.getsockname()[1])],env=env,capture_output=True,text=True,timeout=25)
 (work/'probe.log').write_text(r.stdout+r.stderr);print(r.stdout)
 if r.returncode:raise RuntimeError(r.stderr or 'network control failed: '+str(r.returncode))
 for thread in threads:thread.join(timeout=1)
finally:
 udp.close();tcp.close();subprocess.run([str(engine/'bin/wineserver'),'-k'],env=env,capture_output=True,timeout=15);print('Test workspace (automatic cleanup):',work)
