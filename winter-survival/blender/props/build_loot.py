"""Loot containers, ammo boxes and ground pickups — ASSET_SPEC_V2 §9 / §13 + "T2" (milestone M5).

    cd winter-survival/blender && python3 props/build_loot.py [crate medkit ...]

Exports assets/models/props/loot/<name>.glb (+ sources/<name>.blend + the Godot `.import`, template "prop") and
assets/models/props/loot/manifest.json (nodes, tris, collision box, hinge data per asset, read by the code).
Front = -Y Blender (+Z Godot), origin = centre of the footprint at z = 0, 1 palette surface per mesh, no collision
(the code builds a box from the `col_center` / `col_size` extras, Godot coordinates), no Col* nodes.

Containers (§9 structure): a root mesh named in PascalCase (`Crate`), the moving part(s) as CHILD meshes whose origin
is on the hinge axis (`Lid`, `Door`, `Door_L` / `Door_R`, `Flap`) and a `Loot` empty child (where the loot / the
interaction marker goes, inside the container). Moving parts carry `hinge_axis` (Godot, local) and `open_deg` (the
signed rotation about that axis that opens it) in their extras; the root carries `container` (kind), `slots`,
`col_center`, `col_size`. Everything is exported CLOSED.

Pickups: ONE mesh `Item` (1 surface, extras `pickup` = kind, `col_center` / `col_size`), lying on the ground, x1.3 of the
real size so they read from the game camera (small arms are x1.2 in §12).
"""
import json
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import bpy  # noqa: E402,F401
from mathutils import Matrix, Vector  # noqa: E402

from lib import export  # noqa: E402
from lib import hd as H  # noqa: E402
from lib import lowpoly as lp  # noqa: E402

SUBDIR = "props/loot"
PICKUP_SCALE = 1.3
CONTAINER_BUDGET = 1200          # doc 05 §4.5 v2.1 furniture / prop 100 - 1 200
PICKUP_BUDGET = 400


def godot(v):
    return [round(v[0], 3) + 0.0, round(v[2], 3) + 0.0, round(-v[1], 3) + 0.0]


def godot_axis(v):
    return [v[0], v[2], -v[1]]


# ------------------------------------------------------------------------------------------------------------
# helpers
# ------------------------------------------------------------------------------------------------------------
def rbox(mb, mn, mx, mat, ch=0.01):
    """Chamfered box (octagonal section along X, i.e. the long horizontal edges are chamfered)."""
    mn, mx = Vector(mn), Vector(mx)
    cy, cz = (mn.y + mx.y) / 2, (mn.z + mx.z) / 2
    hy, hz = (mx.y - mn.y) / 2, (mx.z - mn.z) / 2
    ch = min(ch, hy * 0.45, hz * 0.45)
    pts = [(hy, hz - ch), (hy - ch, hz), (-hy + ch, hz), (-hy, hz - ch), (-hy, -hz + ch), (-hy + ch, -hz),
           (hy - ch, -hz), (hy, -hz + ch)]
    rings = [[Vector((x, cy + a, cz + b)) for a, b in pts] for x in (mn.x, mx.x)]
    return mb.loft(rings, mat)


def band(mb, mn, mx, z0, z1, t, mat):
    """Closed strips wrapped around the footprint [mn, mx] (x, y) between z0 and z1, t thick outward."""
    x0, y0 = mn[0], mn[1]
    x1, y1 = mx[0], mx[1]
    mb.box((x0 - t, y0 - t, z0), (x1 + t, y0, z1), mat)
    mb.box((x0 - t, y1, z0), (x1 + t, y1 + t, z1), mat)
    mb.box((x0 - t, y0, z0), (x0, y1, z1), mat)
    mb.box((x1, y0, z0), (x1 + t, y1, z1), mat)


def banded_cylinder(mb, r, zs, mats, sides=12, taper=()):
    """Vertical cylinder at the origin through the heights zs with one material per segment (label bands)."""
    rings = [lp.ring(Vector((0, 0, z)), Vector((0, 0, 1)), r, sides) for z in zs]
    for i, k in taper:
        rings[i] = lp.ring(Vector((0, 0, zs[i])), Vector((0, 0, 1)), r * k, sides)
    return mb.loft(rings, mats[0], side_mats=list(mats), cap_mats=(mats[0], mats[-1]))


def cyl(mb, p0, p1, r, sides, mat, cap_mats=(None, None), r1=None):
    return mb.cylinder(p0, p1, r, r if r1 is None else r1, sides, mat, cap_mats=cap_mats)


def finish(mb, name, pivot=(0, 0, 0), parent=None, angle=35.0, flat=False):
    o = H.mk(mb, name, pivot, parent)
    if flat:
        H.flat(o)
    else:
        H.smooth(o, angle)
    return o


def hinge_props(o, axis_bl, open_deg):
    o["hinge_axis"] = godot_axis(axis_bl)
    o["open_deg"] = open_deg


def col_props(o, mn, mx):
    mn, mx = Vector(mn), Vector(mx)
    c = (mn + mx) / 2
    o["col_center"] = godot(c)
    o["col_size"] = [round(mx.x - mn.x, 3), round(mx.z - mn.z, 3), round(mx.y - mn.y, 3)]


# ------------------------------------------------------------------------------------------------------------
# containers
# ------------------------------------------------------------------------------------------------------------
def crate():
    """Wooden supply crate 0.90 x 0.60 x 0.56: plank walls with dark battens, hinged plank lid (back edge)."""
    W, D, Hh, t = 0.90, 0.60, 0.50, 0.024
    b = lp.MeshBuilder()
    b.box((-W / 2, -D / 2, 0.0), (W / 2, D / 2, 0.03), "wood_dark")                        # bottom
    for k in range(3):                                                                  # wall planks
        z0, z1 = 0.03 + k * (Hh - 0.03) / 3 + 0.003, 0.03 + (k + 1) * (Hh - 0.03) / 3 - 0.003
        mat = "wood" if k != 1 else "wood_light"
        b.box((-W / 2, -D / 2, z0), (W / 2, -D / 2 + t, z1), mat)
        b.box((-W / 2, D / 2 - t, z0), (W / 2, D / 2, z1), mat)
        b.box((-W / 2, -D / 2 + t, z0), (-W / 2 + t, D / 2 - t, z1), mat)
        b.box((W / 2 - t, -D / 2 + t, z0), (W / 2, D / 2 - t, z1), mat)
    for sx in (-1, 1):                                                                  # corner battens
        for sy in (-1, 1):
            x, y = sx * (W / 2 + 0.006), sy * (D / 2 + 0.006)
            b.box((x - 0.030, y - 0.030, 0.0), (x + 0.030, y + 0.030, Hh), "wood_dark")
    for sy in (-1, 1):                                                                  # stencil band (front/back)
        y = sy * (D / 2 + 0.002)
        b.box((-0.16, y - 0.002, 0.20), (0.16, y + 0.002, 0.30), "military_green")
    b.box((-W / 2 + 0.03, -D / 2 + t, 0.03), (W / 2 - 0.03, D / 2 - t, 0.034), "wood_light")   # floor
    body = finish(b, "Crate", flat=True)
    lid = lp.MeshBuilder()
    hy, hz = D / 2 + 0.036, Hh
    for k in range(4):
        y0 = -D / 2 - 0.036 + k * (D + 0.072) / 4 + 0.003
        lid.box((-W / 2 - 0.036, y0, Hh + 0.002), (W / 2 + 0.036, y0 + (D + 0.072) / 4 - 0.006, Hh + 0.030),
                "wood" if k % 2 else "wood_light")
    for x in (-0.34, 0.34):
        lid.box((x - 0.035, -D / 2 - 0.036, Hh + 0.030), (x + 0.035, D / 2 + 0.036, Hh + 0.050), "wood_dark")
    lidobj = finish(lid, "Lid", pivot=(0.0, hy, hz), parent=body, flat=True)
    hinge_props(lidobj, (1, 0, 0), -105.0)
    lp.add_empty("Loot", (0.0, 0.0, 0.12), parent=body, size=0.05)
    return body, dict(container="crate", slots=8), ((-0.49, -0.34, 0), (0.49, 0.34, 0.55))


def footlocker():
    """Military footlocker 0.90 x 0.46 x 0.44: olive trunk, brass corners, side handles, front latches; lid on the back."""
    W, D, Hb, Hl = 0.88, 0.44, 0.33, 0.10
    b = lp.MeshBuilder()
    t = 0.018
    b.box((-W / 2, -D / 2, 0.0), (W / 2, D / 2, 0.02), "military_green")
    b.box((-W / 2, -D / 2, 0.02), (W / 2, -D / 2 + t, Hb), "military_green")
    b.box((-W / 2, D / 2 - t, 0.02), (W / 2, D / 2, Hb), "military_green")
    b.box((-W / 2, -D / 2 + t, 0.02), (-W / 2 + t, D / 2 - t, Hb), "military_green")
    b.box((W / 2 - t, -D / 2 + t, 0.02), (W / 2, D / 2 - t, Hb), "military_green")
    b.box((-W / 2 + t, -D / 2 + t, 0.02), (W / 2 - t, D / 2 - t, 0.024), "wood_dark")         # inner floor
    for z in (0.02, Hb - 0.035):                                                          # rims
        band(b, (-W / 2, -D / 2), (W / 2, D / 2), z, z + 0.035, 0.006, "wood_dark")
    for sx in (-1, 1):
        for sy in (-1, 1):
            x, y = sx * (W / 2 - 0.02), sy * (D / 2 - 0.02)
            b.box((x - 0.028, y - 0.028, 0.0), (x + 0.028, y + 0.028, 0.06), "brass")
        b.box((sx * (W / 2 + 0.004) - 0.012, -0.07, 0.19), (sx * (W / 2 + 0.004) + 0.012, 0.07, 0.215), "iron")  # handles
    for x in (-0.28, 0.28):
        b.box((x - 0.03, -D / 2 - 0.012, Hb - 0.07), (x + 0.03, -D / 2 + 0.002, Hb - 0.01), "brass")      # latches
    b.box((-0.12, -D / 2 - 0.003, 0.10), (0.12, -D / 2 + 0.001, 0.18), "paint_white")                    # stencil
    body = finish(b, "Footlocker", flat=True)
    lid = lp.MeshBuilder()
    rbox(lid, (-W / 2 - 0.004, -D / 2 - 0.004, Hb), (W / 2 + 0.004, D / 2 + 0.004, Hb + Hl), "military_green", 0.02)
    for x in (-0.28, 0.28):
        lid.box((x - 0.025, -D / 2 - 0.012, Hb + 0.01), (x + 0.025, -D / 2 + 0.004, Hb + 0.05), "brass")
    for sx in (-1, 1):
        for sy in (-1, 1):
            x, y = sx * (W / 2 - 0.02), sy * (D / 2 - 0.02)
            lid.box((x - 0.030, y - 0.030, Hb + Hl - 0.04), (x + 0.030, y + 0.030, Hb + Hl + 0.004), "brass")
    lidobj = finish(lid, "Lid", pivot=(0.0, D / 2 + 0.004, Hb), parent=body, flat=True)
    hinge_props(lidobj, (1, 0, 0), -100.0)
    lp.add_empty("Loot", (0.0, 0.0, 0.10), parent=body, size=0.05)
    return body, dict(container="footlocker", slots=8), ((-0.46, -0.24, 0), (0.46, 0.24, 0.44))


def locker():
    """Steel locker 0.50 x 0.50 x 1.85: blue sheet body open to -Y, shelf, coat hook; vented door hinged on the left."""
    W, D, Hh, t = 0.50, 0.50, 1.85, 0.015
    b = lp.MeshBuilder()
    b.box((-W / 2, -D / 2, 0.0), (W / 2, D / 2, 0.08), "metal_sheet")                     # plinth
    b.box((-W / 2, D / 2 - t, 0.08), (W / 2, D / 2, Hh), "metal_blue")                     # back
    b.box((-W / 2, -D / 2, 0.08), (-W / 2 + t, D / 2 - t, Hh), "metal_blue")                # sides
    b.box((W / 2 - t, -D / 2, 0.08), (W / 2, D / 2 - t, Hh), "metal_blue")
    b.box((-W / 2, -D / 2, Hh - t), (W / 2, D / 2 - t, Hh), "metal_blue")                  # top
    b.box((-W / 2 + t, -D / 2 + 0.02, 1.52), (W / 2 - t, D / 2 - t, 1.535), "metal_sheet")  # shelf
    b.box((-0.01, 0.20, 1.40), (0.01, 0.235, 1.46), "iron")                                 # hook
    b.box((-W / 2 - 0.004, -D / 2 - 0.004, Hh - 0.004), (W / 2 + 0.004, D / 2 + 0.004, Hh + 0.02), "metal_sheet")
    body = finish(b, "Locker", flat=True)
    d = lp.MeshBuilder()
    x0, x1, y0, y1 = -W / 2 + 0.004, W / 2 - 0.004, -D / 2 - 0.020, -D / 2 - 0.002
    d.box((x0, y0, 0.085), (x1, y1, Hh - 0.02), "metal_blue")
    for k in range(5):                                                                   # vents (top + bottom)
        for zb in (1.62, 0.22):
            z = zb + k * 0.028
            d.box((x0 + 0.10, y0 - 0.003, z), (x1 - 0.10, y0 + 0.002, z + 0.010), "iron")
    d.box((x1 - 0.06, y0 - 0.030, 0.95), (x1 - 0.035, y0 + 0.002, 1.12), "metal_sheet")   # handle
    d.box((x0 + 0.13, y0 - 0.003, 1.30), (x1 - 0.13, y0 + 0.002, 1.36), "paint_white")      # name card
    door = finish(d, "Door", pivot=(-W / 2 + 0.004, -D / 2 - 0.011, 0.0), parent=body, flat=True)
    hinge_props(door, (0, 0, 1), -100.0)
    lp.add_empty("Loot", (0.0, 0.0, 1.10), parent=body, size=0.05)
    return body, dict(container="locker", slots=10), ((-0.25, -0.27, 0), (0.25, 0.25, 1.87))


def fridge():
    """Fridge 0.70 x 0.68 x 1.76: white shell, frozen interior (ice on the walls), shelves; door hinged on the right."""
    W, D, Hh, t = 0.70, 0.66, 1.76, 0.04
    b = lp.MeshBuilder()
    b.box((-W / 2 + 0.03, -D / 2 + 0.03, 0.0), (W / 2 - 0.03, D / 2, 0.06), "paint_black")    # toe kick
    b.box((-W / 2, D / 2 - t, 0.06), (W / 2, D / 2, Hh), "paint_white")
    b.box((-W / 2, -D / 2, 0.06), (-W / 2 + t, D / 2 - t, Hh), "paint_white")
    b.box((W / 2 - t, -D / 2, 0.06), (W / 2, D / 2 - t, Hh), "paint_white")
    b.box((-W / 2 + t, -D / 2, Hh - t), (W / 2 - t, D / 2 - t, Hh), "paint_white")
    b.box((-W / 2 + t, -D / 2, 0.06), (W / 2 - t, D / 2 - t, 0.10), "paint_white")
    b.box((-W / 2 + t, D / 2 - t - 0.01, 0.10), (W / 2 - t, D / 2 - t, Hh - t), "ice")            # frosted walls
    b.box((-W / 2 + t, -D / 2 + 0.03, 1.22), (W / 2 - t, D / 2 - t, 1.25), "snow_packed")         # freezer floor
    for z in (0.52, 0.86):
        b.box((-W / 2 + t, -D / 2 + 0.06, z), (W / 2 - t, D / 2 - t - 0.01, z + 0.012), "ice_thin")
    body = finish(b, "Fridge", flat=True)
    d = lp.MeshBuilder()
    x0, x1, y0, y1 = -W / 2, W / 2, -D / 2 - 0.05, -D / 2
    rbox(d, (x0, y0, 0.07), (x1, y1, Hh), "paint_white", 0.012)
    d.box((x0 + 0.05, y0 - 0.035, 1.05), (x0 + 0.08, y0 + 0.002, 1.55), "chrome")               # handle
    d.box((x0 + 0.05, y0 - 0.035, 0.55), (x0 + 0.08, y0 + 0.002, 0.95), "chrome")
    d.box((-W / 2 + 0.01, y0 - 0.002, 1.22), (W / 2 - 0.01, y0 + 0.004, 1.235), "cloth_gray")   # freezer line
    d.box((0.05, y0 - 0.003, 1.40), (0.20, y0 + 0.002, 1.52), "paper")                          # note
    door = finish(d, "Door", pivot=(W / 2, -D / 2 - 0.025, 0.0), parent=body, flat=True)
    hinge_props(door, (0, 0, 1), 100.0)
    lp.add_empty("Loot", (0.0, 0.0, 0.95), parent=body, size=0.05)
    return body, dict(container="fridge", slots=8), ((-0.35, -0.38, 0), (0.35, 0.33, 1.76))


def kitchen_cabinet():
    """Kitchen base cabinet 0.80 x 0.60 x 0.92: wood carcass, stone worktop, two doors hinged at the outer sides."""
    W, D, Hh, t = 0.80, 0.58, 0.88, 0.018
    b = lp.MeshBuilder()
    b.box((-W / 2 + 0.02, -D / 2 + 0.05, 0.0), (W / 2 - 0.02, D / 2, 0.09), "wood_dark")        # plinth
    b.box((-W / 2, D / 2 - t, 0.09), (W / 2, D / 2, Hh), "wood_light")
    b.box((-W / 2, -D / 2, 0.09), (-W / 2 + t, D / 2 - t, Hh), "wood_light")
    b.box((W / 2 - t, -D / 2, 0.09), (W / 2, D / 2 - t, Hh), "wood_light")
    b.box((-W / 2 + t, -D / 2, 0.09), (W / 2 - t, D / 2 - t, 0.11), "wood_light")
    b.box((-W / 2 + t, -D / 2 + 0.02, 0.48), (W / 2 - t, D / 2 - t, 0.495), "wood_light")        # shelf
    rbox(b, (-W / 2 - 0.01, -D / 2 - 0.04, Hh), (W / 2 + 0.01, D / 2 + 0.01, Hh + 0.04), "stone", 0.006)   # top
    body = finish(b, "KitchenCabinet", flat=True)
    doors = []
    for side, sx in (("Door_L", -1), ("Door_R", 1)):
        d = lp.MeshBuilder()
        xa, xb = (-W / 2 + 0.004, -0.004) if sx < 0 else (0.004, W / 2 - 0.004)
        y0, y1 = -D / 2 - 0.022, -D / 2 - 0.002
        d.box((xa, y0, 0.11), (xb, y1, Hh - 0.01), "cabin_wall")
        d.box((xa + 0.05, y0 - 0.003, 0.18), (xb - 0.05, y0 + 0.002, Hh - 0.08), "cabin_trim")
        hx = xb - 0.05 if sx < 0 else xa + 0.05
        d.box((hx - 0.010, y0 - 0.030, Hh - 0.22), (hx + 0.010, y0 + 0.002, Hh - 0.10), "chrome")
        hinge_x = xa if sx < 0 else xb
        o = finish(d, side, pivot=(hinge_x, -D / 2 - 0.012, 0.0), parent=body, flat=True)
        hinge_props(o, (0, 0, 1), -100.0 if sx < 0 else 100.0)
        doors.append(o)
    lp.add_empty("Loot", (0.0, 0.0, 0.30), parent=body, size=0.05)
    return body, dict(container="kitchen_cabinet", slots=6), ((-0.41, -0.33, 0), (0.41, 0.30, 0.92))


def backpack():
    """Dropped backpack (player death bag / loot bag) 0.44 x 0.34 x 0.52, standing slumped: roll-top flap hinged at the
    back, side pockets, straps, a sleeping mat strapped below."""
    rnd = random.Random(7)
    b = lp.MeshBuilder()
    rings = []
    for z, hx, hy in ((0.02, 0.17, 0.11), (0.06, 0.20, 0.14), (0.26, 0.20, 0.15), (0.40, 0.18, 0.14),
                      (0.44, 0.165, 0.125)):
        rings.append([Vector((0, 0.02, z)) + Vector((x, y, 0)) for x, y in
                      ((hx, hy * 0.6), (hx * 0.6, hy), (-hx * 0.6, hy), (-hx, hy * 0.6), (-hx, -hy * 0.6),
                       (-hx * 0.6, -hy), (hx * 0.6, -hy), (hx, -hy * 0.6))])
    b.loft(rings, "pack")
    for sx in (-1, 1):                                                                    # side pockets
        b.box((sx * 0.20 - 0.04, -0.06, 0.08), (sx * 0.20 + 0.04, 0.10, 0.26), "pack_dark")
    b.box((-0.13, -0.155, 0.10), (0.13, -0.11, 0.28), "pack_dark")                          # front pocket
    for sx in (-1, 1):                                                                    # shoulder straps (back)
        b.box((sx * 0.08 - 0.03, 0.155, 0.10), (sx * 0.08 + 0.03, 0.185, 0.42), "strap")
    b.cylinder((-0.21, -0.12, 0.06), (0.21, -0.12, 0.06), 0.06, 0.06, 8, "mat_roll")          # mat, front bottom
    b.box((-0.05, -0.18, 0.18), (0.05, -0.15, 0.30), "hivis_orange")                         # tag
    body = finish(b, "Backpack", angle=40.0)
    f = lp.MeshBuilder()
    rf = []
    for z, hx, hy, dy in ((0.44, 0.175, 0.135, 0.0), (0.49, 0.17, 0.13, -0.005), (0.52, 0.12, 0.09, -0.01)):
        rf.append([Vector((x, 0.02 + y + dy, z)) for x, y in
                   ((hx, hy * 0.6), (hx * 0.6, hy), (-hx * 0.6, hy), (-hx, hy * 0.6), (-hx, -hy * 0.6),
                    (-hx * 0.6, -hy), (hx * 0.6, -hy), (hx, -hy * 0.6))])
    f.loft(rf, "pack_dark")
    f.box((-0.02, -0.14, 0.34), (0.02, -0.11, 0.49), "strap")
    flap = finish(f, "Flap", pivot=(0.0, 0.16, 0.46), parent=body, angle=40.0)
    hinge_props(flap, (1, 0, 0), -120.0)
    lp.add_empty("Loot", (0.0, 0.02, 0.30), parent=body, size=0.05)
    return body, dict(container="backpack", slots=12), ((-0.25, -0.18, 0), (0.25, 0.19, 0.53))


def body_bag():
    """Body bag 1.96 x 0.70 x 0.22 along X (head toward +X): black tub + zipped top cover (`Flap`, hinged on the back
    long edge, opens over the back); a covered figure inside (grey cloth, gore-lite)."""
    L = 0.98
    b = lp.MeshBuilder()
    tub = [(0.0, -0.345, 0.0), (0.0, -0.335, 0.07), (0.0, -0.30, 0.09), (0.0, 0.30, 0.09), (0.0, 0.335, 0.07),
           (0.0, 0.345, 0.0)]
    b.prism([(x - L, y, z) for x, y, z in tub], (0, 0, 0), (2 * L, 0, 0), "plastic_black", concave=True)
    b.cylinder((-0.78, 0.0, 0.09), (0.52, 0.0, 0.09), 0.08, 0.10, 8, "cloth_gray")          # figure under a sheet
    b.blob((0.70, 0.0, 0.10), (0.10, 0.09, 0.08), "skin_zombie", subdiv=1, jitter=0.05, rnd=random.Random(3))
    body = finish(b, "BodyBag", angle=45.0)
    f = lp.MeshBuilder()
    outer, inner = [], []
    for k in range(9):
        a = math.pi * k / 8
        y, z = -0.352 * math.cos(a), 0.070 + 0.150 * math.sin(a)
        outer.append((0.0, y, z))
        inner.append((0.0, -0.338 * math.cos(a), 0.070 + 0.136 * math.sin(a)))
    prof = [(x - (L - 0.02), y, z) for x, y, z in outer + inner[::-1]]
    faces = f.prism(prof, (0, 0, 0), (2 * (L - 0.02), 0, 0), "plastic_black", concave=True)
    for fi in faces:
        c = f.center(fi)
        if f.normal(fi).z > 0.8 and abs(c.y) < 0.05:
            f.faces[fi][1] = "iron"                                                        # zip line
    f.box((0.40, -0.035, 0.214), (0.46, -0.005, 0.226), "chrome")                             # zip pull
    f.box((-0.25, -0.20, 0.180), (0.05, -0.10, 0.196), "paint_white")                          # tag
    flap = finish(f, "Flap", pivot=(0.0, 0.352, 0.070), parent=body, angle=45.0)
    hinge_props(flap, (1, 0, 0), -150.0)
    lp.add_empty("Loot", (0.1, 0.0, 0.12), parent=body, size=0.05)
    return body, dict(container="body_bag", slots=10), ((-0.98, -0.36, 0), (0.98, 0.36, 0.23))


# ------------------------------------------------------------------------------------------------------------
# pickups (real size x PICKUP_SCALE, lying on the ground)
# ------------------------------------------------------------------------------------------------------------
def cartridge(mb, base, direction, length, r, case_mat="brass", tip_mat="stone_dark", sides=6):
    base, d = Vector(base), Vector(direction).normalized()
    mb.cylinder(base, base + d * length * 0.65, r, r, sides, case_mat)
    mb.cylinder(base + d * length * 0.65, base + d * length, r * 0.92, r * 0.25, sides, tip_mat, cap0=False)


def ammo_box(label, label_band, cart, n_cart=3):
    """Cardboard ammo box with a label band and a few loose rounds."""
    mb = lp.MeshBuilder()
    w, d, h = 0.130, 0.085, 0.045
    rbox(mb, (-w / 2, -d / 2, 0.0), (w / 2, d / 2, h), label, 0.006)
    band(mb, (-w / 2, -d / 2), (w / 2, d / 2), h * 0.35, h * 0.72, 0.002, label_band)
    mb.box((-w / 2 + 0.012, -d / 2 - 0.004, 0.012), (-w / 2 + 0.040, -d / 2 - 0.001, 0.034), "paint_white")
    for k in range(n_cart):
        y = -d / 2 - 0.018 - k * 0.022
        cartridge(mb, (-0.03 + 0.03 * k, y, cart[1]), (1, 0.15 * (k - 1), 0), cart[0], cart[1], cart[2], cart[3])
    return mb


def item_ammo_box_9mm():
    return ammo_box("plastic_blue", "paint_white", (0.029, 0.0050, "brass", "stone_dark"))


def item_ammo_box_357():
    return ammo_box("paint_red", "paper", (0.040, 0.0058, "brass", "stone_dark"))


def item_ammo_box_shells():
    mb = lp.MeshBuilder()
    w, d, h = 0.130, 0.070, 0.072
    rbox(mb, (-w / 2, -d / 2, 0.0), (w / 2, d / 2, h), "paint_yellow", 0.006)
    band(mb, (-w / 2, -d / 2), (w / 2, d / 2), h * 0.30, h * 0.62, 0.002, "plastic_red")
    for k in range(3):
        y = -d / 2 - 0.022 - k * 0.030
        mb.cylinder((-0.035, y, 0.0105), (-0.022, y, 0.0105), 0.011, 0.011, 8, "brass")
        mb.cylinder((-0.022, y, 0.0105), (0.036, y, 0.0105), 0.0102, 0.0102, 8, "plastic_red",
                    cap_mats=(None, "wood_dark"))
    return mb


def item_ammo_box_308():
    mb = lp.MeshBuilder()
    w, d, h = 0.150, 0.080, 0.055
    rbox(mb, (-w / 2, -d / 2, 0.0), (w / 2, d / 2, h), "military_green", 0.006)
    band(mb, (-w / 2, -d / 2), (w / 2, d / 2), h * 0.55, h * 0.80, 0.002, "paint_yellow")
    for k in range(3):
        y = -d / 2 - 0.018 - k * 0.022
        cartridge(mb, (-0.04 + 0.02 * k, y, 0.006), (1, 0.1 * (k - 1), 0), 0.071, 0.006, "brass", "rust")
    return mb


def item_arrow_bundle():
    import weapons.build_firearms as F  # noqa: E402  (shared arrow recipe)
    mb = lp.MeshBuilder()
    for k, (x, z) in enumerate(((0.0, 0.006), (0.011, 0.006), (-0.011, 0.006), (0.0, 0.016))):
        a = lp.MeshBuilder()
        F.arrow_mesh(a, (0.0, 0.35 + 0.015 * (k % 3), 0.0))
        rot = Matrix.Rotation(math.radians(90 + 3 * (k - 2)), 4, 'Z')
        a.transform(Matrix.Translation(Vector((0.0, x * 1.0, z))) @ rot)
        mb.extend(a)
    for x in (-0.10, 0.12):
        mb.cylinder((x, 0.0, 0.010), (x + 0.02, 0.0, 0.010), 0.016, 0.016, 8, "strap")
    return mb


def item_medkit():
    mb = lp.MeshBuilder()
    w, d, h = 0.26, 0.17, 0.09
    rbox(mb, (-w / 2, -d / 2, 0.0), (w / 2, d / 2, h), "paint_red", 0.012)
    band(mb, (-w / 2, -d / 2 + 0.012), (w / 2, d / 2 - 0.012), h * 0.48, h * 0.54, 0.002, "cloth_dark")
    mb.box((-0.018, -0.052, h), (0.018, 0.052, h + 0.003), "paint_white")                    # cross
    mb.box((-0.052, -0.018, h), (0.052, 0.018, h + 0.003), "paint_white")
    mb.box((-0.045, -d / 2 - 0.012, h * 0.60), (0.045, -d / 2 + 0.002, h * 0.80), "plastic_black")  # handle
    return mb


def item_bandage():
    mb = lp.MeshBuilder()
    mb.cylinder((-0.045, 0.0, 0.040), (0.045, 0.0, 0.040), 0.040, 0.040, 10, "cloth_white",
                cap_mats=("paper", "paper"))
    mb.box((0.0, -0.13, 0.0), (0.060, -0.02, 0.004), "cloth_white")                          # unrolled strip
    mb.box((-0.03, 0.05, 0.0), (0.05, 0.11, 0.012), "paper")                                  # wrapper
    return mb


def can(label, label_band):
    mb = lp.MeshBuilder()
    r, h = 0.037 * PICKUP_SCALE, 0.11 * PICKUP_SCALE
    banded_cylinder(mb, r, [0.0, 0.006, h * 0.40, h * 0.62, h - 0.006, h],
                    ["chrome", label, label_band, label, "chrome"], taper=((0, 0.95), (5, 0.95)))
    return mb, False


def item_can_beans():
    mb, _ = can("can_red", "paper")
    return mb


def item_can_soup():
    mb, _ = can("can_blue", "paint_white")
    return mb


def item_batteries():
    mb = lp.MeshBuilder()
    mb.box((-0.075, -0.055, 0.0), (0.075, 0.055, 0.004), "paper")                            # card
    for k in range(4):
        x = -0.054 + k * 0.036
        mb.cylinder((x, -0.045, 0.0175), (x, 0.030, 0.0175), 0.0165, 0.0165, 8, "plastic_black")
        mb.cylinder((x, 0.030, 0.0175), (x, 0.046, 0.0175), 0.0165, 0.0165, 8, "paint_yellow")
        mb.cylinder((x, 0.046, 0.0175), (x, 0.050, 0.0175), 0.006, 0.006, 6, "chrome")
    return mb


def item_jerrycan():
    mb = lp.MeshBuilder()
    w, d, h = 0.34, 0.17, 0.46
    rbox(mb, (-d / 2, -w / 2, 0.0), (d / 2, w / 2, h - 0.03), "paint_red", 0.02)             # body (thin along X)
    for z in (0.12, 0.26):                                                                 # pressed ribs
        band(mb, (-d / 2, -w / 2 + 0.03), (d / 2, w / 2 - 0.03), z, z + 0.03, 0.004, "paint_red")
    for y in (-0.06, 0.0, 0.06):                                                           # 3 handles
        mb.box((-0.012, y - 0.012, h - 0.03), (0.012, y + 0.012, h + 0.03), "paint_red")
    mb.box((-0.012, -0.08, h + 0.02), (0.012, 0.08, h + 0.045), "paint_red")
    mb.cylinder((0.0, -0.14, h - 0.04), (0.0, -0.17, h + 0.02), 0.028, 0.026, 8, "paint_black",
                cap_mats=(None, "paint_black"))                                            # spout cap
    mb.box((d / 2 - 0.001, -0.08, 0.20), (d / 2 + 0.003, 0.08, 0.30), "paint_yellow")          # label
    return mb


def item_gun_parts():
    mb = lp.MeshBuilder()
    rbox(mb, (-0.09, -0.055, 0.0), (0.09, 0.055, 0.045), "metal_sheet", 0.006)               # tin
    band(mb, (-0.09, -0.055), (0.09, 0.055), 0.030, 0.034, 0.002, "gun_metal")               # lid seam
    mb.box((-0.05, -0.03, 0.045), (0.05, 0.03, 0.047), "paper")                               # label
    H.tube(mb, [(0.11, -0.03, 0.008), (0.12, 0.0, 0.010), (0.11, 0.03, 0.012), (0.12, 0.06, 0.010)],
           [0.007, 0.007, 0.007, 0.007], 5, "chrome", cap_end=True, cap_start=True)       # spring
    mb.cylinder((-0.12, -0.05, 0.006), (-0.12, 0.04, 0.006), 0.005, 0.005, 6, "gun_metal")   # pin
    mb.box((-0.15, 0.05, 0.0), (-0.10, 0.08, 0.010), "gun_metal")                            # extractor
    return mb


def item_gun_oil():
    mb = lp.MeshBuilder()
    banded_cylinder(mb, 0.032, [0.0, 0.035, 0.095, 0.13, 0.16], ["paint_black", "paint_yellow", "paint_black",
                                                                 "paint_black"], sides=10, taper=((4, 0.38),))
    mb.cylinder((0, 0, 0.158), (0, 0, 0.20), 0.006, 0.003, 6, "paint_red")
    return mb


# ------------------------------------------------------------------------------------------------------------
CONTAINERS = {"crate": crate, "footlocker": footlocker, "locker": locker, "fridge": fridge,
              "kitchen_cabinet": kitchen_cabinet, "backpack": backpack, "body_bag": body_bag}
PICKUPS = {"ammo_box_9mm": (item_ammo_box_9mm, "ammo_9mm", 1.0), "ammo_box_357": (item_ammo_box_357, "ammo_357", 1.0),
           "ammo_box_shells": (item_ammo_box_shells, "ammo_shells", 1.0),
           "ammo_box_308": (item_ammo_box_308, "ammo_308", 1.0), "arrow_bundle": (item_arrow_bundle, "arrows", 1.0),
           "medkit": (item_medkit, "medkit", 1.0), "bandage": (item_bandage, "bandage", 1.0),
           "can_beans": (item_can_beans, "food", 1.0 / PICKUP_SCALE), "can_soup": (item_can_soup, "food", 1.0 / PICKUP_SCALE),
           "batteries": (item_batteries, "batteries", 1.0), "jerrycan": (item_jerrycan, "fuel", 1.0 / PICKUP_SCALE),
           "gun_parts": (item_gun_parts, "gun_parts", 1.0), "gun_oil": (item_gun_oil, "gun_oil", 1.0)}
ALL = list(CONTAINERS) + list(PICKUPS)


def write_manifest(name, rec):
    man = export.MODELS_DIR / SUBDIR / "manifest.json"
    data = {}
    if man.exists():
        try:
            data = json.loads(man.read_text())
        except ValueError:
            data = {}
    data[name] = rec
    text = json.dumps(dict(sorted(data.items())), indent=1, sort_keys=True) + "\n"
    man.parent.mkdir(parents=True, exist_ok=True)
    if not man.exists() or man.read_text() != text:
        man.write_text(text)


def build_container(name):
    lp.new_scene()
    body, meta, (mn, mx) = CONTAINERS[name]()
    for k, v in meta.items():
        body[k] = v
    col_props(body, mn, mx)
    parts = {}
    for o in body.children:
        if o.type == 'MESH':
            parts[o.name] = dict(hinge=godot(lp.world_pivot(o)), hinge_axis=list(o["hinge_axis"]),
                                 open_deg=o["open_deg"])
    tris = lp.scene_tris()
    if tris > CONTAINER_BUDGET:
        raise RuntimeError("%s: tris %d > %d" % (name, tris, CONTAINER_BUDGET))
    glb = export.save_and_export(name, SUBDIR, ao=dict(distance=0.25, samples=48, ground=True), import_kind="prop")
    write_manifest(name, {"path": "res://assets/models/%s/%s.glb" % (SUBDIR, name), "node": body.name, "kind": "container",
                          "container": meta["container"], "slots": meta["slots"], "tris": tris,
                          "col_center": body["col_center"].to_list() if hasattr(body["col_center"], "to_list") else list(body["col_center"]),
                          "col_size": list(body["col_size"]), "parts": parts,
                          "loot": godot(lp.world_pivot(bpy.data.objects["Loot"]))})
    return glb


def build_pickup(name):
    lp.new_scene()
    fn, kind, scale = PICKUPS[name]
    mb = fn()
    s = PICKUP_SCALE * scale
    mb.transform(Matrix.Scale(s, 4))
    mn, mx = mb.bounds()
    mb.transform(Matrix.Translation(Vector((-(mn.x + mx.x) / 2, -(mn.y + mx.y) / 2, -mn.z))))
    o = H.mk(mb, "Item")
    H.smooth(o, 40.0)
    o["pickup"] = kind
    mn, mx = mb.bounds()
    col_props(o, mn, mx)
    tris = lp.scene_tris()
    if tris > PICKUP_BUDGET:
        raise RuntimeError("%s: tris %d > %d" % (name, tris, PICKUP_BUDGET))
    glb = export.save_and_export(name, SUBDIR, ao=dict(distance=0.08, samples=48, ground=True), import_kind="prop")
    write_manifest(name, {"path": "res://assets/models/%s/%s.glb" % (SUBDIR, name), "node": "Item", "kind": "pickup",
                          "pickup": kind, "tris": tris, "col_center": list(o["col_center"]),
                          "col_size": list(o["col_size"])})
    return glb


def main(argv=()):
    names = [a for a in argv if not a.startswith("-")] or ALL
    out = []
    for n in names:
        out.append(build_container(n) if n in CONTAINERS else build_pickup(n))
    return out


if __name__ == "__main__":
    main(sys.argv[1:])
