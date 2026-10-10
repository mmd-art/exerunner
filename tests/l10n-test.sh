#!/bin/bash
# The English interface has every text: see tools/l10n-check.py
set -euo pipefail
exec python3 "$(cd "$(dirname "$0")/.." && pwd)/tools/l10n-check.py"
