"""cabin_small (ASSET_SPEC_V2 §8.4 / §8.5 + "M3") -> assets/models/poi/cabin_small.glb: the isolated trapper's log
cabin of the deep forest (4 per map, PLAN §4.3), made by hand with the v2 cutaway structure.

    cd winter-survival/blender && python3 poi/build_cabin_small.py

Footprint 5 x 5 m (log walls, outer faces at +-2.5), floor top at +0.30, front = S = -Y (door), a 1.3 m deep front
porch under the roof overhang. Nodes (all top level):
  Floor0            stone sill, plank floor, porch deck + log posts + step, woodpile, snow drifts   (never hidden)
  Walls0_S/N/E/W    log walls (the S / N logs cross at the corners and carry every protruding corner log end)
  Walls0_*_Stub     the same walls cut at 0.6 m above the floor (two courses), same plan outline
  Interior0         plank table + stool + shelf with jars + pelt rug + firewood box (decorative, merged)
  Roof              gable roof (ridge along Y) with shingle courses, barge boards, gable ends, stovepipe, thick snow
                    slabs with cornice, lumps, icicles under the eaves
  Door_0            plank door leaf, origin on the hinge axis (left seen from outside), closed; extras kind=door,
                    exterior=true, cut_group=Walls0_S, floor=0
  Window_0..2       panes (material window, both faces): E, N, W; extras boarded=false, cut_group, floor
  DoorAnchor        on the porch in front of the door (0, -3.05, 0.30) (like the hunter cabin's DoorAnchor)
  Spawn_Stove_0, Spawn_Bed_0, Spawn_Container_0 (table "cabin_forest"), Spawn_Light_0, Spawn_Loot_0, Spawn_Zombie_0
  Col*-convcolonly  ColFloor0, ColPorch, ColSteps (ramp), ColWalls0_S_0..2 (door open), ColWalls0_N_0,
                    ColWalls0_E_0, ColWalls0_W_0, ColPostL, ColPostR, ColWoodpile (windows are 0.8 x 0.7: solid)
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import bpy  # noqa: E402,F401  (must precede mathutils)
from mathutils import Vector  # noqa: E402

from lib import export  # noqa: E402
from lib import hd as H  # noqa: E402
from lib import kit  # noqa: E402
from lib import lowpoly as lp  # noqa: E402
from lib import veg as V  # noqa: E402
from props.build_icicles import icicle_strip  # noqa: E402

F = 0.30              # floor top
HALF = 2.5            # outer faces
CL = 2.37             # log centre lines
LR = 0.115            # log radius
STEP = 0.25           # course spacing
SLAB = 0.07           # half thickness of the chinking / plank slab behind the logs
NS_COURSES = [F + 0.12 + k * STEP for k in range(10)]            # S / N log centres
EW_COURSES = [F + 0.12 + STEP / 2 + k * STEP for k in range(9)]  # E / W log centres (half a course up)
TOP = NS_COURSES[-1] + LR                                          # wall plate
END = 0.26            # corner log ends stick out
DOOR = (-0.5, 0.5, F, F + 2.0)                                     # u0, u1, z0, z1 (S wall)
WINDOWS = {"E": (-0.4, 0.4, F + 1.0, F + 1.7), "W": (0.2, 1.0, F + 1.0, F + 1.7), "N": (-1.4, -0.8, F + 1.15, F + 1.65)}
PITCH = 38.0
RT = 0.14
EAVE_X = HALF + 0.5
Y_FRONT, Y_BACK = -HALF - 1.55, HALF + 0.45
STUB_Z = F + kit.STUB_H


class Wall:
    """Log wall `d`: axis u along X (S / N) or Y (E / W), centre line at +-CL."""

    def __init__(self, d):
        self.d = d
        self.sign = -1 if d in "SW" else 1
        self.axis = "x" if d in "SN" else "y"

    def p(self, u, z, off=0.0):
        """Point at u along the wall, height z, `off` outward from the centre line."""
        w = self.sign * (CL + off)
        return Vector((u, w, z)) if self.axis == "x" else Vector((w, u, z))

    @property
    def n(self):
        return Vector((0, self.sign, 0)) if self.axis == "x" else Vector((self.sign, 0, 0))

    @property
    def udir(self):
        return Vector((1, 0, 0)) if self.axis == "x" else Vector((0, 1, 0))


def log(mb, a, b, r, sides=8, caps=(False, False), rnd=None, mat="wood"):
    """Straight smooth log from a to b (weathered `wood`), optional sawn ends (bark rim + light wood) or "flat"
    dark ends (E / W log ends inside the corner crossing, only seen when an S / N wall is stubbed)."""
    a, b = Vector(a), Vector(b)
    d = b - a
    ph = rnd.uniform(0, 45) if rnd else 0.0
    ra = lp.ring(a, d, r * (rnd.uniform(0.95, 1.05) if rnd else 1.0), sides, ph)
    rb = lp.ring(b, d, r * (rnd.uniform(0.95, 1.05) if rnd else 1.0), sides, ph)
    mb.loft([ra, rb], mat, cap_start=False, cap_end=False)
    for flag, ring_, c, nrm in ((caps[0], ra, a, -d), (caps[1], rb, b, d)):
        if flag == "flat":                                  # hidden-by-default end (exposed only in the cutaway)
            mb.loft([ring_, [c]], "wood_dark", cap_start=False, cap_end=False, seg_facing=[nrm])
        elif flag:
            inner = [c + (p - c) * 0.8 + nrm.normalized() * 0.004 for p in ring_]
            mb.loft([ring_, inner], "bark", cap_start=False, cap_end=False, seg_facing=[nrm])
            mb.loft([inner, [c + nrm.normalized() * 0.004]], "wood_light", cap_start=False, cap_end=False,
                    seg_facing=[nrm])


def cut_spans(u0, u1, z, hole, margin=0.0):
    """Split [u0, u1] at `hole` (u0, u1, z0, z1) when the course at height z crosses it."""
    if hole is None or not (hole[2] - LR * 0.6 < z < hole[3] + LR * 0.6):
        return [(u0, u1, False, False)]
    out = []
    if hole[0] - margin > u0:
        out.append((u0, hole[0] - margin, False, True))
    if u1 > hole[1] + margin:
        out.append((hole[1] + margin, u1, True, False))
    return out


def build_wall(d, g, stub, rnd):
    """Logs + chinking slab (+ corner ends for S / N) of wall d into group g."""
    w = Wall(d)
    hole = DOOR if d == "S" else WINDOWS.get(d)
    zmax = STUB_Z if stub else 99.0
    smooth = lp.MeshBuilder()
    if d in "SN":
        courses, u0, u1 = NS_COURSES, -CL - LR - END, CL + LR + END
    else:
        courses, u0, u1 = EW_COURSES, -CL, CL
    for z in courses:
        if z > zmax:
            break
        for a, b, cap_a, cap_b in cut_spans(u0, u1, z, hole, 0.0):
            end_a = (d in "SN" and a <= u0 + 1e-6) or ("flat" if d in "EW" and a <= u0 + 1e-6 else False)
            end_b = (d in "SN" and b >= u1 - 1e-6) or ("flat" if d in "EW" and b >= u1 - 1e-6 else False)
            log(smooth, w.p(a, z), w.p(b, z), LR, caps=(cap_a or end_a, cap_b or end_b), rnd=rnd)
    if d in "SN":
        # the E / W logs' protruding corner ends belong to the S / N group (§8.6)
        for z in EW_COURSES:
            if z > zmax:
                break
            for sx in (-1, 1):
                a = Vector((sx * CL, w.sign * CL, z))
                b = Vector((sx * CL, w.sign * (CL + LR + END), z))
                log(smooth, a, b, LR, caps=(False, True), rnd=rnd)
    g.smooth.append(H.smooth(H.mk(smooth), angle=60))
    # chinking (outside, plaster) / planks (inside, wood) slab between the log centre planes
    top = (max(z for z in courses if z <= zmax) + LR) if stub else TOP
    ua, ub = (-CL, CL) if d in "SN" else (-CL + SLAB, CL - SLAB)
    pieces = [(ua, ub, F, top)]
    if hole is not None and hole[2] < top:
        pieces = [(ua, hole[0], F, top), (hole[1], ub, F, top)]
        if hole[2] > F:
            pieces.append((hole[0], hole[1], F, hole[2]))
        if hole[3] < top:
            pieces.append((hole[0], hole[1], hole[3], top))
    out_key = ("+y" if w.sign > 0 else "-y") if w.axis == "x" else ("+x" if w.sign > 0 else "-x")
    in_key = ("-" if out_key[0] == "+" else "+") + out_key[1]
    for a, b, z0, z1 in pieces:
        if b - a < 1e-3 or z1 - z0 < 1e-3:
            continue
        pa, pb = w.p(a, z0, -SLAB), w.p(b, z1, SLAB)
        g.flat.box((min(pa.x, pb.x), min(pa.y, pb.y), z0), (max(pa.x, pb.x), max(pa.y, pb.y), z1), "plaster",
                   mats={out_key: "plaster", in_key: "wood"})
    if stub:
        pa, pb = w.p(ua if d in "SN" else -CL, top, -LR), w.p(ub if d in "SN" else CL, top + 0.03, LR)
        spans = [(min(pa.x, pb.x), max(pa.x, pb.x), min(pa.y, pb.y), max(pa.y, pb.y))]
        if hole is not None and hole[2] < top:
            if w.axis == "x":
                spans = [(spans[0][0], hole[0], spans[0][2], spans[0][3]), (hole[1], spans[0][1], spans[0][2], spans[0][3])]
            else:
                spans = [(spans[0][0], spans[0][1], spans[0][2], hole[0]), (spans[0][0], spans[0][1], hole[1], spans[0][3])]
        for x0, x1, y0, y1 in spans:
            if x1 - x0 > 0.02 and y1 - y0 > 0.02:
                g.hard.box((x0, y0, top), (x1, y1, top + 0.03), "wood")
        return
    if d == "S":
        door_frame(w, g)
    elif hole is not None:
        window(w, g, hole, rnd)


def door_frame(w, g):
    u0, u1, z0, z1 = DOOR
    for a, b in ((u0 - 0.12, u0), (u1, u1 + 0.12)):
        pa, pb = w.p(a, z0, -SLAB - 0.02), w.p(b, z1 + 0.12, LR + 0.02)
        g.hard.box((min(pa.x, pb.x), min(pa.y, pb.y), z0), (max(pa.x, pb.x), max(pa.y, pb.y), z1 + 0.12), "wood")
    pa, pb = w.p(u0 - 0.2, z1, -SLAB - 0.02), w.p(u1 + 0.2, z1 + 0.16, LR + 0.04)
    g.hard.box((min(pa.x, pb.x), min(pa.y, pb.y), z1), (max(pa.x, pb.x), max(pa.y, pb.y), z1 + 0.16), "wood")
    # antler trophy above the door (the trapper's sign)
    c = w.p(0.0, z1 + 0.45, LR + 0.02)
    g.hard.box(c - Vector((0.12, 0.04, 0.1)), c + Vector((0.12, 0.04, 0.1)), "wood_dark")
    for sx in (-1, 1):
        H.tube(g.flat, [c + Vector((sx * 0.06, -0.05, 0.02)), c + Vector((sx * 0.22, -0.1, 0.16)),
                        c + Vector((sx * 0.3, -0.12, 0.34))], [0.022, 0.016, 0.01], 4, "fur", cap_end=True)
        H.tube(g.flat, [c + Vector((sx * 0.2, -0.1, 0.14)), c + Vector((sx * 0.16, -0.14, 0.3))], [0.014, 0.008], 4,
               "fur", cap_end=True)


def window(w, g, hole, rnd):
    u0, u1, z0, z1 = hole
    fr = 0.08
    for a, b, c, e in ((u0 - fr, u0, z0 - fr, z1 + fr), (u1, u1 + fr, z0 - fr, z1 + fr), (u0, u1, z1, z1 + fr)):
        pa, pb = w.p(a, c, -SLAB - 0.02), w.p(b, e, LR + 0.03)
        g.hard.box((min(pa.x, pb.x), min(pa.y, pb.y), c), (max(pa.x, pb.x), max(pa.y, pb.y), e), "wood_light")
    pa, pb = w.p(u0 - fr - 0.05, z0 - fr - 0.05, -SLAB - 0.02), w.p(u1 + fr + 0.05, z0 - fr + 0.0, LR + 0.12)
    g.hard.box((min(pa.x, pb.x), min(pa.y, pb.y), z0 - fr - 0.05), (max(pa.x, pb.x), max(pa.y, pb.y), z0 - fr),
               "wood_light")
    g.snow.append(H.snow_ridge(w.p(u0 - fr - 0.03, z0 - fr, LR + 0.06), w.p(u1 + fr + 0.03, z0 - fr, LR + 0.06), 0.11,
                               0.06, seed=int(u0 * 10) + 3, overhang=0.0, droop=0.02))
    # cross mullion
    um, zm = (u0 + u1) / 2, (z0 + z1) / 2
    for a, b, c, e in ((um - 0.02, um + 0.02, z0, z1), (u0, u1, zm - 0.02, zm + 0.02)):
        pa, pb = w.p(a, c, -0.02), w.p(b, e, 0.01)
        g.flat.box((min(pa.x, pb.x), min(pa.y, pb.y), c), (max(pa.x, pb.x), max(pa.y, pb.y), e), "wood_light")
    # shutters, open against the logs
    sw = (u1 - u0) / 2
    for sgn, edge in ((-1, u0 - fr), (1, u1 + fr)):
        a, b = sorted((edge, edge + sgn * sw))
        pa, pb = w.p(a, z0 - 0.04, LR + 0.01), w.p(b, z1 + 0.04, LR + 0.05)
        g.hard.box((min(pa.x, pb.x), min(pa.y, pb.y), z0 - 0.04), (max(pa.x, pb.x), max(pa.y, pb.y), z1 + 0.04),
                   "wood_dark")
        for zz in (z0 + 0.1, z1 - 0.1):
            pa, pb = w.p(a + 0.02, zz - 0.03, LR + 0.05), w.p(b - 0.02, zz + 0.03, LR + 0.07)
            g.flat.box((min(pa.x, pb.x), min(pa.y, pb.y), zz - 0.03), (max(pa.x, pb.x), max(pa.y, pb.y), zz + 0.03),
                       "wood", skip=("-z",))


# ------------------------------------------------------------------------------------------------------------
def z_under(x):
    return TOP + (CL + LR - abs(x)) * math.tan(math.radians(PITCH))


def build_roof(g, rnd):
    t = math.tan(math.radians(PITCH))
    dz = RT / math.cos(math.radians(PITCH))
    ridge = z_under(0.0)
    xo = EAVE_X
    for sg in (-1, 1):
        n = Vector((sg * t, 0, 1)).normalized()
        prof = [Vector((0, Y_FRONT, ridge)), Vector((sg * xo, Y_FRONT, z_under(xo))),
                Vector((sg * xo, Y_FRONT, z_under(xo) + dz)), Vector((0, Y_FRONT, ridge + dz))]
        g.hard.prism(prof, (0, Y_FRONT, 0), (0, Y_BACK, 0), "wood_dark")
        # shingle courses (saw-tooth sheet), a few darker / lighter rows
        x = xo - 0.01
        k = 0
        while x > 0.25:
            xu = max(x - 0.26, 0.06)
            lo = Vector((sg * x, 0, z_under(x) + dz)) + n * 0.03
            hi = Vector((sg * xu, 0, z_under(xu) + dz)) + n * 0.004
            mat = "bark" if k % 4 == 1 else ("roof" if k % 5 == 3 else "wood_dark")
            g.flat.poly([lo + Vector((0, Y_FRONT, 0)), lo + Vector((0, Y_BACK, 0)), hi + Vector((0, Y_BACK, 0)),
                         hi + Vector((0, Y_FRONT, 0))], mat, facing=n)
            base = Vector((sg * x, 0, z_under(x) + dz))                            # butt edge (faces down-slope)
            g.flat.poly([base + Vector((0, Y_FRONT, 0)), base + Vector((0, Y_BACK, 0)), lo + Vector((0, Y_BACK, 0)),
                         lo + Vector((0, Y_FRONT, 0))], "wood_dark", facing=Vector((sg, 0, -t)))
            x = xu
            k += 1
        # fascia
        a_, b_ = sorted((sg * xo, sg * (xo + 0.04)))
        g.hard.box((a_, Y_FRONT, z_under(xo) - 0.09), (b_, Y_BACK, z_under(xo) + dz + 0.01), "wood")
        # rafters visible under the porch overhang
        for yy in (-3.4, -2.9):
            H.beam(g.hard, (sg * 0.05, yy, ridge - 0.05), (sg * (xo - 0.05), yy, z_under(xo - 0.05) - 0.02), 0.08, 0.1,
                   "wood", up=(sg * t, 0, 1))
    g.hard.prism([Vector((-0.12, Y_FRONT, ridge + dz - 0.02)), Vector((0.12, Y_FRONT, ridge + dz - 0.02)),
                  Vector((0.0, Y_FRONT, ridge + dz + 0.06))], (0, Y_FRONT, 0), (0, Y_BACK, 0), "wood")      # ridge
    # gable ends: vertical boards + battens, barge boards
    for sgy, yw in ((-1, -CL - LR), (1, CL + LR)):
        prof = [Vector((-CL - LR, yw, TOP - 0.05)), Vector((CL + LR, yw, TOP - 0.05)), Vector((0, yw, ridge))]
        g.flat.prism(prof, (0, yw, 0), (0, yw - sgy * 0.12, 0), "wood")
        xx = -CL
        while xx < CL:
            ztop = ridge - abs(xx) * t - 0.06
            if ztop > TOP + 0.1:
                g.flat.box((xx - 0.025, min(yw, yw + sgy * 0.025), TOP), (xx + 0.025, max(yw, yw + sgy * 0.025), ztop),
                           "wood_dark", skip=("-z",))
            xx += 0.3
        yb = Y_FRONT if sgy < 0 else Y_BACK
        for sg in (-1, 1):
            cs = []
            for i in range(8):
                far = bool(i & 2)
                x_ = 0.0 if far else sg * (xo + 0.02)
                z_ = (ridge if far else z_under(xo + 0.02)) + (dz + 0.03 if i & 4 else -0.13)
                y_ = yb + sgy * (0.04 if i & 1 else -0.02)
                cs.append((x_, y_, z_))
            g.hard.hexa(cs, "wood")
    # stovepipe through the W slope (above Spawn_Stove_0)
    px, py = -1.55, 1.45
    zb = z_under(px) + dz - 0.05
    H.tube(g.flat, [(px, py, zb - 0.3), (px, py, zb + 0.9)], [0.08, 0.08], 8, "iron", cap_end=False)
    g.flat.cylinder((px, py, zb + 0.9), (px, py, zb + 0.96), 0.15, 0.15, 8, "iron")
    g.flat.loft([lp.ring((px, py, zb + 0.96), (0, 0, 1), 0.15, 8), [Vector((px, py, zb + 1.08))]], "iron",
                cap_start=True, cap_end=False)
    # snow slabs + lumps + icicles
    slope_len = xo / math.cos(math.radians(PITCH))
    for sg in (-1, 1):
        Vv = Vector((-sg * math.cos(math.radians(PITCH)), 0, math.sin(math.radians(PITCH))))
        N = Vector((sg * math.sin(math.radians(PITCH)), 0, math.cos(math.radians(PITCH))))
        E = Vector((sg * xo, Y_FRONT + 0.06, z_under(xo) + dz))
        ov = 0.13
        size_u = (Y_BACK - Y_FRONT) - 0.12
        size_v = ov + slope_len * (0.76 if sg > 0 else 0.84)
        seed = 7 + sg

        def lip(u, v, ov=ov, size_v=size_v, seed=seed, size_u=size_u):
            dn = -0.10 * H.smoothstep(ov + 0.10, 0.0, v) - 0.05 * H.smoothstep(0.14, 0.0, min(u, size_u - u))
            dv = 0.35 * H.fbm(u * 0.8, seed * 1.3, 2, seed) if v >= size_v - 1e-6 else 0.0
            return (0.0, dv, dn)
        g.snow.append(H.pillow(E - Vv * ov, Vector((0, 1, 0)), Vv, N, size_u, size_v, 0.24, nu=6, nv=4, rim=0.16,
                               seed=seed, lip=lip, bumps=0.04, levels=1, bottom=-0.09))
        x = xo * 0.1
        base = Vector((sg * x, -0.4 + sg * 1.1, z_under(x) + dz))
        g.snow.append(H.pillow(base - Vector((0, 0.4, 0)) - Vv * 0.22, Vector((0, 1, 0)), Vv, N, 0.8, 0.44, 0.13, nu=3,
                               nv=3, rim=0.12, seed=seed + 20, jitter=0.03, levels=1))
        xi = sg * (xo + 0.03)
        zi = z_under(xo) - 0.09
        ya = -1.8 if sg > 0 else 0.2
        g.smooth += icicle_strip((xi, ya, zi), (xi, ya + 1.6, zi), seed=50 + sg, max_len=0.4, spacing=0.15, ridge=False)
    # snow ring around the stovepipe
    g.snow.append(H.mound((px, py, zb - 0.02), 0.28, 0.08, seed=61, sides=8, rings=2, sink=0.03))


def build_floor(g, rnd):
    # stone sill under the walls, plank floor, porch
    g.hard.box((-HALF - 0.04, -HALF - 0.04, -0.05), (HALF + 0.04, HALF + 0.04, F - 0.02), "stone", skip=("-z",))
    n, gap = 11, 0.012
    pw = (2 * (CL - SLAB) - (n - 1) * gap) / n
    for k in range(n):
        x0 = -CL + SLAB + k * (pw + gap)
        g.flat.box((x0, -CL + SLAB, F - 0.02), (x0 + pw, CL - SLAB, F), "wood" if k % 3 else "wood_light",
                   skip=("-z",))
    # porch deck (in front of the S wall) + rim + step
    y0, y1 = -3.85, -HALF
    g.flat.box((-2.35, y0, 0.0), (2.35, y1, F - 0.06), "wood_dark", skip=("-z", "+y"))
    nb = 7
    bw = (y1 - y0 - (nb - 1) * 0.02) / nb
    for k in range(nb):
        yy = y0 + k * (bw + 0.02)
        g.flat.box((-2.33, yy, F - 0.06), (2.33, yy + bw, F), "wood", skip=("-z",))
    log(g.flat, (-0.8, y0 - 0.2, 0.1), (0.8, y0 - 0.2, 0.1), 0.12, caps=(True, True), rnd=rnd)          # log step
    # porch posts (logs) up to the roof
    for sx in (-1, 1):
        x = sx * 2.15
        zt = z_under(x) - 0.02
        H.tube(g.flat, [(x, -3.65, F), (x, -3.65, zt)], [0.1, 0.09], 8, "bark", cap_end=True)
    # woodpile against the S wall, left of the door (split logs: light ends toward the camera)
    x0, x1 = -2.25, -0.85
    g.hard.box((x0, -2.95, F), (x1, -HALF, F + 0.95), "bark")
    for row in range(4):
        for k in range(6):
            cx = x0 + 0.12 + k * 0.23 + (0.1 if row % 2 else 0.0)
            if cx > x1 - 0.1:
                continue
            cz = F + 0.12 + row * 0.22
            g.flat.loft([lp.ring((cx, -2.955, cz), (0, -1, 0), 0.1, 5, rnd.uniform(0, 70)), [Vector((cx, -2.96, cz))]],
                        "wood_light" if (row + k) % 3 else "wood", cap_start=False, cap_end=False, seg_facing=[(0, -1, 0)])
    g.snow.append(H.pillow((x0 - 0.03, -2.98, F + 0.95), (1, 0, 0), (0, 1, 0), (0, 0, 1), x1 - x0 + 0.06, 0.34, 0.08,
                           nu=4, nv=3, rim=0.08, seed=31, levels=1))
    # snow: drifts on N and W walls, piles at the porch corners and beside the step
    specs = [((-HALF - 0.5, HALF + 0.02, 0.0), (1, 0, 0), (0, 1, 0), 2 * HALF + 1.0, 1.0, 0.62),
             ((-HALF - 0.02, HALF + 0.3, 0.0), (0, -1, 0), (-1, 0, 0), 2 * HALF + 0.3, 0.9, 0.55),
             ((HALF + 0.02, HALF - 1.9, 0.0), (0, -1, 0), (1, 0, 0), 2.6, 0.75, 0.35)]
    for k, (o, U, Vv, L, D, Hh) in enumerate(specs):
        def top(u, v, D=D, Hh=Hh, k=k, L=L):
            tt = max(0.0, 1.0 - v / D)
            end = H.smoothstep(0.0, 1.1, min(u, L - u))
            return 0.02 + Hh * (tt ** 0.75) * (0.06 + 0.94 * end) * (1 + 0.15 * H.fbm(u * 0.8, k, 2, k))
        g.snow.append(H.pillow(Vector(o) - Vector(Vv) * 0.12, U, Vv, (0, 0, 1), L, D + 0.12, Hh, nu=6, nv=4, rim=0.25,
                               seed=40 + k, top_fn=top, jitter=0.05, bottom=-0.05, levels=1))
    for k, (x, y, rx, ry, h) in enumerate(((-1.75, y0 - 0.25, 0.75, 0.5, 0.32), (1.75, y0 - 0.3, 0.7, 0.5, 0.3),
                                           (2.7, -2.9, 0.45, 0.6, 0.26))):
        g.snow.append(V.heap((x, y, 0.0), rx, ry, h, seed=45 + k, sides=12, rings=3, sink=0.05, noise=0.1, yaw=15 * k))
    g.snow.append(H.pillow((1.4, -3.8, F), (1, 0, 0), (0, 1, 0), (0, 0, 1), 0.9, 0.6, 0.08, nu=3, nv=3, rim=0.1,
                           seed=48, levels=1))


def build_interior(g, rnd):
    # table + stool, shelf with jars on the N wall, pelt rug, firewood box by the stove
    g.hard.box((-1.2, -1.25, F + 0.72), (-0.1, -0.6, F + 0.77), "wood")
    for sx in (-1.1, -0.2):
        for sy in (-1.18, -0.67):
            g.flat.box((sx - 0.03, sy - 0.03, F), (sx + 0.03, sy + 0.03, F + 0.72), "wood_dark")
    g.hard.box((-0.9, -0.2, F + 0.42), (-0.55, 0.12, F + 0.46), "wood")
    for sx in (-0.86, -0.59):
        g.flat.box((sx - 0.02, -0.16, F), (sx + 0.02, 0.08, F + 0.42), "wood_dark")
    g.hard.box((-1.3, CL - SLAB - 0.28, F + 1.35), (0.1, CL - SLAB, F + 1.39), "wood")
    for k in range(5):
        x = -1.2 + k * 0.28
        g.flat.cylinder((x, CL - SLAB - 0.14, F + 1.39), (x, CL - SLAB - 0.14, F + 1.39 + rnd.uniform(0.12, 0.2)),
                        0.05, 0.045, 6, "paper" if k % 2 else "stone", cap1=True)
    g.flat.poly([(-0.6, -0.4, F + 0.004), (0.7, -0.5, F + 0.004), (0.8, 0.5, F + 0.004), (-0.5, 0.6, F + 0.004)], "fur",
                facing=(0, 0, 1))
    g.hard.box((-CL + SLAB, 0.45, F), (-CL + SLAB + 0.45, 0.9, F + 0.4), "wood_dark")
    for k in range(3):
        log(g.flat, (-CL + SLAB + 0.05, 0.5 + k * 0.13, F + 0.46), (-CL + SLAB + 0.42, 0.5 + k * 0.13, F + 0.46), 0.055,
            caps=(False, True), rnd=rnd)


COL_BOXES = {
    "ColFloor0": ((-HALF, -HALF, 0.0), (HALF, HALF, F)),
    "ColPorch": ((-2.35, -3.85, 0.0), (2.35, -HALF, F)),
    "ColWalls0_S_0": ((-HALF, -HALF, F), (DOOR[0], -CL + SLAB + 0.05, TOP)),
    "ColWalls0_S_1": ((DOOR[0], -HALF, DOOR[3]), (DOOR[1], -CL + SLAB + 0.05, TOP)),
    "ColWalls0_S_2": ((DOOR[1], -HALF, F), (HALF, -CL + SLAB + 0.05, TOP)),
    "ColWalls0_N_0": ((-HALF, CL - SLAB - 0.05, F), (HALF, HALF, TOP)),
    "ColWalls0_E_0": ((CL - SLAB - 0.05, -CL + SLAB + 0.05, F), (HALF, CL - SLAB - 0.05, TOP)),
    "ColWalls0_W_0": ((-HALF, -CL + SLAB + 0.05, F), (-CL + SLAB + 0.05, CL - SLAB - 0.05, TOP)),
    "ColPostL": ((-2.25, -3.75, F), (-2.05, -3.55, 2.6)),
    "ColPostR": ((2.05, -3.75, F), (2.25, -3.55, 2.6)),
    "ColWoodpile": ((-2.25, -2.95, F), (-0.85, -HALF, F + 0.95)),
    "ColSteps": ((-0.8, -4.25, 0.0), (0.8, -3.85, F)),          # ramp (6-vertex wedge), bounds
}


def build_collision():
    for name, (mn, mx) in COL_BOXES.items():
        if name != "ColSteps":
            lp.collision_box(name, mn, mx)
    pts = [(-0.8, -4.25, 0.0), (-0.8, -3.85, 0.0), (-0.8, -3.85, F), (0.8, -4.25, 0.0), (0.8, -3.85, 0.0),
           (0.8, -3.85, F)]
    lp.collision_prism("ColSteps", pts, [(0, 1, 2), (3, 5, 4), (0, 3, 4, 1), (1, 4, 5, 2), (0, 2, 5, 3)])


def door_leaf():
    """Plank door (Z-braced) closed in the S opening, origin on the hinge axis (left seen from outside = -X)."""
    u0, u1, z0, z1 = DOOR
    y = -CL - 0.02
    mb, fl = lp.MeshBuilder(), lp.MeshBuilder()
    mb.box((u0 + 0.02, y - 0.03, z0 + 0.01), (u1 - 0.02, y + 0.03, z1 - 0.01), "wood_dark")
    for zz in (z0 + 0.3, z1 - 0.3):
        fl.box((u0 + 0.06, y - 0.05, zz - 0.06), (u1 - 0.06, y - 0.03, zz + 0.06), "wood", skip=("+y",))
    H.beam(fl, (u0 + 0.12, y - 0.04, z0 + 0.36), (u1 - 0.12, y - 0.04, z1 - 0.36), 0.1, 0.02, "wood", up=(0, -1, 0))
    for k in range(4):
        x = u0 + 0.02 + (k + 1) * (u1 - u0 - 0.04) / 5
        fl.poly([(x - 0.006, y - 0.0305, z0 + 0.02), (x + 0.006, y - 0.0305, z0 + 0.02), (x + 0.006, y - 0.0305, z1 - 0.02),
                 (x - 0.006, y - 0.0305, z1 - 0.02)], "iron", facing=(0, -1, 0))
    fl.box((u1 - 0.14, y - 0.07, z0 + 0.95), (u1 - 0.1, y - 0.03, z0 + 1.08), "iron", skip=("+y",))
    pivot = (u0 + 0.02, y, z0)
    o = H.mk(mb, None, pivot)
    H.bevel(o, 0.01, 1, angle=30)
    H.snap_colors(o)
    leaf = H.join([o, H.flat(H.mk(fl, None, pivot))], "Door_0")
    leaf["kind"] = "door"
    leaf["exterior"] = True
    leaf["cut_group"] = "Walls0_S"
    leaf["floor"] = 0
    leaf["hinge"] = "L"
    leaf["width"] = round(u1 - u0, 3)
    return leaf


def build_cabin_small():
    lp.new_scene()
    rnd = random.Random(17)
    groups = []
    floor = kit.Group("Floor0", 0)
    build_floor(floor, rnd)
    groups.append(floor)
    panes = []
    for d in "SNEW":
        g = kit.Group("Walls0_%s" % d, 0)
        build_wall(d, g, False, rnd)
        gs = kit.Group("Walls0_%s_Stub" % d, 0)
        build_wall(d, gs, True, rnd)
        groups += [g, gs]
        hole = WINDOWS.get(d)
        if hole is not None:
            panes.append((d, window_pane(d, hole)))
    interior = kit.Group("Interior0", 0)
    build_interior(interior, rnd)
    roof = kit.Group("Roof", 1)
    build_roof(roof, rnd)
    groups += [interior, roof]
    for g in groups:
        kit._assemble(g, 0.018 if g is roof else 0.012)
    bpy.data.objects["Floor0"]["floor_z"] = F
    for n, (d, pmb) in enumerate(sorted(panes, key=lambda x: "ENW".index(x[0]))):
        w = H.flat(H.mk(pmb, "Window_%d" % n))
        w["boarded"] = False
        w["cut_group"] = "Walls0_%s" % d
        w["floor"] = 0
    door_leaf()
    lp.add_empty("DoorAnchor", (0.0, -3.05, F))
    spawns = [("Spawn_Stove_0", (-1.55, 1.45, F), 90, {}), ("Spawn_Bed_0", (1.45, 1.2, F), 0, {}),
              ("Spawn_Container_0", (1.95, -1.2, F), -90, {"table": "cabin_forest"}),
              ("Spawn_Light_0", (0.0, 0.0, F + 2.35), 0, {}), ("Spawn_Loot_0", (-0.65, -0.92, F + 0.77), 0, {}),
              ("Spawn_Zombie_0", (0.3, 0.3, F), 200, {})]
    for name, pos, yaw, props in spawns:
        e = lp.add_empty(name, pos, rotation_deg=(0, 0, yaw), size=0.3)
        e["kind"] = name.split("_")[1]
        for k, v in props.items():
            e[k] = v
    build_collision()
    kit.bake_cut_ao(distance=1.2, samples=64)
    export.save_and_export("cabin_small", subdir="poi", ao=dict(distance=1.2, samples=64, ground=True),
                           import_kind="prop")


def window_pane(d, hole):
    w = Wall(d)
    u0, u1, z0, z1 = hole
    pane = lp.MeshBuilder()
    for off, f in ((-0.005, w.n), (-0.009, -w.n)):
        pane.poly([w.p(u0, z0, off), w.p(u1, z0, off), w.p(u1, z1, off), w.p(u0, z1, off)], "window", facing=f)
    return pane


def main():
    build_cabin_small()


if __name__ == "__main__":
    main()
