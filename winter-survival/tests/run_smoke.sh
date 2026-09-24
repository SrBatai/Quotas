#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
godot --headless --path . --import > /tmp/ventisca_import.log 2>&1 || true
godot --headless --path . -s tests/smoke_test.gd 2>&1 | grep -v -E "ALSA lib|pulse|XDG_RUNTIME|libudev|udev" | tee /tmp/ventisca_smoke.log
if grep -E "SCRIPT ERROR|ERROR: |FAIL:" /tmp/ventisca_smoke.log; then echo "SMOKE TEST FAILED"; exit 1; fi
echo "SMOKE TEST OK"
