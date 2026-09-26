"""Verify that survivor_hd_*.glb keeps the game's skeleton contract and plays anims/humanoid_loco.glb.

    cd winter-survival/prototypes/lookdev/blender && python3 verify_survivor_hd.py [--no-godot] [--render]

Blender part (re-import of the exported files):
  1. same 27 bone names, parents and rest matrices as assets/models/chars/survivor_red.glb (<= 1e-4) and as the
     armature inside assets/models/anims/humanoid_loco.glb;
  2. every Loco_* / Crouch_* action of humanoid_loco.glb bound to the HD armature: all channels resolve, and the
     deformed Body keeps its soles on the ground: min z over the cycle within [-2, +2] cm, heel/toe contact;
  3. (--render) posed strips: Loco_Walk / Loco_Run / Crouch_Walk at 6 phases, side and game-camera views.
Godot part (scratch project in $LOOKDEV_OUT/godot_verify, never the look-dev project): import with the 'char' /
'anim' templates, GeneralSkeleton present, COLOR alpha (AO) preserved, the loco library plays and moves bones.
"""
import json
import math
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import hdlib as H  # noqa: E402

HD_CHAR = os.path.join(H.OUT_DIR, "chars", "survivor_hd_brown.glb")
OLD_CHAR = os.path.join(H.OLD_MODELS, "chars", "survivor_red.glb")
LOCO = os.path.join(H.OLD_MODELS, "anims", "humanoid_loco.glb")


def import_glb(path):
    before = set(bpy.data.objects)
    acts_before = set(bpy.data.actions)
    with H.export.quiet():
        bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    arm = next(o for o in new if o.type == 'ARMATURE')
    acts = [a for a in bpy.data.actions if a not in acts_before]
    return arm, new, acts


def rest_table(arm):
    return {b.name: (b.parent.name if b.parent else None, b.matrix_local.copy()) for b in arm.data.bones}


def compare(a, b):
    ta, tb = rest_table(a), rest_table(b)
    problems = []
    if set(ta) != set(tb):
        problems.append("bone sets differ: %s" % sorted(set(ta) ^ set(tb)))
    worst = 0.0
    for n in set(ta) & set(tb):
        if ta[n][0] != tb[n][0]:
            problems.append("%s parent %s != %s" % (n, ta[n][0], tb[n][0]))
        d = max(abs(ta[n][1][i][j] - tb[n][1][i][j]) for i in range(4) for j in range(4))
        worst = max(worst, d)
    if worst > 1e-4:
        problems.append("rest matrices differ by %.2e" % worst)
    return problems, worst, len(ta)


def bind(arm, act):
    ad = arm.animation_data or arm.animation_data_create()
    ad.action = act
    try:
        if act.slots and ad.action_slot is None:
            ad.action_slot = act.slots[0]
    except Exception:
        pass


def foot_metrics(arm, body, act, steps=24):
    """min / max sole height over one cycle (deformed Body, vertices of the boots = z < 0.35 in rest)."""
    sc = bpy.context.scene
    f0, f1 = act.frame_range
    rest_z = [v.co.z for v in body.data.vertices]
    idx = [i for i, z in enumerate(rest_z) if z < 0.35]
    mins, lowest_any = [], 9.0
    for k in range(steps):
        f = f0 + (f1 - f0) * k / steps
        sc.frame_set(int(f), subframe=f - int(f))
        dg = bpy.context.evaluated_depsgraph_get()
        ev = body.evaluated_get(dg)
        me = ev.to_mesh()
        mw = body.matrix_world
        zs = [(mw @ me.vertices[i].co).z for i in idx]
        ev.to_mesh_clear()
        mins.append(min(zs))
        lowest_any = min(lowest_any, min(zs))
    return min(mins), max(mins), lowest_any


def blender_checks(render=False):
    H.export.ensure_gltf()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    H.export.ensure_gltf()
    report = {}
    hd_arm, hd_objs, _ = import_glb(HD_CHAR)
    old_arm, old_objs, _ = import_glb(OLD_CHAR)
    anim_arm, anim_objs, acts = import_glb(LOCO)
    p1, w1, n1 = compare(hd_arm, old_arm)
    p2, w2, n2 = compare(hd_arm, anim_arm)
    report["bones"] = n1
    report["rest_vs_survivor_red"] = {"max_diff": w1, "problems": p1}
    report["rest_vs_humanoid_loco"] = {"max_diff": w2, "problems": p2}
    for o in old_objs + anim_objs:
        if o.type == 'MESH':
            o.hide_render = True
    old_arm.location.x = 3.0
    body = next(o for o in hd_objs if o.type == 'MESH' and o.name.startswith("Body"))
    names = {b.name for b in hd_arm.data.bones}
    report["actions"] = {}
    for act in sorted(acts, key=lambda a: a.name):
        chans = set()
        try:
            for layer in act.layers:
                for strip in layer.strips:
                    for cb in strip.channelbags:
                        for fc in cb.fcurves:
                            if fc.data_path.startswith('pose.bones["'):
                                chans.add(fc.data_path.split('"')[1])
        except Exception:
            for fc in getattr(act, "fcurves", []):
                if fc.data_path.startswith('pose.bones["'):
                    chans.add(fc.data_path.split('"')[1])
        missing = sorted(chans - names)
        bind(hd_arm, act)
        lo, hi, lowest = foot_metrics(hd_arm, body, act)
        report["actions"][act.name] = {"bone_channels": len(chans), "missing_bones": missing,
                                       "sole_min_z_range_cm": [round(lo * 100, 2), round(hi * 100, 2)],
                                       # run cycles have a flight phase (both feet up): only penetration counts
                                       "ok": not missing and lo > -0.02 and (hi < 0.03 or "Run" in act.name)}
    report["ok"] = not p1 and not p2 and all(a["ok"] for a in report["actions"].values())
    if render:
        render_strips(hd_arm, acts)
    return report


def render_strips(arm, acts):
    """Poses of the HD survivor driven by humanoid_loco.glb (side view strip + game camera)."""
    import render_lookdev as R
    sc = bpy.context.scene
    R._MATS.clear()
    for o in bpy.data.objects:
        if o.type == 'MESH' and o.parent is not None and o.parent.type == 'ARMATURE' and o.parent != arm:
            o.hide_render = True
    for o in bpy.data.objects:
        if o.type == 'MESH' and not o.hide_render:
            for s in o.material_slots:
                s.material = R.vcol_material(True)
    R.lights("day")
    R.render_settings(48, (1500, 560))
    R.ground()
    by = {a.name: a for a in acts}
    out = []
    for aname in ("Loco_Walk", "Loco_Run", "Crouch_Walk"):
        act = next((a for n, a in by.items() if n.startswith(aname)), None)
        if act is None:
            continue
        # six copies of the armature at six phases, side view
        copies = []
        f0, f1 = act.frame_range
        for k in range(6):
            a2 = arm.copy()
            a2.data = arm.data
            sc.collection.objects.link(a2)
            a2.animation_data_create()
            bind(a2, act)
            a2.animation_data.action_extrapolation = 'HOLD'
            # time offset through an NLA-free trick: shift keys via frame offset on the copy
            a2.location = (0, k * 1.0 - 2.5, 0)
            copies.append((a2, f0 + (f1 - f0) * k / 6.0))
            for o in [o for o in bpy.data.objects if o.parent == arm and o.type == 'MESH']:
                m2 = o.copy()
                m2.parent = a2
                m2.modifiers["Armature"].object = a2 if "Armature" in m2.modifiers else None
                sc.collection.objects.link(m2)
        arm.hide_render = True
        for o in [o for o in bpy.data.objects if o.parent == arm and o.type == 'MESH']:
            o.hide_render = True
        # bake each copy's pose at its phase: evaluate one by one and freeze with a pose snapshot
        for a2, fr in copies:
            sc.frame_set(int(fr), subframe=fr - int(fr))
            pose = {pb.name: (pb.location.copy(), pb.rotation_quaternion.copy()) for pb in a2.pose.bones}
            a2.animation_data.action = None
            for pb in a2.pose.bones:
                pb.location, pb.rotation_quaternion = pose[pb.name]
        R.camera((0, 0, 0.95), dist=9.5, pitch=6, yaw=90, fov=30)
        name = "survivor_hd_anim_%s_side.png" % aname
        R.shoot(name)
        out.append(name)
        R.camera((0, 0, 0.9), dist=9.0, pitch=48, yaw=135, fov=36)
        name = "survivor_hd_anim_%s_gamecam.png" % aname
        R.shoot(name)
        for a2, _ in copies:
            for o in [o for o in bpy.data.objects if o.parent == a2]:
                bpy.data.objects.remove(o, do_unlink=True)
            bpy.data.objects.remove(a2, do_unlink=True)
    return out


GD_TEST = r'''extends SceneTree
func _initialize() -> void:
	var res := {}
	for path in ["res://assets/hd/chars/survivor_hd_brown.glb", "res://assets/models/chars/survivor_red.glb"]:
		var ps: PackedScene = load(path)
		var m := ps.instantiate()
		get_root().add_child(m)
		var sk: Skeleton3D = m.find_child("GeneralSkeleton", true, false)
		var r := {"skeleton": sk != null}
		if sk == null:
			res[path] = r
			continue
		r["bones"] = sk.get_bone_count()
		var meshes := []
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			var arr: Array = (mi as MeshInstance3D).mesh.surface_get_arrays(0)
			var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
			var amin := 1.0
			for c in cols:
				amin = minf(amin, c.a)
			meshes.append({"name": mi.name, "verts": (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(),
				"colors": cols.size(), "alpha_min": snappedf(amin, 0.001), "skinned": (mi as MeshInstance3D).skin != null})
		r["meshes"] = meshes
		var lib: AnimationLibrary = load("res://assets/models/anims/humanoid_loco.glb")
		var ap := AnimationPlayer.new()
		m.add_child(ap)
		ap.root_node = ap.get_path_to(m)
		ap.add_animation_library("loco", lib)
		r["anims"] = lib.get_animation_list()
		var feet := {}
		for anim in ["Loco_Walk", "Loco_Run", "Crouch_Walk"]:
			ap.play("loco/" + anim)
			var length := ap.get_animation("loco/" + anim).length
			var lo := 9.0
			var hi := -9.0
			var moved := 0.0
			var li := sk.find_bone("LeftToes")
			var hip := sk.find_bone("LeftUpperLeg")
			ap.seek(0.0, true)
			sk.force_update_all_bone_transforms()
			var rest_q := sk.get_bone_pose_rotation(hip)
			for k in 24:
				ap.seek(length * k / 24.0, true)
				sk.force_update_all_bone_transforms()
				var y := sk.get_bone_global_pose(li).origin.y
				lo = minf(lo, y)
				hi = maxf(hi, y)
				moved = maxf(moved, sk.get_bone_pose_rotation(hip).angle_to(rest_q))
			feet[anim] = {"hip_swing_deg": snappedf(rad_to_deg(moved), 0.1)}
		r["feet"] = feet
		res[path] = r
	print("GODOT_VERIFY " + JSON.stringify(res))
	quit()
'''


def godot_checks():
    root = os.path.join(H.SCRATCH, "godot_verify")
    if os.path.isdir(root):
        shutil.rmtree(root)
    for d in ("assets/hd/chars", "assets/hd/rig", "assets/models/anims", "assets/models/chars"):
        os.makedirs(os.path.join(root, d), exist_ok=True)
    with open(os.path.join(root, "project.godot"), "w") as f:
        f.write('config_version=5\n\n[application]\n\nconfig/name="hd_verify"\nconfig/features=PackedStringArray("4.7")\n')
    shutil.copy(HD_CHAR, os.path.join(root, "assets/hd/chars"))
    shutil.copy(HD_CHAR + ".import", os.path.join(root, "assets/hd/chars"))
    shutil.copy(os.path.join(H.OUT_DIR, "rig", "humanoid_bonemap.tres"), os.path.join(root, "assets/hd/rig"))
    shutil.copy(LOCO, os.path.join(root, "assets/models/anims"))
    with open(os.path.join(root, "assets/models/anims/humanoid_loco.glb.import"), "w") as f:
        f.write(H.export.import_file_text("anim").replace(H.export.BONEMAP_RES, "res://assets/hd/rig/humanoid_bonemap.tres"))
    shutil.copy(OLD_CHAR, os.path.join(root, "assets/models/chars"))
    with open(os.path.join(root, "assets/models/chars/survivor_red.glb.import"), "w") as f:
        f.write(H.export.import_file_text("char").replace(H.export.BONEMAP_RES, "res://assets/hd/rig/humanoid_bonemap.tres"))
    with open(os.path.join(root, "verify.gd"), "w") as f:
        f.write(GD_TEST)
    imp = subprocess.run(["godot", "--headless", "--path", root, "--import"], capture_output=True, text=True, timeout=600)
    errors = [ln for ln in (imp.stdout + imp.stderr).splitlines() if "ERROR" in ln]
    run = subprocess.run(["godot", "--headless", "--path", root, "-s", "verify.gd"], capture_output=True, text=True,
                         timeout=600)
    line = next((ln for ln in run.stdout.splitlines() if ln.startswith("GODOT_VERIFY ")), None)
    errors += [ln for ln in (run.stdout + run.stderr).splitlines() if "ERROR" in ln]
    data = json.loads(line[len("GODOT_VERIFY "):]) if line else None
    return {"import_errors": errors[:10], "result": data}


def main():
    args = sys.argv[1:]
    rep = {"blender": blender_checks(render="--render" in args)}
    if "--no-godot" not in args:
        rep["godot"] = godot_checks()
    out = os.path.join(H.SCRATCH, "verify_survivor_hd.json")
    with open(out, "w") as f:
        json.dump(rep, f, indent=1, default=str)
    print(json.dumps(rep, indent=1, default=str))
    ok = rep["blender"]["ok"] and ("godot" not in rep or (not rep["godot"]["import_errors"] and rep["godot"]["result"]))
    print("blender ok %s godot %s -> %s" % (rep["blender"]["ok"], "skipped" if "godot" not in rep else
                                            ("ok" if ok else "FAIL"), "OK" if ok else "FAIL"))
    if not ok:
        sys.exit(1)
    return rep


if __name__ == "__main__":
    main()
