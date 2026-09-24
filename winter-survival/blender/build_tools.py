"""stone_axe (ASSET_SPEC §4.13). Origin at the grip, handle along +Z, blade toward -Y."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402,F401

from lib import export  # noqa: E402
from lib import lowpoly as lp  # noqa: E402


def build_stone_axe():
    lp.new_scene()
    handle = lp.MeshBuilder()
    handle.cylinder((0, 0, -0.05), (0, 0, 0.50), 0.025, 0.023, 6, "wood")
    handle.cylinder((0, 0, 0.0), (0, 0, 0.10), 0.031, 0.031, 6, "cloth")          # grip wrap
    lp.to_object(handle, "Handle")
    blade = lp.MeshBuilder()
    # wedge: 0.06 thick at the back (y = +0.03), 0.02 at the edge (y = -0.20), flared edge z 0.37..0.50
    corners = []
    for i in range(8):
        front = not (i & 2)            # ybit 0 -> edge side (-Y)
        up = bool(i & 4)
        y = -0.20 if front else 0.03
        half = 0.01 if front else 0.03
        x = half if i & 1 else -half
        z = (0.50 if up else 0.37) if front else (0.485 if up else 0.395)
        corners.append((x, y, z))
    blade.hexa(corners, "stone_dark")
    blade.box((-0.036, -0.036, 0.405), (0.036, 0.036, 0.47), "cloth")             # lashing
    blade.box((-0.034, -0.05, 0.415), (0.034, -0.03, 0.46), "cloth")              # lashing over the blade
    lp.to_object(blade, "Blade")
    export.save_and_export("stone_axe")


def main():
    build_stone_axe()


if __name__ == "__main__":
    main()
