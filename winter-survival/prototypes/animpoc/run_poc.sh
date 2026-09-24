#!/bin/sh
# Reproduce the whole skeletal-animation PoC (Blender 5.0.1 bpy module + Godot 4.7.2). Output: results.txt, godot/shots/*.png
set -e
cd "$(dirname "$0")"
{
echo "### build (bpy)"; python3 build_humanoid.py 2>&1 | grep BUILT
python3 inspect_glb.py out/survivor.glb
echo "### automatic weights test (bpy background)"; python3 test_autoweights.py 2>&1 | grep -E "background|ARMATURE_AUTO"
cp out/survivor.glb out/zombie.glb out/survivor_vcol.glb godot/models/
cp out/survivor.glb godot/models/survivor_rt.glb; cp out/survivor.glb godot/models/survivor_lib.glb; cp out/zombie.glb godot/models/zombie_rt.glb
cd godot
godot --headless --path . -s make_bonemap.gd 2>&1 | grep saved
timeout 200 godot --headless --path . --import > import.log 2>&1 || true
echo "### import errors: $(grep -c ERROR import.log)"
echo "### verify default import"; timeout 60 godot --headless --path . -s verify.gd -- res://models/survivor.glb 2>&1 | tail -n +3
echo "### verify retarget import (BoneMap + SkeletonProfileHumanoid, Overwrite Axis, normalize positions)"
timeout 60 godot --headless --path . -s verify.gd -- res://models/survivor_rt.glb res://models/survivor_lib.glb 2>&1 | tail -n +3 | grep -v "^bones"
timeout 60 godot --headless --path . -s verify.gd -- res://models/zombie_rt.glb 2>&1 | tail -n +3 | grep -v "^bones"
echo "### foot metrics"; timeout 60 godot --headless --path . -s metrics.gd 2>&1 | grep "motion_scale"
echo "### draw calls / auto-LOD"; timeout 120 xvfb-run -a godot --rendering-driver opengl3 --path . -s perf.gd 2>&1 | grep -E "^N=|^LOD"
for m in sheet zombie survivor_rt game; do timeout 150 xvfb-run -a godot --rendering-driver opengl3 --path . -s render.gd -- $m 2>&1 | grep saved; done
timeout 120 xvfb-run -a godot --rendering-driver opengl3 --path . -s tree.gd 2>&1 | grep -E "^tree|saved"
echo "### ragdoll"; timeout 60 xvfb-run -a godot --rendering-driver opengl3 --path . -s ragdoll.gd 2>&1 | grep -E "RAGDOLL|saved"
echo "### vehicle import hints"; (cd .. && python3 build_vehicle_test.py 2>&1 | grep exported); cp ../out/sedan_test.glb models/
timeout 100 godot --headless --path . --import > /dev/null 2>&1 || true
timeout 30 godot --headless --path . -s vtest.gd 2>&1 | grep -E "^\s*- "
} | tee results.txt
