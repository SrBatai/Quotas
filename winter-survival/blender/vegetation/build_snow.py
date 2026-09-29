"""M3 snow piles / drifts for the MultiMesh forest (ASSET_SPEC_V2 §13 + "M3"): snow_pile_a, snow_pile_b,
snow_pile_c, snow_drift_4 -> assets/models/vegetation/.

    cd winter-survival/blender && python3 vegetation/build_snow.py

Smooth snow (guide v2.1 §4.2): radial heaps with a bell profile + gaussian lobes + fbm noise, rim sunk 5 cm below
z = 0 (never floats on a slope), `snow` with `snow_deep` crests; the drift is a pillow with a long windward slope, a
steep lee face and a drooping cornice. ONE object `Snow`, ONE palette_vcol surface, no collision (proxy "none":
pass-through decoration; keep them off paths / doors), origin at the base centre.

  snow_pile_a  round pile 1.8 x 1.6 x 0.55 m
  snow_pile_b  big lumpy pile 2.9 x 2.3 x 0.85 m (three lobes)
  snow_pile_c  small low pile 1.2 x 0.9 x 0.3 m
  snow_drift_4 elongated drift 4.0 x 1.65 x 0.55 m with a cornice on the lee side (+Y)
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import bpy  # noqa: E402,F401  (must precede mathutils)
from mathutils import Vector  # noqa: E402

from lib import hd as H  # noqa: E402
from lib import lowpoly as lp  # noqa: E402
from lib import veg as V  # noqa: E402

SNOW_AO = dict(distance=0.6, samples=48, ground=True)

PILES = {
    "snow_pile_a": dict(rx=0.9, ry=0.8, h=0.46, seed=5, sides=16, rings=5, lobes=[(0.2, 0.1, 0.35, 0.1)]),
    "snow_pile_b": dict(rx=1.45, ry=1.15, h=0.62, seed=6, sides=18, rings=6,
                        lobes=[(-0.45, 0.15, 0.5, 0.2), (0.5, -0.2, 0.45, 0.14), (0.1, 0.5, 0.4, 0.1)]),
    "snow_pile_c": dict(rx=0.6, ry=0.45, h=0.28, seed=7, sides=12, rings=4, lobes=[]),
}


def build_pile(name):
    cfg = PILES[name]
    lp.new_scene()
    o = V.heap((0, 0, 0), cfg["rx"], cfg["ry"], cfg["h"], seed=cfg["seed"], sides=cfg["sides"], rings=cfg["rings"],
               sink=0.05, lobes_=cfg["lobes"], noise=0.10, crest=0.72)
    V.export_scatter(name, [o], "Snow", "snow", "none", ao=SNOW_AO)


def build_drift():
    lp.new_scene()
    L, D, Hh = 4.0, 1.55, 0.95
    crest_v = 1.12

    def top(u, v):
        end = H.smoothstep(0.0, 0.9, min(u, L - u))
        if v <= crest_v:
            prof = (v / crest_v) ** 1.35
        else:
            prof = 1.0 - ((v - crest_v) / (D - crest_v)) ** 0.8 * 0.92
        wob = 1.0 + 0.12 * H.fbm(u * 0.8, 3.1, 2, 4)
        return max(0.02, Hh * prof * end * wob)

    def lip(u, v):
        if v >= D - 1e-6:                                   # cornice: the lee rim overhangs and droops
            e = H.smoothstep(0.0, 0.9, min(u, L - u))
            return (0.0, 0.10 * e, -0.06 * e)
        return (0.0, 0.0, 0.0)
    o = H.pillow(Vector((-L / 2, -D / 2, -0.05)), (1, 0, 0), (0, 1, 0), (0, 0, 1), L, D, Hh, nu=9, nv=5, rim=0.22,
                 seed=8, top_fn=top, lip=lip, jitter=0.04, bottom=-0.05, levels=1)
    V.export_scatter("snow_drift_4", [o], "Snow", "snow", "none", ao=SNOW_AO)


def main():
    for name in PILES:
        build_pile(name)
    build_drift()


if __name__ == "__main__":
    main()
