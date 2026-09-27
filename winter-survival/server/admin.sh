#!/usr/bin/env bash
# Localhost admin client for the VENTISCA dedicated server (ARQ v2 §16.5; M5 command set: AdminCommands).
#   server/admin.sh status | players | stats | dbinfo | save | save-and-quit | quit | backup
#   server/admin.sh "say <text>" | "kick <player> [reason]" | "ban <player|token_hash|ip> [reason]" | "unban <token_hash|ip>" | bans
#   server/admin.sh "rule pvp on" | rules | "pvp on" | "ff reduced" | "time 8" | "day 3" | "weather blizzard 120"
#   server/admin.sh "give <player> <item> [n]" | "tp <player> <x> <z>"
# Environment: VENTISCA_SERVER_CFG (the server.cfg: admin_port / admin_token are read from it),
#              VENTISCA_ADMIN_PORT, VENTISCA_ADMIN_TOKEN (override the file).
# systemd ExecStop / Docker stop (server/run_server.sh) call `admin.sh save-and-quit`: SIGTERM would kill the headless
# process instantly, the socket is the clean shutdown path. Exit code 0 when the reply starts with OK.
set -uo pipefail
CFG="${VENTISCA_SERVER_CFG:-$HOME/.local/share/godot/app_userdata/Ventisca/server.cfg}"
cfg_value() { [ -f "$CFG" ] && sed -n "s/^$1=\"\{0,1\}\([^\";]*\)\"\{0,1\}.*/\1/p" "$CFG" | head -n 1 | tr -d ' '; }
PORT="${VENTISCA_ADMIN_PORT:-$(cfg_value admin_port)}"
PORT="${PORT:-7778}"
TOKEN="${VENTISCA_ADMIN_TOKEN:-$(cfg_value admin_token)}"
CMD="${*:-status}"
if command -v nc > /dev/null; then
  REPLY=$(printf '%s\n%s\n' "$TOKEN" "$CMD" | nc -q 2 -w 5 127.0.0.1 "$PORT" 2>/dev/null || printf '%s\n%s\n' "$TOKEN" "$CMD" | nc -w 5 127.0.0.1 "$PORT" 2>/dev/null)
else
  exec 3<>"/dev/tcp/127.0.0.1/$PORT" 2>/dev/null || { echo "ERR cannot connect to 127.0.0.1:$PORT"; exit 1; }
  printf '%s\n%s\n' "$TOKEN" "$CMD" >&3
  REPLY=$(timeout 5 cat <&3)
  exec 3>&-
fi
REPLY="${REPLY%$'\n'END}"
REPLY="${REPLY%END}"
[ -z "$REPLY" ] && { echo "ERR no answer from 127.0.0.1:$PORT"; exit 1; }
echo "$REPLY"
case "$REPLY" in OK*) exit 0;; *) exit 1;; esac
