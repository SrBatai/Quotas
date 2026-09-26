"""berry_bush (slice ASSET_SPEC §4.9; ASSET_SPEC_V2 §13/§17: keeps the child `Berries` the code hides; no front).

M3 HD (guide v2.1): the shrub recipe of vegetation/build_bushes.py (lumpy faceted foliage lobes, spiky tufts, smooth
snow caps draped on the tops) in the slightly brighter `bush` green that marks it as interactive, with 16 berries in
five clusters as the separate child `Berries` (pivot at the bush origin, hidden by berry_bush.gd after picking).
Size unchanged (1.0 x 1.0 x 0.55 m, the code's sphere collider r 0.5 at 0.4).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402,F401  (must precede mathutils)

from lib import export  # noqa: E402
from lib import hd as H  # noqa: E402
from lib import lowpoly as lp  # noqa: E402
from vegetation.build_bushes import berries, shrub  # noqa: E402


def build_berry_bush():
    lp.new_scene()
    lobes = [((0.02, 0.08, 0.13), (0.40, 0.38, 0.28)), ((-0.22, -0.14, 0.10), (0.31, 0.29, 0.24)),
             ((0.24, -0.12, 0.08), (0.29, 0.27, 0.22)), ((0.20, 0.28, 0.06), (0.22, 0.20, 0.17))]
    parts, bvh, rnd = shrub(7, lobes, top="bush", side="pine_light", under="pine_mid", tufts=6, tuft_mat="pine_light",
                            caps=[(0.02, 0.08, 0.26, 0.24, 0.05), (-0.22, -0.14, 0.18, 0.16, 0.04)], sink=0.02)
    bush = H.join(parts, "Bush")
    b = berries(bvh, rnd, [(0.25, 0.10, 4, 0.07), (-0.10, 0.32, 3, 0.06), (-0.30, -0.25, 3, 0.07),
                           (0.25, -0.30, 3, 0.06), (0.35, 0.30, 3, 0.05)], r=(0.036, 0.046))
    H.join([b], "Berries", parent=bush)
    export.save_and_export("berry_bush", ao=dict(distance=0.4, samples=64, ground=True))


def main():
    build_berry_bush()


if __name__ == "__main__":
    main()
