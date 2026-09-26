"""M3 trees for the MultiMesh forest (ASSET_SPEC_V2 §13 + "M3"): pine_d, pine_e, pine_f, pine_young, dead_tree_b,
dead_tree_c, birch -> assets/models/vegetation/<name>.glb (+ .import, + manifest.json entry).

    cd winter-survival/blender && python3 vegetation/build_trees.py

MultiMesh contract: ONE object `Tree`, ONE palette_vcol surface, no children / empties / collision, origin at the
trunk foot (z = 0, snow mound sunk 0.2 m), no front. Collision proxy (the code builds it) in the node extras +
manifest: vertical trunk cylinder r 0.25-0.40, 3 m high (the slice ChoppableTree convention), choppable.
Guide v2.1 (doc 05 §4.3): star tiers almost covered by snow with a dark rim, concave dark underside, faceted; bare
trees = recursive bent tubes (radius >= 1.4 cm) with snow on the trunk / main limbs; AO 1.2 m (pines), 0.8 m (bare).

  pine_d      very tall narrow spruce, 9.0 m, 8 tiers (8/7/6 points), light snow
  pine_e      double crown (forked leader at 4.2 m), 7.4 m
  pine_f      heavy snow load ("snow ghost"): drooping tips, 14 cm shell reaching the tips, 6.1 m
  pine_young  young fir 2.5 m, 5 tiers
  dead_tree_b broken snag 6 m: leaning trunk, splintered top, short broken limbs
  dead_tree_c small multi-stem dead tree 3.4 m (three stems)
  birch       leafless birch 7 m: white bark with dark bands, fine upright dark twigs
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import bpy  # noqa: E402,F401  (must precede mathutils)
from mathutils import Vector  # noqa: E402

from lib import hd as H  # noqa: E402
from lib import lowpoly as lp  # noqa: E402
from lib import veg as V  # noqa: E402

PINE_AO = dict(distance=1.2, samples=64, ground=True)
BARE_AO = dict(distance=0.8, samples=64, ground=True)

PINES = {
    # 9 m spruce: narrow, 8 tiers, fewer points up high (budget)
    "pine_d": dict(seed=41, points=8, snow_t=0.07, trunk=(0.27, 0.10), droop=0.13, tiers=[
        (1.70, 2.05, 1.50, 8), (2.70, 1.85, 1.42, 8), (3.65, 1.62, 1.35, 8), (4.55, 1.40, 1.28, 7),
        (5.40, 1.17, 1.20, 7), (6.20, 0.94, 1.14, 7), (6.95, 0.70, 1.08, 6), (7.65, 0.45, 1.22, 6)]),
    # heavy snow load: long drooping tips, thick shell reaching the tips
    "pine_f": dict(seed=57, points=7, snow_t=0.14, trunk=(0.23, 0.09), droop=0.22, inner=0.64, tcut=(0.03, 0.0),
                   mound_h=0.30, tiers=[
        (1.10, 1.75, 1.45), (1.95, 1.55, 1.35), (2.75, 1.32, 1.25), (3.50, 1.08, 1.15), (4.20, 0.82, 1.05),
        (4.85, 0.52, 1.10)]),
    "pine_young": dict(seed=63, points=6, snow_t=0.06, trunk=(0.075, 0.03), droop=0.10, mound_h=0.14, tiers=[
        (0.35, 0.85, 0.70), (0.80, 0.70, 0.62), (1.22, 0.55, 0.58), (1.60, 0.40, 0.55, 5), (1.95, 0.25, 0.55, 5)]),
}

# double crown: common lower tiers + two leaders (centres offset in x/y)
PINE_E = dict(seed=49, points=7, snow_t=0.085, droop=0.12, tops=[6, 9], tiers=[
    (1.20, 2.10, 1.40), (2.10, 1.85, 1.30), (2.95, 1.60, 1.25), (3.75, 1.30, 1.15, 6),
    (4.45, 0.95, 1.10, 5, 0.52, 0.10), (5.20, 0.72, 1.00, 5, 0.55, 0.12), (5.90, 0.46, 1.05, 5, 0.58, 0.14),
    (4.30, 0.85, 1.00, 5, -0.46, -0.16), (4.98, 0.60, 0.95, 5, -0.49, -0.18), (5.55, 0.38, 0.95, 4, -0.52, -0.20)])


def tree_col(r, h=3.0):
    """Trunk cylinder proxy (Blender centre, [radius, height])."""
    return (0.0, 0.0, h / 2), (r, h)


def build_pine(name):
    lp.new_scene()
    cfg = PINES[name]
    parts = V.pine(cfg)
    r = cfg["trunk"][0] + 0.06
    c, sz = tree_col(r, 3.0 if name != "pine_young" else 1.6)
    V.export_scatter(name, parts, "Tree", "pine", "cylinder", c, sz, choppable=True, ao=PINE_AO)


def build_pine_e():
    lp.new_scene()
    tiers, rnd = V.pine_tiers(PINE_E)
    fork = Vector((0.03, 0.0, 4.15))
    main = V.pine_trunk(0.26, 0.15, fork.z)
    leaders = []
    for cx, cy, top in ((0.58, 0.14, 5.9), (-0.52, -0.20, 5.55)):
        leaders.append(V.trunk([fork + Vector((0, 0, -0.3)), Vector((cx * 0.6, cy * 0.6, fork.z + 0.5)),
                                Vector((cx, cy, fork.z + 1.1)), Vector((cx, cy, top))],
                               [0.14, 0.12, 0.09, 0.05], sides=5))
    mound = V.base_mound(rnd, PINE_E["tiers"][0][1], PINE_E["seed"])
    c, sz = tree_col(0.32)
    V.export_scatter("pine_e", [tiers, main] + leaders + [mound], "Tree", "pine", "cylinder", c, sz, choppable=True,
                     ao=PINE_AO)


# ------------------------------------------------------------------------------------------------------------
def top_ring(pts, radii, sides=7):
    t = (pts[-1] - pts[-2]).normalized()
    return lp.ring(pts[-1], t, radii[-1], sides, 0.0), pts[-1], t


def build_dead_tree_b():
    """Broken snag: tall leaning trunk cut off at 5.3 m with a splintered top, five short limbs (broken ends
    showing light wood), a few twigs, snow on the upper faces."""
    lp.new_scene()
    br, tpts, trad, k_len = V.bare_tree(seed=71, height=6.0, n1=6, n2=2, n3=1, top_twigs=0, trunk_r=0.34,
                                        trunk_len=5.6, lean=(0.12, 0.05), limb_k=0.62, t_range=(0.28, 0.50),
                                        limb_cap="wood_light", trunk_taper=0.62)
    br.snow(1.0)
    tree = H.smooth(H.mk(br.mb))
    ring_, c, t = top_ring(tpts, trad)
    rnd = random.Random(72)
    splinters = V.broken_cap(ring_, c, t, rnd, length=0.55)
    # two dead stubs low on the trunk (broken off, light wood ends)
    stubs = lp.MeshBuilder()
    for (tt, az) in ((0.18, 40), (0.24, 220)):
        p, r, d = V.radius_at(tpts, trad, tt)
        dd = V.rot_towards(d, az, 70)
        H.tube(stubs, [p, p + dd * 0.32], [0.07, 0.05], 5, "bark_grey", cap_end=True)
        stubs.faces[-1][1] = "wood_light"
    stub_o = H.smooth(H.mk(stubs))
    mound = H.mound((0, 0, 0), 0.72, 0.2, seed=71, sides=14, sink=0.2)
    c_, sz = tree_col(0.40)
    V.export_scatter("dead_tree_b", [tree, splinters, stub_o, mound], "Tree", "dead_tree", "cylinder", c_, sz,
                     choppable=True, ao=BARE_AO)


def build_dead_tree_c():
    """Small dead multi-stem tree: three leaning stems from one base, twiggy crowns."""
    lp.new_scene()
    br = None
    for k, (seed, h, r, lean, base, n1) in enumerate((
            (81, 3.4, 0.12, (0.10, 0.04), (0.04, 0.02), 6),
            (82, 2.9, 0.095, (-0.32, 0.12), (-0.07, 0.05), 5),
            (83, 2.5, 0.08, (0.12, -0.36), (0.02, -0.07), 4))):
        br, tpts, trad, k_len = V.bare_tree(seed=seed, height=h, n1=n1, n2=2, n3=2, top_twigs=3, trunk_r=r,
                                            trunk_len=6.4, lean=lean, limb_k=0.9, t_range=(0.30, 0.58), br=br,
                                            base=base)
    br.snow(0.8)
    tree = H.smooth(H.mk(br.mb))
    mound = H.mound((0, 0, 0), 0.5, 0.16, seed=81, sides=12, sink=0.2)
    c_, sz = tree_col(0.25, 2.0)
    V.export_scatter("dead_tree_c", [tree, mound], "Tree", "dead_tree", "cylinder", c_, sz, choppable=True,
                     ao=BARE_AO)


def build_birch():
    """Leafless birch: slender white trunk with dark bands and lenticel marks, upright limbs, dark fine twigs."""
    lp.new_scene()
    br, tpts, trad, k_len = V.bare_tree(seed=91, height=7.0, n1=13, n2=2, n3=2, top_twigs=5, trunk_r=0.19,
                                        trunk_len=6.6, lean=(0.03, -0.02), limb_k=1.05, t_range=(0.34, 0.58),
                                        el_range=(30, 50), mat="paint_white", trunk_segs=6, trunk_taper=0.18)
    rnd = random.Random(92)
    mb = br.mb
    for (a, b), depth in br.bands:
        for fi in range(a, b):
            if depth >= 2:
                mb.faces[fi][1] = "bark"                        # fine twigs: dark red-brown
            elif mb.center(fi).z < 0.45:
                mb.faces[fi][1] = "bark_grey" if rnd.random() < 0.7 else "paint_white"   # dark rough foot
            elif rnd.random() < (0.16 if depth == 0 else 0.28):
                mb.faces[fi][1] = "paint_black" if rnd.random() < 0.5 else "bark_grey"   # bands / lenticels
    br.snow(1.2, nz=0.75)
    tree = H.smooth(H.mk(mb))
    mound = H.mound((0, 0, 0), 0.55, 0.16, seed=91, sides=12, sink=0.2)
    c_, sz = tree_col(0.24)
    V.export_scatter("birch", [tree, mound], "Tree", "birch", "cylinder", c_, sz, choppable=True, ao=BARE_AO)


def main():
    for name in PINES:
        build_pine(name)
    build_pine_e()
    build_dead_tree_b()
    build_dead_tree_c()
    build_birch()


if __name__ == "__main__":
    main()
