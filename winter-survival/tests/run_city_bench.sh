#!/usr/bin/env bash
# City bench (W0 + G2a, tests/city_bench): xvfb + Compatibility (llvmpipe) by default; RENDER=forward runs Forward+
# on software Vulkan (lavapipe, slow). Usage:
#   tests/run_city_bench.sh gate            visibility gate + draw-call budgets (blocking), timings (informative)
#   [ROUNDS=3] tests/run_city_bench.sh perf   only the perf part (ROUNDS interleaved rounds, median reported)
#   tests/run_city_bench.sh shots [dir] [preset ...]   city_day city_night city_cut city_inside city_rooftop city_hlod profile_compare
# On a shared machine pin it: taskset -c 0,1 tests/run_city_bench.sh gate
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
    -s tests/city_bench_run.gd ++ "$@" 2>&1 | grep -v -E "ALSA lib|pulse|XDG_RUNTIME|libudev|udev|V-Sync|set_use_vsync"
  return "${PIPESTATUS[0]}"
}
status=0
case "$MODE" in
  gate)
    run --mode=gate --json=/tmp/ventisca_city_gate$SUFFIX.json | tee /tmp/ventisca_city_gate.log
    grep -q "== city bench gate OK" /tmp/ventisca_city_gate.log || status=1
    run --mode=perf --json=/tmp/ventisca_city_perf$SUFFIX.json | tee /tmp/ventisca_city_perf.log
    grep -q "== city bench perf OK" /tmp/ventisca_city_perf.log || status=1
    ;;
  perf)
    run --mode=perf --rounds="${ROUNDS:-1}" --json=/tmp/ventisca_city_perf$SUFFIX.json | tee /tmp/ventisca_city_perf.log
    grep -q "== city bench perf OK" /tmp/ventisca_city_perf.log || status=1
    ;;
  shots)
    OUT="${1:-/tmp/ventisca_city_shots}"
    shift || true
    PRESETS=("$@")
    [ ${#PRESETS[@]} -eq 0 ] && PRESETS=(city_day city_night city_cut city_inside city_rooftop city_hlod profile_compare)
    mkdir -p "$OUT"
    for p in "${PRESETS[@]}"; do
      run --mode=shots --preset="$p" --out="$OUT/$p$SUFFIX.png" | grep -E "screenshot|FAIL|ERROR|SCRIPT" || true
    done
    ls -la "$OUT"
    ;;
  *)
    echo "usage: $0 gate|perf|shots [dir] [preset ...]"; exit 2 ;;
esac
if [ "$status" -eq 0 ]; then echo "CITY BENCH OK"; else echo "CITY BENCH FAILED"; fi
exit $status
