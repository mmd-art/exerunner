#!/bin/bash
# The English interface has every text: see tools/l10n-check.py
set -euo pipefail
if [ -z "${EXERUNNER_ARTIFACT_SESSION:-}" ]; then
  exec python3 -I "$(cd "$(dirname "$0")/.." && pwd)/tools/artifacts.py" run --label test-l10n-test -- bash "$0" "$@"
fi
exec python3 "$(cd "$(dirname "$0")/.." && pwd)/tools/l10n-check.py"
