"""P2: tent, storage_box (ASSET_SPEC §4.22)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402,F401  (must precede mathutils)
from mathutils import Vector  # noqa: E402

from lib import export  # noqa: E402
from lib import lowpoly as lp  # noqa: E402


def build_tent():
    """Triangular prism 2.4 x 2.6 x 1.7, open at +Y: cloth slopes with snow, closed back, wood poles."""
    lp.new_scene()
    mb = lp.MeshBuilder()
    W, D, H, t = 1.2, 1.3, 1.7, 0.035
    for sx in (-1, 1):
        ob, ot = Vector((sx * W, 0, 0)), Vector((0, 0, H))
        prof = [ob, ot, Vector((0, 0, H - 0.05)), Vector((sx * (W - t * 1.2), 0, 0))]
        mb.prism([p + Vector((0, -D, 0)) for p in prof], (0, -D, 0), (0, D, 0), "cloth")
        # snow on the upper slope
        a0 = ob.lerp(ot, 0.35)
        nrm = Vector((sx * H, 0, W)).normalized() * 0.07
        prof = [a0, ot, Vector((0, 0, H + 0.07 / nrm.normalized().z)), a0 + nrm]
        mb.prism([p + Vector((0, -D + 0.05, 0)) for p in prof], (0, -D + 0.05, 0), (0, D - 0.05, 0), "snow")
    # closed back wall
    mb.prism([Vector((-W + 0.03, -D + 0.01, 0)), Vector((W - 0.03, -D + 0.01, 0)), Vector((0, -D + 0.01, H - 0.04))],
             (0, -D + 0.01, 0), (0, -D + 0.05, 0), "cloth")
    # front door flaps tied open (thin triangles folded against the slopes)
    for sx in (-1, 1):
        mb.prism([Vector((sx * 0.25, D - 0.02, 1.35)), Vector((sx * 1.0, D - 0.02, 0.25)),
                  Vector((sx * 1.12, D - 0.02, 0.1))], (0, D - 0.02, 0), (0, D + 0.01, 0), "wood_light")
    # ground sheet inside
    mb.poly([(-0.95, -D + 0.05, 0.01), (0.95, -D + 0.05, 0.01), (0.95, D - 0.05, 0.01), (-0.95, D - 0.05, 0.01)],
            "wood_dark", facing=(0, 0, 1))
    # poles at the front and back, poking above the ridge
    for y in (-D + 0.08, D - 0.08):
        mb.cylinder((0, y, 0), (0, y, H + 0.12), 0.03, 0.025, 6, "wood", cap0=False)
    lp.to_object(mb, "Tent")
    lp.collision_box("ColBack", (-1.2, -1.3, 0.0), (1.2, -1.2, 1.7))
    export.save_and_export("tent")


def build_storage_box():
    """Wooden crate 0.8 x 0.6 x 0.6: wood panels with wood_dark edge battens."""
    lp.new_scene()
    mb = lp.MeshBuilder()
    mb.box((-0.38, -0.28, 0.0), (0.38, 0.28, 0.58), "wood", skip=('-z',))
    for sx in (-1, 1):
        for sy in (-1, 1):
            x, y = sx * 0.375, sy * 0.275
            mb.box((x - 0.025, y - 0.025, 0.0), (x + 0.025, y + 0.025, 0.6), "wood_dark", skip=('-z',))
    for sy in (-1, 1):                     # top and bottom rails along X
        mb.box((-0.35, sy * 0.3 - 0.02, 0.54), (0.35, sy * 0.3 + 0.02, 0.6), "wood_dark", skip=('-z',))
        mb.box((-0.35, sy * 0.3 - 0.02, 0.0), (0.35, sy * 0.3 + 0.02, 0.07), "wood_dark", skip=('-z',))
    for sx in (-1, 1):                     # top rails along Y
        mb.box((sx * 0.4 - 0.02, -0.25, 0.54), (sx * 0.4 + 0.02, 0.25, 0.6), "wood_dark", skip=('-z',))
    mb.box((-0.05, 0.28, 0.40), (0.05, 0.31, 0.50), "iron", skip=('-y',))          # latch on the front
    lp.to_object(mb, "Box")
    export.save_and_export("storage_box")


def main():
    build_tent()
    build_storage_box()


if __name__ == "__main__":
    main()
