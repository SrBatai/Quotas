#!/usr/bin/env bash
# Perf probe (ARQ v2 §18): fixed clearing scene under xvfb + Compatibility (llvmpipe); RENDER=forward runs it on
# Forward+ over software Vulkan (lavapipe, preset `alto`). Writes tests/perf/last.json and compares with
# tests/perf_budgets.json. Usage: [RENDER=forward] tests/run_perf.sh [--label=name] [--placeholders] [--nocheck] [--out=path]
set -euo pipefail
cd "$(dirname "$0")/.."
ARGS=("$@")
RENDER="${RENDER:-compat}"
if [ "$RENDER" = "forward" ]; then
  export VK_ICD_FILENAMES="${VK_ICD_FILENAMES:-/usr/share/vulkan/icd.d/lvp_icd.json}"
  GODOT_ARGS=(--rendering-driver vulkan --rendering-method forward_plus)
else
  export LIBGL_ALWAYS_SOFTWARE=1
  GODOT_ARGS=(--rendering-driver opengl3 --rendering-method gl_compatibility)
fi
xvfb-run -a -s "-screen 0 1280x720x24" \
  godot --path . "${GODOT_ARGS[@]}" --audio-driver Dummy --resolution 1280x720 \
  -s tests/perf_probe.gd ++ "${ARGS[@]}" 2>&1 | grep -v -E "ALSA lib|pulse|XDG_RUNTIME|libudev|udev|V-Sync|set_use_vsync" | tee /tmp/ventisca_perf.log
if grep -q "== perf probe OK" /tmp/ventisca_perf.log; then echo "PERF OK"; else echo "PERF FAILED"; exit 1; fi
