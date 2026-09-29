"""wolf, deer (slice ASSET_SPEC §4.2-4.3; ASSET_SPEC_V2 §5.3/§17). Same rigid-part hierarchy:
Body > Head (> Muzzle), Tail, Leg*. Underside faces (normal z < -0.3) get the belly colour.

Written in the slice convention (+Y front, left = -X) and built with new_scene(authored_front="+Y"): the
exported animals face -Y (MODEL_FRONT), Muzzle at y < 0, LegFL/BL (the animal's left) at +X."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402,F401  (must precede mathutils)
from mathutils import Vector  # noqa: E402

from lib import export  # noqa: E402
from lib import lowpoly as lp  # noqa: E402


def belly(mb, mat, faces=None, nz=-0.3):
    mb.recolor(lambda n, c, m: n.z < nz and m not in ("eyes", "eyes_dark", "wood_light", "wood_dark"),
               mat, faces)


def leg(mb, top, knee, ankle, foot_y, top_size, bot_size, fur, paw_mat, paw_len):
    """Leg as a 3-ring loft (4-sided) from the hip/shoulder down to the ankle, plus a paw/hoof box."""
    def sq(c, s):
        c = Vector(c)
        return [c + Vector((-s[0] / 2, -s[1] / 2, 0)), c + Vector((s[0] / 2, -s[1] / 2, 0)),
                c + Vector((s[0] / 2, s[1] / 2, 0)), c + Vector((-s[0] / 2, s[1] / 2, 0))]
    mid_size = ((top_size[0] + bot_size[0]) / 2, (top_size[1] + bot_size[1]) / 2)
    mb.loft([sq(top, top_size), sq(knee, mid_size), sq(ankle, bot_size)], fur, cap_start=True,
            cap_end=False)
    ax, ay, az = ankle
    hw = bot_size[0] * 0.55
    mb.box((ax - hw, foot_y - paw_len * 0.35, 0.0), (ax + hw, foot_y + paw_len * 0.65, az), paw_mat)


def eye_quads(mb, pts_list, mat, facing):
    for pts in pts_list:
        mb.poly(pts, mat, facing=facing)


# ------------------------------------------------------------------------------------------------
def build_wolf():
    lp.new_scene(authored_front="+Y")
    fur, pale = "wolf_fur", "wolf_belly"
    # Body: tapered, deepest at the chest, tucked belly; 0.36 wide, y -0.45..0.45, z 0.36..0.74
    body = lp.MeshBuilder()
    rings = [lp.body_ring(-0.45, 0.12, 0.47, 0.67, 0.05),
             lp.body_ring(-0.30, 0.16, 0.43, 0.70, 0.07),
             lp.body_ring(0.00, 0.165, 0.45, 0.715, 0.07),
             lp.body_ring(0.28, 0.18, 0.36, 0.74, 0.08),
             lp.body_ring(0.45, 0.16, 0.42, 0.73, 0.07)]
    body.loft(rings, fur)
    # neck ruff: a wedge of fur over the shoulders
    body.hexa([(-0.17, 0.25, 0.60), (0.17, 0.25, 0.60), (-0.15, 0.50, 0.55), (0.15, 0.50, 0.55),
               (-0.14, 0.22, 0.74), (0.14, 0.22, 0.74), (-0.12, 0.52, 0.76), (0.12, 0.52, 0.76)], fur)
    belly(body, pale)
    bo = lp.to_object(body, "Body", (0, 0, 0.55))

    # Head: skull y 0.45..0.75 z 0.50..0.74, snout y 0.75..0.93 z 0.50..0.64, ears, eyes, nose
    head = lp.MeshBuilder()
    skull = [(-0.12, 0.45, 0.50), (0.12, 0.45, 0.50), (-0.11, 0.75, 0.52), (0.11, 0.75, 0.52),
             (-0.12, 0.45, 0.74), (0.12, 0.45, 0.74), (-0.10, 0.75, 0.72), (0.10, 0.75, 0.72)]
    head.hexa(skull, fur)
    snout = [(-0.07, 0.745, 0.50), (0.07, 0.745, 0.50), (-0.05, 0.93, 0.525), (0.05, 0.93, 0.525),
             (-0.07, 0.745, 0.66), (0.07, 0.745, 0.66), (-0.05, 0.93, 0.625), (0.05, 0.93, 0.625)]
    sf = head.hexa(snout, fur)
    for fi in sf:
        if head.normal(fi).y > 0.9:
            head.faces[fi][1] = pale                      # snout front
    for sx in (-1, 1):                                    # ear pyramids, 0.08 tall at x +-0.08, y 0.55
        cx = sx * 0.08
        base = [Vector((cx - 0.04, 0.52, 0.735)), Vector((cx + 0.04, 0.52, 0.735)),
                Vector((cx + 0.04, 0.59, 0.73)), Vector((cx - 0.04, 0.59, 0.73))]
        head.loft([base, [Vector((cx + sx * 0.01, 0.56, 0.82))]], fur, cap_start=False)
    eye_quads(head, [[(sx * 0.06 - 0.02, 0.751, 0.665), (sx * 0.06 + 0.02, 0.751, 0.665),
                      (sx * 0.06 + 0.02, 0.751, 0.705), (sx * 0.06 - 0.02, 0.751, 0.705)] for sx in (-1, 1)],
              "eyes", (0, 1, 0))
    head.poly([(-0.025, 0.931, 0.585), (0.025, 0.931, 0.585), (0.025, 0.931, 0.62), (-0.025, 0.931, 0.62)],
              "eyes_dark", facing=(0, 1, 0))
    belly(head, pale)
    ho = lp.to_object(head, "Head", (0, 0.45, 0.62), parent=bo)
    lp.add_empty("Muzzle", (0, 0.93, 0.58), parent=ho)

    # Tail: bushy, drooping from (0,-0.45,0.62) to the tip at y -0.90, z 0.45; pale tip
    tail = lp.MeshBuilder()
    path = [Vector((0, -0.42, 0.64)), Vector((0, -0.58, 0.60)), Vector((0, -0.76, 0.52)),
            Vector((0, -0.86, 0.47))]
    radii = [0.045, 0.065, 0.055, 0.035]
    trings = []
    for i, (p, r) in enumerate(zip(path, radii)):
        a = (path[min(i + 1, 3)] - path[max(i - 1, 0)])
        trings.append(lp.ring(p, a, r, 6, 0))
    trings.append([Vector((0, -0.91, 0.44))])
    tail.loft(trings, fur, cap_start=True, side_mats=[fur, fur, pale, pale])
    lp.to_object(tail, "Tail", (0, -0.45, 0.62), parent=bo)

    # Legs: pivots (+-0.13, +-0.30, 0.42), 0.10 x 0.12 down to z 0
    for name, sx, sy in (("LegFL", -1, 1), ("LegFR", 1, 1), ("LegBL", -1, -1), ("LegBR", 1, -1)):
        lm = lp.MeshBuilder()
        x, y = sx * 0.13, sy * 0.30
        if sy > 0:   # front: straight
            leg(lm, (x, y, 0.46), (x, y + 0.01, 0.24), (x, y + 0.01, 0.05), y + 0.02, (0.11, 0.14),
                (0.075, 0.085), fur, pale, 0.12)
        else:        # back: thigh back, hock
            leg(lm, (x, y, 0.46), (x, y - 0.06, 0.22), (x, y - 0.02, 0.05), y, (0.12, 0.16),
                (0.075, 0.085), fur, pale, 0.12)
        lp.to_object(lm, name, (x, y, 0.42), parent=bo)
    export.save_and_export("wolf")


# ------------------------------------------------------------------------------------------------
def build_deer():
    lp.new_scene(authored_front="+Y")
    fur, pale = "deer_fur", "deer_belly"
    body = lp.MeshBuilder()
    rings = [lp.body_ring(-0.55, 0.15, 0.82, 1.09, 0.06),
             lp.body_ring(-0.38, 0.19, 0.74, 1.13, 0.08),
             lp.body_ring(0.10, 0.185, 0.73, 1.11, 0.08),
             lp.body_ring(0.45, 0.20, 0.72, 1.15, 0.08),
             lp.body_ring(0.65, 0.15, 0.84, 1.12, 0.06)]
    body.loft(rings, fur)
    belly(body, pale)
    bo = lp.to_object(body, "Body", (0, 0, 0.90))

    head = lp.MeshBuilder()
    # neck rising from (0,0.60,0.95) to (0,0.85,1.35)
    n0, n1 = Vector((0, 0.58, 0.97)), Vector((0, 0.83, 1.36))
    head.loft([lp.ring(n0, n1 - n0, (0.11, 0.09), 6, 0), lp.ring(n1, n1 - n0, (0.08, 0.07), 6, 0)], fur,
              cap_start=False, cap_end=False)
    # head box 0.20 x 0.30 (y 0.75..1.05), z 1.25..1.47, tapering to the muzzle
    hb = head.hexa([(-0.10, 0.75, 1.26), (0.10, 0.75, 1.26), (-0.06, 1.05, 1.28), (0.06, 1.05, 1.28),
                    (-0.10, 0.75, 1.47), (0.10, 0.75, 1.47), (-0.055, 1.05, 1.38), (0.055, 1.05, 1.38)], fur)
    for k in hb:
        if head.normal(k).y > 0.9:
            head.faces[k][1] = pale
    # ears: flat leaves pointing out-up
    for sx in (-1, 1):
        e0 = Vector((sx * 0.08, 0.79, 1.42))
        e1 = Vector((sx * 0.21, 0.72, 1.46))
        head.loft([lp.ring(e0, e1 - e0, (0.045, 0.014), 4, 0), [e1]], fur, cap_start=False)
    # antlers: two branched beams (3 segments each), wood_light, tips at z ~1.65
    for sx in (-1, 1):
        b0 = Vector((sx * 0.05, 0.82, 1.46))
        b1 = Vector((sx * 0.12, 0.78, 1.56))
        b2 = Vector((sx * 0.21, 0.72, 1.65))
        t1 = Vector((sx * 0.11, 0.88, 1.64))
        head.cylinder(b0, b1, 0.02, 0.016, 4, "wood_light", cap0=False, cap1=False, phase=45)
        head.cylinder(b1 - (b1 - b0).normalized() * 0.01, b2, 0.016, 0.0, 4, "wood_light", cap0=False, phase=45)
        head.cylinder(b1, t1, 0.014, 0.0, 4, "wood_light", cap0=False, phase=45)
    for sx in (-1, 1):                     # eyes on the sides of the head
        head.poly([(sx * 0.093, 0.86, 1.39), (sx * 0.093, 0.90, 1.39), (sx * 0.089, 0.90, 1.425),
                   (sx * 0.089, 0.86, 1.425)], "eyes", facing=(sx, 0, 0))
    head.poly([(-0.03, 1.051, 1.315), (0.03, 1.051, 1.315), (0.03, 1.051, 1.36), (-0.03, 1.051, 1.36)],
              "eyes_dark", facing=(0, 1, 0))
    belly(head, pale)
    ho = lp.to_object(head, "Head", (0, 0.60, 1.00), parent=bo)
    lp.add_empty("Muzzle", (0, 1.05, 1.35), parent=ho)

    tail = lp.MeshBuilder()
    tail.hexa([(-0.045, -0.53, 1.02), (0.045, -0.53, 1.02), (-0.035, -0.64, 0.98), (0.035, -0.64, 0.98),
               (-0.045, -0.53, 1.10), (0.045, -0.53, 1.10), (-0.035, -0.64, 1.06), (0.035, -0.64, 1.06)], pale)
    lp.to_object(tail, "Tail", (0, -0.55, 1.06), parent=bo)

    for name, sx, sy in (("LegFL", -1, 1), ("LegFR", 1, 1), ("LegBL", -1, -1), ("LegBR", 1, -1)):
        lm = lp.MeshBuilder()
        x, y = sx * 0.14, sy * 0.42
        if sy > 0:
            leg(lm, (x, y, 0.80), (x, y + 0.01, 0.40), (x, y, 0.06), y + 0.01, (0.10, 0.13), (0.06, 0.07),
                fur, "wood_dark", 0.09)
        else:
            leg(lm, (x, y, 0.80), (x, y - 0.08, 0.38), (x, y - 0.02, 0.06), y - 0.01, (0.11, 0.16),
                (0.06, 0.07), fur, "wood_dark", 0.09)
        lp.to_object(lm, name, (x, y, 0.70), parent=bo)
    export.save_and_export("deer")


def main():
    build_wolf()
    build_deer()


if __name__ == "__main__":
    main()
