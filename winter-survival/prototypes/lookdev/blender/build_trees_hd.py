"""pine_hd_a, pine_hd_b (snowy pines) and bare_tree_hd - HD look-dev (guidelines v2.1).

    cd winter-survival/prototypes/lookdev/blender && python3 build_trees_hd.py

MultiMesh contract kept (ASSET_SPEC_V2 §13): one object `Tree`, one palette_vcol surface, no children, origin at
the trunk base, no collision. Budgets v2.1: pine <= 1 200 tris, bare tree <= 2 600 tris.

Pines (reference: star-shaped tiers almost fully capped by thick snow, dark green only on the drooping tips and the
undersides, 5-7 tiers, faceted): every tier = a green star shell (8 points, drooping tips, concave underside) +
a snow shell computed ON the green surface (so it never intersects), 7-9 cm thick with a visible skirt, slightly
shorter tips so a thin dark green rim shows. Flat shading (the facets are part of the reference look); the trunk
and the base mound are smooth.
Bare tree: recursive branching (trunk -> 9 limbs -> 3 branches -> 2 twigs), bent tapered tubes, smooth shaded,
thin snow lines on the upper faces of the trunk and limbs.
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import hdlib as H  # noqa: E402
from hdlib import lp  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

Z = Vector((0, 0, 1))

PINES = {
    # height of the green crown top, trunk radius, tiers: (z0, R, h), snow thickness, seed
    "pine_hd_a": dict(trunk=(0.25, 0.10), snow_t=0.075, seed=3, points=8, tiers=[
        (1.40, 2.00, 1.55), (2.35, 1.76, 1.45), (3.25, 1.50, 1.35), (4.10, 1.24, 1.25), (4.90, 0.98, 1.15),
        (5.65, 0.72, 1.05), (6.35, 0.46, 1.10)]),
    "pine_hd_b": dict(trunk=(0.23, 0.09), snow_t=0.095, seed=17, points=7, tiers=[
        (1.20, 2.10, 1.45), (2.10, 1.82, 1.35), (2.95, 1.50, 1.25), (3.75, 1.16, 1.15), (4.50, 0.82, 1.05),
        (5.15, 0.50, 1.00)]),
}


def star(z0, R, n, phase, rnd, inner=0.50, droop=0.10, h=1.0, scale=1.0, jit=0.07):
    """2n points: tips at R (drooping), notches at inner*R."""
    pts = []
    for i in range(2 * n):
        a = math.radians(phase) + math.pi * i / n
        tip = i % 2 == 0
        r = (R * rnd.uniform(1 - jit, 1 + jit) if tip else R * inner * rnd.uniform(0.92, 1.05)) * scale
        z = z0 - (droop * h * rnd.uniform(0.8, 1.2) if tip else -0.03 * h)
        pts.append(Vector((math.cos(a) * r, math.sin(a) * r, z)))
    return pts


def pine_tier(mb, z0, R, h, n, snow_t, rnd, top=False):
    phase = rnd.uniform(0, 360)
    s0 = star(z0, R, n, phase, rnd, inner=0.60, droop=0.12, h=h)
    # second ring: follows the star, 52 % radius, 42 % height
    s1 = [Vector((p.x * 0.50, p.y * 0.50, z0 + 0.44 * h + (0.0 if i % 2 == 0 else 0.02 * h))) for i, p in enumerate(s0)]
    apex = Vector((0, 0, z0 + h))
    mb.loft([s0, s1, [apex]], "pine_mid", cap_start=False, cap_end=False, inside=(0, 0, z0 + 0.2 * h))
    # concave underside
    under = Vector((0, 0, z0 + 0.16 * h))
    m = len(s0)
    for i in range(m):
        mb.poly([s0[i], s0[(i + 1) % m], under], "pine_dark", facing=(0, 0, -1))
    # snow shell on the green surface: bottom ring at 88 % (tips) of s0 along each spoke, thickness snow_t
    def on_green(i, t):
        """point on the spoke of vertex i: t=0 at s0, t=1 at s1 (straight line = the green face edge)."""
        return s0[i].lerp(s1[i], t)
    tcut = [0.20 if i % 2 == 0 else 0.04 for i in range(m)]
    b0 = [on_green(i, tcut[i]) + Vector((0, 0, -0.01)) for i in range(m)]
    t0 = [p + Vector((0, 0, snow_t * (1.0 if i % 2 == 0 else 0.85))) for i, p in enumerate(b0)]
    t1 = [p + Vector((0, 0, snow_t * 0.9)) for p in s1]
    ap = apex + Vector((0, 0, snow_t * (1.4 if top else 0.8)))
    mb.loft([b0, t0], "snow", cap_start=False, cap_end=False, inside=(0, 0, z0 + 0.3 * h))
    mb.loft([t0, t1, [ap]], "snow", cap_start=False, cap_end=False, inside=(0, 0, z0))


def build_pine(name):
    cfg = PINES[name]
    H.new_scene()
    rnd = random.Random(cfg["seed"])
    mb = lp.MeshBuilder()
    for (z0, R, h) in cfg["tiers"]:
        pine_tier(mb, z0, R, h, cfg["points"], cfg["snow_t"], rnd, top=(z0 == cfg["tiers"][-1][0]))
    tiers = H.flat(H.mk(mb))
    # trunk (smooth) up into the crown + base snow mound (smooth pillow disc)
    tr = lp.MeshBuilder()
    r0, r1 = cfg["trunk"]
    top_z = cfg["tiers"][-2][0]
    H.tube(tr, [(0, 0, -0.1), (0.01, 0, 0.6), (0, 0.01, top_z * 0.5), (0, 0, top_z)], [r0 * 1.15, r0, (r0 + r1) / 2,
                                                                                         r1], 7, "bark", cap_end=True)
    trunk = H.smooth(H.mk(tr))
    ang = rnd.uniform(0, 360)
    mound = H.mound((0, 0, 0), 0.85 + 0.1 * math.sin(ang), 0.24, seed=cfg["seed"], sides=14, sink=0.2)
    obj = H.join([tiers, trunk, mound], "Tree")
    H.bake_ao([obj], distance=1.2, samples=64, ground=True)
    glb, tris, surf, per = H.export_hd(name)
    H.write_manifest_entry(name, {"file": name + ".glb", "replaces": "assets/models/pine_a|b|c.glb", "tris": tris,
                                  "height_m": round(cfg["tiers"][-1][0] + cfg["tiers"][-1][2], 2),
                                  "multimesh": True})
    return tris


# ------------------------------------------------------------------------------------------------------------
def build_bare_tree(name="bare_tree_hd", seed=5):
    H.new_scene()
    rnd = random.Random(seed)
    mb = lp.MeshBuilder()
    snowy = []                                     # (first face, last face) ranges that may receive snow

    def rot_towards(d, az, el):
        """direction tilted `el` deg away from d, rotated `az` deg around it."""
        d = d.normalized()
        ref = Vector((0, 0, 1)) if abs(d.z) < 0.95 else Vector((1, 0, 0))
        side = d.cross(ref).normalized()
        q = Matrix.Rotation(math.radians(el), 3, side)
        q2 = Matrix.Rotation(math.radians(az), 3, d)
        return (q2 @ (q @ d)).normalized()

    def limb(p0, d, length, r0, depth, segs):
        pts, radii = [Vector(p0)], [r0]
        dd = d.normalized()
        r1 = max(0.012, r0 * 0.28)
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

    # trunk: slight lean and bend
    tpts, trad = limb((0, 0, -0.15), Vector((0.05, 0.02, 1)), 6.2, 0.27, 0, 5)
    specs1 = 9
    for k in range(specs1):
        t = 0.30 + 0.62 * k / (specs1 - 1) + rnd.uniform(-0.03, 0.03)
        p, r, d = radius_at(tpts, trad, t)
        az = k * 137.5 + rnd.uniform(-20, 20)
        el = rnd.uniform(38, 62) - 18 * t
        dir1 = rot_towards(d, az, el)
        L1 = (2.4 - 1.5 * t) * rnd.uniform(0.85, 1.15)
        p1, r1 = limb(p, dir1, L1, max(0.035, r * 0.55), 1, 3)
        for j in range(3):
            tt = 0.35 + 0.22 * j + rnd.uniform(-0.05, 0.05)
            q, rq, dq = radius_at(p1, r1, tt)
            dir2 = rot_towards(dq, rnd.uniform(0, 360), rnd.uniform(28, 55))
            p2, r2 = limb(q, dir2, L1 * rnd.uniform(0.4, 0.6), max(0.022, rq * 0.62), 2, 2)
            for m in range(2):
                q3, rq3, dq3 = radius_at(p2, r2, 0.45 + 0.4 * m)
                dir3 = rot_towards(dq3, rnd.uniform(0, 360), rnd.uniform(25, 50))
                limb(q3, dir3, L1 * rnd.uniform(0.22, 0.32), max(0.014, rq3 * 0.7), 3, 2)
    # top twigs
    for k in range(4):
        p, r, d = radius_at(tpts, trad, 0.96)
        limb(p, rot_towards(d, k * 90 + 20, 30), 0.8, 0.03, 3, 2)
    # snow lines on upward faces of trunk + limbs
    for a, b in snowy:
        mb.recolor(lambda n, c, m: n.z > 0.72 and c.z > 1.4, "snow", faces=range(a, b))
    tree = H.smooth(H.mk(mb))
    mound = H.mound((0, 0, 0), 0.7, 0.2, seed=seed, sides=14, sink=0.2)
    obj = H.join([tree, mound], "Tree")
    H.bake_ao([obj], distance=0.8, samples=48, ground=True)
    glb, tris, surf, per = H.export_hd(name)
    H.write_manifest_entry(name, {"file": name + ".glb", "replaces": "assets/models/dead_tree.glb", "tris": tris,
                                  "height_m": 6.4, "multimesh": True})
    return tris


def main():
    for n in PINES:
        build_pine(n)
    build_bare_tree()


if __name__ == "__main__":
    main()
