"""campsite_remains (ASSET_SPEC_V2 §13 "Suelo" + §18 M3 + "M3") -> assets/models/poi/campsite_remains.glb: the
abandoned camp found in forest clearings ("claros con restos de acampada", PLAN §4.3). The task list calls it
`camp_remains`; the contract name is `campsite_remains`.

    cd winter-survival/blender && python3 poi/build_campsite_remains.py

Layout (~6.2 x 4.8 m, origin at the centre of the set on the ground, no front): a collapsed olive canvas tent held
up at one end by a leaning pole (snow patches on the canvas), a cold fire ring (stones, charred log ends, ash, snow
filling it) with a cooking tripod and a pot, two crates (one intact with a snow cap, one broken open with its lid
leaning against it), a log bench, a dented can, snow mounds.
Nodes: ONE visual mesh `Remains` (one palette_vcol surface: it can also be put in a MultiMesh if the code ignores the
rest), FlameAnchor (centre of the fire ring, like campfire.glb: the ring can be re-lit), Spawn_Container_0 (intact
crate, table "campsite"), Spawn_Loot_0 (broken crate), Spawn_Loot_1 (under the tent), Col*-convcolonly: ColCrate_0,
ColCrate_1, ColBench, ColTent (the raised end).
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import bpy  # noqa: E402,F401  (must precede mathutils)
from mathutils import Matrix, Vector  # noqa: E402

from lib import export  # noqa: E402
from lib import hd as H  # noqa: E402
from lib import lowpoly as lp  # noqa: E402
from lib import veg as V  # noqa: E402

TENT = Vector((-1.35, 0.75, 0.0))
FIRE = Vector((1.05, -0.55, 0.0))
CRATE_A = Vector((2.25, 1.25, 0.0))
CRATE_B = Vector((1.55, 1.75, 0.0))
BENCH = Vector((0.55, -1.75, 0.0))


def rot_about(p, c, deg):
    return Matrix.Rotation(math.radians(deg), 3, 'Z') @ (Vector(p) - c) + c


def tent(parts, rnd):
    """Collapsed A-tent: a closed soft canvas slab draped from a 1.0 m high pole end down to the ground, folds."""
    L, W = 2.5, 2.1
    yaw = 18.0

    def top(u, v):
        lift = max(0.0, 1.0 - u / 1.7) ** 1.25 * 1.05                # pole end (u = 0) still up: an A profile
        ridge = max(0.0, 1.0 - abs(v - W / 2) / (W / 2 * 0.9))
        fold = 0.06 * math.sin(u * 5.1 + v * 2.3) + 0.04 * math.sin(v * 7.0)
        return max(0.06, 0.08 + lift * ridge ** 1.1 + fold * (0.4 + 0.6 * ridge))
    origin = TENT - Vector((L / 2, W / 2, 0.03))            # sunk 3 cm: the rounded lower rim stays under the snow
    o = H.pillow(origin, (1, 0, 0), (0, 1, 0), (0, 0, 1), L, W, 0.3, mat="military_green", nu=8, nv=7, rim=0.10,
                 seed=5, top_fn=top, jitter=0.03, bottom=-0.04, drop_bottom=False, levels=1)
    _apply(o, Matrix.Translation(TENT) @ Matrix.Rotation(math.radians(yaw), 4, 'Z') @ Matrix.Translation(-TENT))
    parts.append(o)
    # the pole holding the up end, a fallen pole, guy line pegs
    pe = rot_about(TENT + Vector((-L / 2 + 0.12, 0.0, 0)), TENT, yaw)
    mb = lp.MeshBuilder()
    H.tube(mb, [pe + Vector((0.06, 0.04, -0.05)), pe + Vector((0.0, 0.0, 1.12))], [0.03, 0.025], 5, "wood",
           cap_end=True)
    q = rot_about(TENT + Vector((0.6, -W / 2 - 0.35, 0.03)), TENT, yaw)
    H.tube(mb, [q, q + Vector((1.1, 0.35, 0.02))], [0.028, 0.026], 5, "wood", cap_end=True, cap_start=True)
    for dx, dy in ((-L / 2 - 0.3, -W / 2 - 0.2), (-L / 2 - 0.3, W / 2 + 0.2), (L / 2 + 0.25, W / 2 + 0.25)):
        c = rot_about(TENT + Vector((dx, dy, 0)), TENT, yaw)
        H.tube(mb, [c - Vector((0, 0, 0.05)), c + Vector((0, 0, 0.14))], [0.018, 0.012], 4, "wood_dark",
               cap_end=True)
    parts.append(H.smooth(H.mk(mb)))
    # snow patches on the collapsed part of the canvas
    zf = V.surface_fn([o])
    for k, (dx, dy, rx, ry) in enumerate(((0.55, 0.1, 0.55, 0.45), (0.15, -0.55, 0.35, 0.3))):
        c = rot_about(TENT + Vector((dx, dy, 0)), TENT, yaw)
        parts.append(H.snow_cap((c.x, c.y, 0), rx, ry, 0.07, zf, seed=10 + k, sides=10, rings=3, droop=0.02))


def _apply(o, m):
    o.data.transform(m)
    o.rotation_euler = (0, 0, 0)
    o.data.update()


def fire_ring(parts, rnd):
    stones = lp.MeshBuilder()
    for i in range(9):
        a = 2 * math.pi * i / 9 + rnd.uniform(-0.12, 0.12)
        r = rnd.uniform(0.11, 0.15)
        rr = 0.52 + rnd.uniform(-0.03, 0.03)
        stones.blob(FIRE + Vector((rr * math.cos(a), rr * math.sin(a), 0.02)), (r * 1.15, r, r * 0.8), "stone",
                    subdiv=1, jitter=0.12, rnd=rnd, clamp_z=0.0, drop_bottom=True)
    V.color_by_normal(stones, range(len(stones.faces)), top="snow", side="stone", under="stone_dark", top_nz=0.9,
                      under_nz=-0.2)
    for v in stones.verts:
        v.z -= 0.02
    parts.append(H.flat(H.mk(stones)))
    ash = lp.MeshBuilder()
    ash.poly(lp.ring(FIRE + Vector((0, 0, 0.01)), (0, 0, 1), 0.42, 10, 8), "stone_dark", facing=(0, 0, 1))
    parts.append(H.flat(H.mk(ash)))
    # charred log ends (dark, burnt tips) crossing the ring, half buried
    logs = lp.MeshBuilder()
    for k in range(3):
        a = math.radians(30 + 120 * k + rnd.uniform(-15, 15))
        d = Vector((math.cos(a), math.sin(a), 0))
        p0 = FIRE + d * 0.5 + Vector((0, 0, 0.05))
        p1 = FIRE - d * 0.05 + Vector((0, 0, 0.08))
        H.tube(logs, [p0, p1], [0.06, 0.05], 6, "bark", cap_end=True, cap_start=True)
        logs.faces[-1][1] = "paint_black"
        for fi in range(len(logs.faces) - 8, len(logs.faces) - 2):       # the 6 sides: burnt near the centre
            if (logs.center(fi) - FIRE).length < 0.22:
                logs.faces[fi][1] = "paint_black"
    parts.append(H.smooth(H.mk(logs), angle=60))
    # cold: a snow heap filling the ring
    parts.append(V.heap(FIRE, 0.36, 0.33, 0.11, seed=3, sides=10, rings=3, sink=0.02, noise=0.1))
    # tripod + pot
    tp = lp.MeshBuilder()
    apex = FIRE + Vector((0.02, 0.0, 1.05))
    for k in range(3):
        a = math.radians(90 + 120 * k)
        foot = FIRE + Vector((math.cos(a) * 0.75, math.sin(a) * 0.75, -0.02))
        H.tube(tp, [foot, apex + Vector((math.cos(a) * 0.04, math.sin(a) * 0.04, 0.08))], [0.025, 0.02], 5, "wood",
               cap_end=True)
    tp.box(apex + Vector((-0.004, -0.004, -0.55)), apex + Vector((0.004, 0.004, 0.0)), "iron")
    pot_c = apex + Vector((0, 0, -0.55))
    tp.cylinder(pot_c + Vector((0, 0, -0.26)), pot_c + Vector((0, 0, -0.02)), 0.14, 0.15, 10, "iron", cap1=False)
    tp.cylinder(pot_c + Vector((0, 0, -0.03)), pot_c + Vector((0, 0, -0.02)), 0.15, 0.15, 10, "snow", cap0=False)
    parts.append(H.smooth(H.mk(tp), angle=50))


def crate(parts, c, yaw, size=(0.62, 0.46, 0.46), lid=True, broken=False, seed=0):
    rnd = random.Random(seed)
    sx, sy, sz = size
    hard, fine = lp.MeshBuilder(), lp.MeshBuilder()
    xf = Matrix.Translation(c) @ Matrix.Rotation(math.radians(yaw), 4, 'Z')
    top = sz if lid else sz - 0.02
    if broken:
        # open box: four side panels + bottom, no lid
        t = 0.03
        for mn, mx in (((-sx / 2, -sy / 2, 0), (sx / 2, -sy / 2 + t, sz)), ((-sx / 2, sy / 2 - t, 0), (sx / 2, sy / 2, sz)),
                       ((-sx / 2, -sy / 2, 0), (-sx / 2 + t, sy / 2, sz)), ((sx / 2 - t, -sy / 2, 0), (sx / 2, sy / 2, sz - 0.12)),
                       ((-sx / 2, -sy / 2, 0), (sx / 2, sy / 2, 0.04))):
            hard.box(mn, mx, "wood", xf=xf)
        # lid leaning against the box, a loose plank
        lid_xf = xf @ Matrix.Translation((sx / 2 + 0.16, 0, 0)) @ Matrix.Rotation(math.radians(-22), 4, 'Y')
        hard.box((-0.02, -sy / 2, 0), (0.02, sy / 2, sx * 0.95), "wood_light", xf=lid_xf)
        fine.box((-0.6, -0.06, 0), (0.1, 0.06, 0.025), "wood", xf=xf @ Matrix.Translation((-0.25, -sy / 2 - 0.25, 0))
                 @ Matrix.Rotation(math.radians(35), 4, 'Z'))
        parts.append(V.heap(xf @ Vector((0, 0, 0.04)), sx / 2 - 0.05, sy / 2 - 0.05, 0.12, seed=seed, sides=8, rings=2,
                            sink=0.0, noise=0.1))
    else:
        hard.box((-sx / 2, -sy / 2, 0), (sx / 2, sy / 2, top), "wood", xf=xf)
        for zz in (0.06, top - 0.06):                        # bands: four closed strips (no see-through gap)
            for mn, mx in (((-sx / 2 - 0.012, -sy / 2 - 0.012), (sx / 2 + 0.012, -sy / 2)),
                           ((-sx / 2 - 0.012, sy / 2), (sx / 2 + 0.012, sy / 2 + 0.012)),
                           ((-sx / 2 - 0.012, -sy / 2), (-sx / 2, sy / 2)), ((sx / 2, -sy / 2), (sx / 2 + 0.012, sy / 2))):
                fine.box((mn[0], mn[1], zz - 0.03), (mx[0], mx[1], zz + 0.03), "wood_dark", xf=xf)
        for x in (-sx / 2, sx / 2):
            fine.box((x - 0.035, -sy / 2 - 0.014, 0), (x + 0.035, sy / 2 + 0.014, top), "wood_dark", xf=xf,
                     skip=("-z",))
        parts.append(H.pillow(xf @ Vector((-sx / 2 - 0.02, -sy / 2 - 0.02, top)), xf.to_3x3() @ Vector((1, 0, 0)),
                              xf.to_3x3() @ Vector((0, 1, 0)), (0, 0, 1), sx + 0.04, sy + 0.04, 0.08, nu=3, nv=3,
                              rim=0.08, seed=seed, levels=1, bottom=-0.03))
    o = H.mk(hard)
    H.bevel(o, 0.012, 1, angle=30)
    H.snap_colors(o)
    parts += [o, H.flat(H.mk(fine))]


def build_campsite():
    lp.new_scene()
    rnd = random.Random(29)
    parts = []
    tent(parts, rnd)
    fire_ring(parts, rnd)
    crate(parts, CRATE_A, 12, seed=41)
    crate(parts, CRATE_B, -28, size=(0.56, 0.42, 0.42), broken=True, seed=42)
    body, pts, radii = V.log_body(BENCH + Vector((-0.85, 0.0, 0.17)), BENCH + Vector((0.85, 0.08, 0.16)), 0.17, 0.16,
                                  sides=9, segs=2, bend=0.03, seed=43, cap0="rings", cap1="rings")
    parts += body
    parts.append(V.snow_on_log(pts, radii, width_k=1.1, thick=0.05, seed=44))
    can = lp.MeshBuilder()
    can.cylinder(FIRE + Vector((0.75, 0.55, 0.0)), FIRE + Vector((0.77, 0.5, 0.11)), 0.035, 0.035, 8, "can_red")
    parts.append(H.smooth(H.mk(can), angle=50))
    for k, (x, y, rx, ry, h) in enumerate(((-2.7, -1.1, 0.7, 0.45, 0.22), (2.8, -1.5, 0.45, 0.55, 0.18),
                                           (-0.1, 2.05, 0.8, 0.35, 0.2))):
        parts.append(V.heap((x, y, 0), rx, ry, h, seed=60 + k, sides=12, rings=3, sink=0.05, noise=0.15,
                            lobes_=[(rx * 0.3, 0.0, rx * 0.5, h * 0.3)], yaw=25 * k))
    H.join(parts, "Remains")
    lp.add_empty("FlameAnchor", FIRE + Vector((0, 0, 0.18)))
    for name, pos, yaw, props in (("Spawn_Container_0", CRATE_A, 12, {"table": "campsite"}),
                                  ("Spawn_Loot_0", CRATE_B + Vector((0, 0, 0.05)), -28, {}),
                                  ("Spawn_Loot_1", TENT + Vector((0.2, -0.2, 0.0)), 18, {})):
        e = lp.add_empty(name, pos, rotation_deg=(0, 0, yaw), size=0.3)
        e["kind"] = name.split("_")[1]
        for k, v in props.items():
            e[k] = v
    lp.collision_box("ColCrate_0", CRATE_A - Vector((0.36, 0.3, 0)), CRATE_A + Vector((0.36, 0.3, 0.5)))
    lp.collision_box("ColCrate_1", CRATE_B - Vector((0.34, 0.3, 0)), CRATE_B + Vector((0.34, 0.3, 0.45)))
    lp.collision_box("ColBench", BENCH - Vector((0.9, 0.2, 0)), BENCH + Vector((0.9, 0.28, 0.36)))
    tc = rot_about(TENT + Vector((-0.85, 0, 0)), TENT, 18)
    lp.collision_box("ColTent", tc - Vector((0.45, 0.55, 0)), tc + Vector((0.45, 0.55, 0.9)))
    export.save_and_export("campsite_remains", subdir="poi", ao=dict(distance=0.6, samples=64, ground=True),
                           import_kind="prop")


def main():
    build_campsite()


if __name__ == "__main__":
    main()
