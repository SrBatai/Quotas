#!/usr/bin/env bash
# Localhost admin client for the VENTISCA dedicated server (ARQ v2 §16.5, M1 subset).
#   server/admin.sh status | players | save | save-and-quit | quit | "say <text>" | "time <hour>" | "day <n>" | "rule pvp true"
# Environment: VENTISCA_ADMIN_PORT (default 7778), VENTISCA_ADMIN_TOKEN (default: read from user://server.cfg if present).
# systemd ExecStop should call: server/admin.sh save-and-quit   (SIGTERM kills the headless process instantly).
set -uo pipefail
PORT="${VENTISCA_ADMIN_PORT:-7778}"
TOKEN="${VENTISCA_ADMIN_TOKEN:-}"
CFG="${VENTISCA_SERVER_CFG:-$HOME/.local/share/godot/app_userdata/Ventisca/server.cfg}"
if [ -z "$TOKEN" ] && [ -f "$CFG" ]; then
  TOKEN=$(sed -n 's/^admin_token="\(.*\)"/\1/p' "$CFG" | head -n 1)
fi
CMD="${*:-status}"
if command -v nc > /dev/null; then
  printf '%s\n%s\n' "$TOKEN" "$CMD" | nc -q 2 -w 5 127.0.0.1 "$PORT" 2>/dev/null || printf '%s\n%s\n' "$TOKEN" "$CMD" | nc -w 5 127.0.0.1 "$PORT"
else
  exec 3<>"/dev/tcp/127.0.0.1/$PORT" || { echo "ERR cannot connect to 127.0.0.1:$PORT"; exit 1; }
  printf '%s\n%s\n' "$TOKEN" "$CMD" >&3
  timeout 5 cat <&3
  exec 3>&-
fi
