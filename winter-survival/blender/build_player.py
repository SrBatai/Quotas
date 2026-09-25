"""player (slice ASSET_SPEC §4.1, regenerated for ASSET_SPEC_V2 §17): rigid parts parented in a hierarchy,
each with its origin at its joint. Retired in M2 (replaced by the skeletal chars/survivor_*.glb).

The coordinates below are written in the slice convention (faces +Y, right = +X); the script calls
new_scene(authored_front="+Y") so lib.lowpoly turns everything 180 degrees about Z: the exported player
faces -Y Blender = +Z Godot (MODEL_FRONT), right = -X. E.g. ArmR pivot (-0.36, 0, 1.32), BreathAnchor
(0, -0.20, 1.52), ToolSocket (-0.36, -0.05, 0.80) with rotation (-90, 0, 180) deg: its local +Z still
points forward, so tools parented with identity hold the handle forward and the blade/head up."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402,F401  (must precede mathutils)
from mathutils import Vector  # noqa: E402

from lib import export  # noqa: E402
from lib import lowpoly as lp  # noqa: E402


def torso_mesh():
    mb = lp.MeshBuilder()
    # puffy jacket: chamfered rings, 0.56 wide at the hem, 0.52 x 0.32 at the chest, rounded shoulders
    rings = [lp.rrect((0, 0, 0.80), 0.28, 0.165, 0.06),
             lp.rrect((0, 0, 0.86), 0.29, 0.172, 0.07),
             lp.rrect((0, 0, 1.06), 0.285, 0.172, 0.07),
             lp.rrect((0, 0, 1.30), 0.26, 0.16, 0.07),
             lp.rrect((0, 0, 1.36), 0.21, 0.13, 0.06)]
    mb.loft(rings, "jacket")
    # zip line and hem band (dark navy), slightly proud of the jacket front
    mb.box((-0.012, 0.166, 0.84), (0.012, 0.178, 1.29), "hat", skip=('-y',))
    # scarf ring 0.40 x 0.36, z 1.30-1.40, and a scarf tail hanging on the chest
    mb.loft([lp.rrect((0, 0, 1.30), 0.20, 0.18, 0.07), lp.rrect((0, 0, 1.40), 0.19, 0.17, 0.07)], "scarf")
    mb.hexa([(0.05, 0.168, 1.10), (0.12, 0.168, 1.11), (0.05, 0.198, 1.10), (0.12, 0.198, 1.11),
             (0.04, 0.172, 1.33), (0.11, 0.172, 1.33), (0.04, 0.202, 1.33), (0.11, 0.202, 1.33)], "scarf")
    return mb


def head_mesh():
    mb = lp.MeshBuilder()
    mb.box((-0.15, -0.14, 1.38), (0.15, 0.14, 1.64), "skin")                     # face/head
    mb.box((-0.025, 0.14, 1.49), (0.025, 0.175, 1.535), "skin", skip=('-y',))     # nose
    for sx in (-1, 1):                                                            # eyes on the +Y face
        x = sx * 0.06
        mb.poly([(x - 0.02, 0.141, 1.54), (x + 0.02, 0.141, 1.54), (x + 0.02, 0.141, 1.58),
                 (x - 0.02, 0.141, 1.58)], "eyes_dark", facing=(0, 1, 0))
    # beanie: folded band + tapered crown (hat box 0.34 x 0.32, z 1.60-1.74) + pompom
    mb.box((-0.175, -0.165, 1.60), (0.175, 0.165, 1.665), "hat")
    mb.tapered_box(1.665, 1.75, (0.33, 0.31), (0.25, 0.23), "hat", skip=('-z',))
    mb.blob((0, 0, 1.78), 0.06, "snow", subdiv=0, jitter=0.0)
    return mb


def arm_mesh(sx):
    """sx = -1 left, +1 right; shoulder pivot (sx*0.36, 0, 1.32)."""
    mb = lp.MeshBuilder()
    x = sx * 0.36
    mb.tapered_box(0.88, 1.335, (0.15, 0.15), (0.17, 0.17), "jacket", center=(x, 0), top_center=(x, 0))
    mb.tapered_box(0.76, 0.885, (0.15, 0.15), (0.17, 0.17), "scarf", center=(x, 0.005),
                   top_center=(x, 0.0))                                            # mitten
    mb.box((x - sx * 0.07 - 0.025, 0.04, 0.80), (x - sx * 0.07 + 0.025, 0.10, 0.86), "scarf",
           skip=('-x',) if sx < 0 else ('+x',))                                     # thumb
    return mb


def leg_mesh(sx):
    """sx = -1 left, +1 right; hip pivot (sx*0.12, 0, 0.80)."""
    mb = lp.MeshBuilder()
    x = sx * 0.12
    mb.tapered_box(0.18, 0.82, (0.19, 0.21), (0.20, 0.22), "hat", center=(x, 0), top_center=(x, 0))
    mb.tapered_box(0.0, 0.16, (0.22, 0.30), (0.21, 0.26), "boots", center=(x, 0.03), top_center=(x, 0.01))
    mb.box((x - 0.115, -0.125, 0.15), (x + 0.115, 0.125, 0.21), "cloth")         # fur cuff
    return mb


def build_player():
    lp.new_scene(authored_front="+Y")
    hips = lp.add_empty("Hips", (0, 0, 0.80))
    torso = lp.to_object(torso_mesh(), "Torso", (0, 0, 0.80), parent=hips)
    head = lp.to_object(head_mesh(), "Head", (0, 0, 1.36), parent=torso)
    lp.add_empty("BreathAnchor", (0, 0.20, 1.52), parent=head)
    lp.to_object(arm_mesh(-1), "ArmL", (-0.36, 0, 1.32), parent=torso)
    arm_r = lp.to_object(arm_mesh(1), "ArmR", (0.36, 0, 1.32), parent=torso)
    # Slice socket (-90, 0, 0) carried along with the 180-degree body turn: local +Z points forward (-Y),
    # local -Y up, local +X = the player's right (-X). Tools (not front-converted: weapon convention, useful
    # end at -Y) parented with identity hold the handle forward and the blade/head up, as in the slice.
    lp.add_empty("ToolSocket", (0.36, 0.05, 0.80), parent=arm_r, final_rotation_deg=(-90, 0, 180))
    lp.to_object(leg_mesh(-1), "LegL", (-0.12, 0, 0.80), parent=hips)
    lp.to_object(leg_mesh(1), "LegR", (0.12, 0, 0.80), parent=hips)
    export.save_and_export("player", ao=dict(distance=0.25, samples=48, ground=True))


def main():
    build_player()


if __name__ == "__main__":
    main()
