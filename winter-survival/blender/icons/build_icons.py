"""Rendered item icons (hotbar, container panels, craft panel): 256 x 256 RGBA PNG, transparent background.

    cd winter-survival/blender && python3 icons/build_icons.py                 # every icon (skips unchanged ones)
    python3 icons/build_icons.py wood torch --force                            # re-render some icons
    python3 icons/build_icons.py --sheet /tmp/sheet.png                        # + contact sheet (needs Pillow)

Output: ../assets/icons/items/<icon>.png (names = the `icon` fields of scripts/data/items.gd and recipes.gd; the
UI loads them before the flat SVG pictograms, scripts/ui/ui_icons.gd).

Models: small HD v2.1 props built here (palette colours in `Col`, smooth where soft, chamfered where hard, doc 05
§4.2), or the game models reused from ../blender/sources/<asset>.blend (axe, torch, campfire, tent, box) with an
emissive flame. Every icon uses ONE identical setup (camera, lights, colour management, samples):

  * orthographic camera 38 deg down, yaw 30 deg (3/4 top view), the model framed to FILL of the square;
  * soft warm key (sun, upper left), cool fill (right), cool rim (behind) + a dim cool world, so the models read
    on the dark navy UI panels (#1E2A3A); a shadow-catcher ground gives a soft contact shadow in the alpha;
  * Cycles, SAMPLES + OpenImageDenoise, fixed seed, view transform VIEW / LOOK.

Determinism: every icon's PNG carries a tEXt chunk `ventisca_icon` = hash of (this script + the scene geometry,
colours and materials). An icon whose hash is unchanged is not rendered again (build_all stays fast and the
repository has no churn); --force re-renders.
"""
import hashlib
import math
import os
import random
import struct
import sys
import tempfile
import warnings
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
BLENDER_DIR = os.path.dirname(HERE)
sys.path.insert(0, BLENDER_DIR)

import bpy  # noqa: E402
from mathutils import Matrix, Vector, noise  # noqa: E402

from lib import hd  # noqa: E402
from lib import lowpoly as lp  # noqa: E402
from lib import palette  # noqa: E402

ROOT = os.path.dirname(BLENDER_DIR)
OUT_DIR = os.path.join(ROOT, "assets", "icons", "items")
SOURCES = os.path.join(BLENDER_DIR, "sources")

# ---- the one render setup shared by every icon ---------------------------------------------------------------
RES = 256
FILL = 0.84                 # model extent / frame (square)
CAM_PITCH = 38.0            # degrees below the horizon
CAM_YAW = 30.0              # degrees, from the model front (-Y) toward +X
SAMPLES = 192
VIEW = "AgX"
LOOK = "AgX - Medium High Contrast"
EXPOSURE = 0.35
# (azimuth relative to the camera, elevation, strength, angle, colour)
LIGHTS = {
    "Key": (-50.0, 52.0, 3.6, 18.0, (1.0, 0.94, 0.86)),
    "Fill": (80.0, 18.0, 1.1, 50.0, (0.70, 0.80, 1.0)),
    "Rim": (165.0, 30.0, 3.0, 8.0, (0.78, 0.88, 1.0)),
}
WORLD = ((0.42, 0.50, 0.66), 0.55)
SHADOW = True
HASH_KEY = "ventisca_icon"


# ================================================================================================================
# helpers: objects, shading, materials
# ================================================================================================================
def finish(mb, name, mode="flat", width=0.01, segments=2, sharp=50.0, levels=1):
    """MeshBuilder -> object with the HD shading of its part (doc 05 §4.2):
    flat | smooth (<sharp deg creases smooth) | soft (rounded chamfer + smooth by angle) | sub (Catmull-Clark)."""
    o = hd.mk(mb, name)
    if mode == "smooth":
        hd.smooth(o, sharp)
    elif mode == "soft":
        o.data.shade_smooth()
        m = o.modifiers.new("bevel", 'BEVEL')
        m.width = width
        m.segments = segments
        m.limit_method = 'ANGLE'
        m.angle_limit = math.radians(30.0)
        m.use_clamp_overlap = True
        hd._swap_evaluated(o)
        hd.smooth(o, sharp)
        hd.snap_colors(o)
    elif mode == "chamfer":
        hd.bevel(o, width=width)
        hd.snap_colors(o)
    elif mode == "sub":
        hd.subsurf(o, levels)
        hd.smooth(o)
        hd.snap_colors(o)
    return o


def variant(obj, tag, rough=None, metal=None, alpha=None, coat=None):
    """Swap the palette_vcol slot(s) of `obj` for a copy with another roughness / metallic (icon-only look)."""
    base = palette.get_vcol_material()
    name = "icon_%s" % tag
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = base.copy()
        mat.name = name
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        if rough is not None:
            bsdf.inputs["Roughness"].default_value = rough
        if metal is not None:
            bsdf.inputs["Metallic"].default_value = metal
        if coat is not None and "Coat Weight" in bsdf.inputs:
            bsdf.inputs["Coat Weight"].default_value = coat
        if alpha is not None:
            bsdf.inputs["Alpha"].default_value = alpha
    for i, m in enumerate(obj.data.materials):
        if m == base:
            obj.data.materials[i] = mat
    return obj


def flame_material():
    """Emission gradient along the object's generated Z: pale yellow core at the base -> orange -> ember red tip."""
    mat = bpy.data.materials.get("icon_flame")
    if mat is not None:
        return mat
    mat = bpy.data.materials.new("icon_flame")
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    cr = ramp.color_ramp
    cr.elements[0].position = 0.0
    cr.elements[0].color = palette.linear_rgba("emissive_lamp")
    cr.elements[1].position = 1.0
    cr.elements[1].color = palette.linear_rgba("ember")
    e = cr.elements.new(0.45)
    e.color = palette.linear_rgba("scarf")
    nt.links.new(tc.outputs["Generated"], sep.inputs["Vector"])
    nt.links.new(sep.outputs["Z"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], em.inputs["Color"])
    em.inputs["Strength"].default_value = 4.0
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    return mat


def flame(name, base, height, radius, lean=(0.0, 0.0), seed=0, sides=8):
    """Stylised flame tongue: rounded base, pointed curling tip, Catmull-Clark smooth, emissive gradient."""
    rnd = random.Random(seed)
    base = Vector(base)
    mb = lp.MeshBuilder()
    rows = []
    prof = [(0.0, 0.35), (0.10, 0.85), (0.28, 1.0), (0.50, 0.78), (0.72, 0.45), (0.88, 0.2)]
    for t, k in prof:
        c = base + Vector((lean[0] * t * t * height, lean[1] * t * t * height, t * height))
        radii = [1.0 + rnd.uniform(-0.12, 0.12) for _ in range(sides)]
        rows.append(lp.ring(c, (0, 0, 1), radius * k, sides, 0.0, radii))
    tip = base + Vector((lean[0] * height, lean[1] * height, height))
    rows.append([tip])
    mb.loft(rows, "ember", cap_start=True, cap_end=False)
    o = hd.mk(mb, name)
    hd.subsurf(o, 2)
    hd.smooth(o)
    o.data.materials.clear()
    o.data.materials.append(flame_material())
    return o


def glow(loc, energy, radius=0.05, color=(1.0, 0.55, 0.22)):
    li = bpy.data.lights.new("IconGlow", 'POINT')
    li.energy = energy
    li.shadow_soft_size = radius
    li.color = color
    ob = bpy.data.objects.new("IconGlow", li)
    ob.location = Vector(loc)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def load_model(asset):
    """Append every visual object of sources/<asset>.blend (the game model) into the current scene."""
    path = os.path.join(SOURCES, asset + ".blend")
    if not os.path.exists(path):
        raise FileNotFoundError("%s (run the build script of %s first)" % (path, asset))
    with bpy.data.libraries.load(path, link=False) as (src, dst):
        dst.objects = list(src.objects)
    objs = {}
    for o in dst.objects:
        if o is None:
            continue
        if o.type == 'MESH' and o.name.startswith("Col"):
            bpy.data.objects.remove(o, do_unlink=True)
            continue
        bpy.context.scene.collection.objects.link(o)
        objs[o.name] = o
    bpy.context.view_layer.update()
    return objs


def anchor(objs, name):
    return objs[name].matrix_world.translation.copy()


# ================================================================================================================
# icon models (authored with the front at -Y; `rot` in the returned dict poses the model for the camera)
# ================================================================================================================
def log_piece(mb, p0, p1, r, rnd, sides=9, split=False):
    """Log with bark sides and pale end grain (+ a darker heart ring); split=True = half log, split face up."""
    p0, p1 = Vector(p0), Vector(p1)
    axis = (p1 - p0).normalized()
    u, w = lp.perp_basis(axis)
    jit = [1.0 + rnd.uniform(-0.07, 0.07) for _ in range(sides)]
    if split:
        n = sides - 1
        prof = [math.pi + math.pi * i / n for i in range(n + 1)]   # lower half: u cos + w sin, angle pi..2pi
        pts = [(u * math.cos(a) + w * math.sin(a)) * r * jit[i % sides] for i, a in enumerate(prof)]
        # rotate so the flat split face looks up
        rings = [[p0 + q for q in pts], [p1 + q for q in pts]]
    else:
        rings = [lp.ring(p0, axis, r, sides, rnd.uniform(0, 40), jit), lp.ring(p1, axis, r, sides, 0, jit)]
        rings[1] = [q + (p1 - p0) for q in rings[0]]
    faces = mb.loft(rings, "bark", cap_mats=("wood_light", "wood_light"))
    if split:
        for fi in faces:
            nrm = mb.normal(fi)
            if abs(nrm.dot(axis)) < 0.5 and nrm.dot(u) > 0.9:
                mb.faces[fi][1] = "wood_light"
    # heart ring on both ends (slightly proud)
    if not split:
        for p, s in ((p0, -1), (p1, 1)):
            mb.poly(lp.ring(p + axis * s * 0.002, axis, r * 0.42, 8, 11), "wood", facing=axis * s)
    return faces


def icon_wood():
    rnd = random.Random(4)
    mb = lp.MeshBuilder()
    L, r = 0.46, 0.065
    logs = [((-0.070, 0.0, r), 0.0), ((0.070, 0.02, r), 0.0), ((0.0, 0.01, r * 2.62), 0.0)]
    for i, ((x, y, z), _a) in enumerate(logs):
        off = (i - 1) * 0.03
        log_piece(mb, (x, -L / 2 + y + off, z), (x, L / 2 + y + off, z), r * (0.95 + 0.1 * rnd.random()), rnd)
    finish(mb, "Wood", "soft", width=0.008, segments=2, sharp=48.0)
    return dict(rot=(0, 0, -62))


def icon_stone():
    rnd = random.Random(11)
    objs = []
    spec = [((-0.07, 0.02, 0.045), (0.080, 0.065, 0.050), "stone"),
            ((0.075, -0.015, 0.042), (0.072, 0.062, 0.046), "stone_dark"),
            ((0.005, 0.005, 0.105), (0.066, 0.056, 0.046), "stone")]
    for i, (c, radii, col) in enumerate(spec):
        mb = lp.MeshBuilder()
        mb.blob(c, radii, col, subdiv=1, jitter=0.16, rnd=rnd)
        o = finish(mb, "Stone%d" % i, "sub", levels=1)
        hd.smooth(o, 38.0)
        objs.append(o)
    return dict(rot=(0, 0, 10))


def leaf(mb, base, direction, length, width, up=(0, 0, 1), mat="bush", mat2="moss", fold=0.3):
    """Pointed leaf (two halves folded along the midrib)."""
    b = Vector(base)
    d = Vector(direction).normalized()
    s = d.cross(Vector(up)).normalized()
    n = s.cross(d).normalized()
    ts = [0.0, 0.22, 0.5, 0.78, 1.0]
    ws = [0.0, 0.8, 1.0, 0.7, 0.0]
    mid = [b + d * length * t + n * 0.25 * width * math.sin(math.pi * t) for t in ts]
    for side, m in ((1, mat), (-1, mat2)):
        edge = [mid[i] + s * side * width * 0.5 * ws[i] - n * fold * width * 0.5 * ws[i] for i in range(len(ts))]
        for i in range(len(ts) - 1):
            quad = [mid[i], mid[i + 1], edge[i + 1], edge[i]]
            if i == 0:
                quad = [mid[0], mid[1], edge[1]]
            elif i == len(ts) - 2:
                quad = [mid[i], mid[i + 1], edge[i]]
            idx = [mb._v(p) for p in quad]
            mb.add_face(idx, m, facing=n)
            idx = [mb._v(p - n * 0.002) for p in quad]
            mb.add_face(idx, m, facing=-n)


def berry_cluster(rnd, center, count, r, spread, name_prefix, mat="berry"):
    objs = []
    c = Vector(center)
    placed = []
    tries = 0
    while len(placed) < count and tries < 500:
        tries += 1
        a = rnd.uniform(0, 2 * math.pi)
        d = rnd.uniform(0, spread)
        p = c + Vector((math.cos(a) * d, math.sin(a) * d, rnd.uniform(-0.3, 0.3) * r))
        if all((p - q).length > r * 1.75 for q in placed):
            placed.append(p)
    for i, p in enumerate(placed):
        mb = lp.MeshBuilder()
        rr = r * rnd.uniform(0.88, 1.08)
        mb.blob(p, (rr, rr, rr * 0.95), mat, subdiv=1, jitter=0.03, rnd=rnd)
        # tiny dark calyx on top
        mb.poly(lp.ring(p + Vector((0, 0, rr * 0.97)), (0, 0, 1), rr * 0.22, 5, rnd.uniform(0, 70)), "wood_dark",
                facing=(0, 0, 1))
        o = finish(mb, "%s%d" % (name_prefix, i), "sub", levels=1)
        variant(o, "gloss", rough=0.28, coat=0.3)
        objs.append(o)
    return objs


def icon_berry():
    rnd = random.Random(21)
    twig = lp.MeshBuilder()
    hd.tube(twig, [(-0.20, 0.08, 0.02), (-0.08, 0.03, 0.035), (0.03, 0.0, 0.04), (0.12, -0.02, 0.05)],
            [0.012, 0.010, 0.009, 0.006], 6, "bark")
    finish(twig, "Twig", "smooth", sharp=70)
    lv = lp.MeshBuilder()
    leaf(lv, (-0.12, 0.05, 0.03), (-0.6, 1.0, 0.25), 0.19, 0.10)
    leaf(lv, (-0.10, 0.04, 0.03), (-0.3, -1.0, 0.35), 0.17, 0.09)
    leaf(lv, (-0.16, 0.07, 0.03), (-1.0, 0.2, 0.3), 0.15, 0.085)
    finish(lv, "Leaves", "smooth", sharp=80)
    berry_cluster(rnd, (0.03, -0.01, 0.07), 7, 0.042, 0.075, "Berry")
    return dict(rot=(0, 0, 8))


def cup_shell(mb, r_out, h, t, sides, mat):
    """Open cup: outer wall + rolled rim + inner wall + inner floor, normals outward of the material."""
    rows_out = [lp.ring((0, 0, z), (0, 0, 1), r, sides) for r, z in
                ((r_out * 0.86, 0.0), (r_out * 0.97, 0.01), (r_out, 0.03), (r_out * 1.02, h * 0.55),
                 (r_out * 1.05, h))]
    rim = lp.ring((0, 0, h + t * 0.6), (0, 0, 1), r_out * 1.05 - t * 0.5, sides)
    rows_in = [lp.ring((0, 0, z), (0, 0, 1), r, sides) for r, z in
               ((r_out * 1.05 - t, h), (r_out * 1.02 - t, h * 0.55), (r_out * 0.97 - t, t + 0.01))]
    for s in range(len(rows_out) - 1):
        mb.loft([rows_out[s], rows_out[s + 1]], mat, cap_start=False, cap_end=False, inside=Vector((0, 0, h / 2)))
    # bottom
    mb.poly(rows_out[0], mat, facing=(0, 0, -1))
    # rim roll
    mb.loft([rows_out[-1], rim], mat, cap_start=False, cap_end=False, seg_facing=None,
            inside=Vector((0, 0, h * 0.2)))
    mb.loft([rim, rows_in[0]], mat, cap_start=False, cap_end=False, inside=Vector((0, 0, h * 0.2)))
    for s in range(len(rows_in) - 1):
        a, b = rows_in[s], rows_in[s + 1]
        n = len(a)
        for j in range(n):
            ctr = (a[j] + b[(j + 1) % n]) / 2
            inward = Vector((-ctr.x, -ctr.y, 0))
            mb.add_face((mb._v(a[j]), mb._v(a[(j + 1) % n]), mb._v(b[(j + 1) % n]), mb._v(b[j])), mat,
                        facing=inward)
    mb.poly(rows_in[-1], mat, facing=(0, 0, 1))


def icon_berries_hot():
    rnd = random.Random(33)
    R, H, T = 0.075, 0.085, 0.006
    mb = lp.MeshBuilder()
    cup_shell(mb, R, H, T, 24, "metal_sheet")
    cup = finish(mb, "Cup", "smooth", sharp=60)
    variant(cup, "metal", rough=0.32, metal=0.75)
    # handle: loop on the +X side
    hb = lp.MeshBuilder()
    pts = []
    for i in range(9):
        a = -math.pi / 2 + math.pi * i / 8
        pts.append(Vector((R * 1.02 + 0.035 * math.cos(a) + 0.004, 0, H * 0.52 + 0.03 * math.sin(a))))
    hd.tube(hb, pts, [0.0065] * len(pts), 8, "metal_sheet", cap_end=True, cap_start=True)
    h = finish(hb, "Handle", "smooth", sharp=70)
    variant(h, "metal", rough=0.32, metal=0.75)
    # hot berry compote + berries on top
    lq = lp.MeshBuilder()
    lq.poly(lp.ring((0, 0, H * 0.80), (0, 0, 1), R * 1.04 - T - 0.001, 24), "blood_dry", facing=(0, 0, 1))
    liq = finish(lq, "Compote", "smooth")
    variant(liq, "wet", rough=0.18, coat=0.5)
    berry_cluster(rnd, (0.0, 0.0, H * 0.82), 6, 0.024, 0.042, "Berry")
    # steam wisps
    for k, (x, y, ph) in enumerate(((-0.02, 0.01, 0.0), (0.025, -0.012, 1.7))):
        sb = lp.MeshBuilder()
        pts = [Vector((x + 0.018 * math.sin(ph + t * 5.0), y, H + 0.03 + t * 0.12)) for t in
               [i / 7 for i in range(8)]]
        hd.tube(sb, pts, [0.009 * (1 - 0.6 * i / 7) for i in range(8)], 6, "cloth_white", cap_end=True,
                cap_start=True)
        s = finish(sb, "Steam%d" % k, "smooth", sharp=80)
        variant(s, "steam", rough=1.0, alpha=0.55)
    return dict(rot=(0, 0, 0))


def icon_meat_raw():
    rnd = random.Random(44)
    n = 20
    # kidney-shaped steak outline, fat along the +Y / -X side
    rad = []
    for i in range(n):
        a = 2 * math.pi * i / n
        r = 1.0 + 0.16 * math.cos(2 * a) - 0.10 * math.cos(3 * a + 0.6) + rnd.uniform(-0.03, 0.03)
        rad.append(r)
    def ring_at(z, k):
        return [Vector((math.cos(2 * math.pi * i / n) * 0.16 * rad[i] * k,
                        math.sin(2 * math.pi * i / n) * 0.11 * rad[i] * k, z)) for i in range(n)]
    rows = [ring_at(0.0, 0.90), ring_at(0.018, 1.0), ring_at(0.045, 0.99), ring_at(0.058, 0.90),
            ring_at(0.062, 0.62)]
    mb = lp.MeshBuilder()
    faces = mb.loft(rows, "gore", cap_start=True, cap_end=True, inside=Vector((0, 0, 0.03)))

    def fat(i):
        a = math.degrees(2 * math.pi * i / n) % 360
        return 55 <= a <= 170
    for fi in faces:
        c = mb.center(fi)
        a = math.degrees(math.atan2(c.y / 0.11, c.x / 0.16)) % 360
        if 60 <= a <= 165 and c.z > 0.004 and (c.x / 0.16) ** 2 + (c.y / 0.11) ** 2 > 0.62:
            mb.faces[fi][1] = "paper"
    # marbling streaks: two thin pale bands on the top face
    for (x0, y0, x1, y1) in ((-0.07, -0.02, 0.02, 0.02), (0.01, -0.05, 0.08, -0.01)):
        p0, p1 = Vector((x0, y0, 0.0625)), Vector((x1, y1, 0.0625))
        d = (p1 - p0).normalized()
        s = Vector((-d.y, d.x, 0)) * 0.006
        mb.poly([p0 - s, p1 - s, p1 + s, p0 + s], "skin", facing=(0, 0, 1))
    o = finish(mb, "Steak", "soft", width=0.012, segments=2, sharp=60)
    variant(o, "meat", rough=0.38, coat=0.25)
    return dict(rot=(0, 0, 20))


def icon_meat_cooked():
    rnd = random.Random(55)
    axis = Vector((1.0, 0.0, 0.0))
    prof = [(-0.11, 0.035), (-0.10, 0.075), (-0.075, 0.098), (-0.03, 0.104), (0.02, 0.092), (0.06, 0.066),
            (0.095, 0.038), (0.12, 0.024)]
    mb = lp.MeshBuilder()
    rows = []
    for x, r in prof:
        radii = [1.0 + rnd.uniform(-0.06, 0.06) for _ in range(10)]
        rows.append(lp.ring((x, 0, 0), axis, (r, r * 0.9), 10, 0.0, radii))
    faces = mb.loft(rows, "rust", cap_start=True, cap_end=True)
    for fi in faces:
        c = mb.center(fi)
        if noise.noise(c * 28.0 + Vector((3.1, 0.7, 1.9))) > 0.28:
            mb.faces[fi][1] = "gun_wood"
    meat = finish(mb, "Drumstick", "sub", levels=2)
    variant(meat, "roast", rough=0.42, coat=0.35)
    bone = lp.MeshBuilder()
    bone.cylinder((0.10, 0, 0), (0.175, 0, 0), 0.018, 0.016, 8, "paper")
    for dy in (-0.017, 0.017):
        bone.blob((0.185, dy, 0.0), 0.022, "paper", subdiv=1, jitter=0.02, rnd=rnd)
    finish(bone, "Bone", "sub", levels=1)
    stick = lp.MeshBuilder()
    stick.cylinder((-0.34, 0, 0), (0.03, 0, 0), 0.011, 0.010, 7, "wood", cap_mats=("wood_light", "wood_light"))
    finish(stick, "Stick", "soft", width=0.003, sharp=60)
    return dict(rot=(0, -18, -38))


def can(label, spot):
    R, H = 0.05, 0.12
    sides = 32
    mb = lp.MeshBuilder()
    metal = "chrome"
    rows = [(R * 0.93, 0.0, metal), (R * 1.01, 0.004, metal), (R * 1.01, 0.010, metal), (R * 0.985, 0.014, metal),
            (R * 1.0, 0.018, label), (R * 1.0, 0.030, label), (R * 1.0, 0.050, label), (R * 1.0, 0.072, label),
            (R * 1.0, 0.092, label), (R * 1.0, 0.104, label), (R * 0.985, 0.108, metal), (R * 1.01, 0.112, metal),
            (R * 1.01, 0.118, metal), (R * 0.97, 0.121, metal), (R * 0.93, 0.117, metal)]
    rings = [lp.ring((0, 0, z), (0, 0, 1), r, sides, 90.0 + 180.0 / sides) for r, z, _m in rows]
    for s in range(len(rows) - 1):
        m = rows[s][2] if rows[s][2] == rows[s + 1][2] else metal
        if rows[s][2] == label and rows[s + 1][2] == label:
            m = label
        fs = mb.loft([rings[s], rings[s + 1]], m, cap_start=False, cap_end=False,
                     inside=Vector((0, 0, (rows[s][1] + rows[s + 1][1]) / 2)))
        if m == label:
            for fi in fs:
                c = mb.center(fi)
                az = math.degrees(math.atan2(c.x, -c.y))
                if s in (4, 5, 6, 7) and abs(az) < 42:
                    mb.faces[fi][1] = "paper"
                if s in (4, 5, 6, 7) and abs(az) < 16 and s in (5, 6):
                    mb.faces[fi][1] = spot
                if s in (3, 8):
                    mb.faces[fi][1] = "brass"
    # lid: concentric rings stepping down to a recessed centre
    lid = [(R * 0.80, 0.114), (R * 0.72, 0.1165), (R * 0.55, 0.114)]
    lrings = [lp.ring((0, 0, z), (0, 0, 1), r, sides, 90.0 + 180.0 / sides) for r, z in lid]
    mb.loft([rings[-1]] + lrings, metal, cap_start=False, cap_end=True, seg_facing=[(0, 0, 1)] * len(lrings))
    mb.poly(rings[0], metal, facing=(0, 0, -1))
    o = finish(mb, "Can", "smooth", sharp=35)
    variant(o, "tin", rough=0.30, metal=0.55)
    return dict(rot=(0, 0, -CAM_YAW))


def icon_can_beans():
    return can("can_red", "rust")


def icon_can_soup():
    return can("can_blue", "paint_yellow")


def icon_pelt():
    objs = []
    # bottom layer (full hide, fur up) + the folded-over half on top, fur side up, a pale belly band on the fold
    b = hd.pillow((-0.26, -0.17, 0.0), (1, 0, 0), (0, 1, 0), (0, 0, 1), 0.52, 0.34, 0.035, name="PeltBottom",
                  mat="wolf_fur", nu=7, nv=5, rim=0.05, jitter=0.012, seed=3, bumps=0.01, levels=2,
                  drop_bottom=False)
    objs.append(b)
    band = hd.pillow((-0.25, -0.20, 0.028), (1, 0, 0), (0, 1, 0), (0, 0, 1), 0.50, 0.07, 0.03, name="PeltFold",
                     mat="wolf_belly", nu=7, nv=3, rim=0.02, jitter=0.006, seed=5, levels=2, drop_bottom=False)
    objs.append(band)
    t = hd.pillow((-0.25, -0.17, 0.045), (1, 0, 0), (0, 1, 0), (0, 0, 1), 0.50, 0.24, 0.035, name="PeltTop",
                  mat="wolf_fur", nu=7, nv=4, rim=0.05, jitter=0.012, seed=9, bumps=0.012, levels=2,
                  drop_bottom=False)
    objs.append(t)
    # bushy tail curling off the right side, pale tip
    tb = lp.MeshBuilder()
    pts = [Vector((0.22, 0.02, 0.06)), Vector((0.30, -0.02, 0.06)), Vector((0.36, -0.08, 0.05)),
           Vector((0.38, -0.15, 0.04)), Vector((0.35, -0.21, 0.035))]
    radii = [0.030, 0.042, 0.045, 0.036, 0.012]
    faces = hd.tube(tb, pts, radii, 8, "wolf_fur", cap_start=True)
    for fi in faces:
        if tb.center(fi).y < -0.165:
            tb.faces[fi][1] = "cloth_dark"
    finish(tb, "Tail", "sub", levels=1)
    # two ear-less paw flaps sticking out at the left
    pb = lp.MeshBuilder()
    for y in (-0.12, 0.11):
        hd.tube(pb, [(-0.25, y, 0.02), (-0.31, y * 1.15, 0.015), (-0.35, y * 1.25, 0.012)], [0.03, 0.026, 0.012], 6,
                "wolf_fur", cap_start=True)
    finish(pb, "Paws", "sub", levels=1)
    for o in bpy.context.scene.objects:
        if o.type == 'MESH':
            variant(o, "fur", rough=1.0)
    return dict(rot=(0, 0, -8))


def icon_coat():
    rnd = random.Random(66)
    body_col, trim = "parka_rust", "fur"
    mb = lp.MeshBuilder()
    # torso: tapered, slightly flared hem (y = depth)
    rows = []
    for z, hw, hd_ in ((0.0, 0.25, 0.10), (0.05, 0.245, 0.105), (0.35, 0.215, 0.10), (0.62, 0.23, 0.10),
                       (0.70, 0.19, 0.09), (0.74, 0.10, 0.07)):
        rows.append([Vector((x * hw, y * hd_, z)) for x, y in
                     ((-1, -1), (0, -1.12), (1, -1), (1.08, 0), (1, 1), (0, 1.05), (-1, 1), (-1.08, 0))])
    mb.loft(rows, body_col, cap_start=True, cap_end=True)
    torso = finish(mb, "Torso", "sub", levels=2)
    parts = [torso]
    # sleeves hanging from the shoulders, fur cuffs
    sl = lp.MeshBuilder()
    for sx in (-1, 1):
        pts = [Vector((sx * 0.19, 0.0, 0.66)), Vector((sx * 0.29, -0.01, 0.58)), Vector((sx * 0.33, -0.02, 0.36)),
               Vector((sx * 0.34, -0.03, 0.16))]
        hd.tube(sl, pts, [0.075, 0.08, 0.072, 0.066], 8, body_col, cap_start=True)
        hd.tube(sl, [pts[-1] + Vector((0, 0, 0.01)), pts[-1] + Vector((0.0, -0.002, -0.05))], [0.074, 0.07], 8,
                trim, cap_start=True)
    parts.append(finish(sl, "Sleeves", "sub", levels=1))
    # hood lump behind the neck + fur ruff around the opening
    hb = lp.MeshBuilder()
    hb.blob((0, 0.06, 0.78), (0.14, 0.10, 0.10), body_col, subdiv=1, jitter=0.04, rnd=rnd)
    parts.append(finish(hb, "Hood", "sub", levels=1))
    rb = lp.MeshBuilder()
    ruff = [Vector((0.13 * math.cos(a), -0.02 + 0.08 * math.sin(a), 0.74 + 0.05 * math.sin(a) ** 2))
            for a in [math.pi * (i / 10) for i in range(-1, 12)]]
    hd.tube(rb, ruff, [0.04] * len(ruff), 8, trim, cap_start=True)
    parts.append(finish(rb, "Ruff", "sub", levels=1))
    # hem fur band
    fb = lp.MeshBuilder()
    fb.loft([[Vector((x * 0.262, y * 0.112, 0.0)) for x, y in
              ((-1, -1), (0, -1.12), (1, -1), (1.08, 0), (1, 1), (0, 1.05), (-1, 1), (-1.08, 0))],
             [Vector((x * 0.258, y * 0.11, 0.07)) for x, y in
              ((-1, -1), (0, -1.12), (1, -1), (1.08, 0), (1, 1), (0, 1.05), (-1, 1), (-1.08, 0))]],
            trim, cap_start=True, cap_end=True)
    parts.append(finish(fb, "Hem", "sub", levels=1))
    # zip + toggles + pockets on the front
    dt = lp.MeshBuilder()
    dt.box((-0.008, -0.126, 0.07), (0.008, -0.108, 0.70), "strap")
    for z in (0.20, 0.36, 0.52):
        dt.box((-0.03, -0.128, z - 0.008), (0.03, -0.112, z + 0.008), "wood_light")
    for sx in (-1, 1):
        dt.box((sx * 0.07 - 0.055, -0.121, 0.12), (sx * 0.07 + 0.055, -0.100, 0.24), "parka_brown")
    finish(dt, "Details", "chamfer", width=0.004)
    for o in bpy.context.scene.objects:
        if o.type == 'MESH':
            variant(o, "cloth", rough=0.95)
    return dict(rot=(-24, 0, -CAM_YAW))


def icon_axe():
    load_model("stone_axe")
    return dict(rot=(0, 90, 0), post=(0, 0, 118))


def icon_torch():
    objs = load_model("torch")
    p = anchor(objs, "FlameAnchor")
    flame("Flame", p - Vector((0, 0, 0.035)), 0.20, 0.060, lean=(0.0, 0.0), seed=2)
    flame("Flame2", p + Vector((0.02, -0.018, -0.02)), 0.11, 0.035, lean=(0.25, -0.1), seed=5)
    glow(p + Vector((0, 0, 0.05)), 6.0)
    return dict(rot=(0, 34, 0), post=(0, 0, 70))


def icon_campfire():
    objs = load_model("campfire")
    p = anchor(objs, "FlameAnchor")
    flame("Flame", p - Vector((0, 0, 0.09)), 0.52, 0.17, lean=(0.05, 0.0), seed=1, sides=9)
    for k, (dx, dy, h, r, s) in enumerate(((-0.12, 0.06, 0.32, 0.10, 3), (0.12, -0.05, 0.34, 0.10, 4),
                                          (0.03, 0.13, 0.28, 0.09, 6), (-0.02, -0.13, 0.26, 0.08, 7))):
        flame("Tongue%d" % k, p + Vector((dx, dy, -0.10)), h, r, lean=(dx * 1.2, dy * 1.2), seed=s)
    glow(p + Vector((0, 0, 0.12)), 60.0, radius=0.12)
    return dict(rot=(0, 0, 0))


def icon_tent():
    load_model("tent")
    return dict(rot=(0, 0, 0))


def icon_box():
    load_model("storage_box")
    return dict(rot=(0, 0, 0))


ICONS = {
    "wood": icon_wood, "stone": icon_stone, "berry": icon_berry, "berries_hot": icon_berries_hot,
    "meat_raw": icon_meat_raw, "meat_cooked": icon_meat_cooked, "can_beans": icon_can_beans,
    "can_soup": icon_can_soup, "pelt": icon_pelt, "axe": icon_axe, "torch": icon_torch, "campfire": icon_campfire,
    "tent": icon_tent, "box": icon_box, "coat": icon_coat,
}


# ================================================================================================================
# stage: pose + normalise, camera, lights, world, render settings
# ================================================================================================================
def _euler(deg):
    from mathutils import Euler
    return Euler(tuple(math.radians(a) for a in deg), 'XYZ').to_matrix().to_4x4()


def _meshes():
    return sorted([o for o in bpy.context.scene.objects if o.type == 'MESH'], key=lambda o: o.name)


def _world_verts(objs):
    bpy.context.view_layer.update()
    out = []
    for o in objs:
        mw = o.matrix_world
        out += [mw @ v.co for v in o.data.vertices]
    return out


def cam_dir():
    y, p = math.radians(CAM_YAW), math.radians(CAM_PITCH)
    return Vector((math.sin(y) * math.cos(p), -math.cos(y) * math.cos(p), math.sin(p)))


def light_dir(az, el):
    a, e = math.radians(CAM_YAW + az), math.radians(el)
    return Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e)))


def stage(pose):
    """Parent everything to a root, pose it, centre it and scale its bounding sphere to radius 1."""
    sc = bpy.context.scene
    for o in list(sc.objects):
        if o.type == 'EMPTY' and not o.children:
            bpy.data.objects.remove(o, do_unlink=True)
    root = bpy.data.objects.new("IconRoot", None)
    sc.collection.objects.link(root)
    bpy.context.view_layer.update()
    for o in list(sc.objects):
        if o is root or o.parent is not None or o.type == 'CAMERA':
            continue
        mw = o.matrix_world.copy()
        o.parent = root
        o.matrix_parent_inverse = Matrix.Identity(4)
        o.matrix_world = mw
    R = _euler(pose.get("rot", (0, 0, 0)))
    if "post" in pose:
        R = _euler(pose["post"]) @ R
    root.matrix_world = R
    vs = _world_verts(_meshes())
    mn = Vector([min(v[i] for v in vs) for i in range(3)])
    mx = Vector([max(v[i] for v in vs) for i in range(3)])
    c = (mn + mx) / 2
    s = 1.0 / max(1e-6, (mx - mn).length / 2)
    root.matrix_world = Matrix.Scale(s, 4) @ Matrix.Translation(-c) @ R
    bpy.context.view_layer.update()
    return root, (mn.z - c.z) * s


def setup_render(ground_z):
    sc = bpy.context.scene
    r = sc.render
    r.engine = 'CYCLES'
    r.resolution_x = r.resolution_y = RES
    r.resolution_percentage = 100
    r.film_transparent = True
    r.image_settings.file_format = 'PNG'
    r.image_settings.color_mode = 'RGBA'
    r.image_settings.color_depth = '8'
    r.image_settings.compression = 90
    r.use_stamp = False
    for p in r.bl_rna.properties:
        if p.identifier.startswith("use_stamp") and not p.is_readonly:
            try:
                setattr(r, p.identifier, False)
            except Exception:
                pass
    r.threads_mode = 'FIXED'
    r.threads = max(1, os.cpu_count() or 1)
    cy = sc.cycles
    cy.device = 'CPU'
    cy.samples = SAMPLES
    cy.use_adaptive_sampling = False
    cy.seed = 7
    cy.use_denoising = True
    cy.denoiser = 'OPENIMAGEDENOISE'
    cy.max_bounces = 6
    cy.filter_width = 1.2
    cy.film_transparent_glass = False
    vs = sc.view_settings
    vs.view_transform = VIEW
    vs.look = LOOK
    vs.exposure = EXPOSURE
    vs.gamma = 1.0
    sc.display_settings.display_device = 'sRGB'
    # world: dim cool ambient
    w = bpy.data.worlds.new("IconWorld")
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", DeprecationWarning)
        w.use_nodes = True
    bg = w.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = WORLD[0] + (1.0,)
    bg.inputs["Strength"].default_value = WORLD[1]
    sc.world = w
    # lights
    for name, (az, el, strength, angle, col) in LIGHTS.items():
        li = bpy.data.lights.new(name, 'SUN')
        li.energy = strength
        li.angle = math.radians(angle)
        li.color = col
        ob = bpy.data.objects.new(name, li)
        ob.rotation_euler = (-light_dir(az, el)).to_track_quat('-Z', 'Y').to_euler()
        sc.collection.objects.link(ob)
    # camera, orthographic, framed on the projected bounds
    cam = bpy.data.objects.new("IconCam", bpy.data.cameras.new("IconCam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    d = cam_dir()
    rot = (-d).to_track_quat('-Z', 'Y')
    cam.rotation_euler = rot.to_euler()
    cam.data.type = 'ORTHO'
    cam.data.clip_start = 0.1
    cam.data.clip_end = 100.0
    m3 = rot.to_matrix()
    right, up = m3 @ Vector((1, 0, 0)), m3 @ Vector((0, 1, 0))
    vs_ = [v for v in _world_verts([o for o in _meshes() if not o.name.startswith("IconGround")])]
    xs = [v.dot(right) for v in vs_]
    ys = [v.dot(up) for v in vs_]
    cx, cy_ = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    ext = max(max(xs) - min(xs), max(ys) - min(ys))
    cam.data.ortho_scale = ext / FILL
    cam.location = right * cx + up * cy_ + d * 20.0
    # contact shadow
    if SHADOW:
        bpy.ops.mesh.primitive_plane_add(size=40.0, location=(0, 0, ground_z))
        g = bpy.context.active_object
        g.name = "IconGround"
        g.is_shadow_catcher = True
        g.visible_glossy = False


# ================================================================================================================
# hashing + PNG metadata
# ================================================================================================================
def scene_digest(pose):
    h = hashlib.sha1()
    with open(os.path.abspath(__file__), "rb") as f:
        h.update(f.read())
    h.update(repr(sorted(pose.items())).encode())
    for o in sorted(bpy.context.scene.objects, key=lambda o: o.name):
        h.update(o.name.encode())
        h.update(repr([round(x, 5) for row in o.matrix_world for x in row]).encode())
        if o.type == 'MESH':
            me = o.data
            co = [0.0] * (len(me.vertices) * 3)
            me.vertices.foreach_get("co", co)
            h.update(repr([round(x, 5) for x in co]).encode())
            h.update(repr([tuple(p.vertices) for p in me.polygons]).encode())
            h.update(repr([p.material_index for p in me.polygons]).encode())
            h.update(repr([m.name if m else "" for m in me.materials]).encode())
            col = me.color_attributes.get(palette.VCOL_ATTR)
            if col is not None:
                data = [0.0] * (len(col.data) * 4)
                col.data.foreach_get("color", data)
                h.update(repr([round(x, 4) for x in data]).encode())
        elif o.type == 'LIGHT':
            h.update(repr((o.data.type, round(o.data.energy, 4))).encode())
    return h.hexdigest()


def _chunks(data):
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")
    i = 8
    while i < len(data):
        n = struct.unpack(">I", data[i:i + 4])[0]
        yield data[i + 4:i + 8], data[i + 8:i + 8 + n]
        i += 12 + n


def png_hash(path):
    try:
        with open(path, "rb") as f:
            data = f.read()
        for typ, body in _chunks(data):
            if typ == b"tEXt" and body.startswith(HASH_KEY.encode() + b"\0"):
                return body.split(b"\0", 1)[1].decode()
    except (OSError, ValueError):
        pass
    return None


def write_png(src, dst, digest):
    """Copy the PNG keeping only the image chunks + our hash (no date / render-time metadata: deterministic)."""
    with open(src, "rb") as f:
        data = f.read()
    out = [data[:8]]

    def chunk(typ, body):
        return struct.pack(">I", len(body)) + typ + body + struct.pack(">I", zlib.crc32(typ + body) & 0xffffffff)
    for typ, body in _chunks(data):
        if typ in (b"tEXt", b"zTXt", b"iTXt", b"tIME"):
            continue
        out.append(chunk(typ, body))
        if typ == b"IHDR":
            out.append(chunk(b"tEXt", HASH_KEY.encode() + b"\0" + digest.encode()))
    with open(dst, "wb") as f:
        f.write(b"".join(out))


# ================================================================================================================
# build
# ================================================================================================================
def build_icon(name, force=False):
    lp.new_scene()
    pose = ICONS[name]() or {}
    root, ground_z = stage(pose)
    digest = scene_digest(pose)
    dst = os.path.join(OUT_DIR, name + ".png")
    if not force and png_hash(dst) == digest:
        return "unchanged"
    setup_render(ground_z)
    tmp = tempfile.mkdtemp(prefix="ventisca_icon_")
    src = os.path.join(tmp, name + ".png")
    bpy.context.scene.render.filepath = src
    from lib.export import quiet
    with quiet():
        bpy.ops.render.render(write_still=True)
    write_png(src, dst, digest)
    os.remove(src)
    os.rmdir(tmp)
    return "rendered"


def contact_sheet(path, names=None):
    """All icons on the UI panel colour at 96 px (top) and 48 px (bottom), with names. Needs Pillow."""
    from PIL import Image, ImageDraw
    names = names or list(ICONS)
    bg = (0x1E, 0x2A, 0x3A, 255)
    slot = (0x2A, 0x3A, 0x50, 255)
    cw, pad = 112, 8
    W = pad + len(names) * cw
    H = 96 + 48 + 64
    img = Image.new("RGBA", (W, H), bg)
    dr = ImageDraw.Draw(img)
    for i, n in enumerate(names):
        p = os.path.join(OUT_DIR, n + ".png")
        if not os.path.exists(p):
            continue
        ic = Image.open(p).convert("RGBA")
        x = pad + i * cw
        big = ic.resize((96, 96), Image.LANCZOS)
        img.alpha_composite(big, (x + 4, 6))
        dr.rounded_rectangle((x + 28, 108, x + 28 + 52, 108 + 52), 6, fill=slot)
        small = ic.resize((48, 48), Image.LANCZOS)
        img.alpha_composite(small, (x + 30, 110))
        dr.text((x + 4, H - 16), n, fill=(220, 235, 250, 255))
    img.convert("RGB").save(path)
    return path


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    force = "--force" in argv
    sheet = None
    if "--sheet" in argv:
        k = argv.index("--sheet")
        sheet = argv[k + 1]
        del argv[k:k + 2]
    names = [a for a in argv if not a.startswith("--")] or list(ICONS)
    for n in names:
        if n not in ICONS:
            raise KeyError("unknown icon %r (known: %s)" % (n, ", ".join(ICONS)))
    os.makedirs(OUT_DIR, exist_ok=True)
    for n in names:
        print("icon %-12s %s" % (n, build_icon(n, force)))
    if sheet:
        print("contact sheet: %s" % contact_sheet(sheet))
    return 0


if __name__ == "__main__":
    sys.exit(main())
