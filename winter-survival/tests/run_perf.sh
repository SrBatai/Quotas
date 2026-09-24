#!/usr/bin/env bash
# Perf probe (ARQ v2 §18): fixed clearing scene under xvfb + Compatibility; writes tests/perf/last.json and
# compares with tests/perf_budgets.json. Usage: tests/run_perf.sh [--label=name] [--placeholders] [--nocheck] [--out=path]
set -euo pipefail
cd "$(dirname "$0")/.."
ARGS=("$@")
LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1280x720x24" \
  godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility --audio-driver Dummy --resolution 1280x720 \
  -s tests/perf_probe.gd ++ "${ARGS[@]}" 2>&1 | grep -v -E "ALSA lib|pulse|XDG_RUNTIME|libudev|udev|V-Sync|set_use_vsync" | tee /tmp/ventisca_perf.log
if grep -q "== perf probe OK" /tmp/ventisca_perf.log; then echo "PERF OK"; else echo "PERF FAILED"; exit 1; fi
