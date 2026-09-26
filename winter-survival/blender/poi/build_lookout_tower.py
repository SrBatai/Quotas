"""lookout_tower (ASSET_SPEC_V2 §8.5 "lookout_tower 4 x 4 x 12 m" + "M3") -> assets/models/poi/lookout_tower.glb:
the wooden fire-watch tower of the deep forest (TORRE DE VIGILANCIA, PLAN §4.2 "L"), a navigation landmark.

    cd winter-survival/blender && python3 poi/build_lookout_tower.py

Timber frame: 4 splayed legs (feet at +-2.1 m on concrete footings, heads at +-1.55 m under the platform), girts at
3 / 6 m and X-bracing on every face. Four external stair flights (2.3 m rise each, 13 steps of 0.177 x 0.30, 0.9 m
wide, treads 0.37) wrap the frame counter-clockwise S -> W -> N -> E with corner landings on posts; the last flight
arrives on an L-shaped top landing that meets the S edge of the catwalk (platform top +9.20 m, 4.4 x 4.4 m, railing
1.05 m, gap at the landing). Glazed cab 3.0 x 3.0 m (walls 9.2 -> 11.4 m, windows
all round, door on the E side), hip roof to 12.7 m with a draped snow cap, lightning rod, icicles.

Cut groups (ASSET_SPEC_V2 §8.4; floor index k = storey the player stands on):
  Floor0            footings, legs, bracing, stairs, landings, stair rails, ground snow        (never hidden)
  Floor1            platform: joists, deck, catwalk railing, snow on the catwalk              (floor_z = 9.2)
  Walls1_N/S/E/W    cab walls (+ `_Stub` 0.6 m versions, same outline)
  Interior1         fire-finder table (pedestal + map), stool, cot frame, shelf
  Roof              hip roof, ceiling, snow cap, lightning rod, icicles
  Door_0            cab door (E facade), origin on the hinge axis; extras kind=door, exterior=true, cut_group=Walls1_E
  Window_0..4       glazed bands: 0 N, 1-2 E (either side of the door), 3 S, 4 W; extras boarded / cut_group
  DoorAnchor        on the catwalk in front of the cab door; StairFoot = foot of the first flight (ground, S side);
  ViewAnchor        eye height in the cab (0, 0, 10.9): the code can use it for a map-reveal / lookout action
  Spawn_Radio_0, Spawn_Loot_0, Spawn_Container_0 (table "lookout"), Spawn_Bed_0, Spawn_Light_0
  Col*-convcolonly  ColFooting_0..3, ColLeg_0..3 (slanted boxes), ColStair_0..3 (RAMPS: 6-vertex wedges),
                    ColLanding_0..3, ColStairRail_0..3 (outer rails), ColFloor1, ColRail1_N/S/E/W (S stops at the
                    top landing), ColWalls1_N/S/W, ColWalls1_E_0..2 (door open)
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

FOOT, HEAD = 2.1, 1.55          # leg centre at z = 0 / at the platform
PZ0, PZ = 9.0, 9.2              # platform underside / top (Floor1)
PL = 2.2                        # platform half size
CAB = 1.5                       # cab half size (outer face)
CAB_T = 0.12
WALL_TOP = 11.4
EAVE = CAB + 0.45
APEX = 12.7
LANE0, LANE1 = 2.4, 3.3         # stair lane (distance from the tower axis)
LC = (LANE0 + LANE1) / 2
RISE = PZ / 4.0
N_STEPS = 13
TREAD = 2 * LANE0 / N_STEPS     # 0.369: each flight spans exactly between two corner landings
TOP_LANDING = ((1.3, -LANE1), (LANE1, -PL))                    # (x0, y0), (x1, y1) at PZ, meets the catwalk S edge
DOOR = (-0.45, 0.45, PZ, PZ + 2.0)          # along Y on the E facade
WIN = (PZ + 0.95, PZ + 2.0)


def leg_xy(sx, sy, z):
    f = FOOT + (HEAD - FOOT) * (z / PZ0)
    return Vector((sx * f, sy * f, z))


def flights():
    """[(start xy, direction, z0)] counter-clockwise S (going -X) -> W (+Y) -> N (+X) -> E (-Y)."""
    return [
        (Vector((LANE0, -LC, 0)), Vector((-1, 0, 0)), 0.0),
        (Vector((-LC, -LANE0, 0)), Vector((0, 1, 0)), RISE),
        (Vector((-LANE0, LC, 0)), Vector((1, 0, 0)), 2 * RISE),
        (Vector((LC, LANE0, 0)), Vector((0, -1, 0)), 3 * RISE),
    ]


def build_frame(g, rnd):
    """Footings, legs, girts, X-braces (Floor0)."""
    for sx in (-1, 1):
        for sy in (-1, 1):
            c = Vector((sx * FOOT, sy * FOOT, 0))
            g.hard.box((c.x - 0.28, c.y - 0.28, -0.05), (c.x + 0.28, c.y + 0.28, 0.3), "concrete", skip=("-z",))
            H.beam(g.hard, leg_xy(sx, sy, 0.3), leg_xy(sx, sy, PZ0 + 0.02), 0.22, 0.22, "wood", up=(sx, sy, 0))
            g.hard.box((c.x - 0.14, c.y - 0.14, 0.3), (c.x + 0.14, c.y + 0.14, 0.42), "iron")         # steel shoe
    levels = [0.9, 3.0, 6.0, PZ0 - 0.12]
    faces = [((-1, -1), (1, -1)), ((1, -1), (1, 1)), ((1, 1), (-1, 1)), ((-1, 1), (-1, -1))]
    for (ax, ay), (bx, by) in faces:
        for zl in levels[1:-1]:
            H.beam(g.hard, leg_xy(ax, ay, zl), leg_xy(bx, by, zl), 0.12, 0.16, "wood")
        for z0, z1 in zip(levels[:-1], levels[1:]):
            H.beam(g.flat, leg_xy(ax, ay, z0), leg_xy(bx, by, z1), 0.08, 0.1, "wood_dark")
            H.beam(g.flat, leg_xy(bx, by, z0), leg_xy(ax, ay, z1), 0.08, 0.1, "wood_dark")


def build_stairs(g, rnd, col):
    """Four flights with stringers, treads, outer handrails; corner landings on posts, ties to the legs."""
    ramps = []
    for fi, (start, d, z0) in enumerate(flights()):
        side = Vector((-d.y, d.x, 0))            # left of the walking direction
        # the outer side of the lane is away from the tower axis
        outward = side if (start + side * 0.1).length > start.length else -side
        run = N_STEPS * TREAD
        p0 = start.copy()
        p1 = start + d * run
        rise_step = RISE / N_STEPS
        for k in range(N_STEPS):
            a = p0 + d * (k * TREAD)
            zt = z0 + (k + 1) * rise_step
            c0 = a + outward * 0.45
            c1 = a - outward * 0.45
            b0, b1 = c0 + d * TREAD, c1 + d * TREAD
            xs = [c0.x, c1.x, b0.x, b1.x]
            ys = [c0.y, c1.y, b0.y, b1.y]
            g.flat.box((min(xs), min(ys), zt - 0.05), (max(xs), max(ys), zt), "wood" if k % 4 else "wood_light")
        for sgn in (-1, 1):
            q0 = p0 + outward * (sgn * 0.47) + Vector((0, 0, z0 - 0.1))
            q1 = p1 + outward * (sgn * 0.47) + Vector((0, 0, z0 + RISE - 0.05))
            H.beam(g.hard, q0, q1, 0.06, 0.24, "wood")
        # outer handrail: posts + rail + snow line
        for k in range(4):
            t = k / 3.0
            base = p0.lerp(p1, t) + outward * 0.47 + Vector((0, 0, z0 + RISE * t + 0.05))
            H.beam(g.flat, base, base + Vector((0, 0, 0.95)), 0.06, 0.06, "wood", up=(d.x, d.y, 0))
        r0 = p0 + outward * 0.47 + Vector((0, 0, z0 + 1.0))
        r1 = p1 + outward * 0.47 + Vector((0, 0, z0 + RISE + 1.0))
        H.beam(g.hard, r0, r1, 0.06, 0.08, "wood_light")
        g.snow.append(H.snow_ridge(r0 + Vector((0, 0, 0.04)), r1 + Vector((0, 0, 0.04)), 0.08, 0.04, seed=fi + 1,
                                   overhang=0.0, droop=0.01))
        # ramp collision (6-vertex wedge) + outer rail box
        lo, hi = p0, p1
        a = lo + outward * 0.45
        b = lo - outward * 0.45
        pts = [(a.x, a.y, z0), (b.x, b.y, z0), (a.x + d.x * run, a.y + d.y * run, z0),
               (b.x + d.x * run, b.y + d.y * run, z0), (a.x + d.x * run, a.y + d.y * run, z0 + RISE),
               (b.x + d.x * run, b.y + d.y * run, z0 + RISE)]
        ramps.append(("ColStair_%d" % fi, pts))
        ro = outward * 0.47
        rail = []
        for i in range(8):
            base = hi if i & 2 else lo
            zb = (z0 + RISE if i & 2 else z0)
            rail.append(tuple(base + ro + outward * (0.03 if i & 1 else -0.03) + Vector((0, 0, zb + (1.05 if i & 4 else 0.1)))))
        col["ColStairRail_%d" % fi] = rail
    # landings (corner platforms at the end of flights 0, 1, 2) + the top landing onto the catwalk
    lands = [((-LANE1, -LANE1), (-LANE0 + 0.0, -LANE0 + 0.0), RISE), ((-LANE1, LANE0), (-LANE0, LANE1), 2 * RISE),
             ((LANE0, LANE0), (LANE1, LANE1), 3 * RISE)]
    lands.append((TOP_LANDING[0], TOP_LANDING[1], PZ))
    for li, ((x0, y0), (x1, y1), z) in enumerate(lands):
        x0, x1 = sorted((x0, x1))
        y0, y1 = sorted((y0, y1))
        if li == 3:
            y1 -= 0.01                                        # no coincident faces with the platform edge
        g.hard.box((x0, y0, z - 0.2), (x1, y1, z - 0.06), "wood")
        nb = 4
        for k in range(nb):
            xx = x0 + k * (x1 - x0) / nb
            g.flat.box((xx + 0.01, y0, z - 0.06), (xx + (x1 - x0) / nb - 0.01, y1, z), "wood_light" if k % 2 else "wood",
                       skip=("-z",))
        col["ColLanding_%d" % li] = ((x0, y0, z - 0.2), (x1, y1, z))
        if li < 3:                                           # post to the ground under the outer corner + tie to the leg
            cx = x0 + 0.06 if abs(x0) > abs(x1) else x1 - 0.06
            cy = y0 + 0.06 if abs(y0) > abs(y1) else y1 - 0.06
            H.beam(g.hard, (cx, cy, -0.05), (cx, cy, z - 0.2), 0.14, 0.14, "wood", up=(1, 0, 0))
            g.hard.box((cx - 0.2, cy - 0.2, -0.05), (cx + 0.2, cy + 0.2, 0.2), "concrete", skip=("-z",))
            sx, sy = (1 if cx > 0 else -1), (1 if cy > 0 else -1)
            H.beam(g.flat, (cx, cy, z - 0.3), leg_xy(sx, sy, z - 0.3), 0.08, 0.12, "wood_dark")
            H.beam(g.flat, (cx, cy, z * 0.45), leg_xy(sx, sy, z - 0.35), 0.07, 0.1, "wood_dark")
            # snow on the landing (outer half)
            g.snow.append(H.pillow((x0 + 0.05, y0 + 0.05, z), (1, 0, 0), (0, 1, 0), (0, 0, 1), x1 - x0 - 0.1, y1 - y0 - 0.1,
                                   0.07, nu=3, nv=3, rim=0.1, seed=70 + li, levels=1, bottom=-0.05))
    return ramps


def build_platform(g, rnd, col):
    """Floor1: joists, deck boards, rim, catwalk railing with a gap for the top landing, snow on the catwalk."""
    g.hard.box((-PL, -PL, PZ0), (PL, PL, PZ0 + 0.12), "wood_dark")
    for k in range(5):
        x = -PL + 0.2 + k * (2 * PL - 0.4) / 4
        g.flat.box((x - 0.06, -PL, PZ0 - 0.18), (x + 0.06, PL, PZ0), "wood", skip=("+z",))
    n = 16
    bw = (2 * PL - (n - 1) * 0.015) / n
    for k in range(n):
        y = -PL + k * (bw + 0.015)
        g.flat.box((-PL, y, PZ0 + 0.12), (PL, y + bw, PZ), "wood" if k % 3 else "wood_light", skip=("-z",))
    rails = {"N": [((-PL, PL), (PL, PL))], "S": [((-PL, -PL), (TOP_LANDING[0][0], -PL))],
             "W": [((-PL, -PL), (-PL, PL))], "E": [((PL, -PL), (PL, PL))]}
    posts = set()
    for side, segs in rails.items():
        for si, ((xa, ya), (xb, yb)) in enumerate(segs):
            L = math.hypot(xb - xa, yb - ya)
            if L < 0.2:
                continue
            npost = max(2, int(L / 1.1) + 1)
            for k in range(npost):
                t = k / (npost - 1)
                x, y = xa + (xb - xa) * t, ya + (yb - ya) * t
                key = (round(x, 3), round(y, 3))
                if key in posts:                             # corner posts are shared by two runs
                    continue
                posts.add(key)
                g.hard.box((x - 0.05, y - 0.05, PZ), (x + 0.05, y + 0.05, PZ + 1.05), "wood")
            for zr, w in ((PZ + 1.02, 0.07), (PZ + 0.55, 0.05)):
                g.hard.box((min(xa, xb) - 0.035, min(ya, yb) - 0.035, zr - w / 2),
                           (max(xa, xb) + 0.035, max(ya, yb) + 0.035, zr + w / 2), "wood_light")
            g.snow.append(H.snow_ridge((xa, ya, PZ + 1.055), (xb, yb, PZ + 1.055), 0.08, 0.045, seed=80 + si + ord(side),
                                       overhang=0.02, droop=0.012))
            name = "ColRail1_%s" % side if len(segs) == 1 else "ColRail1_%s_%d" % (side, si)
            col[name] = ((min(xa, xb) - 0.05, min(ya, yb) - 0.05, PZ), (max(xa, xb) + 0.05, max(ya, yb) + 0.05, PZ + 1.05))
    # snow along the catwalk (not on the path from the stairs to the door)
    for k, (o, U, Vv, L, D) in enumerate((((-PL + 0.1, PL - 0.1, PZ), (1, 0, 0), (0, -1, 0), 2 * PL - 0.2, 0.5),
                                          ((-PL + 0.1, -PL + 0.1, PZ), (0, 1, 0), (1, 0, 0), 2 * PL - 0.2, 0.5),
                                          ((-PL + 0.1, -PL + 0.1, PZ), (1, 0, 0), (0, 1, 0), 2.6, 0.5))):
        def top(u, v, D=D):
            return 0.03 + 0.14 * max(0.0, 1.0 - v / D) ** 0.8
        g.snow.append(H.pillow(Vector(o), U, Vv, (0, 0, 1), L, D, 0.14, nu=5, nv=3, rim=0.12, seed=90 + k, top_fn=top,
                               jitter=0.02, levels=1, bottom=-0.04))


def cab_facade(d):
    return kit.Facade(d, 2 * CAB, 2 * CAB, 0)


def build_cab_wall(d, g, stub, panes, seed):
    """Cab facade: plank slab + lap sheet up to the sill, glazed band (sash frame, mullions every ~0.5 m), frieze;
    door opening on E. Stub = 0.6 m."""
    fac = cab_facade(d)
    fac.z0, fac.zt = PZ, WALL_TOP
    zt = PZ + (kit.STUB_H if stub else WALL_TOP - PZ)
    style = kit.STYLES["wood_blue"]
    a, b = (fac.u0, fac.u1) if d in "SN" else (fac.u0, fac.u1)
    hole_d = (DOOR[0], DOOR[1], PZ, PZ + 2.0) if d == "E" else None
    win = [(a + 0.18, b - 0.18)] if d != "E" else [(a + 0.16, DOOR[0] - 0.22), (DOOR[1] + 0.22, b - 0.16)]
    mats = {fac.out_key: "wood", fac.in_key: "wood_light"}
    # slab pieces
    pieces = []
    spans = kit._spans(a, b, [(hole_d[0], hole_d[1])] if hole_d else [])
    for sa, sb in spans:
        pieces.append((sa, sb, PZ, min(zt, WIN[0])))
        if not stub:
            pieces.append((sa, sb, WIN[1], zt))
            cuts = [(w0, w1) for w0, w1 in win if w0 < sb and w1 > sa]
            for pa, pb in kit._spans(sa, sb, cuts):
                pieces.append((pa, pb, WIN[0], WIN[1]))
    if hole_d and not stub:
        pieces.append((hole_d[0], hole_d[1], hole_d[3], zt))
    for u0, u1, z0, z1 in pieces:
        if u1 - u0 > 1e-3 and z1 - z0 > 1e-3:
            fac.box(g.flat, u0, u1, z0, z1, -CAB_T, 0.0, "wood", mats=mats)
    holes = [(hole_d[0] - 0.1, hole_d[1] + 0.1, PZ, PZ + 2.1)] if hole_d else []
    kit.lap_sheet(fac, g.flat, a, b, PZ + 0.12, min(zt, WIN[0] - 0.08), holes, "wood")
    fac.box(g.hard, a, b, PZ - 0.02, PZ + 0.12, 0.0, 0.03, "wood_dark", skip=(fac.in_key,))
    if stub:
        for sa, sb in spans:
            fac.box(g.hard, sa, sb, zt, zt + 0.04, -CAB_T - 0.015, 0.03, "wood_light")
    else:
        fac.box(g.hard, a, b, WIN[0] - 0.1, WIN[0], 0.0, 0.1, "wood_light")                 # sill band
        g.snow.append(H.snow_ridge(fac.p(a + 0.05, WIN[0], 0.06), fac.p(b - 0.05, WIN[0], 0.06), 0.09, 0.05, seed=seed,
                                   overhang=0.0, droop=0.015))
        fac.box(g.hard, a, b, WIN[1], WIN[1] + 0.12, 0.0, 0.04, "wood_light", skip=(fac.in_key,))   # head band
        fac.box(g.hard, a, b, zt - 0.14, zt, 0.0, 0.03, "wood_dark", skip=(fac.in_key,))           # frieze
        for w0, w1 in win:
            n = max(2, int(round((w1 - w0) / 0.5)))
            for k in range(n + 1):
                u = w0 + (w1 - w0) * k / n
                fac.box(g.flat, u - 0.025, u + 0.025, WIN[0], WIN[1], -0.07, -0.02, "wood_light", skip=(fac.in_key,))
            fac.box(g.flat, w0, w1, (WIN[0] + WIN[1]) / 2 - 0.02, (WIN[0] + WIN[1]) / 2 + 0.02, -0.07, -0.03,
                    "wood_light", skip=(fac.in_key,))
            pane = lp.MeshBuilder()
            pane.poly(fac.rect(w0, w1, WIN[0], WIN[1], -0.05), "window", facing=fac.n)
            pane.poly(fac.rect(w0, w1, WIN[0], WIN[1], -0.054), "window", facing=-fac.n)
            panes.append((pane, g.name))
        if hole_d:
            kit.door_trim(fac, g, hole_d, style, seed)
    # corner posts belong to S / N (§8.6)
    if d in "SN":
        for end in (-1, 1):
            u = fac.u0 if end < 0 else fac.u1
            v = fac.line + fac.sign * kit.T2
            g.hard.box((u - 0.07 if end > 0 else u - 0.03, v - 0.07 if fac.sign > 0 else v - 0.03, PZ),
                       (u + 0.03 if end > 0 else u + 0.07, v + 0.03 if fac.sign > 0 else v + 0.07, zt), "wood_light")
    return fac, spans


def build_roof(g, rnd):
    """Hip roof (pyramid) with a fascia, draped snow cap, rod, ceiling, icicles."""
    t = (APEX - WALL_TOP) / EAVE
    ring = [Vector((x, y, WALL_TOP - 0.02)) for x, y in ((-EAVE, -EAVE), (EAVE, -EAVE), (EAVE, EAVE), (-EAVE, EAVE))]
    ring_top = [p + Vector((0, 0, 0.14)) for p in ring]
    apex = Vector((0, 0, APEX))
    g.hard.loft([ring, ring_top], "wood_dark", cap_start=True, cap_end=False)
    g.hard.loft([ring_top, [apex]], "roof", cap_start=False, cap_end=False)
    # hip caps
    for p in ring_top:
        H.beam(g.flat, p + Vector((0, 0, 0.02)), apex + Vector((0, 0, 0.02)), 0.08, 0.06, "roof_seam", up=(0, 0, 1))
    g.flat.box((-CAB + CAB_T, -CAB + CAB_T, WALL_TOP - 0.06), (CAB - CAB_T, CAB - CAB_T, WALL_TOP - 0.02), "wood_light",
               skip=("+z",))
    # rod
    H.tube(g.flat, [(0, 0, APEX - 0.1), (0, 0, APEX + 0.9)], [0.02, 0.015], 5, "iron", cap_end=True)
    g.flat.blob((0, 0, APEX + 0.92), 0.04, "iron", subdiv=0, jitter=0.0)

    def z_roof(x, y):
        m = max(abs(x), abs(y))
        return WALL_TOP + 0.12 + max(0.0, EAVE - m) * t
    g.snow.append(H.snow_cap((0.05, -0.05, 0), EAVE * 0.98, EAVE * 0.98, 0.2, z_roof, seed=11, sides=12, rings=4,
                             droop=0.06))
    for sx, sy, ax in ((1, 1, "x"), (-1, -1, "x")):
        y = sy * (EAVE + 0.02)
        g.smooth += icicle_strip((-0.9, y, WALL_TOP - 0.05), (0.7, y, WALL_TOP - 0.05), seed=20 + sy, max_len=0.35,
                                 spacing=0.15, ridge=False)


def build_interior(g, rnd):
    z = PZ
    g.hard.cylinder((0, 0.1, z), (0, 0.1, z + 0.85), 0.12, 0.1, 8, "wood_dark")
    g.hard.cylinder((0, 0.1, z + 0.85), (0, 0.1, z + 0.92), 0.5, 0.5, 12, "wood")
    g.flat.cylinder((0, 0.1, z + 0.92), (0, 0.1, z + 0.925), 0.44, 0.44, 12, "paper", cap0=False)
    g.flat.box((-0.02, -0.3, z + 0.925), (0.02, 0.5, z + 0.95), "brass")                       # alidade
    g.hard.box((0.55, 0.55, z + 0.45), (0.85, 0.85, z + 0.5), "wood")
    for sx in (0.58, 0.82):
        for sy in (0.58, 0.82):
            g.flat.box((sx - 0.02, sy - 0.02, z), (sx + 0.02, sy + 0.02, z + 0.45), "wood_dark")
    g.hard.box((-1.35, -1.35, z + 0.35), (-0.55, 0.55, z + 0.42), "wood_dark")                  # cot frame
    g.flat.box((-1.3, -1.3, z + 0.42), (-0.6, 0.5, z + 0.5), "cloth_gray", skip=("-z",))
    for sx in (-1.3, -0.6):
        for sy in (-1.3, 0.5):
            g.flat.box((sx - 0.02, sy - 0.02, z), (sx + 0.02, sy + 0.02, z + 0.35), "wood_dark")
    g.hard.box((-0.6, 1.1, z + 0.85), (0.6, 1.38, z + 0.9), "wood")                              # shelf (N wall)


def build_collision(col, ramps, cab_spans):
    for sx in (-1, 1):
        for sy in (-1, 1):
            i = (0 if sx < 0 else 1) + (0 if sy < 0 else 2)
            c = Vector((sx * FOOT, sy * FOOT, 0))
            col["ColFooting_%d" % i] = ((c.x - 0.28, c.y - 0.28, 0.0), (c.x + 0.28, c.y + 0.28, 0.42))
            pts = []
            for k in range(8):
                z = PZ0 if k & 4 else 0.42
                p = leg_xy(sx, sy, z)
                pts.append((p.x + (0.12 if k & 1 else -0.12), p.y + (0.12 if k & 2 else -0.12), z))
            col["ColLeg_%d" % i] = pts
    col["ColFloor1"] = ((-PL, -PL, PZ0), (PL, PL, PZ))
    for d in "NSWE":
        fac = cab_facade(d)
        spans = cab_spans[d]
        if d != "E":
            a, b = fac.p(fac.u0, PZ, -CAB_T), fac.p(fac.u1, WALL_TOP, 0.0)
            col["ColWalls1_%s" % d] = ((min(a.x, b.x), min(a.y, b.y), PZ), (max(a.x, b.x), max(a.y, b.y), WALL_TOP))
        else:
            boxes = [(spans[0][0], spans[0][1], PZ, WALL_TOP), (DOOR[0], DOOR[1], DOOR[3], WALL_TOP),
                     (spans[1][0], spans[1][1], PZ, WALL_TOP)]
            for k, (u0, u1, z0, z1) in enumerate(boxes):
                a, b = fac.p(u0, z0, -CAB_T), fac.p(u1, z1, 0.0)
                col["ColWalls1_E_%d" % k] = ((min(a.x, b.x), min(a.y, b.y), z0), (max(a.x, b.x), max(a.y, b.y), z1))
    for name, v in col.items():
        if isinstance(v, tuple) and len(v) == 2:
            lp.collision_box(name, v[0], v[1])
        else:
            mb = lp.MeshBuilder()
            mb.hexa(v, None)
            lp._collision(mb, name)
    for name, pts in ramps:
        lp.collision_prism(name, pts, [(0, 2, 4), (1, 5, 3), (0, 1, 3, 2), (2, 3, 5, 4), (0, 4, 5, 1)])


def build_lookout_tower():
    lp.new_scene()
    rnd = random.Random(23)
    col = {}
    floor0 = kit.Group("Floor0", 0)
    build_frame(floor0, rnd)
    ramps = build_stairs(floor0, rnd, col)
    # ground snow: drifts around the footings + a trodden path to the first flight
    for k, (x, y, r, h) in enumerate(((-2.4, 2.3, 0.9, 0.35), (2.5, 2.2, 0.7, 0.28), (-2.2, -2.0, 0.6, 0.22))):
        floor0.snow.append(H.mound((x, y, 0), r, h, seed=100 + k, sides=10, sink=0.06, stretch=(1.2, 0.9)))
    floor1 = kit.Group("Floor1", 1)
    build_platform(floor1, rnd, col)
    panes = []
    cab_spans = {}
    groups = [floor0, floor1]
    for d in "SNEW":
        g = kit.Group("Walls1_%s" % d, 1)
        fac, spans = build_cab_wall(d, g, False, panes, 30 + ord(d))
        gs = kit.Group("Walls1_%s_Stub" % d, 1)
        build_cab_wall(d, gs, True, [], 30 + ord(d))
        cab_spans[d] = spans
        groups += [g, gs]
    interior = kit.Group("Interior1", 1)
    build_interior(interior, rnd)
    roof = kit.Group("Roof", 2)
    build_roof(roof, rnd)
    groups += [interior, roof]
    for g in groups:
        kit._assemble(g, 0.015)
    bpy.data.objects["Floor0"]["floor_z"] = 0.0
    bpy.data.objects["Floor1"]["floor_z"] = PZ
    order = {"Walls1_N": 0, "Walls1_E": 1, "Walls1_S": 2, "Walls1_W": 3}
    for n, (pmb, cg) in enumerate(sorted(panes, key=lambda x: order[x[1]])):
        w = H.flat(H.mk(pmb, "Window_%d" % n))
        w["boarded"] = False
        w["cut_group"] = cg
        w["floor"] = 1
    fac = cab_facade("E")
    fac.z0, fac.zt = PZ, WALL_TOP
    kit.door_leaf(fac, (DOOR[0], DOOR[1], PZ, PZ + 2.0), kit.STYLES["wood_blue"], "Door_0", True, "Walls1_E", 1)
    fl = flights()
    lp.add_empty("DoorAnchor", (CAB + 0.4, 0.0, PZ))
    lp.add_empty("StairFoot", (fl[0][0].x + 0.5, fl[0][0].y, 0.0))
    lp.add_empty("ViewAnchor", (0.0, 0.0, PZ + 1.7))
    spawns = [("Spawn_Radio_0", (0.0, 1.24, PZ + 0.9), 180, {}), ("Spawn_Loot_0", (0.2, 0.0, PZ + 0.93), 0, {}),
              ("Spawn_Container_0", (-1.0, 1.05, PZ), 180, {"table": "lookout"}),
              ("Spawn_Bed_0", (-0.95, -0.4, PZ), 90, {}), ("Spawn_Light_0", (0.0, 0.0, WALL_TOP - 0.2), 0, {})]
    for name, pos, yaw, props in spawns:
        e = lp.add_empty(name, pos, rotation_deg=(0, 0, yaw), size=0.3)
        e["kind"] = name.split("_")[1]
        for k, v in props.items():
            e[k] = v
    build_collision(col, ramps, cab_spans)
    kit.bake_cut_ao(distance=1.0, samples=48)
    export.save_and_export("lookout_tower", subdir="poi", ao=dict(distance=1.0, samples=48, ground=True),
                           import_kind="prop")


def main():
    build_lookout_tower()


if __name__ == "__main__":
    main()
