#!/usr/bin/env python3
"""Reject false deployment floors and developer-machine load commands in release runtimes."""
import argparse,concurrent.futures,json,re,subprocess,sys
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('root',type=Path);p.add_argument('--minimum',default='15.0');p.add_argument('--report',type=Path);a=p.parse_args();root=a.root.resolve()
def version(s):return tuple((list(map(int,s.split('.')))+[0,0])[:3])
def inspect(path):
 load=subprocess.check_output(['otool','-l',str(path)],text=True)
 mins=re.findall(r'\bminos\s+([\d.]+)|\bversion\s+([\d.]+)\s+sdk',load)
 own=subprocess.run(['otool','-D',str(path)],capture_output=True,text=True).stdout.splitlines()[1:]
 ids={x.strip() for x in own if x.strip() and not x.rstrip().endswith(':')}
 linked=subprocess.check_output(['otool','-L',str(path)],text=True).splitlines()[1:]
 refs=[x.strip().split(' (')[0] for x in linked if ' (' in x and not x.rstrip().endswith(':')]
 external=[x for x in refs if x not in ids and x.startswith(('/Users/','/usr/local/','/opt/homebrew/'))]
 private_ids=[x for x in ids if x.startswith('/Users/')]
 values=[x or y for x,y in mins]
 archs=subprocess.check_output(['lipo','-archs',str(path)],text=True).strip().split()
 rpaths=re.findall(r'cmd LC_RPATH\s+cmdsize \d+\s+path (.*?) \(offset',load)
 external_rpaths=[x for x in rpaths if x.startswith(('/Users/','/usr/local/','/opt/homebrew/'))]
 missing=[]
 for ref in refs:
  if ref in ids or ref.startswith(('/usr/lib/','/System/Library/')):continue
  if ref.startswith('@loader_path/'):
   if not (path.parent/ref[len('@loader_path/'):]).exists():missing.append(ref)
  elif ref.startswith('@rpath/'):
   name=ref[len('@rpath/'):];candidates=[path.parent/name,root/'lib'/name,root/'Contents/Resources/engine/lib'/name]
   for rp in rpaths:
    if rp.startswith('@loader_path/'):candidates.append(path.parent/rp[len('@loader_path/'):]/name)
   if not any(c.exists() for c in candidates):missing.append(ref)
 return {'path':str(path.relative_to(root)),'minimum_os':values,'above_floor':any(version(x)>version(a.minimum) for x in values),'external_links':external,'private_install_ids':private_ids,'architectures':archs,'missing_x86_64':'x86_64' not in archs,'missing_deployment_command':not values,'external_rpaths':external_rpaths,'unresolved_links':missing}
paths=[]
for f in root.rglob('*'):
 if not f.is_file() or f.is_symlink():continue
 with f.open('rb') as stream:magic=stream.read(4)
 if magic in [b'\xcf\xfa\xed\xfe',b'\xce\xfa\xed\xfe',b'\xca\xfe\xba\xbe']:paths.append(f)
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:records=list(pool.map(inspect,paths))
bad=[r for r in records if r['above_floor'] or r['external_links'] or r['private_install_ids'] or r['missing_x86_64'] or r['missing_deployment_command'] or r['external_rpaths'] or r['unresolved_links']]
result={'minimum':a.minimum,'macho_count':len(records),'passed':not bad,'failures':bad,'records':records}
if a.report:a.report.write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({'macho_count':len(records),'passed':not bad,'failures':bad},indent=2));sys.exit(bool(bad))
