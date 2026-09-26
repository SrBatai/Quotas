"""M3 fallen logs for the MultiMesh forest (ASSET_SPEC_V2 §13 + "M3"): fallen_log_b, fallen_log_c ->
assets/models/vegetation/. (The slice `fallen_log` keeps its name / node `Log` / size in build_pickups.py and
uses the same recipe since M3.)

    cd winter-survival/blender && python3 vegetation/build_logs.py

Recipe (lib/veg.py): smooth bark tube (10 sides, slightly bent), sawn end = flat face with growth rings, broken end
= splintered light wood, broken branch stubs with light-wood tips, moss patches on the sides, a rounded snow line
along the top and a small drift against the windward side. ONE object `Log`, ONE palette_vcol surface, no
collision; proxy (node extras + manifest): box along X; choppable like the slice fallen_log.

  fallen_log_b  long log 3.4 m (r 0.24 -> 0.19): sawn end (-X), splintered end (+X), three stubs, moss
  fallen_log_c  wind-thrown trunk 2.9 m with its upturned ROOT PLATE (1.6 m disc of roots and frozen dirt) at -X
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

LOG_AO = dict(distance=0.5, samples=64, ground=True)


def stubs(pts, radii, specs, mat="bark"):
    """Broken branch stubs [(t along the log, azimuth deg around it, length, radius)] with light-wood tips."""
    mb = lp.MeshBuilder()
    for t, az, length, r in specs:
        p, rr, d = V.radius_at([Vector(q) for q in pts], radii, t)
        out = V.rot_towards(d, az, 80)
        base = p + out * (rr * 0.6)
        H.tube(mb, [base, base + out * length], [r, r * 0.75], 5, mat, cap_end=True)
        mb.faces[-1][1] = "wood_light"
    return H.smooth(H.mk(mb))


def mossify(obj, rnd, frac=0.10, zmin=0.08):
    """Recolour some side faces of a bark object `moss` (patches: neighbours follow)."""
    me = obj.data
    from lib import palette
    idx = []
    for p in me.polygons:
        n = p.normal
        c = p.center
        if -0.2 < n.z < 0.45 and c.z > zmin and rnd.random() < frac:
            idx.append(p.index)
    if idx:
        palette.paint(obj, idx, "moss")


def build_fallen_log_b():
    lp.new_scene()
    rnd = random.Random(121)
    r0, r1 = 0.24, 0.19
    parts, pts, radii = V.log_body((-1.7, 0, r0 - 0.03), (1.7, 0.05, r1 - 0.03), r0, r1, sides=10, segs=4,
                                   bend=0.07, seed=121, cap0="rings", cap1="broken")
    mossify(parts[0], rnd)
    parts.append(stubs(pts, radii, [(0.30, 70, 0.26, 0.06), (0.55, 250, 0.2, 0.05), (0.78, 110, 0.3, 0.055)]))
    parts.append(V.snow_on_log(pts, radii, width_k=1.25, thick=0.07, seed=122))
    parts.append(H.mound((0.2, -0.32, 0), 0.55, 0.16, seed=123, sides=12, sink=0.06, stretch=(2.2, 0.55)))
    V.export_scatter("fallen_log_b", parts, "Log", "log", "box", (0, 0, 0.22), (3.4, 0.45, 0.5), choppable=True,
                     ao=LOG_AO)


def root_plate(center, radius, thick, rnd, n=14):
    """Vertical disc (plane YZ, facing +-X) of roots and frozen dirt, jagged rim, root spokes, snow on its top."""
    c = Vector(center)
    mb = lp.MeshBuilder()
    rim = []
    for i in range(n):
        a = 2 * math.pi * i / n
        r = radius * rnd.uniform(0.78, 1.08)
        rim.append(Vector((0, math.cos(a) * r, math.sin(a) * r * 0.85)))
    front = [c + p + Vector((-thick / 2, 0, 0)) for p in rim]
    back = [c + p * 0.92 + Vector((thick / 2, 0, 0)) for p in rim]
    mb.loft([front, back], "bark", cap_start=False, cap_end=False)
    mb.loft([front, [c + Vector((-thick * 0.9, 0, 0))]], "dirt", cap_start=False, cap_end=False,
            seg_facing=[(-1, 0, 0)])
    mb.loft([back, [c + Vector((thick * 0.3, 0, 0))]], "dirt", cap_start=False, cap_end=False,
            seg_facing=[(1, 0, 0)])
    plate = H.flat(H.mk(mb))
    roots = lp.MeshBuilder()
    for i in range(0, n, 2):
        p = c + rim[i] * 0.95 + Vector((-thick * 0.3, 0, 0))
        d = (rim[i].normalized() + Vector((rnd.uniform(-0.6, -0.1), 0, 0))).normalized()
        L = rnd.uniform(0.25, 0.5)
        pts = [p, p + d * L * 0.5 + Vector((0, 0, -0.05)), p + d * L]
        pts = [Vector((q.x, q.y, max(q.z, -0.12))) for q in pts]            # roots bend into the ground, not below it
        H.tube(roots, pts, [0.05, 0.035, 0.015], 4, "bark", cap_end=True)
    root_o = H.smooth(H.mk(roots))
    return plate, root_o


def build_fallen_log_c():
    lp.new_scene()
    rnd = random.Random(131)
    r0, r1 = 0.26, 0.17
    x0 = -1.15
    parts, pts, radii = V.log_body((x0, 0, r0 - 0.02), (1.75, -0.08, r1 - 0.03), r0, r1, sides=10, segs=4,
                                   bend=-0.06, seed=131, cap0=None, cap1="broken")
    mossify(parts[0], rnd, frac=0.08)
    plate, roots = root_plate((x0 - 0.12, 0.0, 0.64), 0.8, 0.26, rnd)
    parts += [plate, roots]
    parts.append(stubs(pts, radii, [(0.45, 90, 0.22, 0.055), (0.7, 280, 0.28, 0.05)]))
    parts.append(V.snow_on_log(pts[1:], radii[1:], width_k=1.2, thick=0.065, seed=132))
    ztop = max((plate.matrix_world @ v.co).z for v in plate.data.vertices)
    parts.append(H.snow_ridge((x0 - 0.12, -0.5, ztop - 0.07), (x0 - 0.12, 0.5, ztop - 0.07), 0.26, 0.08, seed=133,
                              overhang=0.0, droop=0.04))                  # snow line on the plate's upper edge
    parts.append(H.mound((x0 + 0.25, 0.0, 0), 0.75, 0.3, seed=134, sides=12, sink=0.08, stretch=(0.7, 1.3)))
    V.export_scatter("fallen_log_c", parts, "Log", "log", "box", (0.25, 0, 0.45), (3.1, 0.9, 1.7),
                     choppable=True, ao=LOG_AO)


def main():
    build_fallen_log_b()
    build_fallen_log_c()


if __name__ == "__main__":
    main()
