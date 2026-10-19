#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="${1:?usage: test.sh TEST-FILENAME [arguments...]}"; shift
case "$NAME" in *[/\\]*|..*) echo 'Use a filename from tests/' >&2; exit 2;; esac
case "$NAME" in
 *.sh) exec bash "$ROOT/tests/$NAME" "$@" ;;
 *.py) exec python3 -I "$ROOT/tools/artifacts.py" run --label "${NAME%.py}" -- python3 "$ROOT/tests/$NAME" "$@" ;;
 *) echo 'Expected a .sh or .py test' >&2; exit 2;;
esac
