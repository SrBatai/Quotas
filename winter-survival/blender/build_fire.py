"""campfire, torch, lantern (slice ASSET_SPEC §4.12, 4.14, 4.21; ASSET_SPEC_V2 §17). No front: authored
in the final orientation (no front turn). Torch: weapon convention (grip at the origin, handle +Z). Lantern:
glass = material `window` (second surface), LightAnchor unchanged."""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402,F401  (must precede mathutils)
from mathutils import Vector  # noqa: E402

from lib import export  # noqa: E402
from lib import lowpoly as lp  # noqa: E402


def build_campfire():
    lp.new_scene()
    rnd = lp.rng(9)
    stones = lp.MeshBuilder()
    for i in range(8):
        a = 2 * math.pi * i / 8 + rnd.uniform(-0.12, 0.12)
        r = rnd.uniform(0.12, 0.145)
        rr = 0.48 + rnd.uniform(-0.015, 0.015)
        stones.blob((rr * math.cos(a), rr * math.sin(a), 0.02), (r * 1.1, r, r * 0.8), "stone", subdiv=0,
                    jitter=0.12, rnd=rnd, clamp_z=0.0, drop_bottom=True)
    lp.stone_rule(stones, snow=0.85, dark=-0.2)
    # charred ground inside the ring
    stones.poly(lp.ring((0, 0, 0.006), (0, 0, 1), 0.33, 8, 10), "iron", facing=(0, 0, 1))
    lp.to_object(stones, "Stones")

    logs = lp.MeshBuilder()
    elev = math.radians(25)
    for k in range(4):
        a = math.radians(45 + 90 * k + rnd.uniform(-8, 8))
        out = Vector((math.cos(a), math.sin(a), 0))
        p0 = out * 0.40 + Vector((0, 0, 0.06))
        d = -out * math.cos(elev) + Vector((0, 0, math.sin(elev)))
        p1 = p0 + d * 0.6
        faces = logs.cylinder(p0, p1, 0.07, 0.065, 6, "bark", cap_mats=("wood_light", "wood_light"),
                              phase=rnd.uniform(0, 60))
    lp.clamp_ground(logs)
    lp.to_object(logs, "Logs")
    lp.add_empty("FlameAnchor", (0, 0, 0.18))
    export.save_and_export("campfire")


def build_torch():
    lp.new_scene()
    handle = lp.MeshBuilder()
    handle.cylinder((0, 0, 0), (0, 0, 0.42), 0.025, 0.027, 6, "wood")
    lp.to_object(handle, "Handle")
    head = lp.MeshBuilder()
    head.cylinder((0, 0, 0.38), (0, 0, 0.52), 0.05, 0.058, 8, "cloth", cap_mats=("cloth", "iron"),
                  phase=22.5)
    # a wrap band around the cloth head
    head.cylinder((0, 0, 0.425), (0, 0, 0.455), 0.058, 0.06, 8, "wood_dark", phase=22.5)
    lp.to_object(head, "Head")
    lp.add_empty("FlameAnchor", (0, 0, 0.54))
    export.save_and_export("torch")


def build_lantern():
    lp.new_scene()
    mb = lp.MeshBuilder()
    # hook ring (box loop) z -0.06..0
    mb.box((-0.02, -0.006, -0.012), (0.02, 0.006, 0.0), "iron")
    mb.box((-0.02, -0.006, -0.06), (-0.008, 0.006, -0.012), "iron")
    mb.box((0.008, -0.006, -0.06), (0.02, 0.006, -0.012), "iron")
    # cap with a small pyramid roof, z -0.10..-0.06
    mb.box((-0.10, -0.10, -0.10), (0.10, 0.10, -0.085), "iron")
    mb.loft([[Vector((x, y, -0.085)) for x, y in ((-0.1, -0.1), (0.1, -0.1), (0.1, 0.1), (-0.1, 0.1))],
             [Vector((x, y, -0.06)) for x, y in ((-0.03, -0.03), (0.03, -0.03), (0.03, 0.03), (-0.03, 0.03))]],
            "iron", cap_start=False)
    mb.box((-0.08, -0.08, -0.36), (0.08, 0.08, -0.10), "window")               # glass
    mb.box((-0.10, -0.10, -0.40), (0.10, 0.10, -0.36), "iron")                 # base
    for sx in (-1, 1):
        for sy in (-1, 1):
            mb.box((sx * 0.085 - 0.012, sy * 0.085 - 0.012, -0.36), (sx * 0.085 + 0.012, sy * 0.085 + 0.012, -0.10),
                   "iron", skip=('-z', '+z'))
    lp.to_object(mb, "Lantern")
    lp.add_empty("LightAnchor", (0, 0, -0.23))
    export.save_and_export("lantern")


def main():
    build_campfire()
    build_torch()
    build_lantern()


if __name__ == "__main__":
    main()
