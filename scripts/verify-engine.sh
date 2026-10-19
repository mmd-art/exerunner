#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE="${1:?usage: verify-engine.sh /path/to/candidate-engine}"
python3 -I "$ROOT/tools/artifacts.py" check-engine "$ENGINE" -- \
  python3 "$ROOT/tests/general-runtime-test.py" --engine "$ENGINE"
