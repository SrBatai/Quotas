"""HD construction helpers, art guidelines v2.1 (docs/research/05_graficos_arte.md §4, milestone G1).

Ported from the look-dev PoC (prototypes/lookdev/blender/hdlib.py) into the game pipeline. On top of
lowpoly.MeshBuilder (which still builds everything, flat shaded, one palette colour per face):

  * shading per part (§4.2): `bevel()` chamfers hard parts (1 segment, angle limit, hardened normals: flat faces
    + a thin highlight edge), `smooth()` / `flat()`, `subsurf()` for Catmull-Clark cages; `freeze_normals()` +
    `join()` merge flat, smooth and chamfered parts into ONE object (one surface) keeping each part's normals as
    exported custom normals; `snap_colors()` puts every face back on ONE exact palette colour after a bevel or a
    subdivision interpolated the corner colours (RGB stays = palette, the verifier checks it);
  * snow recipes (§4.3): `pillow()` (thick slab / lump with rounded rims and an optional drooping cornice),
    `snow_strip()` (rounded snow line on a rail / sill / beam top), `mound()` (smooth bell mound at trunk bases
    and piles), `snow_cap()` (pillow cap resting on the top faces of a rock / post / stump);
  * `bake_ao()`: Cycles ambient occlusion baked per corner into the ALPHA of the `Col` attribute
    (COLOR_0.a = AO, 1 = open, 0 = occluded). `export.save_and_export` calls `bake_scene_ao()` for every asset
    that has not baked its own AO, so the whole game carries the COLOR.a contract (docs/research/06 §3.7).

Every helper works in the authoring convention of the current scene (lowpoly.new_scene(authored_front=...)).
"""
import math
import random
import time

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

from . import lowpoly as lp
from . import palette

_TMP = {"n": 0}


# ------------------------------------------------------------------------------------------------------------
# objects
# ------------------------------------------------------------------------------------------------------------
def tmp_name(prefix="hdtmp"):
    _TMP["n"] += 1
    return "%s_%05d" % (prefix, _TMP["n"])


def mk(mb, name=None, pivot=(0, 0, 0), parent=None):
    """MeshBuilder -> object (palette colours in `Col`, flat shaded), origin at `pivot` (authoring convention)."""
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
    """Chamfer every edge sharper than `angle` (hard-surface rule v2.1: 1.2-2.5 cm on worked wood, trims, posts,
    beams, frames, furniture, metal; 3-5 cm on vehicle bodies). harden=True keeps the big faces flat (custom
    normals) so the chamfer reads as a thin highlight. Call snap_colors() afterwards."""
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
    """Store the current corner normals as custom normals (a later join keeps flat + smooth + chamfered parts)."""
    me = obj.data
    nors = [tuple(n.vector) for n in me.corner_normals]
    me.normals_split_custom_set(nors)
    return obj


def join(objs, name, parent=None):
    """Join objects built with the same pivot into one object called `name` (normals frozen first)."""
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
    if target.name != name:
        raise RuntimeError("join: name collision %s -> %s" % (name, target.name))
    lp._PIVOTS[name] = lp._PIVOTS.pop(oldname, Vector((0, 0, 0))).copy()
    if parent is not None:
        mw = target.matrix_world.copy()
        target.parent = parent
        target.matrix_parent_inverse = Matrix.Identity(4)
        target.matrix_world = mw
    _dedupe_materials(target)
    return target


def _dedupe_materials(obj):
    """Merge duplicated material slots (a join appends every part's list); palette_vcol first."""
    me = obj.data
    names = [m.name if m else None for m in me.materials]
    order = []
    if palette.VCOL_MATERIAL in names:
        order.append(palette.VCOL_MATERIAL)
    for n in names:
        if n not in order:
            order.append(n)
    if order == names:
        return
    idx = [0] * len(me.polygons)
    me.polygons.foreach_get("material_index", idx)
    mats = {m.name: m for m in me.materials if m}
    remap = [order.index(n) for n in names]
    me.polygons.foreach_set("material_index", [remap[i] for i in idx])
    me.materials.clear()
    for n in order:
        me.materials.append(mats[n])
    me.update()


def snap_colors(obj, allowed=None):
    """Give every palette_vcol face ONE exact palette colour (the nearest to its corner average) after a bevel
    or a subdivision interpolated the corners. Alpha untouched; exception-material faces stay white."""
    me = obj.data
    col = me.color_attributes.get(palette.VCOL_ATTR)
    names = allowed or list(palette.PALETTE)
    targets = [palette.vcol_rgba(n) for n in names]
    vmat = [bool(m and m.name == palette.VCOL_MATERIAL) for m in me.materials]
    data = [0.0] * (len(me.loops) * 4)
    col.data.foreach_get("color", data)
    cache = {}
    for poly in me.polygons:
        li = list(poly.loop_indices)
        if not vmat[poly.material_index]:
            for i in li:
                data[i * 4:i * 4 + 3] = (1.0, 1.0, 1.0)
            continue
        avg = tuple(round(sum(data[i * 4 + k] for i in li) / len(li), 6) for k in range(3))
        best = cache.get(avg)
        if best is None:
            best = min(targets, key=lambda t: sum((t[k] - avg[k]) ** 2 for k in range(3)))
            cache[avg] = best
        for i in li:
            data[i * 4:i * 4 + 3] = best[:3]
    col.data.foreach_set("color", data)
    me.update()


def remove(obj):
    bpy.data.objects.remove(obj, do_unlink=True)


def drop_faces(obj, direction, below):
    """Delete faces whose normal . direction < below (hidden undersides of snow resting on a surface).
    `direction` is in authoring coordinates (converted with the scene's front transform)."""
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


def tris(obj):
    me = obj.data
    me.calc_loop_triangles()
    return len(me.loop_triangles)


# ------------------------------------------------------------------------------------------------------------
# geometry helpers
# ------------------------------------------------------------------------------------------------------------
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


def tube(mb, pts, radii, sides, mat, cap_end=True, cap_start=False, phase=0.0):
    """Tapered tube along a polyline (rings perpendicular to the local tangent). radii may be (ru, rw) pairs."""
    pts = [Vector(p) for p in pts]
    rings = []
    for i, p in enumerate(pts):
        if i == 0:
            t = pts[1] - pts[0]
        elif i == len(pts) - 1:
            t = pts[-1] - pts[-2]
        else:
            t = pts[i + 1] - pts[i - 1]
        rings.append(lp.ring(p, t, radii[i], sides, phase))
    return mb.loft(rings, mat, cap_start=cap_start, cap_end=cap_end)


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


def pillow_cage(mb, origin, U, V, N, us, vs, top_fn, bottom=-0.02, mat="snow", jitter=0.0, rnd=None, lip=None):
    """Closed cage for a Catmull-Clark "pillow" on the plane (origin, U, V) with normal N. us / vs = parameter
    positions along U / V; top_fn(u, v) = top-sheet thickness; `bottom` = offset of the bottom sheet along N;
    lip(u, v) -> extra (dU, dV, dN) offset of the border (cornice overhang / droop)."""
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
    """Rounded snow slab / lump object: cage (nu x nv with support rows `rim` from the border) -> subsurf -> smooth.
    Budget rule v2.1: subdivision level 2 only when the long side is >= 1.5 m, else 1."""
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
    pillow_cage(mb, origin, U, V, N, us, vs, top_fn or top, bottom=bottom, mat=mat, jitter=jitter, rnd=rnd, lip=lip)
    o = mk(mb, name)
    if levels is None:
        levels = 2 if max(size_u, size_v) >= 1.5 else 1
    subsurf(o, levels)
    smooth(o)
    if drop_bottom:
        drop_faces(o, Vector(N), -0.6)
    return o


def snow_strip(p0, p1, width, thick, name=None, overhang=0.03, seed=0, nu=None, droop=0.0):
    """Rounded snow line on top of a rail / sill / beam from p0 to p1 (points on the top surface)."""
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
    """Round smooth snow mound (trunk bases, piles): radial rings with a bell profile, smooth, no bottom.
    `sink` pushes the rim below z (so the mound never floats on a slope)."""
    rnd = random.Random(seed)
    c = Vector(center)
    mb = lp.MeshBuilder()
    jit = [rnd.uniform(0.85, 1.15) for _ in range(sides)]
    rows = []
    for k in range(rings + 1):
        t = k / rings
        r = radius * (1.0 - t)
        z = height * (1 - (1 - t) ** 2) ** 0.8 - sink * (1 - t) ** 3
        if k == rings:
            rows.append([c + Vector((0, 0, height))])
            break
        rows.append([c + Vector((math.cos(2 * math.pi * i / sides) * r * jit[i] * stretch[0],
                                 math.sin(2 * math.pi * i / sides) * r * jit[i] * stretch[1], z)) for i in range(sides)])
    mb.loft(rows, mat, cap_start=False, cap_end=False, inside=c + Vector((0, 0, -1.0)))
    return smooth(mk(mb, name))


def snow_cap(center, rx, ry, thick, z_fn, name=None, seed=0, sides=10, rings=3, droop=0.03, mat="snow"):
    """Smooth pillow cap draped on a surface: rings around `center` (x, y); z_fn(x, y) = surface height under
    the cap. Thickness `thick` at the centre falling to ~0 at the rim, rim drooping `droop` below the surface
    (hides the seam on a rock / stump top). Smooth shaded, open bottom."""
    rnd = random.Random(seed)
    c = Vector(center)
    mb = lp.MeshBuilder()
    jit = [rnd.uniform(0.82, 1.12) for _ in range(sides)]
    rows = []
    for k in range(rings + 1):
        t = k / rings                                   # 0 = rim, 1 = centre
        if k == rings:
            rows.append([Vector((c.x, c.y, z_fn(c.x, c.y) + thick))])
            break
        row = []
        for i in range(sides):
            a = 2 * math.pi * i / sides
            x = c.x + math.cos(a) * rx * (1 - t) * jit[i]
            y = c.y + math.sin(a) * ry * (1 - t) * jit[i]
            h = thick * (1 - (1 - t) ** 2) ** 0.7 - droop * (1 - t) ** 4
            row.append(Vector((x, y, z_fn(x, y) + h)))
        rows.append(row)
    mb.loft(rows, mat, cap_start=False, cap_end=False, inside=Vector((c.x, c.y, z_fn(c.x, c.y) - 1.0)))
    return smooth(mk(mb, name))


# ------------------------------------------------------------------------------------------------------------
# baked ambient occlusion -> COLOR_0.a
# ------------------------------------------------------------------------------------------------------------
def _visual_meshes():
    from .export import is_col
    return [o for o in bpy.context.scene.objects if o.type == 'MESH' and not is_col(o.name)]


def has_ao(obj):
    """True when the `Col` alpha of `obj` already carries AO (some corner < 1)."""
    col = obj.data.color_attributes.get(palette.VCOL_ATTR)
    if col is None or not len(col.data):
        return False
    data = [0.0] * (len(col.data) * 4)
    col.data.foreach_get("color", data)
    return min(data[3::4]) < 0.999


def scene_bounds(objs=None):
    bpy.context.view_layer.update()
    objs = objs if objs is not None else _visual_meshes()
    mn = Vector((1e9, 1e9, 1e9))
    mx = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        for v in o.data.vertices:
            w = o.matrix_world @ v.co
            for i in range(3):
                mn[i] = min(mn[i], w[i])
                mx[i] = max(mx[i], w[i])
    return mn, mx


def _hemisphere(k):
    """k cosine-weighted directions on the +Z hemisphere (Fibonacci spiral: deterministic, well spread)."""
    ga = math.pi * (3.0 - math.sqrt(5.0))
    out = []
    for i in range(k):
        u = (i + 0.5) / k
        r = math.sqrt(u)
        out.append((r * math.cos(i * ga), r * math.sin(i * ga), math.sqrt(max(0.0, 1.0 - u))))
    return out


def _occluder_tree(objs, planes):
    from mathutils.bvhtree import BVHTree
    verts, polys = [], []
    for o in objs:
        mw = o.matrix_world
        base = len(verts)
        verts += [mw @ v.co for v in o.data.vertices]
        polys += [tuple(base + i for i in p.vertices) for p in o.data.polygons]
    for p, n in planes:
        q = n.to_track_quat('Z', 'Y').to_matrix()
        s = 60.0
        base = len(verts)
        verts += [p + q @ Vector((x, y, 0)) for x, y in ((-s, -s), (s, -s), (s, s), (-s, s))]
        polys.append((base, base + 1, base + 2, base + 3))
    return BVHTree.FromPolygons(verts, polys, epsilon=0.0)


def bake_ao(objs, distance=1.0, samples=64, ground=True, ground_z=0.0, gamma=1.0, floor=0.0, walls=(),
            inset=0.05, inset_frac=0.25, eps=0.002, exclude=()):
    """Bake ambient occlusion per corner into the alpha of `Col` for every object in `objs` (ray cast against a
    BVH of every visual mesh of the scene; Col* collision objects never occlude). A ground plane at z = ground_z
    darkens the bases (ground=False for hanging / hand-held assets); `walls` = [(point, normal)] adds occluder
    planes (wall-mounted assets). alpha = floor + (1 - floor) * ao ** gamma, ao = fraction of `samples`
    cosine-weighted rays that travel `distance` without a hit.

    Sampling point (why not Cycles' vertex bake): Cycles samples AO exactly AT each vertex, and on board / box
    construction the vertices sit on contact lines with the neighbouring parts, so whole flat faces (a wall, a
    roof panel) came out 50-97 % occluded. Here a corner of a FLAT face (flat shaded, or a hardened chamfer face)
    is sampled `inset` m (at most `inset_frac` of the way) toward its face centre, 2 mm above the face; a corner
    of a SMOOTH surface is sampled at its vertex along its normal (one value per vertex: no seams on snow / cloth).
    `exclude` = object names that do not occlude (M3: cutaway stubs are baked without the full walls they replace).
    Returns the bake time (s)."""
    from .export import is_col
    t0 = time.time()
    sc = bpy.context.scene
    bpy.context.view_layer.update()          # objects made with a pivot / parent have a stale matrix_world before
    occ = [o for o in sc.objects if o.type == 'MESH' and not is_col(o.name) and o.name not in exclude]
    planes = []
    if ground:
        planes.append((Vector((0, 0, ground_z)), Vector((0, 0, 1))))
    planes += [(Vector(p), Vector(n).normalized()) for p, n in walls]
    tree = _occluder_tree(occ, planes)
    dirs = _hemisphere(samples)
    golden = 0.6180339887
    for o in objs:
        me = o.data
        mw = o.matrix_world
        m3 = mw.to_3x3().inverted().transposed()
        wv = [mw @ v.co for v in me.vertices]
        cn = me.corner_normals
        col = me.color_attributes[palette.VCOL_ATTR]
        c = [0.0] * (len(me.loops) * 4)
        col.data.foreach_get("color", c)
        cache = {}
        for poly in me.polygons:
            li = list(poly.loop_indices)
            vi = list(poly.vertices)
            fn = (m3 @ poly.normal).normalized()
            cen = sum((wv[i] for i in vi), Vector()) / len(vi)
            for k, lidx in enumerate(li):
                n = (m3 @ cn[lidx].vector).normalized()
                p = wv[vi[k]]
                if n.dot(fn) > 0.9995:                         # flat / hardened face corner: sample inside
                    d = cen - p
                    L = d.length
                    if L > 1e-9:
                        p = p + d * (min(inset, inset_frac * L) / L)
                    n = fn
                    key = None
                else:                                         # smooth corner: one sample per vertex + normal
                    key = (vi[k], round(n.x, 3), round(n.y, 3), round(n.z, 3))
                    if key in cache:
                        c[lidx * 4 + 3] = cache[key]
                        continue
                origin = p + n * eps
                t = n.orthogonal().normalized()
                b = n.cross(t)
                ang = 2.0 * math.pi * ((lidx * golden) % 1.0)
                ca, sa = math.cos(ang), math.sin(ang)
                t, b = t * ca + b * sa, b * ca - t * sa
                hits = 0
                for dx, dy, dz in dirs:
                    if tree.ray_cast(origin, t * dx + b * dy + n * dz, distance)[0] is not None:
                        hits += 1
                ao = 1.0 - hits / len(dirs)
                val = floor + (1.0 - floor) * (ao ** gamma)
                c[lidx * 4 + 3] = val
                if key is not None:
                    cache[key] = val
        col.data.foreach_set("color", c)
        me.update()
    return time.time() - t0


def auto_ao_settings():
    """Default AO bake for an asset (doc 05 §4.6): distance ~0.3 x its size (0.1 .. 1.2 m); a ground plane only
    for assets standing on z = 0."""
    mn, mx = scene_bounds()
    size = max(mx - mn)
    return dict(distance=max(0.1, min(1.2, 0.3 * size)), samples=48, ground=mn.z > -0.30 and mn.z < 0.03)


def bake_scene_ao(distance=None, samples=None, ground=None, walls=(), force=False):
    """AO for every visual mesh of the scene that has none yet (or all with force=True). Returns the objects baked."""
    objs = [o for o in _visual_meshes() if force or not has_ao(o)]
    if not objs:
        return []
    auto = auto_ao_settings()
    bake_ao(objs, distance=auto["distance"] if distance is None else distance,
            samples=auto["samples"] if samples is None else samples,
            ground=auto["ground"] if ground is None else ground, walls=walls)
    return objs


def snow_ridge(p0, p1, width, thick, name=None, segs=None, prof=5, overhang=0.01, droop=0.01, seed=0, mat="snow"):
    """Cheap rounded snow line (M3) for thin rails / board tops / post tops of repeated props: a half-dome profile
    (`prof` points) swept from p0 to p1 (points on the top surface) in `segs` segments, thickness tapering to the
    rounded ends, rim drooping `droop` below the surface. Smooth, open bottom. ~8 x segs + 8 tris (vs ~130 for a
    subdivided snow_strip)."""
    rnd = random.Random(seed)
    p0, p1 = Vector(p0), Vector(p1)
    U = (p1 - p0)
    L = U.length
    U.normalize()
    N = Vector((0, 0, 1))
    V = N.cross(U).normalized()
    segs = segs or max(2, min(6, int(L / 0.35) + 1))
    mb = lp.MeshBuilder()
    rows = []
    for k in range(segs + 1):
        t = k / segs
        c = p0 - U * overhang + U * ((L + 2 * overhang) * t)
        end = min(1.0, min(t, 1 - t) * (L + 2 * overhang) / max(0.04, width * 0.6))
        th = thick * (0.35 + 0.65 * end ** 0.6) * rnd.uniform(0.9, 1.1)
        row = []
        for j in range(prof):
            a = math.pi * j / (prof - 1)                     # 0 .. pi across the width
            w = -math.cos(a) * (width / 2) * (0.75 + 0.25 * end)
            h = math.sin(a) * th - droop * (1 - math.sin(a))
            row.append(c + V * w + N * h)
        rows.append(row)
    idx = [[mb._v(p) for p in r] for r in rows]
    for k in range(segs):
        for j in range(prof - 1):
            mb.add_face((idx[k][j], idx[k][j + 1], idx[k + 1][j + 1], idx[k + 1][j]), mat, facing=N)
    for k, sgn in ((0, -1), (segs, 1)):
        cen = mb._v(sum((mb.verts[i] for i in idx[k]), Vector()) / prof + U * (sgn * width * 0.12))
        for j in range(prof - 1):
            mb.add_face((idx[k][j], idx[k][j + 1], cen), mat, facing=U * sgn + N * 0.5)
    return smooth(mk(mb, name))


def snow_cone_cap(center, half, base_z, apex_z, thick, name=None, sides=8, droop=0.015, seed=0, mat="snow"):
    """Snow cap on a square post top / pyramid cap (M3): 2 rings + apex, smooth; ~3 x sides tris."""
    rnd = random.Random(seed)
    c = Vector(center)
    mb = lp.MeshBuilder()
    rows = []
    for k, (f, dz) in enumerate(((1.12, -droop), (0.62, None))):
        row = []
        for i in range(sides):
            a = 2 * math.pi * (i + 0.5) / sides
            r = half * f * rnd.uniform(0.95, 1.08) / max(abs(math.cos(a)), abs(math.sin(a))) ** 0.35
            x, y = math.cos(a) * r, math.sin(a) * r
            zs = base_z + (apex_z - base_z) * max(0.0, 1 - max(abs(x), abs(y)) / half)
            z = zs + dz if dz is not None else zs + thick * 0.85
            row.append(c + Vector((x, y, 0)) + Vector((0, 0, z - c.z)))
        rows.append(row)
    rows.append([Vector((c.x, c.y, apex_z + thick))])
    mb.loft(rows, mat, cap_start=False, cap_end=False, inside=Vector((c.x, c.y, base_z - 1.0)))
    return smooth(mk(mb, name))
