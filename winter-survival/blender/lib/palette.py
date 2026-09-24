"""Palette (ASSET_SPEC §3): material name -> sRGB hex, and the only way scripts create materials."""
import bpy

PALETTE = {
    "snow": "#F1F5FA",
    "snow_shadow": "#B9CBE3",
    "ice": "#BFE3F0",
    "pine_dark": "#2F5D3A",
    "pine_light": "#4B8A55",
    "bark": "#5B3F2E",
    "wood": "#8B6543",
    "wood_light": "#C7A16B",
    "wood_dark": "#4A3426",
    "stone": "#7C8592",
    "stone_dark": "#5A616B",
    "brick": "#8E5A4A",
    "skin": "#F1C9A5",
    "wolf_fur": "#6E7378",
    "eyes": "#F5D142",
    "deer_fur": "#8A6A48",
    "cloth": "#C9B79C",
    "can_red": "#C23B3B",
    "iron": "#2B2E33",
    "cabin_wall": "#5D7FA6",
    "cabin_trim": "#DDE6F0",
    "roof": "#33383F",
    "window": "#9CC4DD",
    "truck_paint": "#5B6B3F",
    "bush": "#3E6B45",
    "berry": "#D9403D",
    "ember": "#E63B12",
    "jacket": "#B03A2E",
    "hat": "#2E4A7A",
    "scarf": "#E8B04B",
    "boots": "#2A2320",
    "wolf_belly": "#A9AEB2",
    "eyes_dark": "#1E1E24",
    "deer_belly": "#C9B79C",
    "paper": "#EDE6D6",
    "can_blue": "#3B6BC2",
}


def srgb_to_linear(c):
    """Exact sRGB transfer function (0..1 in, 0..1 out)."""
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_to_linear_rgba(hex_str):
    h = hex_str.lstrip("#")
    return tuple(srgb_to_linear(int(h[i:i + 2], 16) / 255.0) for i in (0, 2, 4)) + (1.0,)


def get_material(name):
    """Return the palette material `name`, creating it once per file (flat color, rough, no emission)."""
    if name not in PALETTE:
        raise KeyError("material %r is not in the palette (ASSET_SPEC §3)" % name)
    mat = bpy.data.materials.get(name)
    if mat is not None:
        return mat
    rgba = hex_to_linear_rgba(PALETTE[name])
    mat = bpy.data.materials.new(name)
    if mat.name != name:
        raise RuntimeError("material name collision: %s -> %s" % (name, mat.name))
    try:
        mat.use_nodes = True  # deprecated in 5.x (always true) but harmless
    except Exception:
        pass
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
    return mat
