"""Cut-ready stage (A1, docs/research/09 §3 "corte urbano"): storeys, one closed slab per floor, closed-volume and
cut-view tests, tower floor groups and the shadow proxy.

The corte urbano shader discards every fragment above y_cut = base_y + ground_h + k * floor_h + stub (k = the
player's storey) and paints the back faces seen through the cut with `cap_color`. A building then reads as a floor
plan only if (a) its facade is closed (from inside a storey no horizontal line of sight escapes) and (b) every storey
has a slab whose top is at exactly ground_h + k * floor_h. Kenney / Quaternius shells have neither slabs nor a
guaranteed closed shell, so this module:
  * finds the storeys (window rows -> floor_h, ground_h; towers: the detected floor period),
  * builds a slab per floor from the section of the shell at that height: the largest closed section loop,
    simplified and inset, validated by an enclosure ray test (every point of it must be surrounded by the shell);
    fallback: a raster of enclosed cells merged into rectangles,
  * closes the bottom (a ground slab at z = 0) and tests closure / the cut view (also used by verify_assets.py),
  * splits towers into floor groups at storey lines and builds a low-poly shadow proxy (stacked prisms).
"""
import math

import bmesh
from mathutils import Vector
from mathutils.bvhtree import BVHTree

from lib import palette

from . import winterize as W

SLAB_T = 0.20           # slab thickness (m)
SLAB_LIFT = 0.03        # slab top = floor level + 3 cm: clear of the source's own coplanar storey-module faces
SLAB_INSET = 0.06       # slab edge inside the shell (m)
STUB = 0.40             # corte urbano stub above the slab (doc 09 §3.2)


# ------------------------------------------------------------------------------------------------------------------
# BVH / enclosure
# ------------------------------------------------------------------------------------------------------------------
def bvh_of(objs):
    verts, polys = [], []
    for o in objs:
        mw = o.matrix_world
        base = len(verts)
        verts += [mw @ v.co for v in o.data.vertices]
        polys += [tuple(base + i for i in p.vertices) for p in o.data.polygons]
    return BVHTree.FromPolygons(verts, polys, epsilon=0.0)


HDIRS4 = [Vector((1, 0, 0)), Vector((-1, 0, 0)), Vector((0, 1, 0)), Vector((0, -1, 0))]
HDIRS16 = [Vector((math.cos(2 * math.pi * k / 16), math.sin(2 * math.pi * k / 16), 0.0)) for k in range(16)]


def enclosed(bvh, p, reach, dirs=HDIRS4, up=True):
    """True when rays from p in every horizontal direction (and straight up) hit the shell within `reach`."""
    for d in dirs:
        if bvh.ray_cast(p, d, reach)[0] is None:
            return False
    if up and bvh.ray_cast(p, Vector((0, 0, 1)), 400.0)[0] is None:
        return False
    return True


# ------------------------------------------------------------------------------------------------------------------
# 2D polygon helpers
# ------------------------------------------------------------------------------------------------------------------
def poly_area(pts):
    return 0.5 * sum(pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1]
                     for i in range(len(pts)))


def dp_simplify_closed(pts, tol):
    """Douglas-Peucker on a closed polygon (split at the two farthest-apart vertices)."""
    n = len(pts)
    if n <= 4:
        return pts

    def dp(seq):
        if len(seq) < 3:
            return seq
        a, b = Vector(seq[0]), Vector(seq[-1])
        ab = b - a
        L = ab.length
        best, bi = -1.0, 0
        for i in range(1, len(seq) - 1):
            p = Vector(seq[i])
            d = abs(ab.x * (a.y - p.y) - ab.y * (a.x - p.x)) / L if L > 1e-9 else (p - a).length
            if d > best:
                best, bi = d, i
        if best > tol:
            left = dp(seq[:bi + 1])
            right = dp(seq[bi:])
            return left[:-1] + right
        return [seq[0], seq[-1]]
    i0 = 0
    far = max(range(n), key=lambda i: (Vector(pts[i]) - Vector(pts[0])).length)
    a = pts[i0:far + 1]
    b = pts[far:] + pts[:1]
    out = dp(a)[:-1] + dp(b)[:-1]
    # drop collinear leftovers
    clean = []
    for i, p in enumerate(out):
        q, r = Vector(out[i - 1]), Vector(out[(i + 1) % len(out)])
        v = Vector(p)
        if ((v - q).length > 1e-4 and abs((v - q).x * (r - v).y - (v - q).y * (r - v).x) > 1e-6):
            clean.append(p)
    return clean if len(clean) >= 3 else out


def inset_polygon(pts, d):
    """Miter inset of a CCW simple polygon by d (inward = left of each edge). Miters are clamped at 3 d."""
    n = len(pts)
    out = []
    for i in range(n):
        p0, p1, p2 = Vector(pts[i - 1]), Vector(pts[i]), Vector(pts[(i + 1) % n])
        e0 = (p1 - p0).normalized()
        e1 = (p2 - p1).normalized()
        n0 = Vector((-e0.y, e0.x))
        n1 = Vector((-e1.y, e1.x))
        bis = n0 + n1
        if bis.length < 1e-6:
            bis = n0
        bis.normalize()
        cosh = max(0.33, bis.dot(n1))
        q = p1 + bis * (d / cosh)
        out.append((q.x, q.y))
    return out


def point_in_poly(x, y, pts):
    inside = False
    n = len(pts)
    for i in range(n):
        x0, y0 = pts[i]
        x1, y1 = pts[(i + 1) % n]
        if (y0 > y) != (y1 > y) and x < x0 + (y - y0) * (x1 - x0) / (y1 - y0):
            inside = not inside
    return inside


def section_loops(obj, z):
    """Closed section loops of the mesh at height z: [(pts CCW, area)] sorted by area (largest first)."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    res = bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], dist=1e-6,
                                 plane_co=(0, 0, z), plane_no=(0, 0, 1))
    edges = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
    adj = {}
    for e in edges:
        a, b = e.verts
        adj.setdefault(a, []).append(b)
        adj.setdefault(b, []).append(a)
    seen, loops = set(), []
    for v0 in adj:
        if v0 in seen or len(adj[v0]) != 2:
            continue
        loop, prev, cur, closed = [v0], None, v0, False
        seen.add(v0)
        while True:
            nxt = [w for w in adj[cur] if w is not prev]
            if len(adj[cur]) != 2 or not nxt:
                break
            w = nxt[0]
            if w is v0:
                closed = True
                break
            if w in seen:
                break
            loop.append(w)
            seen.add(w)
            prev, cur = cur, w
        if closed and len(loop) >= 3:
            pts = [(v.co.x, v.co.y) for v in loop]
            a = poly_area(pts)
            if a < 0:
                pts.reverse()
            loops.append((pts, abs(a)))
    bm.free()
    loops.sort(key=lambda t: -t[1])
    return loops


# ------------------------------------------------------------------------------------------------------------------
# storeys
# ------------------------------------------------------------------------------------------------------------------
def window_rows(obj):
    """Rows of vertical window faces: [(z_bottom, z_top)] sorted, merging overlapping z ranges."""
    me = obj.data
    cls = W.get_cls(me)
    spans = []
    for p in me.polygons:
        if cls[p.index] == W.CLS["window"] and abs(p.normal.z) < 0.35:
            zs = [me.vertices[i].co.z for i in p.vertices]
            spans.append((min(zs), max(zs)))
    spans.sort()
    rows = []
    for a, b in spans:
        if rows and a < rows[-1][1] - 0.05:
            rows[-1] = (rows[-1][0], max(rows[-1][1], b))
        else:
            rows.append((a, b))
    return rows


def storeys(obj, floor_h, ground_h=None, roof_z=None, min_top_gap=1.2, roof_frac=0.5):
    """Storey table: floor levels z_k = ground_h + k * floor_h below the roof. ground_h: given, or the first window
    row bottom above 3 m minus a sill of 0.9 m snapped to the floor period."""
    mn, mx = W.bounds(obj)
    if roof_z is None:
        roof_z = main_roof_z(obj, roof_frac)
    if ground_h is None:
        rows = window_rows(obj)
        cand = [a - 0.9 for a, b in rows if a - 0.9 >= 2.8]
        ground_h = cand[0] if cand else max(3.2, floor_h)
        ground_h = max(3.0, min(ground_h, 6.5))
    levels = []
    k = 0
    while True:
        z = ground_h + k * floor_h
        if z > roof_z - min_top_gap:
            break
        levels.append(round(z, 4))
        k += 1
    return {"floor_h": round(floor_h, 4), "ground_h": round(ground_h, 4), "levels": levels,
            "floors": len(levels) + 1, "roof_z": round(roof_z, 3), "height": round(mx.z, 3)}


def podium_level(obj, lo=2.8, hi=7.0, min_frac=0.3):
    """Height of the biggest horizontal level (either orientation) between lo and hi covering >= min_frac of the
    footprint box: the podium top / first structural floor of a tower, or None."""
    mn, mx = W.bounds(obj)
    foot = (mx.x - mn.x) * (mx.y - mn.y)
    by = {}
    for p in obj.data.polygons:
        if abs(p.normal.z) > 0.9 and lo <= p.center.z <= hi:
            k = round(p.center.z, 2)
            by[k] = by.get(k, 0.0) + p.area
    best = max(by.items(), key=lambda kv: kv[1], default=None)
    return best[0] if best and best[1] >= min_frac * foot else None


def main_roof_z(obj, frac=0.5):
    """Height of the main roof: the highest up-facing body face level that covers >= frac of the largest such
    level's area (skips antennas / rooftop boxes)."""
    me = obj.data
    by = {}
    for p in me.polygons:
        if p.normal.z > 0.9:
            k = round(p.center.z, 1)
            by[k] = by.get(k, 0.0) + p.area
    if not by:
        return W.bounds(obj)[1].z
    big = max(by.values())
    zs = [z for z, a in by.items() if a >= frac * big]
    return max(zs)


# ------------------------------------------------------------------------------------------------------------------
# slabs
# ------------------------------------------------------------------------------------------------------------------
def validate_loop(bvh, pts, zs, reach, tol, insets, area):
    simp = dp_simplify_closed(pts, tol)
    if len(simp) < 3 or poly_area(simp) <= 0:
        return None
    for d in insets:
        ins = inset_polygon(simp, d)
        if poly_area(ins) < 0.5 * area:
            return None
        ok = True
        for i in range(len(ins)):
            a, b = Vector(ins[i]), Vector(ins[(i + 1) % len(ins)])
            steps = max(1, int((b - a).length / 0.5))
            for s_ in range(steps):
                q = a.lerp(b, s_ / steps)
                if not enclosed(bvh, Vector((q.x, q.y, zs)), reach, up=False):
                    ok = False
                    break
            if not ok:
                break
        if ok:
            return ins
    return None


def slab_outline(obj, bvh, z, reach, tol=0.05, insets=(SLAB_INSET, 0.14, 0.26), ref_area=0.0):
    """Validated slab outline(s) at height z: ('polys', [pts, ...]) — every closed section loop of a volume part
    (largest first, loops inside an accepted one skipped), simplified, inset and enclosure-tested — or
    ('rects', [(x0, y0, x1, y1)]) from the raster fallback, or (None, reason)."""
    best = None
    for zs in (z + 0.06, z - 0.15, z + 0.25, z - 0.35):     # probe heights: the source section may be messy AT z;
        loops = section_loops(obj, zs)                     # the largest valid plan wins (setbacks: the storey
        accepted = []                                      # below; overhangs: the storey above)
        big = loops[0][1] if loops else 0.0
        for pts, area in loops:
            if area < max(2.0, 0.04 * big):
                break
            cx = sum(p[0] for p in pts) / len(pts)
            cy = sum(p[1] for p in pts) / len(pts)
            if any(point_in_poly(cx, cy, a) for a in accepted):
                continue
            ins = validate_loop(bvh, pts, zs, reach, tol, insets, area)
            if ins is not None:
                accepted.append(ins)
        tot = sum(abs(poly_area(a)) for a in accepted)
        if accepted and tot > 0.5 * max(big, ref_area) and (best is None or tot > best[0] * 1.02):
            best = (tot, accepted)
    if best:
        return "polys", best[1]
    rects = raster_rects(bvh, obj, z + 0.06, reach)
    if rects:
        return "rects", rects
    return None, "no enclosed section at z=%.2f" % z


def raster_rects(bvh, obj, z, reach, cell=0.25, margin=0.03):
    """Enclosed cells (centre + 4 corners enclosed) merged into rectangles, edges pushed out to the shell."""
    mn, mx = W.bounds(obj)
    nx = int((mx.x - mn.x) / cell) + 1
    ny = int((mx.y - mn.y) / cell) + 1
    grid = [[False] * nx for _ in range(ny)]
    h = cell * 0.5 - 0.01
    for j in range(ny):
        for i in range(nx):
            cx, cy = mn.x + (i + 0.5) * cell, mn.y + (j + 0.5) * cell
            pts = [(cx, cy), (cx - h, cy - h), (cx + h, cy - h), (cx - h, cy + h), (cx + h, cy + h)]
            grid[j][i] = all(enclosed(bvh, Vector((x, y, z)), reach, up=False) for x, y in pts)
    rects = []
    used = [[False] * nx for _ in range(ny)]
    for j in range(ny):
        i = 0
        while i < nx:
            if not grid[j][i] or used[j][i]:
                i += 1
                continue
            i1 = i
            while i1 + 1 < nx and grid[j][i1 + 1] and not used[j][i1 + 1]:
                i1 += 1
            j1 = j
            while j1 + 1 < ny and all(grid[j1 + 1][k] and not used[j1 + 1][k] for k in range(i, i1 + 1)):
                j1 += 1
            for jj in range(j, j1 + 1):
                for ii in range(i, i1 + 1):
                    used[jj][ii] = True
            rects.append([mn.x + i * cell, mn.y + j * cell, mn.x + (i1 + 1) * cell, mn.y + (j1 + 1) * cell])
            i = i1 + 1
    # push edges that face the shell out to it (keeps `margin` from the wall)
    for r in rects:
        cxm, cym = (r[0] + r[2]) / 2, (r[1] + r[3]) / 2
        for side, d in ((0, Vector((-1, 0, 0))), (2, Vector((1, 0, 0))), (1, Vector((0, -1, 0))), (3, Vector((0, 1, 0)))):
            probe = [Vector((cxm, cym, z))]
            gaps = []
            for q in probe:
                start = Vector((r[side] if side in (0, 2) else q.x, r[side] if side in (1, 3) else q.y, z))
                hit = bvh.ray_cast(start, d, cell * 1.5)
                gaps.append(hit[3] if hit[0] is not None else None)
            if all(g is not None for g in gaps):
                g = min(gaps) - margin
                if g > 0:
                    r[side] += g * (d.x + d.y)
    return rects


def slab_from_outline(kind, data, z_top, thick=SLAB_T, name="Slab"):
    """Closed slab prism (top at z_top). Colour `concrete` (floor-plan tone), class slab."""
    bm = bmesh.new()
    if kind == "poly":
        shapes = [data]
    elif kind == "polys":
        shapes = data
    else:
        shapes = [[(r[0], r[1]), (r[2], r[1]), (r[2], r[3]), (r[0], r[3])] for r in data]
    for pts in shapes:
        top = [bm.verts.new((x, y, z_top)) for x, y in pts]
        f = bm.faces.new(top)
        f.normal_update()
        if f.normal.z < 0:
            f.normal_flip()
        ext = bmesh.ops.extrude_face_region(bm, geom=[f])
        for v in [e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)]:
            v.co.z -= thick
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    # extrusion moved the copy DOWN: the original face is the top (normal +z), the copy is the bottom
    bm.normal_update()
    o = W.mesh_from_bm(bm, name)
    bm.free()
    o.data.materials.append(palette.get_vcol_material())
    c = palette.vcol_rgba("concrete")[:3]
    W.set_col(o.data, list(c + (1.0,)) * len(o.data.loops))
    W.set_cls(o.data, [W.CLS["slab"]] * len(o.data.polygons))
    return o


def drop_internal_floors(obj, levels, bvh=None, band=0.25):
    """Delete the source's own horizontal faces that lie INSIDE the volume within `band` m of a slab level (the
    stacked storey modules of Kenney kits have closed boxes whose tops / bottoms would z-fight with our slabs in
    the cut). Inside = enclosed horizontally AND covered from above within the building. Returns the count."""
    import bmesh as _bm
    bvh = bvh or bvh_of([obj])
    mn, mx = W.bounds(obj)
    reach = (mx - mn).length + 1.0
    me = obj.data
    kill = []
    for p in me.polygons:
        if abs(p.normal.z) < 0.9:
            continue
        z = p.center.z
        if not any(abs(z - lv) <= band for lv in levels):
            continue
        c = p.center.copy()
        probe = c + Vector((0, 0, 0.02 if p.normal.z > 0 else -0.02))
        if enclosed(bvh, probe, reach, up=False) and bvh.ray_cast(c + Vector((0, 0, 0.02)), Vector((0, 0, 1)),
                                                                     200.0)[0] is not None:
            kill.append(p.index)
    if kill:
        bm = _bm.new()
        bm.from_mesh(me)
        bm.faces.ensure_lookup_table()
        _bm.ops.delete(bm, geom=[bm.faces[i] for i in kill], context="FACES")
        bm.to_mesh(me)
        bm.free()
        me.update()
    return len(kill)


def add_slabs(obj, st, bvh=None, ground=True):
    """One slab per floor level of `st` (+ a ground slab at z = 0.02 closing the bottom). Returns (objs, report)."""
    bvh = bvh or bvh_of([obj])
    mn, mx = W.bounds(obj)
    reach = (mx - mn).length + 1.0
    out, rep = [], []
    levels = ([0.02] if ground else []) + st["levels"]
    for z in levels:
        ref = 0.6 * enclosed_area(bvh, mn, mx, (z if z > 0.1 else 0.3) + 0.06, reach)   # the slab must cover the
        kind, data = slab_outline(obj, bvh, z if z > 0.1 else 0.3, reach, ref_area=ref)  # storey's enclosed plan
        if kind is None:
            rep.append((z, "none", data))
            continue
        out.append(slab_from_outline(kind, data, z + SLAB_LIFT))
        rep.append((z, kind, len(data)))
    return out, rep


# ------------------------------------------------------------------------------------------------------------------
# tests (build time + verify_assets.py)
# ------------------------------------------------------------------------------------------------------------------
def closed_problems(objs, st, samples=5):
    """From points inside every storey (mid height, on the slab outline's interior) no horizontal ray escapes."""
    vis = [o for o in objs if o.type == "MESH"]
    bvh = bvh_of(vis)
    mn, mx = W.bounds(vis)
    reach = (mx - mn).length + 1.0
    bad = []
    levels = [0.0] + st["levels"]
    for k, z0 in enumerate(levels):
        z1 = levels[k + 1] if k + 1 < len(levels) else st["roof_z"]
        zm = (z0 + z1) / 2
        pts = interior_points(bvh, mn, mx, zm, reach, samples)
        esc = 0
        for p in pts:
            for d in HDIRS16:
                if bvh.ray_cast(p, d, reach)[0] is None:
                    esc += 1
        if not pts:
            bad.append("storey %d: no interior point" % k)
        elif esc:
            bad.append("storey %d: %d of %d rays escape" % (k, esc, 16 * len(pts)))
    return bad


def enclosed_area(bvh, mn, mx, z, reach, cell=0.75):
    """Area (m2) of the plan enclosed by the shell at height z (coarse grid of 4-ray enclosure tests)."""
    nx = max(1, int((mx.x - mn.x) / cell))
    ny = max(1, int((mx.y - mn.y) / cell))
    dx, dy = (mx.x - mn.x) / nx, (mx.y - mn.y) / ny
    n = sum(1 for j in range(ny) for i in range(nx)
            if enclosed(bvh, Vector((mn.x + (i + 0.5) * dx, mn.y + (j + 0.5) * dy, z)), reach, up=False))
    return n * dx * dy


def interior_points(bvh, mn, mx, z, reach, n, covered=False):
    """Grid points at height z enclosed horizontally by the shell (covered=True: also under a roof)."""
    pts = []
    for j in range(n):
        for i in range(n):
            x = mn.x + (i + 0.5) / n * (mx.x - mn.x)
            y = mn.y + (j + 0.5) / n * (mx.y - mn.y)
            p = Vector((x, y, z))
            if enclosed(bvh, p, reach, up=covered):
                pts.append(p)
    return pts


def cut_view_problems(objs, st, pitch=48.0, yaws=8, grid=7, depth_tol=0.6):
    """Corte urbano view: for every storey k the geometry above y_cut = ground_h + k * floor_h + STUB is removed;
    game-camera rays crossing the cut plane inside the footprint must first hit a front face no deeper than
    depth_tol below the slab top (slab / stub tops) or a BACK face (painted cap_color by the shader) — never fall
    through to a lower storey or the ground."""
    vis = [o for o in objs if o.type == "MESH"]
    verts, polys, norms = [], [], []
    for o in vis:
        mw = o.matrix_world
        base = len(verts)
        verts += [mw @ v.co for v in o.data.vertices]
        m3 = mw.to_3x3()
        for p in o.data.polygons:
            polys.append(tuple(base + i for i in p.vertices))
            norms.append((m3 @ p.normal).normalized())
    bvh = BVHTree.FromPolygons(verts, polys, epsilon=0.0)
    mn, mx = W.bounds(vis)
    reach = (mx - mn).length + 1.0
    bad = []
    levels = st["levels"]
    for k, zs in enumerate(levels):
        ycut = zs + STUB
        pts = interior_points(bvh, mn, mx, ycut - 0.05, reach, grid)
        fails, total = 0, 0
        for yi in range(yaws):
            yaw = math.radians(45 * yi)
            p = math.radians(pitch)
            d = -Vector((math.sin(yaw) * math.cos(p), math.cos(yaw) * math.cos(p), math.sin(p)))
            for q in pts:
                org = Vector((q.x, q.y, ycut))
                loc, _n, idx, _dd = bvh.ray_cast(org + d * 1e-3, d, 60.0)
                total += 1
                if idx is None:
                    fails += 1
                    continue
                front = norms[idx].dot(d) < 0
                if front and loc.z < zs - depth_tol:
                    fails += 1
        if total and fails > 0.05 * total:
            bad.append("cut at storey %d (y_cut %.2f): %d of %d rays see below the slab" % (k, ycut, fails, total))
    return bad


# ------------------------------------------------------------------------------------------------------------------
# groups + shadow proxy
# ------------------------------------------------------------------------------------------------------------------
def split_by_z(obj, cuts):
    """Bisect `obj` at every z in `cuts` and return the face index lists per band (len(cuts) + 1 bands)."""
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    for zc in cuts:
        bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], dist=1e-5,
                               plane_co=(0, 0, zc), plane_no=(0, 0, 1))
    bm.to_mesh(me)
    bm.free()
    me.update()
    bands = [[] for _ in range(len(cuts) + 1)]
    for p in me.polygons:
        z = p.center.z
        k = sum(1 for c in cuts if z > c)
        bands[k].append(p.index)
    return bands


def extract_faces(obj, faces, name):
    """New object with a copy of `faces` of obj (materials, Col, cls, custom normals kept)."""
    import bpy
    new = obj.copy()
    new.data = obj.data.copy()
    new.name = name
    new.data.name = name
    bpy.context.scene.collection.objects.link(new)
    keep = set(faces)
    bm = bmesh.new()
    bm.from_mesh(new.data)
    bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.index not in keep], context="FACES")
    bm.to_mesh(new.data)
    bm.free()
    new.data.update()
    return new


def shadow_proxy(obj, st, name="Tower_Shadow", tol=0.4):
    """Low-poly shadow caster: the building's section at a few heights, simplified (dp tol m) and extruded into
    stacked prisms up to the main roof (the crown's small boxes are ignored). Class slab, colour concrete_dark."""
    bvh = bvh_of([obj])
    mn, mx = W.bounds(obj)
    reach = (mx - mn).length + 1.0
    roof = st["roof_z"]
    samples = sorted({0.5 * st["ground_h"]} | {st["ground_h"] + (k + 0.5) * st["floor_h"]
                                                  for k in range(0, len(st["levels"]), 4)})
    samples = [z for z in samples if z < roof - 0.3]
    outlines = []
    for z in samples:
        loops = section_loops(obj, z)
        if loops and loops[0][1] > 1.0:
            pts = dp_simplify_closed(loops[0][0], tol)
        else:
            pts = [(mn.x, mn.y), (mx.x, mn.y), (mx.x, mx.y), (mn.x, mx.y)]
        outlines.append((z, pts))
    # merge consecutive outlines with ~ the same area
    tiers = []
    for z, pts in outlines:
        a = poly_area(pts)
        if tiers and abs(a - tiers[-1][2]) < 0.08 * max(a, tiers[-1][2]):
            continue
        tiers.append([z, pts, a])
    bm = bmesh.new()
    for i, (z, pts, a) in enumerate(tiers):
        z0 = 0.0 if i == 0 else (tiers[i][0] + tiers[i - 1][0]) * 0.5
        z1 = roof if i == len(tiers) - 1 else (tiers[i + 1][0] + z) * 0.5
        z0 = 0.0 if i == 0 else z0
        bot = [bm.verts.new((x, y, z0)) for x, y in pts]
        f = bm.faces.new(bot)
        f.normal_update()
        if f.normal.z > 0:
            f.normal_flip()
        ext = bmesh.ops.extrude_face_region(bm, geom=[f])
        for v in [e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)]:
            v.co.z = z1
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    o = W.mesh_from_bm(bm, name)
    bm.free()
    o.data.materials.append(palette.get_vcol_material())
    c = palette.vcol_rgba("concrete_dark")[:3]
    W.set_col(o.data, list(c + (1.0,)) * len(o.data.loops))
    W.set_cls(o.data, [W.CLS["slab"]] * len(o.data.polygons))
    return o
