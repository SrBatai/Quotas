"""M3 bushes for the MultiMesh forest (ASSET_SPEC_V2 §13 + "M3"): bush_a, bush_b -> assets/models/vegetation/.

    cd winter-survival/blender && python3 vegetation/build_bushes.py

MultiMesh contract: ONE object `Bush`, ONE palette_vcol surface, no children / empties / collision, origin at the
base centre, no front. Collision proxy (node extras + manifest): sphere r 0.45-0.5 (like the slice berry_bush).

  bush_a  evergreen juniper mound 1.4 x 1.2 x 0.8 m: lumpy faceted foliage lobes (pine greens, dark underside),
          small spiky tufts breaking the silhouette, smooth snow caps draped on the tops
  bush_b  dark holly-like shrub 1.1 x 1.0 x 0.85 m with RED BERRIES baked in (decorative twin of the interactive
          berry_bush, which keeps its separate `Berries` child; see ASSET_SPEC_V2 "M3" for the readability note)

The shared recipe (lobes + tufts + draped caps + berry clusters) is `shrub()` here; build_plants.py (berry_bush HD)
uses it too.
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import bpy  # noqa: E402,F401  (must precede mathutils)
from mathutils import Vector  # noqa: E402
from mathutils.bvhtree import BVHTree  # noqa: E402

from lib import hd as H  # noqa: E402
from lib import lowpoly as lp  # noqa: E402
from lib import veg as V  # noqa: E402

BUSH_AO = dict(distance=0.5, samples=64, ground=True)


def shrub(seed, lobes, top="pine_light", side="pine_mid", under="pine_dark", tufts=0, tuft_mat="pine_mid",
          caps=(), jitter=0.16, sink=0.03):
    """Foliage lobes [(centre, radii)] (faceted icospheres subdiv 1, bottom clipped at z = 0 then sunk `sink`),
    coloured top / side / under by normal; `tufts` small star cones on the upper surface; snow caps
    [(x, y, rx, ry, thick)] draped on the foliage. Returns (objects, foliage BVH for berry placement)."""
    rnd = random.Random(seed)
    mb = lp.MeshBuilder()
    for center, radii in lobes:
        f0 = len(mb.faces)
        mb.blob(center, radii, top, subdiv=1, jitter=jitter, rnd=rnd, clamp_z=0.0, drop_bottom=True)
        for fi in range(f0, len(mb.faces)):
            nz = mb.normal(fi).z
            mb.faces[fi][1] = top if nz > 0.55 else (under if nz < -0.1 else side)
    for v in mb.verts:
        v.z -= sink
    bvh = BVHTree.FromPolygons([v.copy() for v in mb.verts], [f[0] for f in mb.faces])
    foliage = H.flat(H.mk(mb))
    zf = V.surface_fn(foliage)
    parts = [foliage]
    if tufts:
        tb = lp.MeshBuilder()
        placed = 0
        tries = 0
        while placed < tufts and tries < 200:
            tries += 1
            a = rnd.uniform(0, 2 * math.pi)
            r = rnd.uniform(0.1, 0.55)
            x, y = math.cos(a) * r, math.sin(a) * r
            hit = bvh.ray_cast(Vector((x, y, 5.0)), Vector((0, 0, -1)))
            if hit[0] is None or hit[1].z < 0.35:
                continue
            p = hit[0] - hit[1] * 0.04
            d = (hit[1] + Vector((0, 0, 0.8))).normalized()
            n = 5
            rr = rnd.uniform(0.07, 0.11)
            base = lp.ring(p, d, rr, n, rnd.uniform(0, 60))
            tb.loft([base, [p + d * rnd.uniform(0.16, 0.26)]], tuft_mat, cap_start=False, cap_end=False)
            placed += 1
        if tb.faces:
            parts.append(H.flat(H.mk(tb)))
    for k, (x, y, rx, ry, t) in enumerate(caps):
        parts.append(H.snow_cap((x, y, 0), rx, ry, t, zf, seed=seed + k, sides=10, rings=3, droop=0.02))
    return parts, bvh, rnd


def berries(bvh, rnd, clusters, r=(0.034, 0.044), min_nz=0.05):
    """Berry clusters [(x, y, count, spread)] on the foliage surface (ray cast from above), smooth icosahedra."""
    mb = lp.MeshBuilder()
    for cx, cy, cnt, spread in clusters:
        placed = 0
        tries = 0
        while placed < cnt and tries < 60:
            tries += 1
            x = cx + rnd.uniform(-spread, spread)
            y = cy + rnd.uniform(-spread, spread)
            d = Vector((x * 0.35, y * 0.35, -1.0)).normalized()
            hit = bvh.ray_cast(Vector((x, y, 0)) - d * 3.0, d)
            if hit[0] is None or hit[1].z < min_nz:
                continue
            rr = rnd.uniform(*r)
            octa(mb, hit[0] + hit[1].normalized() * rr * 0.6, rr, rnd.uniform(0, 1.0))
            placed += 1
    return H.smooth(H.mk(mb))


def octa(mb, c, r, spin=0.0, mat="berry"):
    """Smooth-shaded octahedron berry (8 tris: at 2-3 px a berry only needs to be a round dot)."""
    import math as _m
    c = Vector(c)
    ca, sa = _m.cos(spin), _m.sin(spin)
    pts = [c + Vector((ca * r, sa * r, 0)), c + Vector((-sa * r, ca * r, 0)), c + Vector((-ca * r, -sa * r, 0)),
           c + Vector((sa * r, -ca * r, 0)), c + Vector((0, 0, r)), c + Vector((0, 0, -r))]
    faces = [(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4), (1, 0, 5), (2, 1, 5), (3, 2, 5), (0, 3, 5)]
    mb.solid(pts, faces, mat, inside=c)


def build_bush_a():
    lp.new_scene()
    lobes = [((0.05, 0.05, 0.28), (0.52, 0.46, 0.46)), ((-0.40, -0.10, 0.18), (0.40, 0.36, 0.34)),
             ((0.42, -0.18, 0.16), (0.38, 0.34, 0.32)), ((0.12, 0.40, 0.14), (0.36, 0.30, 0.30)),
             ((-0.18, -0.38, 0.10), (0.30, 0.26, 0.24))]
    parts, _bvh, _rnd = shrub(101, lobes, top="moss", side="pine_light", under="pine_mid", tufts=9,
                              tuft_mat="pine_light",
                              caps=[(0.05, 0.05, 0.36, 0.30, 0.09), (-0.42, -0.10, 0.22, 0.2, 0.06),
                                    (0.42, -0.2, 0.2, 0.18, 0.06)])
    V.export_scatter("bush_a", parts, "Bush", "bush", "sphere", (0, 0, 0.35), (0.5,), ao=BUSH_AO)


def build_bush_b():
    lp.new_scene()
    lobes = [((0.0, 0.0, 0.36), (0.40, 0.38, 0.46)), ((-0.30, 0.10, 0.22), (0.32, 0.30, 0.32)),
             ((0.30, -0.08, 0.24), (0.32, 0.30, 0.34)), ((0.04, -0.30, 0.16), (0.28, 0.24, 0.26))]
    parts, bvh, rnd = shrub(111, lobes, top="pine_light", side="pine_mid", under="pine_dark", tufts=6,
                            tuft_mat="pine_mid", caps=[(0.0, 0.02, 0.26, 0.24, 0.07), (0.3, -0.08, 0.16, 0.15, 0.05)])
    parts.append(berries(bvh, rnd, [(0.25, 0.20, 4, 0.08), (-0.30, 0.25, 4, 0.08), (0.30, -0.28, 3, 0.07),
                                    (-0.28, -0.22, 3, 0.07), (0.05, 0.36, 3, 0.07)]))
    V.export_scatter("bush_b", parts, "Bush", "bush", "sphere", (0, 0, 0.38), (0.45,), ao=BUSH_AO)


def main():
    build_bush_a()
    build_bush_b()


if __name__ == "__main__":
    main()
