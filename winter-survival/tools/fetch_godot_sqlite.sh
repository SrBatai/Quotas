#!/usr/bin/env bash
# Installs the godot-sqlite GDExtension (MIT, https://github.com/2shady4u/godot-sqlite) into addons/godot-sqlite/
# at a PINNED release, verified by SHA-256 (PLAN C12 / R6, ARQ v2 §15). The only third-party addon of the project.
#   tools/fetch_godot_sqlite.sh            install (no-op when the pinned version is already there)
#   tools/fetch_godot_sqlite.sh --remove   uninstall (the server then falls back to the JSON FileBackend)
#   tools/fetch_godot_sqlite.sh --check    exit 0 when installed at the pinned version, 1 otherwise
# The release asset `demo.zip` carries addons/godot-sqlite/ with every platform binary; only the desktop / server
# ones are kept (Linux x86_64, Windows x86_64, macOS; debug = editor / tests, release = exported builds) and the
# .gdextension manifest is rewritten to list just those. Web, Android and iOS are left out on purpose: the web
# build has no GDExtension support (the Web export preset also excludes addons/godot-sqlite/*) and plays offline
# with MemoryBackend. There is no Linux arm64 binary in the release: an arm64 server uses FileBackend.
# Cache: ${VENTISCA_CACHE:-$HOME/.cache/ventisca} (CI caches it). Needs curl, sha256sum, unzip.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="v4.9"
URL="https://github.com/2shady4u/godot-sqlite/releases/download/${VERSION}/demo.zip"
SHA256="c0eed5f0548bb7f6923e4dfa7725f23357e0e599eba11e981e6383f97fe0dedb"
DEST="addons/godot-sqlite"
STAMP="$DEST/VERSION"
CACHE="${VENTISCA_CACHE:-$HOME/.cache/ventisca}"
ZIP="$CACHE/godot-sqlite-${VERSION}-demo.zip"

want="$VERSION $SHA256"
case "${1:-}" in
  --remove) rm -rf "$DEST"; echo "godot-sqlite removed"; exit 0;;
  --check) [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$want" ] && exit 0 || exit 1;;
esac
if [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$want" ] && [ -f "$DEST/gdsqlite.gdextension" ]; then
  echo "godot-sqlite $VERSION already installed"
  exit 0
fi

mkdir -p "$CACHE"
if [ ! -f "$ZIP" ] || ! echo "$SHA256  $ZIP" | sha256sum -c --status; then
  echo "downloading $URL"
  curl -fsSL --retry 3 -o "$ZIP.part" "$URL"
  mv "$ZIP.part" "$ZIP"
fi
if ! echo "$SHA256  $ZIP" | sha256sum -c --status; then
  echo "godot-sqlite: SHA-256 mismatch for $ZIP (expected $SHA256, got $(sha256sum "$ZIP" | cut -d' ' -f1))" >&2
  rm -f "$ZIP"
  exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
unzip -q "$ZIP" 'demo/addons/godot-sqlite/*' -d "$TMP"
SRC="$TMP/demo/addons/godot-sqlite"
rm -rf "$DEST"
mkdir -p "$DEST/bin"
cp "$SRC/LICENSE.md" "$DEST/"
for f in libgdsqlite.linux.template_debug.x86_64.so libgdsqlite.linux.template_release.x86_64.so \
         libgdsqlite.windows.template_debug.x86_64.dll libgdsqlite.windows.template_release.x86_64.dll; do
  cp "$SRC/bin/$f" "$DEST/bin/"
done
cp -r "$SRC/bin/libgdsqlite.macos.template_debug.framework" "$SRC/bin/libgdsqlite.macos.template_release.framework" "$DEST/bin/"
cat > "$DEST/gdsqlite.gdextension" <<'EOF'
; godot-sqlite (MIT) — installed by tools/fetch_godot_sqlite.sh; desktop / server platforms only (see the script).
[configuration]

entry_symbol = "sqlite_library_init"
compatibility_minimum = "4.7"

[libraries]

macos.debug = "res://addons/godot-sqlite/bin/libgdsqlite.macos.template_debug.framework"
macos.release = "res://addons/godot-sqlite/bin/libgdsqlite.macos.template_release.framework"
windows.debug.x86_64 = "res://addons/godot-sqlite/bin/libgdsqlite.windows.template_debug.x86_64.dll"
windows.release.x86_64 = "res://addons/godot-sqlite/bin/libgdsqlite.windows.template_release.x86_64.dll"
linux.debug.x86_64 = "res://addons/godot-sqlite/bin/libgdsqlite.linux.template_debug.x86_64.so"
linux.release.x86_64 = "res://addons/godot-sqlite/bin/libgdsqlite.linux.template_release.x86_64.so"
EOF
echo "$want" > "$STAMP"
echo "godot-sqlite $VERSION installed into $DEST ($(du -sh "$DEST" | cut -f1)); run 'godot --headless --path . --import' once"
