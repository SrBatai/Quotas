"""bed, desk, chair, shelf, clock, cabinet, wood_stove (slice ASSET_SPEC §4.16; ASSET_SPEC_V2 §9/§17).
Ground furniture: origin at the footprint centre on the floor. Wall furniture (shelf, clock): origin at
the wall contact point.

Written in the slice convention (+Y = the side a person uses / wall furniture protrudes toward +Y) and built
with new_scene(authored_front="+Y"): exported furniture faces -Y (MODEL_FRONT), shelf and clock protrude
toward -Y, the stove Door/StoveAnchor are at y < 0 and its Pipe at y > 0."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402,F401

from lib import export  # noqa: E402
from lib import lowpoly as lp  # noqa: E402

Y = (0, 1, 0)


def build_wood_stove():
    lp.new_scene(authored_front="+Y")
    body = lp.MeshBuilder()
    body.box((-0.30, -0.30, 0.15), (0.30, 0.30, 0.85), "iron", skip=('+z',))
    for sx in (-1, 1):
        for sy in (-1, 1):
            x, y = sx * 0.25, sy * 0.25
            body.box((x - 0.03, y - 0.03, 0.0), (x + 0.03, y + 0.03, 0.15), "iron", skip=('+z',))
    body.box((-0.33, -0.33, 0.85), (0.33, 0.33, 0.89), "iron")                   # top plate
    # door frame around the 0.30 x 0.30 opening (Door quad sits at y = 0.301)
    for (x0, x1, z0, z1) in ((-0.19, -0.15, 0.26, 0.64), (0.15, 0.19, 0.26, 0.64),
                             (-0.15, 0.15, 0.60, 0.64), (-0.15, 0.15, 0.26, 0.30)):
        body.box((x0, 0.30, z0), (x1, 0.318, z1), "iron", skip=('-y',))
    body.box((-0.20, 0.30, 0.17), (0.20, 0.315, 0.23), "stone_dark", skip=('-y',))  # ash drawer
    # tin kettle on the hot plate
    body.cylinder((0.14, 0.12, 0.89), (0.14, 0.12, 1.00), 0.09, 0.075, 8, "stone", cap0=False, phase=22.5)
    body.box((0.125, 0.105, 1.00), (0.155, 0.135, 1.03), "iron", skip=('-z',))
    body.cylinder((0.06, 0.14, 0.93), (-0.01, 0.16, 0.99), 0.018, 0.012, 4, "stone", cap0=False, phase=45)
    lp.to_object(body, "Body")

    door = lp.MeshBuilder()
    door.poly([(-0.15, 0.301, 0.30), (0.15, 0.301, 0.30), (0.15, 0.301, 0.60), (-0.15, 0.301, 0.60)], "ember",
              facing=Y)
    door.box((0.06, 0.30, 0.435), (0.13, 0.33, 0.465), "iron", skip=('-y',))      # handle
    lp.to_object(door, "Door")

    pipe = lp.MeshBuilder()
    pipe.cylinder((0, -0.15, 0.89), (0, -0.15, 2.70), 0.08, 0.08, 8, "iron", cap0=False, phase=22.5)
    pipe.cylinder((0, -0.15, 0.89), (0, -0.15, 0.95), 0.10, 0.10, 8, "iron", cap0=False, phase=22.5)  # collar
    pipe.cylinder((0, -0.15, 1.70), (0, -0.15, 1.74), 0.09, 0.09, 8, "iron", cap0=False, cap1=True,
                  phase=22.5)                                                         # damper ring
    lp.to_object(pipe, "Pipe")
    lp.add_empty("StoveAnchor", (0, 0.35, 0.45))
    lp.add_empty("PipeTop", (0, -0.15, 2.70))
    export.save_and_export("wood_stove")


def build_cabinet():
    lp.new_scene(authored_front="+Y")
    mb = lp.MeshBuilder()
    mb.box((-0.43, -0.25, 0.0), (0.43, 0.23, 0.06), "wood_dark", skip=('-z',))       # plinth
    mb.box((-0.45, -0.25, 0.06), (0.45, 0.25, 1.75), "wood")                          # carcass
    mb.box((-0.48, -0.25, 1.75), (0.48, 0.31, 1.80), "cabin_trim")                   # cornice 0.96x0.56x0.05
    for x0, x1 in ((-0.42, -0.02), (0.02, 0.42)):                                     # door panels
        mb.box((x0, 0.25, 0.15), (x1, 0.27, 1.65), "wood_dark", skip=('-y',))
    for x in (-0.07, 0.04):                                                           # iron handles
        mb.box((x, 0.27, 0.84), (x + 0.03, 0.30, 0.98), "iron", skip=('-y',))
    lp.to_object(mb, "Cabinet")
    export.save_and_export("cabinet")


def build_bed():
    lp.new_scene(authored_front="+Y")
    mb = lp.MeshBuilder()
    mb.box((-0.5, -1.0, 0.0), (0.5, -0.94, 0.95), "wood", skip=('-z',))              # headboard (-Y)
    mb.box((-0.5, -1.0, 0.95), (0.5, -0.92, 0.99), "wood_dark")                      # headboard cap
    mb.box((-0.5, 0.94, 0.0), (0.5, 1.0, 0.60), "wood", skip=('-z',))                # footboard
    for x0, x1 in ((-0.5, -0.44), (0.44, 0.5)):                                       # side rails
        mb.box((x0, -0.94, 0.15), (x1, 0.94, 0.35), "wood", skip=('-y', '+y'))
    mb.box((-0.46, -0.94, 0.33), (0.46, 0.94, 0.50), "cloth", skip=('-y', '+y'))         # mattress
    # blanket (navy) over the foot end; the pillow end stays uncovered (see report)
    mb.box((-0.49, -0.55, 0.36), (0.49, 0.94, 0.535), "hat", skip=('+y', '-z'))
    mb.box((-0.49, -0.62, 0.36), (0.49, -0.55, 0.545), "paper", skip=('-z',))       # sheet fold
    mb.tapered_box(0.50, 0.62, (0.5, 0.3), (0.44, 0.24), "paper", center=(0, -0.77))  # pillow
    lp.to_object(mb, "Bed")
    export.save_and_export("bed")


def build_desk():
    lp.new_scene(authored_front="+Y")
    mb = lp.MeshBuilder()
    mb.box((-0.70, -0.30, 0.70), (0.70, 0.30, 0.75), "wood")                          # top
    for sx in (-1, 1):
        for sy in (-1, 1):
            x, y = sx * 0.63, sy * 0.23
            mb.box((x - 0.03, y - 0.03, 0.0), (x + 0.03, y + 0.03, 0.70), "wood", skip=('-z', '+z'))
    mb.box((0.12, -0.25, 0.60), (0.60, 0.28, 0.70), "wood_dark", skip=('+z',))        # drawer
    mb.poly([(-0.35, -0.02, 0.751), (-0.06, 0.02, 0.751), (-0.08, 0.22, 0.751), (-0.37, 0.18, 0.751)],
            "paper", facing=(0, 0, 1))                                                # sheet 0.3 x 0.2
    mb.cylinder((0.42, 0.05, 0.75), (0.42, 0.05, 0.84), 0.04, 0.04, 8, "iron", cap0=False,
                cap_mats=(None, "wood_dark"), phase=22.5)                              # mug
    mb.box((0.46, 0.04, 0.77), (0.49, 0.06, 0.82), "iron", skip=('-x',))              # mug handle
    mb.box((0.10, -0.22, 0.75), (0.32, -0.06, 0.79), "can_red", skip=('-z',))         # book
    lp.to_object(mb, "Desk")
    export.save_and_export("desk")


def build_chair():
    lp.new_scene(authored_front="+Y")
    mb = lp.MeshBuilder()
    mb.box((-0.225, -0.225, 0.41), (0.225, 0.225, 0.45), "wood")                      # seat
    for sx in (-1, 1):
        x = sx * 0.2
        mb.box((x - 0.02, 0.16, 0.0), (x + 0.02, 0.20, 0.41), "wood", skip=('-z', '+z'))   # front legs
        mb.box((x - 0.02, -0.22, 0.0), (x + 0.02, -0.18, 0.90), "wood", skip=('-z',))      # back legs/posts
    mb.box((-0.18, -0.215, 0.78), (0.18, -0.185, 0.88), "wood", skip=('-x', '+x'))    # top rail
    mb.box((-0.18, -0.21, 0.58), (0.18, -0.19, 0.64), "wood", skip=('-x', '+x'))      # middle rail
    lp.to_object(mb, "Chair")
    export.save_and_export("chair")


def build_shelf():
    lp.new_scene(authored_front="+Y")
    mb = lp.MeshBuilder()
    mb.box((-0.45, 0.0, 0.0), (0.45, 0.25, 0.05), "wood")
    for x in (-0.30, 0.30):                                                           # brackets
        mb.prism([(x - 0.02, 0.0, 0.0), (x - 0.02, 0.19, 0.0), (x - 0.02, 0.0, -0.17)], (x - 0.02, 0, 0),
                 (x + 0.02, 0, 0), "wood_dark")
    shelf = lp.to_object(mb, "Shelf")
    jars = lp.MeshBuilder()
    for x, mat in ((-0.25, "can_red"), (0.0, "can_blue"), (0.25, "paper")):
        jars.cylinder((x, 0.125, 0.05), (x, 0.125, 0.19), 0.06, 0.06, 8, mat, cap0=False, cap1=False,
                      phase=22.5)
        jars.cylinder((x, 0.125, 0.19), (x, 0.125, 0.215), 0.064, 0.064, 8, "iron", cap0=False, phase=22.5)
    lp.to_object(jars, "Jars", parent=shelf)
    export.save_and_export("shelf")


def build_clock():
    lp.new_scene(authored_front="+Y")
    mb = lp.MeshBuilder()
    mb.cylinder((0, 0, 0), (0, 0.06, 0), 0.18, 0.18, 12, "wood", cap0=False, phase=15)
    mb.poly(lp.ring((0, 0.061, 0), Y, 0.15, 12, 15), "paper", facing=Y)
    for (x, z, w, h) in ((0, 0.12, 0.012, 0.03), (0.12, 0, 0.03, 0.012), (0, -0.12, 0.012, 0.03),
                         (-0.12, 0, 0.03, 0.012)):
        mb.poly([(x - w / 2, 0.062, z - h / 2), (x + w / 2, 0.062, z - h / 2), (x + w / 2, 0.062, z + h / 2),
                 (x - w / 2, 0.062, z + h / 2)], "iron", facing=Y)
    clock = lp.to_object(mb, "Clock")
    hh = lp.MeshBuilder()
    hh.box((-0.01, 0.065, -0.015), (0.01, 0.075, 0.09), "iron")
    lp.to_object(hh, "HourHand", (0, 0.07, 0), parent=clock)
    mh = lp.MeshBuilder()
    mh.box((-0.0075, 0.076, -0.02), (0.0075, 0.086, 0.13), "iron")
    lp.to_object(mh, "MinuteHand", (0, 0.075, 0), parent=clock)
    export.save_and_export("clock")


def main():
    build_wood_stove()
    build_cabinet()
    build_bed()
    build_desk()
    build_chair()
    build_shelf()
    build_clock()


if __name__ == "__main__":
    main()
