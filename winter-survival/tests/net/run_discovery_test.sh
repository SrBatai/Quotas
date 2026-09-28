#!/usr/bin/env bash
# PLAN v3.8.1 H2 acceptance, scenario `discovery`: zone discovery is server-authoritative, shared by the group
# (`shared_discovery`, default on) and survives a server restart.
#   tests/net/run_discovery_test.sh [--backend sqlite|file] [--port 7857]
#   1. dedicated server #1 (project) on a fresh store: admin `dbinfo` says schema 3 (the `discoveries` table, H2);
#   2. clients A and B (tests/net/net_steps_h2.gd, phase 1): A teleports to the Granja del Molino and discovers it
#      (full title; server log "zone discovered: granja_del_molino by A"); B gets the feed line «A descubrió: Granja
#      del Molino», goes there later and sees the compact title (no new discovery);
#   3. admin `save-and-quit` (exit 0);
#   4. dedicated server #2 on the same store: "discovery: N zones restored";
#   5. client C (a new player, phase 2): its sync already knows the farm, the title there is compact, no feed line;
#      server #2 records no new discovery of the farm;
#   6. `save-and-quit` again; no SCRIPT ERROR / ERROR in any log.
# Prints DISCOVERY TEST PASSED / FAILED (exit 0 / 1). NET_TEST_OUT sets the work directory (default /tmp/ventisca_discovery).
set -uo pipefail
cd "$(dirname "$0")/../.."
BACKEND=sqlite; PORT=7857
while [ $# -gt 0 ]; do
  case "$1" in
    --backend) BACKEND="$2"; shift 2;;
    --port) PORT="$2"; shift 2;;
    *) echo "unknown arg $1"; exit 2;;
  esac
done
ADMIN_PORT=$((PORT + 1))
OUT="${NET_TEST_OUT:-/tmp/ventisca_discovery}"
mkdir -p "$OUT"
rm -rf "$OUT"/*.log "$OUT"/world.* "$OUT"/backups
EXT=db; [ "$BACKEND" = "file" ] && EXT=json
CFG="$OUT/server.cfg"
TOKEN="h2discovery"
cat > "$CFG" <<EOF
[server]
name="discovery test"
password=""
port=$PORT
max_players=3
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
shared_discovery=true
EOF
NOISE="ALSA lib|pulse|XDG_RUNTIME|libudev|udev"
admin() { printf '%s\n%s\n' "$TOKEN" "$1" | timeout 6 nc -q 2 -w 5 127.0.0.1 "$ADMIN_PORT" 2>/dev/null; }
SRV_PID=""
CLI_PIDS=()
cleanup() { for p in "${CLI_PIDS[@]:-}"; do [ -n "$p" ] && kill "$p" 2>/dev/null; done; [ -n "$SRV_PID" ] && kill "$SRV_PID" 2>/dev/null; }
trap cleanup EXIT
FAIL=0
godot --headless --path . --import > "$OUT/import.log" 2>&1 < /dev/null || true

start_server() {   # $1 = log name
  timeout 400 godot --headless --path . -s tests/net/net_smoke.gd ++ --server --config "$CFG" --duration 0 > "$OUT/$1.log" 2>&1 < /dev/null &
  SRV_PID=$!
  for i in $(seq 1 120); do grep -q "\[NET\] READY" "$OUT/$1.log" 2>/dev/null && return 0; kill -0 "$SRV_PID" 2>/dev/null || break; sleep 0.5; done
  grep -q "Couldn't create an ENet host" "$OUT/$1.log" && echo "!! UDP port $PORT is busy (another test on it?): use --port"
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
}
run_clients() {    # $1 = phase, $2 = duration, $3… = names (0.7 s apart)
  local phase=$1 dur=$2; shift 2
  CLI_PIDS=()
  local names=("$@")
  for n in "${names[@]}"; do
    timeout $(( dur + 90 )) godot --headless --path . -s tests/net/net_smoke.gd ++ --client "--name=$n" --scenario discovery --phase "$phase" --port "$PORT" --duration "$dur" --clients "${#names[@]}" > "$OUT/client_$n.log" 2>&1 < /dev/null &
    CLI_PIDS+=($!)
    sleep 0.7
  done
  local i=0
  for p in "${CLI_PIDS[@]}"; do
    wait "$p"; local code=$?
    local n=${names[$i]}
    grep -h "RESULT" "$OUT/client_$n.log"
    [ "$code" -eq 0 ] && grep -q "RESULT OK" "$OUT/client_$n.log" || { echo "!! client $n (phase $phase) failed (exit $code)"; FAIL=1; }
    i=$((i + 1))
  done
  CLI_PIDS=()
}
check_schema() {   # $1 = label
  local info; info=$(admin dbinfo)
  echo "admin dbinfo ($1) -> ${info%%$'\n'*}"
  echo "$info" | grep -q "backend=$BACKEND" || { echo "!! $1: backend is not $BACKEND"; FAIL=1; }
  echo "$info" | grep -q "schema=3" || { echo "!! $1: schema is not 3 (discoveries)"; FAIL=1; }
}

echo "== discovery test: backend=$BACKEND port=$PORT store=$OUT/world.$EXT"
start_server server1 || exit 1
check_schema "fresh store"
run_clients 1 36 A B
grep -h "\[EVT\] zone discovered" "$OUT/server1.log" | head -n 6
grep -q "zone discovered: granja_del_molino by A" "$OUT/server1.log" || { echo "!! server 1 did not record A's discovery of the farm"; FAIL=1; }
if grep -q "zone discovered: granja_del_molino by B" "$OUT/server1.log"; then echo "!! B discovered the farm again"; FAIL=1; fi
stop_server server1
[ -f "$OUT/world.$EXT" ] && echo "store: $(ls -la "$OUT/world.$EXT" | awk '{print $5}') bytes" || { echo "!! no store file"; FAIL=1; }
start_server server2 || exit 1
grep -h "\[EVT\] discovery:" "$OUT/server2.log" | head -n 2
grep -qE "\[EVT\] discovery: [1-9][0-9]* zones restored" "$OUT/server2.log" || { echo "!! server 2 restored no discovery"; FAIL=1; }
check_schema "after restart"
run_clients 2 28 C
if grep -q "zone discovered: granja_del_molino" "$OUT/server2.log"; then echo "!! the farm was discovered again after the restart"; FAIL=1; fi
stop_server server2
if grep -v -E "$NOISE" "$OUT"/*.log | grep -qE "SCRIPT ERROR|ERROR:"; then
  echo "!! errors found in logs"; grep -v -E "$NOISE" "$OUT"/*.log | grep -E "SCRIPT ERROR|ERROR:" | sort | uniq -c | head -n 20; FAIL=1
fi
[ "$FAIL" -eq 0 ] && echo "DISCOVERY TEST PASSED" || echo "DISCOVERY TEST FAILED"
exit $FAIL
