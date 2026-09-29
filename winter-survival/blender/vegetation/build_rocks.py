"""M3 rocks for the MultiMesh forest (ASSET_SPEC_V2 §13 + "M3"): rock_d, rock_e, rock_f -> assets/models/vegetation/.

    cd winter-survival/blender && python3 vegetation/build_rocks.py

Same recipe as the G1 rocks (build_rocks.py): FACETED jittered icospheres (the facets are the look), `stone` sides,
`stone_dark` steep / under faces, a smooth rounded snow cap draped on each top (rim drooping into the stone), sunk
3 cm. ONE object `Rock`, ONE palette_vcol surface, no children / collision; collision proxy in the node extras +
manifest (box).

  rock_d  flat tilted slab 2.4 x 1.6 x 0.55 m, snow over most of the top
  rock_e  outcrop 3.4 x 2.7 x 2.3 m: three stacked boulders, caps on each, windward drift
  rock_f  scree cluster 1.9 x 1.5 x 0.5 m: five small stones, caps on the three biggest
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import bpy  # noqa: E402,F401  (must precede mathutils)

from lib import hd as H  # noqa: E402
from lib import lowpoly as lp  # noqa: E402
from lib import veg as V  # noqa: E402

# name: dims, blobs [(centre, radii, subdiv)], seed, caps [(x, y, rx, ry, thick)], drifts, tilt (dz per m of x),
# collision box (Blender centre, Godot size [x, y, z])
ROCKS = {
    "rock_d": dict(dims=(2.4, 1.6, 0.55), seed=33, tilt=0.07,
                   blobs=[((0, 0, 0.1), (1.2, 0.8, 0.34), 2)],
                   caps=[(0.05, 0.0, 0.95, 0.62, 0.09)],
                   drifts=[((-0.95, -0.72, 0), 0.5, 0.2, (1.0, 0.7))],
                   col=((0, 0, 0.25), (2.3, 0.5, 1.5))),
    "rock_e": dict(dims=(3.4, 2.7, 2.3), seed=37, tilt=0.0,
                   blobs=[((-0.3, 0.1, 0.55), (1.45, 1.2, 1.25), 2), ((1.05, 0.35, 0.3), (0.85, 0.85, 0.75), 1),
                          ((0.2, -0.95, 0.1), (0.7, 0.55, 0.5), 1)],
                   caps=[(-0.35, 0.12, 0.85, 0.72, 0.13), (1.12, 0.38, 0.45, 0.42, 0.09),
                         (0.22, -1.0, 0.36, 0.28, 0.07)],
                   drifts=[((-1.2, -0.9, 0), 0.8, 0.42, (1.0, 0.8)), ((1.5, -0.4, 0), 0.5, 0.25, (0.8, 1.0))],
                   col=((0, 0, 1.0), (3.0, 2.0, 2.3))),
    "rock_f": dict(dims=(1.9, 1.5, 0.5), seed=39, tilt=0.0,
                   blobs=[((-0.45, 0.1, 0.1), (0.36, 0.3, 0.28), 1), ((0.35, 0.25, 0.08), (0.3, 0.26, 0.24), 1),
                          ((0.1, -0.4, 0.05), (0.26, 0.22, 0.2), 1), ((0.75, -0.25, 0.02), (0.16, 0.14, 0.13), 1),
                          ((-0.8, -0.35, 0.02), (0.17, 0.15, 0.12), 1)],
                   caps=[(-0.45, 0.1, 0.22, 0.18, 0.06), (0.35, 0.25, 0.18, 0.16, 0.05),
                         (0.1, -0.4, 0.14, 0.12, 0.04)],
                   drifts=[],
                   col=((0, 0, 0.2), (1.6, 0.4, 1.2))),
}


def build_rock(name):
    cfg = ROCKS[name]
    lp.new_scene()
    rnd = lp.rng(cfg["seed"])
    mb = lp.MeshBuilder()
    for center, radii, subdiv in cfg["blobs"]:
        mb.blob(center, radii, "stone", subdiv=subdiv, jitter=0.07 if subdiv == 2 else 0.11, rnd=rnd, clamp_z=0.0,
                drop_bottom=True)
    lp.fit_bounds(mb, cfg["dims"])
    for v in mb.verts:
        v.z += cfg["tilt"] * v.x * (v.z / cfg["dims"][2])
        v.z -= 0.03
    V.color_by_normal(mb, range(len(mb.faces)), side="stone", under="stone_dark", under_nz=0.12)
    body = H.flat(H.mk(mb))
    zf = V.surface_fn(body)
    parts = [body]
    for k, (x, y, rx, ry, t) in enumerate(cfg["caps"]):
        parts.append(H.snow_cap((x, y, 0), rx, ry, t, zf, seed=cfg["seed"] + k, sides=12 if rx > 0.3 else 9,
                                rings=3, droop=0.02))
    for k, (c, r, h, st) in enumerate(cfg["drifts"]):
        parts.append(H.mound(c, r, h, seed=cfg["seed"] + 10 + k, sides=10, sink=0.08, stretch=st))
    cc, size = cfg["col"]
    V.export_scatter(name, parts, "Rock", "rock", "box", cc, size,
                     ao=dict(distance=min(0.6, 0.4 * max(cfg["dims"])), samples=64, ground=True))


def main():
    for name in ROCKS:
        build_rock(name)


if __name__ == "__main__":
    main()
