"""rock_a, rock_b, rock_c, stone (slice ASSET_SPEC §4.7-4.8; ASSET_SPEC_V2 §13/§17; HD v2.1 in G1).

    cd winter-survival/blender && python3 build_rocks.py

MultiMesh contract kept: one object (`Rock` / `Stone`), one palette_vcol surface, no front, sizes as the slice
(the code gives each variant a sphere collider). G1 (docs/research/05_graficos_arte.md §4.2/§4.3): the rocks stay
FACETED (part of the reference look) but denser (icosphere subdiv 2 on the boulders), `stone` on the sides and
`stone_dark` on steep / under faces; the snow is no longer painted faces but a smooth rounded cap draped on the top
of the rock (lib/hd.snow_cap, rim drooping into the stone so no seam shows) + a little drift on the windward foot
of the big boulder. `stone` (the pickup) keeps its slice shape with the v2.1 palette. AO baked in COLOR_0.a.
"""
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402,F401  (must precede mathutils)
from mathutils import Vector  # noqa: E402
from mathutils.bvhtree import BVHTree  # noqa: E402

from lib import export  # noqa: E402
from lib import hd as H  # noqa: E402
from lib import lowpoly as lp  # noqa: E402

# name: dims (X, Y, Z) of the stone body, blobs [(centre, radii, subdiv)], seed, snow caps [(x, y, rx, ry, thick)]
ROCKS = {
    "rock_a": ((1.2, 1.0, 0.64), [((0, 0, 0.14), (0.6, 0.5, 0.36), 2)], 3,
               [(-0.04, 0.02, 0.46, 0.38, 0.10)]),
    "rock_b": ((2.2, 1.8, 1.12), [((-0.32, -0.05, 0.22), (0.78, 0.8, 0.62), 2),
                                  ((0.5, 0.22, 0.12), (0.62, 0.62, 0.46), 2)], 8,
               [(-0.36, -0.05, 0.62, 0.58, 0.12), (0.55, 0.25, 0.40, 0.36, 0.09)]),
    "rock_c": ((0.6, 0.5, 0.32), [((0, 0, 0.07), (0.3, 0.25, 0.18), 1)], 21,
               [(0.0, 0.0, 0.22, 0.18, 0.06)]),
}


def surface_fn(obj):
    """z(x, y) of the top of `obj` (ray cast straight down)."""
    me = obj.data
    mw = obj.matrix_world
    tree = BVHTree.FromPolygons([mw @ v.co for v in me.vertices], [tuple(p.vertices) for p in me.polygons])

    def z(x, y):
        hit = tree.ray_cast(Vector((x, y, 50.0)), Vector((0, 0, -1)), 100.0)
        return hit[0].z if hit[0] is not None else 0.0
    return z


def build_rock(name):
    dims, blobs, seed, caps = ROCKS[name]
    lp.new_scene()
    rnd = lp.rng(seed)
    mb = lp.MeshBuilder()
    for center, radii, subdiv in blobs:
        mb.blob(center, radii, "stone", subdiv=subdiv, jitter=0.10 if subdiv == 1 else 0.07, rnd=rnd, clamp_z=0.0,
                drop_bottom=True)
    lp.fit_bounds(mb, dims)
    # sink 3 cm so a slope never shows the flat bottom edge
    for v in mb.verts:
        v.z -= 0.03
    for fi in range(len(mb.faces)):
        nz = mb.normal(fi).z
        mb.faces[fi][1] = "stone_dark" if nz < 0.12 else "stone"
    body = H.flat(H.mk(mb))
    zf = surface_fn(body)
    parts = [body]
    for k, (x, y, rx, ry, t) in enumerate(caps):
        parts.append(H.snow_cap((x, y, 0), rx, ry, t, zf, seed=seed + k, sides=12 if rx > 0.3 else 9, rings=3,
                                droop=0.02))
    if name == "rock_b":                                  # windward drift against the big boulder
        parts.append(H.mound((-0.72, -0.50, 0), 0.46, 0.24, seed=seed, sides=10, sink=0.08, stretch=(1.0, 0.75)))
    H.join(parts, "Rock")
    export.save_and_export(name, ao=dict(distance=min(0.6, 0.4 * max(dims)), samples=64, ground=True))


def build_stone():
    lp.new_scene()
    rnd = lp.rng(4)
    mb = lp.MeshBuilder()
    mb.blob((0, 0, 0.035), (0.15, 0.125, 0.12), "stone", subdiv=0, jitter=0.12, rnd=rnd, clamp_z=0.0,
            drop_bottom=True)
    lp.fit_bounds(mb, (0.30, 0.25, 0.20))
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
