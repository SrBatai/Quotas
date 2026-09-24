"""rock_a, rock_b, rock_c, stone (ASSET_SPEC §4.7-4.8)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402,F401  (must precede mathutils)

from lib import export  # noqa: E402
from lib import lowpoly as lp  # noqa: E402

# name: (dims X, Y, Z), [(center, radii)], seed
ROCKS = {
    "rock_a": ((1.2, 1.0, 0.7), [((0, 0, 0.14), (0.6, 0.5, 0.36))], 3),
    "rock_b": ((2.2, 1.8, 1.2), [((-0.32, -0.05, 0.22), (0.78, 0.8, 0.62)),
                                 ((0.5, 0.22, 0.12), (0.62, 0.62, 0.46))], 8),
    "rock_c": ((0.6, 0.5, 0.35), [((0, 0, 0.07), (0.3, 0.25, 0.18))], 21),
}


def build_rock(name):
    dims, blobs, seed = ROCKS[name]
    lp.new_scene()
    rnd = lp.rng(seed)
    mb = lp.MeshBuilder()
    for center, radii in blobs:
        # icosphere subdiv 1, jitter +-10 %, (radii already flattened to ~60 % on Z), flat bottom
        mb.blob(center, radii, "stone", subdiv=1, jitter=0.10, rnd=rnd, clamp_z=0.0, drop_bottom=True)
    lp.fit_bounds(mb, dims)
    lp.stone_rule(mb)
    lp.to_object(mb, "Rock")
    export.save_and_export(name)


def build_stone():
    lp.new_scene()
    rnd = lp.rng(4)
    mb = lp.MeshBuilder()
    mb.blob((0, 0, 0.035), (0.15, 0.125, 0.12), "stone", subdiv=0, jitter=0.12, rnd=rnd, clamp_z=0.0,
            drop_bottom=True)
    lp.fit_bounds(mb, (0.30, 0.25, 0.20))
    # a snow top face or two: the two most upward-facing faces
    order = sorted(range(len(mb.faces)), key=lambda i: -mb.normal(i).z)
    for fi in order[:2]:
        mb.faces[fi][1] = "snow"
    for fi in range(len(mb.faces)):
        if mb.normal(fi).z < -0.5:
            mb.faces[fi][1] = "stone_dark"
    lp.to_object(mb, "Stone")
    export.save_and_export("stone")


def main():
    for name in ROCKS:
        build_rock(name)
    build_stone()


if __name__ == "__main__":
    main()
