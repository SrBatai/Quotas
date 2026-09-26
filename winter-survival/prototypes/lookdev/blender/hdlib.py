"""hdlib - shared helpers for the VENTISCA HD look-dev PoC (art guidelines v2.1, docs/research/05_graficos_arte.md).

Builds on the game's pipeline (winter-survival/blender/lib: palette, lowpoly.MeshBuilder, rig, export) WITHOUT
modifying it: every change below is a proposal that lives only in this prototype.

What v2.1 adds on top of ASSET_SPEC_V2 (see the doc, section 4):
  * palette v2.1 (desaturated blue-greys, muted greens, warm wood; new names for clothing / packed snow),
    registered at runtime by use_palette_v21();
  * shading per part instead of "everything flat": `hard` parts get a small chamfer (bevel, 1-2 segments,
    harden normals -> flat faces with a soft 1-2 px highlight edge), `soft` parts (all snow, fabric, bark tubes)
    are smooth shaded (optionally Catmull-Clark subdivided cages = "pillows" with thick rounded rims);
    normals are frozen as custom normals before joining parts so mixed flat/smooth parts survive the join;
  * baked ambient occlusion in COLOR_0.a (1 = open, 0 = fully occluded). RGB stays the exact palette colour
    (linear + GODOT_BIAS), so the palette checks of verify_assets.py still hold on RGB. Exported with
    export_vertex_color='NAME' (COLOR_0 becomes VEC4); the shader uses it as AO (see the doc / manifest).
  * no UVs (unchanged): snow sparkle / tint noise is world-space in the shader.
"""
import json
import math
import os
import random
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
WS = os.path.abspath(os.path.join(HERE, "..", "..", ".."))          # winter-survival/
if os.path.join(WS, "blender") not in sys.path:
    sys.path.insert(0, os.path.join(WS, "blender"))

import bpy  # noqa: E402  (must precede bmesh / mathutils)
import bmesh  # noqa: E402,F401
from mathutils import Matrix, Vector, noise  # noqa: E402

from lib import export, palette  # noqa: E402,F401
from lib import lowpoly as lp  # noqa: E402

OUT_DIR = os.path.join(WS, "prototypes", "lookdev", "godot", "assets", "hd")
SRC_DIR = os.path.join(HERE, "sources")
SCRATCH = os.environ.get(
    "LOOKDEV_OUT", "/tmp/claude-0/-home-user-Quotas/3c3b507e-0838-5643-8cd6-6e5a40202a08/scratchpad/lookdev_art")
OLD_MODELS = os.path.join(WS, "assets", "models")

# ------------------------------------------------------------------------------------------------------------
# palette v2.1 (sRGB hex). CHANGED = existing names re-tuned; NEW = additions. Kept small on purpose.
# ------------------------------------------------------------------------------------------------------------
PALETTE_CHANGED = {
    "snow": "#CDDEF5", "snow_shadow": "#AFC3E0",   # = terrain snow albedo of docs/research/06 (snow_terrain.gdshader)
    "pine_dark": "#1F342E", "pine_light": "#2F4A3D",
    "bark": "#4A3D35", "wood": "#7A5F4B", "wood_light": "#A88E70", "wood_dark": "#4A3B31",
    "stone": "#7B8089", "stone_dark": "#565B63", "brick": "#735F5D",
    "cabin_wall": "#6C829C", "cabin_trim": "#D3CFC6", "roof": "#48434A", "iron": "#2A2B2E",
    "truck_paint": "#5E6650",
}
PALETTE_NEW = {
    "snow_packed": "#BFD0E8",        # trodden path / tyre tracks (blended per vertex on terrain)
    "snow_hole": "#93AACB",          # floor of footprints (reads as a shadowed hole)
    "snow_deep": "#D6E4F7",          # drift crests / fresh powder on top of old snow
    "roof_seam": "#2C2A2E",          # battens / ridge cap
    "bark_grey": "#4E4843",          # bare (dead) trees
    "pine_mid": "#27402F",           # pine tier tops that peek between snow caps
    "parka_brown": "#4F4135", "parka_olive": "#4C5040", "parka_navy": "#3A4457", "parka_rust": "#7A4536",
    "pants_dark": "#35383D", "beanie": "#2E3035", "fur": "#CEC8BD", "pack": "#5D4C3C", "pack_dark": "#3D352D",
    "boots_brown": "#5B412F", "sock": "#D9D4CB", "skin_hd": "#C29478", "glove": "#2F2B28", "mat_roll": "#6D7558",
    "strap": "#2B2826", "beard": "#4A3A30",
}


def use_palette_v21():
    palette.PALETTE.update(PALETTE_CHANGED)
    palette.PALETTE.update(PALETTE_NEW)


# ------------------------------------------------------------------------------------------------------------
# scene / objects
# ------------------------------------------------------------------------------------------------------------
_TMP = {"n": 0}


def new_scene(authored_front="-Y"):
    sc = lp.new_scene(authored_front)
    use_palette_v21()
    _TMP["n"] = 0
    return sc


def tmp_name(prefix="tmp"):
    _TMP["n"] += 1
    return "%s_%04d" % (prefix, _TMP["n"])


def mk(mb, name=None, pivot=(0, 0, 0), parent=None):
    """MeshBuilder -> object (palette colours in `Col`), origin at `pivot` (authoring convention)."""
    return lp.to_object(mb, name or tmp_name(), pivot, parent)


def _swap_evaluated(obj):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg)
    nm = bpy.data.meshes.new_from_object(ev, preserve_all_data_layers=True, depsgraph=dg)
    old = obj.data
    obj.modifiers.clear()
    obj.data = nm
    if old.users == 0:
        bpy.data.meshes.remove(old)
    nm.name = obj.name
    return obj


def apply_mods(obj):
    return _swap_evaluated(obj)


def subsurf(obj, levels=2):
    m = obj.modifiers.new("subsurf", 'SUBSURF')
    m.levels = levels
    m.render_levels = levels
    m.uv_smooth = 'NONE'
    try:
        m.boundary_smooth = 'ALL'
    except Exception:
        pass
    _swap_evaluated(obj)
    return obj


def bevel(obj, width=0.02, segments=1, angle=30.0, harden=True, clamp=True):
    """Chamfer every edge sharper than `angle` (hard-surface rule v2.1). harden=True keeps the big faces flat
    (custom normals) so the chamfer reads as a thin soft highlight."""
    obj.data.shade_smooth()
    m = obj.modifiers.new("bevel", 'BEVEL')
    m.width = width
    m.segments = segments
    m.limit_method = 'ANGLE'
    m.angle_limit = math.radians(angle)
    m.use_clamp_overlap = clamp
    m.harden_normals = harden
    m.miter_outer = 'MITER_ARC' if segments > 1 else 'MITER_SHARP'
    _swap_evaluated(obj)
    if not harden:
        flat(obj)
    return obj


def smooth(obj, angle=None):
    """Smooth shading; with `angle` (deg) edges sharper than it stay hard (sharp_edge attribute)."""
    me = obj.data
    me.shade_smooth()
    if angle is not None:
        me.set_sharp_from_angle(angle=math.radians(angle))
    return obj


def flat(obj):
    obj.data.shade_flat()
    return obj


def freeze_normals(obj):
    """Store the current corner normals as custom normals (so a later join keeps flat + smooth + hardened
    parts exactly as authored)."""
    me = obj.data
    nors = [tuple(n.vector) for n in me.corner_normals]
    me.normals_split_custom_set(nors)
    return obj


def join(objs, name, parent=None):
    """Join objects (all built with the same pivot) into one object called `name`."""
    objs = [o for o in objs if o is not None]
    for o in objs:
        freeze_normals(o)
    target = objs[0]
    if len(objs) > 1:
        with bpy.context.temp_override(active_object=target, object=target, selected_objects=objs,
                                       selected_editable_objects=objs):
            bpy.ops.object.join()
    old = bpy.data.objects.get(name)
    if old is not None and old != target:
        raise RuntimeError("join: %s already exists" % name)
    oldname = target.name
    target.name = name
    target.data.name = name
    lp._PIVOTS[name] = lp._PIVOTS.get(oldname, Vector((0, 0, 0))).copy()
    if parent is not None:
        mw = target.matrix_world.copy()
        target.parent = parent
        target.matrix_parent_inverse = Matrix.Identity(4)
        target.matrix_world = mw
    _dedupe_materials(target)
    return target


def _dedupe_materials(obj):
    me = obj.data
    names = [m.name if m else None for m in me.materials]
    if len(set(names)) == len(names):
        return
    first = {}
    remap = []
    for i, n in enumerate(names):
        first.setdefault(n, i)
        remap.append(first[n])
    idx = [0] * len(me.polygons)
    me.polygons.foreach_get("material_index", idx)
    uniq = sorted(set(first.values()))
    newpos = {old: k for k, old in enumerate(uniq)}
    me.polygons.foreach_set("material_index", [newpos[remap[i]] for i in idx])
    mats = [me.materials[i] for i in uniq]
    me.materials.clear()
    for m in mats:
        me.materials.append(m)


def snap_colors(obj, allowed=None):
    """After bevel/subdivision (which interpolate corner colours), give every face ONE exact palette colour
    (nearest to its average), alpha untouched. Exception-material faces are left white."""
    me = obj.data
    col = me.color_attributes.get(palette.VCOL_ATTR)
    names = allowed or [n for n in palette.PALETTE]
    targets = [(n, palette.vcol_rgba(n)) for n in names]
    vmat = [m.name == palette.VCOL_MATERIAL if m else False for m in me.materials]
    data = [0.0] * (len(me.loops) * 4)
    col.data.foreach_get("color", data)
    for poly in me.polygons:
        if not vmat[poly.material_index]:
            continue
        li = list(poly.loop_indices)
        avg = [sum(data[i * 4 + k] for i in li) / len(li) for k in range(3)]
        best = min(targets, key=lambda t: sum((t[1][k] - avg[k]) ** 2 for k in range(3)))[1]
        for i in li:
            data[i * 4:i * 4 + 3] = best[:3]
    col.data.foreach_set("color", data)
    me.update()


def remove(obj):
    bpy.data.objects.remove(obj, do_unlink=True)


# ------------------------------------------------------------------------------------------------------------
# geometry helpers
# ------------------------------------------------------------------------------------------------------------
def grid_quads(mb, rows, mat, facing, snow=False):
    """rows = list of lists of points (a structured grid). Adds shared-vertex quads oriented toward `facing`
    (a vector or a function(center) -> vector). Returns the index grid."""
    idx = [[mb._v(p) for p in r] for r in rows]
    for i in range(len(rows) - 1):
        for j in range(len(rows[0]) - 1):
            q = (idx[i][j], idx[i][j + 1], idx[i + 1][j + 1], idx[i + 1][j])
            f = facing
            if callable(facing):
                c = sum((mb.verts[k] for k in q), Vector()) / 4.0
                f = facing(c)
            m = mat(i, j) if callable(mat) else mat
            mb.add_face(q, m, snow, facing=f)
    return idx


def pillow_cage(mb, origin, U, V, N, us, vs, top_fn, bottom=-0.02, edge_in=None, mat="snow", jitter=0.0,
                rnd=None, lip=None):
    """Closed cage for a Catmull-Clark "pillow" (snow slab / lump / cushion) lying on the plane (origin, U, V)
    with normal N. us / vs = parameter positions along U / V (metres from origin); top_fn(u, v) = thickness of
    the top sheet at (u, v); bottom = offset of the bottom sheet along N. `lip(u, v)` -> extra (dU, dV, dN)
    offset of top AND bottom border vertices (cornice overhang). Subdivide the resulting object with
    subsurf(levels=2) + smooth() to get thick rounded rims."""
    rnd = rnd or random.Random(0)
    O, U, V, N = Vector(origin), Vector(U).normalized(), Vector(V).normalized(), Vector(N).normalized()
    nu, nv = len(us), len(vs)

    jit = [[(rnd.uniform(-jitter, jitter), rnd.uniform(-jitter, jitter)) if jitter else (0.0, 0.0)
            for _u in us] for _v in vs]

    def P(i, j, h):
        u, v = us[j], vs[i]
        d = Vector(lip(u, v)) if lip is not None else Vector((0, 0, 0))
        ju, jv = jit[i][j]
        return O + U * (u + d.x + ju) + V * (v + d.y + jv) + N * (h + d.z)

    top = [[P(i, j, top_fn(us[j], vs[i])) for j in range(nu)] for i in range(nv)]
    bot = [[P(i, j, bottom) for j in range(nu)] for i in range(nv)]
    ti = [[mb._v(p) for p in r] for r in top]
    bi = [[mb._v(p) for p in r] for r in bot]
    for i in range(nv - 1):
        for j in range(nu - 1):
            mb.add_face((ti[i][j], ti[i][j + 1], ti[i + 1][j + 1], ti[i + 1][j]), mat, facing=N)
            mb.add_face((bi[i][j], bi[i][j + 1], bi[i + 1][j + 1], bi[i + 1][j]), mat, facing=-N)
    # side walls around the border
    ring = [(0, j) for j in range(nu)] + [(i, nu - 1) for i in range(1, nv)] + \
           [(nv - 1, j) for j in range(nu - 2, -1, -1)] + [(i, 0) for i in range(nv - 2, 0, -1)]
    c = sum((mb.verts[ti[i][j]] for i in range(nv) for j in range(nu)), Vector()) / (nu * nv)
    for k in range(len(ring)):
        a, b = ring[k], ring[(k + 1) % len(ring)]
        q = (ti[a[0]][a[1]], ti[b[0]][b[1]], bi[b[0]][b[1]], bi[a[0]][a[1]])
        mid = sum((mb.verts[x] for x in q), Vector()) / 4.0
        out = mid - c
        out = out - N * out.dot(N)
        mb.add_face(q, mat, facing=out)
    return ti, bi


def pillow(origin, U, V, N, size_u, size_v, thick, name=None, mat="snow", nu=6, nv=4, rim=0.18, jitter=0.0,
           seed=0, lip=None, levels=None, bumps=0.0, bottom=-0.03, drop_bottom=True, top_fn=None):
    """Rounded snow slab/lump object: cage (nu x nv, with support rows `rim` from the border) -> subsurf -> smooth."""
    rnd = random.Random(seed)
    su, sv = size_u, size_v

    def axis(n, size):
        r = min(rim, size * 0.3)
        inner = [r + (size - 2 * r) * k / max(1, n - 3) for k in range(max(0, n - 2))]
        return [0.0] + inner + [size]
    us, vs = axis(nu, su), axis(nv, sv)

    def top(u, v):
        edge = min(u, su - u, v, sv - v)
        base = thick if edge > 1e-6 else thick * 0.55
        if bumps:
            base += bumps * noise.noise(Vector((u * 0.9 + seed * 7.1, v * 0.9, 0.3)))
        return max(0.02, base)
    mb = lp.MeshBuilder()
    pillow_cage(mb, origin, U, V, N, us, vs, top_fn or top, bottom=bottom, mat=mat, jitter=jitter, rnd=rnd,
                lip=lip)
    o = mk(mb, name)
    if levels is None:                     # budget rule v2.1: level 2 only for big hero slabs
        levels = 2 if max(size_u, size_v) >= 1.5 else 1
    subsurf(o, levels)
    smooth(o)
    if drop_bottom:
        drop_faces(o, Vector(N), -0.6)
    return o


def drop_faces(obj, direction, below):
    """Delete faces whose normal . direction < below (hidden undersides of snow resting on a surface).
    `direction` is given in authoring coordinates (converted with the scene's front transform)."""
    d = (lp.front_xf().to_3x3() @ Vector(direction)).normalized()
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.normal_update()
    kill = [f for f in bm.faces if f.normal.dot(d) < below]
    bmesh.ops.delete(bm, geom=kill, context='FACES')
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    return len(kill)


def tube(mb, pts, radii, sides, mat, cap_end=True, cap_start=False, phase=0.0):
    """Tapered tube along a polyline (rings perpendicular to the local tangent)."""
    pts = [Vector(p) for p in pts]
    rings = []
    for i, p in enumerate(pts):
        if i == 0:
            t = pts[1] - pts[0]
        elif i == len(pts) - 1:
            t = pts[-1] - pts[-2]
        else:
            t = (pts[i + 1] - pts[i - 1])
        rings.append(lp.ring(p, t, radii[i], sides, phase))
    return mb.loft(rings, mat, cap_start=cap_start, cap_end=cap_end)


def fbm(x, y, octaves=3, seed=0.0):
    v, a, f = 0.0, 1.0, 1.0
    for _ in range(octaves):
        v += a * noise.noise(Vector((x * f + seed, y * f - seed, 0.37 * seed)))
        a *= 0.5
        f *= 2.03
    return v


def smoothstep(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


# ------------------------------------------------------------------------------------------------------------
# baked ambient occlusion -> COLOR_0.a
# ------------------------------------------------------------------------------------------------------------
def bake_ao(objs, distance=1.0, samples=64, ground=True, ground_z=0.0, gamma=1.0, floor=0.0):
    """Bake Cycles AO per corner into the alpha channel of `Col` for every object in `objs` (all other visible
    objects occlude). A temporary ground plane at z = ground_z darkens the bases. alpha = floor + (1-floor)*ao^gamma."""
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = samples
    if sc.world is None:
        sc.world = bpy.data.worlds.new("bake_world")
    sc.world.light_settings.distance = distance
    g = None
    if ground:
        me = bpy.data.meshes.new("bake_ground")
        s = 60.0
        me.from_pydata([(-s, -s, ground_z), (s, -s, ground_z), (s, s, ground_z), (-s, s, ground_z)], [],
                       [(0, 1, 2, 3)])
        g = bpy.data.objects.new("bake_ground", me)
        sc.collection.objects.link(g)
    t0 = time.time()
    for o in objs:
        me = o.data
        ao = me.color_attributes.new("AOtmp", 'FLOAT_COLOR', 'CORNER')
        me.color_attributes.active_color = ao
        for ob in sc.objects:
            ob.select_set(False)
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        with export.quiet():
            bpy.ops.object.bake(type='AO', target='VERTEX_COLORS')
        n = len(me.loops)
        a = [0.0] * (n * 4)
        ao.data.foreach_get("color", a)
        col = me.color_attributes[palette.VCOL_ATTR]
        c = [0.0] * (n * 4)
        col.data.foreach_get("color", c)
        for i in range(n):
            v = max(0.0, min(1.0, a[i * 4]))
            c[i * 4 + 3] = floor + (1.0 - floor) * (v ** gamma)
        col.data.foreach_set("color", c)
        me.color_attributes.remove(me.color_attributes["AOtmp"])
        me.color_attributes.active_color = me.color_attributes[palette.VCOL_ATTR]
        try:
            me.color_attributes.render_color_index = me.color_attributes.find(palette.VCOL_ATTR)
        except Exception:
            pass
    if g is not None:
        bpy.data.objects.remove(g, do_unlink=True)
        bpy.data.meshes.remove(bpy.data.meshes["bake_ground"])
    return time.time() - t0


# ------------------------------------------------------------------------------------------------------------
# checks / export
# ------------------------------------------------------------------------------------------------------------
def scene_stats():
    tris, surfaces = 0, 0
    per = {}
    for o in bpy.context.scene.objects:
        if o.type != 'MESH' or export.is_col(o.name):
            continue
        me = o.data
        me.calc_loop_triangles()
        t = len(me.loop_triangles)
        per[o.name] = t
        tris += t
        surfaces += len(me.materials)
    return tris, surfaces, per


def check_scene(name):
    """ASSET_SPEC_V2 contract minus the v2.1 changes (smooth faces, custom normals, alpha AO are allowed)."""
    problems = []
    for o in bpy.data.objects:
        if o.name not in bpy.context.scene.objects:
            problems.append("orphan %s" % o.name)
        if not export.NAME_RE.match(o.name):
            problems.append("bad name %r" % o.name)
        if o.type == 'MESH':
            me = o.data
            if len(me.uv_layers):
                problems.append("uv on %s" % o.name)
            if export.is_col(o.name):
                continue
            bad = [m.name for m in me.materials if m is None or m.name not in export.allowed_materials()]
            if bad:
                problems.append("materials %s on %s" % (bad, o.name))
            if [a.name for a in me.color_attributes] != [palette.VCOL_ATTR]:
                problems.append("colour attributes %s on %s" % ([a.name for a in me.color_attributes], o.name))
            if any(abs(s - 1) > 1e-6 for s in o.scale) or any(abs(r) > 1e-6 for r in o.rotation_euler):
                if o.parent is None or o.parent.type != 'ARMATURE':
                    problems.append("transform on %s" % o.name)
    if problems:
        raise RuntimeError("%s: %s" % (name, "; ".join(problems)))


def export_hd(name, subdir=""):
    """Save sources/<name>.blend (prototype-local) and export assets/hd/[subdir/]<name>.glb with COLOR_0 = RGBA
    (A = baked AO)."""
    check_scene(name)
    for _ in range(3):
        try:
            bpy.data.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)
        except Exception:
            break
    os.makedirs(SRC_DIR, exist_ok=True)
    out = os.path.join(OUT_DIR, subdir) if subdir else OUT_DIR
    os.makedirs(out, exist_ok=True)
    glb = os.path.join(out, name + ".glb")
    has_arm = any(o.type == 'ARMATURE' for o in bpy.context.scene.objects)
    kw = dict(export.export_kwargs(has_arm, False), filepath=glb,
              export_vertex_color='NAME', export_vertex_color_name=palette.VCOL_ATTR)
    export.ensure_gltf()
    try:
        bpy.context.preferences.filepaths.save_version = 0
    except Exception:
        pass
    with export.quiet():
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SRC_DIR, name + ".blend"), compress=True,
                                    check_existing=False)
        bpy.ops.export_scene.gltf(**kw)
    tris, surfaces, per = scene_stats()
    print("HD %-22s tris=%-6d surfaces=%-3d -> %s" % (name, tris, surfaces, os.path.relpath(glb, WS)))
    return glb, tris, surfaces, per


def write_manifest_entry(name, info):
    """assets/hd/hd_manifest.json: what each HD asset is, for the rendering agent (coordination through files)."""
    path = os.path.join(OUT_DIR, "hd_manifest.json")
    data = {}
    if os.path.exists(path):
        try:
            data = json.load(open(path))
        except Exception:
            data = {}
    data.setdefault("conventions", {
        "front": "-Y Blender = +Z Godot (MODEL_FRONT), metres, origin at footprint centre z=0",
        "COLOR_0": "RGBA. RGB = palette colour stored LINEAR (+0.5/255 bias, as the game). "
                   "A = baked ambient occlusion (1 = open sky, 0 = fully occluded).",
        "shader_hint": "world_vcol.gdshader: `AO = COLOR.a; AO_LIGHT_AFFECT = 0.35;` (or ALBEDO *= mix(1.0, COLOR.a, 0.6) "
                       "for a stylised darker crease look). StandardMaterial3D ignores the alpha (opaque).",
        "normals": "custom normals exported: snow/fabric/bark smooth, hard surfaces flat faces with a 1.5-3 cm "
                   "chamfer (hardened normals). Do NOT force flat normals in the shader (no dFdx/dFdy normal).",
        "materials": "palette_vcol (+ window on the glass objects)",
        "palette": "v2.1, see docs/research/05_graficos_arte.md section 4.1",
    })
    data.setdefault("assets", {})[name] = info
    with open(path, "w") as f:
        json.dump(data, f, indent=1, sort_keys=True)


def beam(mb, p0, p1, w, h=None, mat="wood", up=(0, 0, 1), snow=False):
    """Oriented box from p0 to p1 with cross-section w (sideways) x h (toward `up`)."""
    p0, p1 = Vector(p0), Vector(p1)
    a = (p1 - p0).normalized()
    upv = Vector(up)
    if abs(a.dot(upv.normalized())) > 0.97:
        upv = Vector((0, 1, 0)) if abs(a.y) < 0.9 else Vector((1, 0, 0))
    s = a.cross(upv).normalized()
    u = s.cross(a).normalized()
    h = w if h is None else h
    corners = []
    for i in range(8):
        base = p1 if i & 1 else p0
        corners.append(base + s * (w / 2 if i & 2 else -w / 2) + u * (h / 2 if i & 4 else -h / 2))
    return mb.hexa(corners, mat, snow=snow)


def snow_strip(p0, p1, width, thick, name=None, overhang=0.03, seed=0, nu=None, droop=0.0):
    """Rounded snow line on top of a rail / sill / beam from p0 to p1 (top surface points)."""
    p0, p1 = Vector(p0), Vector(p1)
    L = (p1 - p0).length
    U = (p1 - p0).normalized()
    N = Vector((0, 0, 1))
    V = N.cross(U).normalized()
    origin = p0 - U * overhang - V * (width / 2)
    n = nu or max(3, min(7, int(L / 0.6) + 3))
    lipf = None
    if droop:
        def lipf(u, v):
            e = min(v, width - v) / max(width, 1e-6)
            return (0.0, (-1 if v < width / 2 else 1) * droop * 0.6 * (1 - e * 2), -droop * (1 - e * 2))
    return pillow(origin, U, V, N, L + 2 * overhang, width, thick, name=name, nu=n, nv=3,
                  rim=min(0.06, width * 0.3), seed=seed, bottom=-0.01, lip=lipf, levels=1)


def mound(center, radius, height, name=None, seed=0, sides=12, rings=3, mat="snow", sink=0.05, stretch=(1.0, 1.0)):
    """Round smooth snow mound (trunk bases, piles): radial rings with a soft bell profile, smooth shaded,
    no bottom. Cheaper and rounder than a subdivided box cage."""
    rnd = random.Random(seed)
    c = Vector(center)
    mb = lp.MeshBuilder()
    jit = [rnd.uniform(0.85, 1.15) for _ in range(sides)]
    rows = []
    for k in range(rings + 1):
        t = k / rings                                   # 0 = rim, 1 = centre
        r = radius * (1.0 - t)
        z = height * (1 - (1 - t) ** 2) ** 0.8 - sink * (1 - t) ** 3
        if k == rings:
            rows.append([c + Vector((0, 0, height))])
            break
        rows.append([c + Vector((math.cos(2 * math.pi * i / sides) * r * jit[i] * stretch[0],
                                 math.sin(2 * math.pi * i / sides) * r * jit[i] * stretch[1], z)) for i in range(sides)])
    mb.loft(rows, mat, cap_start=False, cap_end=False, inside=c + Vector((0, 0, -1.0)))
    o = mk(mb, name)
    return smooth(o)
