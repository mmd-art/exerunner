#!/usr/bin/env python3
"""Rebuild only too-new native dependencies in managed scratch at macOS15, then stage candidate."""
import hashlib,json,os,shutil,subprocess,sys,tarfile,urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];work=Path(os.environ['EXERUNNER_WORK_ROOT']);report=Path(os.environ['EXERUNNER_RELEASE_REPORT']);base=Path(sys.argv[1]);build=Path(sys.argv[2]);candidate=work/'candidate-engine'
assert os.environ.get('EXERUNNER_ARTIFACT_SESSION') and not candidate.exists()
def run(args,cwd,env=None):
 p=subprocess.run(args,cwd=cwd,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,errors='replace')
 with (report/'dependency-build.log').open('a') as f:f.write(str(args[0])+': exit '+str(p.returncode)+'\n'+p.stdout[-30000:]+'\n')
 if p.returncode:raise RuntimeError('dependency build failed: '+str(args[:2]))
def source(name,url,digest):
 data=urllib.request.urlopen(url,timeout=90).read();assert hashlib.sha256(data).hexdigest()==digest,name
 archive=work/(name+'.tar');archive.write_bytes(data);dest=work/name;dest.mkdir()
 with tarfile.open(archive) as t:t.extractall(dest,filter='data')
 return next(p for p in dest.iterdir() if p.is_dir())
subprocess.run(['ditto',str(base),str(candidate)],check=True)
replaced=[]
for folder,name in [('loader','wine'),('dlls/ntdll','ntdll.so'),('dlls/winemac.drv','winemac.so'),('dlls/win32u','win32u.so'),('dlls/winecoreaudio.drv','winecoreaudio.so'),('dlls/winebus.sys','winebus.so'),('dlls/opencl','opencl.so'),('dlls/wineusb.sys','wineusb.so'),('dlls/winspool.drv','winspool.so')]:
 dest=candidate/'lib/wine/x86_64-unix'/name;shutil.copyfile(build/folder/name,dest);replaced.append(dest)
env=dict(os.environ,CC='/usr/bin/clang -arch x86_64 -mmacosx-version-min=15.0',CFLAGS='-O2 -mmacosx-version-min=15.0',LDFLAGS='-mmacosx-version-min=15.0')
pcre=source('pcre2','https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.47/pcre2-10.47.tar.bz2','47fe8c99461250d42f89e6e8fdaeba9da057855d06eb7fc08d9ca03fd08d7bc7')
run(['./configure','--prefix='+str(work/'pcre-install'),'--enable-jit','--disable-static','--enable-shared'],pcre,env);run(['make','-j6'],pcre,env)
shutil.copyfile(pcre/'.libs/libpcre2-8.0.dylib',candidate/'lib/libpcre2-8.0.dylib');replaced.append(candidate/'lib/libpcre2-8.0.dylib')
ssl=source('openssl','https://github.com/openssl/openssl/releases/download/openssl-3.6.3/openssl-3.6.3.tar.gz','243a86649cf6f23eeb6a2ff2456e09e5d77dd9018a54d3d96b0c6bdd6ba6c7f1')
run(['./Configure','darwin64-x86_64-cc','shared','no-tests','--prefix='+str(work/'ssl-install'),'--openssldir=/private/etc/ssl','-mmacosx-version-min=15.0'],ssl,env);run(['make','-j6','build_libs'],ssl,env)
for name in ['libssl.3.dylib','libcrypto.3.dylib']:
 shutil.copyfile(ssl/name,candidate/'lib'/name);replaced.append(candidate/'lib'/name)
cab=source('cabextract','https://www.cabextract.org.uk/cabextract-1.11.tar.gz','b5546db1155e4c718ff3d4b278573604f30dd64c3c5bfd4657cd089b823a3ac6')
products=[]
for arch in ['arm64','x86_64']:
 folder=work/('cab-'+arch);folder.mkdir();e=dict(os.environ,CC='/usr/bin/clang -arch '+arch+' -mmacosx-version-min=15.0',CFLAGS='-O2 -mmacosx-version-min=15.0',LDFLAGS='-mmacosx-version-min=15.0')
 run([str(cab/'configure'),'--disable-dependency-tracking'],folder,e);run(['make','-j4'],folder,e);products.append(folder/'cabextract')
subprocess.run(['lipo','-create',*map(str,products),'-output',str(work/'cabextract-universal')],check=True)
os.chmod(candidate/'bin/cabextract',0o755)
shutil.copyfile(work/'cabextract-universal',candidate/'bin/cabextract');replaced.append(candidate/'bin/cabextract')
# Normalize own install IDs too: even IDs unused by the loader must not expose developer paths.
for path in candidate.rglob('*'):
 if not path.is_file() or path.is_symlink():continue
 with path.open('rb') as stream:magic=stream.read(4)
 if magic not in [b'\xcf\xfa\xed\xfe',b'\xce\xfa\xed\xfe',b'\xca\xfe\xba\xbe']:continue
 ids=[x for x in subprocess.run(['otool','-D',str(path)],capture_output=True,text=True).stdout.splitlines()[1:] if not x.rstrip().endswith(':')]
 changed=path in replaced
 os.chmod(path,0o755) # Copied candidate only; accepted Homebrew inputs may be read-only.
 if any(x.strip().startswith(('/Users/','/usr/local/','/opt/homebrew/')) for x in ids):
  subprocess.run(['install_name_tool','-id','@rpath/'+path.name,str(path)],check=True,capture_output=True);changed=True
 links=subprocess.check_output(['otool','-L',str(path)],text=True).splitlines()[1:]
 for line in links:
  if line.rstrip().endswith(':'):continue
  ref=line.strip().split(' (')[0]
  if ref.startswith((str(work),'/usr/local/','/opt/homebrew/')):
   target=candidate/'lib'/Path(ref).name
   if not target.exists():raise RuntimeError('unresolved new dependency '+ref)
   relative=os.path.relpath(target,path.parent)
   subprocess.run(['install_name_tool','-change',ref,'@loader_path/'+relative,str(path)],check=True,capture_output=True);changed=True
 if changed:
  subprocess.run(['codesign','--force','--sign','-',str(path)],check=True,capture_output=True)
  if path not in replaced:replaced.append(path)
metadata=json.loads((candidate/'engine.json').read_text());metadata['release_minimum_macos']='15.0';metadata['deployment_rebuild']={str(p.relative_to(candidate)):hashlib.sha256(p.read_bytes()).hexdigest() for p in replaced}
for rel in metadata.get('device_modules',{}):metadata['device_modules'][rel]=hashlib.sha256((candidate/rel).read_bytes()).hexdigest()
(candidate/'engine.json').write_text(json.dumps(metadata,indent=2)+'\n')
(report/'deployment-rebuild.json').write_text(json.dumps({'minimum_macos':'15.0','changed':list(metadata['deployment_rebuild']),'accepted_input_unchanged':True},indent=2)+'\n')
print('Candidate ready; accepted engine untouched')
