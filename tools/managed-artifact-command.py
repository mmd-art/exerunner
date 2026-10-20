#!/usr/bin/env python3
"""ExeRunner command adapter inside the owner's global managed job.
Does not replace TMPDIR/TMP/TEMP or detach the command. Release outputs remain at
build/app.noindex and build/ExeRunner-*.dmg for explicit verification/publication.
"""
import argparse,fcntl,os,signal,subprocess,sys
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--exclusive',choices=['build','engine']);p.add_argument('command',nargs=argparse.REMAINDER);a=p.parse_args()
command=a.command[1:] if a.command[:1]==['--'] else a.command
if not command: p.error('command required')
temp=Path(os.environ['TMPDIR']).resolve()
if not temp.is_dir() or temp.stat().st_uid!=os.getuid():raise RuntimeError('Managed temporary directory unavailable')
work=temp/'exerunner-work';work.mkdir(mode=0o700)
env={**os.environ,'EXERUNNER_ARTIFACT_SESSION':str(work),'EXERUNNER_GLOBAL_MANAGED_ROOT':str(temp.parent),'EXERUNNER_WORK_ROOT':str(work),'CLANG_MODULE_CACHE_PATH':str(work/'clang'),'SWIFT_MODULECACHE_PATH':str(work/'swift'),'CCACHE_DIR':str(work/'ccache'),'PYTHONDONTWRITEBYTECODE':'1'}
lock=None
if a.exclusive:
 path=Path(__file__).resolve().parents[1]/'build/artifacts.noindex'/(a.exclusive+'.lock')
 path.parent.mkdir(parents=True,exist_ok=True)
 if path.is_symlink():raise RuntimeError('Unsafe build lock')
 lock=path.open('a');fcntl.flock(lock,fcntl.LOCK_EX)
 env['EXERUNNER_HELD_LOCKS']=a.exclusive
# No process group escape: the global runner keeps its guard through child completion.
interrupted = []
def defer_signal(signum, frame):
    interrupted.append(signum)  # Keep the outer resource guard until the child actually finishes.
for signum in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT):
    signal.signal(signum, defer_signal)
child = subprocess.Popen(command, env=env)
code = child.wait()
sys.exit(128 + interrupted[0] if interrupted and code == 0 else code if code >= 0 else 128 - code)
