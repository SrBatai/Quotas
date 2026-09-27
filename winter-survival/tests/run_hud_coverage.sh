#!/usr/bin/env bash
# H1 gate: the idle HUD covers ≤ 3 % of a 1920 × 1080 screen (docs/research/10_hud_ux.md §V.5, §V.8).
# Renders the HUD layer only (no 3D, no vignettes, no scrims) over black and white under xvfb + Compatibility.
# Usage: tests/run_hud_coverage.sh [--moments=idle,action,zone,blizzard,info] [--out=dir]
set -uo pipefail
cd "$(dirname "$0")/.."
export LIBGL_ALWAYS_SOFTWARE=1
LOG=/tmp/ventisca_hud_coverage.log
xvfb-run -a -s "-screen 0 1920x1080x24" \
  godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility --audio-driver Dummy --resolution 1920x1080 \
  -s tests/hud_coverage.gd ++ "$@" 2>&1 | grep -v -E "ALSA lib|pulse|XDG_RUNTIME|libudev|udev" > "$LOG"
grep -E "^== |coverage |ok   |FAIL" "$LOG"
if grep -E "SCRIPT ERROR|FAIL:" "$LOG" > /dev/null || ! grep -q "HUD COVERAGE OK" "$LOG"; then echo "HUD COVERAGE FAILED"; exit 1; fi
echo "HUD COVERAGE OK"
