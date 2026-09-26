"""Verify characters and animation libraries against docs/v2/ASSET_SPEC_V2.md §4-§7 (milestone M1).

Run:  cd winter-survival/blender && python3 verify_chars.py      (exit code 0 = ALL OK)

Everything is measured on the exported files (what Godot imports), with lib/gltf_anim.py:
  chars/*.glb, zombies/*.glb   one skin with the 27 joints (22 SkeletonProfileHumanoid names + 5 sockets),
      exact names and parents; T-pose rest = rig.joints() (front +Z glTF = -Y Blender, left +X, feet at 0);
      one mesh `Body`, 1 surface palette_vcol with COLOR_0 (palette colours as Godot stores them),
      JOINTS_0/WEIGHTS_0, no UVs, no animations; rigid skin (every vertex 100 % on one deforming bone, never on
      Root or a socket); eye quads in front (+Z); height, ground contact (sole at y 0, boot heel at the rig
      Heel point); tris <= budget; source .blend: bone deform flags / roll (rig.check_armature) and weights.
  anims/*.glb   armature only (same 27 nodes and rest as the characters, so tracks transfer 1:1); every
      action of the library table present, name rule Set_Action[_Variant][-loop], -loop exactly on loops,
      duration +-1 frame, >= 20 rotation channels and >= 10 channels in total, Root static, only Hips
      translates, no scale keys, loops closed (first pose == last pose); foot metrics on every Loco_*/Crouch_*
      cycle: ankle min >= 0.08 m, sole never under the ground at a key, LEFT foot on the ground at t = 0,
      grounded contact points (heel, ball, toe tip) moving backward at the authored speed: mean within 5 %,
      every sample within 5 % (foot sliding < 5 %), lateral drift < 5 %; standing loops: feet planted.
  Godot side: each .glb has its .import (template lib/export.py: importer, retarget BoneMap +
      SkeletonProfileHumanoid, GeneralSkeleton, Overwrite Axis, except_bone_transform OFF (bug #123782),
      library optimizer OFF) and assets/models/rig/humanoid_bonemap.tres maps our 22 bones 1:1.
G1 (v2.1, docs/research/05_graficos_arte.md §4): a character is `Body` + optional `Outfit_*` meshes (children of
      Armature, skinned); Body is rigid except the vertices of chars/build_survivor.BLEND_PAIRS (parka skirt: Hips +
      one UpperLeg, 2 influences summing to 1); COLOR_0 RGBA with baked AO (verify_assets.gltf_problems); budget
      v2.1 (Body + outfits <= 3 500). Foot metrics: the ankle minimum is also measured BETWEEN keys (the .glb
      evaluated 8x per frame with slerp, as Godot plays it) and, when `godot` is on PATH, on the clips IMPORTED by
      Godot 4.7 (throwaway project in $VENTISCA_GODOT_SCRATCH or a temp dir, retarget templates of lib/export.py,
      240 samples per cycle): every Loco_* / Crouch_* cycle keeps the ankle >= 0.08 m there too.
M4 (zombies + combat): zombies/*.glb are checked with the rig parameters of their variant
      (zombies/build_zombie.VARIANTS: height / width -> rest = rig.joints(params)), the height range and feet rule of their
      kind (crawlers have no feet), meshes Body + Outfit_* + Ice (frozen shards), zombie budget 2 500 (doc 05 v2.1); the
      libraries anims/zombie_anims.glb (ZOMBIE_TABLE) and anims/humanoid_combat.glb (COMBAT_TABLE) carry a clip KIND:
      gait (foot metrics as Loco_*), crawl (palm contact points grounded move backward at the authored speed +-5 %),
      stand (feet planted), additive (first / last frame = rest, deltas < 40 deg), move / ground (no joint under the
      ground; ground clips keep the Hips >= 5 cm). Every clip: >= 20 rotation channels, Hips position track, every
      frame keyed. No visible back face (verify_assets.backface_problems) on any zombie or survivor at rest and in the
      BF_POSES of its kind (zombie_anims / humanoid_loco / humanoid_combat frames, evaluated through the skin). The Godot probe also plays zombie_anims on two zombies of other proportions (retarget check).
Prints one line per asset / action (`OK ...` or `FAIL name: reason`) and ends with `ALL OK` or `N FAILURES`.
"""
import json
import shutil
import subprocess
import tempfile
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy  # noqa: E402
from mathutils import Quaternion, Vector  # noqa: E402

from lib import anim  # noqa: E402
from lib import export  # noqa: E402
from lib import gltf_anim as ga  # noqa: E402
from lib import palette  # noqa: E402
from lib import rig  # noqa: E402

MODELS = export.MODELS_DIR
CHAR_DIRS = ("chars", "zombies")
ANIM_DIR = "anims"
TOL_JOINT = 1e-3
HEIGHT = (1.76, 1.86)          # survivor with beanie + pompom (§4.2: 1.80 reference, skull 1.74)
MAX_SPEED_DEV = 0.05           # stance speed / sliding tolerance (§6.1, §7)
PLANTED_MAX = 0.02             # m/s: standing loops keep their feet still
ANKLE_MIN = 0.08
SOLE_MIN = -0.005
OVERSAMPLE = 8                 # between-key evaluation of the cycles (Godot slerps between the 30 fps keys)
EYE_FRONT = 0.07               # eye quads at least this far in front of the rig axis (glTF +z)


def budgets():
    sys.path.insert(0, os.path.join(HERE, "chars"))
    from chars import build_survivor
    from zombies import build_zombie
    return {"survivor": build_survivor.BUDGET, "zombie": build_zombie.BUDGET}


def blend_pairs():
    from chars import build_survivor
    return {frozenset(p) for p in build_survivor.BLEND_PAIRS}


def loco_table():
    from anims import build_loco
    from anims import build_zombie_anims
    from anims import build_combat
    return {"humanoid_loco": build_loco.LOCO_TABLE, "zombie_anims": build_zombie_anims.ZOMBIE_TABLE,
            "humanoid_combat": build_combat.COMBAT_TABLE}


def char_rules(name):
    """Contract of one character file: rig parameters, height range, feet on the contact points, allowed meshes,
    2-influence pairs, budget."""
    from chars import build_survivor
    if name.startswith("zombie_"):
        from zombies import build_zombie as bz
        v = bz.VARIANTS[name[len("zombie_"):]]
        kr = bz.KIND_RULES[v["kind"]]
        return dict(params=bz.rig_params(name[len("zombie_"):]), height=kr["height"], feet=kr["feet"],
                    meshes=bz.MESH_NAMES, pairs={frozenset(q) for q in bz.BLEND_PAIRS}, budget=bz.BUDGET,
                    blend_pairs=bz.BLEND_PAIRS)
    return dict(params=rig.params(), height=HEIGHT, feet=True, meshes=("Body",),
                pairs={frozenset(q) for q in build_survivor.BLEND_PAIRS}, budget=build_survivor.BUDGET,
                blend_pairs=build_survivor.BLEND_PAIRS)


# ------------------------------------------------------------------------------------------------
# .import / bonemap
# ------------------------------------------------------------------------------------------------
IMPORT_RULES = {
    "char": ['importer="scene"', 'animation/import=false'],
    "anim": ['importer="animation_library"', 'animation/import=true', 'animation/fps=30',
             'animation/import_rest_as_RESET=true', '"PATH:AnimationPlayer": {\n"optimizer/enabled": false'],
}
RETARGET_RULES = ['"PATH:Armature/Skeleton3D"', '"retarget/bone_map": Resource("%s")' % export.BONEMAP_RES,
                  '"retarget/bone_renamer/unique_node/skeleton_name": "GeneralSkeleton"',
                  '"retarget/bone_renamer/unique_node/make_unique": true',
                  '"retarget/remove_tracks/except_bone_transform": false',
                  '"retarget/remove_tracks/unmapped_bones": 0',
                  '"retarget/rest_fixer/normalize_position_tracks": true',
                  '"retarget/rest_fixer/retarget_method": 1', 'nodes/use_name_suffixes=true']


def import_problems(glb, kind):
    path = str(glb) + ".import"
    if not os.path.exists(path):
        return ["missing %s.import (lib/export.py write_import(glb, %r))" % (os.path.basename(str(glb)), kind)]
    text = open(path).read()
    return ["%s.import lacks %s" % (os.path.basename(str(glb)), r.split("\n")[-1]) for r in
            IMPORT_RULES[kind] + RETARGET_RULES if r not in text]


def bonemap_problems():
    if not export.BONEMAP_PATH.exists():
        return ["missing %s" % export.BONEMAP_PATH.relative_to(export.ROOT)]
    got = dict(re.findall(r'^bone_map/(\w+) = &"(\w*)"$', export.BONEMAP_PATH.read_text(), re.M))
    want = dict(re.findall(r'^bone_map/(\w+) = &"(\w*)"$', rig.bonemap_tres_text(), re.M))
    out = []
    if got != want:
        out.append("humanoid_bonemap.tres mapping differs from rig.bonemap_tres_text() (regenerate)")
    if 'type="SkeletonProfileHumanoid"' not in export.BONEMAP_PATH.read_text():
        out.append("humanoid_bonemap.tres profile is not SkeletonProfileHumanoid")
    return out


# ------------------------------------------------------------------------------------------------
# glTF skeleton
# ------------------------------------------------------------------------------------------------
def skeleton_problems(g, joint_idx=None, p=None):
    """27 bone nodes, exact names, parents, rest = rig.joints(p) (glTF axes)."""
    out = []
    names = rig.ALL_BONES
    for b in names:
        if b not in g.by_name:
            out.append("bone %s missing" % b)
    if out:
        return out
    if joint_idx is not None:
        jn = sorted(g.nodes[i]["name"] for i in joint_idx)
        if jn != sorted(names):
            out.append("skin joints %s" % sorted(set(jn) ^ set(names)))
    for b in names:
        want = rig.BONE_PARENTS.get(b, rig.SOCKETS.get(b))
        i = g.by_name[b]
        par = g.parent.get(i)
        got = g.nodes[par]["name"] if par is not None else None
        if want is None:
            if got != "Armature":
                out.append("Root parent %s (want the Armature node)" % got)
        elif got != want:
            out.append("%s parent %s != %s" % (b, got, want))
    heads = rig.rest_heads(p)
    for b in names:
        p = g.rest_global(g.by_name[b]).translation
        if (p - ga.blender_to_gltf(heads[b])).length > TOL_JOINT:
            out.append("%s rest at %s, want %s" % (b, tuple(round(c, 3) for c in p),
                                                   tuple(round(c, 3) for c in ga.blender_to_gltf(heads[b]))))
    for n in g.nodes:
        if "." in n.get("name", ""):
            out.append("dotted node name %s" % n["name"])
    return out


# ------------------------------------------------------------------------------------------------
# characters
# ------------------------------------------------------------------------------------------------
def verify_char(glb, rules):
    name = os.path.basename(str(glb))[:-4]
    budget = rules["budget"]
    pr = []
    if os.path.getsize(glb) < 1024:
        return "FAIL %s: file too small" % name, 0
    g = ga.Glb(glb)
    j = g.json
    pr += import_problems(glb, "char")
    if j.get("animations"):
        pr.append("character carries %d animations (they live in anims/*.glb)" % len(j["animations"]))
    skins = j.get("skins", [])
    if len(skins) != 1:
        return "FAIL %s: %d skins" % (name, len(skins)), 0
    joints = skins[0]["joints"]
    pr += skeleton_problems(g, joints, rules["params"])
    if "Armature" not in g.by_name:
        pr.append("no Armature node")
    meshes = [(i, nd) for i, nd in enumerate(g.nodes) if "mesh" in nd]
    mnames = [nd["name"] for _i, nd in meshes]
    if "Body" not in mnames or any(n not in rules["meshes"] and not n.startswith("Outfit_") for n in mnames):
        pr.append("mesh nodes %s (want Body + Outfit_* + %s)" % (mnames, list(rules["meshes"][1:])))
    pairs = rules["pairs"]
    tris = 0
    gp, surfaces = _palette_problems(g)
    pr += gp
    deform = {i for i in joints if g.nodes[i]["name"] in rig.DEFORM_BONES}
    ymin, ymax = 9.0, -9.0
    eye_z = []
    heel_z = {}
    for _i, nd in meshes:
        if g.parent.get(_i) != g.by_name.get("Armature"):
            pr.append("%s is not a child of Armature" % nd["name"])
        if nd.get("skin") != 0:
            pr.append("%s not skinned" % nd["name"])
        is_body = nd["name"] == "Body"
        eyes = palette.target_godot_bytes("eyes_dark")
        for prim in j["meshes"][nd["mesh"]]["primitives"]:
            at = prim["attributes"]
            for k in ("POSITION", "COLOR_0", "JOINTS_0", "WEIGHTS_0"):
                if k not in at:
                    pr.append("Body primitive lacks %s" % k)
            if any(k.startswith("TEXCOORD") for k in at) or "JOINTS_1" in at:
                pr.append("Body has UVs or a second joint set")
            if not all(k in at for k in ("POSITION", "JOINTS_0", "WEIGHTS_0")):
                continue
            pos = g.accessor(at["POSITION"])
            jts = g.accessor(at["JOINTS_0"], normalized=False)
            wts = g.accessor(at["WEIGHTS_0"], normalized=True)
            cols = g.accessor(at["COLOR_0"], normalized=True) if "COLOR_0" in at else [None] * len(pos)
            idx = g.accessor(prim["indices"]) if "indices" in prim else None
            tris += (len(idx) if idx else len(pos)) // 3
            bad_w = 0
            foot_nodes = {g.by_name["LeftFoot"], g.by_name["RightFoot"]}
            for p, jt, w, c in zip(pos, jts, wts, cols):
                ymin, ymax = min(ymin, p[1]), max(ymax, p[1])
                nz = [(joints[jt[k]], w[k]) for k in range(4) if w[k] > 1e-6]
                if len(nz) == 2 and is_body and abs(nz[0][1] + nz[1][1] - 1.0) < 1e-3 and \
                        frozenset(g.nodes[b]["name"] for b, _w in nz) in pairs:
                    continue                                   # parka skirt blend (BLEND_PAIRS)
                if len(nz) != 1 or abs(nz[0][1] - 1.0) > 1e-3 or nz[0][0] not in deform:
                    bad_w += 1
                    continue
                if c is not None and palette.godot_bytes(c) == eyes:
                    eye_z.append(p[2])
                if nz[0][0] in foot_nodes and p[1] < 1e-4:
                    side = "L" if p[0] > 0 else "R"
                    heel_z[side] = min(heel_z.get(side, 9.0), p[2])
            if bad_w:
                pr.append("%s: %d vertices not rigidly weighted to one deforming bone" % (nd["name"], bad_w))
    if tris > budget:
        pr.append("tris %d > budget %d" % (tris, budget))
    if rules["feet"] and abs(ymin) > 0.002:
        pr.append("lowest vertex at y %.3f (feet must touch 0)" % ymin)
    if not rules["feet"] and ymin < 0.25:
        pr.append("legless character reaches y %.3f (stumps expected above the knees)" % ymin)
    hmin, hmax = rules["height"]
    if not hmin <= ymax <= hmax:
        pr.append("height %.3f outside %s" % (ymax, rules["height"]))
    if not eye_z or min(eye_z) < EYE_FRONT:
        pr.append("eye quads not on the front (+Z glTF = -Y Blender)")
    want_heel = -rig.joints(rules["params"])["LeftHeel"].y
    for side in "LR" if rules["feet"] else "":
        if abs(heel_z.get(side, 9.0) - want_heel) > 0.005:
            pr.append("%s boot heel sole ends at z %.3f, want the rig Heel %.3f" % (side, heel_z.get(side, 9.0),
                                                                                    want_heel))
    pr += blend_problems(name, rules)
    nposes = 0
    if name.startswith("zombie_"):
        from zombies import build_zombie as bz
        bf, nposes = backface_check(name, bz.VARIANTS[name[len("zombie_"):]]["kind"])
        pr += bf
    elif name.startswith("survivor_"):
        bf, nposes = backface_check(name, "survivor")
        pr += bf
    if pr:
        return "FAIL %s: %s" % (name, "; ".join(pr)), tris
    import verify_assets
    return ("OK %-18s tris=%-4d surfaces=%d meshes=%s bones=%d (22 + 5 sockets) height=%.3f skin ok %s%s" %
            (name, tris, surfaces, "+".join(mnames), len(joints), ymax, verify_assets.ao_summary(g.json, g.bin),
             " back faces ok (rest + %d poses)" % (nposes - 1) if nposes else "")), tris


def _palette_problems(g):
    """Surfaces, materials and COLOR_0 values (as Godot stores them) through verify_assets.gltf_problems."""
    import verify_assets
    godot_targets = {palette.target_godot_bytes(n) for n in palette.all_names()}
    return verify_assets.gltf_problems(g.json, g.bin, godot_targets)


def blend_problems(name, rules=None):
    """Source .blend: bone set / parents / deform flags / T-pose / roll and the rigid weights in Blender."""
    rules = rules or char_rules(name)
    path = export.SOURCES_DIR / ("%s.blend" % name)
    if not path.exists():
        return ["missing sources/%s.blend" % name]
    with export.quiet():
        bpy.ops.wm.open_mainfile(filepath=str(path))
    arm = bpy.data.objects.get("Armature")
    body = bpy.data.objects.get("Body")
    if arm is None or body is None:
        return ["%s.blend lacks Armature/Body" % name]
    pr = rig.check_armature(arm, rules["params"]) + rig.check_rigid_skin(body, rules["blend_pairs"])
    for o in [o for o in bpy.data.objects if o.type == 'MESH' and o.name != "Body"]:
        pr += ["%s: %s" % (o.name, x) for x in rig.check_rigid_skin(o)]
    for o in [o for o in bpy.data.objects if o.type == 'MESH']:
        if o.parent != arm or not any(m.type == 'ARMATURE' and m.object == arm for m in o.modifiers):
            pr.append("%s not bound to Armature" % o.name)
    return ["blend: " + x for x in pr]



# ------------------------------------------------------------------------------------------------
# visible back faces (M3 rule, M4: zombies at rest and in representative animated poses)
# ------------------------------------------------------------------------------------------------
Z_ = "zombie_anims"
# (library, action, frame) poses checked for visible back faces, per character kind
BF_POSES = {
    "walker": [(Z_, "Zom_Shamble_A-loop", 9), (Z_, "Zom_Shamble_D-loop", 27), (Z_, "Zom_Attack_A", 13),
               (Z_, "Zom_Knockdown", 24)],
    "frozen": [(Z_, "Zom_Shamble_A-loop", 9), (Z_, "Zom_Attack_A", 13)],
    "runner": [(Z_, "Zom_Run-loop", 5), (Z_, "Zom_Attack_A", 13)],
    "crawler": [(Z_, "Zom_Crawl-loop", 10)],
    "bloater": [(Z_, "Zom_Walk_Heavy-loop", 12), (Z_, "Zom_Attack_A", 13)],
    # M4 follow-up: the survivor (parka skirt, fur collar) under the same rule, in locomotion and combat poses
    "survivor": [("humanoid_loco", "Loco_Walk-loop", 6), ("humanoid_loco", "Loco_Run-loop", 5),
                 ("humanoid_loco", "Crouch_Walk-loop", 10), ("humanoid_loco", "Loco_Idle_Cold-loop", 20),
                 ("humanoid_combat", "Melee2H_Swing_A", 13), ("humanoid_combat", "Melee1H_Light_A", 8),
                 ("humanoid_combat", "Melee_Charged", 24), ("humanoid_combat", "Act_Revive-loop", 20),
                 ("humanoid_combat", "Down_Idle-loop", 10), ("humanoid_combat", "Down_Crawl-loop", 12)],
}


def backface_check(name, kind):
    """verify_assets.backface_problems on the character at rest and posed with BF_POSES[kind] (evaluated through the
    Armature modifier, every mesh of the file). Returns (problems, poses checked)."""
    import verify_assets
    path = export.SOURCES_DIR / ("%s.blend" % name)
    with export.quiet():
        bpy.ops.wm.open_mainfile(filepath=str(path))
    arm = bpy.data.objects.get("Armature")
    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    out = []
    poses = BF_POSES.get(kind, [])
    acts = {}
    for lib in sorted({p_[0] for p_ in poses}):
        path_ = export.SOURCES_DIR / ("%s.blend" % lib)
        if not path_.exists():
            out.append("missing sources/%s.blend for the posed back-face check" % lib)
            continue
        with bpy.data.libraries.load(str(path_), link=False) as (src, dst):
            dst.actions = [a_ for l_, a_, _f in poses if l_ == lib and a_ in src.actions]
        acts.update({(lib, a_.name): a_ for a_ in dst.actions if a_ is not None})
    for lib, label, frame in [(None, "rest", None)] + poses:
        if frame is None:
            anim.reset_pose(arm)
        elif (lib, label) in acts:
            anim.assign(arm, acts[(lib, label)])
        else:
            out.append("pose %s/%s not found" % (lib, label))
            continue
        bpy.context.scene.frame_set(frame or 0)
        dg = bpy.context.evaluated_depsgraph_get()
        tmp = []
        for o in meshes:
            me = bpy.data.meshes.new_from_object(o.evaluated_get(dg), depsgraph=dg)
            t = bpy.data.objects.new("bf_" + o.name, me)
            t.matrix_world = o.matrix_world.copy()
            bpy.context.scene.collection.objects.link(t)
            tmp.append(t)
        bpy.context.view_layer.update()
        pr = verify_assets.backface_problems(tmp, ground=True)
        out += ["%s: %s" % (label if frame is None else "%s f%d" % (label, frame), x) for x in pr]
        for t in tmp:
            bpy.data.objects.remove(t, do_unlink=True)
    return out, 1 + len(poses)


# ------------------------------------------------------------------------------------------------
# animation libraries
# ------------------------------------------------------------------------------------------------
def contact_tracks(g, pl, n, fps):
    """{Side_Point: [Vector per frame (Blender axes)]} for the sole contact points + ankles."""
    j = rig.joints()
    out = {}
    for side in anim.SIDES:
        for key, bone in list(rig.CONTACT_POINTS.items()) + [("Ankle", "Foot")]:
            bi = g.by_name[side + bone]
            p = ga.blender_to_gltf(j[side + ("Foot" if key == "Ankle" else key)])
            local = g.rest_global(bi).inverted() @ p
            pts = []
            for f in range(n + 1):
                q = pl.at(f / fps).global_(bi) @ local
                pts.append(Vector((q.x, -q.z, q.y)))
            out[side + "_" + key] = pts
    return out


def ankle_min_between_keys(g, pl, n, over=OVERSAMPLE):
    """Lowest ankle (Foot head) height over the cycle evaluated `over` times per frame (slerp between keys)."""
    lo = 9.0
    feet = [g.by_name[s + "Foot"] for s in anim.SIDES]
    for f in range(n * over + 1):
        t = pl.duration * f / (n * over)
        ev = pl.at(t)
        for bi in feet:
            lo = min(lo, ev.global_(bi).translation.y)
    return lo


def verify_action(g, name, table, fps=anim.FPS):
    pr = []
    base = name[:-5] if name.endswith("-loop") else name
    entry = table.get(name)
    if entry is None:
        return "FAIL %s: not in the library table" % name, None
    looping, length, speed = entry[:3]
    kind = entry[3] if len(entry) > 3 else ("gait" if speed > 0 else "stand")
    pr += anim.check_action_name(name, looping)
    pl = ga.Player(g, name)
    if abs(pl.duration - length) > 1.0 / fps + 1e-4:
        pr.append("duration %.3f s, want %.3f" % (pl.duration, length))
    rot = trans = scl = 0
    hips_moves = False
    for (node, path), (times, vals, interp) in pl.ch.items():
        bname = g.nodes[node]["name"]
        moving = len(vals) > 1 and any(
            max(abs(a - b) for a, b in zip(v, vals[0])) > 1e-5 for v in vals)
        if interp != "LINEAR" and moving:
            pr.append("%s.%s interpolation %s" % (bname, path, interp))
        if path == "rotation":
            rot += bname in rig.BONE_NAMES and bname != "Root"
        elif path == "translation":
            trans += 1
            if moving and bname != "Hips":
                pr.append("%s translates (only Hips may)" % bname)
            hips_moves = hips_moves or (moving and bname == "Hips")
        elif path == "scale" and moving:
            pr.append("%s has scale keys" % bname)
        if bname == "Root" and moving:
            pr.append("Root is animated (in-place: Root never moves)")
        scl += path == "scale"
    if rot < 20:
        pr.append("%d rotation channels (< 20)" % rot)
    if len(pl.ch) < 10:
        pr.append("%d channels (< 10: Godot bug #123782 symptom)" % len(pl.ch))
    if not hips_moves and kind != "stand" and not name.startswith(("Loco_", "Crouch_")):
        pr.append("no moving Hips position track (Godot drops immutable tracks)")
    n = int(round(pl.duration * fps))
    heads0 = {b: pl.at(0.0).global_(g.by_name[b]).translation.copy() for b in rig.BONE_NAMES}
    headsn = {b: pl.at(pl.duration).global_(g.by_name[b]).translation.copy() for b in rig.BONE_NAMES}
    gap = max((heads0[b] - headsn[b]).length for b in rig.BONE_NAMES)
    if looping and gap > 1e-3:
        pr.append("loop not closed (first/last pose differ by %.4f m)" % gap)
    m = None
    if kind in ("gait", "stand"):
        m = anim.contact_stats(contact_tracks(g, pl, n, fps), speed if speed > 0 else 0.0, fps=fps)
        m["ankle_interp"] = ankle_min_between_keys(g, pl, n)
        if m["ankle_min"] < ANKLE_MIN:
            pr.append("ankle min %.3f < %.2f" % (m["ankle_min"], ANKLE_MIN))
        if m["ankle_interp"] < ANKLE_MIN:
            pr.append("ankle min between keys %.4f < %.2f (Godot slerps the keys)" % (m["ankle_interp"], ANKLE_MIN))
        if m["sole_min"] < SOLE_MIN:
            pr.append("sole %.3f m under the ground" % -m["sole_min"])
        if not m["left_contact_t0"]:
            pr.append("left foot not on the ground at t = 0")
        if speed > 0:
            if m["samples"] < 4:
                pr.append("only %d grounded samples" % m["samples"])
            if abs(m["stance_speed"] - speed) > MAX_SPEED_DEV * speed:
                pr.append("stance speed %.3f vs authored %.2f" % (m["stance_speed"], speed))
            if m["slide"] > MAX_SPEED_DEV:
                pr.append("foot sliding %.1f %% (> 5 %%)" % (100 * m["slide"]))
            if m["lateral"] > MAX_SPEED_DEV:
                pr.append("lateral foot drift %.1f %%" % (100 * m["lateral"]))
        elif m["slide"] * 0.05 > PLANTED_MAX:
            pr.append("standing feet move %.3f m/s" % (m["slide"] * 0.05))
    elif kind == "crawl":
        m = anim.contact_stats(palm_tracks(g, pl, n, fps), speed, fps=fps)
        if m["samples"] < 4:
            pr.append("only %d grounded palm samples" % m["samples"])
        if abs(m["stance_speed"] - speed) > MAX_SPEED_DEV * speed:
            pr.append("palm stance speed %.3f vs authored %.2f" % (m["stance_speed"], speed))
        if m["slide"] > MAX_SPEED_DEV or m["lateral"] > MAX_SPEED_DEV:
            pr.append("palm sliding %.1f %% / lateral %.1f %%" % (100 * m["slide"], 100 * m["lateral"]))
        if not m["left_contact_t0"]:
            pr.append("left palm not on the ground at t = 0")
    elif kind == "additive":
        m = additive_stats(g, pl)
        if m["end_dev"] > 3.0:
            pr.append("additive clip does not start / end at the rest pose (%.1f deg)" % m["end_dev"])
        if m["max_dev"] > 40.0:
            pr.append("additive delta %.1f deg > 40" % m["max_dev"])
    if kind != "additive":
        lo, lo_bone, hips_lo = lowest_joint(g, pl, n)
        if lo < -0.01:
            pr.append("%s goes %.3f m under the ground" % (lo_bone, -lo))
        if kind in ("ground", "crawl") and hips_lo < 0.05:
            pr.append("Hips down to %.3f m (body through the ground)" % hips_lo)
        if kind not in ("gait", "stand"):
            sole = min(v.z for pts in contact_tracks(g, pl, n, fps).values() for v in pts)
            if sole < -0.01:
                pr.append("sole %.3f m under the ground" % -sole)
    if pr:
        return "FAIL %s: %s" % (name, "; ".join(pr)), m
    desc = "OK   %-22s %-4s %.3f s %-8s channels=%d (rot %d)" % (name, "loop" if looping else "once", pl.duration,
                                                                 kind, len(pl.ch), rot)
    if m is not None and kind in ("gait", "stand"):
        if speed > 0:
            desc += "  stance %.3f/%.1f m/s slide %.2f%% ankle_min %.3f (between keys %.4f) (%d samples)" % (
                m["stance_speed"], speed, 100 * m["slide"], m["ankle_min"], m["ankle_interp"], m["samples"])
        else:
            desc += "  feet planted (max %.4f m/s) ankle_min %.3f (between keys %.4f)" % (
                m["slide"] * 0.05, m["ankle_min"], m["ankle_interp"])
    elif kind == "crawl":
        desc += "  palms %.3f/%.1f m/s slide %.2f%% (%d samples)" % (m["stance_speed"], speed, 100 * m["slide"],
                                                                     m["samples"])
    elif kind == "additive":
        desc += "  delta max %.1f deg, ends %.2f deg" % (m["max_dev"], m["end_dev"])
    return desc, m


def palm_tracks(g, pl, n, fps):
    """Crawl contact points: the palm underside of each hand (Hand head + 0.06 m along the hand, 3 cm under it),
    keyed as Side_Heel so anim.contact_stats treats them like sole points; + the wrists as Side_Ankle."""
    from lib import keyanim as ka
    out = {}
    for side in anim.SIDES:
        bi = g.by_name[side + "Hand"]
        for key, pt in (("Ball", ka.palm_rest(None, side) + Vector((0, 0, -0.03))), ("Ankle", rig.joints()[side + "Hand"])):
            local = g.rest_global(bi).inverted() @ ga.blender_to_gltf(pt)
            pts = []
            for f in range(n + 1):
                q = pl.at(f / fps).global_(bi) @ local
                pts.append(Vector((q.x, -q.z, q.y)))
            out[side + "_" + key] = pts
        out[side + "_Heel"] = out[side + "_Ball"]
        out[side + "_TipSole"] = out[side + "_Ball"]
    return out


def lowest_joint(g, pl, n, fps=anim.FPS):
    """(lowest bone head z over the clip, its bone, lowest Hips z) in Blender axes."""
    lo, lo_b, hips = 9.0, None, 9.0
    for f in range(n + 1):
        ev = pl.at(f / fps)
        for b in rig.BONE_NAMES:
            if b == "Root":
                continue
            z = ev.global_(g.by_name[b]).translation.y
            if z < lo:
                lo, lo_b = z, b
            if b == "Hips":
                hips = min(hips, z)
    return lo, lo_b, hips


def additive_stats(g, pl):
    """Largest rotation of any bone away from its rest (glTF node rotation) at the ends and over the clip (deg)."""
    import math
    end_dev = max_dev = 0.0
    for (node, path), (times, vals, _i) in pl.ch.items():
        if path != "rotation":
            continue
        r = g.nodes[node].get("rotation", (0, 0, 0, 1))
        rest = Quaternion((r[3], r[0], r[1], r[2]))
        devs = []
        for v in vals:
            q = Quaternion((v[3], v[0], v[1], v[2]))
            devs.append(math.degrees(rest.rotation_difference(q).angle))
        devs = [min(d, 360 - d) for d in devs]
        end_dev = max(end_dev, devs[0], devs[-1])
        max_dev = max(max_dev, max(devs))
    return dict(end_dev=end_dev, max_dev=max_dev)


def verify_library(glb, table):
    name = os.path.basename(str(glb))[:-4]
    lines = []
    fails = 0
    g = ga.Glb(glb)
    pr = import_problems(glb, "anim")
    if any("mesh" in nd for nd in g.nodes):
        pr.append("animation library must be an armature without mesh")
    pr += skeleton_problems(g)
    got = set(g.animations())
    if got != set(table):
        pr.append("actions %s (want %s)" % (sorted(got), sorted(table)))
    if not export.SOURCES_DIR.joinpath("%s.blend" % name).exists():
        pr.append("missing sources/%s.blend" % name)
    if pr:
        lines.append("FAIL %s: %s" % (name, "; ".join(pr)))
        fails += 1
    else:
        lines.append("OK %-18s actions=%d armature-only (27 bones, rest = survivor rest)" % (name, len(got)))
    for an in sorted(got & set(table)):
        ln, _m = verify_action(g, an, table)
        lines.append("  " + ln)
        fails += ln.startswith("FAIL")
    return lines, fails


# ------------------------------------------------------------------------------------------------
# Godot import (what the game plays)
# ------------------------------------------------------------------------------------------------
GODOT_PROBE = r"""extends SceneTree
## For every (model, library) pair: each clip of the imported library played on the imported model, 240 samples per
## clip (between the 30 fps keys too): lowest ankle (Foot origin), lowest bone origin, rotation-track count, and the
## model's Hips rest height. Measured on the first frame (nodes in the tree).
const PAIRS := %s
var _done := false
var _models := {}


func _initialize() -> void:
	for pair in PAIRS:
		if not _models.has(pair[0]):
			var ps: PackedScene = load("res://assets/models/%%s.glb" %% pair[0])
			var m: Node3D = ps.instantiate()
			root.add_child(m)
			_models[pair[0]] = m


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	var out := {}
	for pair in PAIRS:
		var m: Node3D = _models[pair[0]]
		var sk: Skeleton3D = m.find_child("GeneralSkeleton", true, false)
		var lib: AnimationLibrary = load("res://assets/models/%%s.glb" %% pair[1])
		if sk == null or lib == null:
			out[pair[0] + "|" + pair[1]] = {}
			continue
		var ap := AnimationPlayer.new()
		m.add_child(ap)
		ap.root_node = ap.get_path_to(m)
		ap.add_animation_library("lib", lib)
		var feet := [sk.find_bone("LeftFoot"), sk.find_bone("RightFoot")]
		var to_model := m.global_transform.affine_inverse() * sk.global_transform
		var hips_rest := (to_model * sk.get_bone_global_rest(sk.find_bone("Hips"))).origin.y
		var res := {"_hips_rest": hips_rest}
		for an in lib.get_animation_list():
			var a := lib.get_animation(an)
			var rot := 0
			for t in a.get_track_count():
				if a.track_get_type(t) == Animation.TYPE_ROTATION_3D:
					rot += 1
			ap.play("lib/" + an)
			var lo := 9.0
			var low := 9.0
			for k in 241:
				ap.seek(a.length * k / 240.0, true)
				sk.force_update_all_bone_transforms()
				for b in feet:
					lo = minf(lo, (to_model * sk.get_bone_global_pose(b)).origin.y)
				for b in sk.get_bone_count():
					if sk.get_bone_name(b) != "Root":
						low = minf(low, (to_model * sk.get_bone_global_pose(b)).origin.y)
			res[String(an)] = [lo, low, rot, a.loop_mode]
		out[pair[0] + "|" + pair[1]] = res
		ap.queue_free()
	print("ANKLE_PROBE " + JSON.stringify(out))
	quit()
	return true
"""
# (model, library) pairs measured in Godot; zombies of other proportions check the retarget (feet stay planted)
GODOT_PAIRS = [("chars/survivor_red", "anims/humanoid_loco"), ("chars/survivor_red", "anims/humanoid_combat"),
               ("chars/survivor_red", "anims/zombie_anims"), ("zombies/zombie_walker_17", "anims/zombie_anims"),
               ("zombies/zombie_bloater_01", "anims/zombie_anims"), ("zombies/zombie_runner_01", "anims/zombie_anims")]


def godot_ankle_check():
    """Import the GODOT_PAIRS files in a throwaway Godot project and play every clip on its model: gait clips keep the
    ankle >= 0.08 m (x the model's Hips rest / 0.92 for other proportions), no clip takes a bone origin under the
    ground, every clip keeps >= 20 rotation tracks after Godot's immutable-track removal, loop flags = the tables.
    Returns (lines, failures). Skipped (no failure) when `godot` is not on PATH."""
    godot = shutil.which("godot")
    if godot is None:
        return ["SKIP godot import check (godot not on PATH)"], 0
    tables = {"anims/" + k: v for k, v in loco_table().items()}
    root = os.environ.get("VENTISCA_GODOT_SCRATCH") or tempfile.mkdtemp(prefix="ventisca_godot_")
    if os.path.isdir(root):
        shutil.rmtree(root)
    rels = sorted({r for pr_ in GODOT_PAIRS for r in pr_})
    for rel in [r + ".glb" for r in rels] + ["rig/humanoid_bonemap.tres"]:
        src = MODELS / rel
        dst = os.path.join(root, "assets", "models", rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy(str(src), dst)
        if rel.endswith(".glb"):
            imp = open(str(src) + ".import").read()
            imp = "\n".join(ln for ln in imp.splitlines() if not ln.startswith(("uid=", "path=", "dest_files=")))
            open(dst + ".import", "w").write(imp + "\n")
    with open(os.path.join(root, "project.godot"), "w") as f:
        f.write('config_version=5\n\n[application]\n\nconfig/name="ventisca_verify_chars"\n'
                'config/features=PackedStringArray("4.7")\n')
    with open(os.path.join(root, "ankle_probe.gd"), "w") as f:
        f.write(GODOT_PROBE % json.dumps([list(p_) for p_ in GODOT_PAIRS]))
    cmd = ["taskset", "-c", "2,3", godot] if shutil.which("taskset") else [godot]
    run = subprocess.run(cmd + ["--headless", "--path", root, "--import"], capture_output=True, text=True,
                         timeout=900)
    errors = [ln for ln in (run.stdout + run.stderr).splitlines() if "ERROR" in ln]
    run = subprocess.run(cmd + ["--headless", "--path", root, "-s", "ankle_probe.gd"], capture_output=True,
                         text=True, timeout=900)
    errors += [ln for ln in (run.stdout + run.stderr).splitlines() if "ERROR" in ln]
    line = next((ln for ln in run.stdout.splitlines() if ln.startswith("ANKLE_PROBE ")), None)
    data = json.loads(line[len("ANKLE_PROBE "):]) if line else {}
    lines, fails = [], 0
    if errors:
        lines.append("FAIL godot import: %d ERROR line(s), e.g. %s" % (len(errors), errors[0][:160]))
        fails += 1
    if not data:
        lines.append("FAIL godot import: no probe result")
        return lines, fails + 1
    for key in [m_ + "|" + l_ for m_, l_ in GODOT_PAIRS]:
        res = data.get(key) or {}
        model, lib = key.split("|")
        table = tables.get(lib, {})
        if not res:
            lines.append("FAIL godot %s: not imported / no GeneralSkeleton" % key)
            fails += 1
            continue
        scale = res.pop("_hips_rest") / 0.92
        want = {k[:-5] if k.endswith("-loop") else k: v for k, v in table.items()}
        bad = []
        gait_lo, low_all = 9.0, 9.0
        res.pop("RESET", None)
        for an, (lo, low, rot, loop_mode) in sorted(res.items()):
            entry = want.get(an)
            if entry is None:
                bad.append("%s not in the table" % an)
                continue
            kind = entry[3] if len(entry) > 3 else ("gait" if entry[2] > 0 else "stand")
            if kind in ("gait", "stand"):
                gait_lo = min(gait_lo, lo / scale)
                if lo < ANKLE_MIN * scale - 1e-4:
                    bad.append("%s ankle %.4f < %.3f" % (an, lo, ANKLE_MIN * scale))
            low_all = min(low_all, low)
            if low < -0.02:
                bad.append("%s bone %.3f m under the ground" % (an, -low))
            if rot < 20:
                bad.append("%s %d rotation tracks after import (< 20)" % (an, rot))
            if (loop_mode == 1) != entry[0]:
                bad.append("%s loop mode %d" % (an, loop_mode))
        if set(want) - set(res):
            bad.append("missing %s" % sorted(set(want) - set(res)))
        if bad:
            lines.append("FAIL godot %s: %s" % (key, "; ".join(bad[:6])))
            fails += 1
        else:
            lines.append("OK   godot %-48s %2d clips, hips rest x%.3f, gait ankle min %.4f (normalised), lowest bone %.3f" % (
                key, len(res), scale, gait_lo if gait_lo < 9 else 0.0, low_all))
    if not errors and root.startswith(tempfile.gettempdir()) and not os.environ.get("VENTISCA_GODOT_SCRATCH"):
        shutil.rmtree(root, ignore_errors=True)
    return lines, fails


# ------------------------------------------------------------------------------------------------
def main():
    failures = 0
    tables = loco_table()
    pr = bonemap_problems()
    for p in pr:
        print("FAIL bonemap: %s" % p)
    failures += len(pr)
    n_chars = 0
    for d in CHAR_DIRS:
        folder = MODELS / d
        for glb in sorted(folder.glob("*.glb")) if folder.exists() else []:
            line, _t = verify_char(glb, char_rules(glb.stem))
            print(line)
            failures += line.startswith("FAIL")
            n_chars += 1
    if n_chars == 0:
        print("FAIL no character .glb in assets/models/chars")
        failures += 1
    for lib_name, table in tables.items():
        glb = MODELS / ANIM_DIR / ("%s.glb" % lib_name)
        if not glb.exists():
            print("FAIL %s: missing %s" % (lib_name, glb.relative_to(export.ROOT)))
            failures += 1
            continue
        lines, f = verify_library(glb, table)
        for ln in lines:
            print(ln)
        failures += f
    for glb in sorted((MODELS / ANIM_DIR).glob("*.glb")):
        if glb.stem not in tables:
            print("FAIL %s: no library table (add it to verify_chars.loco_table)" % glb.stem)
            failures += 1
    lines, f = godot_ankle_check()
    for ln in lines:
        print(ln)
    failures += f
    print("ALL OK" if failures == 0 else "%d FAILURES" % failures)
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
