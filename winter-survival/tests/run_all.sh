#!/usr/bin/env bash
# Runs every gate (PLAN §6 "definición de hecho"): import, parse check, unit tests (persistence), smoke test (Jolt,
# headless, skeletal player + feet metric), art contract (inspect_models), perf probe (xvfb + Compatibility, budgets),
# the net scenarios `basic` (4 clients), `shared_world` (3 clients, M2), `far` (2 clients 1 km apart, M3 interest) and
# `zombies` (4 clients, M4: same deaths everywhere, downed/revive/respawn at the bed, friendly fire, pvp, zombie
# bandwidth), the W1 gates (6 km world checks, «el valle no cambia», macro map reproducible; `far` with 4 clients in
# the 4 quadrants), the M3 world gates (determinism client vs server, streaming perf walk: --cpu headless budget + render
# mode under xvfb/llvmpipe for ground and memory), the M4 horde perf (200 zombies + 4 bots on a dedicated server,
# median tick), the W0 + G2a render checks (headless) and city bench (xvfb: visibility through the «corte urbano»,
# shadows, draw-call budgets), the H1 HUD coverage gate (idle HUD ≤ 3 % of 1080p, rendered; the HUD logic checks
# run inside the smoke test) and, with --shots, the screenshots (+ city presets). --no-walk-render skips the (slow)
# render walk. M5: godot-sqlite fetched first (pinned + SHA-256), SQLite / loot / firearms unit tests, the `hitscan`
# scenario behind tests/net/net_sim.gd (150 ms, ±20, 2 % loss) and the `restart` scenario on both stores. H2: the zone
# tracker unit test (hysteresis, hierarchy, cooldowns, highway sign, W1's 20 points, discovery store, names C36; the
# in-game zone steps run inside the smoke test) and the `discovery` scenario (group discovery across a restart) on both
# stores.
# On a shared machine pin it: taskset -c 0,1 tests/run_all.sh
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

step "godot-sqlite (M5 / R6: pinned v4.9, SHA-256 checked; before the import so the extension is registered)"
tools/fetch_godot_sqlite.sh || { echo "GODOT-SQLITE FETCH FAILED (the server would fall back to the JSON store)"; status=1; }

step "import"
godot --headless --path . --import > /tmp/ventisca_import.log 2>&1 || true
if grep -E "^ERROR: " /tmp/ventisca_import.log | grep -v -E "ALSA|pulse|udev" ; then echo "IMPORT: errors above"; fi

step "parse check"
godot --headless --path . -s tests/parse_check.gd 2>&1 | grep -v -E "ALSA lib|pulse|XDG_RUNTIME|libudev|udev" | tail -n 3
[ "${PIPESTATUS[0]}" -eq 0 ] || { echo "PARSE CHECK FAILED"; status=1; }

step "unit tests (persistence backends)"
godot --headless --path . -s tests/unit/persistence_test.gd 2>&1 | grep -v -E "ALSA lib|pulse|XDG_RUNTIME|libudev|udev" | grep -E "FAIL|SCRIPT ERROR|ERROR: |== " | tail -n 5
[ "${PIPESTATUS[0]}" -eq 0 ] || { echo "PERSISTENCE TEST FAILED"; status=1; }

step "unit tests (M5: SqliteBackend, schema 3 + migrations, crash mid-batch; loot rolls, nominal caps, firearms maths)"
for t in persistence_m5_test m5_units_test; do
  godot --headless --path . -s tests/unit/$t.gd 2>&1 | grep -v -E "ALSA lib|pulse|XDG_RUNTIME|libudev|udev" | grep -E "FAIL|SCRIPT ERROR|ERROR: |== " | tail -n 5
  [ "${PIPESTATUS[0]}" -eq 0 ] || { echo "$t FAILED"; status=1; }
done

step "unit tests (H2: zone tracker — zigzag 0 changes, 12 m / 1.5 s, district over city, cooldowns, combat / P0, exit line, highway sign, camera profile, W1's 20 points, discovery store schema 3, names C36)"
godot --headless --path . -s tests/unit/zone_tracker_test.gd 2>&1 | grep -v -E "ALSA lib|pulse|XDG_RUNTIME|libudev|udev" | grep -E "FAIL|== " | tail -n 5
[ "${PIPESTATUS[0]}" -eq 0 ] || { echo "ZONE TRACKER TEST FAILED"; status=1; }

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

step "hud coverage (H1: idle HUD ≤ 3 % of 1920 × 1080, HUD layer only over black / white; xvfb + Compatibility)"
if command -v xvfb-run > /dev/null; then
  if tests/run_hud_coverage.sh --moments=idle,action,zone,blizzard,info > /tmp/ventisca_hud_cov_all.log 2>&1; then
    grep -E "^coverage |ok   |HUD COVERAGE" /tmp/ventisca_hud_cov_all.log
  else
    grep -E "^coverage |FAIL|SCRIPT ERROR|HUD COVERAGE" /tmp/ventisca_hud_cov_all.log | head -n 20; status=1
  fi
else
  echo "xvfb-run not found: hud coverage skipped"
fi

step "render checks (W0 + G2a: corte urbano maths, city building contract, POI cutaway, camera profiles, headless)"
godot --headless --path . -s tests/render_checks.gd 2>&1 | grep -v -E "ALSA lib|pulse|XDG_RUNTIME|libudev|udev" | grep -E "FAIL|SCRIPT ERROR|== render checks" | tail -n 12
[ "${PIPESTATUS[0]}" -eq 0 ] || { echo "RENDER CHECKS FAILED"; status=1; }

step "city bench (W0 + G2a: player visible through the cut at 16-50 m, shadows kept, draw-call budgets; xvfb + Compatibility)"
if command -v xvfb-run > /dev/null; then
  if tests/run_city_bench.sh gate > /tmp/ventisca_city_all.log 2>&1; then
    grep -E "^  (canyon|crossing|rooftop|inside|north|shadow|fade|ok|info|compat)|CITY BENCH" /tmp/ventisca_city_all.log
  else
    grep -E "FAIL|SCRIPT ERROR|CITY BENCH|^  (canyon|crossing|rooftop|inside|north)" /tmp/ventisca_city_all.log | head -n 30; status=1
  fi
else
  echo "xvfb-run not found: city bench skipped"
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

step "net test far (M3 + W1: 4 clients in the 4 quadrants, up to 5 km apart, only receive their own ring: poses, actors, deltas, snapshots; server RSS ≤ 400 MB)"
if NET_TEST_OUT=/tmp/ventisca_net_far tests/net/run_net_test.sh --clients 4 --duration 40 --soak 55 --scenario far --port 7797 > /tmp/ventisca_net_far_all.log 2>&1; then
  grep -E "RESULT|admin|server RSS|NET TEST" /tmp/ventisca_net_far_all.log
else
  grep -E "RESULT|admin|!!|FAIL|SCRIPT ERROR|ERROR: |NET TEST" /tmp/ventisca_net_far_all.log | head -n 30; status=1
fi

step "net test zombies (M4: 4 clients, 100 zombies, same deaths on all, downed → revived → killed → respawn at the bed, ff off/full, pvp, ≤ 15 kB/s)"
if NET_TEST_OUT=/tmp/ventisca_net_zombies tests/net/run_net_test.sh --clients 4 --duration 62 --soak 70 --scenario zombies --port 7807 > /tmp/ventisca_net_zombies_all.log 2>&1; then
  grep -E "RESULT|admin|NET TEST" /tmp/ventisca_net_zombies_all.log
else
  grep -E "RESULT|admin|!!|FAIL|SCRIPT ERROR|ERROR: |NET TEST" /tmp/ventisca_net_zombies_all.log | head -n 30; status=1
fi

step "net test hitscan (M5: --net-sim 150,20,2; A shoots B walking across 10 m away, lag compensation ≤ 200 ms, ≥ 60 % hits and more than without the rewind, dry fire refused)"
if NET_TEST_OUT=/tmp/ventisca_net_hitscan tests/net/run_net_test.sh --clients 2 --duration 25 --soak 38 --scenario hitscan --port 7837 --net-sim 150,20,2 > /tmp/ventisca_net_hitscan_all.log 2>&1; then
  grep -E "RESULT|hitscan \(server\)|NET TEST" /tmp/ventisca_net_hitscan_all.log
else
  grep -E "RESULT|hitscan|!!|FAIL|SCRIPT ERROR|ERROR: |NET TEST" /tmp/ventisca_net_hitscan_all.log | head -n 30; status=1
fi

step "restart (M5: SE-quadrant player, campfires, felled pine, looted container, pistol magazine survive save-and-quit; world_version 2; sqlite + file)"
for b in sqlite file; do
  if NET_TEST_OUT=/tmp/ventisca_restart_$b tests/net/run_restart_test.sh --backend $b --port $([ $b = sqlite ] && echo 7827 || echo 7847) > /tmp/ventisca_restart_${b}_all.log 2>&1; then
    grep -E "dbinfo \(after restart\)|RESULT|RESTART TEST" /tmp/ventisca_restart_${b}_all.log | cut -c1-220
  else
    grep -E "dbinfo|RESULT|!!|RESTART TEST" /tmp/ventisca_restart_${b}_all.log | cut -c1-220 | head -n 30; status=1
  fi
done

step "discovery (H2: A discovers the Granja del Molino, B gets the feed line and the compact title, C after a save-and-quit restart; sqlite + file)"
for b in sqlite file; do
  if NET_TEST_OUT=/tmp/ventisca_discovery_$b tests/net/run_discovery_test.sh --backend $b --port $([ $b = sqlite ] && echo 7857 || echo 7867) > /tmp/ventisca_discovery_${b}_all.log 2>&1; then
    grep -E "RESULT|zone discovered|discovery:|DISCOVERY TEST" /tmp/ventisca_discovery_${b}_all.log | cut -c1-220
  else
    grep -E "dbinfo|RESULT|!!|DISCOVERY TEST" /tmp/ventisca_discovery_${b}_all.log | cut -c1-220 | head -n 30; status=1
  fi
done

step "determinism (M3 + W1: 60 chunks in the 4 quadrants, server path vs client path, two processes)"
if tests/run_determinism.sh > /tmp/ventisca_det_all.log 2>&1; then
  grep -E "determinism|DETERMINISM" /tmp/ventisca_det_all.log | tail -n 3
else
  grep -E "determinism|ERROR|SCRIPT|DETERMINISM|^[<>]" /tmp/ventisca_det_all.log | head -n 20; status=1
fi

step "W1 world (6 km: walls, macro 768², 20 banner points + LocationInfo data, flat ice, reserved pads, road / rail stamps, W1 props, population 96²)"
godot --headless --path . -s tests/w1_world.gd 2>&1 | grep -v -E "ALSA lib|pulse|XDG_RUNTIME|libudev|udev" | grep -E "FAIL|SCRIPT ERROR|== [0-9]+ checks|chunk generation" | tail -n 12
[ "${PIPESTATUS[0]}" -eq 0 ] || { echo "W1 WORLD FAILED"; status=1; }

step "valley unchanged (W1: height / surface / scatter of the 1 225 chunks with |x|, |z| < 1152 m = pre-W1, closed Carretera del Puerto list)"
godot --headless --path . -s tests/valley_unchanged.gd 2>&1 | grep -v -E "ALSA lib|pulse|XDG_RUNTIME|libudev|udev" | grep -E "FAIL|SCRIPT ERROR|valley unchanged|VALLEY" | tail -n 12
[ "${PIPESTATUS[0]}" -eq 0 ] || { echo "VALLEY UNCHANGED FAILED"; status=1; }

step "macro map reproducible (W1: tools/gen_macro_map.gd --check rebuilds macro_map.png + macro_roads.json byte for byte)"
godot --headless --path . -s tools/gen_macro_map.gd ++ --check 2>&1 | grep -v -E "ALSA lib|pulse|XDG_RUNTIME|libudev|udev" | grep -E "check|SCRIPT ERROR" | tail -n 3
[ "${PIPESTATUS[0]}" -eq 0 ] || { echo "MACRO MAP CHECK FAILED"; status=1; }

step "perf walk --cpu (M3 + W1: streaming main-thread cost at 25 m/s over 6.5 km through the 4 quadrants, headless; gated on the work time = wall − run-queue wait)"
if tests/run_perf_walk.sh --cpu > /tmp/ventisca_walk_cpu_all.log 2>&1; then
  grep -E "streaming ms|streaming work|frames over|chunks  |memory  |PERF WALK" /tmp/ventisca_walk_cpu_all.log
else
  grep -E "frame ms|streaming ms|chunks  |memory  |FAIL|SCRIPT ERROR|PERF WALK" /tmp/ventisca_walk_cpu_all.log | head -n 20; status=1
fi

step "perf horde (M4: dedicated server, 4 bots, 200 zombies: median busy tick ≤ 8 ms, p99 reported)"
if tests/run_perf_horde.sh > /tmp/ventisca_horde_all.log 2>&1; then
  grep -E "tick ms|zombies |net |routes |PERF HORDE" /tmp/ventisca_horde_all.log
else
  grep -E "tick ms|FAIL|SCRIPT ERROR|PERF HORDE" /tmp/ventisca_horde_all.log | head -n 20; status=1
fi

if [ "$WALK_RENDER" -eq 1 ]; then
  step "perf walk render (M3 + W1: 6.5 km, xvfb + Compatibility on llvmpipe: ground always under the player, client RSS ≤ 2.5 GB)"
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
  tests/run_city_bench.sh shots "${SHOTS_DIR:-/tmp/ventisca_shots}/city" >> /tmp/ventisca_shots_all.log 2>&1 || status=1
  grep -E "screenshot .* ->" /tmp/ventisca_shots_all.log
fi

echo
if [ "$status" -eq 0 ]; then echo "RUN_ALL: ALL PASSED"; else echo "RUN_ALL: FAILED"; fi
exit $status
