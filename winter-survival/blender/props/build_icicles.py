"""icicles (ASSET_SPEC_V2 §13 "Nieve" + "M3") -> assets/models/props/icicles.glb.

    cd winter-survival/blender && python3 props/build_icicles.py

A 2.0 m strip of icicles to hang under eaves / gutters / rails: ONE object `Icicles`, ONE palette_vcol surface, no
children / collision. HANGING asset (ASSET_SPEC_V2 §2.2): origin = the middle of the eave line at the TOP (z = 0),
the strip runs along X (-1..+1 m), icicles hang to z = -0.55; a thin ice ridge along the top hides the joint. Tile it
every 2 m along an eave (random yaw 0/180 and x-flip keep the repeat invisible). `icicle_strip()` is reused by the
POIs (cabin_small / lookout_tower eaves). Smooth `ice` cones (5 sides) with a lighter `snow_deep` ridge; no AO ground.
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


def icicle_strip(p0, p1, seed=0, max_len=0.55, spacing=0.12, ridge=True, sides=5):
    """Icicles hanging below the line p0 -> p1 (points on the eave's underside edge). Returns one smooth object."""
    rnd = random.Random(seed)
    p0, p1 = Vector(p0), Vector(p1)
    L = (p1 - p0).length
    d = (p1 - p0).normalized()
    mb = lp.MeshBuilder()
    n = max(2, int(L / spacing))
    for k in range(n):
        t = (k + rnd.uniform(0.2, 0.8)) / n
        if rnd.random() < 0.18:
            continue                                            # gaps
        base = p0 + d * (L * t)
        ln = max_len * (rnd.uniform(0.15, 0.45) if rnd.random() < 0.6 else rnd.uniform(0.55, 1.0))
        r = 0.014 + 0.028 * (ln / max_len) * rnd.uniform(0.8, 1.2)
        tip = base + Vector((rnd.uniform(-0.02, 0.02), rnd.uniform(-0.02, 0.02), -ln))
        mid = base.lerp(tip, 0.35) + Vector((0, 0, 0))
        rings = [lp.ring(base + Vector((0, 0, 0.012)), (0, 0, 1), r, sides, rnd.uniform(0, 72)),
                 lp.ring(mid, (0, 0, 1), r * 0.62, sides, rnd.uniform(0, 72)), [tip]]
        mb.loft(rings, "ice", cap_start=True, cap_end=False)             # closed top: no see-through cone
    parts = [H.smooth(H.mk(mb))]
    if ridge:
        parts.append(H.snow_ridge(p0 + Vector((0, 0, 0.0)), p1, 0.07, 0.035, seed=seed + 1, overhang=0.0, droop=0.03,
                                  mat="ice"))
    return parts


def build_icicles():
    lp.new_scene()
    parts = icicle_strip((-1.0, 0, -0.036), (1.0, 0, -0.036), seed=3)     # ridge top at z ~ 0 (the eave line)
    V.export_scatter("icicles", parts, "Icicles", "ice", "none", subdir="props",
                     ao=dict(distance=0.2, samples=48, ground=False))


def main():
    build_icicles()


if __name__ == "__main__":
    main()
