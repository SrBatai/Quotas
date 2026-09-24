"""firewood, fallen_log (ASSET_SPEC §4.10-4.11)."""
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
    lp.new_scene()
    mb = lp.MeshBuilder()
    xs = [-0.8, -0.28, 0.27, 0.8]
    rs = [0.20, 0.19, 0.20, 0.185]
    offs = [(0.0, 0.0), (0.025, 0.004), (-0.02, 0.0), (0.012, -0.012)]
    rings = [lp.ring((x, dy, 0.20 + dz), X, r, 8, 0.0) for x, r, (dy, dz) in zip(xs, rs, offs)]
    faces = mb.loft(rings, "bark", cap_mats=("wood_light", "wood_light"), snow=True)
    # end caps: slight inner ring look via wood_light caps; snow on the upper faces
    mb.snow(0.55, faces)
    # broken branch stubs
    d = Vector((0.3, 0.75, 0.45)).normalized()
    p0 = Vector((0.15, 0.05, 0.25))
    mb.cylinder(p0, p0 + d * 0.24, 0.055, 0.042, 4, "bark", cap0=False, cap_mats=(None, "wood_light"),
                phase=45)
    d2 = Vector((-0.2, -0.85, 0.35)).normalized()
    p1 = Vector((-0.45, -0.05, 0.22))
    mb.cylinder(p1, p1 + d2 * 0.22, 0.045, 0.035, 4, "bark", cap0=False, cap_mats=(None, "wood_light"),
                phase=45)
    lp.clamp_ground(mb)
    lp.to_object(mb, "Log")
    export.save_and_export("fallen_log")


def main():
    build_firewood()
    build_fallen_log()


if __name__ == "__main__":
    main()
