#!/usr/bin/env bash
# PLAN M5 + v3.8.4 acceptance, scenario `restart`: the world survives a server restart.
#   tests/net/run_restart_test.sh [--backend sqlite|file] [--port 7827]
#   1. dedicated server #1 (project) with `[world] backend` on a fresh store; admin `dbinfo` must say schema 3 (H2) and
#      world_version 2 (the 96² world of W1);
#   2. client A phase 1 (tests/net/net_steps_m5.gd): fells a pine, places a campfire, loots the campsite container
#      of camp_1, loads and fires a pistol, goes to the SE quadrant (x, z > 3000) and places a second campfire there,
#      then disconnects;
#   3. admin `save-and-quit`: the server must exit 0 ("save-and-quit: shutting down") — the graceful shutdown path;
#   4. dedicated server #2 on the same store: `dbinfo` again (players 1, chunks ≥ 3, world_version 2);
#   5. client A phase 2: back in the SE quadrant with the same inventory (pistol with 10 rounds in the magazine), both
#      campfires, the felled pine, the looted container still empty (no re-roll);
#   6. `save-and-quit` again; no SCRIPT ERROR / ERROR in any log.
# Prints RESTART TEST PASSED / FAILED (exit 0 / 1). NET_TEST_OUT sets the work directory (default /tmp/ventisca_restart).
set -uo pipefail
cd "$(dirname "$0")/../.."
BACKEND=sqlite; PORT=7827
while [ $# -gt 0 ]; do
  case "$1" in
    --backend) BACKEND="$2"; shift 2;;
    --port) PORT="$2"; shift 2;;
    *) echo "unknown arg $1"; exit 2;;
  esac
done
ADMIN_PORT=$((PORT + 1))
OUT="${NET_TEST_OUT:-/tmp/ventisca_restart}"
mkdir -p "$OUT"
rm -rf "$OUT"/*.log "$OUT"/world.* "$OUT"/backups
EXT=db; [ "$BACKEND" = "file" ] && EXT=json
CFG="$OUT/server.cfg"
TOKEN="m5restart"
cat > "$CFG" <<EOF
[server]
name="restart test"
password=""
port=$PORT
max_players=2
admin_port=$ADMIN_PORT
admin_token="$TOKEN"
debug_commands=true
[world]
seed=1337
backend="$BACKEND"
save_path="$OUT/world.$EXT"
autosave_seconds=20
[rules]
pvp=false
friendly_fire="off"
EOF
NOISE="ALSA lib|pulse|XDG_RUNTIME|libudev|udev"
admin() { printf '%s\n%s\n' "$TOKEN" "$1" | timeout 6 nc -q 2 -w 5 127.0.0.1 "$ADMIN_PORT" 2>/dev/null; }
SRV_PID=""
CLI_PID=""
cleanup() { [ -n "$CLI_PID" ] && kill "$CLI_PID" 2>/dev/null; [ -n "$SRV_PID" ] && kill "$SRV_PID" 2>/dev/null; }
trap cleanup EXIT
FAIL=0
godot --headless --path . --import > "$OUT/import.log" 2>&1 < /dev/null || true
rm -f "$HOME/.local/share/godot/app_userdata/Ventisca/m5_restart_phase1.json"

start_server() {   # $1 = log name
  timeout 400 godot --headless --path . -s tests/net/net_smoke.gd ++ --server --config "$CFG" --duration 0 > "$OUT/$1.log" 2>&1 < /dev/null &
  SRV_PID=$!
  for i in $(seq 1 120); do grep -q "\[NET\] READY" "$OUT/$1.log" 2>/dev/null && return 0; kill -0 "$SRV_PID" 2>/dev/null || break; sleep 0.5; done
  echo "!! server ($1) never became ready"; grep -v -E "$NOISE" "$OUT/$1.log" | tail -n 20; return 1
}
stop_server() {    # $1 = log name
  local q; q=$(admin save-and-quit)
  echo "admin save-and-quit -> ${q%%$'\n'*}"
  for i in $(seq 1 30); do kill -0 "$SRV_PID" 2>/dev/null || break; sleep 0.5; done
  if kill -0 "$SRV_PID" 2>/dev/null; then echo "!! server did not exit after save-and-quit"; kill "$SRV_PID"; FAIL=1; fi
  wait "$SRV_PID" 2>/dev/null; local code=$?
  SRV_PID=""
  grep -q "save-and-quit: shutting down" "$OUT/$1.log" && [ "$code" -eq 0 ] || { echo "!! $1 did not shut down cleanly (exit $code)"; FAIL=1; }
  echo "$1: $(grep -h '\[EVT\] saved' "$OUT/$1.log" | tail -n 1)"
}
run_client() {     # $1 = phase, $2 = duration
  timeout $(( $2 + 90 )) godot --headless --path . -s tests/net/net_smoke.gd ++ --client "--name=A" --scenario restart --phase "$1" --port "$PORT" --duration "$2" --clients 1 > "$OUT/client_phase$1.log" 2>&1 < /dev/null &
  CLI_PID=$!
  wait "$CLI_PID"; local code=$?
  CLI_PID=""
  grep -h "RESULT\|PHASE" "$OUT/client_phase$1.log"
  [ "$code" -eq 0 ] && grep -q "RESULT OK" "$OUT/client_phase$1.log" || { echo "!! client phase $1 failed (exit $code)"; FAIL=1; }
}
check_db() {       # $1 = label, $2 = minimum players, $3 = minimum chunks
  local info; info=$(admin dbinfo)
  echo "admin dbinfo ($1) -> ${info%%$'\n'*}"
  echo "$info" | grep -q "backend=$BACKEND" || { echo "!! $1: backend is not $BACKEND"; FAIL=1; }
  echo "$info" | grep -q "schema=3" || { echo "!! $1: schema is not 3"; FAIL=1; }   # H2: 3 (discoveries)
  echo "$info" | grep -q "world_version=2" || { echo "!! $1: world_meta.world_version is not 2"; FAIL=1; }
  local players chunks
  players=$(echo "$info" | sed -n 's/.* players=\([0-9]*\).*/\1/p'); chunks=$(echo "$info" | sed -n 's/.* chunks=\([0-9]*\).*/\1/p')
  [ "${players:-0}" -ge "$2" ] && [ "${chunks:-0}" -ge "$3" ] || { echo "!! $1: players=$players chunks=$chunks (want >= $2 / $3)"; FAIL=1; }
}

echo "== restart test: backend=$BACKEND port=$PORT store=$OUT/world.$EXT"
start_server server1 || exit 1
check_db "fresh store" 0 0
run_client 1 34
admin save > /dev/null
check_db "after phase 1" 1 3
stop_server server1
[ -f "$OUT/world.$EXT" ] && echo "store: $(ls -la "$OUT/world.$EXT" | awk '{print $5}') bytes" || { echo "!! no store file"; FAIL=1; }
start_server server2 || exit 1
grep -h "\[EVT\] persistence\|restored" "$OUT/server2.log" | head -n 4
check_db "after restart" 1 3
run_client 2 16
stop_server server2
if grep -v -E "$NOISE" "$OUT"/*.log | grep -qE "SCRIPT ERROR|ERROR:"; then
  echo "!! errors found in logs"; grep -v -E "$NOISE" "$OUT"/*.log | grep -E "SCRIPT ERROR|ERROR:" | sort | uniq -c | head -n 20; FAIL=1
fi
if grep -q "wid collision" "$OUT"/*.log; then echo "!! WorldRegistry wid collisions"; FAIL=1; fi
[ "$FAIL" -eq 0 ] && echo "RESTART TEST PASSED" || echo "RESTART TEST FAILED"
exit $FAIL
