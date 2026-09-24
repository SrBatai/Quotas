#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-/tmp/ventisca_shots}"
mkdir -p "$OUT"
for preset in day night blizzard interior menu; do
  echo "== $preset"
  LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1280x720x24" \
    godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility --audio-driver Dummy --resolution 1280x720 \
    -s tests/screenshot.gd ++ --preset=$preset --out=$OUT/$preset.png 2>&1 | grep -v -E "ALSA lib|pulse|XDG_RUNTIME|libudev|udev" | tail -n 8
done
ls -la "$OUT"
