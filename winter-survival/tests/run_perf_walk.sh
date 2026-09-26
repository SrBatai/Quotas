#!/usr/bin/env bash
# Streaming perf walk (PLAN M3): 1.6 km at 25 m/s under xvfb + Compatibility (llvmpipe); RENDER=forward runs it on
# Forward+ over software Vulkan (lavapipe). Writes tests/perf/walk.json, checks tests/perf_budgets.json "perf_walk".
# Usage: [RENDER=forward] tests/run_perf_walk.sh [--out=path] [--speed=25] [--nocheck]
#        tests/run_perf_walk.sh --cpu     # headless: streaming CPU cost only (the 2 ms/frame gate, no xvfb needed)
set -euo pipefail
cd "$(dirname "$0")/.."
ARGS=("$@")
for a in "$@"; do
  if [ "$a" = "--cpu" ]; then
    godot --headless --path . -s tests/perf_walk.gd ++ --out=tests/perf/walk_cpu.json "$@" 2>&1 | grep -v -E "ALSA lib|pulse|XDG_RUNTIME|libudev|udev" | tee /tmp/ventisca_perf_walk_cpu.log
    if grep -q "== perf walk OK" /tmp/ventisca_perf_walk_cpu.log; then echo "PERF WALK CPU OK"; exit 0; else echo "PERF WALK CPU FAILED"; exit 1; fi
  fi
done
RENDER="${RENDER:-compat}"
if [ "$RENDER" = "forward" ]; then
  export VK_ICD_FILENAMES="${VK_ICD_FILENAMES:-/usr/share/vulkan/icd.d/lvp_icd.json}"
  GODOT_ARGS=(--rendering-driver vulkan --rendering-method forward_plus)
else
  export LIBGL_ALWAYS_SOFTWARE=1
  # llvmpipe rasterizes on as many threads as there are cores and overlaps the next frame's CPU work: cap it so
  # the main thread (where streaming is measured) is not preempted by the software GPU (documented in ARQ v2 M3)
  export LP_NUM_THREADS="${LP_NUM_THREADS:-2}"
  GODOT_ARGS=(--rendering-driver opengl3 --rendering-method gl_compatibility)
fi
xvfb-run -a -s "-screen 0 1280x720x24" \
  godot --path . "${GODOT_ARGS[@]}" --audio-driver Dummy --resolution 1280x720 \
  -s tests/perf_walk.gd ++ "${ARGS[@]}" 2>&1 | grep -v -E "ALSA lib|pulse|XDG_RUNTIME|libudev|udev|V-Sync|set_use_vsync" | tee /tmp/ventisca_perf_walk.log
if grep -q "== perf walk OK" /tmp/ventisca_perf_walk.log; then echo "PERF WALK OK"; else echo "PERF WALK FAILED"; exit 1; fi
