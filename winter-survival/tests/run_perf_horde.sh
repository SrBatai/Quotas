#!/usr/bin/env bash
# Server CPU under a horde (PLAN M4, R1): headless dedicated server, 4 bots, 200 zombies around the clearing.
# Writes tests/perf/horde.json and checks tests/perf_budgets.json "perf_horde" (median tick <= 8 ms).
# Usage: tests/run_perf_horde.sh [--zombies=200] [--seconds=20] [--nocheck] [--port=7817]
set -uo pipefail
cd "$(dirname "$0")/.."
godot --headless --path . -s tests/perf_horde.gd ++ "$@" 2>&1 | grep -v -E "ALSA lib|pulse|XDG_RUNTIME|libudev|udev" | tee /tmp/ventisca_perf_horde.log
if grep -E "SCRIPT ERROR" /tmp/ventisca_perf_horde.log > /dev/null; then echo "PERF HORDE FAILED (script errors)"; exit 1; fi
if grep -q "== perf horde OK" /tmp/ventisca_perf_horde.log; then echo "PERF HORDE OK"; exit 0; else echo "PERF HORDE FAILED"; exit 1; fi
