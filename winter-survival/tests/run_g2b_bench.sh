#!/usr/bin/env bash
# G2b bench (tests/g2b_bench.gd, xvfb). Usage:
#   tests/run_g2b_bench.sh ratio [rounds]   blizzard vs day in the C0 city scene, Forward+ on lavapipe (`alto`): frame
#                                           time ratio ≤ 1.25 (PLAN G2b), night / night blizzard informative, and the
#                                           LUT blend step in the real frame loop ≤ 0.1 ms (median)
#   tests/run_g2b_bench.sh depth [dir]      the city at night / dusk / in a blizzard as drawn, without fog and with the
#                                           fog saturated, in Compatibility (llvmpipe) and Forward+ (lavapipe): how far
#                                           the fog moves each pixel toward its colour, far third vs near third; the far
#                                           third must be foggier in both, and `compat` (no volumetrics) must keep ≥ 80 %
#                                           of Forward+'s far fog and far-near gradient (captures saved in dir)
#   tests/run_g2b_bench.sh gate             both
# On a shared machine pin it: taskset -c 0,1 tests/run_g2b_bench.sh gate (ratios survive load; absolute ms do not)
set -uo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-gate}"
shift || true
export LP_NUM_THREADS="${LP_NUM_THREADS:-2}"
run() {   # run <compat|forward> args...
  local r="$1"; shift
  if [ "$r" = "forward" ]; then
    VK_ICD_FILENAMES="${VK_ICD_FILENAMES:-/usr/share/vulkan/icd.d/lvp_icd.json}" xvfb-run -a -s "-screen 0 1280x720x24" \
      godot --path . --rendering-driver vulkan --rendering-method forward_plus --audio-driver Dummy --resolution 1280x720 \
      -s tests/g2b_bench.gd ++ "$@" 2>&1 | grep -v -E "ALSA lib|pulse|XDG_RUNTIME|libudev|udev|V-Sync|set_use_vsync"
  else
    LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1280x720x24" \
      godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility --audio-driver Dummy --resolution 1280x720 \
      -s tests/g2b_bench.gd ++ "$@" 2>&1 | grep -v -E "ALSA lib|pulse|XDG_RUNTIME|libudev|udev|V-Sync|set_use_vsync"
  fi
  return "${PIPESTATUS[0]}"
}
status=0
if [ "$MODE" = "ratio" ] || [ "$MODE" = "gate" ]; then
  ROUNDS="${1:-3}"
  [ "$MODE" = "gate" ] && ROUNDS=3
  run forward --mode=ratio --rounds="$ROUNDS" --json=/tmp/ventisca_g2b_ratio.json | tee /tmp/ventisca_g2b_ratio.log
  grep -q "== g2b bench ratio OK" /tmp/ventisca_g2b_ratio.log || status=1
fi
if [ "$MODE" = "depth" ] || [ "$MODE" = "gate" ]; then
  DIR="${1:-/tmp/ventisca_g2b_depth}"
  [ "$MODE" = "gate" ] && DIR=/tmp/ventisca_g2b_depth
  for r in ${RENDERERS:-compat forward}; do   # RENDERERS=compat reuses the last Forward+ JSON
    run "$r" --mode=depth --json=/tmp/ventisca_g2b_depth_$r.json --shots="$DIR" | tee /tmp/ventisca_g2b_depth_$r.log
    grep -q "== g2b bench depth OK" /tmp/ventisca_g2b_depth_$r.log || status=1
  done
  python3 - << 'PY' || status=1
import json, sys
c = json.load(open("/tmp/ventisca_g2b_depth_compat.json"))
f = json.load(open("/tmp/ventisca_g2b_depth_forward.json"))
bad = 0
for k in ("night", "dusk", "blizzard"):
    dc, df = c[k]["depth"], f[k]["depth"]
    fc, ff = c[k]["far"], f[k]["far"]
    # the far third as foggy (≥ 80 %) and the far-near gradient as steep (≥ 80 %, 0.02 of slack for tiny gradients)
    ok = dc > 0 and df > 0 and fc >= 0.8 * ff and dc >= 0.8 * df - 0.02
    bad += 0 if ok else 1
    print("  %s %-9s depth compat %.3f vs Forward+ %.3f (%.0f %%), far third %.3f vs %.3f (%.0f %%), Forward+ volumetric %s" % (
        "ok  " if ok else "FAIL:", k, dc, df, 100.0 * dc / df if df > 0 else 0.0, fc, ff, 100.0 * fc / ff if ff > 0 else 0.0, f[k]["volumetric"]))
sys.exit(1 if bad else 0)
PY
fi
if [ "$status" -eq 0 ]; then echo "G2B BENCH OK"; else echo "G2B BENCH FAILED"; fi
exit $status
