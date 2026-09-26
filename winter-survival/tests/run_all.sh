#!/usr/bin/env bash
# Runs every gate (PLAN §6 "definición de hecho"): import, parse check, unit tests (persistence), smoke test (Jolt,
# headless, skeletal player + feet metric), art contract (inspect_models), perf probe (xvfb + Compatibility, budgets),
# the net scenarios `basic` (4 clients), `shared_world` (3 clients, M2) and `far` (2 clients 1 km apart, M3 interest),
# the M3 world gates (determinism client vs server, streaming perf walk: --cpu headless budget + render mode under
# xvfb/llvmpipe for ground and memory) and, with --shots, the screenshots. --no-walk-render skips the (slow) render walk.
# Exit code != 0 if anything fails.
set -uo pipefail
cd "$(dirname "$0")/.."
SHOTS=0
WALK_RENDER=1
for a in "$@"; do
  [ "$a" = "--shots" ] && SHOTS=1
  [ "$a" = "--no-walk-render" ] && WALK_RENDER=0
done
status=0
step() { echo; echo "#### $1"; }

step "import"
godot --headless --path . --import > /tmp/ventisca_import.log 2>&1 || true
if grep -E "^ERROR: " /tmp/ventisca_import.log | grep -v -E "ALSA|pulse|udev" ; then echo "IMPORT: errors above"; fi

step "parse check"
godot --headless --path . -s tests/parse_check.gd 2>&1 | grep -v -E "ALSA lib|pulse|XDG_RUNTIME|libudev|udev" | tail -n 3
[ "${PIPESTATUS[0]}" -eq 0 ] || { echo "PARSE CHECK FAILED"; status=1; }

step "unit tests (persistence backends)"
godot --headless --path . -s tests/unit/persistence_test.gd 2>&1 | grep -v -E "ALSA lib|pulse|XDG_RUNTIME|libudev|udev" | grep -E "FAIL|SCRIPT ERROR|ERROR: |== " | tail -n 5
[ "${PIPESTATUS[0]}" -eq 0 ] || { echo "PERSISTENCE TEST FAILED"; status=1; }

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

step "net test shared_world (M2: A chops / B sees, cabinet 'en uso', late joiner C gets the deltas)"
if NET_TEST_OUT=/tmp/ventisca_net_sw tests/net/run_net_test.sh --clients 3 --duration 60 --soak 90 --scenario shared_world --port 7787 > /tmp/ventisca_net_sw_all.log 2>&1; then
  grep -E "RESULT|admin|NET TEST" /tmp/ventisca_net_sw_all.log
else
  grep -E "RESULT|admin|!!|FAIL|SCRIPT ERROR|ERROR: |NET TEST" /tmp/ventisca_net_sw_all.log | head -n 30; status=1
fi

step "net test far (M3: A and B 1 km apart only receive their own ring: poses, actors, deltas, snapshots)"
if NET_TEST_OUT=/tmp/ventisca_net_far tests/net/run_net_test.sh --clients 2 --duration 30 --soak 45 --scenario far --port 7797 > /tmp/ventisca_net_far_all.log 2>&1; then
  grep -E "RESULT|admin|NET TEST" /tmp/ventisca_net_far_all.log
else
  grep -E "RESULT|admin|!!|FAIL|SCRIPT ERROR|ERROR: |NET TEST" /tmp/ventisca_net_far_all.log | head -n 30; status=1
fi

step "determinism (M3: 50 chunks, server path vs client path, two processes)"
if tests/run_determinism.sh > /tmp/ventisca_det_all.log 2>&1; then
  grep -E "determinism|DETERMINISM" /tmp/ventisca_det_all.log | tail -n 3
else
  grep -E "determinism|ERROR|SCRIPT|DETERMINISM|^[<>]" /tmp/ventisca_det_all.log | head -n 20; status=1
fi

step "perf walk --cpu (M3: streaming main-thread cost at 25 m/s, headless)"
if tests/run_perf_walk.sh --cpu > /tmp/ventisca_walk_cpu_all.log 2>&1; then
  grep -E "streaming ms|frames over|chunks  |memory  |PERF WALK" /tmp/ventisca_walk_cpu_all.log
else
  grep -E "frame ms|streaming ms|chunks  |memory  |FAIL|SCRIPT ERROR|PERF WALK" /tmp/ventisca_walk_cpu_all.log | head -n 20; status=1
fi

if [ "$WALK_RENDER" -eq 1 ]; then
  step "perf walk render (M3: xvfb + Compatibility on llvmpipe: ground always under the player, RSS)"
  if command -v xvfb-run > /dev/null; then
    if tests/run_perf_walk.sh > /tmp/ventisca_walk_all.log 2>&1; then
      grep -E "frame ms|streaming ms|chunks  |memory  |PERF WALK" /tmp/ventisca_walk_all.log
    else
      grep -E "frame ms|streaming ms|chunks  |memory  |FAIL|SCRIPT ERROR|PERF WALK" /tmp/ventisca_walk_all.log | head -n 20; status=1
    fi
  else
    echo "xvfb-run not found: render perf walk skipped"
  fi
fi

if [ "$SHOTS" -eq 1 ]; then
  step "screenshots"
  tests/run_screenshots.sh "${SHOTS_DIR:-/tmp/ventisca_shots}" > /tmp/ventisca_shots_all.log 2>&1 || status=1
  grep -E "screenshot .* ->" /tmp/ventisca_shots_all.log
fi

echo
if [ "$status" -eq 0 ]; then echo "RUN_ALL: ALL PASSED"; else echo "RUN_ALL: FAILED"; fi
exit $status
