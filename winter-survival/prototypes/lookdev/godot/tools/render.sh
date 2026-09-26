#!/usr/bin/env bash
# Renders look-dev presets. Usage: tools/render.sh [fp|compat] [extra user args...]
# Example: tools/render.sh fp list=day,dusk,night,blizzard frames=12
# Forward+ runs on software Vulkan (lavapipe) inside the container: slow but faithful.
set -e
HERE="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:-fp}"; shift || true
cd "$HERE"
godot --headless --path "$HERE" --import >/dev/null 2>&1 || true
if [ "$MODE" = "compat" ]; then
  xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-method gl_compatibility --rendering-driver opengl3 \
    --path "$HERE" --resolution 1280x720 -- "$@"
else
  VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a -s "-screen 0 1280x720x24" godot \
    --rendering-method forward_plus --rendering-driver vulkan --path "$HERE" --resolution 1280x720 -- "$@"
fi
