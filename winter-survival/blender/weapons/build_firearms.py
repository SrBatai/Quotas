"""Firearms, bow, arrow and muzzle flash — ASSET_SPEC_V2 §12 + "T2" (milestone M5).

    cd winter-survival/blender && python3 weapons/build_firearms.py [pistol bow ...]

Exports assets/models/weapons/<name>.glb (+ sources/<name>.blend + the Godot `.import`, template "prop"). Same frame
as the M4 melee weapons (weapons/build_weapons.py): origin = centre of the right fist on the main grip, handle +Z
Blender (+Y Godot), muzzle -Y Blender (+Z Godot); mounted with IDENTITY on RightHandSocket. With the muzzle forward,
weapon +X is the SHOOTER'S LEFT (ejection ports and the bolt handle sit at -X, the revolver cylinder swings to +X).
Every number that the animations rely on lives in lib/gunspec.py (support grip, loose-part origins, travels).

Nodes (all top level, like M4): the fixed mesh `Weapon` (1 palette surface; extras weapon_class, length, caliber,
capacity), moving parts as separate meshes whose origin is their pivot (Slide, Pump, Bolt, Cylinder, Scope, String,
StringDrawn), loose parts whose origin is the LEFT fist centre that carries them (Magazine, Round, Arrow), and empties
Grip (origin), Muzzle, SupportGrip, Sight, EjectPort, LoadPort, DrawPoint.

  pistol         9 mm polymer pistol x1.2 (0.24 m): black frame, dark slide, 15-round Magazine in the grip
  revolver       .357 stainless revolver x1.2 (0.34 m): wood grip, Cylinder swings out to the left (+X), Round
  shotgun        pump shotgun 1.0 m: wood Pump (slides back 8.5 cm) and stock, tube magazine, red shell Round
  rifle_hunting  bolt-action .308 1.1 m: walnut stock, Bolt (lift 60 deg + 8 cm back), Scope (glass lenses), Round
  bow            1.3 m flat bow held in the RIGHT fist; String (braced), StringDrawn (full draw), nocked Arrow
  arrow          0.7 m arrow projectile (origin at the middle, tip toward -Y / +Z Godot): Tip, Nock
  muzzle_flash   star-shaped flash (emissive_lamp), origin at the muzzle, pointing -Y: place it at Muzzle
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import bpy  # noqa: E402,F401
from mathutils import Matrix, Vector  # noqa: E402

from lib import export  # noqa: E402
from lib import gunspec as G  # noqa: E402
from lib import hd as H  # noqa: E402
from lib import lowpoly as lp  # noqa: E402

SUBDIR = "weapons"
BUDGET = 900                     # doc 05 §4.5 v2.1: hand-held weapon 100 - 900 (all meshes of the file)
X_AX, Y_AX, Z_AX = Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))


# ------------------------------------------------------------------------------------------------------------
# geometry helpers (weapon frame, metres)
# ------------------------------------------------------------------------------------------------------------
def rring(c, u, w, a, b, ch):
    """8-point chamfered rectangle around c in the plane (u, w): half sizes a (along u), b (along w)."""
    c, u, w = Vector(c), Vector(u), Vector(w)
    ch = min(ch, a * 0.9, b * 0.9)
    pts = [(a, b - ch), (a - ch, b), (-a + ch, b), (-a, b - ch), (-a, -b + ch), (-a + ch, -b), (a - ch, -b),
           (a, -b + ch)]
    return [c + u * x + w * y for x, y in pts]


def bar_y(mb, ys, xs, zs, mats, ch=0.004, caps=(True, True), cap_mats=(None, None)):
    """Chamfered bar along Y through sections at ys; xs[i] = half width, zs[i] = (z0, z1); mats = one per segment."""
    rings = []
    for y, hx, (z0, z1) in zip(ys, xs, zs):
        rings.append(rring((0.0, y, (z0 + z1) / 2), X_AX, Z_AX, hx, (z1 - z0) / 2, ch))
    mats = mats if isinstance(mats, (list, tuple)) else [mats] * (len(ys) - 1)
    return mb.loft(rings, mats[0], cap_start=caps[0], cap_end=caps[1], side_mats=list(mats),
                   cap_mats=(cap_mats[0] or mats[0], cap_mats[1] or mats[-1]))


def bar_axis(mb, c0, axis, t0, t1, u, a, b, mat, ch=0.004, extra=()):
    """Chamfered bar from c0 + axis*t0 to c0 + axis*t1, section half sizes a (along u) and b (along axis x u)."""
    axis = Vector(axis).normalized()
    u = Vector(u).normalized()
    w = axis.cross(u).normalized()
    ts = [t0] + [e[0] for e in extra] + [t1]
    rings = []
    for k, t in enumerate(ts):
        aa, bb = (a, b) if k in (0, len(ts) - 1) or not extra else (extra[k - 1][1], extra[k - 1][2])
        rings.append(rring(Vector(c0) + axis * t, u, w, aa, bb, ch))
    return mb.loft(rings, mat)


def cyl_y(mb, y0, y1, r0, r1, sides, mat, x=0.0, z=0.0, phase=0.0, caps=(True, True), cap_mats=(None, None)):
    return mb.cylinder((x, y0, z), (x, y1, z), r0, r1, sides, mat, cap0=caps[0], cap1=caps[1], phase=phase,
                       cap_mats=cap_mats)


def cyl_x(mb, x0, x1, r, sides, mat, y=0.0, z=0.0):
    return mb.cylinder((x0, y, z), (x1, y, z), r, r, sides, mat)


def lathe_y(mb, prof, sides, mats, x=0.0, z=0.0, phase=0.0):
    """Surface of revolution about the Y axis through (x, *, z): prof = [(y, r)] (r = 0 closes an end)."""
    rings = []
    for y, r in prof:
        if r <= 1e-6:
            rings.append([mb._v((x, y, z))])
        else:
            rings.append([mb._v(p) for p in lp.ring(Vector((x, y, z)), Vector((0, 1, 0)), r, sides, phase)])
    mats = mats if isinstance(mats, (list, tuple)) else [mats] * (len(prof) - 1)
    sgn = 1.0 if prof[-1][0] >= prof[0][0] else -1.0     # facing assumes a profile running toward +Y
    out = []
    for k in range(len(prof) - 1):
        (y0, r0), (y1, r1) = prof[k], prof[k + 1]
        dy, dr = y1 - y0, r1 - r0
        a, b = rings[k], rings[k + 1]
        for j in range(sides):
            if len(a) == 1:
                idx = (a[0], b[j], b[(j + 1) % sides])
            elif len(b) == 1:
                idx = (a[j], a[(j + 1) % sides], b[0])
            else:
                idx = (a[j], a[(j + 1) % sides], b[(j + 1) % sides], b[j])
            c = sum((mb.verts[i] for i in idx), Vector()) / len(idx)
            radial = Vector((c.x - x, 0.0, c.z - z))
            radial = radial.normalized() if radial.length > 1e-9 else Vector()
            out.append(mb.add_face(idx, mats[k], facing=(radial * dy + Vector((0, -dr, 0))) * sgn))
    return out


def lathe_along(mb, origin, axis, prof, sides, mats, phase=0.0):
    """lathe about an arbitrary axis: builds along Y then rotates / translates."""
    n0 = len(mb.verts)
    lathe_y(mb, prof, sides, mats, phase=phase)
    rot = Vector((0, 1, 0)).rotation_difference(Vector(axis).normalized()).to_matrix().to_4x4()
    mb.transform(Matrix.Translation(Vector(origin)) @ rot, verts_from=n0)


def shade(o, angle=40.0):
    H.smooth(o, angle)
    return o


def mk(mb, name, pivot=(0, 0, 0), angle=40.0):
    o = H.mk(mb, name, pivot)
    return shade(o, angle)


def recolor_alternate(mb, faces, mat, axis_pt, period=2):
    """Paint every other side face (by its angle about the Y axis through axis_pt) with `mat` (flutes / grooves)."""
    for fi in faces:
        c = mb.center(fi)
        n = mb.normal(fi)
        if abs(n.y) > 0.5:
            continue
        ang = math.atan2(c.z - axis_pt[1], c.x - axis_pt[0])
        k = int(round(ang / (2 * math.pi) * 12)) % 12
        if k % period == 0:
            mb.faces[fi][1] = mat


# ------------------------------------------------------------------------------------------------------------
# pistol (9 mm, x1.2 already in the numbers)
# ------------------------------------------------------------------------------------------------------------
def build_pistol():
    d = G.GRIP_AXIS
    back = Vector((0.0, math.cos(math.radians(G.GRIP_TILT_DEG)), math.sin(math.radians(G.GRIP_TILT_DEG))))
    fr = lp.MeshBuilder()
    # frame (polymer): dust cover + rail, trigger guard, trigger, grip (tilted), beavertail
    bar_y(fr, [-0.134, -0.128, 0.068, 0.076], [0.0125, 0.0135, 0.0135, 0.012],
          [(0.040, 0.057), (0.038, 0.058), (0.038, 0.058), (0.042, 0.058)], "plastic_black", ch=0.003)
    fr.box((-0.0095, -0.132, 0.030), (0.0095, -0.082, 0.040), "plastic_black")                 # accessory rail
    fr.box((-0.006, -0.082, 0.004), (0.006, -0.073, 0.040), "plastic_black")                   # guard front
    fr.box((-0.006, -0.082, 0.001), (0.006, -0.020, 0.009), "plastic_black")                   # guard bottom
    fr.box((-0.0028, -0.050, 0.012), (0.0028, -0.042, 0.037), "iron")                          # trigger
    bar_axis(fr, (0, 0, 0), d, G.PISTOL_GRIP_T[0], G.PISTOL_GRIP_T[1], X_AX, 0.0165, 0.029, "plastic_black",
             ch=0.006, extra=((-0.030, 0.0172, 0.0295), (0.020, 0.017, 0.029)))
    # grip texture panels (slightly raised stipple) on both sides
    for sx in (-1, 1):
        c = d * (-0.022) + back * 0.004
        fr.cbox((sx * 0.0162, c.y, c.z), (0.003, 0.034, 0.062), "iron")
    # slide
    sl = lp.MeshBuilder()
    y0, y1 = G.PISTOL_SLIDE
    ys = [y0, y0 + 0.006, 0.046, 0.051, 0.056, 0.061, 0.066, 0.071, y1]
    mats = ["gun_metal", "gun_metal", "gun_metal", "iron", "gun_metal", "iron", "gun_metal", "gun_metal"]
    bar_y(sl, ys, [0.0135] + [0.0150] * 8, [(0.058, 0.090)] + [(0.056, 0.092)] * 8, mats, ch=0.005)
    cyl_y(sl, y0 - 0.0015, y0 + 0.004, 0.0068, 0.0068, 8, "iron", z=G.PISTOL_BORE_Z)           # muzzle bore
    sl.box((-0.0022, -0.142, 0.091), (0.0022, -0.134, 0.0985), "iron")                         # front sight
    sl.box((-0.0012, -0.1385, 0.0945), (0.0012, -0.1345, 0.0975), "paint_white")               # its dot
    sl.box((-0.0095, 0.066, 0.091), (0.0095, 0.075, 0.1005), "iron")                           # rear sight
    for sx in (-1, 1):
        sl.box((sx * 0.0048 - 0.0012, 0.0655, 0.0955), (sx * 0.0048 + 0.0012, 0.0665, 0.0985), "paint_white")
    sl.box((-0.0158, -0.030, 0.074), (-0.0146, 0.004, 0.090), "iron")                          # ejection port (right)
    # magazine (origin = left fist centre under its base plate)
    mg = lp.MeshBuilder()
    t0, t1 = G.PISTOL_MAG_T
    bar_axis(mg, (0, 0, 0), d, t0 + 0.007, t1, X_AX, 0.011, 0.017, "gun_metal", ch=0.003)
    bar_axis(mg, (0, 0, 0), d, t0, t0 + 0.008, X_AX, 0.0172, 0.0295, "plastic_black", ch=0.004)
    top = d * t1 - back * 0.004
    mg.cylinder(top - back * 0.009 + d * 0.0045, top + back * 0.009 + d * 0.0045, 0.0045, 0.0045, 6, "brass")
    return {"Weapon": (fr, (0, 0, 0)), "Slide": (sl, (0.0, 0.0, G.PISTOL_BORE_Z)),
            "Magazine": (mg, G.PISTOL_MAG)}


# ------------------------------------------------------------------------------------------------------------
# revolver (.357, stainless, x1.2 in the numbers)
# ------------------------------------------------------------------------------------------------------------
def build_revolver():
    tilt = 21.0
    d = Vector((0.0, -math.sin(math.radians(tilt)), math.cos(math.radians(tilt))))
    fr = lp.MeshBuilder()
    bz = G.PISTOL_BORE_Z
    cyl_y(fr, -0.252, -0.062, 0.0105, 0.0105, 10, "metal_sheet", z=bz, cap_mats=("iron", None))    # barrel
    fr.box((-0.0085, -0.250, 0.054), (0.0085, -0.068, 0.070), "metal_sheet")                       # underlug
    fr.box((-0.0048, -0.250, 0.0835), (0.0048, -0.066, 0.0885), "metal_sheet")                     # top rib
    fr.box((-0.0025, -0.246, 0.0885), (0.0025, -0.232, 0.1000), "metal_sheet")                     # front ramp
    fr.box((-0.0026, -0.244, 0.0935), (0.0026, -0.238, 0.0985), "paint_red")                       # insert
    fr.box((-0.0115, -0.068, 0.086), (0.0115, 0.006, 0.0985), "metal_sheet")                       # top strap
    fr.box((-0.0120, -0.070, 0.028), (0.0120, -0.060, 0.0985), "metal_sheet")                      # front post
    fr.box((-0.0120, -0.068, 0.024), (0.0120, 0.010, 0.034), "metal_sheet")                        # under cylinder
    fr.box((-0.0140, -0.006, 0.024), (0.0140, 0.016, 0.0985), "metal_sheet")                       # recoil shield
    fr.box((-0.0055, 0.004, 0.0985), (0.0055, 0.012, 0.1035), "iron")                              # rear sight
    fr.box((-0.0038, 0.012, 0.086), (0.0038, 0.034, 0.104), "gun_metal")                           # hammer
    fr.box((-0.005, -0.046, -0.004), (0.005, -0.038, 0.026), "metal_sheet")                        # guard front
    fr.box((-0.005, -0.046, -0.006), (0.005, 0.004, 0.002), "metal_sheet")                         # guard bottom
    fr.box((-0.0028, -0.026, 0.004), (0.0028, -0.019, 0.026), "gun_metal")                         # trigger
    # grip frame strap + wooden grip (rounded, tilted)
    bar_axis(fr, (0.0, 0.012, 0.0), d, -0.020, 0.036, X_AX, 0.0135, 0.020, "metal_sheet", ch=0.005)
    g0 = Vector((0.0, 0.006, 0.0))
    bar_axis(fr, g0, d, -0.100, 0.022, X_AX, 0.0175, 0.0245, "gun_wood", ch=0.009,
             extra=((-0.085, 0.0185, 0.0265), (-0.040, 0.0180, 0.0250)))
    bar_axis(fr, g0, d, -0.106, -0.099, X_AX, 0.0150, 0.0215, "metal_sheet", ch=0.007)          # butt cap
    # cylinder + crane (pivot on the hinge axis, swings to +X)
    cy = lp.MeshBuilder()
    y0, y1 = G.REVOLVER_CYL_Y
    faces = lathe_y(cy, [(y0, 0.0), (y0, G.REVOLVER_CYL_R - 0.004), (y0 + 0.004, G.REVOLVER_CYL_R),
                          (y1 - 0.003, G.REVOLVER_CYL_R), (y1, G.REVOLVER_CYL_R - 0.003), (y1, 0.0)], 12,
                    ["iron", "metal_sheet", "metal_sheet", "metal_sheet", "iron"], z=G.REVOLVER_CYL_Z, phase=15.0)
    recolor_alternate(cy, faces, "gun_metal", (0.0, G.REVOLVER_CYL_Z))
    for k in range(6):
        a = math.radians(90 + 60 * k)
        cx, cz = 0.0155 * math.cos(a), G.REVOLVER_CYL_Z + 0.0155 * math.sin(a)
        cyl_y(cy, y1 - 0.0005, y1 + 0.0015, 0.0058, 0.0058, 6, "brass", x=cx, z=cz)                # case heads
    h = Vector(G.REVOLVER_HINGE)
    cy.box((h.x - 0.004, y0 - 0.006, h.z - 0.004), (h.x + 0.004, y0 + 0.002, G.REVOLVER_CYL_Z - 0.006), "metal_sheet")
    cyl_y(cy, y0 - 0.008, y0 + 0.002, 0.0045, 0.0045, 6, "metal_sheet", x=h.x, z=h.z)              # crane pivot
    # a single .357 round for the left fist (origin = fist centre, pushed toward -Y into a chamber)
    rd = lp.MeshBuilder()
    r0 = Vector(G.REVOLVER_ROUND)
    lathe_y(rd, [(r0.y - 0.004, 0.0), (r0.y - 0.004, 0.0064), (r0.y - 0.0055, 0.0058), (r0.y - 0.040, 0.0058),
                 (r0.y - 0.041, 0.0050), (r0.y - 0.050, 0.0030), (r0.y - 0.053, 0.0)], 8,
            ["brass", "brass", "brass", "stone_dark", "stone_dark", "stone_dark"], x=r0.x, z=r0.z)
    return {"Weapon": (fr, (0, 0, 0)), "Cylinder": (cy, G.REVOLVER_HINGE), "Round": (rd, G.REVOLVER_ROUND)}


# ------------------------------------------------------------------------------------------------------------
# pump shotgun
# ------------------------------------------------------------------------------------------------------------
def stock_sections(mb, secs, mats, ch=0.010):
    """Wooden stock / forend: sections [(y, hx, z0, z1)] lofted along +Y."""
    rings = [rring((0.0, y, (z0 + z1) / 2), X_AX, Z_AX, hx, (z1 - z0) / 2, ch) for y, hx, z0, z1 in secs]
    return mb.loft(rings, mats[0], side_mats=list(mats), cap_mats=(mats[0], mats[-1]))


def build_shotgun():
    w = lp.MeshBuilder()
    bz = G.SHOTGUN_BORE_Z
    bar_y(w, [-0.225, -0.219, -0.046, -0.040], [0.0175, 0.0185, 0.0185, 0.0175],
          [(0.056, 0.114), (0.052, 0.118), (0.052, 0.118), (0.056, 0.114)], "gun_metal", ch=0.007)       # receiver
    w.box((-0.0192, -0.150, 0.090), (-0.0170, -0.092, 0.108), "iron")                               # eject port
    w.box((-0.0118, -0.190, 0.047), (0.0118, -0.108, 0.0525), "iron")                               # loading port
    cyl_y(w, -0.225, -0.701, 0.0125, 0.0122, 12, "gun_metal", z=bz, cap_mats=(None, "iron"))        # barrel
    w.box((-0.0038, -0.690, bz + 0.0115), (0.0038, -0.232, bz + 0.0150), "gun_metal")               # vent rib
    cyl_y(w, -0.690, -0.694, 0.0028, 0.0028, 6, "brass", z=bz + 0.0185, caps=(True, True))          # bead
    w.box((-0.0015, -0.6925, bz + 0.015), (0.0015, -0.6915, bz + 0.0165), "brass")
    cyl_y(w, -0.225, -0.636, 0.0110, 0.0110, 10, "gun_metal", z=0.060)                              # mag tube
    cyl_y(w, -0.636, -0.660, 0.0126, 0.0118, 10, "iron", z=0.060)                                   # tube cap
    w.box((-0.0095, -0.628, 0.062), (0.0095, -0.612, 0.086), "iron")                                # barrel clamp
    w.box((-0.005, -0.078, 0.016), (0.005, -0.070, 0.054), "gun_metal")                             # guard front
    w.box((-0.005, -0.078, 0.012), (0.005, -0.004, 0.020), "gun_metal")                             # guard bottom
    w.box((-0.0026, -0.046, 0.024), (0.0026, -0.039, 0.050), "iron")                                # trigger
    stock_sections(w, [(-0.042, 0.0172, 0.052, 0.116), (-0.012, 0.0165, -0.006, 0.098),
                       (0.020, 0.0162, -0.030, 0.070), (0.070, 0.0172, -0.046, 0.074),
                       (0.160, 0.0190, -0.068, 0.086), (0.279, 0.0212, -0.094, 0.094),
                       (0.300, 0.0212, -0.094, 0.094)],
                   ["gun_wood", "gun_wood", "gun_wood", "gun_wood", "gun_wood", "plastic_black"], ch=0.011)
    # pump (grooved wooden forend around the magazine tube), pivot at its centre
    pm = lp.MeshBuilder()
    py = G.SUPPORT_LONG[1]
    rings, mats = [], []
    ys = [py - 0.090, py - 0.086, py - 0.070, py - 0.066, py - 0.050, py - 0.046, py - 0.030, py - 0.026,
          py - 0.010, py - 0.006, py + 0.010, py + 0.014, py + 0.030, py + 0.034, py + 0.050, py + 0.054,
          py + 0.086, py + 0.090]
    for k, y in enumerate(ys):
        groove = k % 4 in (1, 2) and 2 < k < len(ys) - 3
        r = 0.0215 if k in (0, len(ys) - 1) else (0.0228 if groove else 0.0250)
        rings.append(rring((0.0, y, 0.058), X_AX, Z_AX, r * 0.92, r, 0.008))
    for k in range(len(ys) - 1):
        mats.append("wood_dark" if (k % 4 in (1, 2) and 2 < k < len(ys) - 3) else "gun_wood")
    pm.loft(rings, "gun_wood", side_mats=mats, cap_mats=("gun_wood", "gun_wood"))
    # a 12 gauge shell for the left fist (origin = fist centre, pointing +Z into the loading port)
    sh = lp.MeshBuilder()
    s0 = Vector(G.SHOTGUN_LOAD)
    sh.cylinder(s0 + Vector((0, 0, 0.022)), s0 + Vector((0, 0, 0.034)), 0.0112, 0.0112, 10, "brass")
    sh.cylinder(s0 + Vector((0, 0, 0.034)), s0 + Vector((0, 0, 0.092)), 0.0103, 0.0100, 10, "plastic_red",
                cap_mats=(None, "wood_dark"))
    return {"Weapon": (w, (0, 0, 0)), "Pump": (pm, (0.0, py, 0.060)), "Round": (sh, G.SHOTGUN_LOAD)}


# ------------------------------------------------------------------------------------------------------------
# bolt-action hunting rifle (.308) with a scope
# ------------------------------------------------------------------------------------------------------------
def build_rifle():
    w = lp.MeshBuilder()
    bz = G.RIFLE_BORE_Z
    cyl_y(w, -0.200, -0.040, 0.0175, 0.0175, 10, "gun_metal", z=bz)                                  # receiver
    w.box((-0.0100, -0.190, bz - 0.030), (0.0100, -0.050, bz - 0.010), "gun_metal")                 # action body
    w.box((-0.0182, -0.110, bz + 0.004), (-0.0160, -0.052, bz + 0.016), "iron")                     # eject port
    lathe_y(w, [(-0.200, 0.0118), (-0.260, 0.0108), (-0.700, 0.0088), (-0.780, 0.0084), (-0.789, 0.0092),
                (-0.791, 0.0080), (-0.791, 0.0)], 8,
            ["gun_metal", "gun_metal", "gun_metal", "gun_metal", "iron", "iron"], z=bz)            # barrel
    w.box((-0.0130, -0.100, 0.024), (0.0130, -0.034, 0.030), "gun_metal")                           # floor plate
    w.box((-0.0045, -0.046, 0.004), (0.0045, -0.038, 0.030), "gun_metal")                           # guard front
    w.box((-0.0045, -0.046, 0.000), (0.0045, 0.004, 0.007), "gun_metal")                            # guard bottom
    w.box((-0.0024, -0.026, 0.008), (0.0024, -0.020, 0.030), "iron")                                # trigger
    for yy in (-0.150, -0.020):                                                                     # scope bases
        w.box((-0.0090, yy - 0.010, bz + 0.012), (0.0090, yy + 0.010, bz + 0.0195), "iron")
    stock_sections(w, [(-0.484, 0.0140, 0.052, 0.076), (-0.476, 0.0160, 0.048, 0.080),
                       (-0.300, 0.0190, 0.044, 0.082), (-0.200, 0.0200, 0.038, 0.080),
                       (-0.060, 0.0200, 0.030, 0.082), (-0.028, 0.0185, 0.004, 0.080),
                       (0.004, 0.0160, -0.028, 0.068), (0.060, 0.0170, -0.044, 0.078),
                       (0.160, 0.0190, -0.068, 0.092), (0.289, 0.0212, -0.094, 0.094),
                       (0.310, 0.0212, -0.094, 0.094)],
                   ["wood_dark", "gun_wood", "gun_wood", "gun_wood", "gun_wood", "gun_wood", "gun_wood",
                    "gun_wood", "gun_wood", "plastic_black"], ch=0.011)
    # bolt (pivot on the bore axis at the handle root; lift about +Y then slide back +Y)
    bo = lp.MeshBuilder()
    o = Vector(G.RIFLE_BOLT)
    cyl_y(bo, -0.170, -0.040, 0.0100, 0.0100, 8, "metal_sheet", z=bz)                               # bolt body
    cyl_y(bo, -0.040, -0.008, 0.0122, 0.0110, 8, "gun_metal", z=bz, cap_mats=(None, "iron"))      # shroud
    k = Vector(G.RIFLE_BOLT_KNOB)
    root = o + Vector((-0.008, 0.0, -0.002))
    H.tube(bo, [root, root.lerp(k, 0.55) + Vector((0, 0.004, 0.002)), k], [0.0042, 0.0038, 0.0035], 6,
           "metal_sheet", cap_end=True, cap_start=True)
    lathe_along(bo, k + Vector((0.0, 0.0, -0.008)), (0, 0, 1), [(0.0, 0.0), (0.0, 0.006), (0.004, 0.0088),
                                                              (0.012, 0.0088), (0.016, 0.005), (0.016, 0.0)], 6,
                "gun_metal")                                                                        # knob
    # scope (separate piece at Sight; glass lenses)
    sc = lp.MeshBuilder()
    sz = G.FIREARMS["rifle_hunting"]["anchors"]["Sight"][2]
    lathe_y(sc, [(-0.258, 0.0), (-0.258, 0.0205), (-0.254, 0.0212), (-0.222, 0.0212), (-0.190, 0.0128),
                 (0.022, 0.0128), (0.040, 0.0172), (0.074, 0.0172), (0.078, 0.0160), (0.078, 0.0)], 10,
            ["glass", "plastic_black", "plastic_black", "plastic_black", "gun_metal", "plastic_black",
             "plastic_black", "plastic_black", "glass"], z=sz)
    sc.cylinder((0.0, -0.080, sz + 0.012), (0.0, -0.080, sz + 0.026), 0.0095, 0.0095, 6, "gun_metal")  # elevation
    sc.cylinder((-0.012, -0.080, sz), (-0.026, -0.080, sz), 0.0090, 0.0090, 6, "gun_metal")          # windage
    for yy in (-0.150, -0.020):                                                                     # rings
        sc.box((-0.0080, yy - 0.008, bz + 0.0195), (0.0080, yy + 0.008, sz - 0.011), "plastic_black")
        lathe_y(sc, [(yy - 0.008, 0.0145), (yy + 0.008, 0.0145)], 8, "plastic_black", z=sz)
    # a .308 cartridge for the left fist (origin = fist centre, pushed toward +X into the right-side port)
    rd = lp.MeshBuilder()
    r0 = Vector(G.RIFLE_ROUND)
    lathe_along(rd, r0, (1, 0, 0), [(0.010, 0.0), (0.010, 0.0062), (0.050, 0.0060), (0.056, 0.0040),
                                   (0.062, 0.0038), (0.080, 0.0010), (0.081, 0.0)], 6,
                ["brass", "brass", "brass", "brass", "rust", "rust"])
    return {"Weapon": (w, (0, 0, 0)), "Bolt": (bo, G.RIFLE_BOLT),
            "Scope": (sc, G.FIREARMS["rifle_hunting"]["parts"]["Scope"]), "Round": (rd, G.RIFLE_ROUND)}


# ------------------------------------------------------------------------------------------------------------
# bow + arrows
# ------------------------------------------------------------------------------------------------------------
LIMB = [(0.000, 0.085), (0.012, 0.200), (0.040, 0.330), (0.085, 0.450), (0.135, 0.550), (0.180, 0.625)]
LIMB_W = [0.017, 0.016, 0.0145, 0.012, 0.0095, 0.0075]      # half width (x)
LIMB_T = [0.0110, 0.0100, 0.0088, 0.0075, 0.0062, 0.0055]   # half thickness


def limb(mb, sign):
    rings = []
    pts = [Vector((0.0, y, sign * z)) for y, z in LIMB]
    for i, p in enumerate(pts):
        a = pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]
        a.normalize()
        u = X_AX
        wv = a.cross(u).normalized()
        rings.append(rring(p, u, wv, LIMB_W[i], LIMB_T[i], 0.003))
    faces = mb.loft(rings, "wood", cap_start=False, cap_end=True, cap_mats=(None, "wood_dark"))
    for fi in faces:
        if mb.normal(fi).y > 0.35:
            mb.faces[fi][1] = "wood_light"                      # belly toward the archer
    tip = pts[-1]
    mb.box((-0.009, tip.y - 0.008, tip.z - sign * 0.004 - 0.008), (0.009, tip.y + 0.008, tip.z - sign * 0.004 + 0.008),
           "wood_dark")


def arrow_mesh(mb, nock, length=G.ARROW_LEN):
    """Arrow along -Y from the nock point `nock`: nock, fletching, shaft, iron head."""
    n = Vector(nock)
    tip = n + Vector((0.0, -length, 0.0))
    mb.cylinder(n + Vector((0, -0.012, 0)), tip + Vector((0, 0.034, 0)), 0.0042, 0.0042, 6, "wood_light")
    mb.cylinder(n + Vector((0, 0.002, 0)), n + Vector((0, -0.014, 0)), 0.0050, 0.0050, 6, "plastic_red")
    mb.cylinder(tip + Vector((0, 0.036, 0)), tip, 0.0080, 0.0, 4, "iron", phase=45.0)
    for k in range(3):
        a = math.radians(90 + 120 * k)
        dv = Vector((math.cos(a), 0.0, math.sin(a)))
        side = Vector((-math.sin(a), 0.0, math.cos(a))) * 0.0009
        base0, base1 = n + Vector((0, -0.022, 0)), n + Vector((0, -0.118, 0))
        pts = [base0 + dv * 0.004, base1 + dv * 0.004, base1 + dv * 0.006, base0 + dv * 0.017]
        mat = "hivis_orange" if k == 0 else "paint_white"
        mb.hexa([pts[0] - side, pts[1] - side, pts[3] - side, pts[2] - side,
                 pts[0] + side, pts[1] + side, pts[3] + side, pts[2] + side], mat)


def build_bow():
    w = lp.MeshBuilder()
    # riser / grip (the right fist wraps it at the origin), arrow shelf on the left side (+X)
    bar_axis(w, (0.0, 0.004, 0.0), Z_AX, -0.095, 0.095, X_AX, 0.0150, 0.0200, "wood_dark", ch=0.006,
             extra=((-0.050, 0.0165, 0.0225), (0.050, 0.0165, 0.0225)))
    bar_axis(w, (0.0, 0.004, 0.0), Z_AX, -0.046, 0.044, X_AX, 0.0172, 0.0232, "strap", ch=0.007)     # leather wrap
    w.box((0.006, -0.010, G.BOW_NOCK_Z - 0.010), (0.018, 0.012, G.BOW_NOCK_Z - 0.004), "wood_light")   # shelf
    limb(w, 1)
    limb(w, -1)
    tip_y, tip_z = LIMB[-1]
    s = lp.MeshBuilder()
    top, bot = Vector((0.0, tip_y, tip_z - 0.004)), Vector((0.0, tip_y, -tip_z + 0.004))
    nock = Vector((0.0, G.BOW_BRACE, G.BOW_NOCK_Z))
    H.tube(s, [top, nock + Vector((0, 0, 0.07)), nock + Vector((0, 0, -0.07)), bot],
           [0.0024, 0.0030, 0.0030, 0.0024], 4, "cloth_white", cap_end=True, cap_start=True)
    sd = lp.MeshBuilder()
    drawn = Vector((0.0, G.BOW_DRAW, G.BOW_NOCK_Z))
    for end in (top, bot):
        H.tube(sd, [end, drawn], [0.0024, 0.0026], 4, "cloth_white", cap_end=True, cap_start=True)
    ar = lp.MeshBuilder()
    arrow_mesh(ar, nock)
    return {"Weapon": (w, (0, 0, 0)), "String": (s, (0, 0, 0)), "StringDrawn": (sd, (0, 0, 0)),
            "Arrow": (ar, tuple(nock))}


def build_arrow():
    ar = lp.MeshBuilder()
    arrow_mesh(ar, (0.0, G.ARROW_LEN / 2, 0.0))
    return {"Arrow": (ar, (0, 0, 0))}


def build_flash():
    """Muzzle flash: central cone + 4 closed petals + a thin forward spike, all emissive_lamp, pointing -Y."""
    f = lp.MeshBuilder()
    f.cylinder((0, 0.002, 0), (0, -0.16, 0), 0.016, 0.0, 8, "emissive_lamp")
    for k in range(4):
        a = math.radians(45 + 90 * k)
        dv = Vector((math.cos(a), 0.0, math.sin(a)))
        side = Vector((-math.sin(a), 0.0, math.cos(a)))
        c = Vector((0, -0.035, 0)) + dv * 0.034
        pts = [c - dv * 0.028, c + dv * 0.032, c + Vector((0, -0.030, 0)), c + Vector((0, 0.022, 0)),
               c + side * 0.006, c - side * 0.006]
        f.solid(pts, [(0, 2, 4), (2, 1, 4), (1, 3, 4), (3, 0, 4), (0, 5, 2), (2, 5, 1), (1, 5, 3), (3, 5, 0)],
                "emissive_lamp", inside=c)
    return {"Flash": (f, (0, 0, 0))}


# ------------------------------------------------------------------------------------------------------------
BUILDERS = {"pistol": build_pistol, "revolver": build_revolver, "shotgun": build_shotgun,
            "rifle_hunting": build_rifle, "bow": build_bow, "arrow": build_arrow, "muzzle_flash": build_flash}
LOOSE = {"Magazine", "Round", "Arrow"}            # parts carried by the left hand: AO baked on their own
EXTRA_SPECS = {
    "arrow": dict(cls="Ammo", length=G.ARROW_LEN, caliber="arrow", capacity=1,
                  anchors={"Tip": (0.0, -G.ARROW_LEN / 2, 0.0), "Nock": (0.0, G.ARROW_LEN / 2, 0.0)}),
    "muzzle_flash": dict(cls="Fx", length=0.16, caliber="", capacity=0, anchors={}),
}
# per-part extras (movement hints for the code; Godot axes: Blender +Y = Godot -Z)
PART_EXTRAS = {
    "Slide": {"travel": G.PISTOL_SLIDE_TRAVEL, "move": "translate +Y Blender (Godot -Z) on each shot"},
    "Pump": {"travel": G.PUMP_TRAVEL, "move": "translate +Y Blender (Godot -Z) at pump_back"},
    "Bolt": {"lift_deg": G.RIFLE_BOLT_LIFT_DEG, "travel": G.RIFLE_BOLT_TRAVEL,
             "move": "rotate +lift about +Y Blender (Godot rotation.z = -lift), then translate +Y Blender"},
    "Cylinder": {"swing_deg": G.REVOLVER_SWING_DEG,
                 "move": "rotate +swing about +Y Blender (Godot rotation.z = -swing): swings to +X"},
    "Magazine": {"carry": "LeftHandSocket identity"}, "Round": {"carry": "LeftHandSocket identity"},
    "Arrow": {"carry": "follows the nock: SupportGrip -> DrawPoint"},
}


def spec_of(name):
    return G.FIREARMS.get(name) or EXTRA_SPECS[name]


def build(name):
    spec = spec_of(name)
    lp.new_scene()
    parts = BUILDERS[name]()
    objs = {}
    for pname, (mb, pivot) in parts.items():
        o = mk(mb, pname, pivot, angle=40.0 if name != "bow" else 50.0)
        objs[pname] = o
        if pname in PART_EXTRAS:
            for k, v in PART_EXTRAS[pname].items():
                o[k] = v
    main_name = "Weapon" if "Weapon" in objs else next(iter(objs))
    main = objs[main_name]
    main["weapon_class"] = spec["cls"]
    main["length"] = spec["length"]
    main["caliber"] = spec["caliber"]
    main["capacity"] = spec["capacity"]
    for aname, pos in spec["anchors"].items():
        lp.add_empty(aname, pos, size=0.02)
    tris = sum(H.tris(o) for o in objs.values())
    if tris > BUDGET:
        raise RuntimeError("%s: tris %d > %d" % (name, tris, BUDGET))
    # AO: fixed parts together, each loose part on its own (it is seen alone in the left hand)
    loose = [o for n, o in objs.items() if n in LOOSE and len(objs) > 1]
    fixed = [o for o in objs.values() if o not in loose]
    names = set(objs)
    H.bake_ao(fixed, distance=0.05, samples=48, ground=False, exclude={o.name for o in loose})
    for o in loose:
        H.bake_ao([o], distance=0.05, samples=48, ground=False, exclude=names - {o.name})
    glb = export.save_and_export(name, SUBDIR, ao=False, import_kind="prop")
    return glb


def main(argv=()):
    names = [a for a in argv if not a.startswith("-")] or list(BUILDERS)
    return [build(n) for n in names]


if __name__ == "__main__":
    main(sys.argv[1:])
