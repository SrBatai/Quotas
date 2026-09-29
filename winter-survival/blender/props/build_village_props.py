"""M6b village and POI props (PLAN_MAESTRO §7 M6b "Opus"; ASSET_SPEC_V2 §13 "Urbano (M6b)" + "M6b").

    cd winter-survival/blender && python3 props/build_village_props.py [lamp_post fuel_pump ...]

Exports assets/models/props/village/<name>.glb (+ sources/<name>.blend + `.import`, template "prop") and
assets/models/props/village/manifest.json. Front = -Y Blender (+Z Godot), origin = centre of the base at z = 0.

Contract (the A1 prop contract, MultiMesh-friendly): ONE mesh object `Prop`, ONE palette_vcol surface (no emissive:
the village lamps glow through VillageLights' halos and pools), no children / empties / Col* nodes. Extras on `Prop`
(Godot coordinates, metres): `family` "village", `kind`, `height`, `col` ("box" | "cylinder"), `col_center`,
`col_size` ([w, h, d] or [diameter, h]), optional `cols` ([[centre, size], ...]: several boxes, e.g. the canopy's
columns) and `anchors` ({name: [x, y, z]}: LightAnchor / LightPool of lamps, WireA / WireB of power poles, Loot of the
dumpster). Section props (fences, barricades, the jersey) run along X from x = -1 to +1 (2 m), their "outside" toward
-Y Blender (+Z Godot); the game chains them every 2 m.
"""
import json
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import bpy  # noqa: E402,F401
from mathutils import Vector  # noqa: E402

from lib import export  # noqa: E402
from lib import hd as H  # noqa: E402
from lib import lowpoly as lp  # noqa: E402
from lib import veg as V  # noqa: E402

SUBDIR = "props/village"
BUDGET_SMALL = 700          # street furniture (ASSET_SPEC §13: 20-300 v2.0; HD v2.1 with snow and AO: A1 props 160-1400)
BUDGETS = {"gas_canopy": 1400, "silo": 1500, "tractor": 1800, "sawmill_saw": 1600, "log_pile": 1400,
           "lumber_stack": 900, "bus_stop": 900, "fence_chain_2": 700, "barricade_wire": 900, "shopping_cart": 900,
           "tire_stack": 700, "power_pole": 500, "lamp_post": 500, "gas_sign": 600, "fuel_pump": 600,
           "hay_round": 600, "barricade_sandbags": 1100, "dumpster": 600}


def godot(p):
    return V.godot(p)


def gsize(sx, sy, sz):
    """Blender box size (x, y, z) -> Godot [w, h, d]."""
    return [round(float(sx), 3), round(float(sz), 3), round(float(sy), 3)]


# ------------------------------------------------------------------------------------------------------------
# helpers
# ------------------------------------------------------------------------------------------------------------
def post(mb, x, y, z0, z1, r, mat, sides=8, r_top=None):
    mb.cylinder((x, y, z0), (x, y, z1), r, r if r_top is None else r_top, sides, mat)


def plank(mb, p0, p1, w, t, mat):
    H.beam(mb, p0, p1, w, t, mat)


def top_snow(parts, x0, x1, y, z, width, thick=0.05, seed=0):
    parts.append(H.snow_strip((x0, y, z), (x1, y, z), width, thick, seed=seed))


def base_mound(parts, x, y, r, h, seed):
    parts.append(H.mound((x, y, 0), r, h, seed=seed, sides=8, sink=0.05))


def flat_snow(parts, cx, cy, sx, sy, z, thick, seed, big=False):
    """Snow slab on a flat top (a pillow the size of the top; one subdivision level unless `big`)."""
    parts.append(H.pillow(Vector((cx - sx / 2, cy - sy / 2, z)), Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1)),
                          sx, sy, thick, nu=5 if big else 4, nv=4 if big else 3, rim=min(0.12, min(sx, sy) * 0.25), seed=seed,
                          levels=2 if big else 1))


# ------------------------------------------------------------------------------------------------------------
# street furniture
# ------------------------------------------------------------------------------------------------------------
def lamp_post():
    """Village street lamp: tarred wooden pole, steel bracket over the street (-Y), enamel shade; 6.3 m."""
    mb = lp.MeshBuilder()
    post(mb, 0, 0, -0.2, 6.1, 0.11, "wood_dark", 8, 0.085)
    mb.cylinder((0, 0.0, 5.75), (0, -1.15, 5.95), 0.03, 0.03, 6, "iron")                  # bracket
    mb.cylinder((0, 0.0, 5.35), (0, -0.55, 5.8), 0.022, 0.022, 6, "iron")                 # brace
    mb.cylinder((0, -1.3, 5.92), (0, -1.3, 5.72), 0.06, 0.26, 10, "paint_black", cap0=True, cap1=False)   # shade
    mb.cylinder((0, -1.3, 5.72), (0, -1.3, 5.70), 0.26, 0.24, 10, "paint_black", cap0=False, cap1=True)
    mb.cylinder((0, -1.3, 5.70), (0, -1.3, 5.60), 0.09, 0.07, 8, "lamp_clear")              # bulb
    mb.box((-0.12, 0.10, 2.2), (0.12, 0.2, 2.5), "metal_sheet")                            # junction box
    parts = [H.smooth(H.mk(mb), 35.0)]
    parts.append(H.snow_cone_cap((0, -1.3, 5.72), 0.24, 5.72, 5.95, 0.05, sides=10, seed=11))
    base_mound(parts, 0, 0, 0.35, 0.12, 12)
    info = dict(kind="lamp", col="cylinder", col_center=godot((0, 0, 3.0)), col_size=[0.22, 6.0],
                anchors={"LightAnchor": godot((0, -1.3, 5.62)), "LightPool": godot((0, -1.3, 0.02))})
    return parts, info


def power_pole():
    """Wooden utility pole 8 m, cross-arm across the line (along Y), three insulators; wires at WireA / WireB."""
    mb = lp.MeshBuilder()
    post(mb, 0, 0, -0.2, 8.0, 0.14, "wood_dark", 8, 0.11)
    mb.box((-0.06, -0.95, 7.5), (0.06, 0.95, 7.62), "wood")                                # cross arm
    for y in (-0.8, 0.0, 0.8):
        mb.cylinder((0, y, 7.62), (0, y, 7.78), 0.035, 0.03, 6, "concrete")                # insulators
    mb.cylinder((0.0, 0.0, 7.1), (0.0, -0.6, 7.52), 0.02, 0.02, 5, "iron")                 # braces
    mb.cylinder((0.0, 0.0, 7.1), (0.0, 0.6, 7.52), 0.02, 0.02, 5, "iron")
    mb.box((-0.02, -0.2, 2.6), (0.02, 0.2, 2.9), "paint_yellow")                           # danger plate
    parts = [H.smooth(H.mk(mb), 35.0)]
    parts.append(H.snow_strip((0, -0.95, 7.62), (0, 0.95, 7.62), 0.1, 0.04, seed=21))
    base_mound(parts, 0, 0, 0.45, 0.14, 22)
    info = dict(kind="pole", col="cylinder", col_center=godot((0, 0, 4.0)), col_size=[0.28, 8.0],
                anchors={"WireA": godot((0, -0.8, 7.78)), "WireB": godot((0, 0.8, 7.78))})
    return parts, info


def mailbox():
    """Rural mailbox on a post (door toward -Y), red flag."""
    mb = lp.MeshBuilder()
    mb.box((-0.04, -0.04, -0.2), (0.04, 0.04, 1.0), "wood")
    mb.box((-0.14, -0.28, 1.0), (0.14, 0.24, 1.22), "metal_blue")
    mb.cylinder((-0.14, -0.02, 1.22), (0.14, -0.02, 1.22), 0.13, 0.13, 8, "metal_blue")    # rounded roof (axis X)
    mb.box((-0.12, -0.29, 1.02), (0.12, -0.28, 1.28), "metal_sheet")                       # door
    mb.box((0.14, 0.0, 1.1), (0.16, 0.03, 1.42), "paint_red")                              # flag
    parts = [H.smooth(H.mk(mb), 35.0)]
    parts.append(H.snow_strip((0, -0.28, 1.35), (0, 0.24, 1.35), 0.2, 0.05, seed=31))
    base_mound(parts, 0, 0, 0.25, 0.1, 32)
    return parts, dict(kind="mailbox", col="box", col_center=godot((0, -0.02, 0.7)), col_size=gsize(0.3, 0.55, 1.4))


def bench():
    """Park bench: cast-iron ends, wooden slats; snow on the seat and the back rail."""
    mb = lp.MeshBuilder()
    for x in (-0.8, 0.8):
        mb.box((x - 0.04, -0.28, 0.0), (x + 0.04, 0.22, 0.08), "iron")
        mb.box((x - 0.04, -0.22, 0.08), (x + 0.04, -0.16, 0.45), "iron")
        mb.box((x - 0.04, 0.14, 0.08), (x + 0.04, 0.22, 0.85), "iron")
        mb.box((x - 0.04, -0.26, 0.42), (x + 0.04, 0.2, 0.46), "iron")
    for k in range(4):
        y = -0.24 + 0.11 * k
        mb.box((-0.95, y, 0.46), (0.95, y + 0.085, 0.5), "wood")
    for k in range(2):
        z = 0.58 + 0.16 * k
        mb.box((-0.95, 0.16, z), (0.95, 0.2, z + 0.1), "wood")
    parts = [H.flat(H.mk(mb))]
    flat_snow(parts, 0, -0.08, 1.7, 0.36, 0.5, 0.05, 41)
    parts.append(H.snow_strip((-0.92, 0.18, 0.84), (0.92, 0.18, 0.84), 0.06, 0.03, seed=42))
    return parts, dict(kind="bench", col="box", col_center=godot((0, -0.03, 0.425)), col_size=gsize(1.9, 0.52, 0.85))


def trash_can():
    """Village litter bin: green steel basket on a post, snow cap."""
    mb = lp.MeshBuilder()
    post(mb, 0, 0.18, -0.2, 1.05, 0.035, "metal_sheet", 6)
    mb.cylinder((0, -0.04, 0.42), (0, -0.04, 0.95), 0.2, 0.22, 10, "military_green", cap0=True, cap1=False)
    mb.cylinder((0, -0.04, 0.9), (0, -0.04, 0.96), 0.23, 0.23, 10, "iron")
    mb.cylinder((0, -0.04, 0.95), (0, -0.04, 0.5), 0.2, 0.18, 10, "plastic_black", cap0=False, cap1=True)   # inside
    parts = [H.smooth(H.mk(mb), 35.0)]
    parts.append(H.snow_cap((0, -0.04, 0), 0.19, 0.19, 0.06, lambda x, y: 0.88, seed=51, sides=8, rings=2))
    return parts, dict(kind="bin", col="cylinder", col_center=godot((0, 0, 0.5)), col_size=[0.46, 1.0])


def dumpster():
    """1100 l waste container: green body, black lid, 4 casters; snow on the lid. Loot = in front of it."""
    mb = lp.MeshBuilder()
    mb.tapered_box(0.18, 1.18, (1.3, 0.95), (1.4, 1.05), "military_green")
    mb.box((-0.74, -0.58, 1.18), (0.74, 0.58, 1.26), "plastic_black")                     # lid
    mb.box((-0.72, -0.62, 1.0), (0.72, -0.55, 1.08), "iron")                               # rim / handle
    for x in (-0.55, 0.55):
        for y in (-0.38, 0.38):
            mb.cylinder((x - 0.04, y, 0.09), (x + 0.04, y, 0.09), 0.09, 0.09, 8, "tire")
    mb.box((-0.45, -0.525, 0.5), (0.45, -0.52, 0.85), "paint_white")                      # sticker
    parts = [H.smooth(H.mk(mb), 30.0)]
    flat_snow(parts, 0, 0, 1.44, 1.12, 1.26, 0.09, 61)
    info = dict(kind="dumpster", col="box", col_center=godot((0, 0, 0.63)), col_size=gsize(1.45, 1.1, 1.26),
                anchors={"Loot": godot((0, -0.95, 0.0))})
    return parts, info


def bus_stop():
    """Rural bus shelter: concrete back and side walls, tin roof, bench; open front toward -Y."""
    mb = lp.MeshBuilder()
    mb.box((-1.5, 0.55, 0.0), (1.5, 0.7, 2.3), "concrete")                                 # back wall
    for x in (-1.5, 1.35):
        mb.box((x, -0.6, 0.0), (x + 0.15, 0.7, 2.3), "concrete")                           # sides
    mb.box((-1.62, -0.85, 2.3), (1.62, 0.8, 2.42), "metal_sheet")                          # roof
    mb.box((-1.2, 0.2, 0.42), (1.2, 0.55, 0.47), "wood")                                   # bench
    for x in (-1.0, 1.0):
        mb.box((x - 0.04, 0.3, 0.0), (x + 0.04, 0.45, 0.42), "iron")
    mb.box((-1.2, 0.54, 1.3), (-0.3, 0.55, 1.9), "paint_white")                            # timetable
    mb.box((1.55, -0.72, 1.6), (1.6, -0.3, 2.0), "metal_blue")                             # BUS plate
    parts = [H.flat(H.mk(mb))]
    flat_snow(parts, 0, -0.02, 3.2, 1.6, 2.42, 0.12, 71)
    base_mound(parts, 1.9, 0.4, 0.5, 0.2, 72)
    info = dict(kind="bus_stop", col="box", col_center=godot((0, 0.62, 1.15)), col_size=gsize(3.2, 0.2, 2.3),
                cols=[[godot((0, 0.62, 1.15)), gsize(3.2, 0.2, 2.3)], [godot((-1.43, 0.05, 1.15)), gsize(0.2, 1.3, 2.3)],
                      [godot((1.43, 0.05, 1.15)), gsize(0.2, 1.3, 2.3)]],
                anchors={"Seat": godot((0, 0.37, 0.47))})
    return parts, info


def hydrant():
    """Spanish red fire hydrant (column type), 0.8 m."""
    mb = lp.MeshBuilder()
    mb.cylinder((0, 0, -0.1), (0, 0, 0.08), 0.16, 0.15, 10, "paint_red")
    mb.cylinder((0, 0, 0.08), (0, 0, 0.66), 0.11, 0.1, 10, "paint_red")
    mb.cylinder((0, 0, 0.66), (0, 0, 0.8), 0.12, 0.05, 10, "paint_red")
    for a in (0, 180):
        r = math.radians(a)
        mb.cylinder((0, 0, 0.5), (math.sin(r) * 0.2, -math.cos(r) * 0.2, 0.5), 0.045, 0.045, 6, "chrome")
    mb.cylinder((0, 0, 0.3), (0, -0.2, 0.3), 0.06, 0.06, 6, "chrome")
    parts = [H.smooth(H.mk(mb), 35.0)]
    parts.append(H.snow_cone_cap((0, 0, 0.66), 0.12, 0.66, 0.8, 0.03, sides=8, seed=81))
    return parts, dict(kind="hydrant", col="cylinder", col_center=godot((0, 0, 0.4)), col_size=[0.34, 0.8])


# ------------------------------------------------------------------------------------------------------------
# fences and barricades (2 m sections along X)
# ------------------------------------------------------------------------------------------------------------
def fence_wood_2():
    """Picket-and-rail fence section: post at x = -1, two rails, pickets; snow on the top rail and picket tops."""
    mb = lp.MeshBuilder()
    mb.box((-1.06, -0.06, -0.2), (-0.94, 0.06, 1.15), "wood_dark")
    for z in (0.3, 0.85):
        mb.box((-1.0, 0.04, z), (1.0, 0.1, z + 0.09), "wood")
    for k in range(9):
        x = -0.85 + 0.21 * k
        mb.box((x - 0.045, -0.0, 0.08), (x + 0.045, 0.035, 1.02), "wood_light")
    parts = [H.flat(H.mk(mb))]
    parts.append(H.snow_strip((-1.0, 0.07, 0.94), (1.0, 0.07, 0.94), 0.07, 0.03, seed=91))
    parts.append(H.mound((0, -0.1, 0), 0.9, 0.12, seed=92, sides=8, sink=0.05, stretch=(1.2, 0.35)))
    return parts, dict(kind="fence", col="box", col_center=godot((0, 0.02, 0.55)), col_size=gsize(2.0, 0.14, 1.1))


def fence_wire_2():
    """Pasture fence: rough wooden post at x = -1 and three sagging barbed wires."""
    mb = lp.MeshBuilder()
    post(mb, -1.0, 0, -0.2, 1.25, 0.07, "wood_dark", 6, 0.06)
    for z in (0.45, 0.78, 1.1):
        for k in range(4):
            x0, x1 = -1.0 + 0.5 * k, -0.5 + 0.5 * k
            s0 = 0.04 * math.sin(math.pi * (x0 + 1.0) / 2.0)
            s1 = 0.04 * math.sin(math.pi * (x1 + 1.0) / 2.0)
            mb.box((x0, -0.008, z - s0 - 0.008), (x1, 0.008, z - s1 + 0.008), "iron")
    parts = [H.smooth(H.mk(mb), 35.0)]
    parts.append(H.snow_cap((-1.0, 0, 0), 0.08, 0.08, 0.05, lambda x, y: 1.25, seed=95, sides=6, rings=2))
    parts.append(H.mound((-1.0, 0, 0), 0.25, 0.1, seed=96, sides=7, sink=0.05))
    return parts, dict(kind="fence", col="box", col_center=godot((0, 0, 0.6)), col_size=gsize(2.0, 0.1, 1.2))


def fence_chain_2():
    """Chain-link fence: galvanised post at x = -1, top rail, a coarse mesh of thin wires."""
    mb = lp.MeshBuilder()
    post(mb, -1.0, 0, -0.2, 1.9, 0.04, "metal_sheet", 8)
    mb.cylinder((-1.0, 0, 1.85), (1.0, 0, 1.85), 0.025, 0.025, 6, "metal_sheet")
    for k in range(10):
        x = -0.9 + 0.2 * k
        mb.box((x - 0.006, -0.006, 0.05), (x + 0.006, 0.006, 1.83), "metal_sheet")
    for k in range(8):
        z = 0.15 + 0.23 * k
        mb.box((-1.0, -0.006, z - 0.006), (1.0, 0.006, z + 0.006), "metal_sheet")
    parts = [H.smooth(H.mk(mb), 35.0)]
    parts.append(H.snow_strip((-1.0, 0, 1.87), (1.0, 0, 1.87), 0.05, 0.025, seed=101))
    parts.append(H.mound((0, 0, 0), 0.9, 0.15, seed=102, sides=8, sink=0.05, stretch=(1.2, 0.35)))
    return parts, dict(kind="fence", col="box", col_center=godot((0, 0, 0.95)), col_size=gsize(2.0, 0.08, 1.9))


def barricade_wood():
    """Improvised barricade: two trestles with planks nailed across and a door leaf; snow on the top plank."""
    mb = lp.MeshBuilder()
    for x in (-0.8, 0.8):
        plank(mb, (x - 0.1, -0.4, 0.0), (x, 0.0, 1.1), 0.08, 0.08, "wood_dark")
        plank(mb, (x + 0.1, 0.4, 0.0), (x, 0.0, 1.1), 0.08, 0.08, "wood_dark")
    for k, (z0, z1) in enumerate([(0.35, 0.45), (0.7, 0.62), (1.0, 1.08)]):
        plank(mb, (-1.0, -0.05 - 0.02 * k, z0), (1.0, -0.05 - 0.02 * k, z1), 0.2, 0.04, "wood" if k != 1 else "wood_light")
    plank(mb, (-0.9, -0.14, 0.15), (0.85, -0.14, 1.12), 0.18, 0.04, "wood_light")                 # cross plank
    mb.box((0.15, -0.28, 0.0), (0.95, -0.22, 1.0), "paint_white")                                  # an old door
    parts = [H.flat(H.mk(mb))]
    parts.append(H.snow_strip((-1.0, -0.09, 1.1), (1.0, -0.09, 1.1), 0.18, 0.05, seed=111))
    parts.append(H.mound((0, -0.2, 0), 1.0, 0.2, seed=112, sides=8, sink=0.05, stretch=(1.1, 0.5)))
    return parts, dict(kind="barricade", col="box", col_center=godot((0, -0.05, 0.6)), col_size=gsize(2.1, 0.8, 1.2))


def barricade_sandbags():
    """Sandbag wall section: three staggered courses of bags, snow along the top."""
    rnd = random.Random(121)
    mb = lp.MeshBuilder()
    for c, z in enumerate((0.0, 0.2, 0.4)):
        n = 4 if c % 2 == 0 else 3
        w = 2.0 / 4.0
        x0 = -1.0 + w / 2 + (0.0 if c % 2 == 0 else w / 2)
        for k in range(n):
            x = x0 + w * k
            mb.blob((x, rnd.uniform(-0.03, 0.03), z + 0.11), (w * 0.52, 0.3 - 0.05 * c, 0.12), "cloth", subdiv=1,
                    jitter=0.05, rnd=rnd, clamp_z=z)
    parts = [H.smooth(H.mk(mb), 60.0)]
    parts.append(H.snow_strip((-0.85, 0.0, 0.62), (0.85, 0.0, 0.62), 0.32, 0.07, seed=122))
    return parts, dict(kind="barricade", col="box", col_center=godot((0, 0, 0.32)), col_size=gsize(2.0, 0.6, 0.64))


def barricade_wire():
    """Concertina wire on two X trestles (Spanish rider), 2 m."""
    mb = lp.MeshBuilder()
    for x in (-0.9, 0.9):
        plank(mb, (x, -0.45, 0.0), (x, 0.45, 0.9), 0.06, 0.06, "wood_dark")
        plank(mb, (x, 0.45, 0.0), (x, -0.45, 0.9), 0.06, 0.06, "wood_dark")
    plank(mb, (-1.0, 0.0, 0.45), (1.0, 0.0, 0.45), 0.06, 0.06, "wood_dark")
    for k in range(9):
        x = -0.9 + 0.225 * k
        pts = []
        for j in range(9):
            a = 2 * math.pi * j / 8
            pts.append(Vector((x + 0.05 * math.sin(a * 0.5), 0.32 * math.cos(a), 0.48 + 0.32 * math.sin(a))))
        H.tube(mb, pts, [0.008] * len(pts), 4, "iron")
    parts = [H.smooth(H.mk(mb), 40.0)]
    parts.append(H.mound((0, 0, 0), 1.0, 0.18, seed=131, sides=8, sink=0.05, stretch=(1.1, 0.5)))
    return parts, dict(kind="barricade", col="box", col_center=godot((0, 0, 0.45)), col_size=gsize(2.0, 0.9, 0.9))


def barricade_jersey():
    """Concrete jersey barrier section (2 m, 0.8 m high), red-white reflector band; snow along the crest."""
    mb = lp.MeshBuilder()
    prof = [(-0.3, 0.0), (-0.3, 0.08), (-0.18, 0.3), (-0.08, 0.8), (0.08, 0.8), (0.18, 0.3), (0.3, 0.08), (0.3, 0.0)]
    mb.prism([Vector((-1.0, y, z)) for y, z in prof], (-1.0, 0, 0), (1.0, 0, 0), "concrete")
    mb.box((-0.6, -0.16, 0.5), (-0.2, -0.13, 0.58), "paint_red")
    mb.box((0.2, -0.16, 0.5), (0.6, -0.13, 0.58), "paint_white")
    parts = [H.flat(H.mk(mb))]
    parts.append(H.snow_strip((-1.0, 0.0, 0.8), (1.0, 0.0, 0.8), 0.16, 0.05, seed=141))
    parts.append(H.mound((0, -0.3, 0), 0.9, 0.12, seed=142, sides=8, sink=0.05, stretch=(1.2, 0.3)))
    return parts, dict(kind="barricade", col="box", col_center=godot((0, 0, 0.4)), col_size=gsize(2.0, 0.6, 0.8))


# ------------------------------------------------------------------------------------------------------------
# yard clutter
# ------------------------------------------------------------------------------------------------------------
def tire_stack():
    """Four old tyres stacked (slightly off): rounded treads, dark hub hole on the top one, snow in the ring."""
    rnd = random.Random(151)
    mb = lp.MeshBuilder()
    z = 0.0
    cx = cy = 0.0
    for k in range(4):
        cx, cy = rnd.uniform(-0.06, 0.06), rnd.uniform(-0.06, 0.06)
        mb.cylinder((cx, cy, z), (cx, cy, z + 0.03), 0.31, 0.35, 14, "tire", cap1=False)
        mb.cylinder((cx, cy, z + 0.03), (cx, cy, z + 0.17), 0.35, 0.35, 14, "tire", cap0=False, cap1=False)
        mb.cylinder((cx, cy, z + 0.17), (cx, cy, z + 0.2), 0.35, 0.31, 14, "tire", cap0=False)
        z += 0.2
    mb.cylinder((cx, cy, z), (cx, cy, z + 0.004), 0.19, 0.19, 12, "paint_black", cap0=False)   # the hub hole
    parts = [H.smooth(H.mk(mb), 50.0)]
    parts.append(H.snow_cap((cx, cy, 0), 0.28, 0.28, 0.05, lambda x, y: z, seed=152, sides=10, rings=2))
    return parts, dict(kind="tires", col="cylinder", col_center=godot((0, 0, 0.4)), col_size=[0.72, 0.8])


def pallet():
    """Euro pallet 1.2 x 0.8, snowed."""
    mb = lp.MeshBuilder()
    for k in range(5):
        x = -0.55 + 0.275 * k
        mb.box((x - 0.05, -0.4, 0.1), (x + 0.05, 0.4, 0.125), "wood_light")
    for y in (-0.36, 0.0, 0.36):
        mb.box((-0.6, y - 0.05, 0.02), (0.6, y + 0.05, 0.1), "wood")
        for x in (-0.55, 0.0, 0.55):
            mb.box((x - 0.05, y - 0.05, 0.0), (x + 0.05, y + 0.05, 0.02), "wood_dark")
    parts = [H.flat(H.mk(mb))]
    flat_snow(parts, 0, 0, 1.12, 0.74, 0.125, 0.06, 161)
    return parts, dict(kind="pallet", col="box", col_center=godot((0, 0, 0.07)), col_size=gsize(1.2, 0.8, 0.14))


def crate():
    """Wooden crate 0.8 m with planks and battens, snow on the lid."""
    mb = lp.MeshBuilder()
    mb.box((-0.38, -0.38, 0.0), (0.38, 0.38, 0.76), "wood")
    for z0, z1 in ((0.05, 0.12), (0.64, 0.71)):
        mb.box((-0.4, -0.4, z0), (0.4, -0.38, z1), "wood_dark")        # battens, front / back
        mb.box((-0.4, 0.38, z0), (0.4, 0.4, z1), "wood_dark")
        mb.box((-0.4, -0.38, z0), (-0.38, 0.38, z1), "wood_dark")      # sides
        mb.box((0.38, -0.38, z0), (0.4, 0.38, z1), "wood_dark")
    parts = [H.flat(H.mk(mb))]
    flat_snow(parts, 0, 0, 0.74, 0.74, 0.76, 0.07, 171)
    return parts, dict(kind="crate", col="box", col_center=godot((0, 0, 0.38)), col_size=gsize(0.8, 0.8, 0.76))


def barrel():
    """200 l steel drum (rusty blue), rolling hoops, snow on the lid."""
    mb = lp.MeshBuilder()
    mb.cylinder((0, 0, 0.0), (0, 0, 0.88), 0.29, 0.29, 12, "metal_blue")
    for z in (0.29, 0.59):
        mb.cylinder((0, 0, z - 0.015), (0, 0, z + 0.015), 0.3, 0.3, 12, "rust")
    parts = [H.smooth(H.mk(mb), 40.0)]
    parts.append(H.snow_cap((0, 0, 0), 0.27, 0.27, 0.06, lambda x, y: 0.88, seed=181, sides=10, rings=2))
    return parts, dict(kind="barrel", col="cylinder", col_center=godot((0, 0, 0.44)), col_size=[0.6, 0.88])


def shopping_cart():
    """Abandoned shopping trolley: wire basket, handle toward +Y, four casters; a little snow inside."""
    mb = lp.MeshBuilder()
    bars = []
    for x in (-0.25, 0.25):
        bars.append(((x, -0.5, 0.45), (x, 0.4, 0.45)))
        bars.append(((x, -0.5, 0.95), (x, 0.45, 1.0)))
        for y in (-0.5, -0.2, 0.1, 0.4):
            bars.append(((x, y, 0.45), (x, y + (0.05 if y > 0.3 else 0.0), 0.97)))
        bars.append(((x, -0.45, 0.1), (x, 0.35, 0.1)))
        bars.append(((x, 0.35, 0.1), (x, 0.4, 0.45)))
        bars.append(((x, -0.45, 0.1), (x, -0.5, 0.45)))
    for y in (-0.5, 0.4):
        bars.append(((-0.25, y, 0.45), (0.25, y, 0.45)))
        bars.append(((-0.25, y, 0.97), (0.25, y, 0.97)))
    for k in range(5):
        y = -0.5 + 0.225 * k
        bars.append(((-0.25, y, 0.45), (0.25, y, 0.45)))
    bars.append(((-0.25, 0.55, 1.05), (0.25, 0.55, 1.05)))
    for x in (-0.25, 0.25):
        bars.append(((x, 0.45, 1.0), (x, 0.55, 1.05)))
    for a, b in bars:
        mb.cylinder(a, b, 0.009, 0.009, 4, "chrome")
    mb.box((-0.27, 0.53, 1.03), (0.27, 0.58, 1.08), "plastic_red")
    for x in (-0.22, 0.22):
        for y in (-0.42, 0.33):
            mb.cylinder((x - 0.02, y, 0.05), (x + 0.02, y, 0.05), 0.05, 0.05, 6, "plastic_black")
    parts = [H.smooth(H.mk(mb), 40.0)]
    flat_snow(parts, 0, -0.05, 0.46, 0.84, 0.46, 0.08, 191)
    return parts, dict(kind="cart", col="box", col_center=godot((0, 0, 0.55)), col_size=gsize(0.56, 1.1, 1.1))


# ------------------------------------------------------------------------------------------------------------
# gas station
# ------------------------------------------------------------------------------------------------------------
def fuel_pump():
    """Fuel dispenser on its island: white body, dark display head, two nozzles on each side (+-X)."""
    mb = lp.MeshBuilder()
    mb.box((-0.7, -0.45, 0.0), (0.7, 0.45, 0.2), "concrete")                               # island
    mb.box((-0.42, -0.22, 0.2), (0.42, 0.22, 1.6), "paint_white")
    mb.box((-0.44, -0.24, 1.6), (0.44, 0.24, 2.05), "paint_black")
    mb.box((-0.3, -0.25, 1.68), (0.3, -0.24, 1.95), "lamp_clear")                          # display
    mb.box((-0.3, 0.24, 1.68), (0.3, 0.25, 1.95), "lamp_clear")
    mb.box((-0.43, -0.23, 1.2), (0.43, 0.23, 1.3), "paint_red")                            # band
    for s in (-1, 1):
        mb.box((s * 0.42, -0.1, 0.9), (s * 0.5, 0.1, 1.15), "iron")                        # nozzle holsters
        H.tube(mb, [Vector((s * 0.46, 0.0, 0.95)), Vector((s * 0.6, 0.0, 0.6)), Vector((s * 0.55, 0.0, 0.3)),
                    Vector((s * 0.46, 0.0, 0.25))], [0.02] * 4, 5, "plastic_black")
    parts = [H.flat(H.mk(mb))]
    flat_snow(parts, 0, 0, 0.86, 0.46, 2.05, 0.07, 201)
    parts.append(H.snow_strip((-0.7, -0.35, 0.2), (0.7, -0.35, 0.2), 0.18, 0.04, seed=202))
    return parts, dict(kind="pump", col="box", col_center=godot((0, 0, 1.0)), col_size=gsize(1.0, 0.5, 2.05))


def gas_sign():
    """Tall price sign by the road: two steel posts, a lit box with the logo band and three price rows (-Y face)."""
    mb = lp.MeshBuilder()
    for x in (-0.9, 0.9):
        mb.box((x - 0.1, -0.1, -0.2), (x + 0.1, 0.1, 4.6), "metal_sheet")
    mb.box((-1.3, -0.2, 4.6), (1.3, 0.2, 7.2), "paint_white")
    for s in (-1, 1):
        y = s * 0.205
        mb.box((-1.2, y - 0.004, 6.35), (1.2, y + 0.004, 7.1), "paint_red")                # logo band
        for k in range(3):
            z = 4.75 + 0.5 * k
            mb.box((-1.1, y - 0.004, z), (-0.1, y + 0.004, z + 0.38), "metal_blue")         # fuel names
            mb.box((0.05, y - 0.004, z), (1.1, y + 0.004, z + 0.38), "paint_black")        # prices
    parts = [H.flat(H.mk(mb))]
    flat_snow(parts, 0, 0, 2.6, 0.4, 7.2, 0.1, 211)
    for i, x in enumerate((-0.9, 0.9)):
        base_mound(parts, x, 0, 0.35, 0.14, 212 + i)
    info = dict(kind="gas_sign", col="box", col_center=godot((0, 0, 2.3)), col_size=gsize(2.0, 0.2, 4.6),
                cols=[[godot((-0.9, 0, 2.3)), gsize(0.2, 0.2, 4.6)], [godot((0.9, 0, 2.3)), gsize(0.2, 0.2, 4.6)]])
    return parts, info


def gas_canopy():
    """Forecourt canopy 12 x 8 m on four columns, 5 m clearance: white fascia with a red band, snow on the roof."""
    mb = lp.MeshBuilder()
    cols = []
    for x in (-4.0, 4.0):
        for y in (-2.2, 2.2):
            mb.box((x - 0.2, y - 0.2, 0.0), (x + 0.2, y + 0.2, 4.6), "paint_white")
            mb.box((x - 0.26, y - 0.26, 0.0), (x + 0.26, y + 0.26, 0.5), "paint_red")
            cols.append([godot((x, y, 2.3)), gsize(0.4, 0.4, 4.6)])
    mb.box((-6.0, -4.0, 4.6), (6.0, 4.0, 5.3), "paint_white")                               # roof box
    for s in (-1, 1):
        mb.box((-6.02, s * 4.0 - 0.01, 4.72), (6.02, s * 4.0 + 0.01, 4.92), "paint_red")
        mb.box((s * 6.0 - 0.01, -4.02, 4.72), (s * 6.0 + 0.01, 4.02, 4.92), "paint_red")
    mb.box((-5.8, -3.8, 4.55), (5.8, 3.8, 4.6), "metal_sheet")                              # soffit
    for x in (-3.0, 0.0, 3.0):
        for y in (-1.5, 1.5):
            mb.box((x - 0.4, y - 0.15, 4.52), (x + 0.4, y + 0.15, 4.55), "lamp_clear")     # light panels
    parts = [H.flat(H.mk(mb))]
    flat_snow(parts, 0, 0, 11.9, 7.9, 5.3, 0.25, 221, big=True)
    info = dict(kind="canopy", col="box", col_center=godot((0, 0, 2.3)), col_size=gsize(8.4, 4.8, 4.6), cols=cols,
                anchors={"LightAnchor": godot((0, 0, 4.5))})
    return parts, info


# ------------------------------------------------------------------------------------------------------------
# farm
# ------------------------------------------------------------------------------------------------------------
def silo():
    """Corrugated steel grain silo, 5.2 m wide x 11 m + cone roof, cage ladder on the -Y side, snow on the cone."""
    mb = lp.MeshBuilder()
    R, Hh = 2.6, 10.5
    mb.cylinder((0, 0, 0.0), (0, 0, 0.4), R + 0.2, R + 0.2, 16, "concrete")
    for k in range(7):
        z0 = 0.4 + (Hh - 0.4) * k / 7
        z1 = 0.4 + (Hh - 0.4) * (k + 1) / 7
        mb.cylinder((0, 0, z0), (0, 0, z1), R, R, 16, "metal_sheet" if k % 2 == 0 else "concrete", cap0=(k == 0), cap1=(k == 6))
        mb.cylinder((0, 0, z1 - 0.04), (0, 0, z1 + 0.04), R + 0.04, R + 0.04, 16, "concrete_dark")
    mb.cylinder((0, 0, Hh), (0, 0, Hh + 2.2), R + 0.12, 0.35, 16, "metal_sheet")
    mb.cylinder((0, 0, Hh + 2.2), (0, 0, Hh + 2.6), 0.35, 0.3, 8, "metal_sheet")
    for x in (-0.25, 0.25):
        mb.box((x - 0.03, -R - 0.18, 0.4), (x + 0.03, -R - 0.12, Hh + 0.6), "iron")
    for k in range(20):
        z = 0.8 + 0.5 * k
        mb.box((-0.25, -R - 0.16, z), (0.25, -R - 0.14, z + 0.03), "iron")
    parts = [H.smooth(H.mk(mb), 30.0)]
    parts.append(H.snow_cone_cap((0, 0, Hh), R + 0.1, Hh, Hh + 2.2, 0.15, sides=16, seed=231))
    parts.append(H.mound((0, 0, 0), R + 0.9, 0.35, seed=232, sides=16, sink=0.05))
    return parts, dict(kind="silo", col="cylinder", col_center=godot((0, 0, 5.5)), col_size=[5.4, 11.0])


def tractor():
    """Old farm tractor: red hood, cab with dark windows, big rear wheels, snow on the hood and roof. Front -Y."""
    mb = lp.MeshBuilder()
    mb.box((-0.45, -2.1, 0.75), (0.45, -0.3, 1.45), "paint_red")                          # hood
    mb.box((-0.5, -2.2, 0.6), (0.5, -1.95, 1.3), "iron")                                  # grille
    mb.box((-0.6, -0.4, 0.8), (0.6, 0.9, 1.2), "paint_red")                               # body under the cab
    for x in (-0.65, 0.65):
        mb.box((x - 0.05, -0.4, 1.2), (x + 0.05, -0.34, 2.55), "iron")                     # cab posts
        mb.box((x - 0.05, 0.84, 1.2), (x + 0.05, 0.9, 2.55), "iron")
        mb.box((x - 0.02, -0.34, 1.35), (x + 0.02, 0.84, 2.35), "paint_black")             # side windows
    mb.box((-0.6, -0.4, 1.35), (0.6, -0.36, 2.35), "paint_black")                          # windscreen
    mb.box((-0.7, -0.5, 2.55), (0.7, 1.0, 2.65), "paint_white")                            # roof
    mb.cylinder((0.3, -1.3, 1.45), (0.3, -1.3, 2.4), 0.05, 0.045, 6, "iron")               # exhaust
    for s in (-1, 1):
        mb.cylinder((s * 0.72, 0.6, 0.8), (s * 1.12, 0.6, 0.8), 0.8, 0.8, 16, "tire")      # rear wheels
        mb.cylinder((s * 0.7, 0.6, 0.8), (s * 0.74, 0.6, 0.8), 0.45, 0.45, 12, "paint_red")
        mb.cylinder((s * 0.5, -1.6, 0.45), (s * 0.75, -1.6, 0.45), 0.45, 0.45, 12, "tire")  # front wheels
        mb.box((s * 0.72 - 0.25 * s, 0.0, 1.55), (s * 1.15, 1.2, 1.6), "paint_red")        # fenders
    mb.box((-0.3, 1.0, 0.6), (0.3, 1.4, 0.75), "iron")                                     # hitch
    parts = [H.smooth(H.mk(mb), 30.0)]
    flat_snow(parts, 0, 0.25, 1.36, 1.46, 2.65, 0.14, 241)
    flat_snow(parts, 0, -1.2, 0.86, 1.7, 1.45, 0.1, 242)
    for s in (-1, 1):
        parts.append(H.snow_strip((s * 0.94, 0.02, 1.6), (s * 0.94, 1.18, 1.6), 0.38, 0.06, seed=243 + s))
    return parts, dict(kind="tractor", col="box", col_center=godot((0, -0.4, 1.3)), col_size=gsize(2.3, 3.8, 2.6))


def hay_bale():
    """Big square hay bale 1.2 x 0.9 x 0.7 with twines, snow on top."""
    mb = lp.MeshBuilder()
    mb.box((-0.6, -0.45, 0.0), (0.6, 0.45, 0.7), "hay")
    for x in (-0.3, 0.3):
        mb.box((x - 0.012, -0.46, 0.0), (x + 0.012, 0.46, 0.71), "wood_dark")
    parts = [H.flat(H.mk(mb))]
    flat_snow(parts, 0, 0, 1.16, 0.86, 0.71, 0.07, 251)
    return parts, dict(kind="hay", col="box", col_center=godot((0, 0, 0.35)), col_size=gsize(1.2, 0.9, 0.7))


def hay_round():
    """Round hay bale lying on its side (axis X), 1.5 m across, snow on the crown."""
    mb = lp.MeshBuilder()
    mb.cylinder((-0.6, 0, 0.75), (0.6, 0, 0.75), 0.75, 0.75, 16, "hay")
    for x in (-0.3, 0.0, 0.3):
        mb.cylinder((x - 0.01, 0, 0.75), (x + 0.01, 0, 0.75), 0.755, 0.755, 16, "wood_dark", cap0=False, cap1=False)
    parts = [H.smooth(H.mk(mb), 40.0)]
    parts.append(H.snow_strip((-0.58, 0, 1.49), (0.58, 0, 1.49), 0.8, 0.09, seed=261, droop=0.05))
    return parts, dict(kind="hay", col="box", col_center=godot((0, 0, 0.75)), col_size=gsize(1.2, 1.5, 1.5))


# ------------------------------------------------------------------------------------------------------------
# sawmill
# ------------------------------------------------------------------------------------------------------------
def sawmill_saw():
    """Log saw line (8 m along X): rail track, carriage with a log, the head rig with a big circular blade and
    its motor house, a roof over the saw; snow on the roof and the log."""
    mb = lp.MeshBuilder()
    for y in (-0.5, 0.5):
        mb.box((-4.0, y - 0.06, 0.0), (4.0, y + 0.06, 0.18), "iron")                       # rails
    for k in range(9):
        x = -4.0 + k
        mb.box((x - 0.1, -0.7, 0.0), (x + 0.1, 0.7, 0.08), "wood_dark")                    # sleepers
    mb.box((-3.4, -0.65, 0.18), (-0.6, 0.65, 0.5), "iron")                                  # carriage
    for x in (-3.2, -0.8):
        mb.box((x - 0.08, -0.7, 0.5), (x + 0.08, -0.55, 1.1), "rust")                      # dogs
    mb.cylinder((-3.8, 0.0, 0.95), (-0.2, 0.0, 0.95), 0.42, 0.4, 10, "bark")              # log
    mb.cylinder((-3.81, 0.0, 0.95), (-3.8, 0.0, 0.95), 0.4, 0.4, 10, "wood_light", cap0=True, cap1=False)
    mb.box((0.6, -1.3, 0.0), (1.4, 1.3, 1.6), "paint_yellow")                               # head rig frame
    mb.cylinder((1.0, -0.04, 1.25), (1.0, 0.04, 1.25), 0.85, 0.85, 20, "chrome")          # the blade (axis Y)
    mb.box((1.4, -1.0, 0.0), (2.8, 0.2, 1.4), "military_green")                            # motor house
    mb.cylinder((1.9, 0.2, 1.0), (1.9, 0.7, 1.0), 0.25, 0.25, 10, "iron")                  # pulley
    for x, y in ((-4.2, -1.6), (-4.2, 1.6), (3.2, -1.6), (3.2, 1.6), (-0.5, -1.6), (-0.5, 1.6)):
        mb.box((x - 0.08, y - 0.08, 0.0), (x + 0.08, y + 0.08, 3.2), "wood_dark")         # roof posts
    mb.box((-4.4, -1.9, 3.2), (3.4, 1.9, 3.35), "metal_sheet")                              # roof
    parts = [H.smooth(H.mk(mb), 30.0)]
    flat_snow(parts, -0.5, 0, 7.6, 3.6, 3.35, 0.18, 271)
    parts.append(H.snow_strip((-3.7, 0.0, 1.35), (-0.3, 0.0, 1.35), 0.4, 0.05, seed=272))
    info = dict(kind="saw", col="box", col_center=godot((0.5, 0, 0.7)), col_size=gsize(7.0, 2.6, 1.4),
                cols=[[godot((-0.4, 0, 0.7)), gsize(8.0, 1.6, 1.4)], [godot((1.7, -0.5, 0.8)), gsize(2.4, 2.6, 1.6)]])
    for i, (x, y) in enumerate(((-4.2, -1.6), (-4.2, 1.6), (3.2, -1.6), (3.2, 1.6), (-0.5, -1.6), (-0.5, 1.6))):
        info["cols"].append([godot((x, y, 1.6)), gsize(0.16, 0.16, 3.2)])
    return parts, info


def log_pile():
    """Pile of 4 m logs stacked 3-2-1 along X, bark and cut ends, snow on the crest."""
    rnd = random.Random(281)
    mb = lp.MeshBuilder()
    rows = [(3, 0.0), (2, 0.5), (1, 0.97)]
    for n, z in rows:
        for k in range(n):
            y = (k - (n - 1) / 2.0) * 0.56
            r = rnd.uniform(0.24, 0.3)
            x0, x1 = -2.0 + rnd.uniform(-0.15, 0.1), 2.0 + rnd.uniform(-0.1, 0.15)
            mb.cylinder((x0, y, z + r), (x1, y, z + r), r, r * 0.95, 10, "bark", cap_mats=("wood_light", "wood_light"))
    for s in (-1, 1):
        mb.box((s * 1.2 - 0.06, -0.95, 0.0), (s * 1.2 + 0.06, -0.85, 1.2), "wood_dark")    # stakes
        mb.box((s * 1.2 - 0.06, 0.85, 0.0), (s * 1.2 + 0.06, 0.95, 1.2), "wood_dark")
    parts = [H.smooth(H.mk(mb), 40.0)]
    parts.append(H.snow_strip((-1.9, 0.0, 1.5), (1.9, 0.0, 1.5), 0.5, 0.08, seed=282, droop=0.04))
    parts.append(H.snow_strip((-1.9, -0.28, 1.0), (1.9, -0.28, 1.0), 0.3, 0.05, seed=283))
    parts.append(H.snow_strip((-1.9, 0.28, 1.0), (1.9, 0.28, 1.0), 0.3, 0.05, seed=284))
    return parts, dict(kind="logs", col="box", col_center=godot((0, 0, 0.75)), col_size=gsize(4.2, 1.9, 1.5))


def lumber_stack():
    """Stack of sawn planks on spacers (3.6 m along X), strapped, snow on top."""
    mb = lp.MeshBuilder()
    for x in (-1.5, 0.0, 1.5):
        mb.box((x - 0.06, -0.55, 0.0), (x + 0.06, 0.55, 0.12), "wood_dark")
    z = 0.12
    for layer in range(5):
        for k in range(5):
            y = -0.48 + 0.24 * k
            mb.box((-1.8, y - 0.1, z), (1.8, y + 0.1, z + 0.05), "wood_light" if (k + layer) % 2 else "wood")
        z += 0.05
        if layer in (1, 3):
            for x in (-1.5, 0.0, 1.5):
                mb.box((x - 0.03, -0.55, z), (x + 0.03, 0.55, z + 0.03), "wood_dark")
            z += 0.03
    for x in (-1.0, 1.0):
        mb.box((x - 0.02, -0.6, 0.1), (x + 0.02, 0.6, z + 0.01), "metal_sheet")            # straps
    parts = [H.flat(H.mk(mb))]
    flat_snow(parts, 0, 0, 3.5, 1.1, z, 0.09, 291)
    return parts, dict(kind="lumber", col="box", col_center=godot((0, 0, z / 2)), col_size=gsize(3.6, 1.2, z))


PROPS = {
    "lamp_post": lamp_post, "power_pole": power_pole, "mailbox": mailbox, "bench": bench, "trash_can": trash_can,
    "dumpster": dumpster, "bus_stop": bus_stop, "hydrant": hydrant,
    "fence_wood_2": fence_wood_2, "fence_wire_2": fence_wire_2, "fence_chain_2": fence_chain_2,
    "barricade_wood": barricade_wood, "barricade_sandbags": barricade_sandbags, "barricade_wire": barricade_wire,
    "barricade_jersey": barricade_jersey,
    "tire_stack": tire_stack, "pallet": pallet, "crate": crate, "barrel": barrel, "shopping_cart": shopping_cart,
    "fuel_pump": fuel_pump, "gas_sign": gas_sign, "gas_canopy": gas_canopy,
    "silo": silo, "tractor": tractor, "hay_bale": hay_bale, "hay_round": hay_round,
    "sawmill_saw": sawmill_saw, "log_pile": log_pile, "lumber_stack": lumber_stack,
}
MANIFEST_KEYS = ("family", "kind", "height", "radius", "col", "col_center", "col_size", "cols", "anchors")


def build(name):
    lp.new_scene()
    parts, info = PROPS[name]()
    obj = H.join(parts, "Prop")
    mn, mx = H.scene_bounds([obj])
    obj["family"] = "village"
    obj["height"] = round(float(mx.z), 3)
    obj["radius"] = round(float(max(abs(mn.x), abs(mx.x), abs(mn.y), abs(mx.y))), 3)
    for k, v in info.items():
        obj[k] = v
    if "anchors" not in info:
        obj["anchors"] = {}
    if "cols" not in info:
        obj["cols"] = []
    tris = lp.scene_tris()
    budget = BUDGETS.get(name, BUDGET_SMALL)
    if tris > budget:
        raise RuntimeError("%s: tris %d > %d" % (name, tris, budget))
    glb = export.save_and_export(name, SUBDIR, ao=dict(distance=0.6 if obj["height"] > 2.0 else 0.35, samples=48, ground=True),
                                 import_kind="prop")
    man = export.MODELS_DIR / SUBDIR / "manifest.json"
    data = {}
    if man.exists():
        try:
            data = json.loads(man.read_text())
        except ValueError:
            data = {}
    rec = {}
    for k in MANIFEST_KEYS:
        v = obj.get(k)
        if v is None:
            continue
        rec[k] = v.to_list() if hasattr(v, "to_list") else (v.to_dict() if hasattr(v, "to_dict") else v)
    rec = json.loads(json.dumps(rec, default=lambda o: o.to_list() if hasattr(o, "to_list") else o.to_dict()))
    rec["path"] = "res://assets/models/%s/%s.glb" % (SUBDIR, name)
    rec["node"] = "Prop"
    rec["tris"] = tris
    data[name] = rec
    text = json.dumps(dict(sorted(data.items())), indent=1, sort_keys=True) + "\n"
    if not man.exists() or man.read_text() != text:
        man.write_text(text)
    print("%-20s %5d tris  h %.2f" % (name, tris, obj["height"]))
    return glb


ALL = list(PROPS)


def main(argv=()):
    names = [a for a in argv if not a.startswith("-")] or ALL
    for n in names:
        build(n)


if __name__ == "__main__":
    main(sys.argv[1:])
