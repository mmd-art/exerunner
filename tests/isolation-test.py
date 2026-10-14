"""Benign synthetic probes only. Network controls use localhost and TEST-NET UDP."""
import json, socket, subprocess, sys, threading
from pathlib import Path
work, engine = Path(sys.argv[1]), Path(sys.argv[2])
prefix = work / 'isolated-probe'
canary, allowed, link = work/'host-canary.txt', prefix/'allowed.txt', prefix/'escape'
canary.write_text('Synthetic host data\n'); allowed.write_text('Synthetic allowed data\n'); link.symlink_to(canary)
server=socket.socket(); server.bind(('127.0.0.1',0)); server.listen(); port=server.getsockname()[1]
def accept():
    while True:
        try: c,_=server.accept(); c.close()
        except OSError: break
threading.Thread(target=accept,daemon=True).start()
env={'HOME':str(prefix/'.isolation/home'),'TMPDIR':str(prefix/'.isolation/tmp'),'WINEPREFIX':str(prefix),'DYLD_FALLBACK_LIBRARY_PATH':str(engine/'lib')+':/usr/lib','PATH':'/usr/bin:/bin','WINEMSYNC':'0','WINEDEBUG':'-all'}
rows=[]
def run(label,cmd,expected=0):
    r=subprocess.run(cmd,env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=100)
    rows.append({'label':label,'status':r.returncode,'output':r.stdout})
    print(label, r.returncode, r.stdout,flush=True)
    if r.returncode != expected: raise AssertionError(label)
for isolated in [False,True]:
    args=list(map(str,[allowed,canary,str(canary)+'.write',link,port,int(isolated),'parent']))
    cmd=[str(prefix/'native-probe')]+args
    if isolated: cmd=['/usr/bin/sandbox-exec','-f',str(work/'profile.sb')]+cmd
    run('native sandbox='+str(isolated),cmd)
win=lambda p:'Z:'+str(p).replace('/','\\')
for isolated in [False,True]:
    args=[win(allowed),win(canary),win(str(canary)+'.write'),win(link),str(port),str(int(isolated)),'parent']
    if isolated:
        # Exercises the exact application's Wine wrapper, profile setup and wait path.
        cmd=[str(work/'harness'),'run',str(prefix),str(engine)]+args
    else: cmd=[str(engine/'bin/wine'),str(prefix/'drive_c/isolation-probe.exe')]+args
    run('Windows sandbox='+str(isolated),cmd)
    subprocess.run([str(engine/'bin/wineserver'),'-w'],env=env,check=True,timeout=30)
alias = Path('/System/Volumes/Data') / str(canary).lstrip('/')
if alias.exists():
    args=list(map(str,[allowed,alias,str(canary)+'.write',link,port,1,'parent']))
    run('APFS alias denied',['/usr/bin/sandbox-exec','-f',str(work/'profile.sb'),str(prefix/'native-probe')]+args)
server.close()
(work/'results.json').write_text(json.dumps(rows,indent=2))
print('PASS: files, writes, symlink, loopback TCP, nonlocal UDP and child inheritance; positive controls succeeded')
