"""Procedural city props (A1) for what no pinned CC0 pack provides in a usable form: bus stop, sandbag wall,
anti-tank hedgehog, military barricade, military tent, W-beam guardrail and blank info / direction signs.

Each builder makes `lib/lowpoly.MeshBuilder` geometry in final coordinates (front = -Y, base at z = 0) and returns
(objects, anchors, info): objects carry palette colours in `Col` and a face class in `cls` like the imported
models, so build_city.py runs the same grade-free weather / snow / AO / export steps on them. Panels meant for
text (signs, bus-stop sign, ad board) are separate objects named `Panel` / `Panel_<n>`.
"""
import math
import random

from mathutils import Matrix, Vector

from lib import lowpoly as lp
from lib import palette

from . import winterize as W

EXC_CLS = {"window": W.CLS["window"], "glass": W.CLS["glass"], "emissive_lamp": W.CLS["lamp"]}


def to_obj(mb, name, cls_override=None, recalc=True):
    o = lp.to_object(mb, name)
    me = o.data
    if recalc:                                   # closed solids: consistent outward normals per part
        import bmesh
        bm = bmesh.new()
        bm.from_mesh(me)
        closed = [f for f in bm.faces if all(len(e.link_faces) == 2 for e in f.edges)]
        if closed:
            bmesh.ops.recalc_face_normals(bm, faces=closed)
        bm.to_mesh(me)
        bm.free()
        me.update()
    names = [m.name for m in me.materials]
    cls = []
    for p in me.polygons:
        mname = names[p.material_index]
        cls.append(EXC_CLS.get(mname, W.CLS["body"]) if cls_override is None else cls_override)
    W.set_cls(me, cls)
    return o


def bag(mb, c, size, yaw, mat, rnd):
    """Sandbag: an 8-sided rounded section lofted along its length with pinched (tied) ends."""
    L, Wd, H = size
    rot = Matrix.Rotation(yaw, 3, "Z")
    rings = []
    for t, k in ((-0.5, 0.55), (-0.38, 0.95), (0.0, 1.0), (0.38, 0.95), (0.5, 0.55)):
        ring = []
        for i in range(8):
            a = 2 * math.pi * i / 8 + math.pi / 8
            y = math.cos(a) * Wd / 2 * k * rnd.uniform(0.95, 1.05)
            z = (math.sin(a) * 0.5 + 0.5) * H * (0.85 + 0.15 * k)
            ring.append(Vector(c) + rot @ Vector((t * L, y, z)))
        rings.append(ring)
    mb.loft(rings, mat)


def sandbag_wall(length=2.4, rows=3, seed=1):
    rnd = random.Random(seed)
    mb = lp.MeshBuilder()
    mats = ["cloth", "wood_light", "deer_belly", "hay"]
    bl, bw, bh = 0.56, 0.34, 0.17
    for r in range(rows):
        n = int(length / bl) + (0 if r % 2 == 0 else -1)
        x0 = -n * bl / 2 + bl / 2
        for i in range(n):
            x = x0 + i * bl + rnd.uniform(-0.03, 0.03)
            c = (x, rnd.uniform(-0.03, 0.03) + 0.02 * r, r * bh * 0.86)
            bag(mb, c, (bl * 0.98, bw * (1 - 0.06 * r), bh), rnd.uniform(-0.06, 0.06), mats[rnd.randrange(4)], rnd)
    o = to_obj(mb, "Prop")
    return [o], {}, {"col": "box", "col_box": ((-length / 2, -0.2, 0), (length / 2, 0.2, rows * bh * 0.86 + 0.02))}


def hedgehog_geom(mb, c, size=1.5, yaw=0.0, mat="rust"):
    """Czech hedgehog: three steel angle beams crossing at the centre, each a thin box."""
    rot = Matrix.Rotation(yaw, 3, "Z")
    dirs = [Vector((1, 0, 0.62)), Vector((-0.5, 0.866, 0.62)), Vector((-0.5, -0.866, 0.62))]
    cz = size * 0.62 * Vector((1, 0, 0.62)).normalized().z + 0.04      # beam ends rest on the ground
    for d in dirs:
        d = (rot @ d).normalized()
        p0 = Vector(c) + Vector((0, 0, cz)) - d * size * 0.62
        p1 = Vector(c) + Vector((0, 0, cz)) + d * size * 0.62
        mb.cylinder(p0, p1, 0.07, 0.07, 4, mat, phase=45.0)


def hedgehog(seed=2):
    mb = lp.MeshBuilder()
    hedgehog_geom(mb, (0, 0, 0), 1.5, 0.3)
    o = to_obj(mb, "Prop")
    return [o], {}, {"col": "box", "col_box": ((-0.8, -0.8, 0), (0.8, 0.8, 1.3))}


def concertina(mb, x0, x1, z, r, loops, mat="iron"):
    """Coiled razor wire along X: a helix of thin 3-sided tube."""
    segs = loops * 10
    pts = []
    for i in range(segs + 1):
        t = i / segs
        a = 2 * math.pi * loops * t
        pts.append(Vector((x0 + (x1 - x0) * t + 0.08 * math.sin(a), r * math.cos(a), z + r * math.sin(a))))
    for i in range(segs):                               # capped 3-sided segments: every piece a closed solid
        mb.cylinder(pts[i], pts[i + 1], 0.014, 0.014, 3, mat)


def mil_barricade(seed=3):
    """Checkpoint barricade section (4 m): two hedgehogs, sandbags between them, razor wire coil on top."""
    rnd = random.Random(seed)
    mb = lp.MeshBuilder()
    hedgehog_geom(mb, (-1.45, 0.1, 0), 1.4, 0.2)
    hedgehog_geom(mb, (1.45, -0.05, 0), 1.4, 0.9)
    bl, bh = 0.56, 0.17
    for r in range(2):
        for i in range(3 - r):
            x = -0.56 + i * bl + r * bl / 2
            bag(mb, (x, 0.0, r * bh * 0.86), (bl * 0.98, 0.34, bh), rnd.uniform(-0.05, 0.05), "cloth", rnd)
    concertina(mb, -1.9, 1.9, 0.72, 0.36, 6)
    o = to_obj(mb, "Prop")
    return [o], {}, {"col": "box", "col_box": ((-2.2, -0.8, 0), (2.2, 0.8, 1.25))}


def mil_tent(seed=4):
    """Military ridge tent 4.2 x 5.2 m, 2.7 m ridge, olive canvas, dark door flap on the front (-Y)."""
    mb = lp.MeshBuilder()
    w, l, wall, ridge = 4.2, 5.2, 1.5, 2.7
    prof = [(-w / 2, -l / 2, 0.0), (w / 2, -l / 2, 0.0), (w / 2, -l / 2, wall), (0.0, -l / 2, ridge),
            (-w / 2, -l / 2, wall)]
    mb.prism(prof, (0, 0, 0), (0, l, 0), "parka_olive", mats_caps=("military_green", "military_green"))
    # door flap (slightly in front of the front gable)
    mb.prism([(-0.55, -l / 2 - 0.005, 0.0), (0.55, -l / 2 - 0.005, 0.0), (0.0, -l / 2 - 0.005, 2.1)],
             (0, 0, 0), (0, -0.03, 0), "cloth_dark")
    # ridge pole ends + ground pegs of the guy lines
    for y in (-l / 2 - 0.05, l / 2 + 0.05):
        mb.cylinder((0, y, ridge - 0.05), (0, y, ridge + 0.18), 0.03, 0.03, 4, "wood_dark")
    o = to_obj(mb, "Prop")
    return [o], {"Entrance": Vector((0.0, -l / 2 - 0.6, 0.0))}, \
        {"col": "box", "col_box": ((-w / 2, -l / 2, 0), (w / 2, l / 2, ridge))}


def guardrail(length=4.0, seed=5):
    """W-beam highway guardrail section along X: 3 posts + a W profile beam at 0.55 m."""
    mb = lp.MeshBuilder()
    for x in (-length / 2 + 0.25, 0.0, length / 2 - 0.25):
        mb.box((x - 0.06, 0.02, 0.0), (x + 0.06, 0.14, 0.78), "metal_sheet")
    prof = [(0.0, -0.02, 0.40), (0.0, -0.10, 0.46), (0.0, -0.06, 0.55), (0.0, -0.10, 0.64), (0.0, -0.02, 0.70),
            (0.0, 0.02, 0.70), (0.0, 0.02, 0.40)]
    prof = [(x - length / 2, y, z) for x, y, z in prof]
    mb.prism(prof, (0, 0, 0), (length, 0, 0), "chrome", concave=True)
    o = to_obj(mb, "Prop")
    return [o], {}, {"col": "box", "col_box": ((-length / 2, -0.12, 0), (length / 2, 0.16, 0.78))}


def info_sign(kind="street", seed=6):
    """Blank signs whose face is a separate `Panel` mesh for text (Label3D / decal by the code).
    street: 1.1 x 0.3 m street-name blade at 2.6 m on a pole; info: 1.2 x 0.9 m panel; direction: 2.6 x 1.3 m on
    two posts (road direction sign)."""
    mb = lp.MeshBuilder()
    pan = lp.MeshBuilder()
    if kind == "street":
        mb.cylinder((0, 0, 0), (0, 0, 2.95), 0.04, 0.035, 8, "metal_sheet")
        w, h, zc, colr = 1.1, 0.3, 2.62, "hospital_green"
        posts = [0.0]
    elif kind == "info":
        mb.cylinder((0, 0, 0), (0, 0, 2.7), 0.045, 0.04, 8, "metal_sheet")
        w, h, zc, colr = 1.2, 0.9, 2.1, "metal_blue"
        posts = [0.0]
    else:
        for x in (-0.9, 0.9):
            mb.cylinder((x, 0, 0), (x, 0, 2.9), 0.05, 0.045, 8, "metal_sheet")
        w, h, zc, colr = 2.6, 1.3, 2.3, "metal_blue"
        posts = [-0.9, 0.9]
    # frame (white border) behind the panel face
    mb.box((-w / 2 - 0.03, -0.06, zc - h / 2 - 0.03), (w / 2 + 0.03, -0.03, zc + h / 2 + 0.03), "paint_white")
    pan.box((-w / 2, -0.075, zc - h / 2), (w / 2, -0.06, zc + h / 2), colr)
    prop = to_obj(mb, "Prop")
    panel = to_obj(pan, "Panel", cls_override=W.CLS["panel"])
    info = {"col": "cylinder" if len(posts) == 1 else "box",
            "col_box": ((-w / 2, -0.1, 0), (w / 2, 0.1, zc + h / 2)), "pole_r": 0.05,
            "panels": {"Panel": [round(w, 3), round(h, 3)]}}
    return [prop, panel], {"TextPanel": Vector((0.0, -0.09, zc))}, info


def bus_stop(seed=7):
    """Bus shelter 3.6 x 1.5 x 2.6 m, open to -Y (the kerb): posts, roof, tinted back / side panes, a lit
    advertising board at the +X end (emissive_lamp faces), a bench and the bus-stop sign pole with its Panel."""
    mb = lp.MeshBuilder()
    pan = lp.MeshBuilder()
    L, D, H = 3.6, 1.5, 2.45
    for x in (-L / 2 + 0.05, L / 2 - 0.05):
        for y in (-D / 2 + 0.05, D / 2 - 0.05):
            mb.box((x - 0.05, y - 0.05, 0.0), (x + 0.05, y + 0.05, H), "metal_blue")
    mb.box((-L / 2 - 0.1, -D / 2 - 0.2, H), (L / 2 + 0.1, D / 2 + 0.08, H + 0.12), "metal_sheet")
    mb.box((-L / 2 - 0.1, -D / 2 - 0.22, H - 0.12), (L / 2 + 0.1, -D / 2 - 0.18, H + 0.12), "metal_blue")
    # tinted back pane and side pane (palette ice_thin), framed at the bottom
    mb.box((-L / 2 + 0.1, D / 2 - 0.04, 0.25), (L / 2 - 0.1, D / 2 - 0.01, H - 0.1), "ice_thin")
    mb.box((-L / 2 + 0.01, -D / 2 + 0.2, 0.25), (-L / 2 + 0.04, D / 2 - 0.1, H - 0.1), "ice_thin")
    # advertising board at +X: frame + two lit faces
    x = L / 2 - 0.08
    mb.box((x - 0.07, -D / 2 + 0.15, 0.2), (x + 0.07, D / 2 - 0.1, H - 0.15), "iron")
    for side in (-1, 1):
        xx = x + side * 0.075
        mb.poly([(xx, -D / 2 + 0.25, 0.35), (xx, D / 2 - 0.2, 0.35), (xx, D / 2 - 0.2, H - 0.3),
                 (xx, -D / 2 + 0.25, H - 0.3)], "emissive_lamp", facing=(side, 0, 0))
    # bench
    mb.box((-1.2, 0.15, 0.42), (1.0, 0.55, 0.47), "wood")
    for bx in (-1.1, 0.9):
        mb.box((bx - 0.03, 0.3, 0.0), (bx + 0.03, 0.4, 0.42), "iron")
    # stop sign pole in front of the shelter + panel for the line numbers
    mb.cylinder((-L / 2 - 0.5, -D / 2 - 0.3, 0.0), (-L / 2 - 0.5, -D / 2 - 0.3, 2.9), 0.04, 0.035, 8, "metal_sheet")
    pan.box((-L / 2 - 0.8, -D / 2 - 0.36, 2.2), (-L / 2 - 0.2, -D / 2 - 0.33, 2.8), "paint_red")
    prop = to_obj(mb, "Prop")
    panel = to_obj(pan, "Panel", cls_override=W.CLS["panel"])
    anchors = {"LightAnchor": Vector((x, 0.1, 1.3)), "LightPool": Vector((x - 0.6, -0.3, 0.02)),
               "Seat": Vector((-0.1, 0.35, 0.47)), "TextPanel": Vector((-L / 2 - 0.5, -D / 2 - 0.38, 2.5))}
    return [prop, panel], anchors, {"col": "box", "col_box": ((-L / 2 - 0.1, -D / 2 - 0.2, 0), (L / 2 + 0.1, D / 2, H + 0.12)),
                                    "panels": {"Panel": [0.6, 0.6]}}


PROCEDURAL = {
    "bus_stop": bus_stop, "sandbag_wall": sandbag_wall, "hedgehog": hedgehog, "mil_barricade": mil_barricade,
    "mil_tent": mil_tent, "guardrail": guardrail,
    "sign_street": lambda: info_sign("street"), "sign_info": lambda: info_sign("info"),
    "sign_direction": lambda: info_sign("direction"),
}
