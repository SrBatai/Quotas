"""Modular building kit (ASSET_SPEC_V2 §8; started in M3, completed in M6a). Guide v2.1 (doc 05 §2.1 "molduras
modulares", §4.3 snow recipes) on the 2 m grid / 3 m storeys of decision C8.

    kit.build(template_dict, style_name)      # into the current (empty) scene -> building objects, ready to export

Grid and sizes (§8.1): horizontal grid 2 m; storey 3.0 m (wall 2.8 + slab 0.2); foundation 0.3 (floor 0 top at
+0.3); exterior walls 0.2 centred on the grid line, partitions 0.12; door 1.0 x 2.2, window 1.2 x 1.2 with the sill
at 0.9; roof: gable 35 deg with a snow slab; stub walls 0.6 m.

Template (JSON, blender/kits/templates/<id>.json; the code-side copy is data/buildings/templates/<id>.json):
    footprint [W, D] (metres, multiples of 2; x = W, y = D; front = S = -Y), floors (1 in M3),
    doors / windows: [{"pos": [i, j], "dir": "S|N|E|W", ...}] = the wall on side `dir` of cell (i, j) (cell (0, 0)
        = the south-west cell); door: "kind" door|double|garage, "exterior" bool; windows: "boarded" bool;
    partitions: [{"axis": "x", "at": j, "from": i0, "to": i1, "doors": [i, ...]}] = an interior wall along the grid
        line y = j (axis "x": runs along X from cell i0 to i1 inclusive; axis "y": along the line x = i);
    roof: {"kind": "gable", "ridge": "y", "pitch": 35, "overhang": 0.4};
    porch: {"cells": [[i, -1], ...]}  (cells in front of the S facade), chimney: {"pos": [i, j]};
    furniture (decorative, merged into Interior0): [{"kind": "counter|table|shelf", "pos": [x, y], "yaw": deg}];
    spawns: [{"kind": "Container|Bed|Stove|Light|Zombie|Furniture|Loot|Workbench|Radio", "pos": [x, y(, z)],
              "yaw": deg, "table": ..., "furniture": ...}]   (pos in metres from the SW corner of the footprint).

Modules (per style; they are NOT exported alone: every module writes into the group builder of its cut group, and
the groups are fused at the end -> one mesh per cut group, §8.4):
    Wall_2, Wall_Window_2, Wall_Door_2 (+ their `_Stub` 0.6 m versions), Corner_Out, Floor_2x2, Foundation_Skirt_2,
    Roof_Gable_2, Roof_Gable_End, Porch_2x2, Porch_Roof_2, Stair_Porch, Chimney, IWall_2, IWall_Door_2.
Styles: `wood_blue` (lap siding cabin_wall, cream trims, standing-seam roof) and `brick` (brick courses, concrete
lintels / sills / plinth, quoins, tiled roof). Still to do for M6a: concrete / sheet_metal styles, Wall_1,
Wall_DoubleDoor_2, Wall_Shop_4, Wall_Garage_4, Wall_Broken_2, Wall_Boarded_2, Corner_In, Post, stairs and upper
floors (Floor_Stair_Opening_2x6, Stair_2x6), hip / flat roofs, Parapet_2, Awning_4, Shutter, Planks.

Exported structure (§8.4): Floor0, Walls0_{N,S,E,W} (+ `_Stub`), Interior0, Roof, Door_<n> (hinge pivot, closed),
Window_<n> (pane, material `window`, both faces), Spawn_<Kind>_<n> (empties, yaw only), Col*-convcolonly (walls
split around the openings: doors AND windows stay open, the code adds boxes on Door_n / Window_n), all top level.
Custom props (glTF extras): every group `cut_group` + `floor`; Floor<k> `floor_z`; Door_n `kind`, `exterior`,
`cut_group`, `floor`, `hinge` ("L"/"R" seen from outside), `width`; Window_n `boarded`, `cut_group`, `floor`;
Spawn_* `table` / `furniture` / `kind`. Corners belong to the S / N facades (§8.6).
"""
import math
import random

import bpy  # noqa: F401  (must precede mathutils)
from mathutils import Vector

from . import hd as H
from . import lowpoly as lp

GRID = 2.0
STOREY = 3.0
WALL_H = 2.8
SLAB = 0.2
FOUND = 0.3
WALL_T = 0.2
T2 = WALL_T / 2
IWALL_T = 0.12
DOOR_W, DOOR_H = 1.0, 2.2
WIN_W, WIN_H, SILL = 1.2, 1.2, 0.9
STUB_H = 0.6

MODULES = ("Wall_2", "Wall_Window_2", "Wall_Door_2", "Wall_2_Stub", "Wall_Window_2_Stub", "Wall_Door_2_Stub",
           "Corner_Out", "Floor_2x2", "Foundation_Skirt_2", "Roof_Gable_2", "Roof_Gable_End", "Porch_2x2",
           "Porch_Roof_2", "Stair_Porch", "Chimney", "IWall_2", "IWall_Door_2")


class Style:
    def __init__(self, name, **kw):
        self.name = name
        self.__dict__.update(kw)


STYLES = {
    "wood_blue": Style("wood_blue", finish="lap", wall="cabin_wall", trim="cabin_trim", interior="wood_light",
                       wainscot="wood", found="stone", found_top="stone_dark", roof="roof", seam="roof_seam",
                       roof_pattern="seams", fascia="cabin_trim", door="wood_dark", door_panel="wood",
                       frame="cabin_trim", floor="wood", floor_seam="wood_dark", chimney="brick",
                       chimney_band="stone_dark", gable="lap", porch="wood", post="cabin_trim"),
    "brick": Style("brick", finish="brick", wall="brick", trim="concrete", interior="plaster", wainscot="wood",
                   found="concrete_dark", found_top="concrete", roof="roof", seam="roof_seam", roof_pattern="tiles",
                   fascia="wood_dark", door="paint_red", door_panel="brick_dark", frame="paint_white",
                   floor="wood_light", floor_seam="wood", chimney="brick_dark", chimney_band="concrete",
                   gable="brick", porch="wood_dark", post="paint_white", course="brick_dark"),
}


# ------------------------------------------------------------------------------------------------------------
# geometry context
# ------------------------------------------------------------------------------------------------------------
class Group:
    """Builders of one cut group: `hard` (chamfered), `flat` (flat, no chamfer), `snow` (smooth objects)."""

    def __init__(self, name, floor=0):
        self.name = name
        self.floor = floor
        self.hard = lp.MeshBuilder()
        self.flat = lp.MeshBuilder()
        self.snow = []
        self.smooth = []


class Facade:
    """Exterior facade `d` of storey k. u runs along +X (S/N) or +Y (E/W); `p(u, z, d)` = point at `d` metres
    OUTSIDE the outer face (negative = into the wall)."""

    def __init__(self, d, W, D, k=0):
        self.d, self.k = d, k
        hw, hd = W / 2.0, D / 2.0
        if d in "SN":
            self.axis, self.sign = "x", (-1 if d == "S" else 1)
            self.line = self.sign * hd
            self.u0, self.u1 = -hw - T2, hw + T2
            self.cells = [(-hw + GRID * i, -hw + GRID * (i + 1)) for i in range(int(round(W / GRID)))]
        else:
            self.axis, self.sign = "y", (1 if d == "E" else -1)
            self.line = self.sign * hw
            self.u0, self.u1 = -hd + T2, hd - T2
            self.cells = [(max(-hd + GRID * j, -hd + T2), min(-hd + GRID * (j + 1), hd - T2))
                          for j in range(int(round(D / GRID)))]
        self.z0 = FOUND + k * STOREY
        self.zt = self.z0 + WALL_H

    @property
    def n(self):
        return Vector((0, self.sign, 0)) if self.axis == "x" else Vector((self.sign, 0, 0))

    @property
    def udir(self):
        return Vector((1, 0, 0)) if self.axis == "x" else Vector((0, 1, 0))

    @property
    def out_key(self):
        return ("+y" if self.sign > 0 else "-y") if self.axis == "x" else ("+x" if self.sign > 0 else "-x")

    @property
    def in_key(self):
        k = self.out_key
        return ("-" if k[0] == "+" else "+") + k[1]

    def p(self, u, z, d=0.0):
        w = self.line + self.sign * (T2 + d)
        return Vector((u, w, z)) if self.axis == "x" else Vector((w, u, z))

    def box(self, mb, u0, u1, z0, z1, d0, d1, mat, mats=None, skip=()):
        a, b = self.p(u0, z0, d0), self.p(u1, z1, d1)
        return mb.box((min(a.x, b.x), min(a.y, b.y), min(z0, z1)), (max(a.x, b.x), max(a.y, b.y), max(z0, z1)), mat,
                      mats=mats, skip=skip)

    def wedge(self, mb, u0, u1, z0, z1, d_bot, d_top, mat):
        """Lap board: proud d_bot at its lower edge, d_top at its upper edge (back at d = 0)."""
        cs = []
        for i in range(8):
            u = u1 if i & 1 else u0
            out = bool(i & 2)
            up = bool(i & 4)
            d = (d_top if up else d_bot) if out else 0.0
            cs.append(self.p(u, z1 if up else z0, d))
        return mb.hexa(cs, mat)

    def rect(self, u0, u1, z0, z1, d):
        return [self.p(u0, z0, d), self.p(u1, z0, d), self.p(u1, z1, d), self.p(u0, z1, d)]


def opening_of(kind, a, b, z0):
    """(u0, u1, z0, z1) of the hole of a module spanning [a, b] (centred)."""
    c = (a + b) / 2
    if kind == "window":
        return (c - WIN_W / 2, c + WIN_W / 2, z0 + SILL, z0 + SILL + WIN_H)
    if kind == "door":
        return (c - DOOR_W / 2, c + DOOR_W / 2, z0, z0 + DOOR_H)
    return None


def slab_boxes(fac, mb, a, b, z0, z1, hole, style, t=WALL_T):
    """Wall slab over [a, b] x [z0, z1] minus `hole`, outer face `style.wall`, inner face `style.interior`."""
    mats = {fac.out_key: style.wall, fac.in_key: style.interior}
    pieces = []
    if hole is None:
        pieces.append((a, b, z0, z1))
    else:
        ha, hb, hz0, hz1 = hole
        pieces += [(a, ha, z0, z1), (hb, b, z0, z1)]
        if hz0 > z0 + 1e-6:
            pieces.append((ha, hb, z0, min(hz0, z1)))
        if hz1 < z1 - 1e-6:
            pieces.append((ha, hb, hz1, z1))
    for (u0, u1, zz0, zz1) in pieces:
        if u1 - u0 > 1e-4 and zz1 - zz0 > 1e-4:
            fac.box(mb, u0, u1, zz0, zz1, -t, 0.0, style.wall, mats=mats)
    return pieces


# ------------------------------------------------------------------------------------------------------------
# exterior finishes (per module span)
# ------------------------------------------------------------------------------------------------------------
def _spans(a, b, cuts):
    segs, cur = [], a
    for ca, cb in sorted(cuts):
        if ca > cur:
            segs.append((cur, min(ca, b)))
        cur = max(cur, cb)
    if cur < b:
        segs.append((cur, b))
    return segs


def lap_sheet(fac, mb, a, b, z0, z1, holes, mat, step=0.20, d_bot=0.030, d_top=0.006):
    """Lap siding as a saw-tooth SHEET: one sloped quad per course and span (2 tris; the board lips face down and
    are never seen from the game camera). Courses are cut around `holes` (u0, u1, z0, z1)."""
    z = z0
    while z < z1 - 1e-6:
        zl, zh = z, min(z + step, z1)
        for sa, sb in _spans(a, b, [(h[0], h[1]) for h in holes if h[2] < zh - 1e-6 and h[3] > zl + 1e-6]):
            if sb - sa > 0.04:
                mb.poly([fac.p(sa, zl, d_bot), fac.p(sb, zl, d_bot), fac.p(sb, zh, d_top), fac.p(sa, zh, d_top)], mat,
                        facing=fac.n + Vector((0, 0, 0.1)))
        z = zh


def brick_courses(fac, mb, a, b, z0, z1, holes, style, rnd, step=0.30):
    """Course lines (brick_dark flat strips 2.4 cm, 3 mm proud) every 0.30 m + a few proud single bricks."""
    z = z0 + step
    while z < z1 - 0.05:
        for sa, sb in _spans(a, b, [(h[0], h[1]) for h in holes if h[2] < z + 0.03 and h[3] > z]):
            if sb - sa > 0.05:
                mb.poly(fac.rect(sa, sb, z - 0.012, z + 0.012, 0.003), style.course, facing=fac.n)
        z += step
    for _ in range(int((b - a) * 1.5)):
        u = rnd.uniform(a + 0.1, b - 0.35)
        zz = rnd.uniform(z0 + 0.1, z1 - 0.2)
        if any(h[0] - 0.3 < u < h[1] and h[2] - 0.12 < zz < h[3] + 0.1 for h in holes):
            continue
        fac.box(mb, u, u + 0.24, zz, zz + 0.075, 0.0, 0.012, style.course if rnd.random() < 0.6 else style.wall,
                skip=(fac.in_key, "-z"))


def finish(fac, g, a, b, z0, z1, holes, style, rnd, stub=False):
    """Exterior finish of one module span (siding sheet / brick courses). Skirt, frieze, plinth and soldier course
    run along the whole facade (facade_bands)."""
    if style.finish == "lap":
        lap_sheet(fac, g.flat, a, b, z0 + 0.16, z1 - (0.0 if stub else 0.12), holes, style.wall)
    else:
        brick_courses(fac, g.flat, a, b, z0 + 0.45, z1 - (0.0 if stub else 0.16), holes, style, rnd)


def facade_bands(fac, g, style, door_holes, stub=False):
    """Skirt (wood) / plinth (brick) along the whole facade (cut at the doors) + frieze / soldier course on top."""
    zt = fac.z0 + (STUB_H if stub else WALL_H)
    spans = _spans(fac.u0, fac.u1, [(h[0] - 0.12, h[1] + 0.12) for h in door_holes])
    if style.finish == "lap":
        for sa, sb in spans:
            fac.box(g.hard, sa, sb, fac.z0 - 0.02, fac.z0 + 0.16, 0.0, 0.035, style.trim, skip=(fac.in_key,))
        if not stub:
            fac.box(g.hard, fac.u0, fac.u1, zt - 0.12, zt, 0.0, 0.03, style.trim, skip=(fac.in_key,))
    else:
        for sa, sb in _spans(fac.u0, fac.u1, [(h[0], h[1]) for h in door_holes]):
            fac.box(g.hard, sa, sb, fac.z0 - 0.02, fac.z0 + 0.45, 0.0, 0.03, style.found_top, skip=(fac.in_key,))
        if not stub:
            fac.box(g.flat, fac.u0, fac.u1, zt - 0.16, zt, 0.0, 0.018, style.course, skip=(fac.in_key, "-z"))


def stub_cap(fac, g, a, b, z, style, hole=None):
    """Cap board on top of a stub wall (visible from above in the cutaway)."""
    spans = [(a, b)] if hole is None or hole[2] > z else [(a, hole[0]), (hole[1], b)]
    for sa, sb in spans:
        if sb - sa > 0.02:
            fac.box(g.hard, sa, sb, z, z + 0.04, -WALL_T - 0.015, 0.03, style.trim)


def window_trim(fac, g, hole, style, seed, pane_list, cut_group, floor):
    u0, u1, z0, z1 = hole
    w, d = 0.09, 0.07
    t, f = g.hard, g.flat
    sk = (fac.in_key,)
    if style.finish == "lap":
        fac.box(f, u0 - w, u0, z0 - w, z1 + w, 0, d, style.frame, skip=sk)
        fac.box(f, u1, u1 + w, z0 - w, z1 + w, 0, d, style.frame, skip=sk)
        fac.box(f, u0, u1, z1, z1 + w, 0, d, style.frame, skip=sk)
        fac.box(t, u0 - w - 0.06, u1 + w + 0.06, z0 - w - 0.06, z0 - w + 0.0, 0, 0.13, style.frame)   # sill
        fac.box(t, u0 - w - 0.04, u1 + w + 0.04, z1 + w, z1 + w + 0.06, 0, 0.10, style.frame)          # drip cap
        sill = (u0 - w - 0.04, u1 + w + 0.04, z0 - w, 0.07)
        cap = (u0 - w - 0.02, u1 + w + 0.02, z1 + w + 0.06, 0.055)
    else:
        fac.box(t, u0 - 0.10, u1 + 0.10, z1, z1 + 0.18, 0, 0.03, style.trim)                  # lintel
        fac.box(t, u0 - 0.08, u1 + 0.08, z0 - 0.07, z0, 0, 0.12, style.trim)                  # stone sill
        sill = (u0 - 0.06, u1 + 0.06, z0, 0.065)
        cap = None
    # sash frame + 2 x 2 mullions set back in the reveal (closed: seen from inside too)
    um, zm = (u0 + u1) / 2, (z0 + z1) / 2
    for (a_, b_, c_, e_) in ((u0, u1, z0, z0 + 0.05), (u0, u1, z1 - 0.05, z1), (u0, u0 + 0.05, z0, z1),
                             (u1 - 0.05, u1, z0, z1), (um - 0.02, um + 0.02, z0, z1), (u0, u1, zm - 0.02, zm + 0.02)):
        fac.box(f, a_, b_, c_, e_, -0.08, -0.035, style.frame)
    su0, su1, sz, sd = sill
    g.snow.append(H.snow_ridge(fac.p(su0 + 0.02, sz, sd), fac.p(su1 - 0.02, sz, sd), 0.11, 0.06, seed=seed,
                               overhang=0.0, droop=0.02))
    if cap:
        cu0, cu1, cz, cd = cap
        g.snow.append(H.snow_ridge(fac.p(cu0, cz, cd), fac.p(cu1, cz, cd), 0.09, 0.045, seed=seed + 1,
                                   overhang=0.0, droop=0.015))
    # pane (both faces, material window) -> Window_n
    pane = lp.MeshBuilder()
    pane.poly(fac.rect(u0 + 0.05, u1 - 0.05, z0 + 0.05, z1 - 0.05, -0.058), "window", facing=fac.n)
    pane.poly(fac.rect(u0 + 0.05, u1 - 0.05, z0 + 0.05, z1 - 0.05, -0.062), "window", facing=-fac.n)
    pane_list.append((pane, cut_group, floor))


def door_trim(fac, g, hole, style, seed, exterior=True):
    u0, u1, z0, z1 = hole
    t = g.hard
    if style.finish == "lap":
        fac.box(g.flat, u0 - 0.12, u0, z0, z1 + 0.10, 0, 0.05, style.frame, skip=(fac.in_key,))
        fac.box(g.flat, u1, u1 + 0.12, z0, z1 + 0.10, 0, 0.05, style.frame, skip=(fac.in_key,))
        fac.box(t, u0 - 0.16, u1 + 0.16, z1 + 0.10, z1 + 0.18, 0, 0.08, style.frame)
        g.snow.append(H.snow_ridge(fac.p(u0 - 0.14, z1 + 0.18, 0.045), fac.p(u1 + 0.14, z1 + 0.18, 0.045), 0.08,
                                   0.04, seed=seed, overhang=0.0, droop=0.012))
    else:
        fac.box(t, u0 - 0.12, u1 + 0.12, z1, z1 + 0.20, 0, 0.03, style.trim)
        fac.box(t, u0 - 0.10, u0, z0, z1, 0, 0.02, style.frame)
        fac.box(t, u1, u1 + 0.10, z0, z1, 0, 0.02, style.frame)
    # threshold + jamb linings
    fac.box(g.flat, u0, u1, z0 - 0.02, z0 + 0.02, -WALL_T, 0.06, style.trim if style.finish == "brick" else "wood")
    fac.box(g.flat, u0, u0 + 0.02, z0, z1, -WALL_T, 0.0, style.frame)
    fac.box(g.flat, u1 - 0.02, u1, z0, z1, -WALL_T, 0.0, style.frame)
    fac.box(g.flat, u0, u1, z1 - 0.02, z1, -WALL_T, 0.0, style.frame)


def door_leaf(fac, hole, style, name, exterior, cut_group, floor, hinge="L"):
    """Closed door leaf `Door_<n>` with its origin on the hinge axis (inner side of the opening)."""
    u0, u1, z0, z1 = hole
    mb, fl = lp.MeshBuilder(), lp.MeshBuilder()
    d0, d1 = -WALL_T + 0.05, -WALL_T + 0.10                   # set in the inner half of the reveal
    fac.box(mb, u0 + 0.02, u1 - 0.02, z0 + 0.01, z1 - 0.01, d0, d1, style.door)
    for pz0, pz1 in ((z0 + 0.2, z0 + 0.95), (z0 + 1.15, z1 - 0.2)):
        fac.box(fl, u0 + 0.14, u1 - 0.14, pz0, pz1, d1, d1 + 0.012, style.door_panel)
        fac.box(fl, u0 + 0.14, u1 - 0.14, pz0, pz1, d0 - 0.012, d0, style.door_panel)
    # "L" = hinge on the left seen from OUTSIDE: right = (-n) x up; left end = u0 when right points along +u
    right = (-fac.n).cross(Vector((0, 0, 1)))
    left_is_u0 = right.dot(fac.udir) > 0
    at_u0 = left_is_u0 if hinge == "L" else not left_is_u0
    hx = u1 - 0.12 if at_u0 else u0 + 0.12
    fac.box(fl, hx - 0.02, hx + 0.02, z0 + 1.0, z0 + 1.1, d1, d1 + 0.04, "iron")
    fac.box(fl, hx - 0.02, hx + 0.02, z0 + 1.0, z0 + 1.1, d0 - 0.04, d0, "iron")
    hu = u0 + 0.02 if at_u0 else u1 - 0.02
    pivot = fac.p(hu, z0, (d0 + d1) / 2)
    o = H.mk(mb, None, pivot)
    H.bevel(o, 0.01, 1, angle=30)
    H.snap_colors(o)
    leaf = H.join([o, H.flat(H.mk(fl, None, pivot))], name)
    leaf["kind"] = "door"
    leaf["exterior"] = bool(exterior)
    leaf["cut_group"] = cut_group
    leaf["floor"] = floor
    leaf["hinge"] = hinge
    leaf["width"] = round(u1 - u0, 3)
    return leaf


# ------------------------------------------------------------------------------------------------------------
# modules
# ------------------------------------------------------------------------------------------------------------
def door_trim_stub(fac, g, hole, style, zt):
    u0, u1, z0, _ = hole
    fac.box(g.flat, u0, u1, z0 - 0.02, z0 + 0.02, -WALL_T, 0.06, style.trim if style.finish == "brick" else "wood")
    if style.finish == "lap":
        fac.box(g.flat, u0 - 0.12, u0, z0, zt, 0, 0.05, style.frame, skip=(fac.in_key,))
        fac.box(g.flat, u1, u1 + 0.12, z0, zt, 0, 0.05, style.frame, skip=(fac.in_key,))


def corner_module(ctx, fac, g, end, stub):
    """Corner_Out at the `end` (-1 = u0 side, +1 = u1 side) of an S / N facade: boards (wood) or quoins (brick) on
    BOTH faces of the corner column (they belong to the S / N group, §8.6)."""
    style = ctx.style
    z0 = fac.z0
    zt = fac.z0 + (STUB_H if stub else WALL_H)
    u_edge = fac.u0 if end < 0 else fac.u1
    side = Facade("W" if end < 0 else "E", ctx.W, ctx.D, fac.k)
    # the side face of the corner column: v along the side facade, from the corner inward
    v_edge = fac.line + fac.sign * T2
    v_in = v_edge - fac.sign * 0.24                              # covers the column (0.2) + 4 cm overlap
    if style.finish == "lap":
        fac.box(g.hard, u_edge - end * 0.18, u_edge + end * 0.04, z0 - 0.02, zt, 0, 0.04, style.trim)
        a_, b_ = sorted((v_edge + fac.sign * 0.04, v_in))
        side.box(g.hard, a_, b_, z0 - 0.02, zt, 0, 0.04, style.trim)
    else:
        z = z0 + 0.45
        k = 0
        while z < zt - 0.1:
            h = min(0.28, zt - z)
            L1, L2 = (0.36, 0.22) if k % 2 == 0 else (0.22, 0.36)
            fac.box(g.flat, u_edge - end * L1, u_edge + end * 0.0, z + 0.01, z + h - 0.01, 0, 0.02, style.course,
                    skip=(fac.in_key, "-z"))
            a_, b_ = sorted((v_edge, v_edge - fac.sign * L2))
            side.box(g.flat, a_, b_, z + 0.01, z + h - 0.01, 0, 0.02, style.course, skip=(side.in_key, "-z"))
            z += 0.3
            k += 1
        a_, b_ = sorted((v_edge, v_in))
        side.box(g.hard, a_, b_, z0 - 0.02, z0 + 0.45, 0, 0.03, style.found_top)       # plinth wraps the corner


def floor_module(ctx, g, x0, y0, z):
    """Floor_2x2: board field (one quad + board seams) of a 2 x 2 cell, top at z."""
    s = ctx.style
    g.flat.poly([(x0, y0, z), (x0 + 2, y0, z), (x0 + 2, y0 + 2, z), (x0, y0 + 2, z)], s.floor, facing=(0, 0, 1))
    for k in range(1, 5):
        x = x0 + k * 0.4
        g.flat.poly([(x - 0.008, y0, z + 0.002), (x + 0.008, y0, z + 0.002), (x + 0.008, y0 + 2, z + 0.002),
                     (x - 0.008, y0 + 2, z + 0.002)], s.floor_seam, facing=(0, 0, 1))


def foundation_module(ctx, g, fac, a, b):
    """Foundation_Skirt_2: the 0.3 m base under a facade span, a little proud of the wall (front + top faces)."""
    s = ctx.style
    fac.box(g.flat, a, b, -0.05, FOUND - 0.02, -WALL_T, 0.05, s.found, skip=("-z", fac.in_key))


def partition(ctx, g, axis, at, i0, i1, door_cells, z0, stub=False):
    """IWall_2 / IWall_Door_2 run along a grid line, with door holes; returns (spans, holes) for collision."""
    s = ctx.style
    hw, hd = ctx.W / 2, ctx.D / 2
    holes = []
    t = IWALL_T / 2
    for i in range(i0, i1 + 1):
        if axis == "x":
            a, b = -hw + GRID * i, -hw + GRID * (i + 1)
            a, b = max(a, -hw + T2), min(b, hw - T2)
        else:
            a, b = -hd + GRID * i, -hd + GRID * (i + 1)
            a, b = max(a, -hd + T2), min(b, hd - T2)
        hole = None
        if i in door_cells:
            c = (-hw if axis == "x" else -hd) + GRID * i + GRID / 2
            hole = (c - 0.45, c + 0.45, z0, z0 + 2.1)
            holes.append(hole)
        pieces = [(a, b, z0, z0 + WALL_H)] if hole is None else [
            (a, hole[0], z0, z0 + WALL_H), (hole[1], b, z0, z0 + WALL_H), (hole[0], hole[1], hole[3], z0 + WALL_H)]
        line = (-hd if axis == "x" else -hw) + GRID * at
        for (u0, u1, zz0, zz1) in pieces:
            if u1 - u0 < 1e-4:
                continue
            if axis == "x":
                g.flat.box((u0, line - t, zz0), (u1, line + t, zz1), s.interior)
            else:
                g.flat.box((line - t, u0, zz0), (line + t, u1, zz1), s.interior)
        # base board both sides
        for sg in (-1, 1):
            spans = [(a, b)] if hole is None else [(a, hole[0]), (hole[1], b)]
            for u0, u1 in spans:
                if u1 - u0 < 0.02:
                    continue
                if axis == "x":
                    mn, mx = (u0, line + sg * t, z0), (u1, line + sg * (t + 0.015), z0 + 0.1)
                else:
                    mn, mx = (line + sg * t, u0, z0), (line + sg * (t + 0.015), u1, z0 + 0.1)
                g.flat.box(tuple(min(p, q) for p, q in zip(mn, mx)), tuple(max(p, q) for p, q in zip(mn, mx)),
                           "wood_dark")
        if hole is not None:                                  # casing on both sides
            for sg in (-1, 1):
                for (u0, u1, zz0, zz1) in ((hole[0] - 0.07, hole[0], z0, hole[3] + 0.07),
                                           (hole[1], hole[1] + 0.07, z0, hole[3] + 0.07),
                                           (hole[0], hole[1], hole[3], hole[3] + 0.07)):
                    if axis == "x":
                        mn, mx = (u0, line + sg * t, zz0), (u1, line + sg * (t + 0.02), zz1)
                    else:
                        mn, mx = (line + sg * t, u0, zz0), (line + sg * (t + 0.02), u1, zz1)
                    g.hard.box(tuple(min(p, q) for p, q in zip(mn, mx)), tuple(max(p, q) for p, q in zip(mn, mx)),
                               s.frame)
    return holes


# ------------------------------------------------------------------------------------------------------------
# roof
# ------------------------------------------------------------------------------------------------------------
def gable_roof(ctx, g, pitch=35.0, over=0.4, rt=0.16):
    """Gable roof, ridge along Y. The slab and fascia run per slope (one piece each); Roof_Gable_2 = the 2 m slices
    of standing seams (wood_blue) or tile courses (brick, a saw-tooth sheet) + ridge cap; Roof_Gable_End = rake
    overhang, rake boards, gable triangle with its finish and a louvred vent. Ceiling under the eave plate (hidden
    with the roof). Snow: one continuous slab per slope from the eave (drooping cornice) up to 74-82 %, lumps in the
    bare band, a few icicle strips under the eaves."""
    s = ctx.style
    hw, hd = ctx.W / 2, ctx.D / 2
    t = math.tan(math.radians(pitch))
    ze = FOUND + ctx.floors * STOREY - SLAB                  # wall top (eave plate)
    xe = hw + T2                                             # outer wall face
    dz = rt / math.cos(math.radians(pitch))

    def z_under(x):
        return ze + (xe - abs(x)) * t
    ridge = z_under(0.0)
    y0, y1 = -hd - T2 - over, hd + T2 + over
    ctx.roof_ridge = ridge + dz
    xo = xe + over
    g.flat.box((-hw + T2, -hd + T2, ze), (hw - T2, hd - T2, ze + 0.04), s.interior, skip=("+z",))      # ceiling
    edges = [y0, -hd - T2] + [(-hd + GRID * j) for j in range(1, int(round(ctx.D / GRID)))] + [hd + T2, y1]
    slices = list(zip(edges[:-1], edges[1:]))
    for sg in (-1, 1):
        n = Vector((sg * t, 0, 1)).normalized()
        prof = [Vector((0, y0, ridge)), Vector((sg * xo, y0, z_under(xo))), Vector((sg * xo, y0, z_under(xo) + dz)),
                Vector((0, y0, ridge + dz))]
        g.hard.prism(prof, (0, y0, 0), (0, y1, 0), s.roof)
        fa = sg * xo
        a_, b_ = sorted((fa, fa + sg * 0.05))
        g.hard.box((a_, y0, z_under(xo) - 0.10), (b_, y1, z_under(xo) + dz + 0.02), s.fascia)
        for sy0, sy1 in slices:                              # Roof_Gable_2 / Roof_Gable_End slices
            if s.roof_pattern == "seams":
                yy = sy0 + 0.25
                while yy < sy1 - 0.1:
                    a = Vector((sg * (xo - 0.04), yy, z_under(xo - 0.04) + dz))
                    b = Vector((sg * 0.05, yy, ridge + dz - 0.03))
                    for side in (-1, 1):                     # triangular standing seam: two faces, 4 tris
                        g.flat.poly([a + Vector((0, side * 0.018, 0)), b + Vector((0, side * 0.018, 0)),
                                     b + n * 0.03, a + n * 0.03], s.seam, facing=Vector((0, side, 0)) + n * 0.3)
                    yy += 0.5
            else:                                            # tile courses: saw-tooth sheet, one quad per course
                x = xo - 0.02
                while x > 0.3:
                    xu = x - 0.36
                    lo = Vector((sg * x, 0, z_under(x) + dz)) + n * 0.035
                    hi = Vector((sg * max(xu, 0.08), 0, z_under(max(xu, 0.08)) + dz)) + n * 0.004
                    g.flat.poly([lo + Vector((0, sy0, 0)), lo + Vector((0, sy1, 0)), hi + Vector((0, sy1, 0)),
                                 hi + Vector((0, sy0, 0))], s.seam if int((x + sy0) * 7) % 5 == 0 else s.roof,
                                facing=n)
                    x = xu
    g.hard.prism([Vector((-0.14, y0, ridge + dz - 0.02)), Vector((0.14, y0, ridge + dz - 0.02)),
                  Vector((0.0, y0, ridge + dz + 0.07))], (0, y0, 0), (0, y1, 0), s.seam)             # ridge cap
    # gable ends (S and N)
    for sgy in (-1, 1):
        yw = sgy * (hd + T2)
        prof = [Vector((-xe, yw, ze)), Vector((xe, yw, ze)), Vector((0, yw, ridge))]
        g.flat.prism(prof, (0, yw, 0), (0, yw - sgy * WALL_T, 0), s.wall)
        fac = Facade("S" if sgy < 0 else "N", ctx.W, ctx.D, 0)
        if s.gable == "lap":
            z = ze + 0.02
            while z < ridge - 0.25:
                zz = z + 0.2
                half_l, half_h = (ridge - z) / t - 0.02, (ridge - zz) / t - 0.02
                if half_h > 0.1:
                    fac_poly(g.flat, fac, [(-half_l, z, 0.03), (half_l, z, 0.03), (half_h, zz, 0.006),
                                          (-half_h, zz, 0.006)], s.wall)
                z = zz
        else:
            z = ze + 0.3
            while z < ridge - 0.3:
                half = (ridge - z) / t - 0.05
                g.flat.poly(fac.rect(-half, half, z - 0.012, z + 0.012, 0.003), s.course, facing=fac.n)
                z += 0.3
        for sg in (-1, 1):                                   # rake boards
            cs = []
            for i in range(8):
                far = bool(i & 2)
                xx = 0.0 if far else sg * (xo + 0.02)
                zz = (ridge if far else z_under(xo + 0.02)) + (dz + 0.03 if i & 4 else -0.14)
                yy = sgy * (hd + T2 + over + (0.05 if i & 1 else -0.02))
                cs.append((xx, yy, zz))
            g.hard.hexa(cs, s.fascia)
        vz = (ze + ridge) / 2 + 0.2
        fac.box(g.hard, -0.32, 0.32, vz - 0.25, vz + 0.25, 0, 0.04, s.trim, skip=(fac.in_key,))
        for k in range(4):
            fac.box(g.flat, -0.25, 0.25, vz - 0.19 + k * 0.11, vz - 0.14 + k * 0.11, 0.04, 0.07, s.seam,
                    skip=(fac.in_key, "-z"))
    # snow
    slope_len = xo / math.cos(math.radians(pitch))
    for sg in (-1, 1):
        V = Vector((-sg * math.cos(math.radians(pitch)), 0, math.sin(math.radians(pitch))))
        N = Vector((sg * math.sin(math.radians(pitch)), 0, math.cos(math.radians(pitch))))
        E = Vector((sg * xo, y0 + 0.08, z_under(xo) + dz))
        ov = 0.14
        cover = slope_len * (0.74 if sg > 0 else 0.82)
        size_u = (y1 - y0) - 0.16
        size_v = ov + cover
        seed = ctx.seed + (5 if sg > 0 else 9)

        def lip(u, v, ov=ov, size_v=size_v, seed=seed, size_u=size_u):
            dn = -0.11 * H.smoothstep(ov + 0.10, 0.0, v)
            dn -= 0.05 * H.smoothstep(0.14, 0.0, min(u, size_u - u))
            dv = 0.0
            if v >= size_v - 1e-6:
                dv = 0.4 * H.fbm(u * 0.7, seed * 1.3, 2, seed)
            return (0.0, dv, dn)
        g.snow.append(H.pillow(E - V * ov, Vector((0, 1, 0)), V, N, size_u, size_v, 0.22, nu=max(5, int(size_u / 1.5)),
                               nv=4, rim=0.16, seed=seed, lip=lip, bumps=0.04, levels=1, bottom=-0.09))
        rnd = random.Random(seed)
        for k in range(2):
            yy = y0 + (y1 - y0) * (0.25 + 0.45 * k) + rnd.uniform(-0.4, 0.4)
            f = rnd.uniform(0.86, 0.92)
            x = xo * (1 - f)
            base = Vector((sg * x, yy, z_under(x) + dz))
            lu, lv = rnd.uniform(0.6, 0.9), rnd.uniform(0.35, 0.5)
            g.snow.append(H.pillow(base - Vector((0, lu / 2, 0)) - V * (lv / 2), Vector((0, 1, 0)), V, N, lu, lv, 0.13,
                                   nu=3, nv=3, rim=0.12, seed=seed + 20 + k, jitter=0.03, levels=1,
                                   bottom=-0.07))
    from props.build_icicles import icicle_strip
    rnd = random.Random(ctx.seed + 31)
    for sg in (-1, 1):
        x = sg * (xo + 0.03)
        z = z_under(xo) - 0.10
        ya = rnd.uniform(y0 + 0.6, y1 - 2.4)
        g.smooth += icicle_strip((x, ya, z), (x, ya + rnd.uniform(1.4, 1.9), z), seed=ctx.seed + 40 + sg,
                                 max_len=0.42, spacing=0.15, ridge=False)
    ctx.z_under = z_under
    ctx.roof_t = t
    ctx.roof_dz = dz


def fac_poly(mb, fac, pts, mat):
    """Polygon from facade-local (u, z, d) points, facing out of the facade."""
    mb.poly([fac.p(u, z, d) for u, z, d in pts], mat, facing=fac.n)


def chimney(ctx, g, x, y):
    """Chimney stack through the roof slope at (x, y): brick with courses, band, cap slab, flue, snow cap."""
    s = ctx.style
    h = 0.30
    zb = ctx.z_under(x) - 0.2
    top = max(ctx.roof_ridge + 0.5, ctx.z_under(abs(x) - h) + ctx.roof_dz + 0.9)
    g.flat.box((x - h, y - h, zb), (x + h, y + h, top), s.chimney)
    z = zb + 0.6
    while z < top - 0.3:
        g.hard.box((x - h - 0.015, y - h - 0.015, z), (x + h + 0.015, y + h + 0.015, z + 0.045), s.chimney)
        z += 0.36
    g.hard.box((x - h - 0.05, y - h - 0.05, top), (x + h + 0.05, y + h + 0.05, top + 0.12), s.chimney_band)
    H.tube(g.flat, [(x, y, top + 0.1), (x, y, top + 0.38)], [0.09, 0.08], 8, "iron", cap_end=True)
    g.snow.append(H.pillow((x - h - 0.06, y - h - 0.06, top + 0.12), (1, 0, 0), (0, 1, 0), (0, 0, 1), 2 * h + 0.12,
                           h - 0.05, 0.1, nu=4, nv=3, rim=0.07, seed=ctx.seed + 71, levels=1))
    g.snow.append(H.pillow((x - h - 0.06, y + 0.12, top + 0.12), (1, 0, 0), (0, 1, 0), (0, 0, 1), 2 * h + 0.12,
                           h - 0.06, 0.09, nu=4, nv=3, rim=0.07, seed=ctx.seed + 72, levels=1))


def porch(ctx, gf, gr, cells, door_u):
    """Porch_2x2 deck cells in front of the S facade + Stair_Porch + posts (Floor0) + Porch_Roof_2 (Roof)."""
    s = ctx.style
    hw, hd = ctx.W / 2, ctx.D / 2
    xs = [(-hw + GRID * i) for i, _j in cells]
    x0, x1 = min(xs), max(xs) + GRID
    ya, yb = -hd - T2 - GRID, -hd - T2
    gf.flat.box((x0, ya, 0.0), (x1, yb, FOUND - 0.06), "wood_dark", skip=("-z", "+y"))
    n = 9
    pw = (GRID - (n - 1) * 0.02) / n
    for k in range(n):
        y = ya + k * (pw + 0.02)
        gf.flat.box((x0 + 0.02, y, FOUND - 0.06), (x1 - 0.02, y + pw, FOUND), s.porch, skip=("-z",))
    # steps (centred on the door)
    sx0, sx1 = door_u - 0.7, door_u + 0.7
    for (y0_, y1_, z1_) in ((ya - 0.34, ya, 0.20), (ya - 0.68, ya - 0.34, 0.10)):
        gf.hard.box((sx0, y0_, z1_ - 0.05), (sx1, y1_, z1_), s.porch)
        gf.flat.box((sx0, y0_, 0.0), (sx1, y1_ - 0.02, z1_ - 0.05), "wood_dark", skip=("-z",))
    # posts at the front corners
    zr = ctx.porch_roof_low
    posts = [(x0 + 0.12, ya + 0.12), (x1 - 0.12, ya + 0.12)]
    for px, py in posts:
        gf.hard.box((px - 0.07, py - 0.07, FOUND), (px + 0.07, py + 0.07, zr - 0.02), s.post)
        gf.hard.box((px - 0.1, py - 0.1, FOUND), (px + 0.1, py + 0.1, FOUND + 0.08), s.post)
    # snow piles in front of the porch, beside the steps (radial heaps)
    from . import veg as V
    for k, (px0, px1) in enumerate(((x0 - 0.1, sx0 - 0.05), (sx1 + 0.05, x1 + 0.1))):
        if px1 - px0 > 0.3:
            gf.snow.append(V.heap(((px0 + px1) / 2, ya - 0.3, 0.0), (px1 - px0) / 2, 0.5, 0.28, seed=ctx.seed + 80 + k,
                                  sides=12, rings=3, sink=0.05, noise=0.1))
    # Porch_Roof_2: shed roof from the facade to the posts (roof group)
    zw = ctx.porch_roof_high
    dz = 0.12
    prof = [Vector((x0 - 0.25, yb + 0.02, zw)), Vector((x0 - 0.25, ya - 0.35, zr)),
            Vector((x0 - 0.25, ya - 0.35, zr + dz)), Vector((x0 - 0.25, yb + 0.02, zw + dz))]
    gr.hard.prism(prof, (x0 - 0.25, 0, 0), (x1 + 0.25, 0, 0), s.roof)
    gr.hard.box((x0 - 0.25, ya - 0.38, zr - 0.14), (x1 + 0.25, ya - 0.33, zr + dz + 0.01), s.fascia)
    gr.hard.box((x0, ya + 0.05, zr - 0.18), (x1, ya + 0.19, zr - 0.02), s.post)           # beam on the posts
    for sgx, xx in ((1, x0 - 0.25), (-1, x1 + 0.25)):
        a_, b_ = sorted((xx, xx + sgx * 0.05))
        gr.hard.hexa([(a_, yb + 0.02, zw - 0.1), (b_, yb + 0.02, zw - 0.1), (a_, ya - 0.38, zr - 0.14),
                      (b_, ya - 0.38, zr - 0.14), (a_, yb + 0.02, zw + dz + 0.02), (b_, yb + 0.02, zw + dz + 0.02),
                      (a_, ya - 0.38, zr + dz + 0.02), (b_, ya - 0.38, zr + dz + 0.02)], s.fascia)
    L = math.hypot(yb - ya + 0.37, zw - zr)
    V = Vector((0, (yb - ya + 0.37), zw - zr)).normalized()
    N = Vector((0, -V.z, V.y)).normalized()
    if N.z < 0:
        N = -N
    E = Vector((x0 - 0.27, ya - 0.35, zr + dz))

    def lip(u, v, L=L):
        return (0.0, 0.0, -0.08 * H.smoothstep(0.2, 0.0, v))
    gr.snow.append(H.pillow(E - V * 0.1, Vector((1, 0, 0)), V, N, (x1 - x0) + 0.54, L + 0.05, 0.16, nu=5, nv=4,
                            rim=0.14, seed=ctx.seed + 90, lip=lip, bumps=0.03, levels=1, bottom=-0.09))
    ctx.porch_box = ((x0, ya, 0.0), (x1, yb, FOUND))
    ctx.steps = (sx0, sx1, ya - 0.68, ya)


def drifts(ctx, g):
    """Wind drifts against the N and W walls + a small one on the E wall (Floor0: never hidden)."""
    hw, hd = ctx.W / 2, ctx.D / 2
    specs = [((-hw - 0.4, hd + T2 - 0.05, 0.0), (1, 0, 0), (0, 1, 0), ctx.W + 0.8, 1.05, 0.58),
             ((-hw - T2 + 0.05, hd + 0.2, 0.0), (0, -1, 0), (-1, 0, 0), ctx.D + 0.4, 0.95, 0.50),
             ((hw + T2 - 0.05, hd - 2.0, 0.0), (0, -1, 0), (1, 0, 0), 3.2, 0.8, 0.36)]
    for k, (o, U, V, L, D, Hh) in enumerate(specs):
        def top(u, v, D=D, Hh=Hh, k=k, L=L):
            tt = max(0.0, 1.0 - v / D)
            end = H.smoothstep(0.0, 1.1, min(u, L - u))
            return 0.02 + Hh * (tt ** 0.75) * (0.06 + 0.94 * end) * (1 + 0.15 * H.fbm(u * 0.8, k, 2, k))
        g.snow.append(H.pillow(Vector(o) - Vector(V) * 0.12, U, V, (0, 0, 1), L, D + 0.12, Hh, nu=max(5, int(L / 1.1)),
                               nv=4, rim=0.25, seed=ctx.seed + 120 + k, top_fn=top, jitter=0.05, bottom=-0.05, levels=1))


def furniture(ctx, g, kind, x, y, yaw, z0):
    """Decorative furniture merged into Interior0 (counter, table, shelf): chamfered boxes."""
    s = ctx.style
    c, sn = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))

    def P(px, py, pz):
        return Vector((x + px * c - py * sn, y + px * sn + py * c, z0 + pz))

    def box(mn, mx, mat, mb=None):
        corners = [P(mx[0] if i & 1 else mn[0], mx[1] if i & 2 else mn[1], mx[2] if i & 4 else mn[2]) for i in range(8)]
        (mb or g.hard).hexa(corners, mat)
    if kind == "counter":
        box((-1.0, -0.3, 0.0), (1.0, 0.3, 0.86), "wood")
        box((-1.02, -0.32, 0.86), (1.02, 0.32, 0.9), "concrete")
        for k in range(4):
            box((-0.95 + k * 0.5, -0.305, 0.12), (-0.55 + k * 0.5, -0.30, 0.8), "wood_light", g.flat)
    elif kind == "table":
        box((-0.6, -0.4, 0.72), (0.6, 0.4, 0.76), "wood")
        for sx in (-1, 1):
            for sy in (-1, 1):
                box((sx * 0.52 - 0.03, sy * 0.32 - 0.03, 0.0), (sx * 0.52 + 0.03, sy * 0.32 + 0.03, 0.72), "wood_dark",
                    g.flat)
        for sy in (-1, 1):
            box((-0.2, sy * 0.62 - 0.2, 0.43), (0.2, sy * 0.62 + 0.2, 0.47), "wood")
            box((-0.2, sy * 0.8 - 0.02, 0.47), (0.2, sy * 0.8 + 0.02, 0.9), "wood", g.flat)
            for sx in (-1, 1):
                box((sx * 0.17 - 0.02, sy * 0.62 - 0.17, 0.0), (sx * 0.17 + 0.02, sy * 0.62 - 0.13, 0.43), "wood_dark",
                    g.flat)
    elif kind == "shelf":
        box((-0.45, -0.15, 0.0), (0.45, 0.15, 1.6), "wood_dark")
        for k in range(4):
            box((-0.42, -0.16, 0.3 + k * 0.38), (0.42, -0.14, 0.33 + k * 0.38), "wood_light", g.flat)


# ------------------------------------------------------------------------------------------------------------
# assembly
# ------------------------------------------------------------------------------------------------------------
class Ctx:
    def __init__(self, tpl, style):
        self.tpl = tpl
        self.style = STYLES[style]
        self.W, self.D = float(tpl["footprint"][0]), float(tpl["footprint"][1])
        self.floors = int(tpl.get("floors", 1))
        self.seed = sum(ord(ch) for ch in tpl["id"] + style)
        self.rnd = random.Random(self.seed)
        self.panes = []
        self.porch_box = None
        self.steps = None
        self.porch_roof_high = FOUND + WALL_H - 0.05
        self.porch_roof_low = FOUND + 2.45


def _openings(tpl, d, k=0):
    """{cell index along the facade: (kind, spec)} for facade d."""
    out = {}
    for w in tpl.get("windows", []):
        if w["dir"] == d and w.get("floor", 0) == k:
            out[w["pos"][0] if d in "SN" else w["pos"][1]] = ("window", w)
    for dd in tpl.get("doors", []):
        if dd["dir"] == d and dd.get("floor", 0) == k:
            out[dd["pos"][0] if d in "SN" else dd["pos"][1]] = ("door", dd)
    return out


def _col_box(name, fac, u0, u1, z0, z1):
    a, b = fac.p(u0, z0, -WALL_T), fac.p(u1, z1, 0.0)
    return lp.collision_box(name, (min(a.x, b.x), min(a.y, b.y), z0), (max(a.x, b.x), max(a.y, b.y), z1))


def bake_cut_ao(distance=1.2, samples=64, ground=True):
    """AO for a building / POI with the v2 cutaway structure (M3). Pass 1: every visual mesh except the `_Stub`
    walls (they share the space of the full walls and would black them out). Pass 2: the stubs, with the full walls
    and the roof removed from the occluders (a stub is only ever seen with its wall and the roof hidden). Window
    panes get a constant 0.98 (the `window` material does not use COLOR_0; a baked reveal would read as "black")."""
    from .export import is_col
    vis = [o for o in bpy.context.scene.objects if o.type == 'MESH' and not is_col(o.name)]
    stubs = [o for o in vis if o.name.endswith("_Stub")]
    panes = [o for o in vis if o.name.startswith("Window_")]
    main = [o for o in vis if o not in stubs and o not in panes]
    H.bake_ao(main, distance=distance, samples=samples, ground=ground, exclude={o.name for o in stubs})
    hide = {o.name for o in vis if (o.name.startswith("Walls") and not o.name.endswith("_Stub")) or o.name == "Roof"}
    if stubs:
        H.bake_ao(stubs, distance=distance, samples=samples, ground=ground, exclude=hide)
    for o in panes:
        me = o.data
        col = me.color_attributes[0]
        data = [0.0] * (len(col.data) * 4)
        col.data.foreach_get("color", data)
        for i in range(3, len(data), 4):
            data[i] = 0.98
        col.data.foreach_set("color", data)
        me.update()


def _assemble(g, bevel_w=0.012, parent=None):
    parts = []
    if g.hard.faces:
        o = H.mk(g.hard)
        H.bevel(o, bevel_w, 1, angle=30)
        H.snap_colors(o)
        parts.append(o)
    if g.flat.faces:
        parts.append(H.flat(H.mk(g.flat)))
    parts += g.snow + g.smooth
    if not parts:
        return None
    o = H.join(parts, g.name, parent)
    o["cut_group"] = g.name
    o["floor"] = g.floor
    return o


def build(tpl, style_name):
    """Build template `tpl` in style `style_name` into the current scene. Returns a summary dict
    (groups, doors, windows, spawns, collision names, expected collision boxes)."""
    ctx = Ctx(tpl, style_name)
    s = ctx.style
    W, D = ctx.W, ctx.D
    hw, hd = W / 2, D / 2
    k = 0
    summary = {"groups": [], "doors": [], "windows": [], "spawns": [], "col": {}}
    floor = Group("Floor%d" % k, k)
    walls = {d: Group("Walls%d_%s" % (k, d), k) for d in "SNEW"}
    stubs = {d: Group("Walls%d_%s_Stub" % (k, d), k) for d in "SNEW"}
    interior = Group("Interior%d" % k, k)
    roof = Group("Roof", ctx.floors)
    door_specs = []
    col = {}
    # ---- facades
    for d in "SNEW":
        fac = Facade(d, W, D, k)
        ops = _openings(tpl, d, k)
        solid = []                                            # (u0, u1, hole) for collision
        for ci, (a, b) in enumerate(fac.cells):
            kind, spec = ops.get(ci, ("wall", None))
            if d in "SN":
                if ci == 0:
                    a = fac.u0
                if ci == len(fac.cells) - 1:
                    b = fac.u1
            # the opening is centred on the 2 m cell, even when the E / W end cells are clipped by the corners
            cell_c = (-hw if d in "SN" else -hd) + GRID * ci + GRID / 2
            hole = None
            if kind != "wall":
                hole = opening_of(kind, cell_c - 1.0, cell_c + 1.0, fac.z0)
            _wall(ctx, fac, walls[d], a, b, kind, hole, False, ctx.seed + 10 * ci + ord(d))
            _wall(ctx, fac, stubs[d], a, b, kind, hole, True, ctx.seed + 10 * ci + ord(d))
            foundation_module(ctx, floor, fac, a, b)
            solid.append((a, b, hole, kind))
            if kind == "door":
                door_specs.append((fac, hole, spec))
        door_holes = [h for (_a, _b, h, kd) in solid if kd == "door"]
        facade_bands(fac, walls[d], s, door_holes, stub=False)
        facade_bands(fac, stubs[d], s, door_holes, stub=True)
        if d in "SN":
            for end in (-1, 1):
                corner_module(ctx, fac, walls[d], end, False)
                corner_module(ctx, fac, stubs[d], end, True)
        # collision: merge solid runs, split at the openings
        n = 0
        run = None
        for a, b, hole, kind in solid:
            if hole is None:
                run = (run[0], b) if run else (a, b)
                continue
            if run or a < hole[0]:
                ra = run[0] if run else a
                col["ColWalls%d_%s_%d" % (k, d, n)] = (fac, ra, hole[0], fac.z0, fac.zt)
                n += 1
            if hole[2] > fac.z0 + 1e-6:
                col["ColWalls%d_%s_%d" % (k, d, n)] = (fac, hole[0], hole[1], fac.z0, hole[2])
                n += 1
            col["ColWalls%d_%s_%d" % (k, d, n)] = (fac, hole[0], hole[1], hole[3], fac.zt)
            n += 1
            run = (hole[1], b)
        if run:
            col["ColWalls%d_%s_%d" % (k, d, n)] = (fac, run[0], run[1], fac.z0, fac.zt)
    # ---- floor field + foundation
    for i in range(int(W / GRID)):
        for j in range(int(D / GRID)):
            x0 = -hw + GRID * i
            y0 = -hd + GRID * j
            floor_module(ctx, floor, x0, y0, FOUND)
    # ---- interior partitions
    icol = []
    for pi, p in enumerate(tpl.get("partitions", [])):
        holes = partition(ctx, interior, p["axis"], p["at"], p["from"], p["to"], p.get("doors", []), FOUND)
        line = (-hd if p["axis"] == "x" else -hw) + GRID * p["at"]
        a = (-hw if p["axis"] == "x" else -hd) + GRID * p["from"]
        b = (-hw if p["axis"] == "x" else -hd) + GRID * (p["to"] + 1)
        a, b = max(a, (-hw if p["axis"] == "x" else -hd) + T2), min(b, (hw if p["axis"] == "x" else hd) - T2)
        spans = []
        cur = a
        for h in sorted(holes):
            spans.append((cur, h[0], FOUND, FOUND + WALL_H))
            spans.append((h[0], h[1], h[3], FOUND + WALL_H))
            cur = h[1]
        spans.append((cur, b, FOUND, FOUND + WALL_H))
        for si, (u0, u1, z0, z1) in enumerate(spans):
            t = IWALL_T / 2
            if p["axis"] == "x":
                icol.append(("ColIWalls%d_%d_%d" % (k, pi, si), (u0, line - t, z0), (u1, line + t, z1)))
            else:
                icol.append(("ColIWalls%d_%d_%d" % (k, pi, si), (line - t, u0, z0), (line + t, u1, z1)))
        for h in holes:
            door_specs.append(("iwall", (h[0], h[1], line, p["axis"]), {"kind": "door", "exterior": False}))
    # ---- decorative furniture
    for f in tpl.get("furniture", []):
        furniture(ctx, interior, f["kind"], -hw + f["pos"][0], -hd + f["pos"][1], f.get("yaw", 0.0), FOUND)
    # ---- roof, chimney, porch, drifts
    gable_roof(ctx, roof, pitch=tpl.get("roof", {}).get("pitch", 35.0), over=tpl.get("roof", {}).get("overhang", 0.4))
    if tpl.get("chimney"):
        ci, cj = tpl["chimney"]["pos"]
        ox, oy = tpl["chimney"].get("offset", (0.0, 0.0))
        chimney(ctx, roof, -hw + GRID * ci + GRID / 2 + ox, -hd + GRID * cj + GRID / 2 + oy)
    front_door = next((spec for spec in door_specs if spec[0] != "iwall" and spec[2].get("exterior")), None)
    if tpl.get("porch"):
        du = (front_door[1][0] + front_door[1][1]) / 2 if front_door else 0.0
        porch(ctx, floor, roof, tpl["porch"]["cells"], du)
    drifts(ctx, floor)
    # ---- fuse groups
    groups = [floor] + [walls[d] for d in "SNEW"] + [stubs[d] for d in "SNEW"] + [interior, roof]
    objs = {}
    for g in groups:
        o = _assemble(g, 0.018 if g is roof else 0.012)
        if o is not None:
            objs[g.name] = o
            summary["groups"].append(g.name)
    objs[floor.name]["floor_z"] = FOUND
    # ---- windows
    for n, (pane, cut_group, fl) in enumerate(ctx.panes):
        w = H.flat(H.mk(pane, "Window_%d" % n))
        w["boarded"] = False
        w["cut_group"] = cut_group
        w["floor"] = fl
        summary["windows"].append(w.name)
    # ---- doors (exterior first)
    doors = sorted(door_specs, key=lambda sp: 0 if sp[0] != "iwall" and sp[2].get("exterior") else 1)
    for n, (fac, hole, spec) in enumerate(doors):
        name = "Door_%d" % n
        if fac == "iwall":
            h0, h1, line, axis = hole
            ifac = _IFacade(axis, line)
            leaf = door_leaf(ifac, (h0, h1, FOUND, FOUND + 2.1), s, name, False, "Interior%d" % k, k)
        else:
            leaf = door_leaf(fac, hole, s, name, spec.get("exterior", True), "Walls%d_%s" % (k, fac.d), k,
                             hinge=spec.get("hinge", "L"))
            leaf["kind"] = spec.get("kind", "door")
        summary["doors"].append(leaf.name)
    # ---- spawns
    counts = {}
    for sp in tpl.get("spawns", []):
        kind = sp["kind"]
        i = counts.get(kind, 0)
        counts[kind] = i + 1
        pos = sp["pos"]
        z = pos[2] + FOUND if len(pos) > 2 else FOUND
        e = lp.add_empty("Spawn_%s_%d" % (kind, i), (-hw + pos[0], -hd + pos[1], z),
                         rotation_deg=(0, 0, sp.get("yaw", 0.0)), size=0.3)
        for key in ("table", "furniture"):
            if key in sp:
                e[key] = sp[key]
        e["kind"] = kind
        summary["spawns"].append(e.name)
    # ---- collision
    lp.collision_box("ColFloor%d" % k, (-hw - T2, -hd - T2, 0.0), (hw + T2, hd + T2, FOUND))
    summary["col"]["ColFloor%d" % k] = ((-hw - T2, -hd - T2, 0.0), (hw + T2, hd + T2, FOUND))
    for name, (fac, u0, u1, z0, z1) in col.items():
        o = _col_box(name, fac, u0, u1, z0, z1)
        mn = [min(v.co[i] for v in o.data.vertices) for i in range(3)]
        mx = [max(v.co[i] for v in o.data.vertices) for i in range(3)]
        summary["col"][name] = (tuple(mn), tuple(mx))
    for name, mn, mx in icol:
        lp.collision_box(name, mn, mx)
        summary["col"][name] = (tuple(mn), tuple(mx))
    if ctx.porch_box:
        mn, mx = ctx.porch_box
        lp.collision_box("ColPorch", mn, mx)
        summary["col"]["ColPorch"] = (mn, mx)
        sx0, sx1, sy0, sy1 = ctx.steps
        pts = [(sx0, sy0, 0.0), (sx0, sy1, 0.0), (sx0, sy1, FOUND), (sx1, sy0, 0.0), (sx1, sy1, 0.0),
               (sx1, sy1, FOUND)]
        lp.collision_prism("ColSteps", pts, [(0, 1, 2), (3, 5, 4), (0, 3, 4, 1), (1, 4, 5, 2), (0, 2, 5, 3)])
        summary["col"]["ColSteps"] = ((sx0, sy0, 0.0), (sx1, sy1, FOUND))
    summary["roof_ridge"] = ctx.roof_ridge
    return summary


class _IFacade(Facade):
    """Partition 'facade' used to place an interior door leaf: door_leaf() puts the leaf 0.10-0.15 m inside the
    outer face, so the fake outer face sits 0.125 m from the partition line -> the leaf is centred in the partition."""

    def __init__(self, axis, line):
        self.d, self.k = "I", 0
        self.axis = axis
        self.sign = 1
        self.line = line + 0.125 - T2
        self.z0 = FOUND
        self.zt = FOUND + WALL_H


def _wall(ctx, fac, g, a, b, kind, hole, stub, seed):
    """One wall module (Wall_2 / Wall_Window_2 / Wall_Door_2, or the _Stub version) over [a, b]."""
    s = ctx.style
    z0 = fac.z0
    zt = z0 + (STUB_H if stub else WALL_H)
    cut = hole if (hole is not None and hole[2] < zt) else None
    slab_boxes(fac, g.flat, a, b, z0, zt, cut, s)
    holes = []
    if cut is not None:
        m = 0.12 if kind == "door" else (0.1 if s.finish == "lap" else 0.12)
        holes = [(cut[0] - m, cut[1] + m, cut[2] - (0.25 if kind == "window" else 0.0), min(zt, cut[3] + 0.2))]
    finish(fac, g, a, b, z0, zt, holes, s, ctx.rnd, stub=stub)
    if stub:
        stub_cap(fac, g, a, b, zt, s, cut)
        if kind == "door":
            door_trim_stub(fac, g, hole, s, zt)
        return
    if kind == "window":
        window_trim(fac, g, hole, s, seed, ctx.panes, g.name, fac.k)
    elif kind == "door":
        door_trim(fac, g, hole, s, seed)
