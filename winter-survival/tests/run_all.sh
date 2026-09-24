#!/usr/bin/env bash
# Runs every M0 gate (PLAN §6 "definición de hecho"): import, parse check, smoke test (Jolt, headless),
# art contract (inspect_models), perf probe (xvfb + Compatibility, budgets) and, with --shots, the screenshots.
# Exit code != 0 if anything fails.
set -uo pipefail
cd "$(dirname "$0")/.."
SHOTS=0
for a in "$@"; do [ "$a" = "--shots" ] && SHOTS=1; done
status=0
step() { echo; echo "#### $1"; }

step "import"
godot --headless --path . --import > /tmp/ventisca_import.log 2>&1 || true
if grep -E "^ERROR: " /tmp/ventisca_import.log | grep -v -E "ALSA|pulse|udev" ; then echo "IMPORT: errors above"; fi

step "parse check"
godot --headless --path . -s tests/parse_check.gd 2>&1 | grep -v -E "ALSA lib|pulse|XDG_RUNTIME|libudev|udev" | tail -n 3
[ "${PIPESTATUS[0]}" -eq 0 ] || { echo "PARSE CHECK FAILED"; status=1; }

step "smoke test"
if tests/run_smoke.sh > /tmp/ventisca_smoke_all.log 2>&1; then grep -E "== [0-9]+ checks|SMOKE TEST" /tmp/ventisca_smoke_all.log; else grep -E "FAIL|SCRIPT ERROR|ERROR: |SMOKE TEST" /tmp/ventisca_smoke_all.log | head -n 20; status=1; fi

step "inspect models (ASSET_SPEC v2)"
godot --headless --path . -s tests/inspect_models.gd ++ --quiet 2>&1 | grep -v -E "ALSA lib|pulse|XDG_RUNTIME|libudev|udev" | grep -E "^(OK|FAIL|WARN|== inspect)" | tee /tmp/ventisca_inspect.log
grep -q "ALL OK" /tmp/ventisca_inspect.log || { echo "INSPECT MODELS FAILED"; status=1; }

step "perf probe"
if command -v xvfb-run > /dev/null; then
  tests/run_perf.sh --label=run_all > /tmp/ventisca_perf_all.log 2>&1 || status=1
  grep -E "draw calls|objects|primitives|frame ms|ok   |FAIL|PERF" /tmp/ventisca_perf_all.log
else
  echo "xvfb-run not found: perf probe skipped"
fi

step "net test (M1: 1 headless server + 4 headless clients, soak 90 s)"
if tests/net/run_net_test.sh --clients 4 --duration 60 --soak 90 > /tmp/ventisca_net_all.log 2>&1; then
  grep -E "RESULT|admin|NET TEST" /tmp/ventisca_net_all.log
else
  grep -E "RESULT|admin|!!|FAIL|SCRIPT ERROR|ERROR: |NET TEST" /tmp/ventisca_net_all.log | head -n 30; status=1
fi

if [ "$SHOTS" -eq 1 ]; then
  step "screenshots"
  tests/run_screenshots.sh "${SHOTS_DIR:-/tmp/ventisca_shots}" > /tmp/ventisca_shots_all.log 2>&1 || status=1
  grep -E "screenshot .* ->" /tmp/ventisca_shots_all.log
fi

echo
if [ "$status" -eq 0 ]; then echo "RUN_ALL: ALL PASSED"; else echo "RUN_ALL: FAILED"; fi
exit $status
