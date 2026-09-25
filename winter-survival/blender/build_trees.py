"""pine_a, pine_b, pine_c, dead_tree, stump (slice ASSET_SPEC §4.4-4.6; ASSET_SPEC_V2 §13/§17; HD v2.1 in G1).

    cd winter-survival/blender && python3 build_trees.py

MultiMesh contract kept (ASSET_SPEC_V2 §13): one object (`Tree` / `Stump`), one palette_vcol surface, no children,
origin at the trunk base, no collision, no front. Heights as the slice (7.0 / 5.5 / 4.0 / 4.5 m, the code sizes its
collision and interaction shapes from them).

G1 (docs/research/05_graficos_arte.md §1.2/§1.3/§4.3, port of the approved look-dev pine_hd_a/b + bare_tree_hd):
  * pines: star tiers (7-8 points, drooping tips, concave `pine_dark` underside, `pine_mid` top faces) almost fully
    capped by a snow shell computed ON the green surface (never intersects), 7.5-9.5 cm thick and a little shorter
    than the tips so a thin dark rim shows; faceted (the facets are the look); smooth bark trunk visible under the
    first tier; smooth snow mound at the base sunk 0.2 m (never floats on a slope). pine_c = young pine, 5 tiers.
  * dead_tree: recursive branching (trunk -> 9 limbs -> 3 branches -> 2 twigs), bent tapered tubes (4-7 sides),
    radius >= 1.4 cm, smooth `bark_grey` bark, snow on the upper faces of the trunk and main limbs, base mound.
  * stump: smooth bark with a root flare, slanted saw cut with growth rings and a bark rim, rounded snow cap on
    the low half of the cut.
AO baked in COLOR_0.a (1.2 m pines, 0.8 m bare tree, doc 05 §4.6).
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402,F401  (must precede mathutils)
from mathutils import Matrix, Vector  # noqa: E402

from lib import export  # noqa: E402
from lib import hd as H  # noqa: E402
from lib import lowpoly as lp  # noqa: E402

Z = Vector((0, 0, 1))

# tiers: (z0 of the tip ring, radius R, height h); trunk (base r, top r); snow_t = snow shell thickness
PINES = {
    "pine_a": dict(trunk=(0.25, 0.10), snow_t=0.075, seed=3, points=8, tiers=[
        (1.40, 2.00, 1.55), (2.35, 1.76, 1.45), (3.25, 1.50, 1.35), (4.10, 1.24, 1.25), (4.90, 0.98, 1.15),
        (5.65, 0.72, 1.05), (6.35, 0.46, 0.95)]),
    "pine_b": dict(trunk=(0.22, 0.09), snow_t=0.095, seed=17, points=7, tiers=[
        (1.05, 1.80, 1.30), (1.85, 1.56, 1.20), (2.60, 1.29, 1.12), (3.30, 1.00, 1.03), (3.95, 0.71, 0.95),
        (4.55, 0.44, 0.88)]),
    "pine_c": dict(trunk=(0.17, 0.07), snow_t=0.085, seed=29, points=7, tiers=[
        (0.70, 1.35, 1.00), (1.30, 1.14, 0.94), (1.88, 0.92, 0.88), (2.45, 0.68, 0.82), (3.00, 0.42, 0.84)]),
}


def star(z0, R, n, phase, rnd, inner=0.50, droop=0.10, h=1.0, jit=0.07):
    """2n points: tips at R (drooping), notches at inner * R."""
    pts = []
    for i in range(2 * n):
        a = math.radians(phase) + math.pi * i / n
        tip = i % 2 == 0
        r = R * rnd.uniform(1 - jit, 1 + jit) if tip else R * inner * rnd.uniform(0.92, 1.05)
        z = z0 - (droop * h * rnd.uniform(0.8, 1.2) if tip else -0.03 * h)
        pts.append(Vector((math.cos(a) * r, math.sin(a) * r, z)))
    return pts


def pine_tier(mb, z0, R, h, n, snow_t, rnd, top=False):
    phase = rnd.uniform(0, 360)
    s0 = star(z0, R, n, phase, rnd, inner=0.60, droop=0.12, h=h)
    s1 = [Vector((p.x * 0.50, p.y * 0.50, z0 + 0.44 * h + (0.0 if i % 2 == 0 else 0.02 * h))) for i, p in enumerate(s0)]
    apex = Vector((0, 0, z0 + h))
    mb.loft([s0, s1, [apex]], "pine_mid", cap_start=False, cap_end=False, inside=(0, 0, z0 + 0.2 * h))
    under = Vector((0, 0, z0 + 0.16 * h))                      # concave underside
    m = len(s0)
    for i in range(m):
        mb.poly([s0[i], s0[(i + 1) % m], under], "pine_dark", facing=(0, 0, -1))
    # snow shell on the green surface: starts 20 % (tips) / 4 % (notches) up each spoke, thickness snow_t
    tcut = [0.20 if i % 2 == 0 else 0.04 for i in range(m)]
    b0 = [s0[i].lerp(s1[i], tcut[i]) + Vector((0, 0, -0.01)) for i in range(m)]
    t0 = [p + Vector((0, 0, snow_t * (1.0 if i % 2 == 0 else 0.85))) for i, p in enumerate(b0)]
    t1 = [p + Vector((0, 0, snow_t * 0.9)) for p in s1]
    ap = apex + Vector((0, 0, snow_t * (1.4 if top else 0.8)))
    mb.loft([b0, t0], "snow", cap_start=False, cap_end=False, inside=(0, 0, z0 + 0.3 * h))
    mb.loft([t0, t1, [ap]], "snow", cap_start=False, cap_end=False, inside=(0, 0, z0))


def build_pine(name):
    cfg = PINES[name]
    lp.new_scene()
    rnd = random.Random(cfg["seed"])
    mb = lp.MeshBuilder()
    for (z0, R, h) in cfg["tiers"]:
        pine_tier(mb, z0, R, h, cfg["points"], cfg["snow_t"], rnd, top=(z0 == cfg["tiers"][-1][0]))
    tiers = H.flat(H.mk(mb))
    tr = lp.MeshBuilder()
    r0, r1 = cfg["trunk"]
    top_z = cfg["tiers"][-2][0]
    H.tube(tr, [(0, 0, -0.1), (0.01, 0, 0.6), (0, 0.01, top_z * 0.5), (0, 0, top_z)],
           [r0 * 1.15, r0, (r0 + r1) / 2, r1], 7, "bark", cap_end=True)
    trunk = H.smooth(H.mk(tr))
    ang = rnd.uniform(0, 360)
    rad = cfg["tiers"][0][1] * 0.42 + 0.1 * math.sin(ang)
    mound = H.mound((0, 0, 0), rad, 0.24, seed=cfg["seed"], sides=14, sink=0.2)
    H.join([tiers, trunk, mound], "Tree")
    export.save_and_export(name, ao=dict(distance=1.2, samples=64, ground=True))


# ------------------------------------------------------------------------------------------------------------
def build_dead_tree(seed=5, height=4.5):
    lp.new_scene()
    rnd = random.Random(seed)
    mb = lp.MeshBuilder()
    snowy = []
    k_len = height / 6.4                              # the look-dev tree is 6.4 m tall

    def rot_towards(d, az, el):
        d = d.normalized()
        ref = Vector((0, 0, 1)) if abs(d.z) < 0.95 else Vector((1, 0, 0))
        side = d.cross(ref).normalized()
        return (Matrix.Rotation(math.radians(az), 3, d) @ (Matrix.Rotation(math.radians(el), 3, side) @ d)).normalized()

    def limb(p0, d, length, r0, depth, segs):
        pts, radii = [Vector(p0)], [r0]
        dd = d.normalized()
        r1 = max(0.014, r0 * 0.28)
        for k in range(1, segs + 1):
            wob = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-0.4, 0.7))) * 0.22
            dd = (dd + wob + Vector((0, 0, 0.06 if depth < 2 else -0.04))).normalized()
            pts.append(pts[-1] + dd * (length / segs))
            radii.append(r0 + (r1 - r0) * k / segs)
        sides = 7 if r0 > 0.12 else 6 if r0 > 0.06 else 5 if r0 > 0.03 else 4
        f0 = len(mb.faces)
        H.tube(mb, pts, radii, sides, "bark_grey", cap_end=True)
        if depth <= 1:
            snowy.append((f0, len(mb.faces)))
        return pts, radii

    def radius_at(pts, radii, t):
        f = t * (len(pts) - 1)
        i = min(int(f), len(pts) - 2)
        u = f - i
        return pts[i].lerp(pts[i + 1], u), radii[i] + (radii[i + 1] - radii[i]) * u, (pts[i + 1] - pts[i]).normalized()

    tpts, trad = limb((0, 0, -0.15), Vector((0.05, 0.02, 1)), 6.2 * k_len, 0.27, 0, 5)
    n1 = 9
    for k in range(n1):
        t = 0.30 + 0.62 * k / (n1 - 1) + rnd.uniform(-0.03, 0.03)
        p, r, d = radius_at(tpts, trad, t)
        dir1 = rot_towards(d, k * 137.5 + rnd.uniform(-20, 20), rnd.uniform(38, 62) - 18 * t)
        L1 = (2.4 - 1.5 * t) * rnd.uniform(0.85, 1.15) * (0.35 + 0.65 * k_len)
        p1, r1 = limb(p, dir1, L1, max(0.035, r * 0.55), 1, 3)
        for j in range(3):
            q, rq, dq = radius_at(p1, r1, 0.35 + 0.22 * j + rnd.uniform(-0.05, 0.05))
            dir2 = rot_towards(dq, rnd.uniform(0, 360), rnd.uniform(28, 55))
            p2, r2 = limb(q, dir2, L1 * rnd.uniform(0.4, 0.6), max(0.022, rq * 0.62), 2, 2)
            for m in range(2):
                q3, rq3, dq3 = radius_at(p2, r2, 0.45 + 0.4 * m)
                dir3 = rot_towards(dq3, rnd.uniform(0, 360), rnd.uniform(25, 50))
                limb(q3, dir3, L1 * rnd.uniform(0.22, 0.32), max(0.014, rq3 * 0.7), 3, 2)
    for k in range(4):
        p, r, d = radius_at(tpts, trad, 0.96)
        limb(p, rot_towards(d, k * 90 + 20, 30), 0.8 * k_len, 0.03, 3, 2)
    zmin_snow = 1.4 * k_len
    for a, b in snowy:
        mb.recolor(lambda n, c, m: n.z > 0.72 and c.z > zmin_snow, "snow", faces=range(a, b))
    tree = H.smooth(H.mk(mb))
    mound = H.mound((0, 0, 0), 0.62, 0.18, seed=seed, sides=14, sink=0.2)
    H.join([tree, mound], "Tree")
    export.save_and_export("dead_tree", ao=dict(distance=0.8, samples=64, ground=True))


# ------------------------------------------------------------------------------------------------------------
def build_stump():
    """0.6 x 0.6 x 0.45 m: smooth bark body with a root flare, slanted cut with rings, snow cap on the low half."""
    lp.new_scene()
    rnd = random.Random(8)
    n = 12
    cut = lambda x, y: 0.425 + 0.03 * x / 0.26       # noqa: E731  slanted saw cut (low toward -X)
    rings = []
    prof = [(0.00, 0.282), (0.05, 0.268), (0.13, 0.258), (0.30, 0.252)]
    jit = [rnd.uniform(0.95, 1.05) for _ in range(n)]
    for z, r in prof:
        flare = 1.0 + (0.08 if z < 0.06 else 0.0)
        rings.append([Vector((math.cos(2 * math.pi * i / n) * r * jit[i] * (flare if i % 3 == 0 else 1.0),
                              math.sin(2 * math.pi * i / n) * r * jit[i] * (flare if i % 3 == 0 else 1.0), z))
                      for i in range(n)])
    top = []
    for i in range(n):
        x = math.cos(2 * math.pi * i / n) * 0.25 * jit[i]
        y = math.sin(2 * math.pi * i / n) * 0.25 * jit[i]
        top.append(Vector((x, y, cut(x, y))))
    rings.append(top)
    body = lp.MeshBuilder()
    body.loft(rings, "bark", cap_start=False, cap_end=False, inside=(0, 0, 0.2))
    bark = H.smooth(H.mk(body), angle=60)
    # cut face: bark rim -> sapwood -> growth ring -> heart (flat, slightly inset rings)
    face = lp.MeshBuilder()
    radii = [(1.0, "bark"), (0.86, "wood_light"), (0.62, "wood"), (0.52, "wood_light"), (0.24, "wood")]
    prev = None
    for k, (f, mat) in enumerate(radii):
        ring = []
        for i in range(n):
            x = math.cos(2 * math.pi * i / n) * 0.25 * jit[i] * f
            y = math.sin(2 * math.pi * i / n) * 0.25 * jit[i] * f
            ring.append(Vector((x, y, cut(x, y) - (0.004 if k else 0.0))))
        if prev is not None:
            face.loft([prev[0], ring], prev[1], cap_start=False, cap_end=False, seg_facing=[(0.12, 0, 1)])
        prev = (ring, mat)
    face.loft([prev[0], [Vector((0, 0, cut(0, 0) - 0.004))]], prev[1], cap_start=False, cap_end=False,
              seg_facing=[(0.12, 0, 1)])
    cutf = H.flat(H.mk(face))
    cap = H.snow_cap((-0.09, 0.02, 0), 0.17, 0.21, 0.04, lambda x, y: cut(x, y), seed=3, sides=10, rings=3,
                     droop=0.010)
    H.join([bark, cutf, cap], "Stump")
    export.save_and_export("stump", ao=dict(distance=0.3, samples=64, ground=True))


def main():
    for name in PINES:
        build_pine(name)
    build_dead_tree()
    build_stump()


if __name__ == "__main__":
    main()
