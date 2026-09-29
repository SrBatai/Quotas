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
# scenario behind tests/net/net_sim.gd (150 ms, ±20, 2 % loss) and the `restart` scenario on both stores. C0: the city
# checks (headless), the corte urbano probe and the draw calls of the Las Torres block (xvfb), PCSS far from the origin
# (Forward+ on lavapipe) and the perf walk into the city (the lot file hash is in the determinism gate). H2: the zone
# tracker unit test (hysteresis, hierarchy, cooldowns, highway sign, W1's 20 points, discovery store, names C36; the
# in-game zone steps run inside the smoke test) and the `discovery` scenario (group discovery across a restart) on both
# stores. M6a: the kit street checks (headless), the street bench (citycut_probe + interior shadow, xvfb) and the
# `street` scenario (replicated kit doors, late joiner).
# C1: the city generator reproducible (tools/gen_city.gd --check), the C1 city checks (headless; they replace the C0
# ones: the lot file is v1), the corte urbano probe at 10 seeded points of the four districts (xvfb), the `tower`
# scenario (4 clients on 3 floors of a hero tower: doors, a container, the vertical interest filter ≥ 30 %), the urban
# perf walk (--cpu --route=city at 15 m/s) and the city horde (perf_horde --city: 150 walkers + 300 statues).
# M6b: the La Herrería checks (generator, stamps, residents, zones, built chunks; headless), the `village` scenario
# (2 players in 2 houses: doors + containers coherent, the plan hash equal on the server and both clients) and the
# village drive (perf walk --cpu --route=m6b: own frame p99 ≤ 16 ms, 0 frames > 33 ms caused by the village or by
# streaming, the site builders ≤ 16 ms in any frame). The in-game village steps
# (residents by land use, locked doors, the shop alarm, loot by use) run inside the smoke test.
# S1: the audio unit test (event table, files, licences, budgets, voice budget; the in-game audio steps — listener,
# gunfire at the muzzle, loops, ambience beds by place, 50-zombie voice budget — run inside the smoke test).
# H3: the notify router unit test (P0–P3, precedence, queue, merge, cooldown, hazard stack), the `downed_coop`
# coverage moment (≤ 3 %, gated like idle) and the `team` scenario (a danger ping on every client, B's down reaches A
# ≤ 0.2 s after the server, the blizzard countdown); the in-game H3 steps (a simulated P0) run inside the smoke test.
# G2b: the atmosphere checks (headless; LUTs reproducible with tools/make_luts.py --check) and the G2b bench (blizzard
# vs day frame ratio in the city on lavapipe, LUT blend in the frame loop, compat vs Forward+ fog depth); --shots adds
# the 8 hours × 3 weathers contact sheet (g2b_sheet).
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

step "unit tests (H3: notify router — P0 in the world / on the vital, P1–P2 line, P3 pickup line, precedence after 1.2 s, back to the queue, queue of 6, merge, cooldown, co-op filter, zone crossing, P0 sound + caption, hazard stack)"
godot --headless --path . -s tests/unit/notify_router_test.gd 2>&1 | grep -v -E "ALSA lib|pulse|XDG_RUNTIME|libudev|udev" | grep -E "FAIL|== " | tail -n 5
[ "${PIPESTATUS[0]}" -eq 0 ] || { echo "NOTIFY ROUTER TEST FAILED"; status=1; }

step "unit tests (S1: audio — event table valid, every event the code plays has a stream or a documented silence, files load mono / stereo with sane length and peaks, licences, variations, ≤ 10.5 MB, voice budget / loops / layering in the AudioManager)"
godot --headless --path . -s tests/unit/audio_test.gd 2>&1 | grep -v -E "ALSA lib|pulse|XDG_RUNTIME|libudev|udev" | grep -E "FAIL|== " | tail -n 5
[ "${PIPESTATUS[0]}" -eq 0 ] || { echo "AUDIO TEST FAILED"; status=1; }

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

step "hud coverage (H1: idle HUD ≤ 3 % of 1920 × 1080, HUD layer only over black / white; H3: downed_coop ≤ 3 % too; xvfb + Compatibility)"
if command -v xvfb-run > /dev/null; then
  if tests/run_hud_coverage.sh --moments=idle,action,zone,blizzard,info,downed_coop > /tmp/ventisca_hud_cov_all.log 2>&1; then
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

step "G2b checks (atmosphere: LUTs + CPU blend ≤ 0.1 ms / 0 at rest, grade weights, overcast, fog layers + volumetric policy, thaw, wind materials, sprites, beacons / smoke / flocks / cables; headless) + LUTs and sprites reproducible"
godot --headless --path . -s tests/g2b_checks.gd 2>&1 | grep -v -E "ALSA lib|pulse|XDG_RUNTIME|libudev|udev" | grep -E "FAIL|SCRIPT ERROR|info|== g2b checks" | tail -n 12
[ "${PIPESTATUS[0]}" -eq 0 ] || { echo "G2B CHECKS FAILED"; status=1; }
python3 tools/make_luts.py --check || { echo "LUTS NOT REPRODUCIBLE"; status=1; }

step "G2b bench (blizzard in the C0 city ≤ +25 % over the day, Forward+ on lavapipe; LUT step in the frame loop; compat keeps the fog depth of Forward+ ≥ 80 %; xvfb)"
if command -v xvfb-run > /dev/null; then
  if tests/run_g2b_bench.sh gate > /tmp/ventisca_g2b_all.log 2>&1; then
    grep -E "city frame ms|ratio |  ok|depth compat|G2B BENCH" /tmp/ventisca_g2b_all.log
  else
    grep -E "FAIL|SCRIPT ERROR|city frame ms|ratio |depth compat|G2B BENCH" /tmp/ventisca_g2b_all.log | head -n 20; status=1
  fi
else
  echo "xvfb-run not found: G2b bench skipped"
fi

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

step "C1 city generator reproducible (tools/gen_city.gd --check rebuilds data/world/city/altavega_lots.json byte for byte)"
godot --headless --path . -s tools/gen_city.gd ++ --check 2>&1 | grep -v -E "ALSA lib|pulse|XDG_RUNTIME|libudev|udev" | grep -E "check|SCRIPT ERROR|FAIL" | tail -n 3
[ "${PIPESTATUS[0]}" -eq 0 ] || { echo "CITY GENERATOR CHECK FAILED"; status=1; }

step "C1 city (Altavega: lot file v1, districts / zone titles / street graph, families + city contract, streaming of the 4 districts, hero towers: stairs, doors, loot, roof, NavFloorTile + stair links, vertical filter, floor population, dressing digest, silhouettes, frozen statues; headless)"
godot --headless --path . -s tests/c1_city.gd ++ --no-gen 2>&1 | grep -v -E "ALSA lib|pulse|XDG_RUNTIME|libudev|udev" | grep -E "FAIL|SCRIPT ERROR|== [0-9]+ checks" | tail -n 12
[ "${PIPESTATUS[0]}" -eq 0 ] || { echo "C1 CITY FAILED"; status=1; }

step "C0 corte urbano probe (5 fixed points of the superblock LT-01 at 24 / 38 m: player ≥ 99 %, all ≥ 95 % readable; xvfb + Compatibility)"
if command -v xvfb-run > /dev/null; then
  if tests/run_citycut_probe.sh > /tmp/ventisca_citycut_all.log 2>&1; then
    grep -E "^  (gran_via|west_street|back_street|plaza|mirador|overall)|CITYCUT" /tmp/ventisca_citycut_all.log
  else
    grep -E "FAIL|SCRIPT ERROR|CITYCUT|^  (gran_via|west_street|back_street|plaza|mirador|overall)" /tmp/ventisca_citycut_all.log | head -n 20; status=1
  fi
  step "C1 corte urbano probe (10 seeded sidewalk points of the 4 districts of Altavega at 24 / 38 m: player + zombies ≥ 95 % readable; xvfb + Compatibility)"
  if tests/run_citycut_probe.sh --points=c1 > /tmp/ventisca_citycut_c1_all.log 2>&1; then
    grep -E "^  (casco|ensanche|barriada|las_torres|overall)|CITYCUT" /tmp/ventisca_citycut_c1_all.log
  else
    grep -E "FAIL|SCRIPT ERROR|CITYCUT|^  (casco|ensanche|barriada|las_torres|overall)" /tmp/ventisca_citycut_c1_all.log | head -n 30; status=1
  fi
  step "C0 perf probe altavega_c0 (day + night: ≤ 700 draw calls in Compatibility; RENDER=forward: ≤ 1 000)"
  for h in 11 22.5; do
    if tests/run_perf.sh --scene=altavega_c0 --hour=$h --label=altavega_c0 --out=tests/perf/altavega_c0_$h.json > /tmp/ventisca_perf_c0_all.log 2>&1; then
      grep -E "altavega_c0 view|draw calls|ok   " /tmp/ventisca_perf_c0_all.log
    else
      grep -E "altavega_c0 view|draw calls|FAIL|SCRIPT ERROR|PERF" /tmp/ventisca_perf_c0_all.log | head -n 10; status=1
    fi
  done
  step "C0 PCSS far from the origin (R23: the same tower at the origin and at 2.7 km, mean penumbra difference ≤ 3 %; Forward+ on lavapipe)"
  if tests/run_pcss_probe.sh > /tmp/ventisca_pcss_all.log 2>&1; then
    grep -E "penumbra|info|PCSS PROBE" /tmp/ventisca_pcss_all.log
  else
    grep -E "penumbra|FAIL|SCRIPT ERROR|PCSS PROBE" /tmp/ventisca_pcss_all.log | head -n 10; status=1
  fi
else
  echo "xvfb-run not found: C0 probes skipped"
fi

step "M6a checks (kit street: buildings, CutawayManager storeys / stubs / shadow-preserving, doors, signs, wids; headless)"
godot --headless --path . -s tests/m6a_checks.gd 2>&1 | grep -v -E "ALSA lib|pulse|XDG_RUNTIME|libudev|udev" | grep -E "FAIL|SCRIPT ERROR|== m6a checks" | tail -n 12
[ "${PIPESTATUS[0]}" -eq 0 ] || { echo "M6A CHECKS FAILED"; status=1; }

step "M6a street bench (citycut_probe on the test street: player ≥ 99 %, zombies ≥ 95 % readable; interior shadow ±5 %; xvfb + Compatibility)"
if command -v xvfb-run > /dev/null; then
  if tests/run_street_bench.sh gate > /tmp/ventisca_street_all.log 2>&1; then
    grep -E "citycut_probe|interior shadow|STREET BENCH" /tmp/ventisca_street_all.log
  else
    grep -E "FAIL|SCRIPT ERROR|citycut_probe|interior shadow|STREET BENCH" /tmp/ventisca_street_all.log | head -n 20; status=1
  fi
else
  echo "xvfb-run not found: street bench skipped"
fi

step "M6b checks (La Herrería: 15–20 buildings / ≥ 6 enterable, OBB lots 400–900 m², plan hash, level pads, residents by land use, zones, built chunks; headless)"
godot --headless --path . -s tests/m6b_checks.gd 2>&1 | grep -v -E "ALSA lib|pulse|XDG_RUNTIME|libudev|udev" | grep -E "FAIL|SCRIPT ERROR|== m6b checks" | tail -n 12
[ "${PIPESTATUS[0]}" -eq 0 ] || { echo "M6B CHECKS FAILED"; status=1; }

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

step "net test street (M6a: kit doors — A opens, B sees and closes, A reopens, late joiner C gets the open door from the chunk snapshot)"
if NET_TEST_OUT=/tmp/ventisca_net_street tests/net/run_net_test.sh --clients 3 --duration 62 --soak 100 --scenario street --port 7877 > /tmp/ventisca_net_street_all.log 2>&1; then
  grep -E "RESULT|NET TEST" /tmp/ventisca_net_street_all.log | cut -c1-220
else
  grep -E "RESULT|!!|FAIL|SCRIPT ERROR|NET TEST" /tmp/ventisca_net_street_all.log | cut -c1-220 | head -n 30; status=1
fi

step "net test village (M6b: A and B in two La Herrería houses open their doors and containers; each sees the other's door and finds the other's container as it was left; plan hash equal on the server and both clients)"
if NET_TEST_OUT=/tmp/ventisca_net_village tests/net/run_net_test.sh --clients 2 --duration 90 --soak 120 --scenario village --port 7917 > /tmp/ventisca_net_village_all.log 2>&1 \
    && [ "$(grep -h '\[SETTLEMENT\] plans\|\[SETTLEMENT\] client plans' /tmp/ventisca_net_village/*.log | grep -o 'plans [0-9a-f]*' | sort -u | wc -l)" = "1" ]; then
  grep -E "RESULT|NET TEST" /tmp/ventisca_net_village_all.log | cut -c1-220
  grep -h "\[SETTLEMENT\] plans" /tmp/ventisca_net_village/server.log | head -n 1
else
  grep -E "RESULT|!!|FAIL|SCRIPT ERROR|NET TEST" /tmp/ventisca_net_village_all.log | cut -c1-220 | head -n 30
  grep -h "SETTLEMENT\] .*plans" /tmp/ventisca_net_village/*.log | head -n 4; status=1
fi

step "net test interest (replicated nodes spawned / moved outside a peer's chunk interest — late joiner, 3 jumps in and out, a wolf on one side only: no 'Ignoring delta' on any client)"
if NET_TEST_OUT=/tmp/ventisca_net_interest tests/net/run_net_test.sh --clients 2 --duration 40 --soak 60 --scenario interest --port 7887 > /tmp/ventisca_net_interest_all.log 2>&1; then
  grep -E "RESULT|NET TEST" /tmp/ventisca_net_interest_all.log | cut -c1-220
else
  grep -E "RESULT|!!|FAIL|SCRIPT ERROR|NET TEST" /tmp/ventisca_net_interest_all.log | cut -c1-220 | head -n 30; status=1
fi

step "net test team (H3: 4 clients, a horde around — a danger ping on every client, B's down reaches A ≤ 0.2 s after the server with the one indicator + ui_mate_down, the P0 ends on revive, the blizzard warning's countdown everywhere)"
if NET_TEST_OUT=/tmp/ventisca_net_team tests/net/run_net_test.sh --clients 4 --duration 55 --soak 75 --scenario team --port 7897 > /tmp/ventisca_net_team_all.log 2>&1; then
  grep -E "RESULT|A: B down|NET TEST" /tmp/ventisca_net_team_all.log | cut -c1-240
else
  grep -E "RESULT|A: B down|!!|FAIL|SCRIPT ERROR|NET TEST" /tmp/ventisca_net_team_all.log | cut -c1-240 | head -n 30; status=1
fi

step "net test tower (C1: 4 clients on floors 2, 2, 3 and 8 of the Edificio Meridiano — stair doors and a desk container coherent everywhere; the vertical interest filter cuts the zombie downstream ≥ 30 % for every client)"
if NET_TEST_OUT=/tmp/ventisca_net_tower tests/net/run_net_test.sh --clients 4 --duration 240 --soak 260 --scenario tower --port 7927 > /tmp/ventisca_net_tower_all.log 2>&1; then
  grep -E "RESULT|zombie downstream|NET TEST" /tmp/ventisca_net_tower_all.log /tmp/ventisca_net_tower/client_*.log | cut -c1-240
else
  grep -E "RESULT|zombie downstream|!!|FAIL|SCRIPT ERROR|NET TEST" /tmp/ventisca_net_tower_all.log /tmp/ventisca_net_tower/client_*.log | cut -c1-240 | head -n 30; status=1
fi

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

step "perf walk --cpu C0 (Carretera del Puerto → Gran Vía → Puente de Hierro → round the superblock of Las Torres, 25 m/s; streaming work p99 ≤ 2 ms, 0 hitches)"
if tests/run_perf_walk.sh --cpu --route=c0 --out=tests/perf/walk_cpu_c0.json > /tmp/ventisca_walk_c0_all.log 2>&1; then
  grep -E "streaming work|frames over|chunks  |memory  |PERF WALK" /tmp/ventisca_walk_c0_all.log
else
  grep -E "frame ms|streaming ms|chunks  |memory  |FAIL|SCRIPT ERROR|PERF WALK" /tmp/ventisca_walk_c0_all.log | head -n 20; status=1
fi

step "perf walk --cpu C1 (the urban walk: Carretera del Puerto → Gran Vía → Puente de Hierro → Las Torres → two manzanas of the ensanche, 15 m/s; streaming work p99 ≤ 2 ms, 0 hitches)"
if tests/run_perf_walk.sh --cpu --route=city --speed=15 --out=tests/perf/walk_cpu_city.json > /tmp/ventisca_walk_city_all.log 2>&1; then
  grep -E "streaming work|frames over|chunks  |memory  |PERF WALK" /tmp/ventisca_walk_city_all.log
else
  grep -E "frame ms|streaming ms|chunks  |memory  |FAIL|SCRIPT ERROR|PERF WALK" /tmp/ventisca_walk_city_all.log | head -n 20; status=1
fi

step "perf walk --cpu M6b (the La Herrería drive at 25 m/s: the Valdenieve road, the Calle Mayor, the sawmill lane and yard, the branches; own frame p99 ≤ 16 ms, 0 frames > 33 ms caused by the village / streaming)"
if tests/run_perf_walk.sh --cpu --route=m6b --out=tests/perf/walk_cpu_m6b.json > /tmp/ventisca_walk_m6b_all.log 2>&1; then
  grep -E "frame ms|streaming work|chunks  |memory  |village  |ok   frame_own|ok   frames_over_33ms|ok   village|PERF WALK" /tmp/ventisca_walk_m6b_all.log | cut -c1-260
else
  grep -E "frame ms|streaming ms|chunks  |memory  |village  |FAIL|SCRIPT ERROR|PERF WALK" /tmp/ventisca_walk_m6b_all.log | cut -c1-400 | head -n 20; status=1
fi

step "perf horde (M4: dedicated server, 4 bots, 200 zombies: median busy tick ≤ 8 ms, p99 reported)"
if tests/run_perf_horde.sh > /tmp/ventisca_horde_all.log 2>&1; then
  grep -E "tick ms|zombies |net |routes |PERF HORDE" /tmp/ventisca_horde_all.log
else
  grep -E "tick ms|FAIL|SCRIPT ERROR|PERF HORDE" /tmp/ventisca_horde_all.log | head -n 20; status=1
fi

step "perf horde city (C1: 4 bots in Las Torres, 150 walkers off the building footprints + 300 frozen statues, the city streamed on the server: median busy tick ≤ 8 ms)"
if tests/run_perf_horde.sh --city --port=7937 --out=tests/perf/horde_city.json > /tmp/ventisca_horde_city_all.log 2>&1; then
  grep -E "tick ms|zombies |net |routes |PERF HORDE" /tmp/ventisca_horde_city_all.log
else
  grep -E "tick ms|FAIL|SCRIPT ERROR|PERF HORDE" /tmp/ventisca_horde_city_all.log | head -n 20; status=1
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
  tests/run_screenshots.sh "${SHOTS_DIR:-/tmp/ventisca_shots}/g2b" g2b_sheet >> /tmp/ventisca_shots_all.log 2>&1 || status=1
  grep -E "screenshot .* ->" /tmp/ventisca_shots_all.log
fi

echo
if [ "$status" -eq 0 ]; then echo "RUN_ALL: ALL PASSED"; else echo "RUN_ALL: FAILED"; fi
exit $status
