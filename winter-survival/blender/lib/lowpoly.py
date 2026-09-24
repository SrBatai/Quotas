"""Low-poly construction helpers (ASSET_SPEC_V2 §2).

Everything is built in *world* (asset) coordinates with a `MeshBuilder`, then turned into an object
whose origin is the requested pivot (`to_object`). Faces are auto-oriented outward (away from the
solid's centre, or toward an explicit `facing` direction for open quads), so winding mistakes cannot
produce inverted normals. All polygons are flat shaded; there are no UVs. Colour = the palette name of
each face, baked by `palette.assign` into the `Col` corner attribute + one `palette_vcol` material
(named exceptions such as `window` / `ember` keep their own material).

Front axis (decision C1): every asset with a front faces FRONT = -Y Blender (= +Z Godot = MODEL_FRONT).
Scripts written for the slice convention (+Y front) call `new_scene(authored_front="+Y")`: every mesh,
empty, pivot and collision object is then rotated 180 degrees about Z when it is created (to_object /
add_empty / collision_*), so the asset keeps its exact shape and handedness and its front ends up at -Y.
New scripts author directly in -Y (the default) and nothing is rotated.
"""
import math
import random

import bpy
from mathutils import Matrix, Vector

from . import palette

FRONT = Vector((0.0, -1.0, 0.0))          # v2: -Y Blender = +Z Godot (Vector3.MODEL_FRONT)
RIGHT = Vector((-1.0, 0.0, 0.0))          # character's right = -X (left = +X, like SkeletonProfileHumanoid)
LEGACY_FRONT = Vector((0.0, 1.0, 0.0))    # slice convention (+Y), converted by new_scene(authored_front="+Y")

# World-space pivot of every object created through this module (reset by new_scene()).
_PIVOTS = {}
# Transform applied when objects are created (identity, or 180 deg about Z for +Y-authored scripts).
_STATE = {"xf": Matrix.Identity(4), "authored_front": "-Y"}


# ---------------------------------------------------------------------------------------------
# scene
# ---------------------------------------------------------------------------------------------
def new_scene(authored_front="-Y"):
    """Empty scene, metric units, 1 BU = 1 m. `authored_front`: "-Y" (v2 default, geometry already
    faces FRONT) or "+Y" (slice-era script: rotate everything 180 degrees about Z at creation)."""
    if authored_front not in ("-Y", "+Y"):
        raise ValueError("authored_front must be '-Y' or '+Y'")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _PIVOTS.clear()
    _STATE["authored_front"] = authored_front
    _STATE["xf"] = Matrix.Rotation(math.pi, 4, 'Z') if authored_front == "+Y" else Matrix.Identity(4)
    scene = bpy.context.scene
    scene.unit_settings.system = 'METRIC'
    scene.unit_settings.scale_length = 1.0
    return scene


def front_xf():
    """The creation transform of the current scene (identity or 180 degrees about Z)."""
    return _STATE["xf"].copy()


def to_front(p):
    """Map a point given in the script's authoring convention to final (FRONT = -Y) coordinates."""
    return _STATE["xf"] @ vec(p)


def rng(seed):
    return random.Random(seed)


# ---------------------------------------------------------------------------------------------
# math helpers
# ---------------------------------------------------------------------------------------------
def vec(p):
    return p.copy() if isinstance(p, Vector) else Vector(p)


def newell(pts):
    """Unnormalised polygon normal (length = 2 * area)."""
    n = Vector((0.0, 0.0, 0.0))
    k = len(pts)
    for i in range(k):
        a = pts[i]
        b = pts[(i + 1) % k]
        n.x += (a.y - b.y) * (a.z + b.z)
        n.y += (a.z - b.z) * (a.x + b.x)
        n.z += (a.x - b.x) * (a.y + b.y)
    return n


def rot(axis, deg, origin=(0, 0, 0)):
    """4x4 rotation of `deg` degrees about `axis` ('X','Y','Z' or a vector) through `origin`."""
    o = Vector(origin)
    return Matrix.Translation(o) @ Matrix.Rotation(math.radians(deg), 4, axis) @ Matrix.Translation(-o)


def move(offset):
    return Matrix.Translation(Vector(offset))


def perp_basis(axis):
    """Orthonormal (u, w) perpendicular to `axis`. For non-vertical axes u is the 'most upward'
    direction (so angle 0 of a ring points up); for vertical axes u = +X, w = +Y (ccw from above)."""
    a = vec(axis).normalized()
    ref = Vector((0, 0, 1)) if abs(a.z) < 0.99 else Vector((1, 0, 0))
    u = (ref - a * ref.dot(a)).normalized()
    w = a.cross(u).normalized()
    return u, w


def ring(center, axis, radius, sides, phase_deg=0.0, radii=None):
    """Polygon ring of `sides` points around `axis`. `radius` may be a float or (ru, rw) ellipse;
    `radii` (list) overrides the radius per vertex (for jagged tiers)."""
    c = vec(center)
    u, w = perp_basis(axis)
    ru, rw = (radius, radius) if not isinstance(radius, (tuple, list)) else radius
    pts = []
    for i in range(sides):
        t = math.radians(phase_deg) + 2.0 * math.pi * i / sides
        k = radii[i] if radii else 1.0
        pts.append(c + (u * (math.cos(t) * ru) + w * (math.sin(t) * rw)) * k)
    return pts


# ---------------------------------------------------------------------------------------------
# icosphere
# ---------------------------------------------------------------------------------------------
def icosphere_data(subdiv):
    """Unit icosphere. subdiv 0 = 20 faces (icosahedron), subdiv 1 = 80 faces."""
    t = (1.0 + math.sqrt(5.0)) / 2.0
    verts = [Vector(p).normalized() for p in (
        (-1, t, 0), (1, t, 0), (-1, -t, 0), (1, -t, 0),
        (0, -1, t), (0, 1, t), (0, -1, -t), (0, 1, -t),
        (t, 0, -1), (t, 0, 1), (-t, 0, -1), (-t, 0, 1))]
    faces = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11),
             (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6), (7, 1, 8),
             (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9),
             (4, 9, 5), (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1)]
    for _ in range(subdiv):
        cache = {}

        def mid(a, b):
            key = (min(a, b), max(a, b))
            if key not in cache:
                verts.append(((verts[a] + verts[b]) * 0.5).normalized())
                cache[key] = len(verts) - 1
            return cache[key]

        nf = []
        for a, b, c in faces:
            ab, bc, ca = mid(a, b), mid(b, c), mid(c, a)
            nf += [(a, ab, ca), (b, bc, ab), (c, ca, bc), (ab, bc, ca)]
        faces = nf
    return verts, faces


# ---------------------------------------------------------------------------------------------
# mesh builder
# ---------------------------------------------------------------------------------------------
BOX_FACES = {  # corner index = xbit + 2*ybit + 4*zbit
    '-z': (0, 2, 3, 1), '+z': (4, 5, 7, 6),
    '-y': (0, 1, 5, 4), '+y': (2, 6, 7, 3),
    '-x': (0, 4, 6, 2), '+x': (1, 3, 7, 5),
}
BOX_ORDER = ('-z', '+z', '-y', '+y', '-x', '+x')


class MeshBuilder:
    def __init__(self):
        self.verts = []
        self.faces = []  # [idx tuple, material name, snowable]

    # -- low level ---------------------------------------------------------------------------
    def _v(self, p, xf=None):
        p = vec(p)
        if xf is not None:
            p = xf @ p
        self.verts.append(p)
        return len(self.verts) - 1

    def _pts(self, face):
        return [self.verts[i] for i in face[0]]

    def normal(self, fi):
        n = newell(self._pts(self.faces[fi]))
        return n.normalized() if n.length > 1e-12 else n

    def center(self, fi):
        pts = self._pts(self.faces[fi])
        return sum(pts, Vector()) / len(pts)

    def add_face(self, idx, mat, snow=False, inside=None, facing=None):
        idx = tuple(idx)
        pts = [self.verts[i] for i in idx]
        n = newell(pts)
        if n.length < 1e-10:
            raise ValueError("degenerate face in %s" % (mat,))
        if facing is not None:
            if n.dot(vec(facing)) < 0:
                idx = tuple(reversed(idx))
        elif inside is not None:
            c = sum(pts, Vector()) / len(pts)
            if n.dot(c - vec(inside)) < 0:
                idx = tuple(reversed(idx))
        self.faces.append([idx, mat, snow])
        return len(self.faces) - 1

    # -- primitives ----------------------------------------------------------------------------
    def poly(self, pts, mat, facing, snow=False, xf=None):
        """One open polygon, normal oriented toward `facing`."""
        idx = [self._v(p, xf) for p in pts]
        f = vec(facing)
        if xf is not None:
            f = xf.to_3x3() @ f
        return [self.add_face(idx, mat, snow, facing=f)]

    def solid(self, pts, faces, mat, snow=False, xf=None, inside=None):
        """Closed, star-shaped solid; every face is oriented away from `inside` (default centroid).
        `mat` is a name or a list (one per face)."""
        base = len(self.verts)
        for p in pts:
            self._v(p, xf)
        wpts = self.verts[base:]
        ins = sum(wpts, Vector()) / len(wpts) if inside is None else (
            (xf @ vec(inside)) if xf is not None else vec(inside))
        out = []
        for k, f in enumerate(faces):
            m = mat[k] if isinstance(mat, (list, tuple)) else mat
            out.append(self.add_face([base + i for i in f], m, snow, inside=ins))
        return out

    def hexa(self, corners, mat, snow=False, xf=None, skip=(), mats=None):
        """Eight-corner hexahedron (corner index = xbit + 2*ybit + 4*zbit)."""
        keys = [k for k in BOX_ORDER if k not in skip]
        faces = [BOX_FACES[k] for k in keys]
        fm = [(mats or {}).get(k, mat) for k in keys]
        c = sum((vec(p) for p in corners), Vector()) / 8.0
        return self.solid(corners, faces, fm, snow, xf, inside=c)

    def box(self, mn, mx, mat, snow=False, xf=None, skip=(), mats=None):
        corners = [(mx[0] if i & 1 else mn[0], mx[1] if i & 2 else mn[1], mx[2] if i & 4 else mn[2])
                   for i in range(8)]
        return self.hexa(corners, mat, snow, xf, skip, mats)

    def cbox(self, center, size, mat, **kw):
        c, s = vec(center), vec(size) * 0.5
        return self.box(c - s, c + s, mat, **kw)

    def tapered_box(self, z0, z1, bot, top, mat, center=(0, 0), top_center=None, **kw):
        """Box from z0 to z1 with bottom size bot=(sx,sy) and top size top=(sx,sy)."""
        cx, cy = center
        tx, ty = top_center if top_center else center
        corners = []
        for i in range(8):
            up = bool(i & 4)
            sx, sy = (top if up else bot)
            ox, oy = (tx, ty) if up else (cx, cy)
            corners.append((ox + (sx / 2 if i & 1 else -sx / 2), oy + (sy / 2 if i & 2 else -sy / 2),
                            z1 if up else z0))
        return self.hexa(corners, mat, **kw)

    def loft(self, rings, mat, cap_start=True, cap_end=True, snow=False, xf=None, side_mats=None,
             cap_mats=(None, None), inside=None, seg_facing=None):
        """Skin consecutive rings (lists of points, equal counts; a 1-point ring is an apex).
        side_mats: optional list, one material per segment. Faces orient away from the local axis
        (midpoint of the two ring centroids), or away from `inside` when given (whole solid), or
        toward seg_facing[s] (a direction) when that entry is not None (e.g. concave undersides)."""
        rings = [[(xf @ vec(p)) if xf is not None else vec(p) for p in r] for r in rings]
        idx = []
        for r in rings:
            idx.append([self._v(p) for p in r])
        cents = [sum(r, Vector()) / len(r) for r in rings]
        out = []
        for s in range(len(rings) - 1):
            a, b = idx[s], idx[s + 1]
            m = side_mats[s] if side_mats else mat
            ins = vec(inside) if inside is not None else (cents[s] + cents[s + 1]) * 0.5
            fac = seg_facing[s] if seg_facing else None
            kw = dict(facing=fac) if fac is not None else dict(inside=ins)
            if len(a) == 1 or len(b) == 1:
                apex, rr = (a[0], b) if len(a) == 1 else (b[0], a)
                n = len(rr)
                for j in range(n):
                    out.append(self.add_face((rr[j], rr[(j + 1) % n], apex), m, snow, **kw))
            else:
                n = len(a)
                for j in range(n):
                    out.append(self.add_face((a[j], a[(j + 1) % n], b[(j + 1) % n], b[j]), m, snow, **kw))
        if cap_start and len(rings[0]) > 2:
            out.append(self.add_face(idx[0], cap_mats[0] or mat, snow,
                                     inside=vec(inside) if inside is not None else cents[1]))
        if cap_end and len(rings[-1]) > 2:
            out.append(self.add_face(idx[-1], cap_mats[1] or mat, snow,
                                     inside=vec(inside) if inside is not None else cents[-2]))
        return out

    def cylinder(self, p0, p1, r0, r1, sides, mat, cap0=True, cap1=True, phase=0.0, snow=False,
                 cap_mats=(None, None), xf=None):
        p0, p1 = vec(p0), vec(p1)
        axis = p1 - p0
        rings = [ring(p0, axis, r0, sides, phase), ring(p1, axis, r1, sides, phase)]
        if r1 <= 1e-6:
            rings[1] = [p1]
        return self.loft(rings, mat, cap0, cap1, snow, xf, cap_mats=cap_mats)

    def blob(self, center, radii, mat, subdiv=1, jitter=0.08, rnd=None, clamp_z=None, drop_bottom=False,
             snow=False, xf=None):
        """Jittered icosphere (radial jitter ±jitter, then scaled by radii). Vertices below clamp_z are
        flattened onto it; with drop_bottom the resulting flat bottom faces are removed."""
        rnd = rnd or random.Random(0)
        uv, uf = icosphere_data(subdiv)
        c = vec(center)
        rx, ry, rz = radii if isinstance(radii, (tuple, list)) else (radii,) * 3
        pts = []
        for p in uv:
            k = 1.0 + rnd.uniform(-jitter, jitter)
            q = Vector((p.x * rx * k, p.y * ry * k, p.z * rz * k)) + c
            if clamp_z is not None and q.z < clamp_z:
                q.z = clamp_z
            pts.append(q)
        faces = uf
        if clamp_z is not None and drop_bottom:
            faces = [f for f in uf if not all(abs(pts[i].z - clamp_z) < 1e-9 for i in f)]
        return self.solid(pts, faces, mat, snow, xf, inside=c if clamp_z is None or c.z > clamp_z
                          else Vector((c.x, c.y, clamp_z + 0.01)))

    def prism(self, profile, axis_from, axis_to, mat, snow=False, mats_caps=None, xf=None):
        """Extrude a planar polygon `profile` (list of 3D points on the start plane) by the vector
        axis_to - axis_from. Good for pentagon boards, triangular gables and wedges."""
        d = vec(axis_to) - vec(axis_from)
        r0 = [vec(p) for p in profile]
        r1 = [p + d for p in r0]
        return self.loft([r0, r1], mat, True, True, snow, xf,
                         cap_mats=mats_caps if mats_caps else (None, None))

    # -- recolouring ---------------------------------------------------------------------------
    def recolor(self, pred, mat, faces=None, snowable_only=False):
        """Set `mat` on faces for which pred(normal, center, current_mat) is true."""
        rng_ = range(len(self.faces)) if faces is None else faces
        for fi in rng_:
            f = self.faces[fi]
            if snowable_only and not f[2]:
                continue
            if pred(self.normal(fi), self.center(fi), f[1]):
                f[1] = mat

    def snow(self, threshold=0.55, faces=None, mat='snow'):
        """ASSET_SPEC_V2 §2.5 snow rule on the faces flagged snowable."""
        self.recolor(lambda n, c, m: n.z > threshold, mat, faces, snowable_only=True)

    def extend(self, other):
        base = len(self.verts)
        self.verts.extend(v.copy() for v in other.verts)
        for idx, m, s in other.faces:
            self.faces.append([tuple(i + base for i in idx), m, s])

    def transform(self, xf, verts_from=0):
        for i in range(verts_from, len(self.verts)):
            self.verts[i] = xf @ self.verts[i]

    def triangulate_nonplanar(self, tol=1e-5):
        """Split polygons whose vertices are not coplanar into triangles (shorter diagonal for quads),
        so every exported flat-shaded triangle carries its own exact normal (same triangle count)."""
        out = []
        for idx, m, s in self.faces:
            if len(idx) > 3:
                pts = [self.verts[i] for i in idx]
                n = newell(pts)
                if n.length > 1e-12:
                    n = n.normalized()
                    c = sum(pts, Vector()) / len(pts)
                    if max(abs((p - c).dot(n)) for p in pts) > tol:
                        if len(idx) == 4:
                            a, b, cc, d = idx
                            if (self.verts[a] - self.verts[cc]).length <= (self.verts[b] - self.verts[d]).length:
                                out += [[(a, b, cc), m, s], [(a, cc, d), m, s]]
                            else:
                                out += [[(a, b, d), m, s], [(b, cc, d), m, s]]
                        else:
                            out += [[(idx[0], idx[k], idx[k + 1]), m, s] for k in range(1, len(idx) - 1)]
                        continue
            out.append([idx, m, s])
        self.faces = out

    def tri_count(self):
        return sum(len(f[0]) - 2 for f in self.faces)

    def bounds(self):
        xs = [v.x for v in self.verts]
        ys = [v.y for v in self.verts]
        zs = [v.z for v in self.verts]
        return Vector((min(xs), min(ys), min(zs))), Vector((max(xs), max(ys), max(zs)))


# ---------------------------------------------------------------------------------------------
# objects
# ---------------------------------------------------------------------------------------------
def world_pivot(obj):
    """Final (FRONT = -Y) world pivot of an object created by this module."""
    return _PIVOTS[obj.name].copy()


def _link(obj, parent, pivot):
    bpy.context.scene.collection.objects.link(obj)
    if obj.name in _PIVOTS:
        raise RuntimeError("duplicate object name %s" % obj.name)
    _PIVOTS[obj.name] = vec(pivot)
    if parent is not None:
        obj.parent = parent
        obj.matrix_parent_inverse = Matrix.Identity(4)
        obj.location = vec(pivot) - _PIVOTS[parent.name]
    else:
        obj.location = vec(pivot)


def to_object(mb, name, pivot=(0, 0, 0), parent=None):
    """Create a mesh object from builder `mb` (world coords of the authoring convention) with its origin
    at `pivot`. Colours: palette_vcol + `Col` corner colours, exceptions as extra materials. `mb` itself is
    not modified (the front transform is applied to copies)."""
    if bpy.data.objects.get(name) is not None:
        raise RuntimeError("object %s already exists" % name)
    xf = _STATE["xf"]
    pv = xf @ vec(pivot)
    mb.triangulate_nonplanar()
    me = bpy.data.meshes.new(name)
    me.from_pydata([(xf @ v) - pv for v in mb.verts], [], [f[0] for f in mb.faces])
    me.polygons.foreach_set('use_smooth', [False] * len(me.polygons))
    if me.validate(verbose=False):
        print("WARNING: mesh %s needed validation fixes" % name)
    if len(me.polygons) != len(mb.faces):
        raise RuntimeError("mesh %s lost faces during validation" % name)
    palette.assign(me, [f[1] for f in mb.faces])
    me.update()
    obj = bpy.data.objects.new(name, me)
    if obj.name != name:
        raise RuntimeError("name collision %s -> %s" % (name, obj.name))
    _link(obj, parent, pv)
    return obj


def add_empty(name, pivot, parent=None, rotation_deg=(0, 0, 0), size=0.1, final_rotation_deg=None):
    """Empty at `pivot` (authoring convention).

    `rotation_deg` is relative to the model's own front convention, so it is conjugated by the front turn:
    an unrotated anchor stays unrotated (its local -Y = the model front in v2). `final_rotation_deg` sets
    the exported XYZ Euler rotation directly (for sockets whose children are NOT front-converted, e.g. the
    player's ToolSocket holding tools authored in the weapon convention)."""
    from mathutils import Euler
    obj = bpy.data.objects.new(name, None)
    if obj.name != name:
        raise RuntimeError("name collision %s -> %s" % (name, obj.name))
    obj.empty_display_type = 'PLAIN_AXES'
    obj.empty_display_size = size
    xf = _STATE["xf"]
    _link(obj, parent, xf @ vec(pivot))
    if final_rotation_deg is not None:
        r = Euler(tuple(math.radians(a) for a in final_rotation_deg), 'XYZ').to_matrix()
    else:
        x3 = xf.to_3x3()
        r = x3 @ Euler(tuple(math.radians(a) for a in rotation_deg), 'XYZ').to_matrix() @ x3.inverted()
    obj.rotation_euler = r.to_euler('XYZ')
    return obj


def collision_box(name, mn, mx):
    """Convex collision box (`<name>-convcolonly`), top level, no material (authoring coordinates)."""
    mb = MeshBuilder()
    mb.box(mn, mx, None)
    return _collision(mb, name)


def collision_prism(name, pts, faces):
    mb = MeshBuilder()
    mb.solid(pts, faces, None)
    return _collision(mb, name)


def _collision(mb, name):
    full = name if name.endswith("-convcolonly") else name + "-convcolonly"
    xf = _STATE["xf"]
    me = bpy.data.meshes.new(full)
    me.from_pydata([xf @ v for v in mb.verts], [], [f[0] for f in mb.faces])
    me.polygons.foreach_set('use_smooth', [False] * len(me.polygons))
    me.validate(verbose=False)
    me.update()
    obj = bpy.data.objects.new(full, me)
    _link(obj, None, (0, 0, 0))
    return obj


def tri_count(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons) if obj.type == 'MESH' else 0


def scene_tris(exclude_col=True):
    return sum(tri_count(o) for o in bpy.context.scene.objects
               if o.type == 'MESH' and not (exclude_col and o.name.endswith('-convcolonly')))


# ---------------------------------------------------------------------------------------------
# shaping helpers
# ---------------------------------------------------------------------------------------------
def fit_bounds(mb, dims, verts_from=0, ground=True):
    """Scale/translate verts[verts_from:] so their bounding box is exactly `dims` (X, Y, Z), centred
    on x = y = 0, with the bottom at z = 0 (ground=True)."""
    vs = mb.verts[verts_from:]
    mn = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    mx = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    size = mx - mn
    c = (mn + mx) * 0.5
    for v in vs:
        v.x = (v.x - c.x) * dims[0] / size.x
        v.y = (v.y - c.y) * dims[1] / size.y
        v.z = (v.z - mn.z) * dims[2] / size.z if ground else (v.z - c.z) * dims[2] / size.z


def clamp_ground(mb, verts_from=0, z=0.0):
    for v in mb.verts[verts_from:]:
        if v.z < z:
            v.z = z


def stone_rule(mb, faces=None, snow=0.55, dark=0.1):
    """Rock colouring (slice ASSET_SPEC §4.7): snow on top, stone_dark on steep/under faces, stone else."""
    rng_ = range(len(mb.faces)) if faces is None else faces
    for fi in rng_:
        nz = mb.normal(fi).z
        mb.faces[fi][1] = "snow" if nz > snow else ("stone_dark" if nz < dark else "stone")


def rrect(center, a, b, chamfer, plane='XY'):
    """8-point chamfered rectangle (half sizes a, b) around `center`, in the XY plane (vertical axis) or
    the XZ plane (axis along Y; a = half width in X, b = half height in Z)."""
    c = vec(center)
    ch = min(chamfer, a * 0.95, b * 0.95)
    pts2 = [(a, b - ch), (a - ch, b), (-a + ch, b), (-a, b - ch),
            (-a, -b + ch), (-a + ch, -b), (a - ch, -b), (a, -b + ch)]
    if plane == 'XY':
        return [c + Vector((x, y, 0)) for x, y in pts2]
    return [c + Vector((x, 0, z)) for x, z in pts2]


def body_ring(y, half_w, z_bot, z_top, chamfer=0.05):
    """Chamfered cross-section for quadruped bodies (axis along Y)."""
    return rrect((0, y, (z_bot + z_top) * 0.5), half_w, (z_top - z_bot) * 0.5, chamfer, 'XZ')
