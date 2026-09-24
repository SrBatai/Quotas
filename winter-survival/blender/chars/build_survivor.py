"""Skeletal survivor (player) — ASSET_SPEC_V2 §4, §5.1, milestone M1.

    cd winter-survival/blender && python3 chars/build_survivor.py

Exports assets/models/chars/survivor_{red,blue,green,mustard}.glb (+ sources/survivor_<variant>.blend and the
Godot `.import` next to each .glb, template lib/export.py kind "char"). Each file:

    Armature (27 bones: 22 SkeletonProfileHumanoid names + RightHandSocket, LeftHandSocket, BackSocket,
    │         HipSocketR, HeadSocket; T-pose rest, front -Y Blender = +Z Godot)
    └─ Body  one mesh, one surface `palette_vcol` (colour in COLOR_0), rigid skin: every vertex 100 % on
             the bone its part was built for (rig.skin_rigid); no animations (they live in anims/*.glb)

Look = the slice player (build_player.py) on the v2 skeleton: puffy quilted jacket (three bands on Hips /
Spine / Chest: the pinch lines hide the rigid seams), beanie with a snow-white pompom, scarf with a tail,
mittens, navy trousers, dark boots with a fur cuff, boxy skin head with two eye quads and a nose.
Variants (§5.1): jacket jacket / jacket_blue / jacket_green / jacket_mustard, beanie in a contrasting colour;
the mustard variant also swaps the (mustard) scarf + mittens for red so they do not melt into the jacket.
Contact geometry: boot heels end exactly at rig Heel (y +0.10, z 0), the toe box sole at z 0 from the ball
(y -0.10) to the tip (y -0.20): the gait generator pivots the feet on these points.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import bpy  # noqa: E402,F401  (must precede mathutils)
from mathutils import Vector  # noqa: E402

from lib import export  # noqa: E402
from lib import lowpoly as lp  # noqa: E402
from lib import rig  # noqa: E402

VARIANTS = {
    "red": dict(jacket="jacket", hat="hat", scarf="scarf"),
    "blue": dict(jacket="jacket_blue", hat="hivis_orange", scarf="scarf"),
    "green": dict(jacket="jacket_green", hat="jacket", scarf="scarf"),
    "mustard": dict(jacket="jacket_mustard", hat="hat", scarf="jacket"),
}
FIXED = dict(pants="hat", zip="hat", skin="skin", eyes="eyes_dark", boots="boots", cuff="cloth", pompom="snow")
SUBDIR = "chars"
BUDGET = 1500


def band(mb, z0, z1, a, b, mat, inset=0.018, ch=0.07, caps=(True, True), y=0.0):
    """Quilted puffy band: pinched edges, fat middle (8-point chamfered rings)."""
    zm = 0.5 * (z0 + z1)
    rings = [lp.rrect((0, y, z0), a - inset, b - inset, ch), lp.rrect((0, y, zm), a, b, ch),
             lp.rrect((0, y, z1), a - inset, b - inset, ch)]
    return mb.loft(rings, mat, cap_start=caps[0], cap_end=caps[1])


def build_parts(M, p=None):
    """{deforming bone: MeshBuilder} in rest-pose world coordinates (T-pose, front -Y)."""
    j = rig.joints(p)
    parts = {}

    def mb(bone):
        return parts.setdefault(bone, lp.MeshBuilder())

    # ---- pelvis (Hips): trouser seat + lowest jacket band (flared hem) ----------------------------
    hips = mb("Hips")
    hips.loft([lp.rrect((0, 0.005, 0.745), 0.170, 0.120, 0.05), lp.rrect((0, 0.005, 0.845), 0.195, 0.135, 0.05),
               lp.rrect((0, 0.0, 1.00), 0.19, 0.13, 0.05)], M["pants"])
    hips.loft([lp.rrect((0, 0.0, 0.815), 0.256, 0.180, 0.07), lp.rrect((0, 0.0, 0.905), 0.272, 0.192, 0.075),
               lp.rrect((0, 0.0, 0.995), 0.254, 0.175, 0.07)], M["jacket"])
    # ---- jacket middle band (Spine) and chest band + shoulder dome (Chest) -----------------------
    band(mb("Spine"), 0.985, 1.205, 0.272, 0.190, M["jacket"])
    ch = mb("Chest")
    ch.loft([lp.rrect((0, 0.0, 1.195), 0.252, 0.172, 0.07), lp.rrect((0, 0.0, 1.300), 0.264, 0.182, 0.075),
             lp.rrect((0, 0.0, 1.395), 0.246, 0.170, 0.07), lp.rrect((0, 0.0, 1.450), 0.198, 0.140, 0.06),
             lp.rrect((0, 0.005, 1.485), 0.120, 0.100, 0.04)], M["jacket"])
    # zip placket down the front of the three bands (navy, as the slice player)
    for bone, z0, z1, yb in (("Hips", 0.83, 0.99, -0.193), ("Spine", 0.995, 1.195, -0.191),
                             ("Chest", 1.205, 1.40, -0.183)):
        mb(bone).box((-0.013, yb - 0.012, z0), (0.013, yb + 0.02, z1), M["zip"], skip=('+y',))
    # scarf: collar ring + a tail over the left chest
    ch.loft([lp.rrect((0, 0.0, 1.405), 0.160, 0.150, 0.06), lp.rrect((0, 0.0, 1.455), 0.168, 0.158, 0.06),
             lp.rrect((0, 0.0, 1.515), 0.150, 0.140, 0.055)], M["scarf"])
    ch.hexa([(0.035, -0.184, 1.13), (0.105, -0.184, 1.14), (0.035, -0.160, 1.13), (0.105, -0.160, 1.14),
             (0.025, -0.197, 1.43), (0.095, -0.197, 1.43), (0.025, -0.160, 1.43), (0.095, -0.160, 1.43)],
            M["scarf"])
    ch.box((0.030, -0.192, 1.095), (0.110, -0.174, 1.135), M["scarf"])                 # fringe
    # ---- neck + head -----------------------------------------------------------------------------
    rig.limb(mb("Neck"), (0, 0.0, 1.46), (0, 0.0, 1.56), (0.06, 0.06), (0.055, 0.055), M["skin"], 0.02)
    hd = mb("Head")
    hd.box((-0.150, -0.140, 1.455), (0.150, 0.140, 1.705), M["skin"])
    hd.box((-0.024, -0.176, 1.535), (0.024, -0.139, 1.583), M["skin"], skip=('+y',))   # nose
    for sx in (-1, 1):                                                                   # eyes on the -Y face
        x = sx * 0.062
        hd.poly([(x - 0.021, -0.1412, 1.595), (x + 0.021, -0.1412, 1.595), (x + 0.021, -0.1412, 1.638),
                 (x - 0.021, -0.1412, 1.638)], M["eyes"], facing=(0, -1, 0))
    # beanie: folded band, tapered crown, pompom
    hd.box((-0.168, -0.158, 1.648), (0.168, 0.158, 1.712), M["hat"])
    hd.tapered_box(1.712, 1.775, (0.322, 0.302), (0.245, 0.225), M["hat"], skip=('-z',))
    hd.blob((0, 0.0, 1.795), 0.05, M["pompom"], subdiv=0, jitter=0.0)
    # ---- arms (T-pose along +-X) ------------------------------------------------------------------
    for s, side in ((1, "Left"), (-1, "Right")):
        ua, la, hn = (j[side + k] for k in ("UpperArm", "LowerArm", "Hand"))
        rig.limb(mb(side + "Shoulder"), (s * 0.085, 0, 1.405), (s * 0.282, 0, 1.405), (0.108, 0.098),
                 (0.100, 0.100), M["jacket"], 0.045)
        um = mb(side + "UpperArm")
        um.loft([rig.ring8(ua + Vector((s * 0.02, 0, 0)), *rig.frame((s, 0, 0))[1:], 0.084, 0.084, 0.03),
                 rig.ring8(ua + Vector((s * 0.15, 0, 0)), *rig.frame((s, 0, 0))[1:], 0.090, 0.090, 0.032),
                 rig.ring8(la + Vector((s * 0.035, 0, 0)), *rig.frame((s, 0, 0))[1:], 0.078, 0.078, 0.028)],
                M["jacket"])
        rig.limb(mb(side + "LowerArm"), la - Vector((s * 0.02, 0, 0)), hn - Vector((s * 0.005, 0, 0)),
                 (0.077, 0.077), (0.071, 0.071), M["jacket"], 0.026)
        hm = mb(side + "Hand")                                                           # mitten + thumb
        rig.limb(hm, hn - Vector((s * 0.03, 0, 0)), hn + Vector((s * 0.115, 0, 0.0)), (0.062, 0.068),
                 (0.052, 0.060), M["scarf"], 0.024)
        hm.cbox(hn + Vector((s * 0.035, -0.066, 0.004)), (0.055, 0.05, 0.05), M["scarf"])
        # ---- legs -----------------------------------------------------------------------------------
        ul, ll, ft = (j[side + k] for k in ("UpperLeg", "LowerLeg", "Foot"))
        x = ul.x
        rig.limb(mb(side + "UpperLeg"), (x, 0.0, 0.965), (x, 0.0, 0.470), (0.102, 0.108), (0.088, 0.093),
                 M["pants"], 0.032)
        lm = mb(side + "LowerLeg")
        rig.limb(lm, (x, 0.0, 0.525), (x, 0.008, 0.255), (0.088, 0.093), (0.080, 0.085), M["pants"], 0.028)
        rig.limb(lm, (x, 0.008, 0.275), (x, 0.022, 0.100), (0.083, 0.088), (0.080, 0.086), M["boots"], 0.026)
        rig.limb(lm, (x, 0.010, 0.215), (x, 0.010, 0.290), (0.104, 0.108), (0.100, 0.104), M["cuff"], 0.035)
        heel_y = j[side + "Heel"].y
        ball_y = j[side + "Ball"].y
        mb(side + "Foot").hexa([(x - 0.076, ball_y, 0.0), (x + 0.076, ball_y, 0.0),
                                (x - 0.076, heel_y, 0.0), (x + 0.076, heel_y, 0.0),
                                (x - 0.072, ball_y, 0.105), (x + 0.072, ball_y, 0.105),
                                (x - 0.074, heel_y - 0.01, 0.165), (x + 0.074, heel_y - 0.01, 0.165)], M["boots"])
        tip = ball_y - 0.10
        mb(side + "Toes").hexa([(x - 0.070, tip, 0.0), (x + 0.070, tip, 0.0),
                                (x - 0.074, ball_y + 0.035, 0.0), (x + 0.074, ball_y + 0.035, 0.0),
                                (x - 0.064, tip + 0.012, 0.060), (x + 0.064, tip + 0.012, 0.060),
                                (x - 0.072, ball_y + 0.035, 0.092), (x + 0.072, ball_y + 0.035, 0.092)],
                               M["boots"])
    return parts


def colours(variant):
    m = dict(FIXED)
    m.update(VARIANTS[variant])
    return m


def build(variant):
    lp.new_scene()
    arm = rig.build_armature()
    body = rig.skin_rigid(build_parts(colours(variant)), arm, "Body")
    problems = rig.check_armature(arm) + rig.check_rigid_skin(body)
    tris = lp.tri_count(body)
    if tris > BUDGET:
        problems.append("tris %d > %d" % (tris, BUDGET))
    if problems:
        raise RuntimeError("survivor_%s: %s" % (variant, "; ".join(problems)))
    name = "survivor_" + variant
    glb = export.save_and_export(name, SUBDIR)
    export.write_import(glb, "char")
    return glb


def main():
    rig.write_bonemap(export.BONEMAP_PATH)
    return [build(v) for v in VARIANTS]


if __name__ == "__main__":
    main()
