"""Diegetic signs of the M6a test street (ASSET_SPEC_V2 "M6a", docs/research/10_hud_ux.md §7.4: readable at 24 m).

    cd winter-survival/blender && python3 props/build_signs.py [glyphs sign_street ...]

Two parts, both vertex colour only (no textures, no Label3D atlas): the game composes any text from a MESH FONT and
lays it on a sign board's TextPanel.

  signs/glyphs.glb      the mesh font: one flat mesh per glyph, `G_<codepoint>` (A-Z, Ñ, Á É Í Ó Ú Ü Ç, 0-9, and
                        . , - / º ª : ' ( ) & · → ← +), cut from Barlow Condensed SemiBold (assets/fonts/, OFL) with
                        Blender's text-to-mesh (curve resolution 2, collinear points dissolved, beauty triangulation).
                        Units: CAP HEIGHT = 1.0 (scale by the wanted cap height in metres); origin = pen position on the
                        baseline; the glyph lies in the XZ plane of Blender facing -Y (Godot: XY plane facing +Z, the
                        sign's front); extras `char`, `advance` (pen advance incl. tracking, cap units), `width`.
                        Colour paint_white, AO 1: the code rewrites COLOR per sign (dark letters on light plates).
  signs/sign_street     street-name plate on a galvanised post, blue enamel 2.6 x 0.62 with a white rim, BOTH faces
                        carry text (TextPanel_0 front -Y, TextPanel_1 back +Y), snow on the top edge.
  signs/sign_house_number  wall plaque 0.62 x 0.50 (white enamel, blue rim), origin = wall contact point (centre of
                        its back), sticks out toward -Y; TextPanel_0.
  signs/sign_shop       shop fascia board 2.6 x 0.62 (dark green, cream moulding), wall-mounted like the plaque.
  signs/sign_road       road / town sign (S-500 style: white plate 3.6 x 1.3 with a black rim) on two galvanised
                        posts; TextPanel_0 front, TextPanel_1 back (the code writes the name struck through: end of
                        the town, S-510).
Extras on `Prop` (the A1 sign contract, like km_sign): col / col_center / col_size (Godot frame), panels
{"Panel": [w, h]}, `text_w` (max text width, m), `text_h` (cap height, m: >= 0.30 ambient, >= 0.45 for the road sign,
doc 10 §7.4), `text_color` / `plate_color` (palette names), `double_sided`, anchors {TextPanel_n: Godot position}.
`Panel` is the face mesh under the text, `TextPanel_<n>` its centre 3 cm in front (TextPanel_1 faces +Y Blender =
-Z Godot: the code turns the text 180 degrees about Y there).
"""
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import bpy  # noqa: E402,F401
import bmesh  # noqa: E402  (after bpy)
from mathutils import Matrix, Vector  # noqa: E402

from lib import export  # noqa: E402
from lib import hd as H  # noqa: E402
from lib import lowpoly as lp  # noqa: E402
from lib import palette  # noqa: E402
from lib import veg as V  # noqa: E402

SUBDIR = "signs"
FONT = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
                    "assets", "fonts", "barlow_condensed", "BarlowCondensed-SemiBold.ttf")
CHARSET = "ABCDEFGHIJKLMNOPQRSTUVWXYZÑÁÉÍÓÚÜÇ0123456789.,-/ºª:'()&·→←+"
TRACKING = 0.10          # extra pen advance, cap units
SPACE = 0.32             # advance of ' ' (cap units; the code handles spaces)
GLYPH_BUDGET = 140       # tris per glyph
BOARD_BUDGET = 700


def godot(p):
    return V.godot(p)


# ------------------------------------------------------------------------------------------------------------
# mesh font
# ------------------------------------------------------------------------------------------------------------
def glyph_mesh(font, ch, scale):
    """Flat glyph mesh (Blender XZ plane facing -Y), cap height 1: returns (MeshBuilder, xmin, xmax)."""
    cu = bpy.data.curves.new("glyph", 'FONT')
    cu.body = ch
    cu.font = font
    cu.size = 1.0
    cu.resolution_u = 2
    ob = bpy.data.objects.new("glyph_tmp", cu)
    bpy.context.scene.collection.objects.link(ob)
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(2.0), verts=bm.verts, edges=bm.edges)
    bmesh.ops.triangulate(bm, faces=bm.faces, quad_method='BEAUTY', ngon_method='BEAUTY')
    mb = lp.MeshBuilder()
    xs = []
    for f in bm.faces:
        pts = [Vector((v.co.x * scale, 0.0, v.co.y * scale)) for v in f.verts]
        xs += [p.x for p in pts]
        n = (pts[1] - pts[0]).cross(pts[2] - pts[0])
        if n.length < 1e-10:
            continue
        mb.poly(pts, "paint_white", facing=(0, -1, 0))
    bm.free()
    bpy.data.objects.remove(ob)
    bpy.data.curves.remove(cu)
    bpy.data.meshes.remove(me)
    return mb, (min(xs) if xs else 0.0), (max(xs) if xs else 0.0)


def build_glyphs():
    lp.new_scene()
    font = bpy.data.fonts.load(FONT)
    mb_h, _a, _b = glyph_mesh(font, "H", 1.0)
    cap = max(v.z for v in mb_h.verts)
    scale = 1.0 / cap
    table = {}
    for ch in CHARSET:
        mb, x0, x1 = glyph_mesh(font, ch, scale)
        if not mb.faces:
            raise RuntimeError("glyph %r has no geometry" % ch)
        o = H.flat(H.mk(mb, "G_%d" % ord(ch)))
        o["char"] = ch
        o["advance"] = round(x1 + TRACKING, 4)
        o["width"] = round(x1 - x0, 4)
        tris = lp.tri_count(o)
        if tris > GLYPH_BUDGET:
            raise RuntimeError("glyph %r: %d tris > %d" % (ch, tris, GLYPH_BUDGET))
        table[ch] = {"node": o.name, "advance": o["advance"], "width": o["width"], "tris": tris}
    bpy.data.fonts.remove(font)
    glb = export.save_and_export("glyphs", SUBDIR, ao=False, import_kind="prop")
    meta = {"font": "Barlow Condensed SemiBold (OFL, assets/fonts/barlow_condensed)", "cap": 1.0, "space": SPACE,
            "tracking": TRACKING, "glyphs": table}
    with open(os.path.join(os.path.dirname(str(glb)), "glyphs.json"), "w") as f:
        json.dump(meta, f, indent=1, ensure_ascii=False, sort_keys=True)
        f.write("\n")
    # AO = 1 everywhere (flat decals; the plate under them carries the AO)
    return glb


def _set_ao_one(names):
    for n in names:
        o = bpy.data.objects[n]
        col = o.data.color_attributes[0]
        data = [0.0] * (len(col.data) * 4)
        col.data.foreach_get("color", data)
        for i in range(3, len(data), 4):
            data[i] = 1.0
        col.data.foreach_set("color", data)


# ------------------------------------------------------------------------------------------------------------
# boards
# ------------------------------------------------------------------------------------------------------------
def _rim(mb, x0, x1, z0, z1, y0, y1, w, mat):
    mb.box((x0, y0, z1 - w), (x1, y1, z1), mat)
    mb.box((x0, y0, z0), (x1, y1, z0 + w), mat)
    mb.box((x0, y0, z0 + w), (x0 + w, y1, z1 - w), mat)
    mb.box((x1 - w, y0, z0 + w), (x1, y1, z1 - w), mat)


def sign_street():
    """Street-name plate on a galvanised post (double sided)."""
    W, Hh, zc = 2.6, 0.62, 2.55
    mb = lp.MeshBuilder()
    mb.cylinder((0, 0.0, -0.2), (0, 0.0, zc + Hh / 2 + 0.12), 0.05, 0.045, 8, "metal_sheet", cap_mats=(None, "iron"))
    for z in (zc - 0.18, zc + 0.18):
        mb.box((-0.08, -0.035, z - 0.03), (0.08, 0.035, z + 0.03), "iron")                      # clamps
    _rim(mb, -W / 2, W / 2, zc - Hh / 2, zc + Hh / 2, -0.03, 0.03, 0.045, "paint_white")
    pan = lp.MeshBuilder()
    pan.box((-W / 2 + 0.045, -0.022, zc - Hh / 2 + 0.045), (W / 2 - 0.045, 0.022, zc + Hh / 2 - 0.045), "metal_blue")
    prop = H.flat(H.mk(mb, "Prop"))
    snow = H.snow_ridge((-W / 2 + 0.03, 0.0, zc + Hh / 2), (W / 2 - 0.03, 0.0, zc + Hh / 2), 0.07, 0.05, seed=701,
                        segs=5)
    prop = H.join([prop, snow, H.mound((0, 0, 0), 0.3, 0.10, seed=702, sides=8, sink=0.05)], "Prop")
    panel = H.flat(H.mk(pan, "Panel"))
    texts = {"TextPanel_0": (0.0, -0.052, zc), "TextPanel_1": (0.0, 0.052, zc)}
    info = dict(col="cylinder", col_center=godot((0, 0, 1.4)), col_size=[0.1, 2.8], panels={"Panel": [W, Hh]},
                text_w=W - 0.24, text_h=0.40, text_color="paint_white", plate_color="metal_blue", double_sided=True,
                mount="post")
    return prop, panel, texts, info, dict(distance=0.4, samples=48, ground=True)


def sign_house_number():
    """Enamel house-number plaque (wall-mounted, origin at the wall contact point)."""
    W, Hh = 0.62, 0.50
    mb = lp.MeshBuilder()
    mb.box((-W / 2, -0.03, -Hh / 2), (W / 2, 0.0, Hh / 2), "metal_blue")                        # back plate + rim
    pan = lp.MeshBuilder()
    pan.box((-W / 2 + 0.04, -0.034, -Hh / 2 + 0.04), (W / 2 - 0.04, -0.03, Hh / 2 - 0.04), "paint_white")
    for x in (-W / 2 + 0.07, W / 2 - 0.07):
        mb.box((x - 0.015, -0.036, -0.015), (x + 0.015, -0.03, 0.015), "iron")                 # screws
    prop = H.flat(H.mk(mb, "Prop"))
    panel = H.flat(H.mk(pan, "Panel"))
    texts = {"TextPanel_0": (0.0, -0.037, 0.0)}
    info = dict(col="none", col_center=[0.0, 0.0, 0.0], col_size=[], panels={"Panel": [W - 0.08, Hh - 0.08]},
                text_w=W - 0.14, text_h=0.34, text_color="metal_blue", plate_color="paint_white", double_sided=False,
                mount="wall")
    return prop, panel, texts, info, dict(distance=0.25, samples=48, ground=False, walls=[((0, 0, 0), (0, -1, 0))])


def sign_shop():
    """Shop fascia board (wall-mounted): dark green field, cream moulding, snow along the top."""
    W, Hh = 2.6, 0.62
    mb = lp.MeshBuilder()
    mb.box((-W / 2, -0.05, -Hh / 2), (W / 2, 0.0, Hh / 2), "cabin_trim")                         # moulding / back
    mb.box((-W / 2 - 0.03, -0.07, Hh / 2), (W / 2 + 0.03, 0.0, Hh / 2 + 0.05), "cabin_trim")     # cornice
    pan = lp.MeshBuilder()
    pan.box((-W / 2 + 0.06, -0.058, -Hh / 2 + 0.06), (W / 2 - 0.06, -0.05, Hh / 2 - 0.06), "military_green")
    prop = H.flat(H.mk(mb, "Prop"))
    snow = H.snow_ridge((-W / 2 - 0.02, -0.035, Hh / 2 + 0.05), (W / 2 + 0.02, -0.035, Hh / 2 + 0.05), 0.07, 0.04,
                        seed=711, segs=5)
    prop = H.join([prop, snow], "Prop")
    panel = H.flat(H.mk(pan, "Panel"))
    texts = {"TextPanel_0": (0.0, -0.062, 0.0)}
    info = dict(col="none", col_center=[0.0, 0.0, 0.0], col_size=[], panels={"Panel": [W - 0.12, Hh - 0.12]},
                text_w=W - 0.3, text_h=0.38, text_color="cabin_trim", plate_color="military_green",
                double_sided=False, mount="wall")
    return prop, panel, texts, info, dict(distance=0.25, samples=48, ground=False, walls=[((0, 0, 0), (0, -1, 0))])


def sign_road():
    """S-500 town / road sign: white plate with a black rim on two galvanised posts (front and back text)."""
    W, Hh, zc = 3.6, 1.3, 2.35
    mb = lp.MeshBuilder()
    for x in (-1.2, 1.2):
        mb.cylinder((x, 0.06, -0.2), (x, 0.06, zc + Hh / 2 + 0.05), 0.055, 0.05, 8, "metal_sheet",
                    cap_mats=(None, "iron"))
        for z in (zc - 0.4, zc + 0.4):
            mb.box((x - 0.08, 0.02, z - 0.03), (x + 0.08, 0.10, z + 0.03), "iron")
    _rim(mb, -W / 2, W / 2, zc - Hh / 2, zc + Hh / 2, -0.028, 0.028, 0.06, "paint_black")
    pan = lp.MeshBuilder()
    pan.box((-W / 2 + 0.06, -0.02, zc - Hh / 2 + 0.06), (W / 2 - 0.06, 0.02, zc + Hh / 2 - 0.06), "paint_white")
    prop = H.flat(H.mk(mb, "Prop"))
    snow = H.snow_ridge((-W / 2 + 0.02, 0.0, zc + Hh / 2), (W / 2 - 0.02, 0.0, zc + Hh / 2), 0.07, 0.06, seed=721,
                        segs=6)
    mounds = [H.mound((x, 0.06, 0), 0.32, 0.12, seed=722 + i, sides=8, sink=0.05) for i, x in enumerate((-1.2, 1.2))]
    prop = H.join([prop, snow] + mounds, "Prop")
    panel = H.flat(H.mk(pan, "Panel"))
    texts = {"TextPanel_0": (0.0, -0.05, zc), "TextPanel_1": (0.0, 0.05, zc)}
    info = dict(col="box", col_center=godot((0, 0.06, 1.2)), col_size=[2.6, 2.4, 0.15], panels={"Panel": [W, Hh]},
                text_w=W - 0.3, text_h=0.45, text_color="paint_black", plate_color="paint_white", double_sided=True,
                mount="post")
    return prop, panel, texts, info, dict(distance=0.4, samples=48, ground=True)


BOARDS = {"sign_street": sign_street, "sign_house_number": sign_house_number, "sign_shop": sign_shop,
          "sign_road": sign_road}


def build_board(name):
    lp.new_scene()
    prop, panel, texts, info, ao = BOARDS[name]()
    for k, v in info.items():
        prop[k] = v
    prop["anchors"] = {k: godot(p) for k, p in texts.items()}
    for k, p in texts.items():
        lp.add_empty(k, p, size=0.05)
    tris = lp.scene_tris()
    if tris > BOARD_BUDGET:
        raise RuntimeError("%s: tris %d > %d" % (name, tris, BOARD_BUDGET))
    return export.save_and_export(name, SUBDIR, ao=ao, import_kind="prop")


ALL = ["glyphs"] + list(BOARDS)


def main(argv=()):
    names = [a for a in argv if not a.startswith("-")] or ALL
    for n in names:
        if n == "glyphs":
            build_glyphs()
        else:
            build_board(n)


if __name__ == "__main__":
    main(sys.argv[1:])
