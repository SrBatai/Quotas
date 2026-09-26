"""Build every HD look-dev asset, verify the survivor against the game's skeleton/animations, optionally render.

    cd winter-survival/prototypes/lookdev/blender && python3 build_all_hd.py [--render] [--no-godot]

Outputs: ../godot/assets/hd/*.glb (+ chars/, rig/, hd_manifest.json, lookdev_layout.json), sources/*.blend,
previews in $LOOKDEV_OUT (default: session scratchpad lookdev_art/).
"""
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
STEPS = ["build_cabin_hd.py", "build_trees_hd.py", "build_terrain_hd.py", "build_survivor_hd.py"]


def run(args):
    t = time.time()
    r = subprocess.run([sys.executable] + args, cwd=HERE, capture_output=True, text=True)
    lines = [ln for ln in r.stdout.splitlines() if ln.startswith(("HD ", "AO", "rendered", "blender ok"))]
    print("\n".join(lines))
    if r.returncode != 0:
        print(r.stdout[-3000:], r.stderr[-3000:])
        raise SystemExit("FAILED: %s" % " ".join(args))
    print("  (%s: %.1f s)" % (args[0], time.time() - t))


def main():
    for s in STEPS:
        run([s])
    v = ["verify_survivor_hd.py"] + (["--no-godot"] if "--no-godot" in sys.argv else [])
    run(v)
    if "--render" in sys.argv:
        run(["render_lookdev.py", "compare", "scene_dusk", "cabin", "cabin_old", "trees", "survivor", "terrain"])
        run(["verify_survivor_hd.py", "--no-godot", "--render"])
    print("ALL OK")


if __name__ == "__main__":
    main()
