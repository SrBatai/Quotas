"""Modular building kit (ASSET_SPEC_V2 §8; started in M3, completed in M6a: cut-ready). Guide v2.1 (doc 05 §2.1
"molduras modulares", §4.3 snow recipes) on the 2 m grid / 3 m storeys of decision C8.

    kit.build(template_dict, style_name)      # into the current (empty) scene -> building objects, ready to export

Grid and sizes (§8.1): horizontal grid 2 m; storey 3.0 m (wall 2.8 + slab 0.2); foundation 0.3 (floor 0 top at
+0.3); exterior walls 0.2 centred on the grid line, partitions 0.12; door 1.0 x 2.2, window 1.2 x 1.2 with the sill
at 0.9, shop window 3.2 x 2.2 (sill 0.35, 4 m module); stair 17 risers of 0.176 x 16 treads of 0.28 (run 4.48 m,
width 1.1, collision = ramp); roof: gable 35 deg with a snow slab, or flat with a 0.9 m parapet; stub walls 0.6 m.

Cut-ready (W0 contract, ARQ v2 §9.7 / M6a): closed volumes (walls, slabs, partitions and furniture are closed boxes;
the struct shader paints their back faces with `cap_color` where the corte urbano opens them), ONE SLAB PER FLOOR
with its top at FOUND + k * STOREY (= base + ground_h + (k - 1) * floor_h, ground_h 3.3, floor_h 3.0): Floor<k> for
k >= 1 is the 0.2 m slab of floor k (with the stair opening), the top floor's ceiling slab (top at
FOUND + floors * STOREY) belongs to `Roof`; walls with thickness; pieces without Y offset; a closed low-poly
`ShadowProxy` (walls + roof volume, no overhangs) that is the only shadow caster in game and defines the footprint.

Template (JSON, blender/kits/templates/<id>.json; the code reads the .glb, and data/buildings/templates/<id>.json
is a verbatim copy for the street / settlement code):
    footprint [W, D] (metres, multiples of 2; x = W, y = D; front = S = -Y), floors (1-3), kind (house | shop |
        apartment ...), budget (tris, all visual meshes incl. the hidden stubs);
    doors / windows / shops: [{"pos": [i, j], "dir": "S|N|E|W", "floor": k, ...}] = the wall on side `dir` of cell
        (i, j) (cell (0, 0) = the south-west cell); door: "kind" door, "exterior" bool, "hinge" L|R; windows:
        "boarded" bool; shops (Wall_Shop_4): the 4 m module of cells i and i + 1 (S / N) or j and j + 1 (E / W);
    partitions: [{"axis": "x", "at": j, "from": i0, "to": i1, "doors": [i, ...], "floor": k}] = an interior wall
        along the grid line y = j (axis "x": runs along X from cell i0 to i1 inclusive; axis "y": along x = i);
    stairs: [{"floor": k, "pos": [x, y], "dir": "N|S|E|W", "width": 1.1}] = a flight from floor k to k + 1 whose
        centre line starts at (x, y) m from the SW corner and climbs toward `dir`; floor k + 1 gets the opening;
    roof: {"kind": "gable", "ridge": "y", "pitch": 35, "overhang": 0.4} | {"kind": "flat", "parapet": 0.9};
    porch: {"cells": [[i, -1], ...]}  (cells in front of the S facade), chimney: {"pos": [i, j]};
    awnings: [{"dir": "S", "from": u0, "to": u1, "z": 2.75, "depth": 1.1, "floor": 0}] (facade metres from the
        footprint centre along the facade: +X for S / N, +Y for E / W);
    signs: [{"kind": "number|shop|name", "dir": "S", "at": u, "z": 2.1, "floor": 0, "width": w, "cap": h}] ->
        `Spawn_Sign_<n>` empties on the outer face (the code puts a sign board + composed text there);
    furniture (decorative, merged into Interior<k>): [{"kind": "...", "pos": [x, y], "yaw": deg, "floor": k}];
    spawns: [{"kind": "Container|Bed|Stove|Light|Zombie|Furniture|Loot|Workbench|Radio", "pos": [x, y(, z)],
              "yaw": deg, "floor": k, "table": ..., "furniture": ...}]   (pos in metres from the SW corner).

Modules (per style; they are NOT exported alone: every module writes into the group builder of its cut group, and
the groups are fused at the end -> one mesh per cut group, §8.4):
    Wall_2, Wall_Window_2, Wall_Door_2, Wall_Shop_4 (+ their `_Stub` 0.6 m versions), Corner_Out, Floor_2x2,
    Floor_Slab (+ Floor_Stair_Opening), Foundation_Skirt_2, Roof_Gable_2, Roof_Gable_End, Roof_Slab, Roof_Flat_2x2,
    Parapet_2, Porch_2x2, Porch_Roof_2, Stair_Porch, Stair_2x6, Balustrade, Awning_4, Chimney, IWall_2, IWall_Door_2,
    decorative furniture (counter, table, shelf, kitchen, sofa, rug, wardrobe, bookshelf, dresser, tv, shop_shelf,
    shop_counter, desk_block, crates).
Styles: `wood_blue` (lap siding cabin_wall, cream trims, standing-seam roof), `brick` (brick courses, concrete
lintels / sills / plinth, quoins, tiled roof) and `concrete` (M6a: precast panels with joints, dark trims).

Exported structure (§8.4): Floor<k>, Walls<k>_{N,S,E,W} (+ `_Stub`), Interior<k>, Roof, ShadowProxy, Door_<n>
(hinge pivot, closed), Window_<n> (pane, material `window`, both faces), Spawn_<Kind>_<n> (empties, yaw only),
Col*-convcolonly (walls split around the openings: doors AND windows stay open, the code adds boxes on Door_n /
Window_n; slabs split around the stair openings; stairs as ramps), all top level.
Custom props (glTF extras): every group `cut_group` + `floor`; Floor<k> `floor_z`; Door_n `kind`, `exterior`,
`cut_group`, `floor`, `hinge` ("L"/"R" seen from outside), `width`; Window_n `boarded`, `cut_group`, `floor`;
Spawn_* `table` / `furniture` / `kind` (Spawn_Sign: `sign`, `width`, `cap`, `cut_group`, `floor`); ShadowProxy
`floors`, `floor_h`, `ground_h`, `foundation`, `kind`, `enterable` (the CityBuilding root metadata).
Corners belong to the S / N facades (§8.6).
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
SHOP_W, SHOP_H, SHOP_SILL = 3.2, 2.2, 0.35
STUB_H = 0.6
RISERS = 17
RISE = STOREY / RISERS
TREAD = 0.28
RUN = (RISERS - 1) * TREAD
STAIR_W = 1.1
STAIR_HEAD = 0.9          # the slab opening starts this far up the run (2.2 m of headroom)

MODULES = ("Wall_2", "Wall_Window_2", "Wall_Door_2", "Wall_Shop_4", "Wall_2_Stub", "Wall_Window_2_Stub",
           "Wall_Door_2_Stub", "Wall_Shop_4_Stub", "Corner_Out", "Floor_2x2", "Floor_Slab", "Floor_Stair_Opening",
           "Foundation_Skirt_2", "Roof_Gable_2", "Roof_Gable_End", "Roof_Slab", "Roof_Flat_2x2", "Parapet_2",
           "Porch_2x2", "Porch_Roof_2", "Stair_Porch", "Stair_2x6", "Balustrade", "Awning_4", "Chimney", "IWall_2",
           "IWall_Door_2")


class Style:
    def __init__(self, name, **kw):
        self.name = name
        self.__dict__.update(kw)


STYLES = {
    "wood_blue": Style("wood_blue", finish="lap", wall="cabin_wall", trim="cabin_trim", interior="wood_light",
                       wainscot="wood", found="stone", found_top="stone_dark", roof="roof", seam="roof_seam",
                       roof_pattern="seams", fascia="cabin_trim", door="wood_dark", door_panel="wood",
                       frame="cabin_trim", floor="wood", floor_seam="wood_dark", chimney="brick",
                       chimney_band="stone_dark", gable="lap", porch="wood", post="cabin_trim", band="cabin_trim",
                       parapet="cabin_wall", coping="cabin_trim", course="wood_dark"),
    "brick": Style("brick", finish="brick", wall="brick", trim="concrete", interior="plaster", wainscot="wood",
                   found="concrete_dark", found_top="concrete", roof="roof", seam="roof_seam", roof_pattern="tiles",
                   fascia="wood_dark", door="paint_red", door_panel="brick_dark", frame="paint_white",
                   floor="wood_light", floor_seam="wood", chimney="brick_dark", chimney_band="concrete",
                   gable="brick", porch="wood_dark", post="paint_white", course="brick_dark", band="concrete",
                   parapet="brick", coping="concrete"),
    "concrete": Style("concrete", finish="panel", wall="concrete", trim="concrete_dark", interior="plaster",
                      wainscot="wood", found="concrete_dark", found_top="concrete_dark", roof="roof",
                      seam="roof_seam", roof_pattern="tiles", fascia="concrete_dark", door="metal_blue",
                      door_panel="metal_sheet", frame="paint_white", floor="wood", floor_seam="wood_dark",
                      chimney="concrete_dark", chimney_band="concrete", gable="panel", porch="concrete",
                      post="paint_white", course="concrete_dark", band="concrete_dark", parapet="concrete",
                      coping="concrete_dark"),
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
    if kind == "shop":
        return (c - SHOP_W / 2, c + SHOP_W / 2, z0 + SHOP_SILL, z0 + SHOP_SILL + SHOP_H)
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


def lap_sheet(fac, mb, a, b, z0, z1, holes, mat, step=0.20, d_bot=0.030, d_top=0.006, close=(False, False)):
    """Lap siding as a saw-tooth SHEET: one sloped quad per course and span (2 tris; the board lips face down and
    are never seen from the game camera). Courses are cut around `holes` (u0, u1, z0, z1). close = (at a, at b):
    add the saw-tooth end profile there (M3: an E / W wall end is exposed when the S / N facade that owns the
    corner is swapped for its stub in the cutaway)."""
    z = z0
    while z < z1 - 1e-6:
        zl, zh = z, min(z + step, z1)
        for sa, sb in _spans(a, b, [(h[0], h[1]) for h in holes if h[2] < zh - 1e-6 and h[3] > zl + 1e-6]):
            if sb - sa > 0.04:
                mb.poly([fac.p(sa, zl, d_bot), fac.p(sb, zl, d_bot), fac.p(sb, zh, d_top), fac.p(sa, zh, d_top)], mat,
                        facing=fac.n + Vector((0, 0, 0.1)))
                for u, flag, sgn in ((sa, close[0] and abs(sa - a) < 1e-6, -1), (sb, close[1] and abs(sb - b) < 1e-6, 1)):
                    if flag:
                        mb.poly([fac.p(u, zl, 0.0), fac.p(u, zl, d_bot), fac.p(u, zh, d_top), fac.p(u, zh, 0.0)], mat,
                                facing=fac.udir * sgn)
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


def panel_joints(fac, mb, a, b, z0, z1, holes, style, grid_u=True):
    """Precast concrete (M6a): a horizontal joint (dark strip 2 cm, 2 mm proud) at 1.4 m and a vertical joint at
    every 2 m grid line of the span, cut around the holes; a few rust streaks under the sills."""
    zb0 = fac.z0
    z = zb0 + 1.4
    if z < z1 - 0.02:
        for sa, sb in _spans(a, b, [(h[0], h[1]) for h in holes if h[2] < z + 0.02 and h[3] > z - 0.02]):
            if sb - sa > 0.05:
                mb.poly(fac.rect(sa, sb, z - 0.01, z + 0.01, 0.002), style.course, facing=fac.n)
    for u in (a, b):
        if grid_u and abs((u / GRID) - round(u / GRID)) < 1e-4:
            for za, zb in _spans(z0, z1, [(h[2], h[3]) for h in holes if h[0] - 0.02 < u < h[1] + 0.02]):
                if zb - za > 0.05:
                    mb.poly(fac.rect(u - 0.01, u + 0.01, za, zb, 0.002), style.course, facing=fac.n)
    for h in holes:
        za, zb = max(z0 + 0.05, h[2] - 0.7), min(h[2] - 0.02, z1)
        if h[2] > z0 + 0.3 and zb - za > 0.05:
            um = (h[0] + h[1]) / 2 + 0.25
            mb.poly(fac.rect(um - 0.03, um + 0.03, za, zb, 0.0025), "rust", facing=fac.n)


def finish(fac, g, a, b, z0, z1, holes, style, rnd, stub=False):
    """Exterior finish of one module span (siding sheet / brick courses / panel joints). Skirt, frieze, plinth and
    soldier course run along the whole facade (facade_bands)."""
    if style.finish == "lap":
        ends = (fac.d in "EW" and abs(a - fac.u0) < 1e-6, fac.d in "EW" and abs(b - fac.u1) < 1e-6)
        lap_sheet(fac, g.flat, a, b, z0 + (0.16 if fac.k == 0 else 0.14), z1 - (0.0 if stub else 0.12), holes,
                  style.wall, close=ends)
    elif style.finish == "brick":
        brick_courses(fac, g.flat, a, b, z0 + (0.45 if fac.k == 0 else 0.12), z1 - (0.0 if stub else 0.16), holes,
                      style, rnd)
    else:
        panel_joints(fac, g.flat, a, b, z0 + (0.45 if fac.k == 0 else 0.0), z1, holes, style)


def facade_bands(fac, g, style, door_holes, stub=False):
    """Skirt (wood) / plinth (brick, concrete; ground floor only) along the whole facade (cut at the doors) + belt
    board (wood, upper floors) + frieze / soldier course on top. Between storeys the slab rim (Floor<k>) is the
    string course."""
    zt = fac.z0 + (STUB_H if stub else WALL_H)
    spans = _spans(fac.u0, fac.u1, [(h[0] - 0.12, h[1] + 0.12) for h in door_holes])
    if style.finish == "lap":
        for sa, sb in spans:
            fac.box(g.hard, sa, sb, fac.z0 - (0.02 if fac.k == 0 else 0.0), fac.z0 + (0.16 if fac.k == 0 else 0.14),
                    0.0, 0.035, style.trim, skip=(fac.in_key,))
        if not stub:
            fac.box(g.hard, fac.u0, fac.u1, zt - 0.12, zt, 0.0, 0.03, style.trim, skip=(fac.in_key,))
    elif style.finish == "brick":
        if fac.k == 0:
            for sa, sb in _spans(fac.u0, fac.u1, [(h[0], h[1]) for h in door_holes]):
                fac.box(g.hard, sa, sb, fac.z0 - 0.02, fac.z0 + 0.45, 0.0, 0.03, style.found_top, skip=(fac.in_key,))
        if not stub:
            fac.box(g.flat, fac.u0, fac.u1, zt - 0.16, zt, 0.0, 0.018, style.course, skip=(fac.in_key, "-z"))
    else:
        if fac.k == 0:
            for sa, sb in _spans(fac.u0, fac.u1, [(h[0], h[1]) for h in door_holes]):
                fac.box(g.hard, sa, sb, fac.z0 - 0.02, fac.z0 + 0.45, 0.0, 0.025, style.found_top, skip=(fac.in_key,))
        if not stub:
            fac.box(g.flat, fac.u0, fac.u1, zt - 0.10, zt, 0.0, 0.015, style.trim, skip=(fac.in_key, "-z"))


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


def shop_trim(fac, g, hole, style, seed, pane_list, cut_group, floor):
    """Wall_Shop_4 dressing (M6a): a painted shopfront frame round the 3.2 x 2.2 display window (pilasters, head
    rail, stall riser sill), a set-back sash with a centre mullion and a transom bar, snow on the sill; the glass is
    ONE breakable Window_n (both faces)."""
    u0, u1, z0, z1 = hole
    t, f = g.hard, g.flat
    sk = (fac.in_key,)
    fr = style.frame if style.finish != "lap" else style.trim
    fac.box(t, u0 - 0.16, u0, fac.z0, z1 + 0.10, 0, 0.08, fr, skip=sk)             # pilasters
    fac.box(t, u1, u1 + 0.16, fac.z0, z1 + 0.10, 0, 0.08, fr, skip=sk)
    fac.box(t, u0 - 0.20, u1 + 0.20, z1, z1 + 0.16, 0, 0.10, fr, skip=sk)            # head rail
    fac.box(t, u0 - 0.04, u1 + 0.04, z0 - 0.06, z0, 0, 0.12, fr)                     # sill board
    fac.box(f, u0, u1, fac.z0 + 0.02, z0 - 0.06, 0, 0.02, style.course if style.finish == "brick" else
            style.found_top, skip=sk)                                                # stall riser panel
    um = (u0 + u1) / 2
    zt = z1 - 0.55
    for (a_, b_, c_, e_) in ((u0, u1, z0, z0 + 0.06), (u0, u1, z1 - 0.06, z1), (u0, u0 + 0.06, z0, z1),
                             (u1 - 0.06, u1, z0, z1), (um - 0.03, um + 0.03, z0, z1), (u0, u1, zt - 0.03, zt + 0.03)):
        fac.box(f, a_, b_, c_, e_, -0.10, -0.045, fr)
    g.snow.append(H.snow_ridge(fac.p(u0 + 0.02, z0, 0.07), fac.p(u1 - 0.02, z0, 0.07), 0.11, 0.06, seed=seed,
                               overhang=0.0, droop=0.02))
    pane = lp.MeshBuilder()
    pane.poly(fac.rect(u0 + 0.06, u1 - 0.06, z0 + 0.06, z1 - 0.06, -0.070), "window", facing=fac.n)
    pane.poly(fac.rect(u0 + 0.06, u1 - 0.06, z0 + 0.06, z1 - 0.06, -0.074), "window", facing=-fac.n)
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
    fac.box(g.flat, u0, u1, z0 - 0.02, z0 + 0.02, -WALL_T, 0.06, style.trim if style.finish != "lap" else "wood")
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
    # M6a: the origin is on the hinge axis AT THE BUILDING BASE (y = 0): pieces carry no Y offset (the corte urbano
    # shader reads the building base from each piece's origin, ARQ v2 §9.7); rotating about local Y is unchanged
    pivot = fac.p(hu, 0.0, (d0 + d1) / 2)
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
    fac.box(g.flat, u0, u1, z0 - 0.02, z0 + 0.02, -WALL_T, 0.06, style.trim if style.finish != "lap" else "wood")
    if style.finish == "lap":
        fac.box(g.flat, u0 - 0.12, u0, z0, zt, 0, 0.05, style.frame, skip=(fac.in_key,))
        fac.box(g.flat, u1, u1 + 0.12, z0, zt, 0, 0.05, style.frame, skip=(fac.in_key,))


def corner_module(ctx, fac, g, end, stub):
    """Corner_Out at the `end` (-1 = u0 side, +1 = u1 side) of an S / N facade: boards (wood), quoins (brick) or a
    pilaster strip (concrete) on BOTH faces of the corner column (they belong to the S / N group, §8.6)."""
    style = ctx.style
    z0 = fac.z0
    zb = z0 - (0.02 if fac.k == 0 else 0.0)
    zt = fac.z0 + (STUB_H if stub else WALL_H)
    u_edge = fac.u0 if end < 0 else fac.u1
    side = Facade("W" if end < 0 else "E", ctx.W, ctx.D, fac.k)
    # the side face of the corner column: v along the side facade, from the corner inward
    v_edge = fac.line + fac.sign * T2
    v_in = v_edge - fac.sign * 0.24                              # covers the column (0.2) + 4 cm overlap
    if style.finish == "lap":
        fac.box(g.hard, u_edge - end * 0.18, u_edge + end * 0.04, zb, zt, 0, 0.04, style.trim)
        a_, b_ = sorted((v_edge + fac.sign * 0.04, v_in))
        side.box(g.hard, a_, b_, zb, zt, 0, 0.04, style.trim)
    elif style.finish == "brick":
        z = z0 + (0.45 if fac.k == 0 else 0.1)
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
        if fac.k == 0:
            a_, b_ = sorted((v_edge, v_in))
            side.box(g.hard, a_, b_, z0 - 0.02, z0 + 0.45, 0, 0.03, style.found_top)   # plinth wraps the corner
    else:
        zz = z0 + (0.45 if fac.k == 0 else 0.0)
        fac.box(g.flat, u_edge - end * 0.16, u_edge + end * 0.02, zz, zt, 0, 0.02, style.trim, skip=(fac.in_key,))
        a_, b_ = sorted((v_edge + fac.sign * 0.02, v_edge - fac.sign * 0.18))
        side.box(g.flat, a_, b_, zz, zt, 0, 0.02, style.trim, skip=(side.in_key,))
        if fac.k == 0:
            a_, b_ = sorted((v_edge, v_in))
            side.box(g.hard, a_, b_, z0 - 0.02, z0 + 0.45, 0, 0.025, style.found_top)


def floor_module(ctx, g, x0, y0, z, base=True):
    """Floor_2x2: board field (one quad + board seams) of a 2 x 2 cell, top at z. base=False: only the seams (the
    slab box of an upper floor is the field)."""
    s = ctx.style
    if base:
        g.flat.poly([(x0, y0, z), (x0 + 2, y0, z), (x0 + 2, y0 + 2, z), (x0, y0 + 2, z)], s.floor, facing=(0, 0, 1))
    for k in range(1, 5):
        x = x0 + k * 0.4
        g.flat.poly([(x - 0.008, y0, z + 0.002), (x + 0.008, y0, z + 0.002), (x + 0.008, y0 + 2, z + 0.002),
                     (x - 0.008, y0 + 2, z + 0.002)], s.floor_seam, facing=(0, 0, 1))


def foundation_module(ctx, g, fac, a, b):
    """Foundation_Skirt_2: the 0.3 m base under a facade span, a little proud of the wall (front + top faces)."""
    s = ctx.style
    fac.box(g.flat, a, b, -0.05, FOUND - 0.02, -WALL_T, 0.05, s.found, skip=("-z", fac.in_key))


def rect_minus(r, holes):
    """Axis-aligned rectangle (x0, y0, x1, y1) minus non-overlapping holes -> disjoint rectangles (x-slabs)."""
    xs = sorted({r[0], r[2]} | {h[0] for h in holes} | {h[2] for h in holes})
    xs = [x for x in xs if r[0] - 1e-6 <= x <= r[2] + 1e-6]
    out = []
    for xa, xb in zip(xs[:-1], xs[1:]):
        if xb - xa < 1e-4:
            continue
        xm = (xa + xb) / 2
        cuts = [(h[1], h[3]) for h in holes if h[0] < xm < h[2]]
        for ya, yb in _spans(r[1], r[3], cuts):
            if yb - ya > 1e-4:
                out.append((xa, ya, xb, yb))
    # merge vertically adjacent strips with the same y span (fewer boxes)
    merged = []
    for q in out:
        if merged and abs(merged[-1][2] - q[0]) < 1e-6 and abs(merged[-1][1] - q[1]) < 1e-6 and \
                abs(merged[-1][3] - q[3]) < 1e-6:
            merged[-1] = (merged[-1][0], q[1], q[2], q[3])
        else:
            merged.append(q)
    return merged


def floor_slab(ctx, g, k, holes):
    """Floor_Slab of storey k >= 1 (M6a, one slab per floor): a closed 0.2 m box over the whole outer footprint
    (its rim is the string course between the storeys), top = floor boards at FOUND + k * STOREY, underside = the
    ceiling of storey k - 1, split around the stair openings (Floor_Stair_Opening, lined in wood). Returns the
    rectangles (collision)."""
    s = ctx.style
    xe, ye = ctx.W / 2 + T2, ctx.D / 2 + T2
    zt = FOUND + k * STOREY
    zb = zt - SLAB
    rects = rect_minus((-xe, -ye, xe, ye), holes)
    for (x0, y0, x1, y1) in rects:
        mats = {"+z": s.floor, "-z": s.interior}
        for key, v, lim in (("-x", x0, -xe), ("+x", x1, xe), ("-y", y0, -ye), ("+y", y1, ye)):
            mats[key] = s.band if abs(v - lim) < 1e-6 else "wood"
        g.flat.box((x0, y0, zb), (x1, y1, zt), s.band, mats=mats)
    hw, hd = ctx.W / 2, ctx.D / 2
    for i in range(int(ctx.W / GRID)):
        for j in range(int(ctx.D / GRID)):
            x0, y0 = -hw + GRID * i, -hd + GRID * j
            if any(h[0] < x0 + GRID and h[2] > x0 and h[1] < y0 + GRID and h[3] > y0 for h in holes):
                continue
            floor_module(ctx, g, x0, y0, zt, base=False)
    return [((x0, y0, zb), (x1, y1, zt)) for (x0, y0, x1, y1) in rects]


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
# stairs (M6a)
# ------------------------------------------------------------------------------------------------------------
_DIRS = {"N": (0.0, 1.0), "S": (0.0, -1.0), "E": (1.0, 0.0), "W": (-1.0, 0.0)}


class Flight:
    """Frame of a Stair_2x6 flight: u across (to the right looking up), v up the run, z absolute."""

    def __init__(self, ctx, spec):
        self.k = int(spec.get("floor", 0))
        fx, fy = _DIRS[spec.get("dir", "N")]
        self.f = Vector((fx, fy, 0.0))
        self.r = Vector((fy, -fx, 0.0))
        self.o = Vector((-ctx.W / 2 + spec["pos"][0], -ctx.D / 2 + spec["pos"][1], 0.0))
        self.w = float(spec.get("width", STAIR_W))
        self.z0 = FOUND + self.k * STOREY

    def P(self, u, v, z):
        return self.o + self.r * u + self.f * v + Vector((0.0, 0.0, z))

    def corners(self, u0, u1, v0, v1, z0, z1):
        return [self.P(u1 if i & 1 else u0, v1 if i & 2 else v0, z1 if i & 4 else z0) for i in range(8)]

    def rect(self, u0, u1, v0, v1):
        a, b = self.P(u0, v0, 0.0), self.P(u1, v1, 0.0)
        return (min(a.x, b.x), min(a.y, b.y), max(a.x, b.x), max(a.y, b.y))

    def opening(self):
        """The slab opening in floor k + 1 (x0, y0, x1, y1)."""
        return self.rect(-self.w / 2 - 0.05, self.w / 2 + 0.05, STAIR_HEAD, RUN)

    def open_sides(self, ctx):
        """Sides (-1 left, +1 right) not against an exterior wall (they get the handrail / balustrade)."""
        out = []
        xi, yi = ctx.W / 2 - T2, ctx.D / 2 - T2
        for sd in (-1, 1):
            p = self.P(sd * (self.w / 2 + 0.2), RUN / 2, 0.0)
            if abs(p.x) < xi - 0.05 and abs(p.y) < yi - 0.05:
                out.append(sd)
        return out


def stair(ctx, g, fl, rails):
    """Stair_2x6: 16 closed step boxes (tread wood, riser paint / wood light, sides wood dark) climbing 3.0 m over
    4.48 m, a stringer and a handrail on every open side (Interior<k>); returns the ramp collision points."""
    s = ctx.style
    w = fl.w
    riser = "paint_white" if s.finish != "lap" else "wood_light"
    for i in range(RISERS - 1):
        z1 = fl.z0 + (i + 1) * RISE
        c = fl.corners(-w / 2, w / 2, i * TREAD, (i + 1) * TREAD, fl.z0, z1)
        g.flat.hexa(c, "wood_dark", skip=("-z",), mats={"+z": "wood", "-y": riser})
        g.hard.hexa(fl.corners(-w / 2 - 0.01, w / 2 + 0.01, i * TREAD - 0.03, (i + 1) * TREAD, z1, z1 + 0.03),
                    "wood")                                                          # nosing / tread board
    for sd in fl.open_sides(ctx):
        u0, u1 = (w / 2, w / 2 + 0.05) if sd > 0 else (-w / 2 - 0.05, -w / 2)
        cs = []
        for i in range(8):
            u = u1 if i & 1 else u0
            v = RUN if i & 2 else 0.0
            dz = (0.12 if i & 4 else -0.18)
            cs.append(fl.P(u, v, fl.z0 + (STOREY if i & 2 else 0.0) + dz + (0.18 if not (i & 2) and not (i & 4)
                                                                             else 0.0)))
        g.hard.hexa(cs, "wood_dark")                                                 # stringer
        uc = (u0 + u1) / 2
        for v in (0.15, RUN - 0.15):
            zf = fl.z0 + (v / RUN) * STOREY
            g.hard.hexa(fl.corners(uc - 0.035, uc + 0.035, v - 0.035, v + 0.035, zf, zf + 0.95), s.post)   # newel
        rail = []
        for i in range(8):
            u = uc + (0.03 if i & 1 else -0.03)
            v = (RUN - 0.15) if i & 2 else 0.15
            zf = fl.z0 + (v / RUN) * STOREY + 0.9 + (0.05 if i & 4 else 0.0)
            rail.append(fl.P(u, v, zf))
        g.hard.hexa(rail, "wood")                                                    # handrail
        rails.append(fl.corners(uc - 0.03, uc + 0.03, 0.15, RUN - 0.15, fl.z0, fl.z0 + STOREY + 0.95))
    u0, u1 = -w / 2, w / 2
    return [fl.P(u0, 0.0, fl.z0), fl.P(u0, RUN, fl.z0), fl.P(u0, RUN, fl.z0 + STOREY),
            fl.P(u1, 0.0, fl.z0), fl.P(u1, RUN, fl.z0), fl.P(u1, RUN, fl.z0 + STOREY)]


def balustrade(ctx, g, fl, col, k):
    """Balustrade round the stair opening in floor k + 1 (Interior<k + 1>): posts, top and mid rail on the open
    long sides and on the low end; the top end is the way in. Adds ColRail<k+1>_<n> boxes."""
    s = ctx.style
    zf = fl.z0 + STOREY
    w = fl.w
    runs = []
    for sd in fl.open_sides(ctx):
        u = sd * (w / 2 + 0.08)
        runs.append(((u, STAIR_HEAD - 0.05), (u, RUN - 0.05)))
    runs.append(((-w / 2 - 0.08, STAIR_HEAD - 0.08), (w / 2 + 0.08, STAIR_HEAD - 0.08)))
    n = 0
    for (ua, va), (ub, vb) in runs:
        L = math.hypot(ub - ua, vb - va)
        for t in [i / max(1, int(L / 1.2)) for i in range(int(L / 1.2) + 1)]:
            u, v = ua + (ub - ua) * t, va + (vb - va) * t
            g.hard.hexa(fl.corners(u - 0.035, u + 0.035, v - 0.035, v + 0.035, zf, zf + 0.95), s.post)
        for zz, hh in ((zf + 0.92, 0.05), (zf + 0.45, 0.03)):
            g.hard.hexa(fl.corners(min(ua, ub) - 0.03, max(ua, ub) + 0.03, min(va, vb) - 0.03, max(va, vb) + 0.03,
                                   zz, zz + hh), "wood")
        a = fl.P(min(ua, ub) - 0.03, min(va, vb) - 0.03, zf)
        b = fl.P(max(ua, ub) + 0.03, max(va, vb) + 0.03, zf + 1.0)
        col["ColRail%d_%d" % (k + 1, n)] = ((min(a.x, b.x), min(a.y, b.y), zf), (max(a.x, b.x), max(a.y, b.y), zf + 1.0))
        n += 1


# ------------------------------------------------------------------------------------------------------------
# roof
# ------------------------------------------------------------------------------------------------------------
def roof_slab(ctx, g, ze):
    """Roof_Slab (M6a): the ceiling slab of the top storey, a closed 0.2 m box over the whole outer footprint (top
    at FOUND + floors * STOREY, the 'one slab per floor' of the cut contract); its rim is the frieze band."""
    s = ctx.style
    xe, ye = ctx.W / 2 + T2, ctx.D / 2 + T2
    g.flat.box((-xe, -ye, ze), (xe, ye, ze + SLAB), s.band, mats={"-z": s.interior, "+z": s.interior})


def gable_roof(ctx, g, pitch=35.0, over=0.4, rt=0.16):
    """Gable roof, ridge along Y, over the Roof_Slab. The deck and fascia run per slope (one piece each);
    Roof_Gable_2 = the 2 m slices of standing seams (wood_blue) or tile courses (brick, concrete: a saw-tooth sheet)
    + ridge cap; Roof_Gable_End = rake overhang, rake boards, gable triangle (standing on the slab) with its finish
    and a louvred vent. Snow: one continuous slab per slope from the eave (drooping cornice) up to 74-82 %, lumps in
    the bare band, a few icicle strips under the eaves."""
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
    roof_slab(ctx, g, ze)
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
                    mat = s.seam if int((x + sy0) * 7) % 5 == 0 else s.roof
                    g.flat.poly([lo + Vector((0, sy0, 0)), lo + Vector((0, sy1, 0)), hi + Vector((0, sy1, 0)),
                                 hi + Vector((0, sy0, 0))], mat, facing=n)
                    base = Vector((sg * x, 0, z_under(x) + dz))                    # butt edge (faces down-slope)
                    g.flat.poly([base + Vector((0, sy0, 0)), base + Vector((0, sy1, 0)), lo + Vector((0, sy1, 0)),
                                 lo + Vector((0, sy0, 0))], s.seam, facing=Vector((sg, 0, -t)))
                    for yy, sy in ((sy0, -1), (sy1, 1)):                         # closed ends at the rakes
                        if (sy < 0 and abs(yy - y0) < 1e-6) or (sy > 0 and abs(yy - y1) < 1e-6):
                            g.flat.poly([base + Vector((0, yy, 0)), lo + Vector((0, yy, 0)), hi + Vector((0, yy, 0))],
                                        s.seam, facing=Vector((0, sy, 0)))
                    x = xu
    g.hard.prism([Vector((-0.14, y0, ridge + dz - 0.02)), Vector((0.14, y0, ridge + dz - 0.02)),
                  Vector((0.0, y0, ridge + dz + 0.07))], (0, y0, 0), (0, y1, 0), s.seam)             # ridge cap
    # gable ends (S and N), standing on the roof slab
    zg = ze + SLAB
    xg = xe - SLAB / t
    for sgy in (-1, 1):
        yw = sgy * (hd + T2)
        prof = [Vector((-xg, yw, zg)), Vector((xg, yw, zg)), Vector((0, yw, ridge))]
        g.flat.prism(prof, (0, yw, 0), (0, yw - sgy * WALL_T, 0), s.wall)
        fac = Facade("S" if sgy < 0 else "N", ctx.W, ctx.D, 0)
        if s.gable == "lap":
            z = zg + 0.02
            while z < ridge - 0.25:
                zz = z + 0.2
                half_l, half_h = (ridge - z) / t - 0.02, (ridge - zz) / t - 0.02
                if half_h > 0.1:
                    fac_poly(g.flat, fac, [(-half_l, z, 0.03), (half_l, z, 0.03), (half_h, zz, 0.006),
                                          (-half_h, zz, 0.006)], s.wall)
                z = zz
        else:
            z = zg + 0.3
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
        vz = (zg + ridge) / 2 + 0.2
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
            if v >= size_v - 1e-6:            # wavy upper rim; never pulled back past its support row (fold)
                dv = max(-0.09, 0.4 * H.fbm(u * 0.7, seed * 1.3, 2, seed))
            return (0.0, dv, dn)
        g.snow.append(H.pillow(E - V * ov, Vector((0, 1, 0)), V, N, size_u, size_v, 0.22, nu=max(5, int(size_u / 1.5)),
                               nv=4, rim=0.16, seed=seed, lip=lip, bumps=0.04, levels=1, bottom=-0.09,
                               keep_bottom=lambda c, xo=xo, y0=y0, y1=y1: abs(c.x) > xo - 0.05 or c.y < y0 + 0.2
                               or c.y > y1 - 0.2))                      # closed cornice underside (overhang)
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
    ctx.roof_proxy = ("gable", ridge)


def flat_roof(ctx, g, parapet_h=0.9):
    """Flat roof (M6a): Roof_Slab with a dark membrane on top, Parapet_2 walls (0.2 m, closed, the facade material
    outside, a coping cap), a snow blanket inside the parapet, snow lines on the coping, a vent box and a stand
    pipe. Belongs to the Roof group (hidden shadow-preserving with it)."""
    s = ctx.style
    hw, hd = ctx.W / 2, ctx.D / 2
    xe, ye = hw + T2, hd + T2
    ze = FOUND + ctx.floors * STOREY - SLAB
    top = ze + SLAB
    zp = top + parapet_h
    g.flat.box((-xe, -ye, ze), (xe, ye, top), s.band, mats={"-z": s.interior, "+z": s.roof})
    pt = 0.2
    rings = [((-xe, -ye, top), (xe, -ye + pt, zp), "-y"), ((-xe, ye - pt, top), (xe, ye, zp), "+y"),
             ((-xe, -ye + pt, top), (-xe + pt, ye - pt, zp), "-x"), ((xe - pt, -ye + pt, top), (xe, ye - pt, zp), "+x")]
    for mn, mx, out in rings:
        inner = ("-" if out[0] == "+" else "+") + out[1]
        g.flat.box(mn, mx, s.parapet, skip=("-z",), mats={inner: s.coping if s.finish == "lap" else "concrete",
                                                         "+z": s.coping})
    c = 0.05
    for mn, mx in [((-xe - c, -ye - c, zp), (xe + c, -ye + pt + c, zp + 0.07)),
                   ((-xe - c, ye - pt - c, zp), (xe + c, ye + c, zp + 0.07)),
                   ((-xe - c, -ye + pt + c, zp), (-xe + pt + c, ye - pt - c, zp + 0.07)),
                   ((xe - pt - c, -ye + pt + c, zp), (xe + c, ye - pt - c, zp + 0.07))]:
        g.hard.box(mn, mx, s.coping)
    if s.finish == "brick":                                  # soldier course under the coping, outside
        for d in "SNEW":
            fac = Facade(d, ctx.W, ctx.D, 0)
            fac.box(g.flat, fac.u0 if d in "SN" else -ye, fac.u1 if d in "SN" else ye, zp - 0.16, zp - 0.02, 0.0,
                    0.012, s.course, skip=(fac.in_key, "-z"))
    # snow blanket inside the parapet + lines on the coping
    iw, idp = 2 * (xe - pt) - 0.06, 2 * (ye - pt) - 0.06
    g.snow.append(H.pillow(Vector((-xe + pt + 0.03, -ye + pt + 0.03, top)), Vector((1, 0, 0)), Vector((0, 1, 0)),
                           Vector((0, 0, 1)), iw, idp, 0.16, nu=max(5, int(iw / 1.6)), nv=max(4, int(idp / 1.6)),
                           rim=0.25, seed=ctx.seed + 7, bumps=0.05, levels=1, bottom=-0.02))
    for k, (a, b) in enumerate((((-xe, -ye + 0.1), (xe, -ye + 0.1)), ((-xe, ye - 0.1), (xe, ye - 0.1)),
                                ((-xe + 0.1, -ye + 0.3), (-xe + 0.1, ye - 0.3)), ((xe - 0.1, -ye + 0.3), (xe - 0.1, ye - 0.3)))):
        g.snow.append(H.snow_ridge((a[0], a[1], zp + 0.07), (b[0], b[1], zp + 0.07), 0.22, 0.07, seed=ctx.seed + 60 + k,
                                   overhang=0.0, droop=0.02))
    # roof plant: vent box + stand pipe
    vx, vy = xe - pt - 1.4, ye - pt - 1.2
    g.hard.box((vx - 0.45, vy - 0.35, top), (vx + 0.45, vy + 0.35, top + 0.55), "metal_sheet")
    g.hard.box((vx - 0.5, vy - 0.4, top + 0.55), (vx + 0.5, vy + 0.4, top + 0.62), "metal_sheet")
    g.snow.append(H.pillow(Vector((vx - 0.48, vy - 0.38, top + 0.62)), Vector((1, 0, 0)), Vector((0, 1, 0)),
                           Vector((0, 0, 1)), 0.96, 0.76, 0.08, nu=4, nv=3, rim=0.08, seed=ctx.seed + 64, levels=1))
    H.tube(g.flat, [(-vx, vy, top), (-vx, vy, top + 0.8)], [0.07, 0.07], 8, "iron", cap_end=True)
    ctx.roof_ridge = zp + 0.07
    ctx.z_under = lambda x, top=top: top
    ctx.roof_t = 0.0
    ctx.roof_dz = 0.0
    ctx.roof_proxy = ("flat", zp)


def fac_poly(mb, fac, pts, mat):
    """Polygon from facade-local (u, z, d) points, facing out of the facade."""
    mb.poly([fac.p(u, z, d) for u, z, d in pts], mat, facing=fac.n)


def chimney(ctx, g, x, y):
    """Chimney stack through the roof slope (or on the flat roof) at (x, y): brick with courses, band, cap slab,
    flue, snow cap."""
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
    ctx.chimney_box = ((x - h, y - h), (x + h, y + h), top + 0.12)


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
                            rim=0.14, seed=ctx.seed + 90, lip=lip, bumps=0.03, levels=1, bottom=-0.09,
                            keep_bottom=lambda c, ya=ya, x0=x0, x1=x1: c.y < ya - 0.3 or c.x < x0 - 0.2
                            or c.x > x1 + 0.2))
    ctx.porch_box = ((x0, ya, 0.0), (x1, yb, FOUND))
    ctx.steps = (sx0, sx1, ya - 0.68, ya)


def awning(ctx, g, fac, spec, seed):
    """Awning_4 (M6a): striped canvas sloping from the facade at `z` down `drop` over `depth`, a front valance, iron
    brackets and a snow slab on top. Part of the facade group (it goes with the facade in the cutaway)."""
    a, b = float(spec["from"]), float(spec["to"])
    z = fac.z0 + float(spec.get("z", 2.75))
    depth = float(spec.get("depth", 1.1))
    drop = float(spec.get("drop", 0.45))
    cols = spec.get("colors", ["paint_red", "cloth_white"])
    th = 0.03
    nst = max(2, int(round((b - a) / 0.5)))
    for i in range(nst):
        u0 = a + (b - a) * i / nst
        u1 = a + (b - a) * (i + 1) / nst
        cs = []
        for j in range(8):
            u = u1 if j & 1 else u0
            out = bool(j & 2)
            up = bool(j & 4)
            zz = (z - drop if out else z) + (th if up else 0.0)
            cs.append(fac.p(u, zz, depth if out else 0.02))
        g.flat.hexa(cs, cols[i % len(cols)])
        fac.box(g.flat, u0, u1, z - drop - 0.22, z - drop + th, depth - 0.02, depth + 0.01, cols[i % len(cols)])
    for u in [a + 0.08] + [a + (b - a) * t for t in (0.5,)] + [b - 0.08]:
        cs = []
        for j in range(8):
            uu = u + (0.02 if j & 1 else -0.02)
            out = bool(j & 2)
            up = bool(j & 4)
            zz = (z - drop - 0.02 if out else z - 0.35) + (0.04 if up else 0.0)
            cs.append(fac.p(uu, zz, depth - 0.05 if out else 0.01))
        g.hard.hexa(cs, "iron")
    top0, top1 = fac.p(a, z - drop + th, depth), fac.p(a, z + th, 0.02)
    V = (top1 - top0).normalized()
    U = fac.udir
    N = U.cross(V)
    if N.z < 0:
        N = -N
    g.snow.append(H.pillow(top0 - V * 0.04, U, V, N, b - a, (top1 - top0).length + 0.02, 0.12, nu=max(4, int((b - a) / 1.2)),
                           nv=3, rim=0.1, seed=seed, bumps=0.02, levels=1, bottom=-0.02))


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


FURNITURE_MODELS = ("bed", "desk", "chair", "shelf", "clock", "cabinet", "wood_stove", "storage_box")
# spawn kind -> merged visual (M6a: the interactive spawns keep their empty for the code, the look is in the kit)
SPAWN_VISUALS = {"Bed": "bed", "Stove": "wood_stove"}
NO_COLLISION = ("rug", "clock")


def furniture_model(ctx, g, name, x, y, z, yaw):
    """M6a interior sets reuse the existing furniture: assets/models/<name>.glb (bed, desk, chair, shelf, clock,
    cabinet, wood_stove, storage_box) is imported, its meshes joined and posed at (x, y, z) / yaw, and merged into
    the Interior<k> group (one surface, cut-ready: the piece's origin is the building base like every group). The
    stove's `ember` door is repainted iron (a cold stove in an abandoned house). Returns the world AABB."""
    from mathutils import Matrix
    from . import palette
    from .export import MODELS_DIR, quiet, ensure_gltf
    ensure_gltf()
    before = set(bpy.data.objects)
    with quiet():
        bpy.ops.import_scene.gltf(filepath=str(MODELS_DIR / ("%s.glb" % name)))
    new = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in new if o.type == 'MESH']
    xf = Matrix.Translation((x, y, z)) @ Matrix.Rotation(math.radians(yaw), 4, 'Z')
    vmat = palette.get_material("wood")
    for o in meshes:
        mw = o.matrix_world.copy()
        o.parent = None
        o.data = o.data.copy()
        o.data.transform(xf @ mw)
        o.matrix_world = Matrix.Identity(4)
        me = o.data
        # the glTF importer may give a byte / point colour attribute: rebuild `Col` as FLOAT_COLOR per corner (the
        # kit's own format; a byte attribute would requantise the palette values of the whole group on join)
        src = me.color_attributes[0]
        n = len(src.data)
        vals = [0.0] * (n * 4)
        src.data.foreach_get("color", vals)
        if src.domain == 'POINT':
            vals = [vals[l.vertex_index * 4 + c] for l in me.loops for c in range(4)]
        for a in list(me.color_attributes):
            me.color_attributes.remove(a)
        attr = me.color_attributes.new(palette.VCOL_ATTR, 'FLOAT_COLOR', 'CORNER')
        attr.data.foreach_set("color", vals)
        for uv in list(me.uv_layers):
            me.uv_layers.remove(uv)
        ember = [i for i, m in enumerate(me.materials) if m is not None and not m.name.startswith(palette.VCOL_MATERIAL)]
        faces_ember = [p.index for p in me.polygons if p.material_index in ember]
        me.materials.clear()
        me.materials.append(vmat)
        for p in me.polygons:
            p.material_index = 0
        if faces_ember:
            palette.paint(me, faces_ember, "iron")
    for o in new:
        if o.type != 'MESH':
            bpy.data.objects.remove(o, do_unlink=True)
    joined = H.join(meshes, H.tmp_name("furn")) if len(meshes) > 1 else meshes[0]
    if len(meshes) == 1:
        joined.name = H.tmp_name("furn")
    H.snap_colors(joined)                      # slice-era colours -> the nearest v2.1 palette colour
    for m in list(bpy.data.materials):
        if m.users == 0:
            bpy.data.materials.remove(m)
    g.smooth.append(joined)
    ws = [v.co for v in joined.data.vertices]
    return (tuple(min(v[i] for v in ws) for i in range(3)), tuple(max(v[i] for v in ws) for i in range(3)))


def _furniture_box(ctx, x, y, yaw, z0, half, h):
    """World AABB of a decorative piece (local half extents `half` = (hx, hy), height h) for its collision box."""
    c, sn = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    ex = abs(half[0] * c) + abs(half[1] * sn)
    ey = abs(half[0] * sn) + abs(half[1] * c)
    return ((x - ex, y - ey, z0), (x + ex, y + ey, z0 + h))


FURNITURE_EXTENTS = {"counter": ((1.02, 0.32), 0.9), "table": ((0.6, 0.82), 0.76), "shelf": ((0.45, 0.16), 1.6),
                     "kitchen": ((1.22, 0.32), 0.89), "sofa": ((0.95, 0.42), 0.85), "armchair": ((0.42, 0.42), 0.9),
                     "wardrobe": ((0.55, 0.3), 2.0), "bookshelf": ((0.5, 0.17), 1.9), "dresser": ((0.5, 0.24), 0.85),
                     "tv": ((0.6, 0.22), 0.92), "shop_shelf": ((1.0, 0.3), 1.6), "shop_counter": ((1.23, 0.38), 1.0),
                     "desk_block": ((0.7, 0.35), 0.79), "crates": ((0.95, 0.3), 1.0), "bunk": ((0.48, 1.01), 1.9)}


FURNITURE_KINDS = ("counter", "table", "shelf", "kitchen", "sofa", "rug", "wardrobe", "bookshelf", "dresser", "tv",
                   "shop_shelf", "shop_counter", "desk_block", "crates", "armchair", "bunk")


def furniture(ctx, g, kind, x, y, yaw, z0):
    """Decorative furniture merged into Interior<k> (closed chamfered boxes, cut-ready). Front = local -Y (the side
    you use), origin at the base centre; M6a adds the room sets' pieces: kitchen run (base units, sink, upper
    cabinets), sofa / armchair, rug, wardrobe, bookshelf with books, dresser, tv on a stand, shop gondola shelf with
    goods, shop counter with a till, office desk block, crate stack, bunk bed."""
    s = ctx.style
    c, sn = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    rnd = random.Random(int(x * 131 + y * 17 + z0 * 7) + ctx.seed)

    def P(px, py, pz):
        return Vector((x + px * c - py * sn, y + px * sn + py * c, z0 + pz))

    def box(mn, mx, mat, mb=None):
        corners = [P(mx[0] if i & 1 else mn[0], mx[1] if i & 2 else mn[1], mx[2] if i & 4 else mn[2]) for i in range(8)]
        (mb or g.hard).hexa(corners, mat)

    goods = ("can_red", "can_blue", "paint_yellow", "cloth_white", "paper", "hospital_green", "wood_light")
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
    elif kind == "kitchen":                               # 2.4 m run: base units, worktop, sink, upper cabinets
        box((-1.2, -0.3, 0.0), (1.2, 0.3, 0.84), "paint_white")
        box((-1.22, -0.32, 0.84), (1.22, 0.32, 0.89), "concrete_dark")
        for k in range(4):
            box((-1.15 + k * 0.6, -0.305, 0.1), (-0.65 + k * 0.6, -0.30, 0.78), "cloth_white", g.flat)
        box((0.15, -0.22, 0.87), (0.75, 0.2, 0.895), "metal_sheet", g.flat)         # sink
        box((0.43, 0.14, 0.89), (0.47, 0.18, 1.12), "chrome", g.flat)                 # tap
        box((-1.2, 0.0, 1.45), (1.2, 0.3, 2.15), "paint_white")                        # upper cabinets
        for k in range(4):
            box((-1.15 + k * 0.6, -0.005, 1.5), (-0.65 + k * 0.6, 0.0, 2.1), "cloth_white", g.flat)
    elif kind == "sofa":
        col = rnd.choice(("jacket_blue", "parka_olive", "parka_rust", "cloth_gray"))
        box((-0.95, -0.42, 0.0), (0.95, 0.42, 0.42), col)                              # seat
        box((-0.95, 0.2, 0.42), (0.95, 0.42, 0.85), col)                               # back
        for sx in (-1, 1):
            box((sx * 0.83 - 0.12, -0.42, 0.42), (sx * 0.83 + 0.12, 0.42, 0.62), col)            # arms
        for k in (-1, 1):
            box((k * 0.45 - 0.38, -0.36, 0.42), (k * 0.45 + 0.38, 0.16, 0.5), "cloth", g.flat)   # cushions
    elif kind == "armchair":
        col = rnd.choice(("parka_brown", "parka_navy", "cloth_gray"))
        box((-0.42, -0.42, 0.0), (0.42, 0.42, 0.42), col)
        box((-0.42, 0.2, 0.42), (0.42, 0.42, 0.9), col)
        for sx in (-1, 1):
            box((sx * 0.36 - 0.07, -0.42, 0.42), (sx * 0.36 + 0.07, 0.42, 0.62), col)
    elif kind == "rug":
        box((-1.0, -0.7, 0.0), (1.0, 0.7, 0.012), rnd.choice(("parka_rust", "cloth", "parka_navy")), g.flat)
        box((-0.85, -0.55, 0.012), (0.85, 0.55, 0.016), "cloth_white", g.flat)
    elif kind == "wardrobe":
        box((-0.55, -0.3, 0.0), (0.55, 0.3, 2.0), "wood_dark")
        box((-0.003, -0.305, 0.08), (0.003, -0.3, 1.94), "wood", g.flat)
        for sx in (-1, 1):
            box((sx * 0.08 - 0.01, -0.33, 1.0), (sx * 0.08 + 0.01, -0.305, 1.12), "brass", g.flat)
    elif kind == "bookshelf":
        box((-0.5, -0.16, 0.0), (0.5, 0.16, 1.9), "wood_dark")
        for k in range(5):
            zb = 0.08 + k * 0.37
            box((-0.46, -0.17, zb - 0.02), (0.46, -0.15, zb), "wood", g.flat)
            xx = -0.44
            while xx < 0.4:
                bw = rnd.uniform(0.04, 0.09)
                hgt = rnd.uniform(0.2, 0.3)
                box((xx, -0.14, zb), (xx + bw, 0.1, zb + hgt), rnd.choice(goods), g.flat)
                xx += bw + 0.005
    elif kind == "dresser":
        box((-0.5, -0.24, 0.0), (0.5, 0.24, 0.85), "wood")
        for k in range(3):
            box((-0.46, -0.245, 0.08 + k * 0.26), (0.46, -0.24, 0.3 + k * 0.26), "wood_light", g.flat)
    elif kind == "tv":
        box((-0.6, -0.22, 0.0), (0.6, 0.22, 0.5), "wood_dark")
        box((-0.34, -0.12, 0.5), (0.34, 0.14, 0.92), "plastic_black")
        box((-0.29, -0.125, 0.55), (0.29, -0.12, 0.87), "cloth_dark", g.flat)
    elif kind == "shop_shelf":                            # gondola 2.0 x 0.6 x 1.6, goods both sides
        box((-1.0, -0.06, 0.0), (1.0, 0.06, 1.6), "metal_sheet")
        box((-1.0, -0.3, 0.0), (1.0, 0.3, 0.12), "metal_sheet")
        for k in range(3):
            zb = 0.45 + k * 0.4
            for sy in (-1, 1):
                box((-0.98, min(sy * 0.3, sy * 0.06), zb - 0.02), (0.98, max(sy * 0.3, sy * 0.06), zb), "metal_sheet",
                    g.flat)
                xx = -0.95
                while xx < 0.85:
                    bw = rnd.uniform(0.12, 0.26)
                    if rnd.random() < 0.72:
                        hgt = rnd.uniform(0.12, 0.3)
                        box((xx, min(sy * 0.28, sy * 0.1), zb), (xx + bw, max(sy * 0.28, sy * 0.1), zb + hgt),
                            rnd.choice(goods), g.flat)
                    xx += bw + 0.03
    elif kind == "shop_counter":
        box((-1.2, -0.35, 0.0), (1.2, 0.35, 0.95), "wood_dark")
        box((-1.23, -0.38, 0.95), (1.23, 0.38, 1.0), "wood")
        box((0.5, -0.2, 1.0), (0.9, 0.15, 1.2), "plastic_black")                       # till
        box((0.55, -0.22, 1.2), (0.85, -0.05, 1.32), "cloth_dark", g.flat)
    elif kind == "desk_block":
        box((-0.7, -0.35, 0.72), (0.7, 0.35, 0.76), "wood")
        box((-0.7, -0.35, 0.0), (-0.3, 0.35, 0.72), "wood_dark")
        box((0.66, -0.35, 0.0), (0.7, 0.35, 0.72), "wood_dark", g.flat)
        box((-0.2, -0.1, 0.76), (0.25, 0.2, 0.79), "paper", g.flat)
    elif kind == "crates":
        for k, (dx, dy, dz) in enumerate(((0.0, 0.0, 0.0), (0.62, 0.05, 0.0), (0.3, 0.0, 0.5))):
            box((dx - 0.3, dy - 0.25, dz), (dx + 0.3, dy + 0.25, dz + 0.5), "wood" if k % 2 == 0 else "wood_light")
    elif kind == "bunk":
        for zz in (0.3, 1.35):
            box((-0.45, -1.0, zz), (0.45, 1.0, zz + 0.12), "wood_dark")
            box((-0.42, -0.97, zz + 0.12), (0.42, 0.97, zz + 0.24), "cloth_gray")
        for sx in (-1, 1):
            for sy in (-1, 1):
                box((sx * 0.43 - 0.03, sy * 0.98 - 0.03, 0.0), (sx * 0.43 + 0.03, sy * 0.98 + 0.03, 1.9), "wood_dark",
                    g.flat)
    else:
        raise ValueError("unknown furniture kind %r" % kind)


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
        self.chimney_box = None
        self.roof_proxy = None
        self.porch_roof_high = FOUND + WALL_H - 0.05
        self.porch_roof_low = FOUND + 2.45


def _openings(tpl, d, k=0):
    """{cell index along the facade: (kind, spec)} for facade d of storey k (a shop takes its 2-cell module; the
    second cell is marked "shop+")."""
    out = {}
    for w in tpl.get("windows", []):
        if w["dir"] == d and w.get("floor", 0) == k:
            out[w["pos"][0] if d in "SN" else w["pos"][1]] = ("window", w)
    for dd in tpl.get("doors", []):
        if dd["dir"] == d and dd.get("floor", 0) == k:
            out[dd["pos"][0] if d in "SN" else dd["pos"][1]] = ("door", dd)
    for sp in tpl.get("shops", []):
        if sp["dir"] == d and sp.get("floor", 0) == k:
            ci = sp["pos"][0] if d in "SN" else sp["pos"][1]
            out[ci] = ("shop", sp)
            out[ci + 1] = ("shop+", sp)
    return out


def _col_box(name, fac, u0, u1, z0, z1):
    a, b = fac.p(u0, z0, -WALL_T), fac.p(u1, z1, 0.0)
    return lp.collision_box(name, (min(a.x, b.x), min(a.y, b.y), z0), (max(a.x, b.x), max(a.y, b.y), z1))


def bake_cut_ao(distance=1.2, samples=64, ground=True):
    """AO for a building / POI with the v2 cutaway structure (M3). Pass 1: every visual mesh except the `_Stub`
    walls (they share the space of the full walls and would black them out) and the ShadowProxy (M6a: it wraps the
    whole building). Pass 2: the stubs, with the full walls and the roof removed from the occluders (a stub is only
    ever seen with its wall and the roof hidden). Window panes and the proxy get a constant 0.98 / 1.0 (the `window`
    material does not use COLOR_0; the proxy is never drawn, only casts)."""
    from .export import is_col
    vis = [o for o in bpy.context.scene.objects if o.type == 'MESH' and not is_col(o.name)]
    stubs = [o for o in vis if o.name.endswith("_Stub")]
    panes = [o for o in vis if o.name.startswith("Window_")]
    proxy = [o for o in vis if o.name == "ShadowProxy"]
    main = [o for o in vis if o not in stubs and o not in panes and o not in proxy]
    H.bake_ao(main, distance=distance, samples=samples, ground=ground,
              exclude={o.name for o in stubs} | {o.name for o in proxy})
    hide = {o.name for o in vis if (o.name.startswith("Walls") and not o.name.endswith("_Stub")) or o.name == "Roof"}
    if stubs:
        H.bake_ao(stubs, distance=distance, samples=samples, ground=ground, exclude=hide | {o.name for o in proxy})
    for o, a in [(p, 0.98) for p in panes] + [(p, 1.0) for p in proxy]:
        me = o.data
        col = me.color_attributes[0]
        data = [0.0] * (len(col.data) * 4)
        col.data.foreach_get("color", data)
        for i in range(3, len(data), 4):
            data[i] = a
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


def shadow_proxy(ctx, kind):
    """ShadowProxy (M6a, W0 contract): one closed low-poly volume = the walls' box from the ground to the roof slab
    + the gable prism (no overhangs) or the parapet box, + the chimney stack. palette_vcol (concrete_dark, AO 1) so
    it passes the export contract; in game CityBuilding makes it SHADOWS_ONLY, it is the only caster (the roof,
    walls and upper floors hidden by the cutaway keep their shadow: the interior stays dark) and its AABB is the
    footprint of the own-building rule."""
    xe, ye = ctx.W / 2 + T2, ctx.D / 2 + T2
    top = FOUND + ctx.floors * STOREY
    mb = lp.MeshBuilder()
    mb.box((-xe, -ye, 0.0), (xe, ye, top), "concrete_dark")
    kind_, h = ctx.roof_proxy
    if kind_ == "gable":
        mb.prism([Vector((-xe, -ye, top)), Vector((xe, -ye, top)), Vector((0.0, -ye, h))], (0, -ye, 0), (0, ye, 0),
                 "concrete_dark")
    else:
        mb.box((-xe, -ye, top), (xe, ye, h), "concrete_dark")
    if ctx.chimney_box:
        (x0, y0), (x1, y1), zt = ctx.chimney_box
        mb.box((x0, y0, top), (x1, y1, zt), "concrete_dark")
    o = H.flat(H.mk(mb, "ShadowProxy"))
    tpl = ctx.tpl
    o["floors"] = ctx.floors
    o["floor_h"] = STOREY
    o["ground_h"] = FOUND + STOREY
    o["foundation"] = FOUND
    o["kind"] = tpl.get("kind", "house")
    o["enterable"] = True
    return o


def _floor_spec(e):
    return int(e.get("floor", 0))


def build(tpl, style_name):
    """Build template `tpl` in style `style_name` into the current scene. Returns a summary dict
    (groups, doors, windows, spawns, extra nodes, collision names, expected collision boxes, storey levels)."""
    ctx = Ctx(tpl, style_name)
    s = ctx.style
    W, D = ctx.W, ctx.D
    hw, hd = W / 2, D / 2
    floors = ctx.floors
    summary = {"groups": [], "doors": [], "windows": [], "spawns": [], "extra": [], "col": {}, "floors": floors}
    roof = Group("Roof", floors)
    door_specs = []
    col = {}
    ramps = {}
    flights = [Flight(ctx, sp) for sp in tpl.get("stairs", [])]
    openings = {k: [fl.opening() for fl in flights if fl.k + 1 == k] for k in range(floors)}
    groups = []
    floor_groups = {}
    interior_groups = {}
    wall_groups = {}
    for k in range(floors):
        floor = Group("Floor%d" % k, k)
        walls = {d: Group("Walls%d_%s" % (k, d), k) for d in "SNEW"}
        stubs = {d: Group("Walls%d_%s_Stub" % (k, d), k) for d in "SNEW"}
        interior = Group("Interior%d" % k, k)
        floor_groups[k] = floor
        interior_groups[k] = interior
        wall_groups[k] = walls
        # ---- facades of storey k
        for d in "SNEW":
            fac = Facade(d, W, D, k)
            ops = _openings(tpl, d, k)
            solid = []                                        # (u0, u1, hole, kind) for collision
            ci = 0
            while ci < len(fac.cells):
                a, b = fac.cells[ci]
                kind, spec = ops.get(ci, ("wall", None))
                span = 1
                if kind == "shop":
                    span = 2
                    b = fac.cells[ci + 1][1]
                if d in "SN":
                    if ci == 0:
                        a = fac.u0
                    if ci + span - 1 == len(fac.cells) - 1:
                        b = fac.u1
                # the opening is centred on the module, even when the E / W end cells are clipped by the corners
                cell_c = (-hw if d in "SN" else -hd) + GRID * ci + GRID * span / 2
                hole = None
                if kind != "wall":
                    hole = opening_of(kind, cell_c - GRID * span / 2, cell_c + GRID * span / 2, fac.z0)
                seed = ctx.seed + 10 * ci + ord(d) + 97 * k
                _wall(ctx, fac, walls[d], a, b, kind, hole, False, seed)
                _wall(ctx, fac, stubs[d], a, b, kind, hole, True, seed)
                if k == 0:
                    foundation_module(ctx, floor, fac, a, b)
                solid.append((a, b, hole, kind))
                if kind == "door":
                    door_specs.append((fac, hole, spec))
                ci += span
            door_holes = [h for (_a, _b, h, kd) in solid if kd == "door"]
            facade_bands(fac, walls[d], s, door_holes, stub=False)
            facade_bands(fac, stubs[d], s, door_holes, stub=True)
            if d in "SN":
                for end in (-1, 1):
                    corner_module(ctx, fac, walls[d], end, False)
                    corner_module(ctx, fac, stubs[d], end, True)
            for aw in tpl.get("awnings", []):
                if aw["dir"] == d and _floor_spec(aw) == k:
                    awning(ctx, walls[d], fac, aw, ctx.seed + 300 + int(float(aw["from"]) * 10))
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
        # ---- floor field (storey 0) / slab with the stair openings (storeys >= 1)
        if k == 0:
            for i in range(int(W / GRID)):
                for j in range(int(D / GRID)):
                    floor_module(ctx, floor, -hw + GRID * i, -hd + GRID * j, FOUND)
            summary["col"]["ColFloor0"] = ((-hw - T2, -hd - T2, 0.0), (hw + T2, hd + T2, FOUND))
        else:
            for n, (mn, mx) in enumerate(floor_slab(ctx, floor, k, openings.get(k, []))):
                summary["col"]["ColFloor%d_%d" % (k, n)] = (mn, mx)
        # ---- interior partitions
        z0 = FOUND + k * STOREY
        icol = []
        for pi, p in enumerate([p for p in tpl.get("partitions", []) if _floor_spec(p) == k]):
            holes = partition(ctx, interior, p["axis"], p["at"], p["from"], p["to"], p.get("doors", []), z0)
            line = (-hd if p["axis"] == "x" else -hw) + GRID * p["at"]
            a = (-hw if p["axis"] == "x" else -hd) + GRID * p["from"]
            b = (-hw if p["axis"] == "x" else -hd) + GRID * (p["to"] + 1)
            a, b = max(a, (-hw if p["axis"] == "x" else -hd) + T2), min(b, (hw if p["axis"] == "x" else hd) - T2)
            spans = []
            cur = a
            for h in sorted(holes):
                spans.append((cur, h[0], z0, z0 + WALL_H))
                spans.append((h[0], h[1], h[3], z0 + WALL_H))
                cur = h[1]
            spans.append((cur, b, z0, z0 + WALL_H))
            for si, (u0, u1, zz0, zz1) in enumerate(spans):
                t = IWALL_T / 2
                if p["axis"] == "x":
                    icol.append(("ColIWalls%d_%d_%d" % (k, pi, si), (u0, line - t, zz0), (u1, line + t, zz1)))
                else:
                    icol.append(("ColIWalls%d_%d_%d" % (k, pi, si), (line - t, u0, zz0), (line + t, u1, zz1)))
            for h in holes:
                door_specs.append(("iwall", (h[0], h[1], line, p["axis"], k), {"kind": "door", "exterior": False}))
        for name, mn, mx in icol:
            summary["col"][name] = (mn, mx)
        # ---- decorative furniture (+ its collision box) and the merged visuals of the furniture spawns
        nf = 0
        for f in tpl.get("furniture", []):
            if _floor_spec(f) == k:
                fx, fy = -hw + f["pos"][0], -hd + f["pos"][1]
                furniture(ctx, interior, f["kind"], fx, fy, f.get("yaw", 0.0), z0)
                if f["kind"] not in NO_COLLISION:
                    half, h = FURNITURE_EXTENTS[f["kind"]]
                    summary["col"]["ColFurn%d_%d" % (k, nf)] = _furniture_box(ctx, fx, fy, f.get("yaw", 0.0), z0, half, h)
                    nf += 1
        for sp in tpl.get("spawns", []):
            model = sp.get("furniture") if sp["kind"] == "Furniture" else SPAWN_VISUALS.get(sp["kind"])
            if _floor_spec(sp) == k and model:
                pos = sp["pos"]
                zz = (pos[2] if len(pos) > 2 else 0.0) + z0
                bb = furniture_model(ctx, interior, model, -hw + pos[0], -hd + pos[1], zz, sp.get("yaw", 0.0))
                if model not in NO_COLLISION:
                    summary["col"]["ColFurn%d_%d" % (k, nf)] = ((round(bb[0][0], 4), round(bb[0][1], 4), zz),
                                                                (round(bb[1][0], 4), round(bb[1][1], 4), round(bb[1][2], 4)))
                    nf += 1
        groups += [floor] + [walls[d] for d in "SNEW"] + [stubs[d] for d in "SNEW"] + [interior]
    # ---- stairs (Interior<k>) + balustrades round the openings (Interior<k+1>)
    rails = []
    for n, fl in enumerate(flights):
        ramps["ColStair%d_%d" % (fl.k, n)] = stair(ctx, interior_groups[fl.k], fl, rails)
        if fl.k + 1 < floors:
            balustrade(ctx, interior_groups[fl.k + 1], fl, summary["col"], fl.k)
    # ---- roof, chimney, porch, drifts
    rk = tpl.get("roof", {}).get("kind", "gable")
    if rk == "flat":
        flat_roof(ctx, roof, parapet_h=tpl.get("roof", {}).get("parapet", 0.9))
    else:
        gable_roof(ctx, roof, pitch=tpl.get("roof", {}).get("pitch", 35.0), over=tpl.get("roof", {}).get("overhang", 0.4))
    if tpl.get("chimney"):
        ci, cj = tpl["chimney"]["pos"]
        ox, oy = tpl["chimney"].get("offset", (0.0, 0.0))
        chimney(ctx, roof, -hw + GRID * ci + GRID / 2 + ox, -hd + GRID * cj + GRID / 2 + oy)
    front_door = next((spec for spec in door_specs if spec[0] != "iwall" and spec[2].get("exterior")), None)
    if tpl.get("porch"):
        du = (front_door[1][0] + front_door[1][1]) / 2 if front_door else 0.0
        porch(ctx, floor_groups[0], roof, tpl["porch"]["cells"], du)
    drifts(ctx, floor_groups[0])
    groups.append(roof)
    # ---- fuse groups
    objs = {}
    for g in groups:
        o = _assemble(g, 0.018 if g is roof else 0.012)
        if o is not None:
            objs[g.name] = o
            summary["groups"].append(g.name)
    for k in range(floors):
        objs["Floor%d" % k]["floor_z"] = FOUND + k * STOREY
    shadow_proxy(ctx, rk)
    summary["extra"].append("ShadowProxy")
    # ---- windows
    for n, (pane, cut_group, fl_) in enumerate(ctx.panes):
        w = H.flat(H.mk(pane, "Window_%d" % n))
        w["boarded"] = False
        w["cut_group"] = cut_group
        w["floor"] = fl_
        summary["windows"].append(w.name)
    # ---- doors (exterior first)
    doors = sorted(door_specs, key=lambda sp: 0 if sp[0] != "iwall" and sp[2].get("exterior") else 1)
    for n, (fac, hole, spec) in enumerate(doors):
        name = "Door_%d" % n
        if fac == "iwall":
            h0, h1, line, axis, kk = hole
            ifac = _IFacade(axis, line, kk)
            z0 = FOUND + kk * STOREY
            leaf = door_leaf(ifac, (h0, h1, z0, z0 + 2.1), s, name, False, "Interior%d" % kk, kk)
        else:
            leaf = door_leaf(fac, hole, s, name, spec.get("exterior", True), "Walls%d_%s" % (fac.k, fac.d), fac.k,
                             hinge=spec.get("hinge", "L"))
            leaf["kind"] = spec.get("kind", "door")
        summary["doors"].append(leaf.name)
    # ---- spawns (+ Spawn_Sign anchors on the facades)
    counts = {}

    def spawn(kind, pos, yaw, props):
        i = counts.get(kind, 0)
        counts[kind] = i + 1
        e = lp.add_empty("Spawn_%s_%d" % (kind, i), pos, rotation_deg=(0, 0, yaw), size=0.3)
        for key, v in props.items():
            e[key] = v
        e["kind"] = kind
        summary["spawns"].append(e.name)
    for sp in tpl.get("spawns", []):
        pos = sp["pos"]
        z = (pos[2] if len(pos) > 2 else 0.0) + FOUND + _floor_spec(sp) * STOREY
        spawn(sp["kind"], (-hw + pos[0], -hd + pos[1], z), sp.get("yaw", 0.0),
              {k2: sp[k2] for k2 in ("table", "furniture") if k2 in sp})
    for sg in tpl.get("signs", []):
        k = _floor_spec(sg)
        fac = Facade(sg["dir"], W, D, k)
        yaw = {"S": 0.0, "E": 90.0, "N": 180.0, "W": -90.0}[sg["dir"]]
        spawn("Sign", fac.p(float(sg["at"]), fac.z0 + float(sg.get("z", 2.1)), float(sg.get("d", 0.0))), yaw,
              {"sign": sg["kind"], "width": float(sg.get("width", 0.6)), "cap": float(sg.get("cap", 0.34)),
               "cut_group": sg.get("group", "Walls%d_%s" % (k, sg["dir"])), "floor": k})
    # ---- collision
    lp.collision_box("ColFloor0", *summary["col"]["ColFloor0"])
    for name, (mn, mx) in list(summary["col"].items()):
        if name != "ColFloor0":
            lp.collision_box(name, mn, mx)
    for name, (fac, u0, u1, z0, z1) in col.items():
        o = _col_box(name, fac, u0, u1, z0, z1)
        mn = [min(v.co[i] for v in o.data.vertices) for i in range(3)]
        mx = [max(v.co[i] for v in o.data.vertices) for i in range(3)]
        summary["col"][name] = (tuple(mn), tuple(mx))
    for name, pts in ramps.items():
        lp.collision_prism(name, [tuple(p) for p in pts], [(0, 1, 2), (3, 5, 4), (0, 3, 4, 1), (1, 4, 5, 2),
                                                            (0, 2, 5, 3)])
        mn = tuple(min(p[i] for p in pts) for i in range(3))
        mx = tuple(max(p[i] for p in pts) for i in range(3))
        summary["col"][name] = (mn, mx)
    for n, cs in enumerate(rails):
        mn = tuple(min(p[i] for p in cs) for i in range(3))
        mx = tuple(max(p[i] for p in cs) for i in range(3))
        name = "ColStairRail%d" % n
        lp.collision_box(name, mn, mx)
        summary["col"][name] = (mn, mx)
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
    summary["levels"] = [FOUND + STOREY * k for k in range(1, floors + 1)]
    summary["roof_z"] = ctx.roof_ridge
    return summary


class _IFacade(Facade):
    """Partition 'facade' used to place an interior door leaf: door_leaf() puts the leaf 0.10-0.15 m inside the
    outer face, so the fake outer face sits 0.125 m from the partition line -> the leaf is centred in the partition."""

    def __init__(self, axis, line, k=0):
        self.d, self.k = "I", k
        self.axis = axis
        self.sign = 1
        self.line = line + 0.125 - T2
        self.z0 = FOUND + k * STOREY
        self.zt = self.z0 + WALL_H


def _wall(ctx, fac, g, a, b, kind, hole, stub, seed):
    """One wall module (Wall_2 / Wall_Window_2 / Wall_Door_2 / Wall_Shop_4, or the _Stub version) over [a, b]."""
    s = ctx.style
    z0 = fac.z0
    zt = z0 + (STUB_H if stub else WALL_H)
    cut = hole if (hole is not None and hole[2] < zt) else None
    slab_boxes(fac, g.flat, a, b, z0, zt, cut, s)
    holes = []
    if cut is not None:
        m = 0.12 if kind in ("door", "shop") else (0.1 if s.finish == "lap" else 0.12)
        if kind == "shop":
            m = 0.18
        holes = [(cut[0] - m, cut[1] + m, cut[2] - (0.25 if kind == "window" else (0.1 if kind == "shop" else 0.0)),
                  min(zt, cut[3] + 0.2))]
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
    elif kind == "shop":
        shop_trim(fac, g, hole, s, seed, ctx.panes, g.name, fac.k)
