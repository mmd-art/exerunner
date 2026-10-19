#!/bin/bash
# Repair deployment-target build defects in an isolated candidate; never edit the accepted engine.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -z "${EXERUNNER_ARTIFACT_SESSION:-}" ]; then
 exec python3 -I "$ROOT/tools/artifacts.py" run --label portable-floor --exclusive engine -- bash "$0" "$@"
fi
BASE="${1:?accepted engine required}"
SOURCE_REPO="${2:?read-only upstream source checkout required}"
export EXERUNNER_RELEASE_REPORT="${EXERUNNER_RELEASE_REPORT:-$ROOT/build/release-checks}"
mkdir -p "$EXERUNNER_RELEASE_REPORT"
export MACOSX_DEPLOYMENT_TARGET=15.0
export EXERUNNER_ENGINE_SOURCE_ROOT="$EXERUNNER_WORK_ROOT/source"
export EXERUNNER_ENGINE_TOOLS_ROOT="$EXERUNNER_WORK_ROOT/tools"
export EXERUNNER_ENGINE_BUILD_ROOT="$EXERUNNER_WORK_ROOT/wine-build"
export EXERUNNER_ENGINE_DIST_ROOT="$EXERUNNER_WORK_ROOT/dist"
export CCACHE_DIR="$EXERUNNER_WORK_ROOT/ccache"
# These are reproducibly downloaded/copied inputs and generated compiler trees, not authored source.
# Unique authored scripts/patches live in ROOT; the input SOURCE_REPO stays read-only.
cleanup_inputs() {
 python3 -I - "$EXERUNNER_WORK_ROOT" <<'PY'
import os,json,shutil,sys
from pathlib import Path
w=Path(sys.argv[1]).resolve();j=Path(os.environ['EXERUNNER_ARTIFACT_SESSION']).resolve()
assert w==j/'work' and json.loads((j/'lease.json').read_text())['area']=='jobs'
for name in ['source','tools','wine-build','pcre2','openssl','cabextract','cab-arm64','cab-x86_64','ccache']:
 p=w/name
 if p.is_dir() and not p.is_symlink():shutil.rmtree(p)
PY
}
trap cleanup_inputs EXIT
mkdir -p "$EXERUNNER_ENGINE_SOURCE_ROOT"
git -C "$SOURCE_REPO" archive 7dbc5b5322a6ef3fb04bdc643c64b188fd641149 | tar -x -C "$EXERUNNER_ENGINE_SOURCE_ROOT"
# Patch helpers use git apply; a local fresh repository never touches SOURCE_REPO.
git -C "$EXERUNNER_ENGINE_SOURCE_ROOT" init -q
bash "$ROOT/scripts/build-engine.sh" tools
bash "$ROOT/scripts/build-engine.sh" configure
make -C "$EXERUNNER_ENGINE_BUILD_ROOT" -j6 loader/wine dlls/ntdll/ntdll.so dlls/winemac.drv/winemac.so dlls/win32u/win32u.so dlls/winecoreaudio.drv/winecoreaudio.so dlls/winebus.sys/winebus.so dlls/opencl/opencl.so dlls/wineusb.sys/wineusb.so dlls/winspool.drv/winspool.so
python3 -I "$ROOT/tools/portable-floor-deps.py" "$BASE" "$EXERUNNER_ENGINE_BUILD_ROOT"
# The candidate exists only during this managed job. App packaging retains its own final copy.
export EXERUNNER_BUILD_ENGINE_ROOT="$EXERUNNER_WORK_ROOT/candidate-engine"
export EXERUNNER_KEEP_ENGINE_SIGNATURES=1
python3 -I "$ROOT/tools/check-portable.py" "$EXERUNNER_BUILD_ENGINE_ROOT" --report "$EXERUNNER_RELEASE_REPORT/engine-portability-final.json"
bash "$ROOT/scripts/verify-engine.sh" "$EXERUNNER_BUILD_ENGINE_ROOT"
export EXERUNNER_BUILD_ENGINE_ROOT="$(python3 -I "$ROOT/tools/artifacts.py" engine --checked-only)"
bash "$ROOT/scripts/build-app.sh" release
