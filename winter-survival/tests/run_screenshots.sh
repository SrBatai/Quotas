#!/usr/bin/env bash
# Screenshot presets under xvfb. Default = Compatibility (llvmpipe); RENDER=forward uses Forward+ on software
# Vulkan (lavapipe, slow). Usage: [RENDER=forward] tests/run_screenshots.sh [out_dir] [preset ...]
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-/tmp/ventisca_shots}"
shift || true
PRESETS=("$@")
[ ${#PRESETS[@]} -eq 0 ] && PRESETS=(day dusk night blizzard interior menu)
mkdir -p "$OUT"
RENDER="${RENDER:-compat}"
if [ "$RENDER" = "forward" ]; then
  export VK_ICD_FILENAMES="${VK_ICD_FILENAMES:-/usr/share/vulkan/icd.d/lvp_icd.json}"
  GODOT_ARGS=(--rendering-driver vulkan --rendering-method forward_plus)
  SUFFIX="_forward"
else
  export LIBGL_ALWAYS_SOFTWARE=1
  GODOT_ARGS=(--rendering-driver opengl3 --rendering-method gl_compatibility)
  SUFFIX=""
fi
for preset in "${PRESETS[@]}"; do
  echo "== $preset ($RENDER)"
  xvfb-run -a -s "-screen 0 1280x720x24" \
    godot --path . "${GODOT_ARGS[@]}" --audio-driver Dummy --resolution 1280x720 \
    -s tests/screenshot.gd ++ --preset=$preset --out=$OUT/$preset$SUFFIX.png 2>&1 | grep -v -E "ALSA lib|pulse|XDG_RUNTIME|libudev|udev" | tail -n 8
done
ls -la "$OUT"
