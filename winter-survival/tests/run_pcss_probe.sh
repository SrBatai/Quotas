#!/usr/bin/env bash
# R23 / C0: PCSS penumbra of the same tower at the origin and at Las Torres (2.7 km) — tests/pcss_probe.gd.
# Needs Forward+ (PCSS): RENDER=forward (lavapipe) is the default here; Compatibility reports and passes.
# Usage: [RENDER=compat] tests/run_pcss_probe.sh [--shots=dir] [--x=2688 --z=-384] [--json=path]
set -uo pipefail
cd "$(dirname "$0")/.."
RENDER="${RENDER:-forward}"
if [ "$RENDER" = "forward" ]; then
  export VK_ICD_FILENAMES="${VK_ICD_FILENAMES:-/usr/share/vulkan/icd.d/lvp_icd.json}"
  GODOT_ARGS=(--rendering-driver vulkan --rendering-method forward_plus)
else
  export LIBGL_ALWAYS_SOFTWARE=1
  GODOT_ARGS=(--rendering-driver opengl3 --rendering-method gl_compatibility)
fi
xvfb-run -a -s "-screen 0 1280x720x24" \
  godot --path . "${GODOT_ARGS[@]}" --audio-driver Dummy --resolution 1280x720 \
  -s tests/pcss_probe.gd ++ "$@" 2>&1 | grep -v -E "ALSA lib|pulse|XDG_RUNTIME|libudev|udev|V-Sync|set_use_vsync" | tee /tmp/ventisca_pcss.log
if grep -q "== pcss probe OK" /tmp/ventisca_pcss.log; then echo "PCSS PROBE OK"; else echo "PCSS PROBE FAILED"; exit 1; fi
