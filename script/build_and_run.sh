#!/bin/bash
# Canonical local UI build/run loop. The installed app is updated separately.
set -euo pipefail
if [ -z "${EXERUNNER_ARTIFACT_SESSION:-}" ]; then
  exec python3 -I "$(cd "$(dirname "$0")/.." && pwd)/tools/artifacts.py" run --label build-and-run --exclusive build -- bash "$0" "$@"
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/app.noindex/ExeRunner.app"
MODE="${1:-run}"
case "$MODE" in run|--verify|--debug|--logs|--telemetry|--build-only) ;; *) echo 'usage: build_and_run.sh [--verify|--debug|--logs|--telemetry|--build-only]' >&2; exit 2;; esac
if [ "$MODE" != --build-only ]; then python3 -I "$ROOT/tools/artifacts.py" idle-runtime; fi
if [ "$MODE" != --build-only ] && pgrep -x ExeRunner >/dev/null; then
  osascript -e 'tell application id "local.exerunner.app" to quit'
  for attempt in 1 2 3 4 5; do pgrep -x ExeRunner >/dev/null || break; sleep 1; done
  if pgrep -x ExeRunner >/dev/null; then echo 'ExeRunner did not finish closing; build refused' >&2; exit 1; fi
fi
bash "$ROOT/scripts/build-app.sh" release
trap 'python3 -I "$ROOT/tools/search-privacy.py" unregister-build "$APP"' EXIT
if [ "$MODE" = --build-only ]; then exit 0; fi
if [ "$MODE" = --debug ]; then lldb "$APP/Contents/MacOS/ExeRunner"; exit; fi
open -n "$APP"
case "$MODE" in
 --verify) sleep 1; pgrep -x ExeRunner >/dev/null ;;
 --logs|--telemetry) /usr/bin/log stream --info --style compact --predicate 'process == "ExeRunner"' ;;
esac
