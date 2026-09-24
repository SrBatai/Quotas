#!/usr/bin/env bash
# Multiplayer acceptance test (PLAN M1): 1 headless dedicated server + N headless clients in separate processes.
#   tests/net/run_net_test.sh [--clients 4] [--duration 60] [--scenario basic] [--soak 90] [--port 7777] [--friendly-fire off]
# Passes when: every client prints RESULT OK (see each other move, chat relayed, request_hit_player blocked,
# client A reconnects inside the grace and keeps its position, downstream <= 5 kB/s), the server answers the
# admin `status`, survives the soak (physics ticks ~ 60 Hz with the main scene), exits cleanly on `save-and-quit`
# printing SERVER RESULT OK, and no log contains SCRIPT ERROR / ERROR:.
set -uo pipefail
cd "$(dirname "$0")/../.."
CLIENTS=4; DURATION=60; SCENARIO=basic; SOAK=90; PORT=7777; FF=off; PVP=false
while [ $# -gt 0 ]; do
  case "$1" in
    --clients) CLIENTS="$2"; shift 2;;
    --duration) DURATION="$2"; shift 2;;
    --scenario) SCENARIO="$2"; shift 2;;
    --soak) SOAK="$2"; shift 2;;
    --port) PORT="$2"; shift 2;;
    --friendly-fire) FF="$2"; shift 2;;
    --pvp) PVP="$2"; shift 2;;
    *) echo "unknown arg $1"; exit 2;;
  esac
done
ADMIN_PORT=$((PORT + 1))
OUT="${NET_TEST_OUT:-/tmp/ventisca_net}"
mkdir -p "$OUT"
rm -f "$OUT"/*.log "$OUT"/world_save.json
CFG="$OUT/server.cfg"
TOKEN="m1test"
cat > "$CFG" <<EOF
[server]
name="net test"
password=""
port=$PORT
max_players=$((CLIENTS + 1))
admin_port=$ADMIN_PORT
admin_token="$TOKEN"
[world]
seed=1337
save_path="$OUT/world_save.json"
autosave_seconds=30
[rules]
pvp=$PVP
friendly_fire="$FF"
EOF
NOISE="ALSA lib|pulse|XDG_RUNTIME|libudev|udev"
admin() { printf '%s\n%s\n' "$TOKEN" "$1" | timeout 6 nc -q 2 -w 5 127.0.0.1 "$ADMIN_PORT" 2>/dev/null; }
SRV_PID=""
CLIENT_PIDS=()
cleanup() {
  for p in "${CLIENT_PIDS[@]:-}"; do [ -n "$p" ] && kill "$p" 2>/dev/null; done
  [ -n "$SRV_PID" ] && kill "$SRV_PID" 2>/dev/null
}
trap cleanup EXIT
godot --headless --path . --import > "$OUT/import.log" 2>&1 < /dev/null || true

echo "== net test: $CLIENTS clients, $DURATION s, scenario=$SCENARIO, soak=$SOAK s, port=$PORT, friendly_fire=$FF pvp=$PVP"
T_START=$(date +%s)
timeout $((SOAK + 120)) godot --headless --path . -s tests/net/net_smoke.gd ++ --server --config "$CFG" --duration 0 > "$OUT/server.log" 2>&1 < /dev/null &
SRV_PID=$!
# wait for the world (READY banner)
for i in $(seq 1 120); do grep -q "\[NET\] READY" "$OUT/server.log" 2>/dev/null && break; kill -0 "$SRV_PID" 2>/dev/null || break; sleep 0.5; done
if ! grep -q "\[NET\] READY" "$OUT/server.log"; then
  echo "NET TEST FAILED: server never became ready"; grep -v -E "$NOISE" "$OUT/server.log" | tail -n 20; exit 1
fi
STATUS=$(admin status)
echo "admin status -> ${STATUS%%$'\n'*}"
NAMES=(A B C D E F G H)
for ((i=0; i<CLIENTS; i++)); do
  n=${NAMES[$i]}
  timeout $((DURATION + 90)) godot --headless --path . -s tests/net/net_smoke.gd ++ --client "--name=$n" --scenario "$SCENARIO" --port "$PORT" --duration "$DURATION" --clients "$CLIENTS" > "$OUT/client_$n.log" 2>&1 < /dev/null &
  CLIENT_PIDS+=($!)
  sleep 0.7
done
FAIL=0
for p in "${CLIENT_PIDS[@]}"; do wait "$p" || FAIL=1; done
# soak: keep the server alive until SOAK seconds have passed since launch, then stop it through the admin socket
while [ $(( $(date +%s) - T_START )) -lt "$SOAK" ]; do kill -0 "$SRV_PID" 2>/dev/null || break; sleep 1; done
STATUS2=$(admin status)
echo "admin status (end) -> ${STATUS2%%$'\n'*}"
QUIT=$(admin save-and-quit)
echo "admin save-and-quit -> ${QUIT%%$'\n'*}"
for i in $(seq 1 30); do kill -0 "$SRV_PID" 2>/dev/null || break; sleep 0.5; done
if kill -0 "$SRV_PID" 2>/dev/null; then echo "!! server did not exit after save-and-quit"; kill "$SRV_PID"; FAIL=1; fi
wait "$SRV_PID" 2>/dev/null
SRV_PID=""
echo "--- results ---"
grep -h "RESULT" "$OUT"/client_*.log "$OUT/server.log"
grep -h "alive" "$OUT/server.log" | tail -n 3
grep -h "saved" "$OUT/server.log" | tail -n 1
case "$STATUS" in OK*) ;; *) echo "!! admin status did not answer OK"; FAIL=1;; esac
case "$QUIT" in OK*) ;; *) echo "!! admin save-and-quit did not answer OK"; FAIL=1;; esac
grep -q "SERVER RESULT OK" "$OUT/server.log" || { echo "!! server soak result missing/failed"; FAIL=1; }
for ((i=0; i<CLIENTS; i++)); do grep -q "RESULT OK" "$OUT/client_${NAMES[$i]}.log" || FAIL=1; done
if grep -v -E "$NOISE" "$OUT"/*.log | grep -qE "SCRIPT ERROR|ERROR:"; then
  echo "!! errors found in logs"; grep -v -E "$NOISE" "$OUT"/*.log | grep -E "SCRIPT ERROR|ERROR:" | sort | uniq -c | head -n 20; FAIL=1
fi
if grep -hE "WARNING:" "$OUT"/*.log | grep -qv -E "$NOISE"; then echo "(warnings)"; grep -hE "WARNING:" "$OUT"/*.log | grep -v -E "$NOISE" | sort | uniq -c | head -n 10; fi
[ "$FAIL" -eq 0 ] && echo "NET TEST PASSED" || echo "NET TEST FAILED"
exit $FAIL
