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
rm -f "$OUT"/*.log
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
admin() { printf '%s\n%s\n' "$TOKEN" "$1" | timeout 6 nc -q 2 -w 5 127.0.0.1 "$ADMIN_PORT" 2>/dev/null || printf '%s\n%s\n' "$TOKEN" "$1" | timeout 6 nc -w 5 127.0.0.1 "$ADMIN_PORT" 2>/dev/null; }
filter() { grep -v -E "ALSA lib|pulse|XDG_RUNTIME|libudev|udev"; }
godot --headless --path . --import > "$OUT/import.log" 2>&1 || true

echo "== net test: $CLIENTS clients, $DURATION s, scenario=$SCENARIO, soak=$SOAK s, port=$PORT, friendly_fire=$FF pvp=$PVP"
godot --headless --path . -s tests/net/net_smoke.gd ++ --server --config "$CFG" --duration 0 2>&1 | filter > "$OUT/server.log" &
SRV_PIPE=$!
# wait for the world (READY banner)
for i in $(seq 1 120); do grep -q "\[NET\] READY" "$OUT/server.log" 2>/dev/null && break; sleep 0.5; done
if ! grep -q "\[NET\] READY" "$OUT/server.log"; then echo "NET TEST FAILED: server never became ready"; tail -n 20 "$OUT/server.log"; exit 1; fi
STATUS=$(admin status)
echo "admin status -> ${STATUS%%$'\n'*}"
NAMES=(A B C D E F G H)
PIDS=()
for ((i=0; i<CLIENTS; i++)); do
  n=${NAMES[$i]}
  godot --headless --path . -s tests/net/net_smoke.gd ++ --client "--name=$n" --scenario "$SCENARIO" --port "$PORT" --duration "$DURATION" --clients "$CLIENTS" 2>&1 | filter > "$OUT/client_$n.log" &
  PIDS+=($!)
  sleep 0.7
done
FAIL=0
for p in "${PIDS[@]}"; do wait "$p" || FAIL=1; done
# soak: keep the server alive until SOAK seconds have passed since launch, then stop it through the admin socket
SRV_START=$(stat -c %Y "$CFG")
while [ $(( $(date +%s) - SRV_START )) -lt "$SOAK" ]; do sleep 1; done
STATUS2=$(admin status)
echo "admin status (end) -> ${STATUS2%%$'\n'*}"
QUIT=$(admin save-and-quit)
echo "admin save-and-quit -> ${QUIT%%$'\n'*}"
for i in $(seq 1 30); do kill -0 "$SRV_PIPE" 2>/dev/null || break; sleep 0.5; done
if kill -0 "$SRV_PIPE" 2>/dev/null; then echo "server did not exit after save-and-quit"; pkill -f "net_smoke.gd ++ --server" ; FAIL=1; fi
wait "$SRV_PIPE" 2>/dev/null
echo "--- results ---"
grep -h "RESULT" "$OUT"/client_*.log "$OUT/server.log"
grep -h "alive" "$OUT/server.log" | tail -n 3
grep -h "saved" "$OUT/server.log" | tail -n 1
case "$STATUS" in OK*) ;; *) echo "!! admin status did not answer OK"; FAIL=1;; esac
case "$QUIT" in OK*) ;; *) echo "!! admin save-and-quit did not answer OK"; FAIL=1;; esac
grep -q "SERVER RESULT OK" "$OUT/server.log" || { echo "!! server soak result missing/failed"; FAIL=1; }
for ((i=0; i<CLIENTS; i++)); do grep -q "RESULT OK" "$OUT/client_${NAMES[$i]}.log" || FAIL=1; done
if grep -qE "SCRIPT ERROR|ERROR:" "$OUT"/*.log; then echo "!! errors found in logs"; grep -hE "SCRIPT ERROR|ERROR:" "$OUT"/*.log | sort | uniq -c | head -n 20; FAIL=1; fi
if grep -qE "WARNING:" "$OUT"/*.log; then echo "(warnings)"; grep -hE "WARNING:" "$OUT"/*.log | sort | uniq -c | head -n 10; fi
[ "$FAIL" -eq 0 ] && echo "NET TEST PASSED" || echo "NET TEST FAILED"
exit $FAIL
