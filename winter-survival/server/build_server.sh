#!/usr/bin/env bash
# Exports the dedicated server (preset "Dedicated Server": Linux x86_64, strip visuals, .pck embedded) into
# export/server/ together with the godot-sqlite library and the operation scripts, ready for server/Dockerfile,
# ventisca.service or a plain copy (ARQ v2 §16.1). Needs the Godot 4.7.2 export templates (linux_release.x86_64).
#   server/build_server.sh [out_dir]      default export/server
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-export/server}"
tools/fetch_godot_sqlite.sh
mkdir -p "$OUT"
godot --headless --path . --import > /dev/null 2>&1 || true
godot --headless --path . --export-release "Dedicated Server" "$OUT/ventisca_server.x86_64"
cp server/run_server.sh server/admin.sh server/server.cfg.example "$OUT/"
[ -f "$OUT/libgdsqlite.linux.template_release.x86_64.so" ] || cp addons/godot-sqlite/bin/libgdsqlite.linux.template_release.x86_64.so "$OUT/"
ls -la "$OUT"
