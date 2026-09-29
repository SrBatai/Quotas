#!/usr/bin/env bash
# Screenshot of a networked session: 1 headless dedicated server + N idle headless clients + one rendering client
# (preset `multi`) that joins and captures the remote survivors (distinct jackets, skeletal animation).
#   [RENDER=forward] tests/run_multi_shot.sh [out.png] [--clients 2] [--port 7797] [--wait 8]
set -uo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-/tmp/ventisca_shots/multi.png}"; shift || true
CLIENTS=2; PORT=7797; WAIT=8
while [ $# -gt 0 ]; do case "$1" in --clients) CLIENTS="$2"; shift 2;; --port) PORT="$2"; shift 2;; --wait) WAIT="$2"; shift 2;; *) shift;; esac; done
mkdir -p "$(dirname "$OUT")"
DIR="${NET_TEST_OUT:-/tmp/ventisca_multi_shot}"; mkdir -p "$DIR"; rm -f "$DIR"/*.log "$DIR/world_save.json"   # fresh world (a restored clock could be night: wolves)
ADMIN_PORT=$((PORT + 1)); TOKEN=shot
cat > "$DIR/server.cfg" <<CFG
[server]
name="shot"
password=""
port=$PORT
max_players=$((CLIENTS + 2))
admin_port=$ADMIN_PORT
admin_token="$TOKEN"
debug_commands=true
[world]
seed=1337
save_path="$DIR/world_save.json"
CFG
PIDS=()
cleanup() { for p in "${PIDS[@]:-}"; do [ -n "$p" ] && kill "$p" 2>/dev/null; done; }
trap cleanup EXIT
timeout 400 godot --headless --path . -s tests/net/net_smoke.gd ++ --server --config "$DIR/server.cfg" --duration 0 > "$DIR/server.log" 2>&1 < /dev/null &
PIDS+=($!)
for i in $(seq 1 120); do grep -q "\[NET\] READY" "$DIR/server.log" 2>/dev/null && break; sleep 0.5; done
NAMES=(Bea Carlos Dana Eva)
for ((i=0; i<CLIENTS; i++)); do
  # the rendering client is slow (software GL): the idle players stay long enough for it to join and settle
  timeout 330 godot --headless --path . -s tests/net/net_smoke.gd ++ --client "--name=${NAMES[$i]}" --scenario idle --port "$PORT" --duration 240 --clients "$CLIENTS" > "$DIR/client_$i.log" 2>&1 < /dev/null &
  PIDS+=($!)
  sleep 0.7
done
sleep 6
RENDER="${RENDER:-compat}"
if [ "$RENDER" = "forward" ]; then
  export VK_ICD_FILENAMES="${VK_ICD_FILENAMES:-/usr/share/vulkan/icd.d/lvp_icd.json}"
  GODOT_ARGS=(--rendering-driver vulkan --rendering-method forward_plus)
else
  export LIBGL_ALWAYS_SOFTWARE=1
  GODOT_ARGS=(--rendering-driver opengl3 --rendering-method gl_compatibility)
fi
xvfb-run -a -s "-screen 0 1280x720x24" godot --path . "${GODOT_ARGS[@]}" --audio-driver Dummy --resolution 1280x720 \
  -s tests/screenshot.gd ++ --preset=multi --out="$OUT" "--port=$PORT" "--wait=$WAIT" > "$DIR/shot_client.log" 2>&1
grep -v -E "ALSA lib|pulse|XDG_RUNTIME|libudev|udev" "$DIR/shot_client.log" | grep -E "multi:|screenshot|SCRIPT ERROR|ERROR"
printf '%s\nsave-and-quit\n' "$TOKEN" | timeout 6 nc -q 2 -w 5 127.0.0.1 "$ADMIN_PORT" > /dev/null 2>&1 || true
sleep 1
