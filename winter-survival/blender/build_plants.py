"""berry_bush (slice ASSET_SPEC §4.9; ASSET_SPEC_V2 §13/§17: keeps the child `Berries` the code hides; no front)."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402,F401  (must precede mathutils)
from mathutils import Vector  # noqa: E402
from mathutils.bvhtree import BVHTree  # noqa: E402

from lib import export  # noqa: E402
from lib import lowpoly as lp  # noqa: E402


def build_berry_bush():
    lp.new_scene()
    rnd = lp.rng(7)
    mb = lp.MeshBuilder()
    # union of 3 jittered icospheres (r 0.35 / 0.40 / 0.30, offsets +-0.2), bottom clipped at z = 0
    for center, r in (((0.02, 0.14, 0.12), 0.40), ((-0.2, -0.13, 0.08), 0.35), ((0.22, -0.12, 0.05), 0.30)):
        mb.blob(center, (r, r, r * 0.9), "bush", subdiv=1, jitter=0.08, rnd=rnd, clamp_z=0.0,
                drop_bottom=True, snow=True)
    lp.fit_bounds(mb, (1.0, 1.0, 0.55))
    mb.snow(0.6)
    bush = lp.to_object(mb, "Bush")

    # berries: 10 tiny icospheres in 4 clusters on the upper surface (found by ray casting)
    bvh = BVHTree.FromPolygons([v.copy() for v in mb.verts], [f[0] for f in mb.faces])
    berries = lp.MeshBuilder()
    clusters = [(0.25, 30), (0.28, 140), (0.22, 250), (0.12, 330)]
    counts = [3, 3, 2, 2]
    for (rad, az), cnt in zip(clusters, counts):
        a = math.radians(az)
        cx, cy = rad * math.cos(a), rad * math.sin(a)
        placed = 0
        tries = 0
        while placed < cnt and tries < 50:
            tries += 1
            x = cx + rnd.uniform(-0.07, 0.07)
            y = cy + rnd.uniform(-0.07, 0.07)
            hit = bvh.ray_cast(Vector((x, y, 2.0)), Vector((0, 0, -1)))
            if hit[0] is None or hit[1].z < 0.12:
                continue
            p = hit[0] + hit[1].normalized() * 0.02
            berries.blob(p, 0.045, "berry", subdiv=0, jitter=0.0, rnd=rnd)
            placed += 1
    lp.to_object(berries, "Berries", pivot=(0, 0, 0), parent=bush)
    export.save_and_export("berry_bush")


def main():
    build_berry_bush()


if __name__ == "__main__":
    main()
