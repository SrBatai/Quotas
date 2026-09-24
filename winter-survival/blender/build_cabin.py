"""cabin (ASSET_SPEC §4.15): the hunter's house. Faces +Y (porch side). Walls x +-3.0, y +-2.5,
floor top z 0.30, eaves 3.0, ridge 4.6, chimney top 5.3. Separate top-level parts for the cutaway,
windows parented to their walls, embedded `-convcolonly` collision boxes.

Notes / deliberate choices (reported to the code agent):
* Wall *inner* faces use `wood` (warm plank interior like the reference); outer faces `cabin_wall`.
* The porch roof slab, its snow and its two support posts are part of `Roof` (not `Porch`) so that
  the cutaway (which hides `Roof`) also clears the porch roof that would otherwise hide the front of
  the room from the high camera, as in the reference.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402,F401  (must precede mathutils)
from mathutils import Vector  # noqa: E402

from lib import export  # noqa: E402
from lib import lowpoly as lp  # noqa: E402

T = 0.18                  # wall thickness
Z0, ZE = 0.30, 3.0        # floor top / eave
SIDING_STEP = 0.30
SIDING_D = 0.04           # lap board protrusion at its lower edge


class WallFace:
    """Maps wall-local (u = horizontal along the face, z, d = outward offset) to world coords."""

    def __init__(self, axis, plane, sign):
        self.axis, self.plane, self.sign = axis, plane, sign     # axis 'x' or 'y' = the face normal axis

    def p(self, u, z, d=0.0):
        if self.axis == 'y':
            return Vector((u, self.plane + self.sign * d, z))
        return Vector((self.plane + self.sign * d, u, z))

    @property
    def n(self):
        return Vector((0, self.sign, 0)) if self.axis == 'y' else Vector((self.sign, 0, 0))

    @property
    def u_dir(self):
        return Vector((1, 0, 0)) if self.axis == 'y' else Vector((0, 1, 0))


def siding(mb, face, u0, u1, holes, z_from=Z0, z_to=ZE):
    """Horizontal lap boards on an outer wall face, interrupted by `holes` [(u0,u1,z0,z1)]."""
    z = z_from
    while z < z_to - 1e-6:
        zl, zh = z, min(z + SIDING_STEP, z_to)
        cuts = sorted((h[0], h[1]) for h in holes if h[2] < zh - 1e-6 and h[3] > zl + 1e-6)
        segs, cur = [], u0
        for a, b in cuts:
            if a > cur:
                segs.append((cur, min(a, u1)))
            cur = max(cur, b)
        if cur < u1:
            segs.append((cur, u1))
        for a, b in segs:
            if b - a < 0.05:
                continue
            f = face
            mb.poly([f.p(a, zl, SIDING_D), f.p(b, zl, SIDING_D), f.p(b, zh, 0), f.p(a, zh, 0)], "cabin_wall",
                    facing=f.n)
            mb.poly([f.p(a, zl, 0), f.p(b, zl, 0), f.p(b, zl, SIDING_D), f.p(a, zl, SIDING_D)], "cabin_wall",
                    facing=(0, 0, -1))
            mb.poly([f.p(a, zl, 0), f.p(a, zl, SIDING_D), f.p(a, zh, 0)], "cabin_wall", facing=-f.u_dir)
            mb.poly([f.p(b, zl, 0), f.p(b, zl, SIDING_D), f.p(b, zh, 0)], "cabin_wall", facing=f.u_dir)
        z = zh


def face_box(mb, face, u0, u1, z0, z1, d0, d1, mat, skip_back=True):
    """Box on a wall face spanning u0..u1, z0..z1, from d0 to d1 outward."""
    a, b = face.p(u0, z0, d0), face.p(u1, z1, d1)
    mn = Vector((min(a.x, b.x), min(a.y, b.y), z0))
    mx = Vector((max(a.x, b.x), max(a.y, b.y), z1))
    skip = ()
    if skip_back and abs(d0) < 1e-9:
        key = ('-' if face.sign > 0 else '+') + face.axis
        skip = (key,)
    return mb.box(mn, mx, mat, skip=skip)


def window(face, u0, u1, z0=1.3, z1=2.3):
    """Painted-on window: pane quad (material `window`) 0.01 proud, trim frame 0.08 wide / 0.04 proud,
    one vertical + one horizontal mullion, and a sill."""
    mb = lp.MeshBuilder()
    f = face
    mb.poly([f.p(u0, z0, 0.01), f.p(u1, z0, 0.01), f.p(u1, z1, 0.01), f.p(u0, z1, 0.01)], "window",
            facing=f.n)
    w = 0.08
    face_box(mb, f, u0 - w, u0, z0 - w, z1 + w, 0, 0.04, "cabin_trim")
    face_box(mb, f, u1, u1 + w, z0 - w, z1 + w, 0, 0.04, "cabin_trim")
    face_box(mb, f, u0, u1, z1, z1 + w, 0, 0.04, "cabin_trim")
    face_box(mb, f, u0, u1, z0 - w, z0, 0, 0.04, "cabin_trim")
    um, zm = (u0 + u1) / 2, (z0 + z1) / 2
    face_box(mb, f, um - 0.02, um + 0.02, z0, z1, 0.0, 0.025, "cabin_trim")
    face_box(mb, f, u0, u1, zm - 0.02, zm + 0.02, 0.0, 0.025, "cabin_trim")
    face_box(mb, f, u0 - w - 0.06, u1 + w + 0.06, z0 - w - 0.06, z0 - w, 0, 0.09, "cabin_trim")   # sill
    return mb


def wall_box(mb, mn, mx, inner):
    """Wall slab: cabin_wall outside, wood inside (`inner` = face key toward the room)."""
    mb.box(mn, mx, "cabin_wall", mats={inner: "wood"})


# ------------------------------------------------------------------------------------------------
def build_floor():
    mb = lp.MeshBuilder()
    # stone foundation skirt (outer sides + top ring under the walls), open bottom
    o = [Vector((-3.0, -2.5, 0)), Vector((3.0, -2.5, 0)), Vector((3.0, 2.5, 0)), Vector((-3.0, 2.5, 0))]
    top_o = [p + Vector((0, 0, Z0)) for p in o]
    for i in range(4):
        a, b = o[i], o[(i + 1) % 4]
        mid = (a + b) / 2
        mb.poly([a, b, top_o[(i + 1) % 4], top_o[i]], "stone", facing=Vector((mid.x, mid.y, 0)))
    ix, iy = 2.82, 2.32
    inner = [Vector((-ix, -iy, Z0)), Vector((ix, -iy, Z0)), Vector((ix, iy, Z0)), Vector((-ix, iy, Z0))]
    for i in range(4):
        mb.poly([top_o[i], top_o[(i + 1) % 4], inner[(i + 1) % 4], inner[i]], "stone", facing=(0, 0, 1))
    # a darker stone course along the bottom of the foundation
    for (mn, mx) in (((-3.02, -2.52, 0.0), (3.02, -2.5, 0.08)), ((-3.02, 2.5, 0.0), (3.02, 2.52, 0.08)),
                     ((-3.02, -2.5, 0.0), (-3.0, 2.5, 0.08)), ((3.0, -2.5, 0.0), (3.02, 2.5, 0.08))):
        mb.box(mn, mx, "stone_dark", skip=('-z',))
    # interior floor slab (z 0.20-0.30): dark underlay + 12 plank strips (wood_light) with gaps
    mb.poly([(-ix, -iy, 0.292), (ix, -iy, 0.292), (ix, iy, 0.292), (-ix, iy, 0.292)], "wood_dark",
            facing=(0, 0, 1))
    n, gap = 12, 0.014
    pw = (2 * ix - (n - 1) * gap) / n
    for k in range(n):
        x0 = -ix + k * (pw + gap)
        mb.poly([(x0, -iy, Z0), (x0 + pw, -iy, Z0), (x0 + pw, iy, Z0), (x0, iy, Z0)], "wood_light",
                facing=(0, 0, 1))
    # threshold board in the doorway
    mb.box((-1.4, 2.30, Z0), (-0.4, 2.52, Z0 + 0.02), "wood_dark", skip=('-z',))
    return mb


def build_walls():
    walls = {}
    back = lp.MeshBuilder()
    wall_box(back, (-3.0, -2.5, Z0), (3.0, -2.5 + T, ZE), '+y')
    fb = WallFace('y', -2.5, -1)
    siding(back, fb, -2.9, 2.9, [])
    for x in (-3.0, 2.9):     # back corner trims (0.1 wide, 0.03 proud of both faces)
        back.box((x - 0.03 if x < 0 else x, -2.53, Z0), (x + 0.1 if x < 0 else x + 0.13, -2.40, ZE - 0.005),
                 "cabin_trim")   # top kept 5 mm under the wall tops (no z-fighting in the cutaway)
    walls["WallBack"] = back

    left = lp.MeshBuilder()
    wall_box(left, (-3.0, -2.5, Z0), (-3.0 + T, 2.5, ZE), '+x')
    fl = WallFace('x', -3.0, -1)
    siding(left, fl, -2.4, 2.4, [(-1.98 - 0.06, -0.62 + 0.06, 1.16, 2.38), (0.25, 0.95, 0.0, 9.0)])
    walls["WallLeft"] = left

    right = lp.MeshBuilder()
    wall_box(right, (3.0 - T, -2.5, Z0), (3.0, 2.5, ZE), '-x')
    fr = WallFace('x', 3.0, 1)
    siding(right, fr, -2.4, 2.4, [])
    walls["WallRight"] = right

    front = lp.MeshBuilder()
    y0, y1 = 2.5 - T, 2.5
    wall_box(front, (-3.0, y0, Z0), (-1.4, y1, ZE), '-y')
    wall_box(front, (-0.4, y0, Z0), (3.0, y1, ZE), '-y')
    wall_box(front, (-1.4, y0, 2.40), (-0.4, y1, ZE), '-y')
    ff = WallFace('y', 2.5, 1)
    siding(front, ff, -2.9, 2.9, [(-1.5, -0.3, 0.0, 2.5), (0.8 - 0.14, 2.0 + 0.14, 1.16, 2.38)])
    # door frame (0.1 wide) + jamb linings inside the opening
    face_box(front, ff, -1.5, -1.4, Z0, 2.5, 0, 0.03, "cabin_trim")
    face_box(front, ff, -0.4, -0.3, Z0, 2.5, 0, 0.03, "cabin_trim")
    face_box(front, ff, -1.4, -0.4, 2.40, 2.5, 0, 0.03, "cabin_trim")
    front.box((-1.4, y0 - 0.01, Z0), (-1.38, y1, 2.40), "cabin_trim", skip=('-x',))
    front.box((-0.42, y0 - 0.01, Z0), (-0.4, y1, 2.40), "cabin_trim", skip=('+x',))
    front.box((-1.4, y0 - 0.01, 2.38), (-0.4, y1, 2.40), "cabin_trim", skip=('+z',))
    for x in (-3.0, 2.9):     # front corner trims
        front.box((x - 0.03 if x < 0 else x, 2.40, Z0), (x + 0.1 if x < 0 else x + 0.13, 2.53, ZE - 0.005),
                  "cabin_trim")
    walls["WallFront"] = front
    return walls, ff, fl


def slope_z(y, y_eave, z_eave, y_ridge, z_ridge):
    return z_eave + (z_ridge - z_eave) * (y_eave - y) / (y_eave - y_ridge)


def build_roof():
    mb = lp.MeshBuilder()
    t, s = 0.15, 0.12
    slope = 1.6 / 2.9
    cos_t = math.cos(math.atan(slope))
    dz_roof, dz_snow = t / cos_t, s / cos_t
    for sg in (1, -1):
        # roof slab: underside from the eave (y=+-2.9, z=3.0) to the ridge (y=0, z=4.6)
        prof = [Vector((-3.4, 0.0, 4.6)), Vector((-3.4, sg * 2.9, 3.0)), Vector((-3.4, sg * 2.9, 3.0 + dz_roof)),
                Vector((-3.4, 0.0, 4.6 + dz_roof))]
        mb.prism(prof, (-3.4, 0, 0), (3.4, 0, 0), "roof")
        # snow slab 0.12 thick on top, inset from the gable edges and the eave so the dark roof frames it
        zt0, zt1 = 4.6 + dz_roof, 3.0 + dz_roof
        ye = sg * 2.62
        ze = zt1 + slope * (2.9 - 2.62)
        prof = [Vector((-3.22, 0.0, zt0)), Vector((-3.22, ye, ze)), Vector((-3.22, ye, ze + dz_snow)),
                Vector((-3.22, 0.0, zt0 + dz_snow))]
        mb.prism(prof, (-3.22, 0, 0), (3.22, 0, 0), "snow")
        # bargeboards (cabin_trim) under the roof edges at both gable ends
        for x0, x1 in ((-3.42, -3.36), (3.36, 3.42)):
            a0 = Vector((x0, sg * 2.9, 3.0 - 0.10))
            a1 = Vector((x0, 0.0, 4.6 - 0.10))
            corners = []
            for i in range(8):
                xx = x1 if i & 1 else x0
                far = bool(i & 2)
                up = bool(i & 4)
                y = 0.0 if far else sg * 2.94       # not coplanar with the slab's eave face
                z = (4.6 if far else 3.0) + (dz_roof + 0.02 if up else -0.10)
                corners.append((xx, y, z))
            mb.hexa(corners, "cabin_trim")
    # gable triangles at x = +-3.0 (cabin_wall) closing the roof above z = 3.0
    zu = slope_z(2.5, 2.9, 3.0, 0.0, 4.6)
    for x0, x1 in ((-3.0, -3.0 + T), (3.0 - T, 3.0)):
        prof = [Vector((x0, -2.5, ZE)), Vector((x0, 2.5, ZE)), Vector((x0, 2.5, zu)), Vector((x0, 0.0, 4.6)),
                Vector((x0, -2.5, zu))]
        mb.prism(prof, (x0, 0, 0), (x1, 0, 0), "cabin_wall")
    # attic vent on each gable (dark louvre)
    for x, sg in ((-3.0, -1), (3.0, 1)):
        mb.prism([Vector((x, -0.35, 3.55)), Vector((x, 0.35, 3.55)), Vector((x, 0.0, 3.95))],
                 (x, 0, 0), (x + sg * 0.03, 0, 0), "wood_dark")
    # friezes closing the gap between the wall tops and the roof underside (front/back)
    for y0, y1 in ((-2.5, -2.5 + T), (2.5 - T, 2.5)):
        mb.box((-3.0, y0, ZE), (3.0, y1, zu), "cabin_wall", skip=('-z',))

    # porch roof: shed slab 0.12 thick from (y 2.5, z 3.0) to (y 4.8, z 2.5), x -3.2..3.2, snow on top
    pt = 0.12
    pslope = 0.5 / 2.3
    pcos = math.cos(math.atan(pslope))
    prof = [Vector((-3.2, 2.5, 3.0)), Vector((-3.2, 4.8, 2.5)), Vector((-3.2, 4.8, 2.5 + pt / pcos)),
            Vector((-3.2, 2.5, 3.0 + pt / pcos))]
    mb.prism(prof, (-3.2, 0, 0), (3.2, 0, 0), "roof")
    zs0, zs1 = 3.0 + pt / pcos, 2.5 + pt / pcos
    ye = 4.58
    ze = zs1 + pslope * (4.8 - ye)
    prof = [Vector((-3.0, 2.5, zs0)), Vector((-3.0, ye, ze)), Vector((-3.0, ye, ze + 0.10 / pcos)),
            Vector((-3.0, 2.5, zs0 + 0.10 / pcos))]
    mb.prism(prof, (-3.0, 0, 0), (3.0, 0, 0), "snow")
    # fascia trim along the porch roof front edge
    mb.box((-3.22, 4.8, 2.40), (3.22, 4.84, 2.5 + pt / pcos), "cabin_trim")

    def porch_underside(y):
        return 3.0 - pslope * (y - 2.5)
    for x in (-2.9, 2.9):       # support posts
        mb.box((x - 0.06, 4.34, Z0), (x + 0.06, 4.46, porch_underside(4.46)), "wood")
    # lantern chain from the porch roof down to the LanternSocket
    mb.box((-1.61, 4.29, 2.35), (-1.59, 4.31, porch_underside(4.29) + 0.01), "iron")
    return mb


def build_chimney():
    mb = lp.MeshBuilder()
    mb.box((-3.72, 0.23, 0.0), (-2.99, 0.97, Z0), "stone_dark", skip=('-z',))          # plinth
    mb.box((-3.7, 0.25, Z0), (-3.0, 0.95, 5.1), "brick", skip=('-z',))
    # a couple of protruding brick courses for texture
    for z in (1.6, 3.2, 4.4):
        mb.box((-3.72, 0.23, z), (-2.99, 0.97, z + 0.08), "brick")
    mb.box((-3.74, 0.21, 5.1), (-2.96, 0.99, 5.3), "stone_dark", mats={'+z': "snow"})   # rim, snowy top
    mb.poly([(-3.52, 0.43, 5.301), (-3.18, 0.43, 5.301), (-3.18, 0.77, 5.301), (-3.52, 0.77, 5.301)],
            "iron", facing=(0, 0, 1))                                                     # flue
    return mb


def build_porch():
    mb = lp.MeshBuilder()
    # stone skirt (z 0-0.20) and deck (z 0.20-0.30): dark underlay + plank strips along X
    mb.box((-3.0, 2.5, 0.0), (3.0, 4.5, 0.20), "stone", skip=('-z', '+z', '-y'))
    mb.box((-3.0, 2.5, 0.20), (3.0, 4.5, 0.292), "wood_dark", skip=('-z', '-y'))
    n, gap = 8, 0.014
    pw = (2.0 - (n - 1) * gap) / n
    for k in range(n):
        y0 = 2.5 + k * (pw + gap)
        mb.poly([(-3.0, y0, Z0), (3.0, y0, Z0), (3.0, y0 + pw, Z0), (-3.0, y0 + pw, Z0)], "wood", facing=(0, 0, 1))
    # steps in front of the door
    mb.box((-1.5, 4.5, 0.0), (-0.3, 4.85, 0.20), "wood", skip=('-z', '-y'))
    mb.box((-1.5, 4.85, 0.0), (-0.3, 5.2, 0.10), "wood", skip=('-z', '-y'))
    # railing (cabin_trim): posts, top rails at z 1.2, bottom rails, balusters every 0.3 m
    trim = "cabin_trim"
    posts = [(-3.0, 4.5), (3.0, 4.5), (-1.5, 4.5), (-0.3, 4.5), (-3.0, 2.5), (3.0, 2.5)]
    for x, y in posts:
        mb.box((x - 0.05, y - 0.05, Z0), (x + 0.05, y + 0.05, 1.3), trim, skip=('-z',), mats={'+z': "snow"})
    rails = [((-3.0, 4.5), (-1.5, 4.5)), ((-0.3, 4.5), (3.0, 4.5)), ((-3.0, 2.5), (-3.0, 4.5)),
             ((3.0, 2.5), (3.0, 4.5))]
    for (xa, ya), (xb, yb) in rails:
        for zc, hs in ((1.2, 0.04), (0.40, 0.025)):
            if xa == xb:
                mb.box((xa - hs, ya + 0.05, zc - hs), (xa + hs, yb - 0.05, zc + hs), trim)
            else:
                mb.box((xa + 0.05, ya - hs, zc - hs), (xb - 0.05, ya + hs, zc + hs), trim)
        length = abs(xb - xa) + abs(yb - ya)
        count = int(round(length / 0.3)) - 1
        for k in range(1, count + 1):
            t = k / (count + 1)
            x = xa + (xb - xa) * t
            y = ya + (yb - ya) * t
            mb.box((x - 0.02, y - 0.02, Z0), (x + 0.02, y + 0.02, 1.16), trim, skip=('-z', '+z'))
    return mb


def build_collision():
    boxes = {
        "ColFoundation": ((-3.0, -2.5, 0.0), (3.0, 2.5, 0.30)),
        "ColPorch": ((-3.0, 2.5, 0.0), (3.0, 4.5, 0.30)),
        "ColWallBack": ((-3.0, -2.5, 0.30), (3.0, -2.32, 3.0)),
        "ColWallLeft": ((-3.0, -2.5, 0.30), (-2.82, 2.5, 3.0)),
        "ColWallRight": ((2.82, -2.5, 0.30), (3.0, 2.5, 3.0)),
        "ColWallFrontL": ((-3.0, 2.32, 0.30), (-1.4, 2.5, 3.0)),
        "ColWallFrontR": ((-0.4, 2.32, 0.30), (3.0, 2.5, 3.0)),
        "ColDoorTop": ((-1.4, 2.32, 2.40), (-0.4, 2.5, 3.0)),
        "ColChimney": ((-3.7, 0.25, 0.0), (-3.0, 0.95, 3.0)),
        "ColRailFrontL": ((-3.0, 4.42, 0.30), (-1.5, 4.5, 1.3)),
        "ColRailFrontR": ((-0.3, 4.42, 0.30), (3.0, 4.5, 1.3)),
        "ColRailLeft": ((-3.0, 2.5, 0.30), (-2.92, 4.5, 1.3)),
        "ColRailRight": ((2.92, 2.5, 0.30), (3.0, 4.5, 1.3)),
    }
    for name, (mn, mx) in boxes.items():
        lp.collision_box(name, mn, mx)
    # ramp prism for the steps: (x, 5.3, 0), (x, 4.5, 0), (x, 4.5, 0.30) for x = -1.5, -0.3
    pts = [(-1.5, 5.3, 0.0), (-1.5, 4.5, 0.0), (-1.5, 4.5, 0.30), (-0.3, 5.3, 0.0), (-0.3, 4.5, 0.0),
           (-0.3, 4.5, 0.30)]
    faces = [(0, 1, 2), (3, 5, 4), (0, 3, 4, 1), (1, 4, 5, 2), (0, 2, 5, 3)]
    lp.collision_prism("ColSteps", pts, faces)


def build_cabin():
    lp.new_scene()
    lp.to_object(build_floor(), "Floor")
    walls, face_front, face_left = build_walls()
    lp.to_object(walls["WallBack"], "WallBack")
    wl = lp.to_object(walls["WallLeft"], "WallLeft")
    lp.to_object(window(WallFace('x', -3.0, -1), -1.9, -0.7), "WindowsLeft", parent=wl)
    lp.to_object(walls["WallRight"], "WallRight")
    wf = lp.to_object(walls["WallFront"], "WallFront")
    lp.to_object(window(WallFace('y', 2.5, 1), 0.8, 2.0), "WindowsFront", parent=wf)
    lp.to_object(build_roof(), "Roof")
    lp.to_object(build_chimney(), "Chimney")
    lp.to_object(build_porch(), "Porch")
    lp.add_empty("DoorAnchor", (-0.9, 3.2, 0.30))
    lp.add_empty("LanternSocket", (-1.6, 4.3, 2.35))
    build_collision()
    export.save_and_export("cabin")


def main():
    build_cabin()


if __name__ == "__main__":
    main()
