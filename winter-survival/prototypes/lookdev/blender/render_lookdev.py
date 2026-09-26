"""Cycles previews for the HD look-dev PoC, from the GAME camera (pitch 48 deg, yaw 45 deg, vertical FOV 36 deg,
perspective, 20-27 m; scripts/data/balance.gd) plus close-ups.

    python3 render_lookdev.py <preset> [--samples N] [--res WxH]
    presets: cabin | trees | survivor | terrain | scene_day | scene_dusk | compare | all

Materials: every palette_vcol surface is shaded as  base = COLOR_0.rgb * mix(1, COLOR_0.a, AO_STRENGTH)  (the
v2.1 shader proposal; old assets have alpha 1 so they are unaffected). Window glass glows at dusk.
Output: $LOOKDEV_OUT (default: the session scratchpad lookdev_art/).
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import hdlib as H  # noqa: E402

HD = H.OUT_DIR
OLD = H.OLD_MODELS
OUT = H.SCRATCH
AO_STRENGTH = 0.75


def lin(h):
    h = h.lstrip('#')
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c) + (1.0,)


def reset():
    _MATS.clear()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    H.export.ensure_gltf()


_MATS = {}


def vcol_material(ao=True):
    key = "vcol_ao" if ao else "vcol"
    if key in _MATS:
        return _MATS[key]
    m = bpy.data.materials.new(key)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.88
    try:
        bsdf.inputs["Specular IOR Level"].default_value = 0.3
    except Exception:
        pass
    ca = nt.nodes.new("ShaderNodeVertexColor")
    ca.layer_name = ""
    if ao:
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = 'FLOAT'
        mix.inputs["Factor"].default_value = AO_STRENGTH
        mix.inputs["A"].default_value = 1.0
        nt.links.new(ca.outputs["Alpha"], mix.inputs["B"])
        mul = nt.nodes.new("ShaderNodeMix")
        mul.data_type = 'RGBA'
        mul.blend_type = 'MULTIPLY'
        mul.inputs["Factor"].default_value = 1.0
        nt.links.new(ca.outputs["Color"], mul.inputs["A"])
        nt.links.new(mix.outputs["Result"], mul.inputs["B"])
        nt.links.new(mul.outputs["Result"], bsdf.inputs["Base Color"])
    else:
        nt.links.new(ca.outputs["Color"], bsdf.inputs["Base Color"])
    _MATS[key] = m
    return m


def window_material(glow):
    key = "win_glow" if glow else "win"
    if key in _MATS:
        return _MATS[key]
    m = bpy.data.materials.new(key)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    if glow:
        b.inputs["Base Color"].default_value = lin("#FFC98A")
        b.inputs["Emission Color"].default_value = lin("#FFB870")
        b.inputs["Emission Strength"].default_value = 6.0
    else:
        b.inputs["Base Color"].default_value = lin("#5F7C96")
        b.inputs["Roughness"].default_value = 0.15
    _MATS[key] = m
    return m


def simple_material(name, hexc, rough=0.9):
    if name in _MATS:
        return _MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = lin(hexc)
    b.inputs["Roughness"].default_value = rough
    _MATS[name] = m
    return m


def load(path, pos=(0, 0, 0), yaw=0.0, glow=False, hide=(), ao=True, scale=1.0):
    """Import a .glb (Godot space -> Blender space is handled by the importer), wrap in a holder empty."""
    before = set(bpy.data.objects)
    with H.export.quiet():
        bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    holder = bpy.data.objects.new("holder", None)
    bpy.context.scene.collection.objects.link(holder)
    for o in new:
        if o.parent is None:
            o.parent = holder
        if o.name.startswith("Col") or o.name.split(".")[0] in hide:
            o.hide_render = True
        if o.type == 'MESH':
            for i, s in enumerate(o.material_slots):
                n = s.material.name if s.material else ""
                if n.startswith("window") or n.startswith("glass"):
                    s.material = window_material(glow)
                elif n.startswith("ember"):
                    s.material = simple_material("ember", "#E63B12")
                else:
                    s.material = vcol_material(ao)
    holder.location = pos
    holder.rotation_euler = (0, 0, math.radians(yaw))
    holder.scale = (scale, scale, scale)
    return holder, new


def ground(color="#CDDEF5", size=400, z=-0.002):
    bpy.ops.mesh.primitive_plane_add(size=size, location=(0, 0, z))
    g = bpy.context.active_object
    g.data.materials.append(simple_material("ground_" + color, color, 0.95))
    return g


def lights(mode="day"):
    sc = bpy.context.scene
    world = bpy.data.worlds.new("w")
    sc.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", 'SUN'))
    sc.collection.objects.link(sun)
    sun.data.angle = math.radians(1.5)
    if mode == "day":
        # reference (docs/research/06 §2): low backlight from the upper-right of the screen, shadows toward the
        # camera, strong pastel-blue sky fill
        bg.inputs[0].default_value = lin("#86A6D6")
        bg.inputs[1].default_value = 1.05
        sun.data.energy = 3.4
        sun.data.color = (1.0, 0.93, 0.84)
        sun.rotation_euler = (math.radians(64), 0, math.radians(172))
    elif mode == "dusk":
        bg.inputs[0].default_value = lin("#40557F")
        bg.inputs[1].default_value = 0.55
        sun.data.energy = 0.55
        sun.data.color = (0.75, 0.82, 1.0)
        sun.rotation_euler = (math.radians(66), 0, math.radians(172))
    return sun


def render_settings(samples=64, res=(1600, 900)):
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    sc.cycles.max_bounces = 4
    try:
        sc.view_settings.view_transform = 'AgX'
        sc.view_settings.look = 'AgX - Medium High Contrast'
    except Exception:
        sc.view_settings.view_transform = 'Standard'
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = False


def camera(target, dist=24.0, pitch=48.0, yaw=135.0, fov=36.0, ortho=None):
    """yaw 135 = the game's default view (Godot yaw 45 deg): camera toward +X -Y of the target (models face -Y)."""
    sc = bpy.context.scene
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    t = Vector(target)
    y, p = math.radians(yaw), math.radians(pitch)
    off = Vector((math.sin(y) * math.cos(p), math.cos(y) * math.cos(p), math.sin(p)))
    cam.location = t + off * dist
    cam.rotation_euler = (t - cam.location).to_track_quat('-Z', 'Y').to_euler()
    if ortho:
        cam.data.type = 'ORTHO'
        cam.data.ortho_scale = ortho
    else:
        cam.data.sensor_fit = 'VERTICAL'
        cam.data.angle = math.radians(fov)
    cam.data.clip_end = 2000
    sc.camera = cam
    return cam


def shoot(name):
    sc = bpy.context.scene
    os.makedirs(OUT, exist_ok=True)
    sc.render.filepath = os.path.join(OUT, name)
    with H.export.quiet():
        bpy.ops.render.render(write_still=True)
    print("rendered", sc.render.filepath)


def point_light(pos, color, energy, radius=0.2):
    lo = bpy.data.objects.new("pl", bpy.data.lights.new("pl", 'POINT'))
    bpy.context.scene.collection.objects.link(lo)
    lo.location = pos
    lo.data.color = color
    lo.data.energy = energy
    lo.data.shadow_soft_size = radius
    return lo


# --------------------------------------------------------------------------------------------------------
# presets
# --------------------------------------------------------------------------------------------------------
def p_cabin(samples, res):
    reset()
    lights("day")
    render_settings(samples, res)
    load(os.path.join(HD, "cabin_hd.glb"))
    if os.path.exists(os.path.join(HD, "terrain_tile_hd.glb")):
        load(os.path.join(HD, "terrain_tile_hd.glb"), pos=(0, 0, 0))
        ground(z=-0.6)
    else:
        ground()
    camera((0.3, -0.8, 1.6), dist=16, pitch=40, yaw=140)
    shoot("cabin_hd_closeup.png")
    camera((0.0, -0.5, 1.2), dist=24, pitch=48, yaw=135)
    shoot("cabin_hd_gamecam24.png")


def p_cabin_old(samples, res):
    reset()
    lights("day")
    render_settings(samples, res)
    load(os.path.join(OLD, "cabin.glb"), ao=False)
    ground()
    camera((0.3, -0.8, 1.6), dist=16, pitch=40, yaw=140)
    shoot("cabin_old_closeup.png")


def p_trees(samples, res):
    reset()
    lights("day")
    render_settings(samples, res)
    ground()
    # new (left half of the frame): pine_hd_a, pine_hd_b, bare_tree_hd ; old (right): pine_a, pine_b, dead_tree
    for f, pos in (("pine_hd_a", (-7.5, 3.0, 0)), ("pine_hd_b", (-4.5, -1.0, 0)), ("bare_tree_hd", (-2.0, 3.5, 0))):
        load(os.path.join(HD, f + ".glb"), pos=pos)
    for f, pos in (("pine_a", (3.0, 6.5, 0)), ("pine_b", (6.0, 2.5, 0)), ("dead_tree", (8.5, 7.0, 0))):
        load(os.path.join(OLD, f + ".glb"), pos=pos, ao=False)
    camera((0.5, 3.0, 2.5), dist=22, pitch=48, yaw=135)
    shoot("trees_new_left_old_right.png")
    camera((-4.5, 1.8, 3.0), dist=12, pitch=35, yaw=150)
    shoot("trees_hd_closeup.png")


def layout():
    import json
    with open(os.path.join(HD, "lookdev_layout.json")) as f:
        return json.load(f)["items"]


OLD_OF = {"pine_hd_a": "pine_a", "pine_hd_b": "pine_b", "bare_tree_hd": "dead_tree"}


def build_scene(new=True, mode="day", survivor=True, samples=64, res=(1600, 900)):
    """Same layout for old and new assets. new=False: game assets of today on the same heights sampled at 1 m and
    flat shaded (what terrain_chunk does), no AO."""
    reset()
    lights(mode)
    render_settings(samples, res)
    items = layout()
    glow = mode != "day"
    if new:
        load(os.path.join(HD, "terrain_tile_hd.glb"))
        load(os.path.join(HD, "cabin_hd.glb"), glow=glow)
    else:
        load(os.path.join(OUT, "terrain_flat_1m_ref.glb"), ao=False)
        load(os.path.join(OLD, "cabin.glb"), glow=glow, ao=False)
    ground(z=-1.2)
    for name, pts in items.items():
        if name == "survivor":
            continue
        for k, (x, y, z) in enumerate(pts):
            yaw = (k * 73) % 360
            if new:
                load(os.path.join(HD, name + ".glb"), pos=(x, y, z - 0.02), yaw=yaw)
            else:
                load(os.path.join(OLD, OLD_OF[name] + ".glb"), pos=(x, y, z), yaw=yaw, ao=False)
    if survivor:
        x, y, z = items["survivor"][0]
        f = os.path.join(HD, "chars", "survivor_hd_brown.glb") if new else os.path.join(OLD, "chars",
                                                                                          "survivor_red.glb")
        if os.path.exists(f):
            _, objs = load(f, pos=(x, y, z), yaw=35, ao=new)
            pose_idle([o for o in objs if o.type == 'ARMATURE'][0])
    if glow:
        # interior + porch lantern light (the game's InteriorLight / Lantern), cool moon fill
        point_light((0.0, 0.0, 1.8), (1.0, 0.62, 0.32), 900, 0.5)
        point_light((1.6, -4.3, 2.2), (1.0, 0.7, 0.4), 120, 0.1)


def pose_idle(arm, action="Loco_Idle", frame=10):
    """Pose an imported character with an action of the game's anims/humanoid_loco.glb (same skeleton)."""
    before = set(bpy.data.objects)
    acts_before = set(bpy.data.actions)
    with H.export.quiet():
        bpy.ops.import_scene.gltf(filepath=os.path.join(OLD, "anims", "humanoid_loco.glb"))
    for o in [o for o in bpy.data.objects if o not in before]:
        bpy.data.objects.remove(o, do_unlink=True)
    act = next(a for a in bpy.data.actions if a not in acts_before and a.name.startswith(action))
    ad = arm.animation_data or arm.animation_data_create()
    ad.action = act
    try:
        if ad.action_slot is None and act.slots:
            ad.action_slot = act.slots[0]
    except Exception:
        pass
    bpy.context.scene.frame_set(frame)


def p_scene_day(samples, res):
    build_scene(True, "day", samples=samples, res=res)
    camera((0.2, -6.0, 0.8), dist=24, pitch=48, yaw=135)
    shoot("scene_hd_day_gamecam24.png")
    camera((0.5, -5.0, 1.2), dist=16, pitch=48, yaw=135)
    shoot("scene_hd_day_gamecam16.png")


def p_scene_dusk(samples, res):
    build_scene(True, "dusk", samples=samples, res=res)
    camera((0.2, -6.0, 0.8), dist=24, pitch=48, yaw=135)
    shoot("scene_hd_dusk_gamecam24.png")


def p_scene_old(samples, res):
    build_scene(False, "day", samples=samples, res=res)
    camera((0.2, -6.0, 0.8), dist=24, pitch=48, yaw=135)
    shoot("scene_old_day_gamecam24.png")


def p_compare(samples, res):
    """old | new side by side (same camera, layout, light) -> compare_old_vs_new_gamecam24.png"""
    p_scene_old(samples, res)
    p_scene_day(samples, res)
    compose_compare()


def compose_compare():
    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError:
        return
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 30)
    except Exception:
        font = None
    a = Image.open(os.path.join(OUT, "scene_old_day_gamecam24.png")).convert("RGB")
    b = Image.open(os.path.join(OUT, "scene_hd_day_gamecam24.png")).convert("RGB")
    w, h = a.size
    im = Image.new("RGB", (w * 2 + 12, h), (20, 24, 30))
    im.paste(a, (0, 0))
    im.paste(b, (w + 12, 0))
    d = ImageDraw.Draw(im)
    for x, t in ((24, "ANTES: assets actuales, terreno 1 m facetado"),
                 (w + 36, "DESPUES: HD v2.1 (chaflan, nieve suave, AO)")):
        tw = d.textlength(t, font=font) if font else 8 * len(t)
        d.rectangle((x - 12, 16, x + tw + 12, 62), fill=(20, 24, 30))
        d.text((x, 22), t, fill=(235, 240, 245), font=font)
    im.save(os.path.join(OUT, "compare_old_vs_new_gamecam24.png"))
    print("rendered", os.path.join(OUT, "compare_old_vs_new_gamecam24.png"))


def p_terrain(samples, res):
    reset()
    lights("day")
    render_settings(samples, res)
    load(os.path.join(OUT, "terrain_flat_1m_ref.glb"), pos=(-22, 0, 0), ao=False)
    load(os.path.join(HD, "terrain_tile_hd.glb"), pos=(22, 0, 0))
    ground(z=-1.2)
    camera((-22, -9.0, 0.0), dist=20, pitch=48, yaw=135)
    shoot("terrain_flat1m_before.png")
    camera((22, -9.0, 0.0), dist=20, pitch=48, yaw=135)
    shoot("terrain_hd_after.png")
    camera((22 + 0.2, -8.5, 0.0), dist=7, pitch=50, yaw=135)
    shoot("terrain_hd_footprints_closeup.png")


PRESETS = {"cabin": p_cabin, "cabin_old": p_cabin_old, "trees": p_trees, "scene_day": p_scene_day,
           "scene_dusk": p_scene_dusk, "scene_old": p_scene_old, "compare": p_compare, "terrain": p_terrain}


def p_survivor(samples, res):
    reset()
    lights("day")
    render_settings(samples, res)
    ground()
    xs = [-2.4, -1.2, 0.0, 1.2]
    for x, v in zip(xs, ("brown", "olive", "navy", "rust")):
        load(os.path.join(HD, "chars", "survivor_hd_%s.glb" % v), pos=(x, 0, 0))
    load(os.path.join(OLD, "chars", "survivor_red.glb"), pos=(2.7, 0, 0), ao=False)
    camera((0.15, 0, 0.95), dist=7.5, pitch=10, yaw=180 + 0.0, fov=32)
    shoot("survivor_hd_variants_front_vs_old.png")
    camera((0.15, 0, 0.95), dist=7.5, pitch=14, yaw=-35, fov=32)
    shoot("survivor_hd_variants_back.png")
    camera((0.15, 0, 0.8), dist=22, pitch=48, yaw=135)
    shoot("survivor_hd_variants_gamecam22.png")


PRESETS["survivor"] = p_survivor


def main():
    args = sys.argv[1:]
    samples, res = 64, (1600, 900)
    if "--samples" in args:
        samples = int(args[args.index("--samples") + 1])
    if "--res" in args:
        w, h = args[args.index("--res") + 1].split("x")
        res = (int(w), int(h))
    names = [a for a in args if not a.startswith("--") and not a[0].isdigit() and "x" not in a[1:4]]
    if not names or names == ["all"]:
        names = list(PRESETS)
    for n in names:
        PRESETS[n](samples, res)


if __name__ == "__main__":
    main()
