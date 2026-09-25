"""Palette (ASSET_SPEC_V2 §3, v2.1 values of milestone G1) -> baked vertex colours (decision C2).

Every visual mesh carries ONE colour attribute `Col` (corner domain, float colour = the palette hex converted
sRGB -> linear; the glTF exporter writes it unchanged as `COLOR_0`) and ONE shared material `palette_vcol`
(Principled, Base Color = the `Col` attribute on a white factor, roughness 0.9, metallic 0, no emission).
Faces painted with one of the named EXCEPTIONS get their own material instead (second surface), and white
in `Col` so that an importer that multiplies albedo by COLOR_0 (Godot does) still shows the material colour.

Godot quantisation (measured with 4.7.2): Godot stores COLOR as RGBA8 *linear* and truncates
(uint8(c * 255)), which would darken 13 of the 81 palette colours by 3-6 sRGB levels (bark, boots, hat,
iron, tire, ...). `Col` therefore holds the centre of the nearest 8-bit linear bin (≈ linear + GODOT_BIAS, half an
8-bit step): Godot's truncation then lands on the nearest 8-bit linear value (godot_bytes()), and COLOR_0 stays
within 0.5/255 of the exact linear palette colour.

    palette.paint(obj_or_mesh, faces, "cabin_wall")    # repaint polygons of an existing mesh
    palette.assign(mesh, names)                        # one name per polygon (lowpoly.to_object uses it)
    palette.zombify("jacket")  -> "z_jacket"           # 40 % toward cloth_gray, registered in PALETTE

v2.1 (G1): COLOR_0 is RGBA. RGB = the palette colour exactly as above (linear + GODOT_BIAS); A = ambient occlusion
baked by lib/hd.py::bake_ao (1 = open, 0 = fully occluded; export.save_and_export bakes it for every asset). Every
function here writes alpha 1.0; only the AO bake touches alpha.
"""
import warnings

import bpy

PALETTE = {
    # slice colours (v2.1 re-tuned values: docs/research/05_graficos_arte.md §4.1, milestone G1)
    "snow": "#CDDEF5", "snow_shadow": "#AFC3E0", "ice": "#BFE3F0",
    "pine_dark": "#1F342E", "pine_light": "#2F4A3D", "bark": "#4A3D35",
    "wood": "#7A5F4B", "wood_light": "#A88E70", "wood_dark": "#4A3B31",
    "stone": "#7B8089", "stone_dark": "#565B63", "brick": "#735F5D",
    "iron": "#2A2B2E", "cabin_wall": "#6C829C", "cabin_trim": "#D3CFC6",
    "roof": "#48434A", "window": "#9CC4DD", "truck_paint": "#5E6650",
    "bush": "#3E6B45", "berry": "#D9403D", "ember": "#E63B12",
    "jacket": "#B03A2E", "hat": "#2E4A7A", "scarf": "#E8B04B",
    "skin": "#F1C9A5", "boots": "#2A2320", "wolf_fur": "#6E7378",
    "wolf_belly": "#A9AEB2", "eyes": "#F5D142", "eyes_dark": "#1E1E24",
    "deer_fur": "#8A6A48", "deer_belly": "#C9B79C", "cloth": "#C9B79C",
    "paper": "#EDE6D6", "can_red": "#C23B3B", "can_blue": "#3B6BC2",
    # v2 additions
    "jacket_blue": "#2F5C9E", "jacket_green": "#3D7A4E", "jacket_mustard": "#C9952B",
    "skin_dark": "#8D5B3C", "skin_zombie": "#9AA48C", "skin_frozen": "#C7D9E6",
    "blood": "#8B1E1E", "blood_dry": "#6B1F1F", "gore": "#A33A3A",
    "cloth_gray": "#6E7075", "cloth_dark": "#3A3C42", "cloth_white": "#E9ECEF",
    "denim": "#41598A", "police_blue": "#243B6B", "military_green": "#4F5A3C",
    "hospital_green": "#7FB9A6", "hivis_orange": "#F28C28", "rust": "#8A4A2B",
    "asphalt": "#3E4248", "asphalt_line": "#D9D2B0", "concrete": "#9EA3A8",
    "concrete_dark": "#6F747A", "brick_dark": "#6E4438", "plaster": "#D8CFC0",
    "metal_sheet": "#7A8590", "metal_blue": "#4D6B8A", "paint_red": "#A83A32",
    "paint_white": "#E6E9EC", "paint_yellow": "#E0B93A", "paint_black": "#1C1E22",
    "tire": "#1F2124", "chrome": "#C4CBD2", "glass": "#7FA6C2",
    "ice_clear": "#A9D8EA", "ice_thin": "#7FB3CC", "emissive_lamp": "#FFE2A8",
    "gun_metal": "#3A3E45", "gun_wood": "#6B4A2E", "brass": "#B8963E",
    "plastic_black": "#25272B", "plastic_red": "#C0392B", "plastic_blue": "#2E86C1",
    "hay": "#C9B26B", "dirt": "#5A4A3A", "moss": "#5C7A4A",
    # v2.1 additions (docs/research/05_graficos_arte.md §4.1, milestone G1)
    "snow_packed": "#BFD0E8", "snow_hole": "#93AACB", "snow_deep": "#D6E4F7", "roof_seam": "#2C2A2E",
    "bark_grey": "#4E4843", "pine_mid": "#27402F",
    "parka_brown": "#4F4135", "parka_olive": "#4C5040", "parka_navy": "#3A4457", "parka_rust": "#7A4536",
    "pants_dark": "#35383D", "beanie": "#2E3035", "fur": "#CEC8BD", "pack": "#5D4C3C", "pack_dark": "#3D352D",
    "boots_brown": "#5B412F", "sock": "#D9D4CB", "skin_hd": "#C29478", "glove": "#2F2B28", "mat_roll": "#6D7558",
    "strap": "#2B2826", "beard": "#4A3A30",
    # G1 additions (ASSET_SPEC_V2 "G1"): muted co-op parkas for the green / mustard survivors; tail-light red and
    # headlight lens that do not glare against the v2.1 palette
    "parka_green": "#465A43", "parka_mustard": "#8A6B34", "lamp_red": "#8C3A34", "lamp_clear": "#BFC4C2",
}
BASE_NAMES = tuple(PALETTE)

VCOL_MATERIAL = "palette_vcol"
VCOL_ATTR = "Col"
# Named exceptions (ASSET_SPEC_V2 §2.5): painting a face with one of these gives it its own material.
EXCEPTIONS = ("window", "glass", "ember", "ice_clear", "emissive_lamp")
# `blood` is a plain vertex colour; a separate blood material is requested explicitly with "mat:blood".
OPTIONAL_EXCEPTIONS = ("blood",)
MATERIAL_PREFIX = "mat:"
WHITE = (1.0, 1.0, 1.0, 1.0)
GODOT_BIAS = 0.5 / 255.0
VERSION = "2.1"


def srgb_to_linear(c):
    """Exact sRGB transfer function (0..1 in, 0..1 out)."""
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_bytes(hex_str):
    h = hex_str.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def hex_to_linear_rgba(hex_str):
    return tuple(srgb_to_linear(b / 255.0) for b in hex_bytes(hex_str)) + (1.0,)


def srgb_rgba(name):
    """Palette colour as sRGB floats (0..1)."""
    return tuple(b / 255.0 for b in hex_bytes(PALETTE[name])) + (1.0,)


def linear_rgba(name):
    return hex_to_linear_rgba(PALETTE[name])


def vcol_rgba(name):
    """Value stored in `Col` / COLOR_0 for palette colour `name`: the CENTRE of the 8-bit linear bin Godot keeps
    for it ((round(linear * 255) + 0.5) / 255, i.e. linear + GODOT_BIAS rounded to the bin centre). v2.1: the NAME
    export writes COLOR_0 as normalised 16-bit, and a plain linear + 0.5/255 that lands within 1/65535 of a bin
    edge (eyes_dark blue: 4.9988 / 255) could round into the next bin; the bin centre is robust to that."""
    return tuple(min(1.0, (int(round(c * 255.0)) + 0.5) / 255.0) for c in linear_rgba(name)[:3]) + (1.0,)


def godot_bytes(linear_rgb):
    """What Godot 4.7 keeps of a linear COLOR value: uint8(c * 255) per channel (truncation)."""
    return tuple(int(max(0.0, min(255.0, c * 255.0))) for c in linear_rgb[:3])


def target_godot_bytes(name):
    """Best possible 8-bit linear representation of palette colour `name` (nearest step)."""
    return tuple(int(round(c * 255.0)) for c in linear_rgba(name)[:3])


def is_exception(name):
    """True when faces painted `name` get their own material (and white vertex colour)."""
    return name in EXCEPTIONS or (name.startswith(MATERIAL_PREFIX) and name[len(MATERIAL_PREFIX):] in
                                  EXCEPTIONS + OPTIONAL_EXCEPTIONS)


def material_name(name):
    """Material a face painted `name` ends up in."""
    if not is_exception(name):
        check(name)
        return VCOL_MATERIAL
    return name[len(MATERIAL_PREFIX):] if name.startswith(MATERIAL_PREFIX) else name


def check(name):
    if name not in PALETTE:
        raise KeyError("colour %r is not in the palette (ASSET_SPEC_V2 §3)" % name)


def zombify(name, amount=0.40):
    """Desaturated zombie variant: mix `amount` toward cloth_gray (sRGB), registered as z_<name>."""
    base = name[2:] if name.startswith("z_") else name
    key = "z_" + base
    if key not in PALETTE:
        a = hex_bytes(PALETTE[base])
        g = hex_bytes(PALETTE["cloth_gray"])
        PALETTE[key] = "#" + "".join("%02X" % int(round(x + (y - x) * amount)) for x, y in zip(a, g))
    return key


def all_names():
    """The palette plus every z_* variant."""
    for n in BASE_NAMES:
        zombify(n)
    return list(PALETTE)


# ------------------------------------------------------------------------------------------------
# materials
# ------------------------------------------------------------------------------------------------
def _principled(mat, rgba):
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", DeprecationWarning)
        # Blender 5.0.1: still required, otherwise the glTF exporter uses the viewport colour (0.8 grey)
        mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = rgba
    bsdf.inputs["Roughness"].default_value = 0.9
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Alpha"].default_value = 1.0
    for key in ("Emission Color", "Emission"):
        if key in bsdf.inputs:
            bsdf.inputs[key].default_value = (0.0, 0.0, 0.0, 1.0)
            break
    if "Emission Strength" in bsdf.inputs:
        bsdf.inputs["Emission Strength"].default_value = 0.0
    mat.diffuse_color = rgba
    mat.roughness = 0.9
    mat.metallic = 0.0
    return bsdf


def _new(name):
    mat = bpy.data.materials.new(name)
    if mat.name != name:
        raise RuntimeError("material name collision: %s -> %s" % (name, mat.name))
    return mat


def get_vcol_material():
    """The shared `palette_vcol` material: Base Color = colour attribute `Col` (white factor)."""
    mat = bpy.data.materials.get(VCOL_MATERIAL)
    if mat is not None:
        return mat
    mat = _new(VCOL_MATERIAL)
    bsdf = _principled(mat, WHITE)
    node = mat.node_tree.nodes.new("ShaderNodeVertexColor")
    node.layer_name = VCOL_ATTR
    node.location = (bsdf.location.x - 300, bsdf.location.y)
    mat.node_tree.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


def _material_by_name(mname):
    if mname == VCOL_MATERIAL:
        return get_vcol_material()
    if mname not in EXCEPTIONS + OPTIONAL_EXCEPTIONS:
        raise KeyError("material %r is not palette_vcol or a named exception (ASSET_SPEC_V2 §2.5)" % mname)
    mat = bpy.data.materials.get(mname)
    if mat is None:
        mat = _new(mname)
        _principled(mat, linear_rgba(mname))
    return mat


def get_material(name):
    """Material for faces painted `name`: palette_vcol, or the named exception material."""
    return _material_by_name(material_name(name))


# ------------------------------------------------------------------------------------------------
# colour attribute
# ------------------------------------------------------------------------------------------------
def _mesh(target):
    return target.data if isinstance(target, bpy.types.Object) else target


def ensure_attribute(me):
    attr = me.color_attributes.get(VCOL_ATTR)
    if attr is None:
        attr = me.color_attributes.new(VCOL_ATTR, 'FLOAT_COLOR', 'CORNER')
        data = [1.0] * (len(me.loops) * 4)
        attr.data.foreach_set("color", data)
    me.color_attributes.active_color = attr
    try:
        me.color_attributes.render_color_index = me.color_attributes.find(VCOL_ATTR)
    except Exception:
        pass
    return attr


def _slot(me, name):
    mat = get_material(name)  # name = a palette colour name
    for i, m in enumerate(me.materials):
        if m == mat:
            return i
    me.materials.append(mat)
    return len(me.materials) - 1


def assign(me, names):
    """Colour every polygon of `me` (one palette name per polygon, in polygon order): palette_vcol first
    (slot 0) when any face uses it, then the exception materials in order of first use."""
    me = _mesh(me)
    if len(names) != len(me.polygons):
        raise ValueError("assign: %d names for %d polygons" % (len(names), len(me.polygons)))
    me.materials.clear()
    order = []
    if any(not is_exception(n) for n in names):
        order.append(VCOL_MATERIAL)
    for n in names:
        mn = material_name(n)
        if mn not in order:
            order.append(mn)
    for mn in order:
        me.materials.append(_material_by_name(mn))
    me.polygons.foreach_set("material_index", [order.index(material_name(n)) for n in names])
    attr = ensure_attribute(me)
    data = [1.0] * (len(me.loops) * 4)
    for poly, n in zip(me.polygons, names):
        c = WHITE if is_exception(n) else vcol_rgba(n)
        for li in poly.loop_indices:
            data[li * 4:li * 4 + 4] = c
    attr.data.foreach_set("color", data)
    me.update()


def paint(target, faces, name):
    """Write palette colour `name` into the corners of polygons `faces` (and give them the right material)."""
    me = _mesh(target)
    attr = ensure_attribute(me)
    if not me.materials:
        me.materials.append(get_vcol_material())
    idx = _slot(me, name)
    c = WHITE if is_exception(name) else vcol_rgba(name)
    for fi in faces:
        poly = me.polygons[fi]
        poly.material_index = idx
        for li in poly.loop_indices:
            attr.data[li].color = c
    me.update()
