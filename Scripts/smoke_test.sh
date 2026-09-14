#!/bin/bash
set -euo pipefail

# Boot a simulator, install the app, and prove the world runs on its own.
# The core assertion matches the design goal: with zero input, two screenshots
# taken seconds apart must differ.

cd "$(dirname "$0")/.."

if [ "${VERBOSE:-0}" = "1" ]; then set -x; fi

BUNDLE_ID="com.example.tinyfarm"
APP="build/TinyFarm.app"
OUT="artifacts"
mkdir -p "$OUT"

[ -d "$APP" ] || { echo "missing $APP - run Scripts/build_app.sh first"; exit 1; }

echo "==> Picking a simulator"
UDID="$(xcrun simctl list devices available | grep -E 'iPhone' | head -1 \
        | sed -E 's/.*\(([0-9A-Fa-f-]{36})\).*/\1/')"
[ -n "$UDID" ] || { echo "no iPhone simulator available"; exit 1; }
echo "    UDID=$UDID"

xcrun simctl list devices | grep -F "$UDID" || true

echo "==> Booting"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b

echo "==> Installing and launching"
xcrun simctl install "$UDID" "$APP"
PID="$(xcrun simctl launch "$UDID" "$BUNDLE_ID" | sed -E 's/.*: ([0-9]+)/\1/')"
echo "    pid=$PID"
sleep 5

echo "==> Capturing frames with no interaction"
xcrun simctl io "$UDID" screenshot "$OUT/frame_a.png"
sleep 6
xcrun simctl io "$UDID" screenshot "$OUT/frame_b.png"
ls -la "$OUT"

A="$(shasum -a 256 "$OUT/frame_a.png" | cut -d' ' -f1)"
B="$(shasum -a 256 "$OUT/frame_b.png" | cut -d' ' -f1)"
echo "    frame_a=$A"
echo "    frame_b=$B"
if [ "$A" = "$B" ]; then
    echo "FAIL: the world did not change over 6 seconds - it should run itself"
    exit 1
fi
echo "PASS: the world animates with no input"

echo "==> Checking the app survived"
ALIVE="$(xcrun simctl spawn "$UDID" launchctl list 2>/dev/null | grep -c tinyfarm || true)"
[ "$ALIVE" -ge 1 ] || { echo "FAIL: app is no longer running"; exit 1; }
echo "PASS: app still running"

CRASHES="$(find "$HOME/Library/Logs/DiagnosticReports" -iname '*inyFarm*' 2>/dev/null | wc -l | tr -d ' ')"
[ "$CRASHES" = "0" ] || { echo "FAIL: found $CRASHES crash report(s)"; exit 1; }
echo "PASS: no crash reports"

echo "==> Smoke test complete"
