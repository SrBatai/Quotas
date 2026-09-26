"""survivor_hd_{brown,olive,navy,rust} - HD look-dev survivor (guidelines v2.1).

    cd winter-survival/prototypes/lookdev/blender && python3 build_survivor_hd.py

Same skeleton as the game's chars/survivor_*.glb: lib.rig.build_armature() with the default 1.80 m parameters
(22 SkeletonProfileHumanoid bones + 5 sockets, T-pose, front -Y), so anims/humanoid_loco.glb plays unchanged
(checked by verify_survivor_hd.py in Blender and in a Godot 4.7.2 import). Boot soles touch the ground exactly at
the rig contact points (heel y +0.10, ball y -0.10, tip y -0.19, z 0).

Look (reference): natural proportions (head ~1/7.5 of the height, no box head), long dark parka to mid-thigh
with a fur-trimmed collar and bunched hood, dark trousers, brown boots with light sock cuffs, dark gloves and
beanie, muted colours. Smooth shaded lofts (10-14 sides) with hard edges only at hems/cuffs (angle 55 deg).
Structure (ASSET_SPEC_V2 §4.4):
    Armature
    ├─ Body                 rigid skin; the parka skirt below the hips blends Hips -> UpperLeg (<= 2 influences,
    │                       smoothstep rings, as §4.3 allows for long coats) so the hem follows the legs
    └─ Outfit_backpack_m    backpack + bedroll + straps, rigid on Chest (the code shows/hides it by name)
Budget v2.1: Body <= 3 500 tris, backpack <= 900.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import hdlib as H  # noqa: E402
from hdlib import lp  # noqa: E402
from lib import rig  # noqa: E402
from mathutils import Vector  # noqa: E402

VARIANTS = {"brown": "parka_brown", "olive": "parka_olive", "navy": "parka_navy", "rust": "parka_rust"}
SUB = "chars"


def sq_ring(cx, cy, z, rx, ry, n=14, p=2.6, y_bias=0.0):
    """Horizontal superellipse ring (rounded-rectangle cross-section of the torso). y_bias pushes the back (+Y)."""
    pts = []
    for i in range(n):
        t = 2 * math.pi * i / n + math.pi / n
        c, s = math.cos(t), math.sin(t)
        x = rx * math.copysign(abs(c) ** (2 / p), c)
        y = ry * math.copysign(abs(s) ** (2 / p), s)
        if y > 0:
            y *= 1 + y_bias
        pts.append(Vector((cx + x, cy + y, z)))
    return pts


def yz_ring(x, cy, cz, ry, rz, n=10, p=2.2):
    pts = []
    for i in range(n):
        t = 2 * math.pi * i / n
        c, s = math.cos(t), math.sin(t)
        pts.append(Vector((x, cy + ry * math.copysign(abs(c) ** (2 / p), c), cz + rz * math.copysign(abs(s) ** (2 / p), s))))
    return pts


def build_parts(M):
    j = rig.joints()
    parts = {}

    def mb(b):
        return parts.setdefault(b, lp.MeshBuilder())
    P = M["parka"]
    # ---- torso: parka (Hips skirt / Spine / Chest) -------------------------------------------------------
    hips = mb("Hips")
    hem = [sq_ring(0, 0.006, 0.625, 0.200, 0.150, y_bias=0.05), sq_ring(0, 0.006, 0.645, 0.214, 0.160, y_bias=0.05),
           sq_ring(0, 0.004, 0.76, 0.212, 0.156, y_bias=0.05), sq_ring(0, 0.0, 0.88, 0.206, 0.150, y_bias=0.05),
           sq_ring(0, 0.0, 1.00, 0.204, 0.146, y_bias=0.05)]
    hips.loft(hem, P, cap_start=True, cap_end=False)
    # drawcord band at the waist
    hips.loft([sq_ring(0, 0.0, 0.975, 0.210, 0.152, y_bias=0.05), sq_ring(0, 0.0, 1.005, 0.210, 0.152, y_bias=0.05)],
              M["dark"], cap_start=False, cap_end=False)
    # trouser seat (inside the skirt, shows between the legs)
    hips.loft([sq_ring(0, 0.0, 0.70, 0.16, 0.11, n=10), sq_ring(0, 0.0, 0.95, 0.17, 0.115, n=10)], M["pants"])
    spine = mb("Spine")
    spine.loft([sq_ring(0, 0.0, 0.99, 0.204, 0.146, y_bias=0.05), sq_ring(0, 0.0, 1.10, 0.210, 0.150, y_bias=0.06),
                sq_ring(0, 0.0, 1.22, 0.212, 0.150, y_bias=0.07)], P, cap_start=False, cap_end=False)
    chest = mb("Chest")
    chest.loft([sq_ring(0, 0.0, 1.21, 0.212, 0.150, y_bias=0.07), sq_ring(0, 0.0, 1.33, 0.218, 0.148, y_bias=0.08),
                sq_ring(0, 0.0, 1.42, 0.205, 0.138, y_bias=0.06), sq_ring(0, 0.004, 1.475, 0.16, 0.115),
                sq_ring(0, 0.008, 1.50, 0.095, 0.085)], P, cap_start=False, cap_end=True)
    # front placket + chest pockets (dark), hand-warmer pocket flaps on the skirt
    for bone, z0, z1, yb in (("Hips", 0.66, 0.99, -0.168), ("Spine", 0.99, 1.21, -0.160), ("Chest", 1.21, 1.43, -0.160)):
        mb(bone).box((-0.008, yb - 0.006, z0), (0.008, yb + 0.03, z1), M["dark"])
    for sx in (-1, 1):
        chest.box((sx * 0.06 - 0.045, -0.166, 1.30), (sx * 0.06 + 0.045, -0.13, 1.37), P)
        chest.box((sx * 0.06 - 0.048, -0.172, 1.35), (sx * 0.06 + 0.048, -0.13, 1.375), P)
        hips.box((sx * 0.12 - 0.06, -0.176, 0.80), (sx * 0.12 + 0.06, -0.13, 0.82), P)
    # fur-trimmed collar (lumpy ring) + bunched hood behind the neck
    rnd = __import__("random").Random(4)
    fur = []
    for k, (z, rx, ry) in enumerate(((1.455, 0.125, 0.115), (1.50, 0.140, 0.128), (1.555, 0.118, 0.110))):
        ring = []
        for i in range(14):
            t = 2 * math.pi * i / 14
            w = 1.0 + (rnd.uniform(-0.07, 0.07) if k == 1 else 0.0)
            ring.append(Vector((math.cos(t) * rx * w, 0.012 + math.sin(t) * ry * w, z + (0.012 if math.sin(t) > 0.3 else 0))))
        fur.append(ring)
    chest.loft(fur, M["fur"], cap_start=False, cap_end=False, inside=(0, 0.012, 1.505))
    chest.loft([sq_ring(0, 0.12, 1.40, 0.13, 0.055, n=10), sq_ring(0, 0.135, 1.48, 0.14, 0.07, n=10),
                sq_ring(0, 0.13, 1.56, 0.11, 0.06, n=10), sq_ring(0, 0.12, 1.60, 0.05, 0.03, n=10)], P)
    # ---- neck + head ----------------------------------------------------------------------------------
    H.tube(mb("Neck"), [(0, 0.005, 1.46), (0, 0.005, 1.57)], [0.052, 0.050], 8, M["skin"], cap_end=False)
    hd = mb("Head")
    hd.blob((0, 0.004, 1.628), (0.083, 0.098, 0.114), M["skin"], subdiv=2, jitter=0.0)
    # jaw/cheeks a little narrower: squash via a second small blob for the chin
    hd.blob((0, -0.03, 1.555), (0.055, 0.05, 0.04), M["beard"], subdiv=1, jitter=0.0)
    hd.box((-0.012, -0.112, 1.60), (0.012, -0.090, 1.636), M["skin"])                       # nose
    for sx in (-1, 1):
        x = sx * 0.036
        hd.poly([(x - 0.013, -0.0935, 1.646), (x + 0.013, -0.0935, 1.646), (x + 0.013, -0.0935, 1.662),
                 (x - 0.013, -0.0935, 1.662)], M["eyes"], facing=(0, -1, 0))
        hd.box((x - 0.02, -0.098, 1.668), (x + 0.02, -0.084, 1.678), M["beard"])             # brows
    # beanie with a folded cuff
    hd.loft([sq_ring(0, 0.004, 1.648, 0.092, 0.107, n=14, p=2.0), sq_ring(0, 0.004, 1.690, 0.094, 0.109, n=14, p=2.0),
             sq_ring(0, 0.004, 1.705, 0.090, 0.105, n=14, p=2.0), sq_ring(0, 0.004, 1.745, 0.080, 0.094, n=14, p=2.0),
             sq_ring(0, 0.004, 1.775, 0.055, 0.066, n=14, p=2.0), [Vector((0, 0.004, 1.79))]], M["beanie"],
            cap_start=True, cap_end=False)
    # ---- arms (T-pose along +-X) -----------------------------------------------------------------------
    for s, side in ((1, "Left"), (-1, "Right")):
        ua, la, hn = (j[side + k] for k in ("UpperArm", "LowerArm", "Hand"))
        sh = mb(side + "Shoulder")
        sh.loft([yz_ring(s * 0.10, 0.0, 1.405, 0.105, 0.085), yz_ring(s * 0.19, 0.0, 1.40, 0.095, 0.090),
                 yz_ring(s * 0.26, 0.0, 1.405, 0.085, 0.084)], P, cap_start=False, cap_end=False)
        um = mb(side + "UpperArm")
        um.loft([yz_ring(s * 0.19, 0.0, 1.405, 0.088, 0.086), yz_ring(s * 0.34, 0.0, 1.425, 0.080, 0.080),
                 yz_ring(la.x + s * 0.03, 0.0, 1.435, 0.072, 0.072)], P, cap_start=False, cap_end=False)
        lm = mb(side + "LowerArm")
        lm.loft([yz_ring(la.x - s * 0.04, 0.0, 1.435, 0.072, 0.072), yz_ring(la.x + s * 0.12, 0.0, 1.44, 0.066, 0.064),
                 yz_ring(hn.x - s * 0.03, 0.0, 1.44, 0.062, 0.060)], P, cap_start=False, cap_end=True)
        lm.loft([yz_ring(hn.x - s * 0.055, 0.0, 1.44, 0.058, 0.056), yz_ring(hn.x + s * 0.005, 0.0, 1.44, 0.056, 0.054)],
                M["dark"], cap_start=False, cap_end=True)                                       # knit cuff
        hm = mb(side + "Hand")
        hm.loft([yz_ring(hn.x - s * 0.01, 0.0, 1.44, 0.042, 0.036, n=8), yz_ring(hn.x + s * 0.05, -0.004, 1.438, 0.048, 0.030, n=8),
                 yz_ring(hn.x + s * 0.095, -0.006, 1.434, 0.040, 0.024, n=8)], M["glove"])
        H.tube(hm, [(hn.x + s * 0.02, -0.03, 1.44), (hn.x + s * 0.05, -0.065, 1.44)], [0.018, 0.015], 6, M["glove"])
        # ---- legs ----------------------------------------------------------------------------------------
        x = j[side + "UpperLeg"].x
        ul = mb(side + "UpperLeg")
        ul.loft([sq_ring(x, 0.0, 0.95, 0.090, 0.098, n=10, p=2.2), sq_ring(x, -0.004, 0.72, 0.082, 0.090, n=10, p=2.2),
                 sq_ring(x, 0.0, 0.47, 0.070, 0.078, n=10, p=2.2)], M["pants"], cap_start=False, cap_end=True)
        ll = mb(side + "LowerLeg")
        ll.loft([sq_ring(x, 0.0, 0.53, 0.070, 0.077, n=10, p=2.2), sq_ring(x, 0.004, 0.36, 0.062, 0.068, n=10, p=2.2),
                 sq_ring(x, 0.006, 0.31, 0.060, 0.066, n=10, p=2.2)], M["pants"], cap_start=False, cap_end=True)
        ll.loft([sq_ring(x, 0.008, 0.285, 0.068, 0.074, n=10, p=2.2), sq_ring(x, 0.008, 0.335, 0.071, 0.077, n=10, p=2.2)],
                M["sock"], cap_start=True, cap_end=True)                                          # sock cuff
        ll.loft([sq_ring(x, 0.012, 0.09, 0.060, 0.070, n=10, p=2.4), sq_ring(x, 0.010, 0.20, 0.063, 0.070, n=10, p=2.4),
                 sq_ring(x, 0.008, 0.292, 0.066, 0.072, n=10, p=2.4)], M["boots"], cap_start=False, cap_end=True)
        heel_y, ball_y, tip_y = j[side + "Heel"].y, j[side + "Ball"].y, j[side + "TipSole"].y
        ft = mb(side + "Foot")
        ft.loft([lp.rrect((x, heel_y, 0.075), 0.056, 0.075, 0.03, 'XZ'),
                 lp.rrect((x, 0.0, 0.07), 0.061, 0.070, 0.03, 'XZ'),
                 lp.rrect((x, ball_y + 0.01, 0.052), 0.061, 0.052, 0.025, 'XZ')], M["boots"])
        ft.box((x - 0.058, heel_y - 0.075, 0.0), (x + 0.058, heel_y + 0.002, 0.03), M["sole"])
        tt = mb(side + "Toes")
        tt.loft([lp.rrect((x, ball_y + 0.03, 0.047), 0.060, 0.047, 0.022, 'XZ'),
                 lp.rrect((x, ball_y - 0.05, 0.045), 0.058, 0.045, 0.022, 'XZ'),
                 lp.rrect((x, tip_y + 0.012, 0.035), 0.048, 0.035, 0.02, 'XZ'),
                 lp.rrect((x, tip_y, 0.028), 0.036, 0.028, 0.015, 'XZ')], M["boots"])
    return parts


def backpack_parts(M):
    """Outfit_backpack_m on Chest: rounded pack body, lid, front pocket, bedroll, shoulder straps."""
    mb = lp.MeshBuilder()
    # body: loft of rounded rectangles (axis Z), slight taper
    body = [lp.rrect((0, 0.255, 0.96), 0.155, 0.095, 0.05), lp.rrect((0, 0.26, 1.00), 0.172, 0.108, 0.06),
            lp.rrect((0, 0.262, 1.30), 0.178, 0.112, 0.06), lp.rrect((0, 0.258, 1.46), 0.165, 0.104, 0.06),
            lp.rrect((0, 0.25, 1.50), 0.14, 0.085, 0.05)]
    mb.loft(body, M["pack"])
    # lid flap
    mb.loft([lp.rrect((0, 0.262, 1.43), 0.182, 0.118, 0.06), lp.rrect((0, 0.262, 1.52), 0.170, 0.110, 0.06),
             lp.rrect((0, 0.258, 1.545), 0.14, 0.09, 0.05)], M["pack_dark"])
    # front (back-facing) pocket and side pockets
    mb.loft([lp.rrect((0, 0.36, 1.02), 0.115, 0.035, 0.025), lp.rrect((0, 0.37, 1.20), 0.118, 0.038, 0.025),
             lp.rrect((0, 0.362, 1.24), 0.11, 0.03, 0.02)], M["pack_dark"])
    for sx in (-1, 1):
        mb.loft([lp.rrect((sx * 0.19, 0.26, 1.02), 0.03, 0.07, 0.02), lp.rrect((sx * 0.195, 0.26, 1.18), 0.03, 0.07, 0.02)],
                M["pack_dark"])
        # shoulder straps: from the pack top over the shoulder down the chest
        pts = [(sx * 0.09, 0.16, 1.42), (sx * 0.10, 0.07, 1.505), (sx * 0.11, -0.06, 1.47), (sx * 0.11, -0.165, 1.36),
               (sx * 0.105, -0.168, 1.20)]
        H.tube(mb, pts, [(0.010, 0.022)] * 5, 4, M["pack_dark"], cap_end=True, cap_start=True)
    # bedroll across the top
    mb.cylinder((-0.21, 0.27, 1.60), (0.21, 0.27, 1.60), 0.072, 0.072, 12, M["roll"])
    for sx in (-1, 1):
        mb.cylinder((sx * 0.12 - 0.012, 0.27, 1.60), (sx * 0.12 + 0.012, 0.27, 1.60), 0.076, 0.076, 12, M["strap"])
    return {"Chest": mb}


def colours(variant):
    return dict(parka=VARIANTS[variant], dark="pack_dark", pants="pants_dark", fur="fur", skin="skin_hd",
                beard="beard", eyes="eyes_dark", beanie="beanie", glove="glove", sock="sock", boots="boots_brown",
                sole="boots", pack="pack", pack_dark="pack_dark", strap="strap", roll="mat_roll")


def blend_skirt(body):
    """Parka skirt below the hips follows the legs: w = smoothstep(0.90 -> 0.64) * side factor, Hips keeps 1-w."""
    vg = {g.name: g for g in body.vertex_groups}
    hips = vg["Hips"]
    changed = 0
    for v in body.data.vertices:
        gs = [(body.vertex_groups[g.group].name, g.weight) for g in v.groups]
        if len(gs) != 1 or gs[0][0] != "Hips":
            continue
        co = v.co
        if co.z > 0.90:
            continue
        w = H.smoothstep(0.90, 0.64, co.z) * 0.7 * H.smoothstep(0.0, 0.07, abs(co.x))
        if w <= 1e-3:
            continue
        leg = "LeftUpperLeg" if co.x > 0 else "RightUpperLeg"
        hips.add([v.index], 1.0 - w, 'REPLACE')
        vg[leg].add([v.index], w, 'REPLACE')
        changed += 1
    return changed


def build(variant):
    H.new_scene()
    arm = rig.build_armature()
    M = colours(variant)
    body = rig.skin_rigid(build_parts(M), arm, "Body")
    moved = blend_skirt(body)
    pack = rig.skin_rigid(backpack_parts(M), arm, "Outfit_backpack_m")
    for o in (body, pack):
        H.smooth(o, angle=55)
    problems = rig.check_armature(arm) + rig.check_rigid_skin(pack)
    if problems:
        raise RuntimeError("; ".join(problems))
    H.bake_ao([body, pack], distance=0.25, samples=64, ground=True)
    glb, tris, surf, per = H.export_hd("survivor_hd_" + variant, SUB)
    H.write_manifest_entry("survivor_hd_" + variant, {
        "file": "chars/survivor_hd_%s.glb" % variant, "replaces": "assets/models/chars/survivor_*.glb",
        "tris": tris, "parts": per, "skeleton": "identical to survivor_*.glb (lib/rig.py, 27 bones)",
        "import": "char template (.import next to the .glb): BoneMap res://assets/hd/rig/humanoid_bonemap.tres -> "
                  "GeneralSkeleton; plays anims/humanoid_loco.glb", "skirt_blend_vertices": moved,
        "outfits": ["Outfit_backpack_m"]})
    return glb, tris


def write_godot_import(glb):
    """.import for the look-dev project: same 'char' template as the game, BoneMap inside assets/hd/rig/."""
    text = H.export.import_file_text("char").replace(H.export.BONEMAP_RES, "res://assets/hd/rig/humanoid_bonemap.tres")
    with open(glb + ".import", "w") as f:
        f.write(text)


def main():
    rig.write_bonemap(os.path.join(H.OUT_DIR, "rig", "humanoid_bonemap.tres"))
    out = []
    for v in VARIANTS:
        glb, tris = build(v)
        write_godot_import(glb)
        out.append((v, tris))
    return out


if __name__ == "__main__":
    main()
