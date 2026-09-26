"""campfire, torch, lantern (slice ASSET_SPEC §4.12, 4.14, 4.21; ASSET_SPEC_V2 §17). No front: authored
in the final orientation (no front turn). Torch: weapon convention (grip at the origin, handle +Z). Lantern:
glass = material `window` (second surface), LightAnchor unchanged."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402,F401  (must precede mathutils)
from mathutils import Vector  # noqa: E402

from lib import export  # noqa: E402
from lib import hd as H  # noqa: E402
from lib import lowpoly as lp  # noqa: E402


def build_campfire():
    lp.new_scene()
    rnd = lp.rng(9)
    stones = lp.MeshBuilder()
    for i in range(8):
        a = 2 * math.pi * i / 8 + rnd.uniform(-0.12, 0.12)
        r = rnd.uniform(0.12, 0.145)
        rr = 0.48 + rnd.uniform(-0.015, 0.015)
        stones.blob((rr * math.cos(a), rr * math.sin(a), 0.02), (r * 1.1, r, r * 0.8), "stone", subdiv=0,
                    jitter=0.12, rnd=rnd, clamp_z=0.0, drop_bottom=True)
    lp.stone_rule(stones, snow=0.85, dark=-0.2)
    # charred ground inside the ring
    stones.poly(lp.ring((0, 0, 0.006), (0, 0, 1), 0.33, 8, 10), "iron", facing=(0, 0, 1))
    lp.to_object(stones, "Stones")

    logs = lp.MeshBuilder()
    elev = math.radians(25)
    for k in range(4):
        a = math.radians(45 + 90 * k + rnd.uniform(-8, 8))
        out = Vector((math.cos(a), math.sin(a), 0))
        p0 = out * 0.40 + Vector((0, 0, 0.06))
        d = -out * math.cos(elev) + Vector((0, 0, math.sin(elev)))
        p1 = p0 + d * 0.6
        faces = logs.cylinder(p0, p1, 0.07, 0.065, 6, "bark", cap_mats=("wood_light", "wood_light"),
                              phase=rnd.uniform(0, 60))
    lp.clamp_ground(logs)
    lp.to_object(logs, "Logs")
    lp.add_empty("FlameAnchor", (0, 0, 0.18))
    export.save_and_export("campfire")


def build_torch():
    lp.new_scene()
    handle = lp.MeshBuilder()
    handle.cylinder((0, 0, 0), (0, 0, 0.42), 0.025, 0.027, 6, "wood")
    lp.to_object(handle, "Handle")
    head = lp.MeshBuilder()
    head.cylinder((0, 0, 0.38), (0, 0, 0.52), 0.05, 0.058, 8, "cloth", cap_mats=("cloth", "iron"),
                  phase=22.5)
    # a wrap band around the cloth head
    head.cylinder((0, 0, 0.425), (0, 0, 0.455), 0.058, 0.06, 8, "wood_dark", phase=22.5)
    lp.to_object(head, "Head")
    lp.add_empty("FlameAnchor", (0, 0, 0.54))
    export.save_and_export("torch", ao=dict(ground=False))  # hand-held (v2.1 AO)


def build_lantern():
    """lantern (slice §4.21, v2 §17; HD v2.1 in M3): ONE object `Lantern` (palette_vcol + `window` glass, which the
    code swaps for its glow material at night) hanging from its hook ring (top at z = 0), LightAnchor (0, 0, -0.23).
    HD: chamfered base and top plate, pyramid roof with a brass vent, corner posts, two wire guard bands around the
    glass, round hook ring."""
    lp.new_scene()
    hard, fine = lp.MeshBuilder(), lp.MeshBuilder()
    # hook ring (torus in the XZ plane), top of the tube at z = 0
    n, m, R, r = 10, 4, 0.021, 0.006
    cz = -R - r
    idx = []
    for k in range(n):
        a_ = 2 * math.pi * k / n
        rad = Vector((math.cos(a_), 0, math.sin(a_)))
        idx.append([fine._v(Vector((0, 0, cz)) + rad * R + (rad * math.cos(2 * math.pi * j / m + 0.785) +
                                                             Vector((0, 1, 0)) * math.sin(2 * math.pi * j / m + 0.785)) * r)
                    for j in range(m)])
    for k in range(n):
        a_, b_ = idx[k], idx[(k + 1) % n]
        for j in range(m):
            q = (a_[j], a_[(j + 1) % m], b_[(j + 1) % m], b_[j])
            c = sum((fine.verts[i] for i in q), Vector()) / 4
            ang = 2 * math.pi * (k + 0.5) / n
            core = Vector((0, 0, cz)) + Vector((math.cos(ang), 0, math.sin(ang))) * R
            fine.add_face(q, "iron", facing=c - core)
    # vent (brass) + pyramid roof + top plate
    fine.cylinder((0, 0, -0.075), (0, 0, -0.050), 0.026, 0.022, 8, "brass", cap0=False, phase=22.5)
    hard.loft([[Vector((x, y, -0.088)) for x, y in ((-0.105, -0.105), (0.105, -0.105), (0.105, 0.105), (-0.105, 0.105))],
               [Vector((x, y, -0.062)) for x, y in ((-0.035, -0.035), (0.035, -0.035), (0.035, 0.035), (-0.035, 0.035))]],
              "iron", cap_start=False, cap_end=True)
    hard.box((-0.105, -0.105, -0.103), (0.105, 0.105, -0.088), "iron")
    # glass (window material), corner posts, wire guards
    fine.box((-0.082, -0.082, -0.352), (0.082, 0.082, -0.103), "window")
    for sx in (-1, 1):
        for sy in (-1, 1):
            fine.box((sx * 0.085 - 0.011, sy * 0.085 - 0.011, -0.36), (sx * 0.085 + 0.011, sy * 0.085 + 0.011, -0.103),
                     "iron")
    for z in (-0.19, -0.27):
        for (x0, y0, x1, y1) in ((-0.085, -0.090, 0.085, -0.084), (-0.085, 0.084, 0.085, 0.090),
                                 (-0.090, -0.085, -0.084, 0.085), (0.084, -0.085, 0.090, 0.085)):
            fine.box((x0, y0, z - 0.004), (x1, y1, z + 0.004), "iron")
    # base with a brass trim band
    hard.box((-0.10, -0.10, -0.40), (0.10, 0.10, -0.36), "iron")
    fine.box((-0.102, -0.102, -0.372), (0.102, 0.102, -0.364), "brass")
    body = H.mk(hard)
    H.bevel(body, 0.006, 1, angle=30)
    H.snap_colors(body)
    H.join([body, H.flat(H.mk(fine))], "Lantern")
    lp.add_empty("LightAnchor", (0, 0, -0.23))
    export.save_and_export("lantern", ao=dict(ground=False, distance=0.12, samples=48))  # hangs from its hook


def main():
    build_campfire()
    build_torch()
    build_lantern()


if __name__ == "__main__":
    main()
