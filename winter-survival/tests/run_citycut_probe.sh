#!/usr/bin/env bash
# C0 «corte urbano» probe at 5 fixed points of the superblock LT-01 of Las Torres, in the streamed game world
# (tests/citycut_probe.gd). xvfb + Compatibility (llvmpipe) by default; RENDER=forward runs Forward+ on lavapipe.
# Usage: [RENDER=forward] tests/run_citycut_probe.sh [--json=path] [--shots=dir]
# On a shared machine pin it: taskset -c 0,1 tests/run_citycut_probe.sh
set -uo pipefail
cd "$(dirname "$0")/.."
RENDER="${RENDER:-compat}"
if [ "$RENDER" = "forward" ]; then
  export VK_ICD_FILENAMES="${VK_ICD_FILENAMES:-/usr/share/vulkan/icd.d/lvp_icd.json}"
  GODOT_ARGS=(--rendering-driver vulkan --rendering-method forward_plus)
else
  export LIBGL_ALWAYS_SOFTWARE=1
  GODOT_ARGS=(--rendering-driver opengl3 --rendering-method gl_compatibility)
fi
export LP_NUM_THREADS="${LP_NUM_THREADS:-2}"
xvfb-run -a -s "-screen 0 1280x720x24" \
  godot --path . "${GODOT_ARGS[@]}" --audio-driver Dummy --resolution 1280x720 \
  -s tests/citycut_probe.gd ++ "$@" 2>&1 | grep -v -E "ALSA lib|pulse|XDG_RUNTIME|libudev|udev|V-Sync|set_use_vsync" | tee /tmp/ventisca_citycut.log
if grep -q "== citycut probe OK" /tmp/ventisca_citycut.log; then echo "CITYCUT PROBE OK"; else echo "CITYCUT PROBE FAILED"; exit 1; fi
