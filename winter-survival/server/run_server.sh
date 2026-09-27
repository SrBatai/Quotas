#!/usr/bin/env bash
# Foreground launcher of the VENTISCA dedicated server with a graceful stop (M5, ARQ v2 §16.3–§16.4):
# SIGTERM / SIGINT (docker stop, systemctl stop, Ctrl+C) become `admin.sh save-and-quit` (final save, clients told,
# store closed), then up to 25 s for the process to exit before it is killed. Without this wrapper the headless
# Godot process dies instantly on SIGTERM and only the last autosave (≤ 60 s) survives.
#   server/run_server.sh [config]          default config: $VENTISCA_SERVER_CFG or /data/server.cfg
# Environment: VENTISCA_BIN (default: ./ventisca_server.x86_64 next to this script), VENTISCA_SERVER_CFG.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CFG="${1:-${VENTISCA_SERVER_CFG:-/data/server.cfg}}"
BIN="${VENTISCA_BIN:-$HERE/ventisca_server.x86_64}"
export VENTISCA_SERVER_CFG="$CFG"
if [ ! -f "$CFG" ] && [ -f "$HERE/server.cfg.example" ]; then
  echo "run_server: $CFG not found; creating it from server.cfg.example (edit it and restart)"
  mkdir -p "$(dirname "$CFG")"
  sed -e 's#^save_path=.*#save_path="'"$(dirname "$CFG")"'/world.db"#' \
      -e 's#^admin_token="".*#admin_token="'"$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n')"'"#' "$HERE/server.cfg.example" > "$CFG"
fi
"$BIN" --headless -- --server --config "$CFG" &
PID=$!
stop() {
  echo "run_server: stopping (save-and-quit)"
  "$HERE/admin.sh" save-and-quit || true
  for _ in $(seq 1 50); do kill -0 "$PID" 2>/dev/null || break; sleep 0.5; done
  kill -0 "$PID" 2>/dev/null && { echo "run_server: still running, killing"; kill -9 "$PID"; }
}
trap stop TERM INT
wait "$PID"
CODE=$?
# `wait` returns early (128 + signal) when a trapped signal arrives: wait for the real exit
while kill -0 "$PID" 2>/dev/null; do wait "$PID"; CODE=$?; done
# the trap ran while `wait` was interrupted: collect the server's own exit status (0 after save-and-quit)
[ "$CODE" -gt 128 ] && { wait "$PID" 2>/dev/null; CODE=$?; }
exit $CODE
