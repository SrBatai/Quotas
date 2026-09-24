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
def build_pickup_truck():
    lp.new_scene(authored_front="+Y")
    body = lp.MeshBuilder()
    paint = "truck_paint"
    # frame under the body, visible between the wheels
    body.box((-0.70, -2.30, 0.30), (0.70, 2.30, 0.42), "iron", skip=('+z',))
    # lower body (inboard of the wheels); its top face is the wood bed floor at z 0.80
    body.box((-0.80, -2.40, 0.40), (0.80, 2.40, 0.80), paint, mats={'+z': "wood_dark"})
    # hood (y 1.0..2.4, z up to 1.3, gently sloping forward) with fenders over the front wheels
    body.hexa([(-0.95, 0.95, 0.80), (0.95, 0.95, 0.80), (-0.95, 2.40, 0.80), (0.95, 2.40, 0.80),
               (-0.95, 0.95, 1.30), (0.95, 0.95, 1.30), (-0.93, 2.40, 1.20), (0.93, 2.40, 1.20)], paint,
              skip=('-y',))
    # cab lower + greenhouse (windshield slanted)
    body.box((-0.95, -0.28, 0.80), (0.95, 0.95, 1.30), paint)
    gh = [(-0.93, -0.25, 1.30), (0.93, -0.25, 1.30), (-0.93, 0.95, 1.30), (0.93, 0.95, 1.30),
          (-0.84, -0.20, 1.92), (0.84, -0.20, 1.92), (-0.84, 0.55, 1.92), (0.84, 0.55, 1.92)]
    body.hexa(gh, paint, skip=('-z',))
    g = [Vector(c) for c in gh]
    win = "window"
    ws = [g[2], g[3], g[7], g[6]]                               # windshield face (front)
    body.poly(quad_on(ws, 0.06, 0.94, 0.10, 0.90, 0.006, (0, 0.9, 0.5)), win, facing=(0, 0.9, 0.5))
    rw = [g[1], g[0], g[4], g[5]]                               # rear face
    body.poly(quad_on(rw, 0.12, 0.88, 0.18, 0.85, 0.006, (0, -1, 0)), win, facing=(0, -1, 0))
    for sx in (-1, 1):                                          # side windows
        sd = [g[1], g[3], g[7], g[5]] if sx > 0 else [g[0], g[2], g[6], g[4]]
        body.poly(quad_on(sd, 0.08, 0.80, 0.12, 0.86, 0.006, (sx, 0, 0.12)), win, facing=(sx, 0, 0.12))
    # bed: side walls 0.08 thick up to z 1.3, front wall, closed tailgate, open top
    for sx in (-1, 1):
        body.box((sx * 0.87 if sx > 0 else -0.95, -2.40, 0.80), (0.95 if sx > 0 else -0.87, -0.28, 1.30), paint)
    body.box((-0.87, -2.40, 0.80), (0.87, -2.32, 1.28), paint)                  # tailgate
    # fenders over the rear wheels (flared)
    for sx in (-1, 1):
        body.box((sx * 0.95 if sx > 0 else -1.0, -2.10, 0.80), (1.0 if sx > 0 else -0.95, -1.10, 0.98), paint)
        body.box((sx * 0.95 if sx > 0 else -1.0, 1.10, 0.80), (1.0 if sx > 0 else -0.95, 2.10, 0.98), paint)
    # bumpers, grille, lights, mirrors
    body.box((-0.98, 2.40, 0.42), (0.98, 2.50, 0.66), "iron")
    body.box((-0.98, -2.50, 0.42), (0.98, -2.40, 0.62), "iron")
    body.box((-0.50, 2.40, 0.72), (0.50, 2.42, 1.10), "iron", skip=('-y',))
    for sx in (-1, 1):
        body.box((sx * 0.72 - 0.12, 2.40, 0.96), (sx * 0.72 + 0.12, 2.43, 1.12), "cabin_trim", skip=('-y',))
        body.box((sx * 0.88 - 0.06, -2.43, 1.05), (sx * 0.88 + 0.06, -2.40, 1.22), "can_red", skip=('+y',))
        body.box((sx * 0.95 - (0.08 if sx < 0 else 0), 0.86, 1.34), (sx * 0.95 + (0.08 if sx > 0 else 0), 0.92, 1.48),
                 "iron")
    # a crate in the bed
    body.box((-0.75, -1.95, 0.80), (-0.20, -1.45, 1.15), "wood_dark")
    lp.to_object(body, "Body")

    wheels = lp.MeshBuilder()
    for sx in (-1, 1):
        for sy in (-1, 1):
            c = Vector((sx * 0.95, sy * 1.6, 0.42))
            a = c - Vector((0.125, 0, 0))
            b = c + Vector((0.125, 0, 0))
            wheels.cylinder(a, b, 0.42, 0.42, 12, "iron", phase=15)
            o = c + Vector((sx * 0.125, 0, 0))
            wheels.cylinder(o - Vector((sx * 0.02, 0, 0)), o + Vector((sx * 0.006, 0, 0)), 0.2, 0.18, 8, "stone",
                            cap0=False, phase=22.5)
    lp.to_object(wheels, "Wheels")

    snow = lp.MeshBuilder()
    s = "snow"
    # hood slab (follows the hood slope)
    snow.hexa([(-0.86, 1.0, 1.30), (0.86, 1.0, 1.30), (-0.84, 2.30, 1.215), (0.84, 2.30, 1.215),
               (-0.82, 1.0, 1.40), (0.82, 1.0, 1.40), (-0.80, 2.25, 1.30), (0.80, 2.25, 1.30)], s, skip=('-z',))
    snow.tapered_box(1.92, 2.02, (1.60, 0.70), (1.50, 0.62), s, center=(0, 0.17), skip=('-z',))  # cab roof
    for sx in (-1, 1):                                                                        # bed rim
        snow.box((sx * 0.86 if sx > 0 else -0.96, -2.38, 1.30), (0.96 if sx > 0 else -0.86, -0.30, 1.36), s,
                 skip=('-z',))
    snow.box((-0.86, -2.41, 1.28), (0.86, -2.31, 1.34), s, skip=('-z',))                   # tailgate rim
    snow.box((-0.95, -0.30, 1.30), (0.95, -0.22, 1.36), s, skip=('-z',))                   # front bed wall
    snow.hexa([(-0.86, -2.30, 0.80), (0.86, -2.30, 0.80), (-0.86, -0.40, 0.80), (0.86, -0.40, 0.80),
               (-0.86, -2.30, 0.95), (0.86, -2.30, 0.95), (-0.86, -0.40, 0.86), (0.86, -0.40, 0.86)], s,
              skip=('-z',))                                                                  # drift in the bed
    snow.box((-0.76, -1.96, 1.15), (-0.19, -1.44, 1.20), s, skip=('-z',))                  # on the crate
    lp.to_object(snow, "Snow")
    lp.add_empty("BedAnchor", (0, -1.35, 1.0))
    lp.collision_box("ColChassis", (-1.0, -2.5, 0.3), (1.0, 2.5, 1.3))
    lp.collision_box("ColCab", (-0.95, -0.2, 1.3), (0.95, 1.0, 2.0))
    export.save_and_export("pickup_truck")


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
def build_a_frame_cabin():
    lp.new_scene(authored_front="+Y")
    H, W, D = 6.0, 3.0, 3.5          # ridge height, half width, half depth
    t = 0.2
    body = lp.MeshBuilder()
    slope_len = math.hypot(W, H)
    nx, nz = H / slope_len, W / slope_len       # outward normal of the +X slope
    y0, y1 = -3.7, 3.75                         # roof overhangs the end walls a little
    for sx in (-1, 1):
        # roof slab: outer surface on the collision prism (x = +-3 at z 0 -> ridge z 6), 0.2 thick inward
        outer_b, outer_t = Vector((sx * W, 0, 0)), Vector((0, 0, H))
        inner_b = Vector((sx * (W - t / nx), 0, 0))          # inner face cut flat at the ground
        inner_t = Vector((0, 0, H - t / nz))
        prof = [outer_b, outer_t, inner_t, inner_b]
        body.prism([p + Vector((0, y0, 0)) for p in prof], (0, y0, 0), (0, y1, 0), "roof")
        # snow slab on the upper part of the slope
        f0, f1 = 0.28, 1.0
        a0 = outer_b.lerp(outer_t, f0)
        a1 = outer_b.lerp(outer_t, f1)
        up = Vector((sx * nx, 0, nz)) * 0.16
        top_ridge = Vector((0, 0, H + 0.16 / nz))
        prof = [a0, a1, top_ridge, a0 + up]
        body.prism([p + Vector((0, y0 + 0.08, 0)) for p in prof], (0, y0 + 0.08, 0), (0, y1 - 0.08, 0), "snow")
        # drift where the roof meets the ground
        body.prism([Vector((sx * (W + 0.22), y0, 0)), Vector((sx * (W - 0.05), y0, 0)),
                    Vector((sx * (W - 0.05), y0, 0.32))], (0, y0, 0), (0, y1, 0), "snow")
    # back triangle wall
    body.prism([Vector((-2.9, -3.45, 0)), Vector((2.9, -3.45, 0)), Vector((0, -3.45, 5.8))], (0, -3.45, 0),
               (0, -3.3, 0), "wood_dark")
    lp.to_object(body, "Body")

    front = lp.MeshBuilder()
    yf = 3.45                                   # front wall outer face
    front.prism([Vector((-2.9, yf - 0.12, 0)), Vector((2.9, yf - 0.12, 0)), Vector((0, yf - 0.12, 5.8))],
                (0, yf - 0.12, 0), (0, yf, 0), "wood")

    def half_width(z):
        return 2.9 * (1 - z / 5.8)
    door = (0.15, 1.05, 0.25, 2.25)
    window = (-1.28, -0.12, 2.42, 3.58)
    for x in (-2.2, -1.55, -0.65, 0.4, 1.55, 2.2):            # vertical dark planks
        segs = [(0.25, 5.8)]
        for (u0, u1, z0, z1) in (door, window):
            if u0 - 0.05 < x < u1 + 0.05:
                nsegs = []
                for (a, b) in segs:
                    if z0 > a:
                        nsegs.append((a, min(b, z0 - 0.08)))
                    if z1 < b:
                        nsegs.append((max(a, z1 + 0.08), b))
                segs = nsegs
        for a, b in segs:
            ztop = min(b, 5.8 * (1 - (abs(x) + 0.05) / 2.9) - 0.1)
            if ztop - a > 0.3:
                front.box((x - 0.035, yf, a), (x + 0.035, yf + 0.02, ztop), "wood_dark", skip=('-y',))
    # light timber A-frame beams along the front edges and a collar beam
    for sx in (-1, 1):
        yb = yf + 0.3 + (0.012 if sx > 0 else 0.0)        # avoid coplanar faces where the beams cross
        a = Vector((sx * 3.02, yb, 0.0))
        b = Vector((0.0, yb, H + 0.02))
        front.cylinder(a, b, 0.09, 0.09, 4, "wood_light", phase=45)
    front.box((-0.85, yf, 3.9), (0.85, yf + 0.14, 4.08), "wood_light", skip=('-y',))      # collar beam
    # door quad + trim frame
    u0, u1, z0, z1 = 0.15, 1.05, 0.25, 2.25
    front.poly([(u0, yf + 0.01, z0), (u1, yf + 0.01, z0), (u1, yf + 0.01, z1), (u0, yf + 0.01, z1)], "wood_dark",
               facing=(0, 1, 0))
    for (a0, a1, b0, b1) in ((u0 - 0.08, u0, z0, z1 + 0.08), (u1, u1 + 0.08, z0, z1 + 0.08), (u0, u1, z1, z1 + 0.08)):
        front.box((a0, yf, b0), (a1, yf + 0.04, b1), "cabin_trim", skip=('-y',))
    front.box((0.88, yf + 0.01, 1.2), (0.94, yf + 0.05, 1.3), "iron", skip=('-y',))        # door handle
    # window trim + mullions (palette colours, part of Front; the pane alone is WindowsFront)
    wu0, wu1, wz0, wz1 = -1.2, -0.2, 2.5, 3.5
    w = 0.08
    for (a0, a1, b0, b1) in ((wu0 - w, wu0, wz0 - w, wz1 + w), (wu1, wu1 + w, wz0 - w, wz1 + w),
                             (wu0, wu1, wz1, wz1 + w), (wu0, wu1, wz0 - w, wz0)):
        front.box((a0, yf, b0), (a1, yf + 0.04, b1), "cabin_trim", skip=('-y',))
    front.box((-0.72, yf, wz0), (-0.68, yf + 0.025, wz1), "cabin_trim", skip=('-y',))
    front.box((wu0, yf, 2.98), (wu1, yf + 0.025, 3.02), "cabin_trim", skip=('-y',))
    lp.clamp_ground(front)
    fo = lp.to_object(front, "Front")

    wmb = lp.MeshBuilder()
    wmb.poly([(wu0, yf + 0.01, wz0), (wu1, yf + 0.01, wz0), (wu1, yf + 0.01, wz1), (wu0, yf + 0.01, wz1)], "window",
             facing=(0, 1, 0))
    lp.to_object(wmb, "WindowsFront", parent=fo)

    deck = lp.MeshBuilder()
    deck.box((-2.0, 3.4, 0.0), (2.0, 5.0, 0.25), "wood", skip=('-z',))
    for i in range(1, 6):                                                      # plank grooves
        y = 3.5 + i * 0.25
        deck.box((-2.0, y - 0.01, 0.25), (2.0, y + 0.01, 0.255), "wood_dark", skip=('-z',))
    for sx in (-1, 1):
        deck.box((sx * 1.9 - 0.06, 4.84, 0.25), (sx * 1.9 + 0.06, 4.96, 1.2), "wood", skip=('-z',),
                 mats={'+z': "snow"})
        deck.box((sx * 1.9 - 0.04, 3.5, 1.0), (sx * 1.9 + 0.04, 4.84, 1.08), "wood", mats={'+z': "snow"})
    deck.box((-1.84, 4.86, 1.0), (-0.3, 4.94, 1.08), "wood", mats={'+z': "snow"})
    lp.to_object(deck, "Deck")

    # collision: triangular prism for the whole body, box for the deck
    pts = [(-3.0, -3.5, 0.0), (3.0, -3.5, 0.0), (0.0, -3.5, 6.0), (-3.0, 3.5, 0.0), (3.0, 3.5, 0.0), (0.0, 3.5, 6.0)]
    faces = [(0, 1, 2), (3, 5, 4), (0, 3, 4, 1), (1, 4, 5, 2), (0, 2, 5, 3)]
    lp.collision_prism("ColBody", pts, faces)
    lp.collision_box("ColDeck", (-2.0, 3.5, 0.0), (2.0, 5.0, 0.25))
    export.save_and_export("a_frame_cabin")


def main():
    build_a_frame_cabin()
    build_pickup_truck()
    build_signpost()
    build_fence()


if __name__ == "__main__":
    main()
