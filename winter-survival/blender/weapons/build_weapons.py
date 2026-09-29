"""Melee weapons — ASSET_SPEC_V2 §12 (M4: knife, crowbar, bat, bat_nailed, machete; stone_axe stays in build_tools.py).

    cd winter-survival/blender && python3 weapons/build_weapons.py [knife bat ...]

Exports assets/models/weapons/<weapon>.glb (+ sources/<weapon>.blend + the Godot `.import`, template "prop").
Convention (§12): origin = centre of the main (right-hand) grip; handle along +Z Blender (+Y Godot); business end
(edge, hook, face with the nails) toward -Y Blender (+Z Godot); +X = the weapon's right side. Attach with IDENTITY
to RightHandSocket (socket Y = toward the thumb = the handle axis, Z = along the forearm = the edge). Real scale,
x1.2 for the knife (small weapon). One model for hand and ground. File structure:

    Weapon        mesh, 1 palette_vcol surface (COLOR_0 RGBA, A = AO), smooth handles / chamfered metal
    Grip          empty at the origin (explicit, §12)
    Tip           empty at the business end (top of the blade / hook / barrel): trails, hit probes, blood decals
    SupportGrip   (bat, bat_nailed) left-hand grip 9 cm below the right hand (TwoBoneIK3D target for two-handed use)

Silhouettes and one accent colour per class: knife (brass guard), machete (long pale blade, blood near the tip),
crowbar (paint_red bar, bare steel ends), bat (pale wood, black grip tape), bat_nailed (+ 12 iron nails toward the
hitting side -Y, dried blood).
"""
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

SUBDIR = "weapons"
BUDGET = 900                     # doc 05 §4.5 v2.1: hand-held weapon 100 - 900
KNIFE_SCALE = 1.2                # §12: small weapons x1.2
# name -> (length along Z, lowest z, tip (x, y, z), support grip or None, class)
WEAPONS = {
    "knife": dict(length=0.31, minz=-0.066, tip=(0.0, 0.007, 0.246), support=None, cls="Melee1H"),
    "machete": dict(length=0.55, minz=-0.075, tip=(0.0, -0.026, 0.478), support=None, cls="Melee1H"),
    "crowbar": dict(length=0.60, minz=-0.205, tip=(0.0, -0.096, 0.376), support=None, cls="Melee1H"),
    "bat": dict(length=0.85, minz=-0.165, tip=(0.0, 0.0, 0.689), support=(0.0, 0.0, -0.09), cls="Melee2H"),
    "bat_nailed": dict(length=0.85, minz=-0.165, tip=(0.0, 0.0, 0.689), support=(0.0, 0.0, -0.09), cls="Melee2H"),
}


def lathe(mb, prof, sides, mat_fn, phase=0.0):
    """Surface of revolution about Z: prof = [(z, r)] (r = 0 closes an end), mat_fn(segment index) -> palette name.
    Every face is oriented by the profile's outward normal (dz, -dr), so flat end discs and concave waists are safe."""
    rings = []
    for z, r in prof:
        if r <= 1e-6:
            rings.append([mb._v((0, 0, z))])
        else:
            rings.append([mb._v(p) for p in lp.ring(Vector((0, 0, z)), Vector((0, 0, 1)), r, sides, phase)])
    out = []
    for k in range(len(prof) - 1):
        (z0, r0), (z1, r1) = prof[k], prof[k + 1]
        dz, dr = z1 - z0, r1 - r0
        a, b = rings[k], rings[k + 1]
        mat = mat_fn(k)
        for j in range(sides):
            if len(a) == 1:
                idx = (a[0], b[j], b[(j + 1) % sides])
            elif len(b) == 1:
                idx = (a[j], a[(j + 1) % sides], b[0])
            else:
                idx = (a[j], a[(j + 1) % sides], b[(j + 1) % sides], b[j])
            c = sum((mb.verts[i] for i in idx), Vector()) / len(idx)
            radial = Vector((c.x, c.y, 0.0))
            radial = radial.normalized() if radial.length > 1e-9 else Vector((0, 0, 0))
            out.append(mb.add_face(idx, mat, facing=radial * dz + Vector((0, 0, -dr))))
    return out


def blade(mb, z0, z1, w0, w1, t, mat_flat, mat_edge, tip_len, tip_drop=0.5, spine_y=None, belly=0.0):
    """Flat blade from z0 to z1 in the YZ plane: spine at +Y, edge at -Y (bevelled edge faces `mat_edge`), thickness t
    (X), width w0 -> w1, pointed tip (tip_len) that rises toward the spine by tip_drop."""
    def section(z, w, sp):
        e = sp - w                        # edge y
        m = sp - w * 0.55                  # start of the edge bevel
        hx = t / 2
        return [Vector((0, e, z)), Vector((hx, m, z)), Vector((hx, sp, z)), Vector((-hx, sp, z)), Vector((-hx, m, z))]
    sp0 = spine_y if spine_y is not None else w0 * 0.5
    zs = [z0, z0 + (z1 - z0) * 0.5, z1]
    ws = [w0, (w0 + w1) * 0.5 + belly, w1]
    rings = [section(z, w, sp0) for z, w in zip(zs, ws)]
    tip = Vector((0, sp0 - w1 * (1 - tip_drop), z1 + tip_len))
    rings.append([tip])
    faces = mb.loft(rings, mat_flat, cap_start=True, cap_end=False)
    # the two bevel faces on each side of the edge (between vertex 0 and 1 / 4 and 0) get the edge colour
    for fi in faces:
        c = mb.center(fi)
        n = mb.normal(fi)
        if n.y < -0.3 and abs(n.x) > 0.05 and c.z < z1 + tip_len * 0.9:
            mb.faces[fi][1] = mat_edge
    return faces


def finish(mb, name, smooth_angle=40.0):
    o = H.mk(mb, name)
    H.smooth(o, smooth_angle)
    return o


def anchors(spec):
    lp.add_empty("Grip", (0, 0, 0), size=0.03)
    lp.add_empty("Tip", spec["tip"], size=0.03)
    if spec["support"]:
        lp.add_empty("SupportGrip", spec["support"], size=0.03)


# ------------------------------------------------------------------------------------------------------------
def build_knife():
    k = KNIFE_SCALE
    mb = lp.MeshBuilder()
    # handle (wood_dark, slightly waisted), brass pommel and guard
    lathe(mb, [(-0.055 * k, 0.0), (-0.055 * k, 0.012 * k), (-0.050 * k, 0.014 * k), (-0.030 * k, 0.012 * k),
               (0.010 * k, 0.0115 * k), (0.045 * k, 0.013 * k), (0.052 * k, 0.012 * k), (0.052 * k, 0.0)], 8,
          lambda i: "brass" if i in (0, 1) else "wood_dark")
    mb.box((-0.006 * k, -0.022 * k, 0.052 * k), (0.006 * k, 0.020 * k, 0.060 * k), "brass")     # guard
    blade(mb, 0.058 * k, 0.175 * k, 0.030 * k, 0.026 * k, 0.005 * k, "metal_sheet", "chrome", 0.030 * k, 0.75,
          spine_y=0.012 * k, belly=0.003 * k)
    # the model is authored x1.2; lowest point = pommel bottom
    o = finish(mb, "Weapon")
    return o


def build_machete():
    mb = lp.MeshBuilder()
    lathe(mb, [(-0.075, 0.0), (-0.075, 0.015), (-0.068, 0.017), (-0.03, 0.0145), (0.02, 0.0145), (0.055, 0.017),
               (0.062, 0.016), (0.062, 0.0)], 8, lambda i: "plastic_black")
    mb.box((-0.006, -0.03, 0.060), (0.006, 0.018, 0.068), "iron")                                 # bolster
    blade(mb, 0.066, 0.43, 0.040, 0.058, 0.004, "metal_sheet", "chrome", 0.048, 0.35, spine_y=0.012, belly=0.004)
    o = finish(mb, "Weapon")
    # blood + rust near the tip (gore-lite accent)
    faces_blood = [p.index for p in o.data.polygons if 0.33 < p.center.z < 0.44 and p.center.y < -0.018]
    faces_rust = [p.index for p in o.data.polygons if 0.12 < p.center.z < 0.18 and p.center.y > 0.0]
    from lib import palette
    palette.paint(o, faces_blood, "blood")
    palette.paint(o, faces_rust, "rust")
    return o


def build_crowbar():
    mb = lp.MeshBuilder()
    r = 0.0135
    # straight hex bar: chisel end at the bottom (steel), red paint from -0.15 to the neck, bent hook at the top
    pts = [(0, 0, -0.185), (0, 0, -0.15), (0, 0, 0.0), (0, 0, 0.18), (0, 0, 0.30), (0, -0.004, 0.335),
           (0, -0.02, 0.365), (0, -0.045, 0.385), (0, -0.072, 0.388), (0, -0.092, 0.372)]
    rings = [lp.ring(Vector(pts[0]), Vector((0, 0, 1)), r * 0.9, 6, 30.0)]
    for i in range(1, len(pts)):
        a = Vector(pts[i]) - Vector(pts[i - 1])
        if i < len(pts) - 1:
            a = Vector(pts[i + 1]) - Vector(pts[i - 1])
        rings.append(lp.ring(Vector(pts[i]), a, r * (0.8 if i >= 8 else 1.0), 6, 30.0))
    H.untwist(rings)
    mats = ["chrome", "paint_red", "paint_red", "paint_red", "paint_red", "paint_red", "chrome", "chrome", "chrome"]
    mb.loft(rings, "paint_red", side_mats=mats, cap_start=False, cap_end=True, cap_mats=(None, "chrome"))
    # chisel end: flattened wedge
    mb.hexa([(-r, -r * 0.9, -0.185), (r, -r * 0.9, -0.185), (-r, r * 0.9, -0.185), (r, r * 0.9, -0.185),
             (-r * 1.1, -0.003, -0.205), (r * 1.1, -0.003, -0.205), (-r * 1.1, 0.003, -0.205),
             (r * 1.1, 0.003, -0.205)], "chrome")
    # claw: two prongs at the hook end
    for sx in (-1, 1):
        mb.hexa([(sx * 0.003, -0.084, 0.378), (sx * 0.013, -0.084, 0.378), (sx * 0.003, -0.098, 0.368),
                 (sx * 0.013, -0.098, 0.368), (sx * 0.002, -0.094, 0.352), (sx * 0.010, -0.094, 0.352),
                 (sx * 0.002, -0.104, 0.350), (sx * 0.010, -0.104, 0.350)], "chrome")
    return finish(mb, "Weapon", 50.0)


def bat_profile():
    return [(-0.165, 0.0), (-0.165, 0.022), (-0.158, 0.030), (-0.150, 0.029), (-0.143, 0.016), (-0.10, 0.0135),
            (0.034, 0.0139), (0.035, 0.0172), (0.052, 0.0172), (0.053, 0.0143), (0.18, 0.017), (0.30, 0.024), (0.42, 0.032), (0.55, 0.035), (0.64, 0.035), (0.672, 0.031),
            (0.685, 0.018), (0.689, 0.0)]


def build_bat(nailed=False):
    mb = lp.MeshBuilder()
    prof = bat_profile()

    def mat(i):
        z = (prof[i][0] + prof[i + 1][0]) / 2
        if z < -0.14:
            return "paint_black"
        if z < 0.053:
            return "plastic_black"                          # grip tape (+ its wrapped end band)
        if 0.36 < z < 0.40:
            return "paint_red"                              # painted ring (accent)
        return "wood_light"
    lathe(mb, prof, 10, mat, phase=18.0)
    o = finish(mb, "Weapon", 60.0)
    if nailed:
        nb = lp.MeshBuilder()
        rnd = random.Random(11)
        for k in range(12):
            z = 0.44 + 0.21 * (k % 6) / 5 + rnd.uniform(-0.012, 0.012)
            # mostly around the hitting side (-Y), a few to the sides
            a = math.radians(-90 + (k % 4 - 1.5) * 38 + rnd.uniform(-10, 10))
            d = Vector((math.cos(a), math.sin(a), 0.0))
            bent = Vector((0, 0, rnd.uniform(-0.25, 0.25)))
            base = Vector((0, 0, z)) + d * 0.030
            tip = base + (d + bent).normalized() * 0.065
            H.tube(nb, [base - d * 0.01, tip], [0.0045, 0.0032], 4, "iron", cap_end=True, cap_start=True)
            nb.box(tuple(base - Vector((0.004, 0.004, 0.004)) + d * 0.004), tuple(base + Vector((0.004, 0.004, 0.004)) + d * 0.004),
                   "iron")
        nails = H.mk(nb, "Nails")
        H.flat(nails)
        o = H.join([o, nails], "Weapon")
        from lib import palette
        blood = [p.index for p in o.data.polygons if 0.47 < p.center.z < 0.62 and p.center.y < -0.018
                 and p.material_index == 0 and p.area > 1e-5 and abs(p.center.x) < 0.02]
        palette.paint(o, blood, "blood_dry")
    return o


BUILDERS = {"knife": build_knife, "machete": build_machete, "crowbar": build_crowbar, "bat": lambda: build_bat(False),
            "bat_nailed": lambda: build_bat(True)}


def build(name):
    spec = WEAPONS[name]
    lp.new_scene()
    o = BUILDERS[name]()
    anchors(spec)
    o["weapon_class"] = spec["cls"]
    o["length"] = spec["length"]
    tris = H.tris(o)
    if tris > BUDGET:
        raise RuntimeError("%s: tris %d > %d" % (name, tris, BUDGET))
    glb = export.save_and_export(name, SUBDIR, ao=dict(distance=0.16 if name == "bat" else 0.06, samples=48, ground=False),
                                 import_kind="prop")
    return glb


def main(argv=()):
    names = [a for a in argv if not a.startswith("-")] or list(WEAPONS)
    return [build(n) for n in names]


if __name__ == "__main__":
    main(sys.argv[1:])
