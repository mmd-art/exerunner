#!/bin/bash
# Explicit idle-only installation. Never quits games; rotates one verified rollback.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/build/app.noindex/ExeRunner.app}"
python3 -I "$ROOT/tools/artifacts.py" install "$APP"
