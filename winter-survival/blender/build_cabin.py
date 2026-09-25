"""cabin (slice ASSET_SPEC §4.15; ASSET_SPEC_V2 §17; HD v2.1 in milestone G1): the hunter's house, replaced in
M6a by the kit template house_hunter.

    cd winter-survival/blender && python3 build_cabin.py

G1 (docs/research/05_graficos_arte.md §1.1/§4, port of the approved look-dev cabin_hd) with the M0 contract kept
exactly: top-level cutaway parts Floor, WallBack, WallLeft (+ child WindowsLeft), WallRight, WallFront (+ child
WindowsFront), Roof, Chimney, Porch; empties DoorAnchor (-0.9, 3.2, 0.30 slice = 0.9, -3.2 final) and LanternSocket;
the same 14 Col*-convcolonly boxes (+ ColSteps prism). Authored in the slice convention (porch toward +Y) and
turned 180 degrees at creation (new_scene(authored_front="+Y")): the exported cabin faces -Y (MODEL_FRONT).
Surfaces: 8 palette_vcol (one per part) + 2 `window` panes = 10 (<= 12).

Look (v2.1): lap siding 0.20 m + cream corner boards, frieze and skirt; windows with 2x3 mullions, deep frame,
drip cap and a sill carrying a rounded snow line; interior wainscot; open door leaf. Roof: battens (standing
seams), cream rake/fascia, ridge cap, THICK rounded snow slabs (subdivided pillows, 0.22 m, cornice drooping over
the eave) covering 60-80 % of the slopes so the dark roof shows, loose lumps. Porch: entry cross-gable with an open
cream truss, posts with knee braces, deck boards, dense balusters, rail caps with snow lines. Chimney: stone base,
brick stack with courses, pillowed snow cap. Snow drifts against the outer walls live in `Floor` (never hidden by
the cutaway). Hard parts chamfered (1.2-2 cm, hardened normals), all snow smooth, AO baked in COLOR_0.a.
Differences from the look-dev cabin_hd: no window on WallRight (the contract has WindowsFront / WindowsLeft only,
cabin.gd lights those two) and no ColPostL/ColPostR (the rail boxes already cover the gable posts).
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402,F401  (must precede mathutils)
from mathutils import Vector  # noqa: E402

from lib import export  # noqa: E402
from lib import hd as H  # noqa: E402
from lib import lowpoly as lp  # noqa: E402

T = 0.18                  # wall thickness
Z0, ZE = 0.30, 3.0        # floor top / eave
RIDGE = 4.6
SLOPE = 1.6 / 2.9         # main roof rise / run
TRIM = "cabin_trim"
WALL = "cabin_wall"


class Face:
    """Wall-local (u along the face, z, d = outward offset) -> world (slice convention)."""

    def __init__(self, axis, plane, sign):
        self.axis, self.plane, self.sign = axis, plane, sign

    def p(self, u, z, d=0.0):
        if self.axis == 'y':
            return Vector((u, self.plane + self.sign * d, z))
        return Vector((self.plane + self.sign * d, u, z))

    @property
    def n(self):
        return Vector((0, self.sign, 0)) if self.axis == 'y' else Vector((self.sign, 0, 0))

    @property
    def udir(self):
        return Vector((1, 0, 0)) if self.axis == 'y' else Vector((0, 1, 0))


def fbox(mb, f, u0, u1, z0, z1, d0, d1, mat):
    a, b = f.p(u0, z0, d0), f.p(u1, z1, d1)
    return mb.box((min(a.x, b.x), min(a.y, b.y), z0), (max(a.x, b.x), max(a.y, b.y), z1), mat)


def fwedge(mb, f, u0, u1, z0, z1, d_bot, d_top, mat):
    """Lap board: protrudes d_bot at its lower edge, d_top at its upper edge (back at d = 0)."""
    cs = []
    for i in range(8):
        u = u1 if i & 1 else u0
        out = bool(i & 2)
        up = bool(i & 4)
        d = (d_top if up else d_bot) if out else 0.0
        cs.append(f.p(u, z1 if up else z0, d))
    return mb.hexa(cs, mat)


def lap_siding(mb, f, u0, u1, holes, z0=Z0 + 0.14, z1=ZE - 0.12, step=0.20):
    z = z0
    while z < z1 - 1e-6:
        zl, zh = z, min(z + step, z1)
        cuts = sorted((h[0], h[1]) for h in holes if h[2] < zh - 1e-6 and h[3] > zl + 1e-6)
        segs, cur = [], u0
        for a, b in cuts:
            if a > cur:
                segs.append((cur, min(a, u1)))
            cur = max(cur, b)
        if cur < u1:
            segs.append((cur, u1))
        for a, b in segs:
            if b - a > 0.04:
                fwedge(mb, f, a, b, zl, zh, 0.032, 0.006, WALL)
        z = zh


def window(face, u0, u1, z0, z1, trim_mb, snow_objs, seed):
    """Frame + 2x3 mullions + sill + drip cap (into trim_mb), rounded snow on sill and cap (snow_objs),
    returns (pane MeshBuilder, siding hole)."""
    f = face
    w, d = 0.09, 0.07
    fbox(trim_mb, f, u0 - w, u0, z0 - w, z1 + w, 0, d, TRIM)
    fbox(trim_mb, f, u1, u1 + w, z0 - w, z1 + w, 0, d, TRIM)
    fbox(trim_mb, f, u0, u1, z1, z1 + w, 0, d, TRIM)
    fbox(trim_mb, f, u0, u1, z0 - w, z0, 0, d, TRIM)
    um = (u0 + u1) / 2
    fbox(trim_mb, f, um - 0.02, um + 0.02, z0, z1, 0, 0.045, TRIM)
    for k in (1, 2):
        zm = z0 + (z1 - z0) * k / 3
        fbox(trim_mb, f, u0, u1, zm - 0.017, zm + 0.017, 0, 0.045, TRIM)
    # sill (projects 0.13) and drip cap (projects 0.10)
    s0, s1 = u0 - w - 0.06, u1 + w + 0.06
    fbox(trim_mb, f, s0, s1, z0 - w - 0.07, z0 - w, 0, 0.13, TRIM)
    fbox(trim_mb, f, u0 - w - 0.04, u1 + w + 0.04, z1 + w, z1 + w + 0.06, 0, 0.10, TRIM)
    snow_objs.append(H.snow_strip(f.p(s0 + 0.02, z0 - w, 0.07), f.p(s1 - 0.02, z0 - w, 0.07), 0.12, 0.07,
                                  seed=seed, overhang=0.0))
    snow_objs.append(H.snow_strip(f.p(u0 - w - 0.02, z1 + w + 0.06, 0.055), f.p(u1 + w + 0.02, z1 + w + 0.06, 0.055),
                                  0.09, 0.045, seed=seed + 1, overhang=0.0))
    pane = lp.MeshBuilder()
    pane.poly([f.p(u0, z0, 0.006), f.p(u1, z0, 0.006), f.p(u1, z1, 0.006), f.p(u0, z1, 0.006)], "window", facing=f.n)
    hole = (u0 - w - 0.07, u1 + w + 0.07, z0 - w - 0.08, z1 + w + 0.07)
    return pane, hole


def corner_boards(mb, f, us, z0=Z0, z1=ZE - 0.005):
    for (a, b) in us:
        fbox(mb, f, a, b, z0, z1, 0, 0.04, TRIM)


def base_bands(mb, f, u0, u1):
    """Skirt board (cream) at the bottom and frieze board under the eave."""
    fbox(mb, f, u0, u1, Z0 - 0.02, Z0 + 0.14, 0, 0.035, TRIM)
    fbox(mb, f, u0, u1, ZE - 0.12, ZE - 0.005, 0, 0.03, TRIM)


def wall_slab(mb, mn, mx, inner):
    mb.box(mn, mx, WALL, mats={inner: "wood"})


def wainscot(mb, axis, plane, sign, u0, u1):
    """Interior wainscot: dark lower panel + cap rail on the inner face (sign = toward the room)."""
    f = Face(axis, plane, sign)
    fbox(mb, f, u0, u1, Z0, 1.0, 0, 0.02, "wood_dark")
    fbox(mb, f, u0, u1, 1.0, 1.05, 0, 0.04, "wood_light")


# ------------------------------------------------------------------------------------------------------------
def build_walls():
    out = {}
    # ---------------- back (y = -2.5) ----------------
    slab, hard, snow = lp.MeshBuilder(), lp.MeshBuilder(), []
    wall_slab(slab, (-3.0, -2.5, Z0), (3.0, -2.5 + T, ZE), '+y')
    fb = Face('y', -2.5, -1)
    lap_siding(slab, fb, -2.9, 2.9, [])
    corner_boards(hard, fb, [(-3.04, -2.86), (2.86, 3.04)])
    base_bands(hard, fb, -2.86, 2.86)
    wainscot(slab, 'y', -2.5 + T, 1, -2.82, 2.82)
    out["WallBack"] = (slab, hard, snow, [])
    # ---------------- left (x = -3.0): window + chimney ----------------
    slab, hard, snow = lp.MeshBuilder(), lp.MeshBuilder(), []
    wall_slab(slab, (-3.0, -2.5, Z0), (-3.0 + T, 2.5, ZE), '+x')
    fl = Face('x', -3.0, -1)
    pane, hole = window(fl, -1.9, -0.7, 1.25, 2.30, hard, snow, 11)
    lap_siding(slab, fl, -2.46, 2.46, [hole, (0.20, 1.00, 0.0, 9.0)])
    corner_boards(hard, fl, [(-2.54, -2.36), (2.36, 2.54)])
    base_bands(hard, fl, -2.36, 0.2)
    base_bands(hard, fl, 1.0, 2.36)
    wainscot(slab, 'x', -3.0 + T, 1, -2.32, 2.32)
    out["WallLeft"] = (slab, hard, snow, [("WindowsLeft", pane)])
    # ---------------- right (x = +3.0) ----------------
    slab, hard, snow = lp.MeshBuilder(), lp.MeshBuilder(), []
    wall_slab(slab, (3.0 - T, -2.5, Z0), (3.0, 2.5, ZE), '-x')
    fr = Face('x', 3.0, 1)
    lap_siding(slab, fr, -2.46, 2.46, [])
    corner_boards(hard, fr, [(-2.54, -2.36), (2.36, 2.54)])
    base_bands(hard, fr, -2.36, 2.36)
    wainscot(slab, 'x', 3.0 - T, -1, -2.32, 2.32)
    out["WallRight"] = (slab, hard, snow, [])
    # ---------------- front (y = +2.5): door + big window ----------------
    slab, hard, snow = lp.MeshBuilder(), lp.MeshBuilder(), []
    y0, y1 = 2.5 - T, 2.5
    wall_slab(slab, (-3.0, y0, Z0), (-1.4, y1, ZE), '-y')
    wall_slab(slab, (-0.4, y0, Z0), (3.0, y1, ZE), '-y')
    wall_slab(slab, (-1.4, y0, 2.40), (-0.4, y1, ZE), '-y')
    ff = Face('y', 2.5, 1)
    pane_f, hole_f = window(ff, 0.55, 2.15, 1.20, 2.30, hard, snow, 31)
    lap_siding(slab, ff, -2.9, 2.9, [(-1.56, -0.24, 0.0, 2.60), hole_f])
    # door casing (0.12) + head casing + jamb linings
    fbox(hard, ff, -1.52, -1.4, Z0, 2.52, 0, 0.05, TRIM)
    fbox(hard, ff, -0.4, -0.28, Z0, 2.52, 0, 0.05, TRIM)
    fbox(hard, ff, -1.56, -0.24, 2.52, 2.60, 0, 0.08, TRIM)
    slab.box((-1.4, y0 - 0.01, Z0), (-1.38, y1, 2.40), TRIM)
    slab.box((-0.42, y0 - 0.01, Z0), (-0.4, y1, 2.40), TRIM)
    slab.box((-1.4, y0 - 0.01, 2.38), (-1.38 + 0.98, y1, 2.40), TRIM)
    corner_boards(hard, ff, [(-3.04, -2.86), (2.86, 3.04)])
    base_bands(hard, ff, -2.86, -1.52)
    base_bands(hard, ff, -0.28, 2.86)
    wainscot(slab, 'y', y0, -1, -2.82, -1.42)
    wainscot(slab, 'y', y0, -1, -0.38, 2.82)
    # open door leaf, swung ~95 deg into the room against the inner wall (hinge at x -1.38)
    leaf = lp.MeshBuilder()
    leaf.box((-1.38, y0 - 0.96, Z0 + 0.01), (-1.33, y0 - 0.02, 2.36), "wood_dark")
    for z0_, z1_ in ((0.45, 1.25), (1.40, 2.20)):
        leaf.box((-1.39, y0 - 0.86, z0_), (-1.38, y0 - 0.12, z1_), "wood")
        leaf.box((-1.33, y0 - 0.86, z0_), (-1.32, y0 - 0.12, z1_), "wood")
    leaf.box((-1.31, y0 - 0.85, 1.12), (-1.29, y0 - 0.80, 1.20), "iron")
    out["WallFront"] = (slab, hard, snow, [("WindowsFront", pane_f)], leaf)
    return out


# ------------------------------------------------------------------------------------------------------------
def z_roof_under(y):
    """Main roof underside height at |y| (eave y 2.9 z 3.0, ridge y 0 z 4.6)."""
    return ZE + SLOPE * (2.9 - abs(y))


ROOF_T = 0.16
COS = math.cos(math.atan(SLOPE))
DZ_ROOF = ROOF_T / COS
GX, GH, GPITCH = -0.9, 1.45, math.radians(40)       # entry gable: centre x, half span, pitch
G_EAVE = 2.62
G_RIDGE = G_EAVE + GH * math.tan(GPITCH)
G_T = 0.12
G_FRONT, G_BACK = 4.85, 1.45


def z_top(y):
    return z_roof_under(y) + DZ_ROOF


def build_roof(rnd):
    hard, flatp, snow = lp.MeshBuilder(), lp.MeshBuilder(), []
    for sg in (1, -1):
        prof = [Vector((-3.4, 0.0, RIDGE)), Vector((-3.4, sg * 2.9, ZE)), Vector((-3.4, sg * 2.9, ZE + DZ_ROOF)),
                Vector((-3.4, 0.0, RIDGE + DZ_ROOF))]
        hard.prism(prof, (-3.4, 0, 0), (3.4, 0, 0), "roof")
        # battens (standing seams) every 0.4 m, 3 x 2.5 cm
        n = Vector((0, sg * SLOPE, 1)).normalized()
        for k in range(17):
            x = -3.2 + k * 0.4
            a = Vector((x, sg * 2.88, ZE + DZ_ROOF))
            b = Vector((x, sg * 0.04, RIDGE + DZ_ROOF))
            cs = []
            for i in range(8):
                base = b if i & 2 else a
                cs.append(base + Vector((0.015 if i & 1 else -0.015, 0, 0)) + (n * 0.025 if i & 4 else Vector()))
            flatp.hexa(cs, "roof_seam")
        # fascia (cream) along the eave and rake boards along both gable edges
        hard.box((-3.44, sg * 2.9 - (0.0 if sg > 0 else 0.05), ZE - 0.12),
                 (3.44, sg * 2.9 + (0.05 if sg > 0 else 0.0), ZE + DZ_ROOF + 0.02), TRIM)
        for x0, x1 in ((-3.46, -3.38), (3.38, 3.46)):
            cs = []
            for i in range(8):
                xx = x1 if i & 1 else x0
                far = bool(i & 2)
                up = bool(i & 4)
                y = 0.0 if far else sg * 2.95
                z = (RIDGE if far else ZE) + (DZ_ROOF + 0.03 if up else -0.14)
                cs.append((xx, y, z))
            hard.hexa(cs, TRIM)
    # ridge cap
    hard.prism([Vector((-3.42, -0.14, RIDGE + DZ_ROOF - 0.02)), Vector((-3.42, 0.14, RIDGE + DZ_ROOF - 0.02)),
                Vector((-3.42, 0.0, RIDGE + DZ_ROOF + 0.07))], (-3.42, 0, 0), (3.42, 0, 0), "roof_seam")
    # gable walls with board-and-batten, eave band and a louvred vent
    zu = z_roof_under(2.5)
    for x0, x1, sgn in ((-3.0, -3.0 + T, -1), (3.0 - T, 3.0, 1)):
        prof = [Vector((x0, -2.5, ZE)), Vector((x0, 2.5, ZE)), Vector((x0, 2.5, zu)), Vector((x0, 0.0, RIDGE)),
                Vector((x0, -2.5, zu))]
        flatp.prism(prof, (x0, 0, 0), (x1, 0, 0), WALL)
        xo = x0 if sgn < 0 else x1
        for k in range(-7, 8):
            y = k * 0.32
            ztop = z_roof_under(y) - 0.02
            if ztop - ZE < 0.12 or abs(y) > 2.4:
                continue
            a, b = sorted((xo, xo + sgn * 0.03))
            flatp.box((a, y - 0.025, ZE + 0.1), (b, y + 0.025, ztop), WALL)
        a, b = sorted((xo, xo + sgn * 0.05))
        hard.box((a, -2.56, ZE - 0.02), (b, 2.56, ZE + 0.12), TRIM)
        # vent (dark louvre in a cream frame)
        a2, b2 = sorted((xo, xo + sgn * 0.04))
        hard.prism([Vector((a2, -0.42, 3.50)), Vector((a2, 0.42, 3.50)), Vector((a2, 0.0, 3.98))],
                   (a2, 0, 0), (b2, 0, 0), TRIM)
        a3, b3 = sorted((xo + sgn * 0.04, xo + sgn * 0.05))
        flatp.prism([Vector((a3, -0.32, 3.56)), Vector((a3, 0.32, 3.56)), Vector((a3, 0.0, 3.90))],
                    (a3, 0, 0), (b3, 0, 0), "wood_dark")
    for y0, y1 in ((-2.5, -2.5 + T), (2.5 - T, 2.5)):
        flatp.box((-3.0, y0, ZE), (3.0, y1, zu), WALL, skip=('-z',))

    # ---------------- entry cross-gable over the door ----------------
    tg = math.tan(GPITCH)
    dzg = G_T / math.cos(GPITCH)
    for sx in (1, -1):
        e = Vector((GX + sx * (GH + 0.17), G_BACK, G_RIDGE - (GH + 0.17) * tg))
        r = Vector((GX, G_BACK, G_RIDGE))
        prof = [r, e, e + Vector((0, 0, dzg)), r + Vector((0, 0, dzg))]
        hard.prism(prof, (0, G_BACK, 0), (0, G_FRONT, 0), "roof")
        # rake board under the front edge
        cs = []
        for i in range(8):
            base = e if i & 1 else r
            yy = G_FRONT + (0.05 if i & 2 else -0.03)
            zz = base.z + (dzg + 0.02 if i & 4 else -0.15)
            cs.append((base.x, yy, zz))
        hard.hexa(cs, TRIM)
    # truss in the gable end (set back 0.25 from the front edge)
    yt = G_FRONT - 0.25
    xl, xr = GX - GH + 0.08, GX + GH - 0.08
    H.beam(hard, (xl - 0.1, yt, G_EAVE - 0.09), (xr + 0.1, yt, G_EAVE - 0.09), 0.12, 0.18, TRIM)      # tie beam
    H.beam(hard, (GX, yt, G_EAVE), (GX, yt, G_RIDGE - 0.08), 0.12, 0.10, TRIM, up=(1, 0, 0))              # king post
    for sx in (1, -1):
        H.beam(hard, (GX + sx * 0.05, yt, G_EAVE + 0.35), (GX + sx * 0.78, yt, G_RIDGE - 0.78 * tg - 0.12),
               0.10, 0.08, TRIM, up=(0, 1, 0))                                                           # struts
        H.beam(hard, (GX + sx * (GH + 0.05), yt, G_EAVE - 0.02), (GX, yt, G_RIDGE - 0.06), 0.12, 0.10, TRIM,
               up=(0, 1, 0))                                                                             # rafter
    # side plates (wall -> front) and posts with knee braces
    for x in (xl, xr):
        H.beam(hard, (x, 2.5, G_EAVE - 0.09), (x, yt + 0.1, G_EAVE - 0.09), 0.14, 0.16, TRIM)
        H.beam(hard, (x, 4.40, Z0), (x, 4.40, G_EAVE - 0.18), 0.16, 0.16, TRIM, up=(0, 1, 0))
        hard.box((x - 0.12, 4.28, Z0), (x + 0.12, 4.52, Z0 + 0.10), TRIM)                              # base
        inward = 1 if x < GX else -1
        H.beam(hard, (x, 4.40, G_EAVE - 0.72), (x + inward * 0.52, yt, G_EAVE - 0.16), 0.08, 0.08, TRIM,
               up=(0, 1, 0))
        H.beam(hard, (x, 4.32, G_EAVE - 0.72), (x, 3.78, G_EAVE - 0.16), 0.08, 0.08, TRIM, up=(1, 0, 0))
    # ceiling boards under the gable (so the underside is not see-through)
    flatp.box((xl, 2.5, G_EAVE + 0.06), (xr, yt, G_EAVE + 0.08), "wood")
    # lantern chain down to LanternSocket (-1.6, 4.3, 2.35)
    under = G_RIDGE - abs(-1.6 - GX) * tg
    flatp.box((-1.61, 4.29, 2.35), (-1.59, 4.31, under), "iron")

    # ---------------- snow ----------------
    # main roof, front slope (sg=+1) right of the cross gable, back slope (sg=-1) almost full
    for sg, x0, x1, cover in ((1, 0.78, 3.32, 1.95), (-1, -3.32, 3.32, 2.35)):
        slope_len = 2.9 / COS
        V = Vector((0, -sg, SLOPE)).normalized()                 # up-slope
        N = Vector((0, sg * SLOPE, 1)).normalized()
        E = Vector((x0, sg * 2.9, ZE + DZ_ROOF))                  # eave top edge
        over = 0.14
        origin = E - V * over
        size_v = over + min(cover, slope_len)
        seed = 5 if sg > 0 else 9

        def lip(u, v, over=over, size_v=size_v, seed=seed):
            dn = -0.11 * H.smoothstep(over + 0.10, 0.0, v)        # cornice droops over the eave
            dv = 0.0
            if v >= size_v - 1e-6:                                 # wavy upper edge
                dv = 0.35 * H.fbm(u * 0.7, seed * 1.3, 2, seed)
            return (0.0, dv, dn)
        o = H.pillow(origin, Vector((1, 0, 0)), V, N, x1 - x0, size_v, 0.22, nu=7, nv=4, rim=0.16, seed=seed,
                     lip=lip, bumps=0.04)
        snow.append(o)
    # lumps on the bare upper band / left of the gable
    lumps = [(-2.2, 0.55, 0.9, 0.55), (-3.0, 1.9, 0.62, 0.5), (1.5, 0.45, 0.7, 0.45), (2.7, 0.8, 0.55, 0.4),
             (-1.0, -0.5, 0.8, 0.5), (-0.9, 0.85, 0.75, 0.45), (0.35, 1.05, 0.55, 0.4)]
    for k, (x, y, lu, lv) in enumerate(lumps):
        sg = 1 if y > 0 else -1
        V = Vector((0, -sg, SLOPE)).normalized()
        N = Vector((0, sg * SLOPE, 1)).normalized()
        base = Vector((x, y, z_top(y)))
        snow.append(H.pillow(base - Vector((lu / 2, 0, 0)) - V * (lv / 2), Vector((1, 0, 0)), V, N, lu, lv,
                             0.13 + 0.03 * rnd.random(), nu=4, nv=4, rim=0.12, seed=40 + k, jitter=0.03, levels=1))
    # cross gable: one pillow per slope, meeting in a rounded crest over the ridge
    for sx in (1, -1):
        V = Vector((-sx * math.cos(GPITCH), 0, math.sin(GPITCH)))
        N = Vector((sx * math.sin(GPITCH), 0, math.cos(GPITCH)))
        e = Vector((GX + sx * (GH + 0.17), G_FRONT + 0.06, G_RIDGE - (GH + 0.17) * tg + dzg))
        over = 0.10
        size_v = over + (GH + 0.17) / math.cos(GPITCH) + 0.06
        size_u = G_FRONT + 0.06 - 1.55

        def lip(u, v, over=over, size_u=size_u):
            dn = -0.09 * H.smoothstep(over + 0.08, 0.0, v)
            dn += -0.05 * H.smoothstep(0.12, 0.0, u)               # droop over the front edge
            return (0.0, 0.0, dn)
        o = H.pillow(e - V * over, Vector((0, -1, 0)), V, N, size_u, size_v, 0.20, nu=5, nv=4, rim=0.14,
                     seed=60 + sx, lip=lip, bumps=0.03)
        snow.append(o)
    return hard, flatp, snow


# ------------------------------------------------------------------------------------------------------------
def build_chimney():
    hard, flatp, snow = lp.MeshBuilder(), lp.MeshBuilder(), []
    x0, x1, y0, y1 = -3.70, -3.00, 0.25, 0.95
    # stone base: 4 courses of 3 big stones on the two visible faces + plinth
    rnd = random.Random(3)
    hard.box((x0 - 0.06, y0 - 0.06, 0.0), (x1 + 0.01, y1 + 0.06, 0.12), "stone_dark")
    z = 0.12
    for row in range(4):
        hgt = 0.26
        # three stones along y on the -x face, two along x on the +/-y faces
        ys = [y0 - 0.04, y0 + 0.20 + rnd.uniform(-0.05, 0.05), y0 + 0.47 + rnd.uniform(-0.05, 0.05), y1 + 0.04]
        for k in range(3):
            c = "stone" if (row + k) % 3 else "stone_dark"
            flatp.box((x0 - 0.04, ys[k] + 0.01, z + 0.01), (x0 + 0.25, ys[k + 1] - 0.01, z + hgt - 0.01), c)
        for yy0, yy1 in ((y0 - 0.04, y0 + 0.2), (y1 - 0.2, y1 + 0.04)):
            xs = [x0 + 0.24, x0 + 0.47 + rnd.uniform(-0.04, 0.04), x1]
            for k in range(2):
                c = "stone_dark" if (row + k) % 2 else "stone"
                flatp.box((xs[k] + 0.01, yy0, z + 0.01), (xs[k + 1] - 0.01, yy1, z + hgt - 0.01), c)
        z += hgt
    # brick stack with courses and a few proud bricks
    flatp.box((x0, y0, z), (x1, y1, 5.10), "brick")
    zz = z + 0.34
    while zz < 5.0:
        hard.box((x0 - 0.018, y0 - 0.018, zz), (x1 + 0.005, y1 + 0.018, zz + 0.05), "brick")
        zz += 0.36
    for k in range(10):
        zb = z + 0.2 + k * 0.33 + rnd.uniform(-0.05, 0.05)
        if zb > 4.9:
            break
        face = k % 3
        if face == 0:
            yb = rnd.uniform(y0 + 0.1, y1 - 0.3)
            hard.box((x0 - 0.02, yb, zb), (x0 + 0.02, yb + 0.22, zb + 0.08), "stone_dark" if k % 4 == 0 else "brick")
        else:
            xb = rnd.uniform(x0 + 0.08, x1 - 0.3)
            yy = y0 if face == 1 else y1
            hard.box((xb, yy - 0.02, zb), (xb + 0.22, yy + 0.02, zb + 0.08), "brick")
    # cap slab + flue
    hard.box((x0 - 0.07, y0 - 0.07, 5.10), (x1 + 0.07, y1 + 0.07, 5.24), "stone_dark")
    H.tube(flatp, [(-3.35, 0.60, 5.2), (-3.35, 0.60, 5.52)], [0.11, 0.10], 8, "iron", cap_end=True)
    flatp.cylinder((-3.35, 0.60, 5.50), (-3.35, 0.60, 5.55), 0.14, 0.14, 8, "iron")
    # snow cap: a rounded pillow ring made of two lumps around the flue
    snow.append(H.pillow((x0 - 0.08, y0 - 0.08, 5.24), (1, 0, 0), (0, 1, 0), (0, 0, 1), 0.86, 0.30, 0.12, nu=5,
                         nv=3, rim=0.08, seed=71))
    snow.append(H.pillow((x0 - 0.08, 0.70, 5.24), (1, 0, 0), (0, 1, 0), (0, 0, 1), 0.86, 0.33, 0.10, nu=5, nv=3,
                         rim=0.08, seed=72))
    return hard, flatp, snow


# ------------------------------------------------------------------------------------------------------------
def build_porch(rnd):
    hard, flatp, snow = lp.MeshBuilder(), lp.MeshBuilder(), []
    # skirt: dark vertical boards, rim joist
    flatp.box((-3.0, 2.5, 0.0), (3.0, 4.46, 0.20), "wood_dark", skip=('-z', '-y'))
    for k in range(40):
        x = -2.97 + k * 0.15
        if x > 2.97:
            break
        flatp.box((x, 4.46, 0.0), (x + 0.11, 4.49, 0.19), "wood_dark")
    for k in range(13):
        y = 2.55 + k * 0.15
        for xs in (-1, 1):
            a, b = sorted((xs * 3.0, xs * 3.03))
            flatp.box((a, y, 0.0), (b, y + 0.11, 0.19), "wood_dark")
    hard.box((-3.03, 2.5, 0.19), (3.03, 4.52, 0.27), "wood")                 # rim joist / deck frame
    # deck boards along X with gaps
    n, gap = 8, 0.02
    pw = (1.96 - (n - 1) * gap) / n
    for k in range(n):
        y0 = 2.52 + k * (pw + gap)
        hard.box((-2.99, y0, 0.26), (2.99, y0 + pw, Z0), "wood")
    # steps (two treads on stringers)
    for (y0, y1, z1) in ((4.52, 4.86, 0.20), (4.86, 5.20, 0.10)):
        hard.box((-1.5, y0, z1 - 0.05), (-0.3, y1, z1), "wood")
        hard.box((-1.5, y0, 0.0), (-0.3, y1 - 0.02, z1 - 0.05), "wood_dark")
    # railing: posts with caps, top + bottom rails, dense balusters; snow lines on rails and caps
    posts = [(-3.0, 4.46), (3.0, 4.46), (-1.52, 4.46), (-0.28, 4.46), (-3.0, 2.54), (3.0, 2.54), (1.4, 4.46)]
    for x, y in posts:
        hard.box((x - 0.055, y - 0.055, Z0), (x + 0.055, y + 0.055, 1.18), TRIM)
        hard.box((x - 0.075, y - 0.075, 1.18), (x + 0.075, y + 0.075, 1.24), TRIM)
        snow.append(H.pillow((x - 0.085, y - 0.085, 1.24), (1, 0, 0), (0, 1, 0), (0, 0, 1), 0.17, 0.17, 0.07,
                             nu=3, nv=3, rim=0.05, seed=int(100 + x * 10 + y)))
    rails = [((-3.0, 4.46), (-1.52, 4.46)), ((-0.28, 4.46), (1.4, 4.46)), ((1.4, 4.46), (3.0, 4.46)),
             ((-3.0, 2.54), (-3.0, 4.46)), ((3.0, 2.54), (3.0, 4.46))]
    for (xa, ya), (xb, yb) in rails:
        horiz = abs(yb - ya) < 1e-6
        for zc, hs, ws in ((1.10, 0.035, 0.05), (0.42, 0.025, 0.035)):
            if horiz:
                hard.box((xa + 0.055, ya - ws, zc - hs), (xb - 0.055, ya + ws, zc + hs), TRIM)
            else:
                hard.box((xa - ws, ya + 0.055, zc - hs), (xa + ws, yb - 0.055, zc + hs), TRIM)
        a = Vector((xa, ya, 1.10 + 0.035)) + (Vector((0.06, 0, 0)) if horiz else Vector((0, 0.06, 0)))
        b = Vector((xb, yb, 1.10 + 0.035)) - (Vector((0.06, 0, 0)) if horiz else Vector((0, 0.06, 0)))
        snow.append(H.snow_strip(a, b, 0.09, 0.055, seed=int(abs(xa * 7 + ya * 3)), overhang=0.0))
        length = abs(xb - xa) + abs(yb - ya)
        count = int(round(length / 0.15)) - 1
        for k in range(1, count + 1):
            t = k / (count + 1)
            x = xa + (xb - xa) * t
            y = ya + (yb - ya) * t
            flatp.box((x - 0.022, y - 0.022, 0.445), (x + 0.022, y + 0.022, 1.065), TRIM, skip=('-z', '+z'))
    # snow on the uncovered deck (left of the gable posts and right of them), swept strip at the door
    snow.append(H.pillow((0.68, 2.56, Z0), (1, 0, 0), (0, 1, 0), (0, 0, 1), 2.26, 1.86, 0.11, nu=7, nv=5, rim=0.16,
                         seed=81, bumps=0.03, jitter=0.05, levels=1))
    snow.append(H.pillow((-2.94, 2.56, Z0), (1, 0, 0), (0, 1, 0), (0, 0, 1), 0.52, 1.86, 0.10, nu=3, nv=5,
                         rim=0.12, seed=82, jitter=0.03))
    # snow piles against the skirt on both sides of the steps
    for x0, w in ((-2.95, 1.35), (-0.2, 3.1)):
        def top(u, v, w=w):
            return 0.30 * max(0.0, 1.0 - v / 0.75) ** 0.8 + 0.04
        snow.append(H.pillow((x0, 4.40, 0.0), (1, 0, 0), (0, 1, 0), (0, 0, 1), w, 0.75, 0.30, nu=6, nv=4, rim=0.2, levels=1,
                             seed=90 + int(x0), top_fn=top, jitter=0.04))
    return hard, flatp, snow


def build_floor():
    hard, flatp, snow = lp.MeshBuilder(), lp.MeshBuilder(), []
    # foundation skirt (stone, mostly buried by drifts) + dark lower course
    hard.box((-3.02, -2.52, 0.0), (3.02, 2.52, Z0 - 0.02), "stone", skip=('-z',))
    ix, iy = 2.82, 2.32
    flatp.poly([(-ix, -iy, 0.292), (ix, -iy, 0.292), (ix, iy, 0.292), (-ix, iy, 0.292)], "wood_dark",
               facing=(0, 0, 1))
    n, gap = 14, 0.012
    pw = (2 * ix - (n - 1) * gap) / n
    for k in range(n):
        x0 = -ix + k * (pw + gap)
        flatp.box((x0, -iy, 0.28), (x0 + pw, iy, Z0), "wood_light" if k % 3 else "wood", skip=('-z',))
    flatp.box((-1.4, 2.30, Z0), (-0.4, 2.52, Z0 + 0.02), "wood_dark", skip=('-z',))
    # drifts piled against the outer walls (wedge profile, highest at the wall)
    specs = [  # origin, U, V (away from wall), length, depth, height
        ((-3.3, -2.45, 0.0), (1, 0, 0), (0, -1, 0), 6.6, 1.05, 0.62),     # back wall
        ((3.0 - 0.05, -2.7, 0.0), (0, 1, 0), (1, 0, 0), 5.3, 0.95, 0.55),  # right wall (slice x+)
        ((-3.0 + 0.05, 2.6, 0.0), (0, -1, 0), (-1, 0, 0), 1.6, 0.80, 0.45),  # left wall, front of chimney
        ((-3.0 + 0.05, -0.1, 0.0), (0, -1, 0), (-1, 0, 0), 2.7, 0.85, 0.50),  # left wall, behind chimney
    ]
    for k, (o, U, V, L, D, Hh) in enumerate(specs):
        def top(u, v, D=D, Hh=Hh, k=k, L=L):
            t = max(0.0, 1.0 - v / D)
            end = min(1.0, min(u, L - u) / 0.6)
            return 0.03 + Hh * (t ** 0.75) * (0.55 + 0.45 * end) * (1 + 0.15 * H.fbm(u * 0.8, k, 2, k))
        snow.append(H.pillow(Vector(o) - Vector(V) * 0.12, U, V, (0, 0, 1), L, D + 0.12, Hh, nu=9, nv=4,
                             rim=0.25, seed=120 + k, top_fn=top, jitter=0.05, bottom=-0.05, levels=1))
    return hard, flatp, snow


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
    pts = [(-1.5, 5.3, 0.0), (-1.5, 4.5, 0.0), (-1.5, 4.5, 0.30), (-0.3, 5.3, 0.0), (-0.3, 4.5, 0.0),
           (-0.3, 4.5, 0.30)]
    faces = [(0, 1, 2), (3, 5, 4), (0, 3, 4, 1), (1, 4, 5, 2), (0, 2, 5, 3)]
    lp.collision_prism("ColSteps", pts, faces)


def assemble(name, hard, flatp, snow, bevel_w=0.014, extra=None, parent=None):
    parts = []
    if hard is not None and hard.faces:
        o = H.mk(hard)
        H.bevel(o, bevel_w, 1, angle=30)
        H.snap_colors(o)
        parts.append(o)
    if flatp is not None and flatp.faces:
        parts.append(H.flat(H.mk(flatp)))
    for mbx in (extra or []):
        o = H.mk(mbx)
        H.bevel(o, 0.01, 1, angle=30)
        H.snap_colors(o)
        parts.append(o)
    parts += snow
    return H.join(parts, name, parent)


def build_cabin():
    lp.new_scene(authored_front="+Y")
    rnd = random.Random(7)
    assemble("Floor", *build_floor())
    walls = build_walls()
    for wname, spec in walls.items():
        slab, hard, snow, panes = spec[0], spec[1], spec[2], spec[3]
        extra = [spec[4]] if len(spec) > 4 else None
        w = assemble(wname, hard, slab, snow, extra=extra)
        for pname, pmb in panes:
            H.flat(H.mk(pmb, pname, parent=w))
    assemble("Roof", *build_roof(rnd), bevel_w=0.018)
    assemble("Chimney", *build_chimney(), bevel_w=0.02)
    assemble("Porch", *build_porch(rnd), bevel_w=0.012)
    lp.add_empty("DoorAnchor", (-0.9, 3.2, 0.30))
    lp.add_empty("LanternSocket", (-1.6, 4.3, 2.35))
    build_collision()
    # AO: Col* boxes are hidden from the bake; 1.2 m reach (buildings, doc 05 §4.6)
    export.save_and_export("cabin", ao=dict(distance=1.2, samples=96, ground=True))


def main():
    build_cabin()


if __name__ == "__main__":
    main()
