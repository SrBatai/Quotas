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
  # W0: the city presets (city_day, city_night, city_cut, city_inside, city_rooftop, city_hlod, profile_compare)
  # are rendered by the city bench, not the game scene
  if [[ "$preset" == city_* || "$preset" == profile_* ]]; then
    echo "== $preset ($RENDER, city bench)"
    RENDER="$RENDER" tests/run_city_bench.sh shots "$OUT" "$preset" | grep -E "screenshot|FAIL" || true
    continue
  fi
  # H1: the HUD presets (hud_*) are judged at 1920 × 1080 like the mockups; RES overrides any preset
  RES_P="${RES:-1280x720}"
  [ -z "${RES:-}" ] && [[ "$preset" == hud_* ]] && RES_P="1920x1080"
  echo "== $preset ($RENDER, $RES_P)"
  xvfb-run -a -s "-screen 0 ${RES_P}x24" \
    godot --path . "${GODOT_ARGS[@]}" --audio-driver Dummy --resolution "$RES_P" \
    -s tests/screenshot.gd ++ --preset=$preset --out=$OUT/$preset$SUFFIX.png 2>&1 | grep -v -E "ALSA lib|pulse|XDG_RUNTIME|libudev|udev" | tail -n 8
done
ls -la "$OUT"
