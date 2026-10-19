#!/bin/bash
set -euo pipefail
if [ -z "${EXERUNNER_ARTIFACT_SESSION:-}" ]; then
  exec python3 -I "$(cd "$(dirname "$0")/.." && pwd)/tools/artifacts.py" run --label test-native-display-test -- bash "$0" "$@"
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/app/Sources/ExeRunner/Core"
WORK="$(mktemp -d "${TMPDIR:-/private/tmp}/exerunner-native-display.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
cp "$ROOT/tests/native-display-test.swift" "$WORK/main.swift"
cat > "$WORK/paths.swift" <<'SWIFT'
import Foundation
enum Paths {
 static let support = URL(fileURLWithPath: "/private/tmp/exerunner-display-fixture-support")
 static let settingsFile = support.appendingPathComponent("settings.json")
 static let defaultBottles = support.appendingPathComponent("bottles")
 static func ensure(_ url: URL) throws { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
}
SWIFT
swiftc -O -module-cache-path "$WORK/modules" "$WORK/main.swift" "$WORK/paths.swift" \
 "$SRC/NativeDisplayPolicy.swift" "$SRC/Settings.swift" "$SRC/Localization.swift" "$SRC/English.swift" -o "$WORK/check"
"$WORK/check"
