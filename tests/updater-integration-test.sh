#!/bin/bash
set -euo pipefail
if [ -z "${EXERUNNER_ARTIFACT_SESSION:-}" ]; then
 exec python3 -I "$(cd "$(dirname "$0")/.." && pwd)/tools/artifacts.py" run --label test-updater-integration -- bash "$0" "$@"
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$EXERUNNER_WORK_ROOT/updater-check"
mkdir -p "$WORK"
git -C "$ROOT" diff --quiet
git -C "$ROOT" rev-parse HEAD > "$WORK/tested-revision"
FRAMEWORK="$ROOT/build/app.noindex/ExeRunner.app/Contents/Frameworks"
swiftc -parse-as-library -module-cache-path "$WORK/modules" -F "$FRAMEWORK" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks "$ROOT/tests/updater-host.swift" "$ROOT/app/Sources/ExeRunner/App/AppUpdater.swift" -o "$WORK/host"
echo "compiled host: $WORK/host"
curl -fsL https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-2.10.0.tar.xz -o "$WORK/sparkle.tar.xz"
mkdir "$WORK/sparkle"
tar -xf "$WORK/sparkle.tar.xz" -C "$WORK/sparkle"
swift -module-cache-path "$WORK/modules" "$ROOT/tests/update-fixture-key.swift" "$WORK/test-key" "$WORK/test-public-key"
chmod 600 "$WORK/test-key"
python3 "$ROOT/tests/updater-integration-test.py" "$WORK" "$FRAMEWORK" "$ROOT"
