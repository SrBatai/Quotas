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
M3: the pine / bare-tree generators live in lib/veg.py (shared with the vegetation/ scatter families); the defaults
reproduce these G1 assets byte for byte.
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402,F401  (must precede mathutils)
from mathutils import Vector  # noqa: E402

from lib import export  # noqa: E402
from lib import hd as H  # noqa: E402
from lib import lowpoly as lp  # noqa: E402
from lib import veg as V  # noqa: E402

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


def build_pine(name):
    lp.new_scene()
    H.join(V.pine(PINES[name]), "Tree")
    export.save_and_export(name, ao=dict(distance=1.2, samples=64, ground=True))


# ------------------------------------------------------------------------------------------------------------
def build_dead_tree(seed=5, height=4.5):
    lp.new_scene()
    br, _tpts, _trad, k_len = V.bare_tree(seed=seed, height=height)
    br.snow(1.4 * k_len)
    tree = H.smooth(H.mk(br.mb))
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
