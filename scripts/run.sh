#!/bin/bash
# Run a Windows program (or a wine command) in a bottle, with the engine from engine/dist.
#
# usage: run.sh [--bottle NAME] [--recipe NAME] [--kill] [--] <program.exe | wine-command> [args...]
#   run.sh winecfg
#   run.sh --bottle steam --recipe steam "C:\\Program Files (x86)\\Steam\\steam.exe"
#   run.sh --bottle steam --kill          stop everything running in that bottle
#
# Bottles live in bottles/<NAME> (default "default"); recipes in recipes/<NAME>.recipe.
# Set WINEDEBUG yourself to get logs.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/engine/dist"
BOTTLE="default"
RECIPE=""
KILL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --bottle) BOTTLE="${2:?bottle name}"; shift 2 ;;
    --recipe) RECIPE="${2:?recipe name}"; shift 2 ;;
    --kill) KILL=1; shift ;;
    --) shift; break ;;
    *) break ;;
  esac
done
[ $# -gt 0 ] || [ "$KILL" = 1 ] || { sed -n '2,11p' "$0"; exit 2; }
[ -x "$DIST/bin/wine" ] || { echo "no engine in engine/dist, run build-engine.sh first"; exit 1; }

# Wine hands the whole Unix environment to every Windows process, so a program in the bottle
# could read tokens and keys from the shell that started it. Keep only what Wine and the
# graphics layers need; the caller's own WINE*, D3DM_*, MTL_* and Steam settings pass through.
if [ -z "${EXERUNNER_CLEAN_ENV:-}" ]; then
  keep=(HOME USER LOGNAME SHELL TMPDIR LANG TERM PATH)
  while IFS='=' read -r name _; do
    case "$name" in
      LC_*|WINE*|EXERUNNER_*|D3DM_*|MTL_*|ROSETTA_*|DXVK_*|MVK_*|GST_*|SteamAppId|SteamGameId|STEAM_COMPAT_*) keep+=("$name") ;;
    esac
  done < <(env)
  args=()
  for name in "${keep[@]}"; do
    if [ -n "${!name+x}" ]; then args+=("$name=${!name}"); fi
  done
  opts=(--bottle "$BOTTLE")
  if [ -n "$RECIPE" ]; then opts+=(--recipe "$RECIPE"); fi
  if [ "$KILL" = 1 ]; then opts+=(--kill); fi
  exec env -i EXERUNNER_CLEAN_ENV=1 "${args[@]}" /bin/bash "$0" "${opts[@]}" -- "$@"
fi
unset EXERUNNER_CLEAN_ENV

export WINEPREFIX="$ROOT/bottles/$BOTTLE"
if [ "$KILL" = 1 ]; then
  exec "$DIST/bin/wineserver" -k
fi

export WINEDEBUG="${WINEDEBUG:--all}"
export WINEMSYNC="${WINEMSYNC:-1}"
# libraries the engine dlopens by soname: MoltenVK from engine/dist/lib, then the x86_64
# Homebrew ones (freetype, gnutls, sdl2, ffmpeg)
export DYLD_FALLBACK_LIBRARY_PATH="$DIST/lib:/usr/local/lib:/usr/lib"
export GST_PLUGIN_SYSTEM_PATH_1_0="${GST_PLUGIN_SYSTEM_PATH_1_0:-/usr/local/lib/gstreamer-1.0}"
# games that probe cpuid before using AVX/AVX2 (Rosetta can run them since macOS 15)
export ROSETTA_ADVERTISE_AVX="${ROSETTA_ADVERTISE_AVX:-1}"
# MoltenVK prints every supported extension at info level
export MVK_CONFIG_LOG_LEVEL="${MVK_CONFIG_LOG_LEVEL:-1}"

# D3DMetal (deploy-gptk.sh) for DX10-DX12. cxcompatdb.so prepends its DLLs in every process
# except EXERUNNER_D3DMETAL_SKIP; the libd3dshared path lets ntdll register D3DMetal's code with
# Rosetta. EXERUNNER_D3DMETAL=0 turns it off for this run.
GPTK="$DIST/lib/apple_gptk"
if [ "${EXERUNNER_D3DMETAL:-1}" != 0 ] && [ -e "$GPTK/external/libd3dshared.dylib" ]; then
  export CX_APPLEGPTK_LIBD3DSHARED_PATH="$GPTK/external/libd3dshared.dylib"
  export EXERUNNER_D3DMETAL_DIR="$GPTK/wine"
fi

if [ ! -d "$WINEPREFIX" ]; then
  echo "creating bottle $BOTTLE"
  # wine makes the prefix itself but not its parent
  mkdir -p "$ROOT/bottles"
  "$DIST/bin/wine" wineboot --init
  "$DIST/bin/wineserver" -w
fi

# A recipe holds per-program settings, one per line:
#   env NAME=value                 exported for this run
#   dxvk program.exe               that program draws D3D10/11 through DXVK instead of D3DMetal
#   dll program.exe name=mode,...  more DLL overrides for that program; an empty mode disables
# Lines that don't match are refused rather than guessed at.
if [ -n "$RECIPE" ]; then
  file="$ROOT/recipes/$RECIPE.recipe"
  [ -f "$file" ] || { echo "no recipe $file"; exit 1; }
  dxvk_exes=()
  dll_lines=()
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|'#'*) continue ;;
    esac
    if [[ "$line" =~ ^(name|kind|status|about|symbol|bottle|installer|sha256|exe|games|shutdown)\ .*$ ]]; then
      :  # catalog metadata, read by the app
    elif [[ "$line" =~ ^env\ ([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      export "${BASH_REMATCH[1]}=${BASH_REMATCH[2]}"
    elif [[ "$line" =~ ^dxvk\ (.+\.exe)$ ]]; then
      dxvk_exes+=("${BASH_REMATCH[1]}")
    elif [[ "$line" =~ ^dll\ (.+\.exe)\ ([A-Za-z0-9_.,=-]+)$ ]]; then
      dll_lines+=("${BASH_REMATCH[1]}"$'\t'"${BASH_REMATCH[2]}")
    else
      echo "$file: cannot read line: $line"; exit 1
    fi
  done < "$file"

  if [ "${#dxvk_exes[@]}" -gt 0 ]; then
    [ -d "$DIST/lib/dxvk/x64" ] || { echo "no DXVK in the engine, run build-engine.sh dxvk"; exit 1; }
    skip="$(IFS=,; echo "${dxvk_exes[*]}")"
    export EXERUNNER_D3DMETAL_SKIP="${EXERUNNER_D3DMETAL_SKIP:+$EXERUNNER_D3DMETAL_SKIP,}$skip"
    # DXVK's DLLs in the bottle; programs without an override keep loading the builtin ones
    for pair in "x64:system32" "x32:syswow64"; do
      src="$DIST/lib/dxvk/${pair%%:*}"; dst="$WINEPREFIX/drive_c/windows/${pair##*:}"
      for f in "$src"/*.dll; do
        cmp -s "$f" "$dst/$(basename "$f")" || cp -f "$f" "$dst/"
      done
    done
  fi
  if [ "${#dxvk_exes[@]}" -gt 0 ] || [ "${#dll_lines[@]}" -gt 0 ]; then
    # per-program overrides, imported once per recipe version
    stamp="$WINEPREFIX/.exerunner-recipe-$RECIPE"
    sum="$(shasum -a 256 "$file" | cut -d' ' -f1)"
    if [ "$(cat "$stamp" 2>/dev/null)" != "$sum" ]; then
      reg="$WINEPREFIX/drive_c/exerunner-recipe-$RECIPE.reg"
      {
        echo "REGEDIT4"
        for exe in ${dxvk_exes[@]+"${dxvk_exes[@]}"}; do
          echo
          echo "[HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\$exe\\DllOverrides]"
          for f in "$DIST/lib/dxvk/x64"/*.dll; do
            name="$(basename "$f" .dll)"
            echo "\"$name\"=\"native\""
          done
        done
        for entry in ${dll_lines[@]+"${dll_lines[@]}"}; do
          echo
          echo "[HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\${entry%%$'\t'*}\\DllOverrides]"
          # a word without "=" continues the mode before it (msvcp140=native,builtin)
          IFS=, read -ra words <<< "${entry#*$'\t'}"
          pairs=()
          for word in "${words[@]}"; do
            if [[ "$word" == *=* ]] || [ "${#pairs[@]}" -eq 0 ]; then pairs+=("$word")
            else pairs[${#pairs[@]}-1]+=",$word"; fi
          done
          for pair in "${pairs[@]}"; do echo "\"${pair%%=*}\"=\"${pair#*=}\""; done
        done
      } > "$reg"
      "$DIST/bin/wine" regedit /S "C:\\exerunner-recipe-$RECIPE.reg"
      "$DIST/bin/wineserver" -w
      rm -f "$reg"
      echo "$sum" > "$stamp"
    fi
  fi
fi

# DLSS through MetalFX needs both DLLs inside the bottle (Apple's Read Me)
if [ -n "${EXERUNNER_D3DMETAL_DIR:-}" ] && [ -e "$GPTK/wine/x86_64-windows/nvngx.dll" ]; then
  sys32="$WINEPREFIX/drive_c/windows/system32"
  for f in nvngx.dll nvapi64.dll; do
    cmp -s "$GPTK/wine/x86_64-windows/$f" "$sys32/$f" || cp -f "$GPTK/wine/x86_64-windows/$f" "$sys32/$f"
  done
  export D3DM_ENABLE_METALFX="${D3DM_ENABLE_METALFX:-1}"
fi

exec "$DIST/bin/wine" "$@"
