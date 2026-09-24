"""Save .blend + export .glb (ASSET_SPEC §2.9), plus scene sanity checks and a re-import helper."""
import math
import re
from pathlib import Path

import bpy

from . import lowpoly

ROOT = Path(__file__).resolve().parents[2]          # winter-survival/
BLENDER_DIR = ROOT / "blender"
SOURCES_DIR = BLENDER_DIR / "sources"
MODELS_DIR = ROOT / "assets" / "models"

EXPORT_KW = dict(
    export_format='GLB', export_yup=True, export_apply=True,
    export_animations=False, export_skins=False, export_morph=False,
    export_materials='EXPORT', export_image_format='NONE',
    export_normals=True, export_texcoords=False,
    export_cameras=False, export_lights=False, export_extras=False,
    use_selection=False, use_visible=False, use_active_collection=False)

# Empties allowed to carry a rotation (ASSET_SPEC §2.3).
ROTATED_SOCKETS = {"ToolSocket": (-90.0, 0.0, 0.0), "TextTop": (0.0, 0.0, 180.0),
                   "TextBottom": (0.0, 0.0, 180.0)}

NAME_RE = re.compile(r"^[A-Za-z0-9]+(-convcolonly)?$")


def ensure_gltf():
    if not hasattr(bpy.ops.export_scene, "gltf") or not hasattr(bpy.ops.import_scene, "gltf"):
        import addon_utils
        addon_utils.enable("io_scene_gltf2", default_set=True)


def sanity_check_scene(name):
    problems = []
    for o in bpy.data.objects:
        if o.name not in bpy.context.scene.objects:
            problems.append("orphan object %s" % o.name)
        if o.type not in ('MESH', 'EMPTY'):
            problems.append("stray %s object %s" % (o.type, o.name))
        if not NAME_RE.match(o.name):
            problems.append("bad name %r" % o.name)
        if o.name.endswith("-convcolonly") and (o.parent is not None or not o.name.startswith("Col")):
            problems.append("collision object %s must be top-level Col*" % o.name)
        expected = ROTATED_SOCKETS.get(o.name, (0.0, 0.0, 0.0))
        if any(abs(math.degrees(a) - e) > 1e-4 for a, e in zip(o.rotation_euler, expected)):
            problems.append("rotation on %s" % o.name)
        if any(abs(s - 1.0) > 1e-6 for s in o.scale):
            problems.append("scale on %s" % o.name)
        if o.type == 'MESH':
            me = o.data
            if any(p.use_smooth for p in me.polygons):
                problems.append("smooth faces on %s" % o.name)
            if len(me.uv_layers) or len(me.color_attributes):
                problems.append("uv/colour data on %s" % o.name)
            if not o.name.endswith("-convcolonly") and len(me.materials) == 0:
                problems.append("no material on %s" % o.name)
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


def export_gltf(glb_path):
    ensure_gltf()
    kw = dict(EXPORT_KW, filepath=str(glb_path))
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


def save_and_export(name):
    """Sanity-check the scene, save sources/<name>.blend, export assets/models/<name>.glb."""
    sanity_check_scene(name)
    _purge_orphans()
    SOURCES_DIR.mkdir(parents=True, exist_ok=True)
    MODELS_DIR.mkdir(parents=True, exist_ok=True)
    blend = SOURCES_DIR / ("%s.blend" % name)
    glb = MODELS_DIR / ("%s.glb" % name)
    try:
        bpy.context.preferences.filepaths.save_version = 0   # no .blend1 backups
    except Exception:
        pass
    with quiet():
        bpy.ops.wm.save_as_mainfile(filepath=str(blend), compress=True, check_existing=False)
        export_gltf(glb)
    for stale in SOURCES_DIR.glob("*.blend1"):
        stale.unlink()
    tris = lowpoly.scene_tris()
    print("built %-14s tris=%-5d -> %s" % (name, tris, glb.relative_to(ROOT)))
    return glb


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
