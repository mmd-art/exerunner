#!/bin/bash
# Add CUPS, libusb and OpenCL to a verified portable engine without rebuilding its game modules.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE="${1:-$ROOT/engine/portable}"
OUT="${2:-$ROOT/engine/portable-devices}"
DEVICE_BUILD="${EXERUNNER_DEVICE_MODULE_BUILD:-$ROOT/engine/build-devices}"
if [ "${EXERUNNER_DEVICE_MODULES_READY:-0}" != 1 ]; then
  EXERUNNER_ENGINE_BUILD_ROOT="$DEVICE_BUILD" EXERUNNER_ENGINE_DIST_ROOT="$ROOT/engine/dist-devices" bash "$ROOT/scripts/build-engine.sh" configure
  make -C "$DEVICE_BUILD" -j4 dlls/winspool.drv/all dlls/wineusb.sys/all dlls/winebus.sys/all dlls/opencl/all
fi
python3 -I - "$BASE" "$OUT" "$DEVICE_BUILD" <<'PY'
from pathlib import Path
import hashlib,json,os,shutil,subprocess,sys
base,out,build=map(Path,sys.argv[1:])
assert base.resolve()!=out.resolve(), 'Base engine must remain intact'
assert (base/'engine.json').is_file(), 'Requires a portable base engine'
subprocess.run(['ditto',str(base),str(out)],check=True)
critical=['bin/wine','lib/wine/x86_64-unix/winemac.so','lib/wine/x86_64-unix/win32u.so','lib/wine/x86_64-unix/winecoreaudio.so']
modules={'winspool.drv':('winspool.so','winspool.drv'),'wineusb.sys':('wineusb.so','wineusb.sys'),
         'winebus.sys':('winebus.so','winebus.sys'),'opencl':('opencl.so','opencl.dll')}
changed=[]
for folder,(unix,pe) in modules.items():
    target=out/'lib/wine/x86_64-unix'/unix
    shutil.copy2(build/'dlls'/folder/unix,target);changed.append(target)
    for arch in ['i386','x86_64']:
        target=out/'lib/wine'/f'{arch}-windows'/pe
        target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(build/'dlls'/folder/f'{arch}-windows'/pe,target)
        subprocess.run([f'{"i686" if arch=="i386" else "x86_64"}-w64-mingw32-strip','--strip-debug',str(target)],check=True)
usb=Path('/usr/local/lib/libusb-1.0.dylib').resolve()
assert subprocess.check_output(['lipo','-archs',str(usb)],text=True).strip()=='x86_64'
destination=out/'lib/libusb-1.0.0.dylib';shutil.copy2(usb,destination);changed.append(destination)
subprocess.run(['install_name_tool','-id','@rpath/libusb-1.0.0.dylib',str(destination)],check=True)
for target in changed:
    links=subprocess.check_output(['otool','-L',str(target)],text=True).splitlines()[1:]
    for line in links:
        ref=line.strip().split(' (')[0]
        if ref.startswith('/usr/local/') or ref.startswith('/opt/homebrew/'):
            assert 'libusb-1.0' in ref, f'Unexpected external runtime dependency: {ref}'
            subprocess.run(['install_name_tool','-change',ref,'@loader_path/../../libusb-1.0.0.dylib',str(target)],check=True)
    subprocess.run(['codesign','--force','--sign','-',str(target)],check=True,capture_output=True)
    subprocess.run(['codesign','--verify','--strict',str(target)],check=True)
for rel in critical: assert (base/rel).read_bytes()==(out/rel).read_bytes(), f'Accepted module changed: {rel}'
licence=usb.parent.parent/'COPYING'
assert licence.is_file()
(out/'LICENSES/libusb').mkdir(parents=True,exist_ok=True)
shutil.copy2(licence,out/'LICENSES/libusb/COPYING')
with (out/'LICENSES.md').open('a') as f: f.write('\n\nlibusb 1.0.29, LGPL-2.1-or-later; source https://github.com/libusb/libusb/tree/v1.0.29. Licence: LICENSES/libusb/COPYING.\n')
manifest=json.loads((out/'engine.json').read_text())
manifest['capabilities']={'cups':True,'libusb':True,'coremidi':True,'iohid':True,'opencl':True}
manifest['device_modules']={str(p.relative_to(out)):hashlib.sha256(p.read_bytes()).hexdigest() for p in changed}
manifest['device_module_source']='Wine 11.16 / 7dbc5b5322a6ef3fb04bdc643c64b188fd641149'
(out/'engine.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('Prepared portable printing/device engine:',out)
PY
