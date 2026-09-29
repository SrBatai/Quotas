#!/usr/bin/env bash
# Launches 1 headless server + N headless clients (separate processes) on localhost.
#   SERVER_SECONDS=75 ./run_poc.sh        # long soak (checks the headless "stall after 25-55 s" report, godot#122707)
#   NCLIENTS=4 ./run_poc.sh               # bandwidth with 4 players
set -uo pipefail
cd "$(dirname "$0")"
PORT=${PORT:-7777}
NCLIENTS=${NCLIENTS:-2}
SERVER_SECONDS=${SERVER_SECONDS:-24}
CLIENT_SECONDS=${CLIENT_SECONDS:-15}
NAMES=(A B C D)
rm -f server.log client_*.log
godot --headless --path . --import > import.log 2>&1 || true

godot --headless --path . -- --server --port "$PORT" --duration "$SERVER_SECONDS" > server.log 2>&1 &
SRV=$!
sleep 1.5
PIDS=()
for ((i=0; i<NCLIENTS; i++)); do
  n=${NAMES[$i]}
  godot --headless --path . -- --client --port "$PORT" --name "$n" --duration "$CLIENT_SECONDS" > "client_$n.log" 2>&1 &
  PIDS+=($!)
  [ "$i" -eq 0 ] && sleep 2   # second client joins late (tests late-join spawn of existing players)
done
FAIL=0
for p in "${PIDS[@]}"; do wait "$p" || FAIL=1; done
wait $SRV || FAIL=1
echo "--- results ---"
grep -h "POC RESULT" client_*.log
grep -h "alive" server.log | tail -n 4
if grep -qE "SCRIPT ERROR|ERROR:|WARNING:" server.log client_*.log; then echo "!! errors/warnings found in logs"; grep -hE "SCRIPT ERROR|ERROR:|WARNING:" server.log client_*.log | sort | uniq -c; FAIL=1; fi
[ "$FAIL" -eq 0 ] && echo "POC PASSED" || echo "POC FAILED"
exit $FAIL
