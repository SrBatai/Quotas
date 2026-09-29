#!/usr/bin/env bash
# M6a street bench (tests/street_bench: the kit test street of Santa María del Puerto): xvfb + Compatibility (llvmpipe)
# by default; RENDER=forward runs Forward+ on software Vulkan (lavapipe, slow). Usage:
#   tests/run_street_bench.sh gate                citycut probe on the street + interior shadow checks (blocking)
#   tests/run_street_bench.sh shots [dir] [preset ...]   street_day street_night house_inside
# On a shared machine pin it: taskset -c 0,1 tests/run_street_bench.sh gate
set -uo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-gate}"
shift || true
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
export LP_NUM_THREADS="${LP_NUM_THREADS:-2}"
run() {
  xvfb-run -a -s "-screen 0 1280x720x24" \
    godot --path . "${GODOT_ARGS[@]}" --audio-driver Dummy --resolution 1280x720 \
    -s tests/street_bench_run.gd ++ "$@" 2>&1 | grep -v -E "ALSA lib|pulse|XDG_RUNTIME|libudev|udev|V-Sync|set_use_vsync"
  return "${PIPESTATUS[0]}"
}
status=0
case "$MODE" in
  gate)
    run --mode=gate --json=/tmp/ventisca_street_gate$SUFFIX.json | tee /tmp/ventisca_street_gate.log
    grep -q "== street bench gate OK" /tmp/ventisca_street_gate.log || status=1
    ;;
  shots)
    OUT="${1:-/tmp/ventisca_street_shots}"
    shift || true
    PRESETS=("$@")
    [ ${#PRESETS[@]} -eq 0 ] && PRESETS=(street_day street_night house_inside)
    mkdir -p "$OUT"
    for p in "${PRESETS[@]}"; do
      run --mode=shots --preset="$p" --out="$OUT/$p$SUFFIX.png" | grep -E "screenshot|FAIL|ERROR|SCRIPT" || true
    done
    ls -la "$OUT"
    ;;
  *)
    echo "usage: $0 gate|shots [dir] [preset ...]"; exit 2 ;;
esac
if [ "$status" -eq 0 ]; then echo "STREET BENCH OK"; else echo "STREET BENCH FAILED"; fi
exit $status
