"""a_frame_cabin, pickup_truck, signpost, fence (slice ASSET_SPEC §4.17-4.20; ASSET_SPEC_V2 §17).

* a_frame_cabin, pickup_truck: written in the slice convention (+Y front) and built with
  new_scene(authored_front="+Y") -> exported facing -Y (MODEL_FRONT); BedAnchor (0, 1.35, 1.0).
  The A-frame window trim lives in `Front`; `WindowsFront` is only the pane (material `window`).
  The truck keeps the slice `window` material on its glass (same look); the vehicle material `glass`
  (v2 §2.5/§11) comes with the M7 vehicles/pickup.glb.
* signpost: authored directly in v2 (no rotation): the boards still point to +X, their text face looks
  toward -Y, TextTop/TextBottom at y = -0.125 with rotation (0, 0, 0) (Label3D +Z = -Y Blender).
* fence: no front; unchanged orientation (rails on the +Y side of the posts, as in the slice).
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402,F401  (must precede mathutils)
from mathutils import Vector  # noqa: E402

from lib import export  # noqa: E402
from lib import hd as H  # noqa: E402
from lib import lowpoly as lp  # noqa: E402

X = (1, 0, 0)


def quad_on(corners, u0, u1, v0, v1, off, normal):
    """Sub-rectangle of a (possibly trapezoidal) quad given as [bl, br, tr, tl], offset along `normal`."""
    bl, br, tr, tl = [Vector(c) for c in corners]

    def at(u, v):
        b = bl.lerp(br, u)
        t = tl.lerp(tr, u)
        return b.lerp(t, v) + Vector(normal).normalized() * off
    return [at(u0, v0), at(u1, v0), at(u1, v1), at(u0, v1)]


# ------------------------------------------------------------------------------------------------
WHEEL_Y, WHEEL_Z, WHEEL_R, WHEEL_X = 1.6, 0.42, 0.42, 0.93
ARCH_R = 0.50
BELT = 1.00                      # top of the lower body / bed floor


def _arch(y0, n=9):
    """Wheel-arch points (y, z) over the wheel at y0, from front to back (slice +Y = front)."""
    pts = []
    zc = WHEEL_Z
    a0 = math.asin(max(-1.0, min(1.0, (0.40 - zc) / ARCH_R)))
    for k in range(n):
        t = a0 + (math.pi - 2 * a0) * k / (n - 1)
        pts.append((y0 + ARCH_R * math.cos(t), zc + ARCH_R * math.sin(t)))
    return pts


def truck_body():
    """Body: chamfered lower body with wheel arches, hood, cab + greenhouse, bed; flat details; window panes."""
    hard, fine, panes = lp.MeshBuilder(), lp.MeshBuilder(), lp.MeshBuilder()
    paint, dark = "truck_paint", "iron"
    # lower body: side profile (y, z) with two arches, extruded along X
    prof = [(2.42, 0.40)] + _arch(WHEEL_Y) + _arch(-WHEEL_Y) + [(-2.42, 0.40), (-2.42, BELT), (2.42, BELT)]
    hard.prism([Vector((-0.96, y, z)) for y, z in prof], (-0.96, 0, 0), (0.96, 0, 0), paint,
               mats_caps=(paint, paint))
    # hood: from the cab (y 0.95) to the nose, sloping 1.30 -> 1.20
    hard.hexa([(-0.94, 0.95, BELT), (0.94, 0.95, BELT), (-0.94, 2.42, BELT), (0.94, 2.42, BELT),
               (-0.94, 0.95, 1.30), (0.94, 0.95, 1.30), (-0.92, 2.42, 1.21), (0.92, 2.42, 1.21)], paint)
    # cab lower + greenhouse
    hard.box((-0.95, -0.28, BELT), (0.95, 0.95, 1.32), paint)
    gh = [(-0.93, -0.25, 1.32), (0.93, -0.25, 1.32), (-0.93, 0.93, 1.32), (0.93, 0.93, 1.32),
          (-0.84, -0.20, 1.92), (0.84, -0.20, 1.92), (-0.84, 0.52, 1.92), (0.84, 0.52, 1.92)]
    hard.hexa(gh, paint)
    g = [Vector(c) for c in gh]
    ws = [g[2], g[3], g[7], g[6]]
    panes.poly(quad_on(ws, 0.06, 0.94, 0.10, 0.90, 0.012, (0, 0.85, 0.53)), "window", facing=(0, 0.85, 0.53))
    rw = [g[1], g[0], g[4], g[5]]
    panes.poly(quad_on(rw, 0.14, 0.86, 0.18, 0.84, 0.012, (0, -1, 0)), "window", facing=(0, -1, 0))
    for sx in (-1, 1):
        sd = [g[1], g[3], g[7], g[5]] if sx > 0 else [g[0], g[2], g[6], g[4]]
        nrm = (sx, 0, 0.14)
        panes.poly(quad_on(sd, 0.07, 0.46, 0.12, 0.86, 0.012, nrm), "window", facing=nrm)
        panes.poly(quad_on(sd, 0.52, 0.84, 0.12, 0.86, 0.012, nrm), "window", facing=nrm)
        # B-pillar strip between the two side windows
        fine.poly(quad_on(sd, 0.46, 0.52, 0.10, 0.88, 0.010, nrm), dark, facing=nrm)
    # bed walls (0.08 thick) up to 1.32, front wall, tailgate
    for sx in (-1, 1):
        hard.box((0.87 if sx > 0 else -0.96, -2.42, BELT), (0.96 if sx > 0 else -0.87, -0.30, 1.32), paint)
    hard.box((-0.87, -0.38, BELT), (0.87, -0.30, 1.30), paint)
    hard.box((-0.87, -2.42, BELT), (0.87, -2.34, 1.30), paint)
    # fender flares: dark tubes along the arches, just proud of the body sides
    for sx in (-1, 1):
        for y0 in (WHEEL_Y, -WHEEL_Y):
            pts = [Vector((sx * 0.975, y, z)) for y, z in _arch(y0, 11)]
            pts = [p + (p - Vector((sx * 0.975, y0, WHEEL_Z))).normalized() * 0.03 for p in pts]
            H.tube(hard, pts, [(0.045, 0.06)] * len(pts), 4, dark, cap_end=True, cap_start=True, phase=45)
    # bumpers
    hard.box((-1.0, 2.42, 0.44), (1.0, 2.55, 0.66), dark)
    hard.box((-1.0, -2.55, 0.44), (1.0, -2.42, 0.64), dark)
    hard.box((-0.35, -2.62, 0.47), (0.35, -2.55, 0.52), dark)                      # rear step
    # grille (frame + bars) and lights
    hard.box((-0.56, 2.42, 0.72), (0.56, 2.47, 1.12), dark)
    for k in range(5):
        z = 0.78 + k * 0.075
        fine.box((-0.50, 2.47, z), (0.50, 2.49, z + 0.03), "metal_sheet")
    for sx in (-1, 1):
        hard.box((sx * 0.74 - 0.14, 2.42, 0.94), (sx * 0.74 + 0.14, 2.46, 1.12), "iron")
        fine.box((sx * 0.74 - 0.11, 2.46, 0.965), (sx * 0.74 + 0.11, 2.475, 1.095), "lamp_clear")
        fine.box((sx * 0.74 - 0.10, 2.42, 0.82), (sx * 0.74 + 0.10, 2.445, 0.88), "lamp_clear")   # fog light
        fine.box((sx * 0.905 - 0.05, -2.445, 1.02), (sx * 0.905 + 0.05, -2.42, 1.26), "lamp_red")
        # mirrors on stalks
        hard.box((sx * 0.95 - (0.12 if sx < 0 else 0.0), 0.84, 1.36), (sx * 0.95 + (0.12 if sx > 0 else 0.0), 0.91, 1.52),
                 dark)
        fine.box((sx * 0.93 - 0.02, 0.86, 1.33), (sx * 0.93 + 0.02, 0.89, 1.37), dark)
        # door seams, handles, sill step
        for y in (0.93, -0.26):
            fine.box((sx * 0.955 - 0.004, y - 0.006, 0.52), (sx * 0.955 + 0.004, y + 0.006, 1.31), dark)
        fine.box((sx * 0.957 - 0.006, 0.60, 1.18), (sx * 0.957 + 0.006, 0.74, 1.21), "metal_sheet")
        hard.box((sx * 0.96 - (0.10 if sx < 0 else 0.0), -0.22, 0.36), (sx * 0.96 + (0.10 if sx > 0 else 0.0), 0.90, 0.42),
                 dark)
    # chassis, exhaust, spare tyre carrier under the bed
    hard.box((-0.70, -2.30, 0.30), (0.70, 2.30, 0.42), dark)
    H.tube(fine, [(0.55, -2.2, 0.36), (0.55, -2.62, 0.36)], [0.035, 0.035], 6, dark, cap_end=True)
    # a crate in the bed (chamfered, dark wood) and a coiled rope
    hard.box((-0.75, -1.98, BELT), (-0.18, -1.42, BELT + 0.36), "wood_dark")
    fine.box((-0.76, -1.99, BELT + 0.12), (-0.17, -1.41, BELT + 0.15), "wood")
    body = H.mk(hard)
    H.bevel(body, 0.035, 1, angle=30)
    H.snap_colors(body)
    return H.join([body, H.flat(H.mk(fine)), H.flat(H.mk(panes))], "Body")


def truck_wheels():
    """Smooth tyres (rounded section, 18 sides), dark steel rims with a hub; axle along X."""
    parts = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            c = Vector((sx * WHEEL_X, sy * WHEEL_Y, WHEEL_Z))
            mb = lp.MeshBuilder()
            hw = 0.13
            sec = [(-hw, 0.30), (-hw, 0.37), (-hw * 0.82, 0.41), (-hw * 0.45, WHEEL_R),
                   (hw * 0.45, WHEEL_R), (hw * 0.82, 0.41), (hw, 0.37), (hw, 0.30)]
            rings = [lp.ring(c + Vector((dx, 0, 0)), (1, 0, 0), r, 18, 10) for dx, r in sec]
            mb.loft(rings, "tire", cap_start=False, cap_end=False, inside=c)
            tyre = H.smooth(H.mk(mb), angle=50)
            rim = lp.MeshBuilder()
            o = sx * (hw - 0.01)
            rim.loft([lp.ring(c + Vector((o, 0, 0)), (1, 0, 0), 0.30, 18, 10),
                      lp.ring(c + Vector((o - sx * 0.035, 0, 0)), (1, 0, 0), 0.24, 18, 10)], "stone_dark",
                     cap_start=False, cap_end=False, seg_facing=[(sx, 0, 0)])
            rim.loft([lp.ring(c + Vector((o - sx * 0.035, 0, 0)), (1, 0, 0), 0.24, 9, 10),
                      lp.ring(c + Vector((o - sx * 0.02, 0, 0)), (1, 0, 0), 0.11, 9, 10),
                      [c + Vector((o + sx * 0.005, 0, 0))]], "metal_sheet", cap_start=False, cap_end=False,
                     seg_facing=[(sx, 0, 0), (sx, 0, 0)])
            parts += [tyre, H.flat(H.mk(rim))]
    return H.join(parts, "Wheels")


def truck_snow():
    """Rounded snow: hood and roof pillows drooping over the edges, bed-rail lines, a drift in the bed, crate cap."""
    parts = []
    # hood: plane from (y 0.98, z 1.30) to (y 2.40, z 1.21)
    hv = Vector((0, 2.40 - 0.98, 1.21 - 1.30))
    V = hv.normalized()
    N = Vector((0, -V.z, V.y)).normalized()
    L = hv.length

    def hood_lip(u, v):
        return (0.0, 0.0, -0.06 * H.smoothstep(0.10, 0.0, min(u, 1.72 - u)) - 0.08 * H.smoothstep(L - 0.12, L + 0.04, v))
    parts.append(H.pillow(Vector((-0.86, 0.98, 1.30)), (1, 0, 0), V, N, 1.72, L + 0.03, 0.10, nu=6, nv=5, rim=0.14,
                          seed=11, lip=hood_lip, bumps=0.02, levels=1))

    def roof_lip(u, v):
        e = min(u, 1.62 - u, v, 0.76 - v)
        return (0.0, 0.0, -0.05 * H.smoothstep(0.10, 0.0, e))
    parts.append(H.pillow(Vector((-0.81, -0.22, 1.92)), (1, 0, 0), (0, 1, 0), (0, 0, 1), 1.62, 0.76, 0.13, nu=6, nv=4,
                          rim=0.14, seed=12, lip=roof_lip, bumps=0.02, levels=1))
    for sx in (-1, 1):
        x = sx * 0.915
        parts.append(H.snow_strip((x, -2.36, 1.32), (x, -0.34, 1.32), 0.11, 0.06, seed=20 + sx, overhang=0.0))
    parts.append(H.snow_strip((-0.84, -2.38, 1.30), (0.84, -2.38, 1.30), 0.10, 0.05, seed=24, overhang=0.0))
    parts.append(H.snow_strip((-0.84, -0.34, 1.30), (0.84, -0.34, 1.30), 0.10, 0.05, seed=25, overhang=0.0))

    def bed_top(u, v):                               # deeper against the front wall and the sides
        return 0.05 + 0.20 * H.smoothstep(1.2, 1.95, v) + 0.08 * H.smoothstep(0.35, 0.0, min(u, 1.72 - u))
    parts.append(H.pillow(Vector((-0.86, -2.33, BELT)), (1, 0, 0), (0, 1, 0), (0, 0, 1), 1.72, 1.96, 0.2, nu=6, nv=6,
                          rim=0.2, seed=13, top_fn=bed_top, jitter=0.02, levels=1))
    parts.append(H.pillow(Vector((-0.77, -2.0, BELT + 0.36)), (1, 0, 0), (0, 1, 0), (0, 0, 1), 0.61, 0.60, 0.07,
                          nu=3, nv=3, rim=0.08, seed=14, levels=1))
    return H.join(parts, "Snow")


def build_pickup_truck():
    """pickup_truck (slice §4.18, ASSET_SPEC_V2 §17; HD v2.1 in G1). Nodes Body (palette_vcol + window),
    Wheels, Snow, BedAnchor; ColChassis / ColCab. Written in the slice convention (+Y = hood) and turned 180
    degrees at creation. G1: chamfered body (3.5 cm, hardened normals) with real wheel arches and dark fender
    flares, split side windows, grille bars, lens colours that do not glare (lamp_clear / lamp_red), mirrors,
    door seams, smooth rounded tyres with steel rims, thick rounded snow pillows on hood and roof drooping over the
    edges, snow lines on the bed rails, a drift in the bed. AO baked in COLOR_0.a."""
    lp.new_scene(authored_front="+Y")
    truck_body()
    truck_wheels()
    truck_snow()
    lp.add_empty("BedAnchor", (0, -1.35, 1.0))
    lp.collision_box("ColChassis", (-1.0, -2.5, 0.3), (1.0, 2.5, 1.3))
    lp.collision_box("ColCab", (-0.95, -0.2, 1.3), (0.95, 1.0, 2.0))
    export.save_and_export("pickup_truck", ao=dict(distance=0.8, samples=64, ground=True))


# ------------------------------------------------------------------------------------------------
def arrow_board(z0, z1, tip_x=0.85, base_x=-0.25, s=-1):
    """Arrow board (pointed end at +X), |y| 0.06..0.12 on the side s (-1 = -Y), text face toward s*Y:
    wood_dark back with a 0.02 border around a wood_light face, snow on top."""
    mb = lp.MeshBuilder()
    zc = (z0 + z1) / 2
    h = (z1 - z0) / 2
    shoulder = tip_x - h * 0.55

    def pent(inset, y):
        y *= s
        return [Vector((base_x + inset, y, z0 + inset)), Vector((shoulder - inset * 0.4, y, z0 + inset)),
                Vector((tip_x - inset * 1.4, y, zc)), Vector((shoulder - inset * 0.4, y, z1 - inset)),
                Vector((base_x + inset, y, z1 - inset))]
    mb.prism(pent(0.0, 0.06), (0, s * 0.06, 0), (0, s * 0.105, 0), "wood_dark", snow=True)
    mb.prism(pent(0.02, 0.105), (0, s * 0.105, 0), (0, s * 0.12, 0), "wood_light")
    mb.snow(0.55)
    # snow strip along the top edge
    y0, y1 = sorted((s * 0.055, s * 0.125))
    mb.box((base_x, y0, z1), (shoulder, y1, z1 + 0.035), "snow", skip=('-z',))
    return mb


def build_signpost():
    lp.new_scene()
    post = lp.MeshBuilder()
    post.box((-0.06, -0.06, 0.0), (0.06, 0.06, 2.2), "wood", skip=('-z',))
    post.loft([lp.rrect((0, 0, 2.2), 0.075, 0.075, 0.02), [Vector((0, 0, 2.27))]], "snow")   # snow cap
    # small brace at the foot and a snow mound
    post.cylinder((0, 0, 0), (0, 0, 0.1), 0.3, 0.16, 8, "snow", cap0=False, phase=22.5)
    lp.to_object(post, "Post")
    top = lp.to_object(arrow_board(1.70, 1.98), "BoardTop", (0, 0, 1.84))
    bottom = lp.to_object(arrow_board(1.30, 1.58), "BoardBottom", (0, 0, 1.44))
    # text anchors, unrotated: local +Z (Godot) = -Y Blender = the board's text face; +X (the arrow tip) is
    # the reader's right, so a Label3D child with identity transform reads left-to-right toward the tip
    lp.add_empty("TextTop", (0.28, -0.125, 1.84), parent=top)
    lp.add_empty("TextBottom", (0.28, -0.125, 1.44), parent=bottom)
    export.save_and_export("signpost")


# ------------------------------------------------------------------------------------------------
def build_fence():
    lp.new_scene()
    mb = lp.MeshBuilder()
    for x in (-0.94, 0.94):
        mb.box((x - 0.06, -0.06, 0.0), (x + 0.06, 0.06, 1.1), "wood", skip=('-z',))
        mb.box((x - 0.065, -0.065, 1.1), (x + 0.065, 0.065, 1.13), "snow", skip=('-z',))
    for z0 in (0.40, 0.80):
        mb.box((-1.0, 0.06, z0), (1.0, 0.12, z0 + 0.12), "wood")
        mb.box((-1.0, 0.055, z0 + 0.12), (1.0, 0.125, z0 + 0.15), "snow", skip=('-z',))
    lp.to_object(mb, "Fence")
    export.save_and_export("fence")


# ------------------------------------------------------------------------------------------------
AF_H, AF_W = 6.0, 3.0              # ridge height, half width at the ground (outer roof surface = ColBody prism)
AF_Y0, AF_Y1 = -3.7, 3.75          # roof overhang (back / front)
AF_T = 0.2
AF_YF = 3.45                       # front wall outer face
AF_SLOPE = math.hypot(AF_W, AF_H)


def af_roof_point(sx, f, y, off=0.0):
    """Point on the outer roof surface of side sx at slope fraction f (0 = ground, 1 = ridge), offset `off` along
    the outward normal."""
    nx, nz = AF_H / AF_SLOPE, AF_W / AF_SLOPE
    return Vector((sx * AF_W * (1 - f) + sx * nx * off, y, AF_H * f + nz * off))


def a_frame_body():
    """Roof slabs with standing seams, cream rake boards, ridge cap, back wall, thick snow + ground drifts."""
    hard, fine, snow = lp.MeshBuilder(), lp.MeshBuilder(), []
    nx, nz = AF_H / AF_SLOPE, AF_W / AF_SLOPE
    for sx in (-1, 1):
        outer_b, outer_t = Vector((sx * AF_W, 0, 0)), Vector((0, 0, AF_H))
        inner_b = Vector((sx * (AF_W - AF_T / nx), 0, 0))
        inner_t = Vector((0, 0, AF_H - AF_T / nz))
        prof = [outer_b, outer_t, inner_t, inner_b]
        hard.prism([p + Vector((0, AF_Y0, 0)) for p in prof], (0, AF_Y0, 0), (0, AF_Y1, 0), "roof")
        # standing seams every 0.46 m along the slope (fine, no chamfer)
        k = 0
        y = AF_Y0 + 0.2
        while y < AF_Y1 - 0.15:
            a0 = af_roof_point(sx, 0.04, y)
            a1 = af_roof_point(sx, 0.985, y)
            n = Vector((sx * nx, 0, nz))
            cs = []
            for i in range(8):
                base = a1 if i & 2 else a0
                cs.append(base + Vector((0, 0.016 if i & 1 else -0.016, 0)) + (n * 0.028 if i & 4 else Vector()))
            fine.hexa(cs, "roof_seam")
            y += 0.46
            k += 1
        # rake boards (cream) along the front and back roof edges
        for yb, d in ((AF_Y1, 0.07), (AF_Y0, -0.07)):
            a0 = af_roof_point(sx, 0.0, yb - d * 0.5, 0.02)
            a1 = af_roof_point(sx, 1.0, yb - d * 0.5, 0.02)
            H.beam(hard, a0 + Vector((0, 0, 0.0)), a1, 0.07, 0.24, "cabin_trim", up=(sx * nx, 0, nz))
        # snow: thick pillow on the upper 65 % of the slope, cornice at the lower edge, crest over the ridge
        U = Vector((0, 1, 0))
        V = (outer_t - outer_b).normalized()
        N = Vector((sx * nx, 0, nz))
        f0 = 0.36 + (0.04 if sx > 0 else 0.0)
        origin = af_roof_point(sx, f0, AF_Y0 + 0.10)
        size_u = (AF_Y1 - AF_Y0) - 0.20
        size_v = (1 - f0) * AF_SLOPE + 0.10
        seed = 30 + sx

        def lip(u, v, seed=seed, size_v=size_v):
            dv = 0.0
            if v <= 1e-6:
                dv = -0.45 * H.fbm(u * 0.55, seed * 1.7, 2, seed) - 0.15
            dn = -0.10 * H.smoothstep(0.30, 0.0, v)
            dn -= 0.06 * H.smoothstep(0.12, 0.0, min(u, size_u - u))
            if v >= size_v - 1e-6:
                dn -= 0.10                                  # the crest folds over the ridge
            return (0.0, dv, dn)
        o = H.pillow(origin, U, V, N if sx > 0 else N, size_u, size_v, 0.22, nu=10, nv=6, rim=0.2, seed=seed,
                     lip=lip, bumps=0.04, levels=1)
        snow.append(o)
        # lumps on the dark lower band
        for j, (yy, ff) in enumerate(((-2.2, 0.20), (0.4, 0.16), (2.3, 0.22))):
            base = af_roof_point(sx, ff, yy)
            lu, lv = 0.8, 0.5
            snow.append(H.pillow(base - U * (lu / 2) - V * (lv / 2), U, V, N, lu, lv, 0.13, nu=4, nv=4, rim=0.12,
                                 seed=40 + j + (5 if sx > 0 else 0), jitter=0.03, levels=1))

        # ground drift piled against the roof foot (wedge, highest at the roof)
        def drift_top(u, v):
            t = max(0.0, 1.0 - v / 0.58)
            return 0.03 + 0.42 * t ** 0.9 * (0.75 + 0.25 * math.sin(u * 1.3 + sx))
        snow.append(H.pillow(Vector((sx * (AF_W - 0.30), AF_Y0 + 0.2, -0.05)), (0, 1, 0) if sx > 0 else (0, -1, 0),
                             (sx, 0, 0), (0, 0, 1), (AF_Y1 - AF_Y0) - 0.4, 0.58, 0.45, nu=9, nv=4, rim=0.16,
                             seed=50 + sx, top_fn=drift_top, jitter=0.03, bottom=-0.05, levels=1)
                     if sx > 0 else
                     H.pillow(Vector((sx * (AF_W - 0.30), AF_Y1 - 0.2, -0.05)), (0, -1, 0), (sx, 0, 0), (0, 0, 1),
                              (AF_Y1 - AF_Y0) - 0.4, 0.58, 0.45, nu=9, nv=4, rim=0.16, seed=50 + sx, top_fn=drift_top,
                              jitter=0.03, bottom=-0.05, levels=1))
    # ridge cap
    hard.prism([Vector((0.0, AF_Y0, AF_H + 0.10)), Vector((-0.16, AF_Y0, AF_H - 0.08)), Vector((0.16, AF_Y0, AF_H - 0.08))],
               (0, AF_Y0, 0), (0, AF_Y1, 0), "roof_seam")
    # back wall (triangle) with board-and-batten
    fine.prism([Vector((-2.9, -3.45, 0)), Vector((2.9, -3.45, 0)), Vector((0, -3.45, 5.8))], (0, -3.45, 0),
               (0, -3.3, 0), "wood_dark")
    for x in (-2.1, -1.4, -0.7, 0.0, 0.7, 1.4, 2.1):
        ztop = 5.8 * (1 - (abs(x) + 0.05) / 2.9) - 0.08
        fine.box((x - 0.03, -3.48, 0.1), (x + 0.03, -3.45, ztop), "wood")
    body = H.mk(hard)
    H.bevel(body, 0.02, 1, angle=30)
    H.snap_colors(body)
    return H.join([body, H.flat(H.mk(fine))] + snow, "Body")


def a_frame_front():
    """Gable wall (board and batten), exposed truss, door with canopy, big 2x2 window with sill; pane separately."""
    hard, fine, snow = lp.MeshBuilder(), lp.MeshBuilder(), []
    yf = AF_YF
    fine.prism([Vector((-2.9, yf - 0.12, 0)), Vector((2.9, yf - 0.12, 0)), Vector((0, yf - 0.12, 5.8))],
               (0, yf - 0.12, 0), (0, yf, 0), "wood")
    door = (0.15, 1.05, 0.25, 2.25)
    win = (-1.30, -0.10, 2.40, 3.60)
    for x in [(-2.45 + 0.35 * k) for k in range(15)]:          # battens every 0.35 m
        segs = [(0.25, 5.8)]
        for (u0, u1, z0, z1) in (door, win):
            if u0 - 0.12 < x < u1 + 0.12:
                nsegs = []
                for (a_, b_) in segs:
                    if z0 - 0.10 > a_:
                        nsegs.append((a_, min(b_, z0 - 0.10)))
                    if z1 + 0.12 < b_:
                        nsegs.append((max(a_, z1 + 0.12), b_))
                segs = nsegs
        for a_, b_ in segs:
            ztop = min(b_, 5.8 * (1 - (abs(x) + 0.05) / 2.9) - 0.12)
            if ztop - a_ > 0.25:
                fine.box((x - 0.028, yf, a_), (x + 0.028, yf + 0.025, ztop), "wood_dark")
    # skirt board along the bottom
    hard.box((-2.9, yf, 0.0), (2.9, yf + 0.05, 0.25), "wood_dark")
    # exposed A-frame truss: two edge beams, collar tie, king post, struts
    for sx in (-1, 1):
        yb = yf + 0.22 + (0.012 if sx > 0 else 0.0)
        H.beam(hard, (sx * 3.05, yb, 0.0), (sx * 0.02, yb, AF_H + 0.04), 0.18, 0.22, "wood_light", up=(0, 1, 0))
        H.beam(hard, (sx * 0.05, yf + 0.10, 4.05), (sx * 1.08, yf + 0.10, 3.95 - 1.0 * 0.62), 0.10, 0.10, "wood_light",
               up=(0, 1, 0))
    hard.box((-1.05, yf + 0.03, 3.92), (1.05, yf + 0.19, 4.14), "wood_light")                      # collar tie
    hard.box((-0.07, yf + 0.04, 4.14), (0.07, yf + 0.18, 5.72), "wood_light")                      # king post
    # door: frame, leaf with two raised panels, handle; canopy with snow on top
    u0, u1, z0, z1 = door
    fine.box((u0, yf, z0), (u1, yf + 0.012, z1), "wood_dark")
    for pz0, pz1 in ((0.40, 1.15), (1.30, 2.10)):
        hard.box((u0 + 0.12, yf + 0.012, pz0), (u1 - 0.12, yf + 0.04, pz1), "wood")
    hard.box((u0 - 0.09, yf, z0), (u0, yf + 0.06, z1 + 0.09), "cabin_trim")
    hard.box((u1, yf, z0), (u1 + 0.09, yf + 0.06, z1 + 0.09), "cabin_trim")
    hard.box((u0, yf, z1), (u1, yf + 0.06, z1 + 0.09), "cabin_trim")
    fine.box((0.90, yf + 0.04, 1.18), (0.96, yf + 0.08, 1.30), "iron")
    hard.hexa([(u0 - 0.25, yf, z1 + 0.14), (u1 + 0.25, yf, z1 + 0.14), (u0 - 0.25, yf + 0.55, z1 + 0.02),
               (u1 + 0.25, yf + 0.55, z1 + 0.02), (u0 - 0.25, yf, z1 + 0.22), (u1 + 0.25, yf, z1 + 0.22),
               (u0 - 0.25, yf + 0.55, z1 + 0.10), (u1 + 0.25, yf + 0.55, z1 + 0.10)], "roof")
    for x in (u0 - 0.2, u1 + 0.2):
        H.beam(hard, (x, yf, z1 - 0.28), (x, yf + 0.42, z1 + 0.06), 0.06, 0.06, "wood_light", up=(1, 0, 0))
    cv = Vector((0, 0.55, -0.12)).normalized()
    cn = Vector((0, 0.12, 0.55)).normalized()
    snow.append(H.pillow(Vector((u0 - 0.27, yf + 0.02, z1 + 0.22)), (1, 0, 0), cv, cn, (u1 - u0) + 0.54, 0.58, 0.10,
                         nu=4, nv=3, rim=0.08, seed=61, levels=1,
                         lip=lambda u, v: (0.0, 0.0, -0.05 * H.smoothstep(0.45, 0.6, v))))
    # window: deep frame, 2x2 mullions, sill + drip cap with snow lines; pane = WindowsFront
    w0, w1, wz0, wz1 = win
    fw, d = 0.09, 0.08
    hard.box((w0 - fw, yf, wz0 - fw), (w0, yf + d, wz1 + fw), "cabin_trim")
    hard.box((w1, yf, wz0 - fw), (w1 + fw, yf + d, wz1 + fw), "cabin_trim")
    hard.box((w0, yf, wz1), (w1, yf + d, wz1 + fw), "cabin_trim")
    hard.box((w0, yf, wz0 - fw), (w1, yf + d, wz0), "cabin_trim")
    fine.box(((w0 + w1) / 2 - 0.02, yf, wz0), ((w0 + w1) / 2 + 0.02, yf + 0.05, wz1), "cabin_trim")
    fine.box((w0, yf, (wz0 + wz1) / 2 - 0.02), (w1, yf + 0.05, (wz0 + wz1) / 2 + 0.02), "cabin_trim")
    hard.box((w0 - fw - 0.06, yf, wz0 - fw - 0.07), (w1 + fw + 0.06, yf + 0.14, wz0 - fw), "cabin_trim")
    hard.box((w0 - fw - 0.04, yf, wz1 + fw), (w1 + fw + 0.04, yf + 0.11, wz1 + fw + 0.06), "cabin_trim")
    snow.append(H.snow_strip((w0 - fw - 0.04, yf + 0.07, wz0 - fw), (w1 + fw + 0.04, yf + 0.07, wz0 - fw), 0.12, 0.07,
                             seed=62, overhang=0.0))
    snow.append(H.snow_strip((w0 - fw - 0.02, yf + 0.055, wz1 + fw + 0.06), (w1 + fw + 0.02, yf + 0.055, wz1 + fw + 0.06),
                             0.09, 0.045, seed=63, overhang=0.0))
    # small louvred vent under the ridge
    fine.prism([Vector((-0.42, yf, 4.55)), Vector((0.42, yf, 4.55)), Vector((0.0, yf, 5.15))], (0, yf, 0),
               (0, yf + 0.03, 0), "wood_dark")
    lp.clamp_ground(hard)
    lp.clamp_ground(fine)
    body = H.mk(hard)
    H.bevel(body, 0.018, 1, angle=30)
    H.snap_colors(body)
    front = H.join([body, H.flat(H.mk(fine))] + snow, "Front")
    pane = lp.MeshBuilder()
    pane.poly([(w0, yf + 0.008, wz0), (w1, yf + 0.008, wz0), (w1, yf + 0.008, wz1), (w0, yf + 0.008, wz1)], "window",
              facing=(0, 1, 0))
    H.flat(H.mk(pane, "WindowsFront", parent=front))
    return front


def a_frame_deck():
    """Deck: boards with gaps on a dark rim, posts with snow caps, rails with snow lines, balusters, a step."""
    hard, fine, snow = lp.MeshBuilder(), lp.MeshBuilder(), []
    fine.box((-2.0, 3.4, 0.0), (2.0, 5.0, 0.18), "wood_dark", skip=('-z',))
    n, gap = 9, 0.018
    pw = (1.6 - (n - 1) * gap) / n
    for k in range(n):
        y0 = 3.4 + k * (pw + gap)
        hard.box((-1.98, y0, 0.18), (1.98, y0 + pw, 0.25), "wood")
    hard.box((-0.55, 5.0, 0.0), (0.55, 5.34, 0.12), "wood")                      # step
    posts = [(-1.9, 4.9), (1.9, 4.9), (-1.9, 3.55), (1.9, 3.55), (-0.62, 4.9), (0.62, 4.9)]
    for x, y in posts:
        hard.box((x - 0.06, y - 0.06, 0.25), (x + 0.06, y + 0.06, 1.12), "wood")
        hard.box((x - 0.08, y - 0.08, 1.12), (x + 0.08, y + 0.08, 1.18), "wood_light")
        snow.append(H.pillow((x - 0.09, y - 0.09, 1.18), (1, 0, 0), (0, 1, 0), (0, 0, 1), 0.18, 0.18, 0.07, nu=3, nv=3,
                             rim=0.05, seed=int(70 + x * 10 + y)))
    rails = [((-1.9, 4.9), (-0.62, 4.9)), ((0.62, 4.9), (1.9, 4.9)), ((-1.9, 3.55), (-1.9, 4.9)),
             ((1.9, 3.55), (1.9, 4.9))]
    for (xa, ya), (xb, yb) in rails:
        horiz = abs(yb - ya) < 1e-6
        if horiz:
            hard.box((xa + 0.06, ya - 0.04, 1.02), (xb - 0.06, ya + 0.04, 1.08), "wood_light")
        else:
            hard.box((xa - 0.04, ya + 0.06, 1.02), (xa + 0.04, yb - 0.06, 1.08), "wood_light")
        a_ = Vector((xa, ya, 1.08)) + (Vector((0.07, 0, 0)) if horiz else Vector((0, 0.07, 0)))
        b_ = Vector((xb, yb, 1.08)) - (Vector((0.07, 0, 0)) if horiz else Vector((0, 0.07, 0)))
        snow.append(H.snow_strip(a_, b_, 0.09, 0.05, seed=int(abs(xa * 7 + ya * 3)), overhang=0.0))
        length = abs(xb - xa) + abs(yb - ya)
        count = int(round(length / 0.16)) - 1
        for k in range(1, count + 1):
            t = k / (count + 1)
            x = xa + (xb - xa) * t
            y = ya + (yb - ya) * t
            fine.box((x - 0.02, y - 0.02, 0.25), (x + 0.02, y + 0.02, 1.02), "wood_light", skip=('-z', '+z'))
    # snow on the deck corners (the path to the door stays swept) and a pile beside the step
    for x0 in (-1.86, 0.78):
        snow.append(H.pillow((x0, 4.0, 0.25), (1, 0, 0), (0, 1, 0), (0, 0, 1), 1.08, 0.86, 0.09, nu=4, nv=4, rim=0.12,
                             seed=80 + int(x0 * 3), jitter=0.03, levels=1))
    for x0 in (-1.95, 0.62):
        def pile(u, v):
            return 0.24 * max(0.0, 1.0 - v / 0.55) ** 0.8 + 0.03
        snow.append(H.pillow((x0, 5.0, -0.04), (1, 0, 0), (0, 1, 0), (0, 0, 1), 1.3, 0.55, 0.24, nu=5, nv=4, rim=0.14,
                             seed=90 + int(x0 * 3), top_fn=pile, jitter=0.03, levels=1))
    body = H.mk(hard)
    H.bevel(body, 0.012, 1, angle=30)
    H.snap_colors(body)
    return H.join([body, H.flat(H.mk(fine))] + snow, "Deck")


def build_a_frame_cabin():
    """a_frame_cabin exterior (slice §4.17, ASSET_SPEC_V2 §17; HD v2.1 in G1). Nodes Body, Front (+ child
    WindowsFront: the single window pane, material `window`), Deck; ColBody (prism) + ColDeck. Slice convention
    (+Y = front) turned 180 degrees at creation. G1: dark roof with standing seams, cream rake boards and ridge
    cap, THICK rounded snow on the upper two thirds of both slopes with a wavy cornice, lumps on the dark band,
    drifts piled against the roof foot; board-and-batten gable with an exposed chamfered truss (edge beams,
    collar tie, king post, struts), door with panels and a snow-covered canopy on brackets, deep 2x2 window with
    sill + drip cap carrying snow lines; deck with boards, capped posts, rails with snow lines, balusters, a step
    and snow piles. AO baked in COLOR_0.a."""
    lp.new_scene(authored_front="+Y")
    a_frame_body()
    a_frame_front()
    a_frame_deck()
    pts = [(-3.0, -3.5, 0.0), (3.0, -3.5, 0.0), (0.0, -3.5, 6.0), (-3.0, 3.5, 0.0), (3.0, 3.5, 0.0), (0.0, 3.5, 6.0)]
    faces = [(0, 1, 2), (3, 5, 4), (0, 3, 4, 1), (1, 4, 5, 2), (0, 2, 5, 3)]
    lp.collision_prism("ColBody", pts, faces)
    lp.collision_box("ColDeck", (-2.0, 3.5, 0.0), (2.0, 5.0, 0.25))
    export.save_and_export("a_frame_cabin", ao=dict(distance=1.2, samples=64, ground=True))


def main():
    build_a_frame_cabin()
    build_pickup_truck()
    build_signpost()
    build_fence()


if __name__ == "__main__":
    main()
