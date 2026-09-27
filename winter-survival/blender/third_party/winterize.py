"""winterize — bring a third-party (CC0) model to the VENTISCA contract (milestone A1; prototype: docs/research/07 §4).

Stages (each one a function; build_city.py chains them per asset):
  1. import     glTF / GLB / FBX / OBJ / USD[A] -> mesh objects with baked transforms, no empties / armatures
  2. conform    axes (front = -Y), origin = base centre, scale (fixed | per detected floor | per length | per
                target dims), band EXTEND (repeat a period: tower floors, bus window bays) and band STRETCH (lengthen
                a toy van between its axles without deforming the wheels)
  3. colour     per corner: the base-colour texture at the corner UV (palette atlases: exact) or the material colour
                or a name -> palette rule (packs whose colours were lost), written to the `Col` attribute (linear);
                per face a class in the INT face attribute `cls` (body, window, glass, lamp, tail, beacon, ...)
  4. grade      OKLab winter grade (lightness into the v2.1 range, chroma x0.45..0.76, cool neutrals, cream whites)
                + snap to the nearest v2.1 palette colour when dE_ok < SNAP_DE
  5. weather    grime rising from the ground, facade streaks, frost on steep-up faces, rust (vehicles), value noise
  6. snow       rounded snow slabs on flat up-facing islands (with a height window: towers only get slabs on the
                parts the game camera can see), painted snow on small ledges, drifts at the base, mounds
  7. AO         lib/hd.bake_ao into COLOR_0.a (the game assets' bake)
  8. export     lib/export.export_gltf (COLOR_0 RGBA, palette_vcol + window / glass / emissive_lamp, no UV, no images);
                NO .blend is saved (third-party outputs are regenerated from the pinned sources)

Everything is deterministic (seeds from zlib.crc32 of the asset id), so a rebuild is byte-identical.
"""
import math
import random
import re
import zlib

import bpy  # noqa: I001  (bpy first: it provides bmesh / mathutils)
import bmesh
from mathutils import Matrix, Vector, noise

from lib import export as ex
from lib import hd
from lib import palette

VERSION = "a1.0"

# face classes (INT face attribute `cls`)
CLS = {"body": 0, "window": 1, "glass": 2, "lamp": 3, "tail": 4, "beacon": 5, "snow": 6, "slab": 7, "interior": 8,
       "panel": 9, "burnt": 10, "frost": 11}
CLS_NAME = {v: k for k, v in CLS.items()}
# class -> material (palette_vcol unless listed); exception faces carry white RGB
CLS_MATERIAL = {CLS["window"]: "window", CLS["glass"]: "glass", CLS["lamp"]: "emissive_lamp"}
# classes whose RGB is left alone by grade / weather (already final)
FIXED_CLASSES = {CLS["window"], CLS["glass"], CLS["lamp"], CLS["tail"], CLS["snow"], CLS["frost"]}

WINDOW_WORDS = ("window", "glass", "interior", "fakeinterior")
LAMP_WORDS = ("headlight", "whitelight", "lights", "light", "lamp")
TAIL_WORDS = ("taillight", "brakelight", "brake")
BEACON_WORDS = ("bluelight", "redlight", "beacon")

SNAP_DE = 0.03
SLAB_AO = 0.25          # baked AO of floor slabs (W0: <= 0.3)


def seed_of(text):
    return zlib.crc32(text.encode("utf-8")) & 0xffff


# ------------------------------------------------------------------------------------------------------------------
# colour science (linear sRGB <-> OKLab)
# ------------------------------------------------------------------------------------------------------------------
def s2l(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def l2s(c):
    c = max(0.0, c)
    return c * 12.92 if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def hex_lin(h):
    h = h.lstrip("#")
    return tuple(s2l(int(h[i:i + 2], 16) / 255.0) for i in (0, 2, 4))


def lin_to_oklab(r, g, b):
    l_ = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    m_ = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    s_ = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
    l_, m_, s_ = (max(v, 0.0) ** (1 / 3) for v in (l_, m_, s_))
    return (0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
            1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
            0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_)


def oklab_to_lin(L, a, b):
    l_ = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3
    m_ = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3
    s_ = (L - 0.0894841775 * a - 1.2914855480 * b) ** 3
    return (max(0.0, 4.0767416621 * l_ - 3.3077115913 * m_ + 0.2309699292 * s_),
            max(0.0, -1.2684380046 * l_ + 2.6097574011 * m_ - 0.3413193965 * s_),
            max(0.0, -0.0041960863 * l_ - 0.7034186147 * m_ + 1.7076147010 * s_))


def smooth01(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def de_ok(c1, c2):
    a, b = lin_to_oklab(*c1), lin_to_oklab(*c2)
    return math.sqrt(sum((x - y) ** 2 for x, y in zip(a, b)))


_PAL = None


def palette_targets():
    """[(name, linear rgb stored in Col, oklab)] of every non-exception v2.1 palette colour."""
    global _PAL
    if _PAL is None:
        _PAL = []
        for n in palette.BASE_NAMES:
            if palette.is_exception(n):
                continue
            rgb = palette.vcol_rgba(n)[:3]
            _PAL.append((n, rgb, lin_to_oklab(*palette.linear_rgba(n)[:3])))
    return _PAL


def snap(rgb, tol=SNAP_DE):
    """Nearest v2.1 palette colour when within dE_ok `tol` (returns (rgb, name or None))."""
    lab = lin_to_oklab(*rgb)
    best, bd = None, 1e9
    for n, stored, plab in palette_targets():
        d = math.sqrt(sum((x - y) ** 2 for x, y in zip(lab, plab)))
        if d < bd:
            best, bd = (n, stored), d
    if bd < tol:
        return best[1], best[0]
    return rgb, None


def grade(rgb, kind, chroma=0.0):
    """Winter grade of one LINEAR colour -> LINEAR colour (palette v2.1 art direction in one function, doc 07 §4.1):
    whites land on cream (~#CECAC4: facades read against the #CDDEF5 snow), blacks lift a little (#303034 ->
    ~#3D424A), chroma x0.45..0.70 (+0.06 on vehicle paint, + `chroma`), mid neutrals lean cool, near-whites warm."""
    L, a, b = lin_to_oklab(*rgb)
    C = math.hypot(a, b)
    h = math.atan2(b, a)
    L2 = 0.17 + 0.67 * L
    k = 0.45 + 0.25 * smooth01(0.10, 0.22, C)
    if kind == "vehicle":
        k += 0.14                       # paint is the only colour on the street: keep it readable
    k += chroma
    C2 = C * k
    a2, b2 = C2 * math.cos(h), C2 * math.sin(h)
    neutral = 1.0 - smooth01(0.02, 0.10, C2)
    warm = smooth01(0.72, 0.86, L2)
    a2 += neutral * (-0.003 * (1 - warm) + 0.002 * warm)
    b2 += neutral * (-0.012 * (1 - warm) + 0.010 * warm)
    return oklab_to_lin(L2, a2, b2)


# ------------------------------------------------------------------------------------------------------------------
# scene / import
# ------------------------------------------------------------------------------------------------------------------
def reset():
    from lib import lowpoly as lp
    lp.new_scene()                      # factory settings + clears lowpoly's pivot registry
    ex.ensure_gltf()
    try:
        bpy.context.preferences.filepaths.save_version = 0
    except Exception:
        pass


def norm_mat(name):
    """'Black.003' / 'Green_002' / 'Windows.005' -> 'black' / 'green' / 'windows'."""
    n = re.sub(r"[._]\d{3}$", "", name or "")
    return n.lower()


def import_any(path):
    """Import a model file; returns its mesh objects (parent transforms baked, modifiers removed, no other object)."""
    path = str(path)
    ext = path.lower().rsplit(".", 1)[1]
    before = set(bpy.data.objects)
    with ex.quiet():
        if ext in ("glb", "gltf"):
            bpy.ops.import_scene.gltf(filepath=path)
        elif ext == "fbx":
            bpy.ops.import_scene.fbx(filepath=path)
        elif ext == "obj":
            bpy.ops.wm.obj_import(filepath=path)
        elif ext in ("usd", "usda", "usdc", "usdz"):
            bpy.ops.wm.usd_import(filepath=path, import_skeletons=False, import_blendshapes=False)
        else:
            raise ValueError("unsupported format: %s" % path)
    new = [o for o in bpy.data.objects if o not in before]
    bpy.context.view_layer.update()
    meshes = [o for o in new if o.type == "MESH"]
    for o in meshes:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
        for m in list(o.modifiers):
            o.modifiers.remove(m)
    for o in new:
        if o.type != "MESH":
            bpy.data.objects.remove(o, do_unlink=True)
    for o in meshes:
        o.data = o.data.copy() if o.data.users > 1 else o.data     # instanced meshes -> own data
        mirrored = o.matrix_world.determinant() < 0
        o.data.transform(o.matrix_world)
        if mirrored:                                   # a mirrored instance: baking the matrix flips the winding
            o.data.flip_normals()
        o.matrix_world = Matrix.Identity(4)
    return meshes


def join(objs, name):
    """Join mesh objects into one called `name` (normals frozen first, materials deduplicated)."""
    objs = [o for o in objs if o is not None]
    if len(objs) == 1:
        o = objs[0]
        hd.freeze_normals(o)
        o.name = name
        o.data.name = name
        hd._dedupe_materials(o)
        return o
    return hd.join(objs, name)


def mesh_from_bm(bm, name, like=None):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    if like is not None:
        for m in like.data.materials:
            me.materials.append(m)
    return o


def bounds(objs):
    objs = objs if isinstance(objs, (list, tuple)) else [objs]
    vs = [o.matrix_world @ v.co for o in objs for v in o.data.vertices]
    mn = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    mx = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    return mn, mx


def tri_count(objs):
    objs = objs if isinstance(objs, (list, tuple)) else [objs]
    return sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objs if o.type == "MESH")


def merge_close(obj, dist=1e-4):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=dist)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def fix_inverted_parts(obj):
    """Flip every CLOSED connected component whose signed volume is negative (inside-out parts exist in some source
    meshes). Open components are left alone. Returns the number of components flipped."""
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    bm.normal_update()
    seen, flipped = set(), 0
    for f0 in bm.faces:
        if f0.index in seen:
            continue
        comp, st = [], [f0]
        seen.add(f0.index)
        while st:
            f = st.pop()
            comp.append(f)
            for e in f.edges:
                for g in e.link_faces:
                    if g.index not in seen:
                        seen.add(g.index)
                        st.append(g)
        edges = {e for f in comp for e in f.edges}
        if any(len(e.link_faces) != 2 for e in edges):
            # open part: flip when most of its area faces its own centroid (an inside-out open box / trim)
            if len(comp) < 4:
                continue
            area = sum(f.calc_area() for f in comp)
            cen = sum((f.calc_center_median() * f.calc_area() for f in comp), Vector()) / max(area, 1e-9)
            inward = sum(f.calc_area() for f in comp if f.normal.dot(f.calc_center_median() - cen) < -1e-4)
            outward = sum(f.calc_area() for f in comp if f.normal.dot(f.calc_center_median() - cen) > 1e-4)
            if inward > 0.75 * area and inward > 3.0 * outward:
                for f in comp:
                    f.normal_flip()
                flipped += 1
            continue
        vol = 0.0
        for f in comp:
            vs = [v.co for v in f.verts]
            for i in range(1, len(vs) - 1):
                vol += vs[0].dot(vs[i].cross(vs[i + 1]))
        if vol < -1e-7:
            for f in comp:
                f.normal_flip()
            flipped += 1
    if flipped:
        bm.to_mesh(me)
        me.update()
    bm.free()
    return flipped


def separate_coplanar(obj, tol=0.002, push=0.001):
    """Zero-thickness double-sided panels (two faces on the same plane with opposite normals) render at random:
    push each face of such a pair `push` m along its own normal. Returns the number of pairs."""
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.normal_update()
    grid = {}
    for f in bm.faces:
        c = f.calc_center_median()
        grid.setdefault((round(c.x / tol), round(c.y / tol), round(c.z / tol)), []).append(f)
    pairs = 0
    moved = set()
    for fs in grid.values():
        if len(fs) < 2:
            continue
        for i, a in enumerate(fs):
            for b in fs[i + 1:]:
                if a.normal.dot(b.normal) < -0.99 and abs(a.calc_area() - b.calc_area()) < 0.05 * a.calc_area() + 1e-6:
                    for f in (a, b):
                        n = f.normal.copy()
                        for v in f.verts:
                            if v not in moved:
                                v.co += n * push
                                moved.add(v)
                    pairs += 1
    if pairs:
        bm.to_mesh(me)
        me.update()
    bm.free()
    return pairs


def transform(obj, m):
    obj.data.transform(m)
    obj.data.update()


# ------------------------------------------------------------------------------------------------------------------
# conform
# ------------------------------------------------------------------------------------------------------------------
def floor_period(obj, lo=0.2, hi=0.85):
    """Most frequent vertical repeat of the vertex heights in the middle of the model (floor-to-floor), or None."""
    zs = sorted({round(v.co.z, 3) for v in obj.data.vertices})
    if len(zs) < 6:
        return None
    H = zs[-1] - zs[0]
    mid = [z for z in zs if zs[0] + lo * H <= z <= zs[0] + hi * H]
    zset = set(zs)
    best, best_n = None, 0
    cands = sorted({round(b - a, 3) for i, a in enumerate(mid) for b in mid[i + 1:i + 12]
                    if 0.08 * H < b - a < 0.45 * H})
    for p in cands:
        n = sum(1 for z in mid if round(z + p, 3) in zset or round(z + p + 0.001, 3) in zset
                or round(z + p - 0.001, 3) in zset)
        if n > best_n * 1.05 or (n >= best_n and best and p < best):
            best, best_n = p, n
    if best and best_n >= 4:
        half = best / 2
        n2 = sum(1 for z in mid if any(abs((z + half) - w) < 2e-3 for w in zs))
        if n2 >= 0.75 * best_n and half > 0.05 * H:
            best = half
    return best if best_n >= 4 else None


def band_start(obj, period, axis=2, lo=0.25, hi=0.7, target=0.45):
    """A coordinate c (on `axis`) where both c and c + period are vertex planes, near `target` of the extent."""
    cs = [v.co[axis] for v in obj.data.vertices]
    c_lo, c_hi = min(cs), max(cs)
    H = c_hi - c_lo
    cset = sorted({round(c, 4) for c in cs})
    cands = [c for c in cset if any(abs(c + period - w) < 2e-3 for w in cset) and c_lo + lo * H < c < c_lo + hi * H]
    if not cands:
        return None
    return min(cands, key=lambda c: abs(c - (c_lo + target * H)))


def extend_band(obj, period, copies, axis=2, start=None):
    """Repeat the band [start, start + period] along `axis` `copies` times (towers are floor-periodic; a bus is
    window-bay-periodic): split at both planes, lift everything beyond the band, duplicate the band. Returns
    (start, added length) or (None, 0)."""
    if copies <= 0:
        return None, 0.0
    z0 = start if start is not None else band_start(obj, period, axis)
    if z0 is None:
        return None, 0.0
    z1 = z0 + period
    no = [0.0, 0.0, 0.0]
    no[axis] = 1.0
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    for zc in (z0, z1):
        co = [0.0, 0.0, 0.0]
        co[axis] = zc
        geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
        bmesh.ops.bisect_plane(bm, geom=geom, dist=1e-5, plane_co=co, plane_no=no)
    bm.faces.ensure_lookup_table()
    eps = 1e-4
    band = [f for f in bm.faces if z0 - eps <= f.calc_center_median()[axis] <= z1 + eps]
    beyond = [f for f in bm.faces if f.calc_center_median()[axis] > z1 + eps]
    res = bmesh.ops.split(bm, geom=beyond, use_only_faces=False)
    moved = {v for e in res["geom"] if isinstance(e, bmesh.types.BMFace) for v in e.verts}
    for v in moved:
        v.co[axis] += period * copies
    for i in range(1, copies + 1):
        d = bmesh.ops.duplicate(bm, geom=band)
        for e in d["geom"]:
            if isinstance(e, bmesh.types.BMVert):
                e.co[axis] += period * i
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-4)
    bm.to_mesh(me)
    bm.free()
    me.update()
    return z0, period * copies


def stretch_band(obj, axis, at, amount):
    """Move every vertex beyond `at` on `axis` by `amount` (faces crossing `at` stretch; parts entirely on one side,
    e.g. the wheels, keep their shape). Cut first so only the faces AT the plane stretch."""
    if abs(amount) < 1e-6:
        return
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    co = [0.0, 0.0, 0.0]
    co[axis] = at
    no = [0.0, 0.0, 0.0]
    no[axis] = 1.0
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], dist=1e-5, plane_co=co, plane_no=no)
    for v in bm.verts:
        if v.co[axis] > at + 1e-5:
            v.co[axis] += amount
    # the faces lying exactly in the cut plane (none normally) stay; split faces spanning the gap are the stretch
    bm.to_mesh(me)
    bm.free()
    me.update()


def conform(obj, cfg):
    """Axes, origin, scale and band edits of `cfg` (see build_city.py tables). Returns an info dict."""
    info = {}
    kind = cfg["kind"]
    if cfg.get("fix_up"):
        transform(obj, Matrix.Rotation(math.radians(90), 4, "X"))
    mn, mx = bounds(obj)
    size = mx - mn
    if kind == "vehicle" and size.x > size.y:                  # long axis to Y
        transform(obj, Matrix.Rotation(math.radians(90), 4, "Z"))
    if cfg.get("yaw"):
        transform(obj, Matrix.Rotation(math.radians(cfg["yaw"]), 4, "Z"))
    mn, mx = bounds(obj)
    transform(obj, Matrix.Translation(-Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z))))
    sc = cfg.get("scale", 1.0)
    per = floor_period(obj) if kind in ("tower", "building") else None
    info["floor_period_src"] = round(per, 4) if per else None
    if isinstance(sc, str) and sc.startswith("floor:"):
        if not per:
            raise RuntimeError("no floor period detected for %s" % cfg.get("src"))
        sc = float(sc[6:]) / per
    elif isinstance(sc, str) and sc.startswith("len:"):
        mn, mx = bounds(obj)
        sc = float(sc[4:]) / max(mx.x - mn.x, mx.y - mn.y)
    elif isinstance(sc, str) and sc.startswith("width:"):
        mn, mx = bounds(obj)
        sc = float(sc[6:]) / (mx.x - mn.x)
    elif isinstance(sc, str) and sc.startswith("dims:"):
        mn, mx = bounds(obj)
        w, ln, h = (float(x) for x in sc[5:].split(","))
        sc = [w / (mx.x - mn.x), ln / (mx.y - mn.y), h / (mx.z - mn.z)]
    elif isinstance(sc, str) and sc.startswith("height:"):
        mn, mx = bounds(obj)
        sc = float(sc[7:]) / (mx.z - mn.z)
    if cfg.get("extend") and per:
        z0, added = extend_band(obj, per, cfg["extend"])
        info["band_start_src"] = z0
        info["extended_src"] = added
    if isinstance(sc, (list, tuple)):
        transform(obj, Matrix.Diagonal((sc[0], sc[1], sc[2], 1.0)))
        info["scale"] = [round(s, 4) for s in sc]
    else:
        transform(obj, Matrix.Scale(sc, 4))
        info["scale"] = round(sc, 4)
    info["floor_period"] = round(per * (sc if not isinstance(sc, (list, tuple)) else sc[2]), 4) if per else None
    # post-scale band edits in metres: [("x"|"y"|"z", at (fraction of extent if |at| <= 1.0 and frac=True), amount)]
    for axis_name, at, amount in cfg.get("stretch", ()):
        axis = "xyz".index(axis_name)
        stretch_band(obj, axis, at, amount)
    for axis_name, period, copies, start in cfg.get("extend_axis", ()):
        axis = "xyz".index(axis_name)
        z0, added = extend_band(obj, period, copies, axis=axis, start=start)
        info.setdefault("extend_axis", []).append([axis_name, z0, added])
    mn, mx = bounds(obj)
    transform(obj, Matrix.Translation(-Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z))))
    mn, mx = bounds(obj)
    info["size_m"] = [round(x, 2) for x in (mx - mn)]
    return info


# ------------------------------------------------------------------------------------------------------------------
# colour extraction -> `Col` (linear) + `cls`
# ------------------------------------------------------------------------------------------------------------------
_IMG_CACHE = {}


def load_image(path):
    key = str(path)
    img = bpy.data.images.get(key)
    if img is None:
        img = bpy.data.images.load(str(path), check_existing=True)
    return img


def image_sampler(img, downsample=None):
    key = (img.filepath or img.name, downsample)
    if key in _IMG_CACHE:
        return _IMG_CACHE[key]
    w, h = img.size
    px = list(img.pixels[:])
    ch = img.channels
    if downsample and (w > downsample or h > downsample):
        nw = nh = downsample
        acc = [[0.0, 0.0, 0.0, 0] for _ in range(nw * nh)]
        for y in range(h):
            yy = y * nh // h
            row = y * w * ch
            for x in range(0, w, 2):
                i = row + x * ch
                a = acc[yy * nw + x * nw // w]
                a[0] += px[i]
                a[1] += px[i + 1]
                a[2] += px[i + 2]
                a[3] += 1
        px2 = []
        for a in acc:
            n = max(1, a[3])
            px2 += [a[0] / n, a[1] / n, a[2] / n, 1.0]
        w, h, ch, px = nw, nh, 4, px2
    srgb = img.colorspace_settings.name.lower().startswith("srgb")

    def sample(u, v):
        x = int((u % 1.0) * w) % w
        y = int((v % 1.0) * h) % h
        i = (y * w + x) * ch
        c = px[i:i + 3]
        return tuple(s2l(t) for t in c) if srgb else tuple(c)
    _IMG_CACHE[key] = sample
    return sample


def material_source(mat):
    """(image or None, base colour linear) of a material's Base Color."""
    if mat is None:
        return None, (0.6, 0.6, 0.6)
    if not mat.use_nodes:
        return None, tuple(mat.diffuse_color[:3])
    nt = mat.node_tree
    bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        return None, tuple(mat.diffuse_color[:3])
    inp = bsdf.inputs["Base Color"]
    col = tuple(inp.default_value[:3])
    img = None
    stack = [lk.from_node for lk in inp.links]
    seen = 0
    while stack and seen < 12:
        n = stack.pop()
        seen += 1
        if n.type == "TEX_IMAGE" and n.image:
            img = n.image
            break
        for i in n.inputs:
            stack += [lk.from_node for lk in i.links]
    if img is not None:
        col = (1.0, 1.0, 1.0)
    return img, col


def hsv(rgb_lin):
    import colorsys
    return colorsys.rgb_to_hsv(*(l2s(c) for c in rgb_lin))


def classify(mname, rgb_lin, kind, cfg, nz=0.0):
    """Face class from the material name (exact per pack in cfg['classes'], else word rules) or the atlas swatch."""
    n = norm_mat(mname)
    rules = cfg.get("classes", {})
    if n in rules:
        return rules[n]
    if any(w in n for w in TAIL_WORDS):
        return "tail"
    if any(w in n for w in BEACON_WORDS):
        return "beacon"
    if any(w in n for w in WINDOW_WORDS):
        return "glass" if kind == "vehicle" else "window"
    if any(w in n for w in LAMP_WORDS):
        return "lamp"
    h, s, v = hsv(rgb_lin)
    hdeg = h * 360
    if kind in ("tower", "building") and cfg.get("window_rule", True) and abs(nz) < 0.35 and 190 <= hdeg <= 236 \
            and cfg.get("window_sat", 0.10) <= s <= 0.80 and v >= 0.50:
        return "window"          # Kenney glass swatches (light blue -> blue) on vertical faces only (doc 07 §3.4-5)
    rule = cfg.get("glass_rule")
    if kind == "vehicle" and rule == "kenney" and 220 <= hdeg <= 250 and 0.10 <= s <= 0.32 and 0.33 <= v <= 0.62:
        return "glass"           # Kenney Car Kit window swatch (#606275 family)
    if kind == "vehicle" and isinstance(rule, dict):
        tgt = hex_lin(rule["hex"])
        if de_ok(rgb_lin, tgt) < rule.get("tol", 0.03):
            return "glass"
    for hx, cname, tol in cfg.get("swatch_classes", ()):
        if de_ok(rgb_lin, hex_lin(hx)) < tol:
            return cname
    return "body"


def fix_windows(obj, roof_z, min_h=0.35):
    """Post-scale cleanup of the swatch window rule: no window faces on parapets / above the main roof, none thinner
    than `min_h` (trims and cap strips keep their facade colour). Returns the number of faces reclassified."""
    me = obj.data
    cls = get_cls(me)
    n = 0
    for p in me.polygons:
        if cls[p.index] != CLS["window"]:
            continue
        zs = [me.vertices[i].co.z for i in p.vertices]
        if max(zs) - min(zs) < min_h or p.center.z > roof_z - 0.3:
            cls[p.index] = CLS["body"]
            n += 1
    set_cls(me, cls)
    return n


def ensure_cls(me):
    a = me.attributes.get("cls")
    if a is None:
        a = me.attributes.new("cls", "INT", "FACE")
    return a


def get_cls(me):
    a = me.attributes.get("cls")
    out = [0] * len(me.polygons)
    if a is not None:
        a.data.foreach_get("value", out)
    return out


def set_cls(me, vals):
    ensure_cls(me).data.foreach_set("value", vals)


def get_col(me):
    attr = palette.ensure_attribute(me)
    data = [0.0] * (len(me.loops) * 4)
    attr.data.foreach_get("color", data)
    return data


def set_col(me, data):
    palette.ensure_attribute(me).data.foreach_set("color", data)


def extract(obj, cfg):
    """Per corner base colour (linear) into `Col`, face class into `cls`. Material colour rules first
    (cfg['colours']: normalised material name -> palette name or #hex), then the texture at the corner UV
    (palette atlas; cfg['atlas'] overrides the image, e.g. Kenney variation-a/b), then the material colour."""
    me = obj.data
    uv = me.uv_layers.active
    mats = list(me.materials)
    srcs = [material_source(m) for m in mats]
    override = load_image(cfg["atlas"]) if cfg.get("atlas") else None
    rules = cfg.get("colours", {})
    kind = cfg["kind"]
    ds = 64 if cfg.get("tiling") else None
    data = [1.0] * (len(me.loops) * 4)
    cls = [0] * len(me.polygons)
    for p in me.polygons:
        mi = p.material_index if p.material_index < len(mats) else 0
        mname = mats[mi].name if mats and mats[mi] else ""
        img, base = srcs[mi] if srcs else (None, (0.6, 0.6, 0.6))
        if img is not None and override is not None:
            img = override
        cols = []
        rule = rules.get(norm_mat(mname))
        if rule is not None:
            c = hex_lin(rule) if rule.startswith("#") else palette.linear_rgba(rule)[:3]
            cols = [c] * p.loop_total
        elif img is not None and uv is not None:
            smp = image_sampler(img, ds)
            cu = sum(uv.data[li].uv.x for li in p.loop_indices) / p.loop_total
            cv = sum(uv.data[li].uv.y for li in p.loop_indices) / p.loop_total
            if ds:
                c = smp(cu, cv)
                cols = [tuple(c[i] * base[i] for i in range(3))] * p.loop_total
            else:
                for li in p.loop_indices:
                    u, v = uv.data[li].uv
                    c = smp(u * 0.8 + cu * 0.2, v * 0.8 + cv * 0.2)   # 20 % toward the centroid: no swatch bleed
                    cols.append(tuple(c[i] * base[i] for i in range(3)))
        else:
            cols = [base] * p.loop_total
        avg = tuple(sum(c[i] for c in cols) / len(cols) for i in range(3))
        cls[p.index] = CLS[classify(mname, avg, kind, cfg, p.normal.z)]
        for li, c in zip(p.loop_indices, cols):
            data[li * 4:li * 4 + 3] = c
    set_col(me, data)
    set_cls(me, cls)
    return cls


def recolour(obj, rules, kind):
    """Swatch remaps BEFORE grading: [(source #hex, target palette name or #hex, dE_ok tolerance)] — e.g. the olive
    Quaternius truck repainted as a civilian box truck. Keeps the per-corner shading ratio of each face."""
    if not rules:
        return
    me = obj.data
    data = get_col(me)
    tgt = [(hex_lin(s), hex_lin(t) if t.startswith("#") else palette.linear_rgba(t)[:3], tol) for s, t, tol in rules]
    for i in range(0, len(data), 4):
        c = tuple(data[i:i + 3])
        for src, dst, tol in tgt:
            if de_ok(c, src) < tol:
                Ls = lin_to_oklab(*src)[0]
                Lc = lin_to_oklab(*c)[0]
                d = lin_to_oklab(*dst)
                data[i:i + 3] = oklab_to_lin(max(0.0, d[0] + (Lc - Ls)), d[1], d[2])
                break
    set_col(me, data)


def grade_mesh(obj, kind, cfg):
    """OKLab grade + palette snap of every non-fixed face's corners."""
    me = obj.data
    data = get_col(me)
    cls = get_cls(me)
    chroma = cfg.get("chroma", 0.0)
    cache = {}
    snapped = 0
    for p in me.polygons:
        if cls[p.index] in FIXED_CLASSES:
            continue
        for li in p.loop_indices:
            key = tuple(round(x, 5) for x in data[li * 4:li * 4 + 3])
            if key not in cache:
                g = grade(key, kind, chroma)
                g2, name = snap(g) if cfg.get("snap", True) else (g, None)
                cache[key] = (g2, name)
            g2, name = cache[key]
            snapped += name is not None
            data[li * 4:li * 4 + 3] = g2
    set_col(me, data)
    return snapped


# ------------------------------------------------------------------------------------------------------------------
# weathering (baked into RGB)
# ------------------------------------------------------------------------------------------------------------------
GRIME = (0.10, 0.085, 0.07)


def weather(obj, kind, seed, amount=1.0, rust=None):
    me = obj.data
    data = get_col(me)
    cls = get_cls(me)
    rnd = random.Random(seed)
    off = Vector((rnd.random() * 100, rnd.random() * 100, rnd.random() * 100))
    frost = palette.linear_rgba("snow_shadow")[:3]
    rustc = palette.linear_rgba("rust")[:3]
    rust = (kind == "vehicle") if rust is None else rust
    gh = 0.9 if kind == "vehicle" else 1.8
    vco = [v.co.copy() for v in me.vertices]
    for p in me.polygons:
        if cls[p.index] in FIXED_CLASSES or cls[p.index] == CLS["slab"]:
            continue
        n = p.normal
        for li, vi in zip(p.loop_indices, p.vertices):
            wp = vco[vi]
            c = Vector(data[li * 4:li * 4 + 3])
            nz = noise.noise(wp * 0.9 + off)
            fine = noise.noise(wp * 4.1 + off * 2.0)
            c *= 1.0 + amount * (0.06 * nz + 0.025 * fine)
            g = (1.0 - smooth01(0.0, gh, wp.z)) * (0.55 + 0.45 * nz)
            if kind in ("tower", "building") and abs(n.z) < 0.3:
                st = noise.noise(Vector((wp.x * 2.3, wp.y * 2.3, wp.z * 0.15)) + off)
                g = max(g, 0.35 * smooth01(0.25, 0.7, st))
            c = c.lerp(Vector(GRIME), 0.38 * g * amount)
            fr = smooth01(0.25, 0.75, n.z) * (1.0 - smooth01(0.75, 0.9, n.z)) * (0.5 + 0.5 * nz)
            c = c.lerp(Vector(frost), 0.45 * fr)
            if rust:
                r = (1.0 - smooth01(0.2, 0.8, wp.z)) * smooth01(0.1, 0.6, fine)
                c = c.lerp(Vector(rustc), 0.35 * r * amount)
            data[li * 4:li * 4 + 3] = [max(0.0, x) for x in c]
    set_col(me, data)


# ------------------------------------------------------------------------------------------------------------------
# materials from classes
# ------------------------------------------------------------------------------------------------------------------
TAIL_RGB = palette.vcol_rgba("lamp_red")[:3]


def finish_materials(obj):
    """Material slots from the face classes (palette_vcol first), white RGB on exception faces, tail lights red,
    alpha reset to 1, UV layers removed, flat shading kept as authored (normals frozen by the caller)."""
    me = obj.data
    cls = get_cls(me)
    order = []
    if any(c not in CLS_MATERIAL for c in cls):
        order.append(palette.VCOL_MATERIAL)
    for c in cls:
        m = CLS_MATERIAL.get(c, palette.VCOL_MATERIAL)
        if m not in order:
            order.append(m)
    me.materials.clear()
    for m in order:
        me.materials.append(palette.get_vcol_material() if m == palette.VCOL_MATERIAL else palette.get_material(m))
    me.polygons.foreach_set("material_index", [order.index(CLS_MATERIAL.get(c, palette.VCOL_MATERIAL)) for c in cls])
    data = get_col(me)
    for p in me.polygons:
        c = cls[p.index]
        for li in p.loop_indices:
            if c in CLS_MATERIAL:
                data[li * 4:li * 4 + 3] = (1.0, 1.0, 1.0)
            elif c == CLS["tail"]:
                data[li * 4:li * 4 + 3] = TAIL_RGB
            data[li * 4 + 3] = 1.0
    set_col(me, data)
    while len(me.uv_layers):
        me.uv_layers.remove(me.uv_layers[0])
    for a in [a for a in me.color_attributes if a.name != palette.VCOL_ATTR]:
        me.color_attributes.remove(a)
    me.update()


def paint_faces(obj, faces, rgb=None, name=None, cls_name=None):
    """Repaint polygons (linear rgb or palette name) and/or change their class."""
    me = obj.data
    data = get_col(me)
    cls = get_cls(me)
    c = palette.vcol_rgba(name)[:3] if name else rgb
    for fi in faces:
        if c is not None:
            for li in me.polygons[fi].loop_indices:
                data[li * 4:li * 4 + 3] = c
        if cls_name:
            cls[fi] = CLS[cls_name]
    set_col(me, data)
    set_cls(me, cls)


def view_dirs():
    """The game-camera ray directions of the M3 back-face rule: pitch 48 (8 yaws) and 25 degrees (8 yaws)."""
    out = []
    for pitch, off in ((48.0, 0.0), (25.0, 22.5)):
        for k in range(8):
            p, y = math.radians(pitch), math.radians(45 * k + off)
            out.append(-Vector((math.sin(y) * math.cos(p), math.cos(y) * math.cos(p), math.sin(p))))
    return out


def patch_backfaces(objs, step_div=150, offset=0.002):
    """Give every face that a game-camera ray reaches from BEHIND (openings into a shell, open ends of source
    parts) a flipped twin 2 mm behind it with the same colour / class: Godot's world shader culls back faces, so
    the twin is what renders there. Returns the number of faces patched."""
    from mathutils.bvhtree import BVHTree
    objs = [o for o in objs if o.type == "MESH"]
    for o in objs:                         # triangles: what the exporter writes (non-planar n-gons would fold)
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 3], quad_method="BEAUTY",
                              ngon_method="BEAUTY")
        bm.to_mesh(o.data)
        bm.free()
        o.data.update()
    verts, polys, owner = [], [], []
    for o in objs:
        base = len(verts)
        verts += [v.co.copy() for v in o.data.vertices]
        for p in o.data.polygons:
            polys.append(tuple(base + i for i in p.vertices))
            owner.append((o, p.index))
    if not polys:
        return 0
    tree = BVHTree.FromPolygons(verts, polys, epsilon=0.0)
    mn = Vector([min(v[i] for v in verts) for i in range(3)])
    mx = Vector([max(v[i] for v in verts) for i in range(3)])
    c = (mn + mx) / 2
    R = (mx - mn).length / 2 + 0.2
    step = max(0.035, R / step_div)
    n = int(2 * R / step)
    hits = {}
    for d in view_dirs():
        u = d.cross(Vector((0, 0, 1))).normalized()
        w = u.cross(d).normalized()
        for i in range(n):
            for j in range(n):
                org = c - d * (R + 5) + u * (-R + i * step) + w * (-R + j * step)
                loc, nrm, idx, _dist = tree.ray_cast(org, d, 2 * R + 10)
                if idx is None or loc.z < -0.001:
                    continue
                o, fi = owner[idx]
                if o.data.polygons[fi].normal.dot(d) > 1e-4:
                    hits.setdefault(o, set()).add(fi)
    total = 0
    for o, faces in hits.items():
        me = o.data
        bm = bmesh.new()
        bm.from_mesh(me)
        bm.faces.ensure_lookup_table()
        bm.normal_update()
        src = [bm.faces[i] for i in sorted(faces)]
        for s_ in src:                                     # one twin per face (own vertices, own offset)
            nrm = s_.normal.copy()
            f = bmesh.ops.duplicate(bm, geom=[s_])["face_map"][s_]
            for v in f.verts:
                v.co -= nrm * offset
            f.normal_flip()
        bm.to_mesh(me)
        bm.free()
        me.update()
        total += len(faces)
    return total


def double_side(obj, offset=0.008):
    """Single-sided sheets (tent canvas): add a flipped copy of every face, offset `offset` m behind it."""
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.normal_update()
    faces = list(bm.faces)
    d = bmesh.ops.duplicate(bm, geom=faces)
    fmap = d["face_map"]
    moved = set()
    for src in faces:
        f = fmap[src]
        n = src.normal.copy()
        for v in f.verts:
            if v not in moved:
                v.co -= n * offset
                moved.add(v)
        f.normal_flip()
    bm.to_mesh(me)
    bm.free()
    me.update()


def strip_attributes(obj):
    me = obj.data
    for name in ("cls",):
        a = me.attributes.get(name)
        if a is not None:
            me.attributes.remove(a)


# ------------------------------------------------------------------------------------------------------------------
# snow
# ------------------------------------------------------------------------------------------------------------------
SNOW = palette.vcol_rgba("snow")[:3]
SNOW_DEEP = palette.vcol_rgba("snow_deep")[:3]
SNOW_SH = palette.vcol_rgba("snow_shadow")[:3]


def up_islands(obj, nz_min=0.80, z_range=None, classes=(0,)):
    """Connected islands of up-facing faces (same height within 5 cm) of the given classes: [(faces, area)]."""
    me = obj.data
    cls = get_cls(me)
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()

    def ok_face(f):
        if f.normal.z < nz_min or cls[f.index] not in classes:
            return False
        if z_range is not None:
            z = f.calc_center_median().z
            return z_range[0] <= z <= z_range[1]
        return True
    ok = {f.index for f in bm.faces if ok_face(f)}
    seen, islands = set(), []
    for f in bm.faces:
        if f.index not in ok or f.index in seen:
            continue
        stack, isl = [f], []
        seen.add(f.index)
        while stack:
            g = stack.pop()
            isl.append(g.index)
            gz = g.calc_center_median().z
            for e in g.edges:
                for h in e.link_faces:
                    if h.index in ok and h.index not in seen and abs(h.calc_center_median().z - gz) < 0.05:
                        seen.add(h.index)
                        stack.append(h)
        area = sum(bm.faces[i].calc_area() for i in isl)
        islands.append((isl, area))
    bm.free()
    return islands


def snow_slab(obj, faces, area, kind, seed, thick_scale=1.0, min_short=None, cuts_cap=3):
    """Rounded snow slab on top of `faces` (one flat island): copy -> extrude up -> bevel the top rim -> noise.
    Returns the new object (class snow) or None for thin strips (those get painted snow)."""
    me = obj.data
    src = bmesh.new()
    src.from_mesh(me)
    src.faces.ensure_lookup_table()
    bm = bmesh.new()
    vmap = {}
    for fi in faces:
        f = src.faces[fi]
        vs = []
        for v in f.verts:
            if v.index not in vmap:
                vmap[v.index] = bm.verts.new(v.co.copy())
            vs.append(vmap[v.index])
        try:
            bm.faces.new(vs)
        except ValueError:
            pass
    src.free()
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-4)
    bm.normal_update()
    if not bm.faces:
        bm.free()
        return None
    xs = [v.co.x for v in bm.verts]
    ys = [v.co.y for v in bm.verts]
    short = max(0.02, min(max(xs) - min(xs), max(ys) - min(ys)))
    if min_short is None:
        min_short = {"vehicle": 0.18, "tower": 0.6}.get(kind, 0.35)
    if short < min_short:
        bm.free()
        return None
    if kind == "vehicle":
        t = max(0.05, min(0.16, 0.05 + 0.05 * math.sqrt(area)))
    else:
        t = max(0.06, min(0.32, 0.05 + 0.03 * math.sqrt(area)))
    t = min(t * thick_scale, 0.9 * short)
    boundary = [e for e in bm.edges if e.is_boundary]
    cen = sum((v.co for v in bm.verts), Vector()) / len(bm.verts)
    grow = 0.0 if kind == "vehicle" else min(0.04, 0.2 * short)
    for v in {v for e in boundary for v in e.verts}:
        d = v.co - cen
        d.z = 0
        if d.length > 1e-6:
            v.co += d.normalized() * grow
    for f in bm.faces:                                # island faces up, whatever the source winding
        f.normal_update()
        if f.normal.z < 0:
            f.normal_flip()
    base_faces = list(bm.faces)
    ext = bmesh.ops.extrude_face_region(bm, geom=bm.faces[:])
    top_verts = [e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)]
    for v in top_verts:
        v.co.z += t
    bm.normal_update()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])   # closed now: consistent outward normals
    bm.normal_update()
    bottom = [f for f in base_faces if f.is_valid]           # the original island copy = the hidden underside
    bmesh.ops.delete(bm, geom=bottom, context="FACES_ONLY")
    top_set = set(top_verts)
    top_faces = [f for f in bm.faces if all(v in top_set for v in f.verts)]
    cuts = 0 if area < 2 else (1 if area < 20 else (2 if area < 120 else 3))
    cuts = min(cuts, cuts_cap)
    if cuts:
        bm.edges.index_update()                           # sorted: set order (memory addresses) varies per run
        edges = sorted({e for f in top_faces for e in f.edges if all(v in top_set for v in e.verts)},
                       key=lambda e: e.index)
        bmesh.ops.subdivide_edges(bm, edges=edges, cuts=cuts, use_grid_fill=True)
    top_set = {v for v in bm.verts if v.co.z > cen.z + t * 0.5}
    rim = [e for e in bm.edges if all(v in top_set for v in e.verts) and
           any(f.normal.z < 0.5 for f in e.link_faces) and any(f.normal.z >= 0.5 for f in e.link_faces)]
    off = min(0.85 * t, 0.3 * short)
    if rim and off > 0.005:
        try:
            bmesh.ops.bevel(bm, geom=rim, offset=off, offset_type="OFFSET", segments=3, profile=0.5,
                            affect="EDGES", clamp_overlap=True)
        except Exception:
            pass
    rnd = Vector((seed * 1.37, seed * 2.11, 0.3))
    for v in bm.verts:
        if v.co.z > cen.z + t * 0.95:
            v.co.z += (0.35 * t) * noise.noise(v.co * 0.55 + rnd)
    bm.normal_update()
    for f in bm.faces:                                # guard: faces of the top must face up
        if f.calc_center_median().z > cen.z + 0.6 * t and f.normal.z < -0.2:
            f.normal_flip()
    so = mesh_from_bm(bm, "Snow")
    bm.free()
    for p in so.data.polygons:
        p.use_smooth = True
    colour_snow(so)
    return so


def paint_snow_faces(obj, nz_min=0.80, z_range=None, coverage=1.0, seed=0):
    """Small up faces (ledges, sills, rails, the shaft cornices of towers) become snow-coloured (cheap).
    coverage < 1: only the faces where a 1.5 m noise field is above the matching threshold (patchy snow)."""
    me = obj.data
    cls = get_cls(me)
    faces = []
    off = Vector((seed * 0.61, seed * 0.29, 0.0))
    thr = 1.0 - 2.0 * coverage
    for p in me.polygons:
        if cls[p.index] in (CLS["body"], CLS["burnt"]) and p.normal.z >= nz_min:
            if z_range is None or z_range[0] <= p.center.z <= z_range[1]:
                if coverage >= 1.0 or noise.noise(p.center * 0.66 + off) * 1.6 > thr:
                    faces.append(p.index)
    data = get_col(me)
    for fi in faces:
        z = me.polygons[fi].center
        n = noise.noise(z * 0.7)
        c = Vector(SNOW).lerp(Vector(SNOW_DEEP), 0.5 + 0.5 * n) if n > 0 else Vector(SNOW).lerp(Vector(SNOW_SH), -0.35 * n)
        for li in me.polygons[fi].loop_indices:
            data[li * 4:li * 4 + 3] = c
        cls[fi] = CLS["snow"]
    set_col(me, data)
    set_cls(me, cls)
    return len(faces)


def colour_snow(obj, dirty=0.0, seed=0):
    """Snow colour per corner (snow / snow_deep / snow_shadow noise); `dirty` mixes toward grey slush."""
    me = obj.data
    if not me.materials:
        me.materials.append(palette.get_vcol_material())
    data = [1.0] * (len(me.loops) * 4)
    slush = Vector(palette.vcol_rgba("concrete_dark")[:3])
    off = Vector((seed * 0.73, seed * 1.9, 0))
    for p in me.polygons:
        for li, vi in zip(p.loop_indices, p.vertices):
            wp = me.vertices[vi].co
            n = noise.noise(wp * 0.7 + off)
            c = Vector(SNOW).lerp(Vector(SNOW_DEEP), 0.5 + 0.5 * n) if n > 0 else \
                Vector(SNOW).lerp(Vector(SNOW_SH), -0.35 * n)
            if dirty:
                c = c.lerp(slush, dirty * (0.5 + 0.5 * noise.noise(wp * 1.7 + off)))
            data[li * 4:li * 4 + 3] = c
    set_col(me, data)
    set_cls(me, [CLS["snow"]] * len(me.polygons))


def drift_strip(a, b, n, h0, w0, seed, sink=0.05, spacing=0.8):
    """Snow drift against a wall from `a` to `b` (outward normal `n`): smooth grid with a wobbly crest."""
    a, b, n = Vector(a), Vector(b), Vector(n)
    L = (b - a).length
    nu = max(4, int(L / spacing))
    nv = 5
    bm = bmesh.new()
    grid = []
    for i in range(nu + 1):
        u = i / nu
        p = a.lerp(b, u)
        wob = 0.75 + 0.35 * noise.noise(Vector((p.x * 0.35, p.y * 0.35, seed)))
        ends = smooth01(0.0, 0.12, u) * smooth01(0.0, 0.12, 1 - u)
        row = []
        for j in range(nv + 1):
            v = j / nv
            h = h0 * wob * (1 - v) ** 1.6 * (0.35 + 0.65 * ends)
            q = p + n * (-0.05 + v * w0 * wob) + Vector((0, 0, h - sink * v))
            row.append(bm.verts.new(q))
        grid.append(row)
    for i in range(nu):
        for j in range(nv):
            bm.faces.new((grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]))
    bm.normal_update()
    for f in bm.faces:
        if f.normal.z < 0:
            f.normal_flip()
    o = mesh_from_bm(bm, "Drift")
    bm.free()
    for p in o.data.polygons:
        p.use_smooth = True
    colour_snow(o, seed=seed)
    return o


def base_drifts(mn, mx, kind, seed, windward=(1, 2), spacing=0.8):
    """Drifts against the 4 walls of the footprint rectangle; deeper on the two windward sides (0 S, 1 E, 2 N, 3 W)."""
    sides = [((mn.x, mn.y), (mx.x, mn.y), (0, -1)), ((mx.x, mn.y), (mx.x, mx.y), (1, 0)),
             ((mx.x, mx.y), (mn.x, mx.y), (0, 1)), ((mn.x, mx.y), (mn.x, mn.y), (-1, 0))]
    out = []
    for k, (a, b, n) in enumerate(sides):
        wind = 1.0 if k in windward else 0.55
        h0 = (0.55 if kind != "vehicle" else 0.3) * wind
        w0 = 1.3 * wind + 0.4
        out.append(drift_strip(a + (0,), b + (0,), n + (0,), h0, w0, seed + k, spacing=spacing))
    return out


def mound(center, rx, ry, height, seed, sides=20, rings=5, sink=0.03, dirty=0.0):
    """Smooth snow mound (hd.mound) with rx / ry radii, coloured as snow."""
    o = hd.mound((center[0], center[1], center[2] if len(center) > 2 else 0.0), 1.0, height, name=None, seed=seed,
                 sides=sides, rings=rings, sink=sink, stretch=(rx, ry))
    colour_snow(o, dirty=dirty, seed=seed)
    return o


# ------------------------------------------------------------------------------------------------------------------
# AO + export
# ------------------------------------------------------------------------------------------------------------------
def bake(objs, kind, distance=None, samples=None, exclude=()):
    objs = [o for o in objs if o.type == "MESH" and not ex.is_col(o.name)]
    for o in objs:                    # the AO sample pattern follows the loop index: make it order-independent
        canonical_face_order(o)
    mn, mx = bounds(objs)
    size = max(mx - mn)
    if distance is None:
        distance = 1.2 if kind in ("tower", "building") else max(0.3, min(1.0, 0.25 * size))
    if samples is None:
        samples = 24 if tri_count(objs) > 40000 else 40
    t = hd.bake_ao(objs, distance=distance, samples=samples, ground=True, ground_z=0.0, exclude=exclude)
    # window panes: constant AO 0.98 (the window material does not use it; same rule as the M3 POIs);
    # slabs: constant AO 0.25 (W0 contract: interior slabs <= 0.3, the cut floor plan reads darker than outside)
    for o in objs:
        me = o.data
        wi = [i for i, m in enumerate(me.materials) if m and m.name == "window"]
        cls = get_cls(me)
        if not wi and CLS["slab"] not in cls:
            continue
        data = get_col(me)
        for p in me.polygons:
            if p.material_index in wi:
                a = 0.98
            elif cls[p.index] == CLS["slab"]:
                a = SLAB_AO
            else:
                continue
            for li in p.loop_indices:
                data[li * 4 + 3] = a
        set_col(me, data)
    return t


def empty(name, loc, parent=None, yaw_deg=0.0, props=None):
    """Anchor Empty (identity rotation unless a yaw is given for Spawn-like anchors)."""
    e = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(e)
    e.empty_display_size = 0.2
    e.location = Vector(loc)
    if yaw_deg:
        e.rotation_euler = (0.0, 0.0, math.radians(yaw_deg))
    if parent is not None:
        e.parent = parent
    for k, v in (props or {}).items():
        e[k] = v
    return e


def godot_xyz(p):
    """Blender (x, y, z) -> Godot (x, z, -y), rounded to mm (for extras / manifests)."""
    return [round(p[0], 3), round(p[2], 3), round(-p[1], 3)]


def canonical_face_order(obj):
    """Sort the faces by (material, centre, normal) so the exported index buffer does not depend on the order in
    which bmesh operators (and Python sets of faces) produced them: a rebuild is then byte-identical and
    export_glb leaves the .glb untouched."""
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    def key(f):
        c = f.calc_center_median()
        return (f.material_index, round(c.z, 4), round(c.y, 4), round(c.x, 4),
                round(f.normal.z, 3), round(f.normal.y, 3), round(f.normal.x, 3), len(f.verts))
    bm.faces.ensure_lookup_table()
    order = sorted(range(len(bm.faces)), key=lambda i: key(bm.faces[i]))
    rank = [0] * len(order)
    for r, i in enumerate(order):
        rank[i] = r
    bm.faces.index_update()
    bm.faces.sort(key=lambda f: rank[f.index])          # bmesh wants a number per face
    bm.faces.index_update()
    bm.to_mesh(me)
    bm.free()
    me.update()


def export_glb(path, name):
    """Scene sanity check (lib/export) + GLB export (no .blend). Writes a Godot .import template next to a NEW .glb."""
    import filecmp
    import shutil
    import tempfile
    from pathlib import Path
    for o in bpy.context.scene.objects:
        if o.type == "MESH":
            strip_attributes(o)
            canonical_face_order(o)
    for img in list(bpy.data.images):
        bpy.data.images.remove(img)
    _IMG_CACHE.clear()
    ex._purge_orphans()
    for o in bpy.context.scene.objects:            # mesh datablock names = object names (no `.001` in the glTF)
        if o.type == "MESH" and o.data.name != o.name:
            other = bpy.data.meshes.get(o.name)
            if other is not None and other != o.data:
                other.name = "zz_orphan_" + other.name
            o.data.name = o.name
    ex.sanity_check_scene(name)
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp_dir = tempfile.mkdtemp(prefix="ventisca_city_")
    tmp = Path(tmp_dir) / path.name
    with ex.quiet():
        ex.export_gltf(tmp)
    unchanged = path.exists() and filecmp.cmp(str(tmp), str(path), shallow=False)
    if not unchanged:
        shutil.copyfile(str(tmp), str(path))
    shutil.rmtree(tmp_dir, ignore_errors=True)
    write_city_import(path)
    return unchanged


CITY_IMPORT_SCRIPT = "res://assets/models/city/city_import.gd"


def write_city_import(glb):
    """The Godot .import of a city .glb: the `prop` template of lib/export with the city post-import script (copies
    the root metadata from Base / Body / Prop to the scene root). An existing file (with its uid) is only patched."""
    import re as _re
    from pathlib import Path
    p = Path(str(glb) + ".import")
    line = 'import_script/path="%s"' % CITY_IMPORT_SCRIPT
    if not p.exists():
        p.write_text(ex.import_file_text("prop").replace('import_script/path=""', line))
        return p
    txt = p.read_text()
    new = _re.sub(r'^import_script/path=.*$', line, txt, flags=_re.M)
    if new != txt:
        p.write_text(new)
    return p
