#!/usr/bin/env bash
# Multiplayer acceptance test (PLAN M1): 1 headless dedicated server + N headless clients in separate processes.
#   tests/net/run_net_test.sh [--clients 4] [--duration 60] [--scenario basic] [--soak 90] [--port 7777] [--friendly-fire off]
#   tests/net/run_net_test.sh --clients 3 --duration 60 --soak 90 --scenario shared_world   # PLAN M2 acceptance (C joins 22 s late)
#   tests/net/run_net_test.sh --quick            # server with 0 players: start → status → save-and-quit → 0 ERROR
#   tests/net/run_net_test.sh --clients 2 --duration 26 --soak 40 --scenario hitscan --net-sim 150,20,2   # PLAN M5 (lag compensation)
#                                                (--net-sim L,J,P: every client goes through tests/net/net_sim.gd, a UDP relay
#                                                 with a round trip of L ± J ms (half each way) and P % loss per direction;
#                                                 it listens on PORT + 2)
#   SERVER_BIN=export/linux/ventisca.x86_64 tests/net/run_net_test.sh [...]   # run the SERVER from an exported binary
#                                                (clients always run from the project with `godot --path .`)
#   NET_BACKEND=sqlite tests/net/run_net_test.sh [...]   # the server's store (default file: world_save.json)
# Passes when: every client prints RESULT OK (see each other move, chat relayed, request_hit_player blocked,
# client A reconnects inside the grace and keeps its position, downstream <= 5 kB/s), the server answers the
# admin `status`, survives the soak (physics ticks ~ 60 Hz with the main scene), exits cleanly on `save-and-quit`
# printing SERVER RESULT OK (project server) and no log contains SCRIPT ERROR / ERROR:.
set -uo pipefail
cd "$(dirname "$0")/../.."
CLIENTS=4; DURATION=60; SCENARIO=basic; SOAK=90; PORT=7777; FF=off; PVP=false; QUICK=0; NET_SIM=""
while [ $# -gt 0 ]; do
  case "$1" in
    --clients) CLIENTS="$2"; shift 2;;
    --duration) DURATION="$2"; shift 2;;
    --scenario) SCENARIO="$2"; shift 2;;
    --soak) SOAK="$2"; shift 2;;
    --port) PORT="$2"; shift 2;;
    --friendly-fire) FF="$2"; shift 2;;
    --pvp) PVP="$2"; shift 2;;
    --quick) QUICK=1; CLIENTS=0; SOAK=4; shift;;
    --net-sim) NET_SIM="$2"; shift 2;;
    *) echo "unknown arg $1"; exit 2;;
  esac
done
SERVER_BIN="${SERVER_BIN:-}"
ADMIN_PORT=$((PORT + 1))
OUT="${NET_TEST_OUT:-/tmp/ventisca_net}"
mkdir -p "$OUT"
rm -f "$OUT"/*.log "$OUT"/world_save.json "$OUT"/world_save.db "$OUT"/world_save.db-wal "$OUT"/world_save.db-shm
CFG="$OUT/server.cfg"
TOKEN="m1test"
NET_BACKEND="${NET_BACKEND:-file}"   # M5: NET_BACKEND=sqlite runs the server on the SQLite store (exported build: the .so next to it)
SAVE="$OUT/world_save.json"; [ "$NET_BACKEND" = "sqlite" ] && SAVE="$OUT/world_save.db"
cat > "$CFG" <<EOF
[server]
name="net test"
password=""
port=$PORT
max_players=$((CLIENTS + 1))
admin_port=$ADMIN_PORT
admin_token="$TOKEN"
debug_commands=true
[world]
seed=1337
backend="$NET_BACKEND"
save_path="$SAVE"
autosave_seconds=30
[rules]
pvp=$PVP
friendly_fire="$FF"
EOF
NOISE="ALSA lib|pulse|XDG_RUNTIME|libudev|udev"
admin() { printf '%s\n%s\n' "$TOKEN" "$1" | timeout 6 nc -q 2 -w 5 127.0.0.1 "$ADMIN_PORT" 2>/dev/null; }
SRV_PID=""
SIM_PID=""
CLIENT_PIDS=()
cleanup() {
  for p in "${CLIENT_PIDS[@]:-}"; do [ -n "$p" ] && kill "$p" 2>/dev/null; done
  [ -n "$SRV_PID" ] && kill "$SRV_PID" 2>/dev/null
  [ -n "$SIM_PID" ] && kill "$SIM_PID" 2>/dev/null
}
trap cleanup EXIT
godot --headless --path . --import > "$OUT/import.log" 2>&1 < /dev/null || true

if [ -n "$SERVER_BIN" ]; then
  [ -x "$SERVER_BIN" ] || { echo "NET TEST FAILED: SERVER_BIN '$SERVER_BIN' is not executable"; exit 1; }
  echo "== net test: server from exported binary $SERVER_BIN; $CLIENTS clients, $DURATION s, scenario=$SCENARIO, soak=$SOAK s, port=$PORT"
  T_START=$(date +%s)
  timeout $((SOAK + 120)) "$SERVER_BIN" --headless -- --server --config "$CFG" > "$OUT/server.log" 2>&1 < /dev/null &
else
  echo "== net test: $CLIENTS clients, $DURATION s, scenario=$SCENARIO, soak=$SOAK s, port=$PORT, friendly_fire=$FF pvp=$PVP"
  T_START=$(date +%s)
  timeout $((SOAK + 120)) godot --headless --path . -s tests/net/net_smoke.gd ++ --server --config "$CFG" --duration 0 > "$OUT/server.log" 2>&1 < /dev/null &
fi
SRV_PID=$!
# wait for the world (READY banner)
for i in $(seq 1 120); do grep -q "\[NET\] READY" "$OUT/server.log" 2>/dev/null && break; kill -0 "$SRV_PID" 2>/dev/null || break; sleep 0.5; done
if ! grep -q "\[NET\] READY" "$OUT/server.log"; then
  echo "NET TEST FAILED: server never became ready"; grep -v -E "$NOISE" "$OUT/server.log" | tail -n 20; exit 1
fi
STATUS=$(admin status)
echo "admin status -> ${STATUS%%$'\n'*}"
CLIENT_PORT=$PORT
if [ -n "$NET_SIM" ]; then
  IFS=',' read -r SIM_LAT SIM_JIT SIM_LOSS <<< "$NET_SIM"
  CLIENT_PORT=$((PORT + 2))
  timeout $((SOAK + 180)) godot --headless --path . -s tests/net/net_sim.gd ++ --listen "$CLIENT_PORT" --to "$PORT" --latency "${SIM_LAT:-100}" --jitter "${SIM_JIT:-0}" --loss "${SIM_LOSS:-0}" > "$OUT/net_sim.log" 2>&1 < /dev/null &
  SIM_PID=$!
  sleep 1.5
  echo "net sim: $(grep -h '\[SIM\] relay' "$OUT/net_sim.log" | head -n 1)"
fi
NAMES=(A B C D E F G H)
for ((i=0; i<CLIENTS; i++)); do
  n=${NAMES[$i]}
  LATE=0
  # shared_world: C is the late joiner (receives the chunk deltas of what A and B already did)
  [ "$SCENARIO" = "shared_world" ] && [ "$n" = "C" ] && LATE=22
  timeout $((DURATION + LATE + 90)) godot --headless --path . -s tests/net/net_smoke.gd ++ --client "--name=$n" --scenario "$SCENARIO" --port "$CLIENT_PORT" --duration "$DURATION" --clients "$CLIENTS" --late "$LATE" > "$OUT/client_$n.log" 2>&1 < /dev/null &
  CLIENT_PIDS+=($!)
  sleep 0.7
done
FAIL=0
for p in "${CLIENT_PIDS[@]:-}"; do [ -n "$p" ] && { wait "$p" || FAIL=1; }; done
# soak: keep the server alive until SOAK seconds have passed since launch, then stop it through the admin socket
while [ $(( $(date +%s) - T_START )) -lt "$SOAK" ]; do kill -0 "$SRV_PID" 2>/dev/null || break; sleep 1; done
STATUS2=$(admin status)
echo "admin status (end) -> ${STATUS2%%$'\n'*}"
QUIT=$(admin save-and-quit)
echo "admin save-and-quit -> ${QUIT%%$'\n'*}"
for i in $(seq 1 30); do kill -0 "$SRV_PID" 2>/dev/null || break; sleep 0.5; done
if kill -0 "$SRV_PID" 2>/dev/null; then echo "!! server did not exit after save-and-quit"; kill "$SRV_PID"; FAIL=1; fi
wait "$SRV_PID" 2>/dev/null
SRV_EXIT=$?
SRV_PID=""
echo "--- results ---"
grep -h "RESULT" "$OUT"/client_*.log "$OUT/server.log" 2>/dev/null
if [ "$SCENARIO" = "hitscan" ]; then
  SHOTS=$(grep -c "\[EVT\] shot .* hits=" "$OUT/server.log")
  HITS=$(grep -c "\[EVT\] shot .* hits=[1-9]" "$OUT/server.log")
  NOREW=$(grep -c "\[EVT\] shot .* norewind=1" "$OUT/server.log")
  echo "hitscan (server): $SHOTS shots, $HITS hits with lag compensation, $NOREW would have hit without it; $(grep -h 'rewind=' "$OUT/server.log" | sed -n 's/.*rewind=\([0-9]*\)ms rtt=\([0-9]*\)ms.*/rewind \1 ms rtt \2 ms/p' | tail -n 1)"
  [ -n "$SIM_PID" ] && kill "$SIM_PID" 2>/dev/null && sleep 0.3 && grep -h "\[SIM\] up=" "$OUT/net_sim.log" | tail -n 1
  # lag compensation must matter: more hits with the rewind than the same shots would have scored without it
  if [ -n "$SIM_PID" ] && [ "$HITS" -le "$NOREW" ]; then echo "!! lag compensation did not help ($HITS vs $NOREW)"; FAIL=1; fi
fi
grep -h "alive" "$OUT/server.log" | tail -n 3
grep -h "saved\|restored" "$OUT/server.log" | tail -n 2
case "$STATUS" in OK*) ;; *) echo "!! admin status did not answer OK"; FAIL=1;; esac
case "$STATUS" in *"backend=$NET_BACKEND"*) ;; *) echo "!! the server is not on the $NET_BACKEND store"; FAIL=1;; esac
case "$QUIT" in OK*) ;; *) echo "!! admin save-and-quit did not answer OK"; FAIL=1;; esac
if [ -n "$SERVER_BIN" ]; then
  [ "$SRV_EXIT" -eq 0 ] && grep -q "save-and-quit: shutting down" "$OUT/server.log" || { echo "!! exported server did not shut down cleanly (exit $SRV_EXIT)"; FAIL=1; }
else
  grep -q "SERVER RESULT OK" "$OUT/server.log" || { echo "!! server soak result missing/failed"; FAIL=1; }
fi
for ((i=0; i<CLIENTS; i++)); do grep -q "RESULT OK" "$OUT/client_${NAMES[$i]}.log" || FAIL=1; done
# W1: the server's resident memory with the players spread over the 6 km world (far: ≤ SERVER_RSS_MAX_MB, 400)
RSS_MAX=$(grep -h -o "rss_max_mb=[0-9]*" "$OUT/server.log" 2>/dev/null | tail -n 1 | cut -d= -f2)
if [ -n "$RSS_MAX" ]; then
  echo "server RSS max ${RSS_MAX} MB"
  if [ "$SCENARIO" = "far" ] && [ "$RSS_MAX" -gt "${SERVER_RSS_MAX_MB:-400}" ]; then echo "!! server RSS ${RSS_MAX} MB > ${SERVER_RSS_MAX_MB:-400} MB"; FAIL=1; fi
fi
# --net-sim: with 75+ ms per direction SceneMultiplayer may receive the first game packets of a freshly authenticated
# peer before it processes its own auth completion (an engine-side race across ENet channels): benign, filtered.
[ -n "$NET_SIM" ] && NOISE="$NOISE|SYS_COMMAND_AUTH|scene_multiplayer.cpp"
if grep -v -E "$NOISE" "$OUT"/*.log | grep -qE "SCRIPT ERROR|ERROR:"; then
  echo "!! errors found in logs"; grep -v -E "$NOISE" "$OUT"/*.log | grep -E "SCRIPT ERROR|ERROR:" | sort | uniq -c | head -n 20; FAIL=1
fi
# an id collision means a chunk was rebuilt while its old nodes were alive (WorldStreamer / WorldRegistry, M3)
if grep -q "wid collision" "$OUT"/*.log; then echo "!! WorldRegistry wid collisions"; grep -h "wid collision" "$OUT"/*.log | head -n 5; FAIL=1; fi
if grep -hE "WARNING:" "$OUT"/*.log | grep -qv -E "$NOISE"; then echo "(warnings)"; grep -hE "WARNING:" "$OUT"/*.log | grep -v -E "$NOISE" | sort | uniq -c | head -n 10; fi
[ "$QUICK" -eq 1 ] && echo "quick check: server exit=$SRV_EXIT, errors=$(grep -v -E "$NOISE" "$OUT/server.log" | grep -cE 'SCRIPT ERROR|ERROR:')"
[ "$FAIL" -eq 0 ] && echo "NET TEST PASSED" || echo "NET TEST FAILED"
exit $FAIL
