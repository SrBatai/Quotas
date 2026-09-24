"""pine_a, pine_b, pine_c, dead_tree, stump (ASSET_SPEC §4.4-4.6)."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402,F401  (must precede mathutils)
from mathutils import Vector  # noqa: E402

from lib import export  # noqa: E402
from lib import lowpoly as lp  # noqa: E402

Z = (0, 0, 1)

# variant: total height, trunk r (base, top), tiers [(base z, base radius, height, material)], snow ring
PINES = {
    "pine_a": dict(height=7.0, trunk=(0.25, 0.12), snow_at=0.24, seed=11, tiers=[
        (1.4, 1.9, 2.0, "pine_dark"), (3.0, 1.5, 1.8, "pine_dark"),
        (4.4, 1.1, 1.6, "pine_light"), (5.6, 0.7, 1.4, "pine_light")]),
    "pine_b": dict(height=5.5, trunk=(0.22, 0.10), snow_at=0.24, seed=23, tiers=[
        (1.1, 1.6, 1.7, "pine_dark"), (2.5, 1.2, 1.5, "pine_light"), (3.7, 0.8, 1.8, "pine_light")]),
    "pine_c": dict(height=4.0, trunk=(0.18, 0.08), snow_at=0.17, seed=37, tiers=[
        (0.8, 1.3, 1.5, "pine_dark"), (1.9, 0.9, 1.3, "pine_light"), (2.8, 0.55, 1.2, "pine_light")]),
}


def snow_mound(mb, r=0.45, h=0.08):
    """Flattened 8-gon snow disc at the trunk base."""
    mb.cylinder((0, 0, 0), (0, 0, h), r, r * 0.72, 8, "snow", cap0=False, phase=11.25)


def pine_tier(mb, z0, r, h, green, snow_at, rnd):
    """One tier: 8-sided cone with an extra vertex ring; faces below the ring are pine green, faces
    above are snow. The base ring is jagged (long drooping tips / short valleys), the snow ring flares
    into a small overhanging lip, and the underside is a concave umbrella.

    DEVIATION (reported): the spec puts the ring at 55 % of the tier height; with the spec's tier radii
    (each tier covers the one below up to 0.4 m from its edge) that snow is completely hidden from the
    game camera. The ring therefore sits low on the tier (`snow_at` is a fraction of the height,
    0.24 / 0.17 for the heavy-snow pine_c) so the visible outer band of every tier is snow-capped."""
    n = 8
    phase = rnd.uniform(0, 45)
    radii = [(1.0 if i % 2 == 0 else 0.74) * rnd.uniform(0.95, 1.05) for i in range(n)]
    base = lp.ring((0, 0, z0), Z, r, n, phase, radii)
    for i, p in enumerate(base):
        p.z += -0.09 * h if i % 2 == 0 else 0.02 * h       # drooping branch tips
    zs = z0 + snow_at * h
    ring_r = r * (0.86 - 0.5 * snow_at) * 0.97
    green_top = lp.ring((0, 0, zs), Z, ring_r, n, phase,
                        [1.0 if i % 2 == 0 else 0.84 for i in range(n)])
    lip = lp.ring((0, 0, zs + 0.03 * h), Z, ring_r * 1.07, n, phase,
                  [1.0 if i % 2 == 0 else 0.86 for i in range(n)])
    apex = [Vector((0, 0, z0 + h))]
    mb.loft([base, green_top, lip, apex], green, cap_start=False, cap_end=False,
            side_mats=[green, "snow", "snow"])
    # concave underside (umbrella), explicitly facing down
    under = Vector((0, 0, z0 + 0.10 * h))
    for i in range(n):
        mb.poly([base[i], base[(i + 1) % n], under], green, facing=(0, 0, -1))


def build_pine(name):
    cfg = PINES[name]
    lp.new_scene()
    rnd = lp.rng(cfg["seed"])
    mb = lp.MeshBuilder()
    r0, r1 = cfg["trunk"]
    top_tier = cfg["tiers"][-1]
    trunk_top = top_tier[0] + 0.35 * top_tier[2]
    mb.cylinder((0, 0, 0), (0, 0, trunk_top), r0, r1, 6, "bark", cap0=False, cap1=False, phase=15)
    for (z0, r, h, mat) in cfg["tiers"]:
        pine_tier(mb, z0, r, h, mat, cfg["snow_at"], rnd)
    snow_mound(mb)
    lp.to_object(mb, "Tree")
    export.save_and_export(name)


def build_dead_tree():
    lp.new_scene()
    rnd = lp.rng(5)
    mb = lp.MeshBuilder()
    # leaning, slightly bent trunk (lean baked into the mesh)
    path = [(0.0, 0.0, 0.0), (0.0, 0.0, 0.35), (0.04, 0.01, 1.3), (0.12, -0.02, 2.4),
            (0.24, 0.02, 3.5), (0.38, 0.0, 4.5)]
    radii = [0.27, 0.20, 0.175, 0.145, 0.11, 0.07]
    rings = []
    for i, (p, r) in enumerate(zip(path, radii)):
        if i == 0:
            axis = Vector(path[1]) - Vector(path[0])
        elif i == len(path) - 1:
            axis = Vector(path[-1]) - Vector(path[-2])
        else:
            axis = Vector(path[i + 1]) - Vector(path[i - 1])
        rings.append(lp.ring(p, axis, r, 6, 10))
    rings.append([Vector((0.42, 0.0, 4.75))])
    mb.loft(rings, "bark", cap_start=False, cap_end=False)

    def trunk_at(z):
        for a, b in zip(path, path[1:]):
            if a[2] <= z <= b[2]:
                t = (z - a[2]) / (b[2] - a[2])
                return Vector(a).lerp(Vector(b), t)
        return Vector(path[-1])

    def branch(p0, direction, length, r0, r1):
        d = direction.normalized()
        p1 = p0 + d * length
        mb.cylinder(p0, p1, r0, r1, 4, "bark", cap0=False, cap1=True, phase=45, snow=True)
        return p1

    # (height, azimuth deg, elevation deg, length, forked)
    specs = [(1.9, 20, 38, 1.5, True), (2.4, 150, 45, 1.35, False), (2.9, 265, 40, 1.6, True),
             (3.3, 75, 55, 1.2, False), (3.7, 200, 50, 1.05, False), (4.0, 320, 60, 0.95, False),
             (2.15, 300, 35, 0.9, False)]
    for (z, az, el, length, forked) in specs:
        a, e = math.radians(az), math.radians(el)
        d = Vector((math.cos(a) * math.cos(e), math.sin(a) * math.cos(e), math.sin(e)))
        c = trunk_at(z)
        p0 = c + d * 0.05
        branch(p0, d, length, 0.05, 0.02)
        if forked:
            fp = p0 + d * (length * 0.55)
            a2 = a + math.radians(rnd.choice((-35, 35)))
            e2 = e + math.radians(12)
            d2 = Vector((math.cos(a2) * math.cos(e2), math.sin(a2) * math.cos(e2), math.sin(e2)))
            branch(fp, d2, length * 0.45, 0.032, 0.015)
    mb.snow(0.55)
    snow_mound(mb, 0.45, 0.08)
    lp.to_object(mb, "Tree")
    export.save_and_export("dead_tree")


def build_stump():
    lp.new_scene()
    mb = lp.MeshBuilder()
    n = 8
    ph = 22.5
    bot = lp.ring((0, 0, 0), Z, 0.33, n, ph)
    mid = lp.ring((0, 0, 0.12), Z, 0.30, n, ph)
    top = lp.ring((0, 0, 0.45), Z, 0.29, n, ph)
    for p in top:                      # slightly slanted saw cut
        p.z += 0.03 * p.x / 0.29
    ring_o = lp.ring((0, 0, 0.45), Z, 0.19, n, ph)          # thin darker growth ring
    ring_i = lp.ring((0, 0, 0.45), Z, 0.155, n, ph)
    for rr in (ring_o, ring_i):
        for p in rr:
            p.z += 0.03 * p.x / 0.29
    mb.loft([bot, mid, top, ring_o, ring_i], "bark", cap_start=False, cap_end=True,
            side_mats=["bark", "bark", "wood_light", "wood"], cap_mats=(None, "wood_light"),
            inside=(0, 0, 0.2))
    # snow patch on half of the cut (the -X half, where the cut is lowest)
    half = [p.copy() for p in top[2:6]]              # rim points on the -X side (112.5..247.5 deg)
    for p in half:
        p.x *= 0.98
        p.y *= 0.98
        p.z += 0.002
    raised = [p + Vector((0.02 * (1 if p.x < 0 else 0), 0, 0.05)) for p in half]
    raised[0].z -= 0.025
    raised[-1].z -= 0.025
    # the loop closes along the chord, so this also makes the straight edge of the patch
    mb.loft([half, raised], "snow", cap_start=False, cap_end=True, inside=(-0.14, 0, 0.3))
    lp.to_object(mb, "Stump")
    export.save_and_export("stump")


def main():
    for name in PINES:
        build_pine(name)
    build_dead_tree()
    build_stump()


if __name__ == "__main__":
    main()
