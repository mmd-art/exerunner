"""Regression for the global-runner adapter: no nested admission or fake legacy lease."""
import importlib.util,json,os,subprocess,sys
from pathlib import Path
root=Path(__file__).resolve().parents[1]
if not os.environ.get('EXERUNNER_ARTIFACT_SESSION'):
 os.execv(sys.executable,[sys.executable,'-I',str(root/'tools/artifacts.py'),'run','--label','test-managed-context','--',sys.executable,__file__])
s=importlib.util.spec_from_file_location('artifacts',root/'tools/artifacts.py');m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
work=m.Artifacts.managed_workspace()
if work is None:print('SKIP: owner global managed runner unavailable');sys.exit(0)
project=work/'fake-project';project.mkdir();(project/'game.save').write_text('OWNER FIXTURE')
store=m.Artifacts(project,in_use=lambda path:False)
original={k:os.environ[k] for k in ['TMPDIR','TMP','TEMP']}
status=store.run('nested-failure',[sys.executable,'-c','import sys;sys.exit(7)'])
assert status==7 and json.loads((store.root/'reports/run-nested-failure.json').read_text())['status']==7
assert store.run('nested-lock',[sys.executable,'-c','print("same admitted context")'],exclusive='build')==0
assert original=={k:os.environ[k] for k in original}
assert os.environ['EXERUNNER_ARTIFACT_SESSION']==str(work)
assert (project/'game.save').read_text()=='OWNER FIXTURE'
assert not list((store.root/'jobs').iterdir())
print('PASS: nested reuse, status 7, lock, unchanged managed temp paths, no fake leases')
