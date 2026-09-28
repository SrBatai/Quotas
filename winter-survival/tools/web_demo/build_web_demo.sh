#!/usr/bin/env bash
# Builds the browser demo published as a claude.ai artifact.
# Output: export/web_demo/ (git-ignored) with ventisca.html + index.js + worklets + base64 text payloads
# (artifact hosting serves .js/.txt but not .pck/.gz, and caps binaries at 15 MB).
# Needs Godot 4.7.2 with the web_nothreads export templates installed.
set -euo pipefail
cd "$(dirname "$0")/../.."          # winter-survival/
OUT="export/web_demo"
TMP="export/web_export"
rm -rf "$OUT" "$TMP" && mkdir -p "$OUT" "$TMP" && touch export/.gdignore
created_presets=0
if [ ! -f export_presets.cfg ]; then cp tools/web_demo/export_presets.cfg export_presets.cfg; created_presets=1; fi
godot --headless --path . --import > /dev/null 2>&1 || true
godot --headless --path . --export-release "Web" "$TMP/index.html"
[ "$created_presets" = 1 ] && rm -f export_presets.cfg
gzip -9 -c "$TMP/index.wasm" | base64 -w0 > "$OUT/index.wasm.gz.txt"
# the game data outgrew one artifact file (16 MB cap): base64 cut into parts at a multiple of 4 characters, so each
# part decodes on its own; the page fetches index.pck.0.txt … index.pck.<n-1>.txt and joins the bytes
PART_CHARS=14000000
base64 -w0 "$TMP/index.pck" > "$TMP/index.pck.b64"
split -b "$PART_CHARS" -d -a 1 "$TMP/index.pck.b64" "$OUT/index.pck."
PCK_PARTS=0
for f in "$OUT"/index.pck.[0-9]; do mv "$f" "$f.txt"; PCK_PARTS=$((PCK_PARTS + 1)); done
PCK_TXT_BYTES=$(stat -c %s "$TMP/index.pck.b64")
cp "$TMP/index.js" "$TMP/index.audio.worklet.js" "$TMP/index.audio.position.worklet.js" "$OUT/"
cp tools/web_demo/ventisca.html "$OUT/"
# Keep the sizes baked into the page in sync with this build.
WASM_TXT_BYTES=$(stat -c %s "$OUT/index.wasm.gz.txt")
PCK_BYTES=$(stat -c %s "$TMP/index.pck"); WASM_BYTES=$(stat -c %s "$TMP/index.wasm")
sed -i -E "s/const WASM_TXT_BYTES = [0-9]+;/const WASM_TXT_BYTES = ${WASM_TXT_BYTES};/; s/const PCK_PARTS = [0-9]+;/const PCK_PARTS = ${PCK_PARTS};/; s/const PCK_TXT_BYTES = [0-9]+;/const PCK_TXT_BYTES = ${PCK_TXT_BYTES};/; s/'index.pck': [0-9]+, 'index.wasm': [0-9]+/'index.pck': ${PCK_BYTES}, 'index.wasm': ${WASM_BYTES}/" "$OUT/ventisca.html"
echo "web demo ready in $(cd "$OUT" && pwd) (add a poster.png screenshot before publishing)"
ls -la "$OUT"
