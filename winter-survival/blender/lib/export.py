"""Save .blend + export .glb (ASSET_SPEC_V2 §2.8), scene sanity checks, re-import helper and
`write_import` (Godot .import templates, §1/§2.9).

Deviation from the literal §2.8 call (reported): `export_image_format='AUTO'` instead of 'NONE'. The
Blender 5.0.1 exporter only follows the Base Color link to the `Col` attribute when the image format is not
'NONE' (io_scene_gltf2/blender/exp/material/pbr_metallic_roughness.py); with 'NONE' no COLOR_0 is written.
No asset contains images, so nothing else changes.

v2.1 (milestone G1, docs/research/05_graficos_arte.md §4.6): COLOR_0 is exported by NAME from the `Col` attribute
(`export_vertex_color='NAME'`: with 'MATERIAL' the exporter drops the alpha) and is RGBA: RGB = palette colour
(linear + GODOT_BIAS, unchanged), A = baked ambient occlusion. `save_and_export` bakes the AO (lib/hd.py) for every
visual mesh that has none yet. Smooth shading and custom normals are allowed (normals are exported per corner).
"""
import math
import re
from pathlib import Path

import bpy

from . import lowpoly
from . import palette

ROOT = Path(__file__).resolve().parents[2]          # winter-survival/
BLENDER_DIR = ROOT / "blender"
SOURCES_DIR = BLENDER_DIR / "sources"
MODELS_DIR = ROOT / "assets" / "models"
# Identity BoneMap for the humanoid retarget (ASSET_SPEC_V2 §2.9). M1 deviation: it lives under assets/models/rig/
# (the art agent's folder) instead of assets/rig/; every char/anim .import template points here.
BONEMAP_PATH = MODELS_DIR / "rig" / "humanoid_bonemap.tres"
BONEMAP_RES = "res://assets/models/rig/humanoid_bonemap.tres"


def export_kwargs(has_armature=False, has_actions=False):
    """ASSET_SPEC_V2 §2.8 exporter options."""
    return dict(
        export_format='GLB', export_yup=True,
        export_apply=(not has_armature),                       # with an Armature: do NOT apply modifiers
        export_animations=has_actions, export_animation_mode='ACTIONS',
        export_force_sampling=True, export_frame_step=1, export_optimize_animation_size=True,
        export_anim_single_armature=True, export_reset_pose_bones=True, export_rest_position_armature=True,
        export_def_bones=False,                                  # keeps the non-deforming socket bones
        export_leaf_bone=False, export_skins=has_armature, export_morph=False,
        export_vertex_color='NAME', export_vertex_color_name=palette.VCOL_ATTR,   # COLOR_0 = RGBA (A = AO)
        export_all_vertex_colors=False,                                            # a single COLOR_0
        export_materials='EXPORT',
        export_image_format='AUTO',                              # see module docstring ('NONE' drops COLOR_0)
        export_texcoords=False, export_normals=True,
        export_cameras=False, export_lights=False, export_extras=True,
        use_selection=False, use_visible=False, use_active_collection=False)


# Empties allowed to carry a rotation, as final (FRONT = -Y) Blender XYZ Euler degrees. ToolSocket is the
# slice's (-90, 0, 0) turned 180 degrees about Z with the player: its local +Z still points forward (-Y).
ROTATED_SOCKETS = {"ToolSocket": (-90.0, 0.0, 180.0)}

NAME_RE = re.compile(r"^[A-Za-z0-9_]+(-convcolonly|-colonly)?$")


def ensure_gltf():
    if not hasattr(bpy.ops.export_scene, "gltf") or not hasattr(bpy.ops.import_scene, "gltf"):
        import addon_utils
        addon_utils.enable("io_scene_gltf2", default_set=True)


def is_col(name):
    return name.startswith("Col") and (name.endswith("-convcolonly") or name.endswith("-colonly"))


def allowed_materials():
    return {palette.VCOL_MATERIAL} | set(palette.EXCEPTIONS) | set(palette.OPTIONAL_EXCEPTIONS)


def sanity_check_scene(name):
    problems = []
    from mathutils import Euler
    for o in bpy.data.objects:
        if o.name not in bpy.context.scene.objects:
            problems.append("orphan object %s" % o.name)
        if o.type not in ('MESH', 'EMPTY', 'ARMATURE'):
            problems.append("stray %s object %s" % (o.type, o.name))
        if not NAME_RE.match(o.name):
            problems.append("bad name %r" % o.name)
        if ("-" in o.name) and (o.parent is not None or not is_col(o.name)):
            problems.append("collision object %s must be top-level Col*" % o.name)
        if o.type != 'ARMATURE':
            expected = ROTATED_SOCKETS.get(o.name, (0.0, 0.0, 0.0))
            want = Euler(tuple(math.radians(a) for a in expected), 'XYZ').to_matrix()
            got = o.matrix_basis.to_3x3().normalized()
            if any(abs(got[i][j] - want[i][j]) > 1e-4 for i in range(3) for j in range(3)):
                problems.append("rotation on %s" % o.name)
            if any(abs(s - 1.0) > 1e-6 for s in o.scale):
                problems.append("scale on %s" % o.name)
        if o.type == 'MESH':
            me = o.data
            if len(me.uv_layers):
                problems.append("uv data on %s" % o.name)
            if is_col(o.name):
                if len(me.materials) or len(me.color_attributes):
                    problems.append("collision %s must have no material/colours" % o.name)
                continue
            if len(me.materials) == 0:
                problems.append("no material on %s" % o.name)
            bad = [m.name for m in me.materials if m is None or m.name not in allowed_materials()]
            if bad:
                problems.append("materials %s on %s not allowed" % (bad, o.name))
            if len(me.materials) > 2:
                problems.append("%d materials on %s (max 2)" % (len(me.materials), o.name))
            names = [a.name for a in me.color_attributes]
            if names != [palette.VCOL_ATTR]:
                problems.append("colour attributes %s on %s (want ['Col'])" % (names, o.name))
            elif me.color_attributes[0].domain != 'CORNER':
                problems.append("Col on %s is not per corner" % o.name)
    if len(bpy.data.images):
        problems.append("image datablocks present")
    if problems:
        raise RuntimeError("%s: scene check failed:\n  " % name + "\n  ".join(problems))


def _purge_orphans():
    for _ in range(3):
        try:
            bpy.data.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)
        except Exception:
            break


def export_gltf(glb_path, has_armature=None, has_actions=None):
    ensure_gltf()
    if has_armature is None:
        has_armature = any(o.type == 'ARMATURE' for o in bpy.context.scene.objects)
    if has_actions is None:
        has_actions = len(bpy.data.actions) > 0
    kw = dict(export_kwargs(has_armature, has_actions), filepath=str(glb_path))
    while True:
        try:
            bpy.ops.export_scene.gltf(**kw)
            return
        except TypeError as ex:
            m = re.search(r'keyword "(\w+)"', str(ex))
            if m and m.group(1) in kw and m.group(1) != "filepath":
                print("export: dropping unsupported keyword %s" % m.group(1))
                kw.pop(m.group(1))
            else:
                raise


def save_and_export(name, subdir="", ao=True):
    """Sanity-check the scene, bake AO (v2.1), save sources/<name>.blend, export assets/models/[subdir/]<name>.glb.

    ao: True = hd.bake_scene_ao() with the automatic settings for every visual mesh without AO; a dict = the same
    with explicit settings (distance, samples, ground, walls); False = no bake (armature-only animation files).

    The .glb export is byte-deterministic but a .blend save is not (timestamps): when the freshly exported
    .glb equals the existing one and the .blend exists, both files are left untouched (no churn in the repo
    when nothing changed)."""
    import filecmp
    import shutil
    import tempfile
    sanity_check_scene(name)
    if ao:
        from . import hd
        hd.bake_scene_ao(**(ao if isinstance(ao, dict) else {}))
    _purge_orphans()
    SOURCES_DIR.mkdir(parents=True, exist_ok=True)
    out_dir = MODELS_DIR / subdir if subdir else MODELS_DIR
    out_dir.mkdir(parents=True, exist_ok=True)
    blend = SOURCES_DIR / ("%s.blend" % name)
    glb = out_dir / ("%s.glb" % name)
    try:
        bpy.context.preferences.filepaths.save_version = 0   # no .blend1 backups
    except Exception:
        pass
    tmp_dir = tempfile.mkdtemp(prefix="ventisca_export_")
    tmp_glb = Path(tmp_dir) / glb.name
    with quiet():
        export_gltf(tmp_glb)
    unchanged = glb.exists() and blend.exists() and filecmp.cmp(str(tmp_glb), str(glb), shallow=False)
    if not unchanged:
        with quiet():
            bpy.ops.wm.save_as_mainfile(filepath=str(blend), compress=True, check_existing=False)
        shutil.copyfile(str(tmp_glb), str(glb))
    shutil.rmtree(tmp_dir, ignore_errors=True)
    for stale in SOURCES_DIR.glob("*.blend1"):
        stale.unlink()
    tris = lowpoly.scene_tris()
    surfaces = sum(len(o.data.materials) for o in bpy.context.scene.objects
                   if o.type == 'MESH' and not is_col(o.name))
    print("built %-16s tris=%-6d surfaces=%-3d -> %s%s" % (name, tris, surfaces, glb.relative_to(ROOT),
                                                           " (unchanged)" if unchanged else ""))
    return glb


# ------------------------------------------------------------------------------------------------
# Godot .import templates (ASSET_SPEC_V2 §2.9). Only for NEW asset families: the 33 slice models keep the
# .import files Godot already generated. Godot fills in uid / dest_files on the next --import.
#   char : importer "scene", no animations, humanoid retarget -> Skeleton3D renamed GeneralSkeleton
#   anim : importer "animation_library" (30 fps, rest pose as RESET), same retarget so the tracks target
#          %GeneralSkeleton:<Bone>; `-loop` names -> LOOP_LINEAR (Godot strips the suffix)
# `except_bone_transform` stays OFF: Godot bug #123782 (with it on, retargeted libraries keep 1 track).
# anim also turns OFF the AnimationPlayer key optimizer (M1): Godot's default lossy key reduction (91 -> 45 keys
# on Loco_Idle) made planted feet drift up to 0.8 mm per frame; with it off Godot plays the exact keys.
# ------------------------------------------------------------------------------------------------
_SCENE_PARAMS = [
    'nodes/root_type=""', 'nodes/root_name=""', 'nodes/apply_root_scale=true', 'nodes/root_scale=1.0',
    'nodes/import_as_skeleton_bones=false', 'nodes/use_name_suffixes=true', 'nodes/use_node_type_suffixes=true',
    'meshes/ensure_tangents=true', 'meshes/generate_lods=true', 'meshes/create_shadow_meshes=true',
    'meshes/light_baking=1', 'meshes/lightmap_texel_size=0.2', 'meshes/force_disable_compression=false',
    'skins/use_named_skins=true', 'import_script/path=""', 'materials/extract=0',
    'gltf/naming_version=2', 'gltf/embedded_image_handling=1',
]
_RETARGET = '''_subresources={
"nodes": {
"PATH:Armature/Skeleton3D": {
"retarget/bone_map": Resource("%s"),
"retarget/bone_renamer/rename_bones": true,
"retarget/bone_renamer/unique_node/make_unique": true,
"retarget/bone_renamer/unique_node/skeleton_name": "GeneralSkeleton",
"retarget/remove_tracks/except_bone_transform": false,
"retarget/remove_tracks/unimportant_positions": true,
"retarget/remove_tracks/unmapped_bones": 0,
"retarget/rest_fixer/apply_node_transforms": true,
"retarget/rest_fixer/fix_silhouette/enable": false,
"retarget/rest_fixer/normalize_position_tracks": true,
"retarget/rest_fixer/reset_all_bone_poses_after_import": true,
"retarget/rest_fixer/retarget_method": 1
}
}
}''' % BONEMAP_RES
_ANIM_PLAYER = '''"PATH:AnimationPlayer": {
"optimizer/enabled": false
},
'''
IMPORT_KINDS = ("prop", "char", "anim")


def import_file_text(kind):
    if kind not in IMPORT_KINDS:
        raise ValueError("kind must be one of %s" % (IMPORT_KINDS,))
    if kind == "anim":
        head = '[remap]\n\nimporter="animation_library"\nimporter_version=1\ntype="AnimationLibrary"\n'
        params = _SCENE_PARAMS + ['animation/import=true', 'animation/fps=30', 'animation/trimming=false',
                                  'animation/remove_immutable_tracks=true', 'animation/import_rest_as_RESET=true',
                                  _RETARGET.replace('"nodes": {\n', '"nodes": {\n' + _ANIM_PLAYER, 1)]
    else:
        head = '[remap]\n\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\n'
        params = list(_SCENE_PARAMS)
        if kind == "char":
            params += ['animation/import=false', _RETARGET]
        else:
            params += ['animation/import=false', '_subresources={}']
    return head + "\n[params]\n\n" + "\n".join(params) + "\n"


def write_import(glb_path, kind, overwrite=False):
    """Write <glb>.import from a template (kind: prop | char | anim). Never touches an existing file unless
    overwrite=True. Returns the path, or None when it already existed."""
    path = Path(str(glb_path) + ".import")
    if path.exists() and not overwrite:
        return None
    path.write_text(import_file_text(kind))
    return path


# ------------------------------------------------------------------------------------------------
class _Quiet:
    """Silence C-level and Python stdout (the glTF add-on is chatty)."""

    def __enter__(self):
        import os
        import sys
        sys.stdout.flush()
        self._fd = os.dup(1)
        self._null = os.open(os.devnull, os.O_WRONLY)
        os.dup2(self._null, 1)
        return self

    def __exit__(self, *exc):
        import os
        import sys
        sys.stdout.flush()
        os.dup2(self._fd, 1)
        os.close(self._fd)
        os.close(self._null)
        return False


def quiet():
    return _Quiet()


def reimport(glb_path):
    ensure_gltf()
    with quiet():
        bpy.ops.wm.read_factory_settings(use_empty=True)
        ensure_gltf()
        bpy.ops.import_scene.gltf(filepath=str(glb_path))
