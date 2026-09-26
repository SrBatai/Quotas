"""firewood, fallen_log (slice ASSET_SPEC §4.10-4.11; ASSET_SPEC_V2 §13/§17: one palette_vcol surface, no front)."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402,F401  (must precede mathutils)
from mathutils import Vector  # noqa: E402

from lib import export  # noqa: E402
from lib import lowpoly as lp  # noqa: E402

X = (1, 0, 0)


def split_log(mb, length, r, xf, snow_nz=0.9):
    """Half-cylinder (6 facets) along X, split face down at z = 0: bark outside, wood_light cuts."""
    n = 6
    prof = [Vector((0, r * math.cos(math.pi * i / n), r * math.sin(math.pi * i / n))) for i in range(n + 1)]
    r0 = [p + Vector((-length / 2, 0, 0)) for p in prof]
    r1 = [p + Vector((length / 2, 0, 0)) for p in prof]
    faces = mb.loft([r0, r1], "bark", xf=xf)
    for fi in faces:
        nrm = mb.normal(fi)
        axis = (xf.to_3x3() @ Vector(X)).normalized()
        if abs(nrm.dot(axis)) > 0.9:
            mb.faces[fi][1] = "wood_light"            # end cuts
        elif nrm.z < -0.8:
            mb.faces[fi][1] = "wood_light"            # split face (underside)
        elif nrm.z > snow_nz:
            mb.faces[fi][1] = "snow"
    return faces


def build_firewood():
    lp.new_scene()
    mb = lp.MeshBuilder()
    split_log(mb, 0.50, 0.10, lp.move((0.0, 0.07, 0.0)), snow_nz=0.99)
    xf2 = lp.rot('Z', 78) @ lp.move((0.0, 0.0, 0.075)) @ lp.rot('Y', -9)
    split_log(mb, 0.50, 0.10, lp.move((0.02, -0.03, 0.0)) @ xf2, snow_nz=0.9)
    lp.clamp_ground(mb)
    lp.to_object(mb, "Firewood")
    export.save_and_export("firewood")


def build_fallen_log():
    """fallen_log (slice §4.11, v2 §13/§17; HD v2.1 in M3 with the vegetation/build_logs.py recipe): one object `Log`,
    1.6 m along X, 0.40 m high with its snow (the code's chop box 1.6 x 0.4 x 0.4). Smooth bark tube with sawn ends
    (growth rings), two broken branch stubs, rounded snow line on top, a little drift on one side."""
    from lib import hd as H
    from lib import veg as V
    from vegetation.build_logs import stubs
    lp.new_scene()
    r0, r1 = 0.185, 0.17
    parts, pts, radii = V.log_body((-0.8, 0, r0 - 0.01), (0.8, 0.0, r1 - 0.01), r0, r1, sides=10, segs=3, bend=0.03,
                                   seed=141, cap0="rings", cap1="rings")
    parts.append(stubs(pts, radii, [(0.35, 60, 0.2, 0.05), (0.7, 250, 0.16, 0.042)]))
    parts.append(V.snow_on_log(pts, radii, width_k=1.2, thick=0.055, seed=142))
    parts.append(H.mound((0.1, -0.26, 0), 0.4, 0.12, seed=143, sides=10, sink=0.05, stretch=(1.6, 0.5)))
    H.join(parts, "Log")
    export.save_and_export("fallen_log", ao=dict(distance=0.4, samples=64, ground=True))


def main():
    build_firewood()
    build_fallen_log()


if __name__ == "__main__":
    main()
