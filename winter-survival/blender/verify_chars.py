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
Prints one line per asset / action (`OK ...` or `FAIL name: reason`) and ends with `ALL OK` or `N FAILURES`.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

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


def budgets():
    sys.path.insert(0, os.path.join(HERE, "chars"))
    from chars import build_survivor
    return {"survivor": build_survivor.BUDGET}


def loco_table():
    from anims import build_loco
    return {"humanoid_loco": build_loco.LOCO_TABLE}


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
def skeleton_problems(g, joint_idx=None):
    """27 bone nodes, exact names, parents, rest = rig.joints() (glTF axes)."""
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
    heads = rig.rest_heads()
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
def verify_char(glb, budget):
    name = os.path.basename(str(glb))[:-4]
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
    pr += skeleton_problems(g, joints)
    if "Armature" not in g.by_name:
        pr.append("no Armature node")
    meshes = [(i, nd) for i, nd in enumerate(g.nodes) if "mesh" in nd]
    if [nd["name"] for _i, nd in meshes] != ["Body"]:
        pr.append("mesh nodes %s (want ['Body'])" % [nd["name"] for _i, nd in meshes])
    tris = 0
    gp, surfaces = _palette_problems(g)
    pr += gp
    deform = {i for i in joints if g.nodes[i]["name"] in rig.DEFORM_BONES}
    ymin, ymax = 9.0, -9.0
    eye_z = []
    heel_z = {}
    for _i, nd in meshes:
        if g.parent.get(_i) != g.by_name.get("Armature"):
            pr.append("Body is not a child of Armature")
        if nd.get("skin") != 0:
            pr.append("Body not skinned")
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
                if len(nz) != 1 or abs(nz[0][1] - 1.0) > 1e-3 or nz[0][0] not in deform:
                    bad_w += 1
                    continue
                if c is not None and palette.godot_bytes(c) == eyes:
                    eye_z.append(p[2])
                if nz[0][0] in foot_nodes and p[1] < 1e-4:
                    side = "L" if p[0] > 0 else "R"
                    heel_z[side] = min(heel_z.get(side, 9.0), p[2])
            if bad_w:
                pr.append("%d vertices not rigidly weighted to one deforming bone" % bad_w)
    if tris > budget:
        pr.append("tris %d > budget %d" % (tris, budget))
    if abs(ymin) > 0.002:
        pr.append("lowest vertex at y %.3f (feet must touch 0)" % ymin)
    if not HEIGHT[0] <= ymax <= HEIGHT[1]:
        pr.append("height %.3f outside %s" % (ymax, HEIGHT))
    if not eye_z or min(eye_z) < 0.10:
        pr.append("eye quads not on the front (+Z glTF = -Y Blender)")
    want_heel = -rig.joints()["LeftHeel"].y
    for side in "LR":
        if abs(heel_z.get(side, 9.0) - want_heel) > 0.005:
            pr.append("%s boot heel sole ends at z %.3f, want the rig Heel %.3f" % (side, heel_z.get(side, 9.0),
                                                                                    want_heel))
    pr += blend_problems(name)
    if pr:
        return "FAIL %s: %s" % (name, "; ".join(pr)), tris
    return ("OK %-18s tris=%-4d surfaces=%d bones=%d (22 + 5 sockets) height=%.3f rigid-skin COLOR_0" %
            (name, tris, surfaces, len(joints), ymax)), tris


def _palette_problems(g):
    """Surfaces, materials and COLOR_0 values (as Godot stores them) through verify_assets.gltf_problems."""
    import verify_assets
    godot_targets = {palette.target_godot_bytes(n) for n in palette.all_names()}
    return verify_assets.gltf_problems(g.json, g.bin, godot_targets)


def blend_problems(name):
    """Source .blend: bone set / parents / deform flags / T-pose / roll and the rigid weights in Blender."""
    path = export.SOURCES_DIR / ("%s.blend" % name)
    if not path.exists():
        return ["missing sources/%s.blend" % name]
    with export.quiet():
        bpy.ops.wm.open_mainfile(filepath=str(path))
    arm = bpy.data.objects.get("Armature")
    body = bpy.data.objects.get("Body")
    if arm is None or body is None:
        return ["%s.blend lacks Armature/Body" % name]
    pr = rig.check_armature(arm) + rig.check_rigid_skin(body)
    if body.parent != arm or not any(m.type == 'ARMATURE' and m.object == arm for m in body.modifiers):
        pr.append("Body not bound to Armature")
    return ["blend: " + x for x in pr]


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


def verify_action(g, name, table, fps=anim.FPS):
    pr = []
    base = name[:-5] if name.endswith("-loop") else name
    entry = table.get(name)
    if entry is None:
        return "FAIL %s: not in the library table" % name, None
    looping, length, speed = entry
    pr += anim.check_action_name(name, looping)
    pl = ga.Player(g, name)
    if abs(pl.duration - length) > 1.0 / fps + 1e-4:
        pr.append("duration %.3f s, want %.3f" % (pl.duration, length))
    rot = trans = scl = 0
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
        elif path == "scale" and moving:
            pr.append("%s has scale keys" % bname)
        if bname == "Root" and moving:
            pr.append("Root is animated (in-place: Root never moves)")
        scl += path == "scale"
    if rot < 20:
        pr.append("%d rotation channels (< 20)" % rot)
    if len(pl.ch) < 10:
        pr.append("%d channels (< 10: Godot bug #123782 symptom)" % len(pl.ch))
    n = int(round(pl.duration * fps))
    heads0 = {b: pl.at(0.0).global_(g.by_name[b]).translation.copy() for b in rig.BONE_NAMES}
    headsn = {b: pl.at(pl.duration).global_(g.by_name[b]).translation.copy() for b in rig.BONE_NAMES}
    gap = max((heads0[b] - headsn[b]).length for b in rig.BONE_NAMES)
    if looping and gap > 1e-3:
        pr.append("loop not closed (first/last pose differ by %.4f m)" % gap)
    m = None
    if base.startswith(("Loco_", "Crouch_", "Zom_Shamble", "Zom_Run")):
        m = anim.contact_stats(contact_tracks(g, pl, n, fps), speed if speed > 0 else 0.0, fps=fps)
        if m["ankle_min"] < ANKLE_MIN:
            pr.append("ankle min %.3f < %.2f" % (m["ankle_min"], ANKLE_MIN))
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
    if pr:
        return "FAIL %s: %s" % (name, "; ".join(pr)), m
    desc = "OK   %-22s %-4s %.3f s  channels=%d (rot %d)" % (name, "loop" if looping else "once", pl.duration,
                                                             len(pl.ch), rot)
    if m is not None:
        if speed > 0:
            desc += "  stance %.3f/%.1f m/s slide %.2f%% ankle_min %.3f (%d samples)" % (
                m["stance_speed"], speed, 100 * m["slide"], m["ankle_min"], m["samples"])
        else:
            desc += "  feet planted (max %.4f m/s) ankle_min %.3f" % (m["slide"] * 0.05, m["ankle_min"])
    return desc, m


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
def main():
    failures = 0
    bud = budgets()
    tables = loco_table()
    pr = bonemap_problems()
    for p in pr:
        print("FAIL bonemap: %s" % p)
    failures += len(pr)
    n_chars = 0
    for d in CHAR_DIRS:
        folder = MODELS / d
        for glb in sorted(folder.glob("*.glb")) if folder.exists() else []:
            fam = glb.stem.split("_")[0]
            line, _t = verify_char(glb, bud.get(fam, 1300))
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
    print("ALL OK" if failures == 0 else "%d FAILURES" % failures)
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
