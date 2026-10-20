#!/bin/bash
set -euo pipefail
if [ -z "${EXERUNNER_ARTIFACT_SESSION:-}" ]; then
 exec python3 -I "$(cd "$(dirname "$0")/.." && pwd)/tools/artifacts.py" run --label test-executable-file-picker -- bash "$0" "$@"
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$EXERUNNER_WORK_ROOT/file-picker"
mkdir -p "$WORK"
swiftc -parse-as-library -module-cache-path "$WORK/modules" "$ROOT/tests/executable-file-picker-test.swift" "$ROOT/app/Sources/ExeRunner/UI/FilePicker.swift" "$ROOT/app/Sources/ExeRunner/Core/Localization.swift" "$ROOT/app/Sources/ExeRunner/Core/English.swift" -o "$WORK/check"
"$WORK/check" "$WORK"
