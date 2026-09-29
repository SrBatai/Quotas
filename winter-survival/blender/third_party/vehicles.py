"""Static city vehicles for traffic jams and checkpoints (A1): one prepared model -> five variants.

  clean    light snow on roof / hood, light grime
  snowed   buried to the window line (mound + drift), thick roof slab, frosted glass
  crashed  front crumpled, windscreen crazed, headlights broken, tilted on a flat tyre, glass shards
  doors    front-left (and rear-right on 4-door bodies) door swung open, dark interior showing, light snow
  burnt    charred paint ramp, no glass, tyres gone (rims only, body sits lower), soot patch, little snow

Source wheels (420-956 tris each in the Quaternius packs) are replaced by procedural 16-sided wheels at the same
centre / radius / width (~110 tris each): the budget goes to snow instead. Wheels, snow and ground patches are
merged into `Body`; glass is its own mesh `Glass` (ASSET_SPEC_V2 §11). Front = -Y, left = +X.
"""
import math
import random

import bpy  # noqa: I001
import bmesh
from mathutils import Matrix, Vector, noise

from lib import palette

from . import winterize as W

WHEEL_SIDES = 16
VARIANTS = ("clean", "snowed", "crashed", "doors", "burnt")


# ------------------------------------------------------------------------------------------------------------------
# wheels
# ------------------------------------------------------------------------------------------------------------------
def tag_wheels(objs):
    """Flag the faces of wheel objects (INT face attribute `wheel` = 1): low, round (y extent ~ z extent) objects."""
    mn, mx = W.bounds(objs)
    H = mx.z - mn.z
    n = 0
    for o in objs:
        omn, omx = W.bounds(o)
        dz, dy, dx = omx.z - omn.z, omx.y - omn.y, omx.x - omn.x
        long_y = (mx.y - mn.y) >= (mx.x - mn.x)
        d_len = dy if long_y else dx
        is_wheel = ("wheel" in o.name.lower() or (omn.z - mn.z) < 0.08 * H) and (omx.z - mn.z) < 0.55 * H \
            and abs(d_len - dz) < 0.25 * dz and dz > 0.12 * H
        a = o.data.attributes.new("wheel", "INT", "FACE")
        a.data.foreach_set("value", [1 if is_wheel else 0] * len(o.data.polygons))
        n += is_wheel
    return n


def wheel_records(obj):
    """Wheels from the flagged faces (after conform): [(centre, radius, width, side)] and delete those faces."""
    me = obj.data
    a = me.attributes.get("wheel")
    if a is None:
        return []
    flags = [0] * len(me.polygons)
    a.data.foreach_get("value", flags)
    verts = {}
    for p in me.polygons:
        if flags[p.index]:
            for vi in p.vertices:
                verts[vi] = me.vertices[vi].co.copy()
    # cluster wheel vertices: by side (x sign) and by axle (y gaps > 0.3 m)
    recs = []
    for side in (1, -1):
        pts = sorted((v for v in verts.values() if v.x * side > 0), key=lambda v: v.y)
        groups, cur = [], []
        for v in pts:
            if cur and v.y - cur[-1].y > 0.3:
                groups.append(cur)
                cur = []
            cur.append(v)
        if cur:
            groups.append(cur)
        for g in groups:
            xs, ys, zs = [v.x for v in g], [v.y for v in g], [v.z for v in g]
            r = (max(zs) - min(zs)) / 2
            if r < 0.12:
                continue
            c = Vector(((max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2, min(zs) + r))
            recs.append((c, r, max(xs) - min(xs), side))
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    layer = bm.faces.layers.int.get("wheel")
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f[layer]], context="FACES")
    bm.to_mesh(me)
    bm.free()
    me.attributes.remove(me.attributes["wheel"])
    me.update()
    return recs


def wheel_object(recs, burnt=False, sides=WHEEL_SIDES, name="Wheels"):
    """Procedural wheels: tread + outer sidewall + recessed rim + hub (closed with an inner cap). Burnt: rims only."""
    bm = bmesh.new()
    cols = []
    tyre = palette.vcol_rgba("tire")[:3]
    rim = palette.vcol_rgba("concrete_dark" if not burnt else "rust")[:3]
    hub = palette.vcol_rgba("chrome" if not burnt else "iron")[:3]
    for c, r, w, side in recs:
        rr = r * (0.62 if not burnt else 0.60)
        w = max(0.14, min(w, 0.4))
        xo, xi = c.x + side * w / 2, c.x - side * w / 2          # outer / inner face planes
        ang = [2 * math.pi * k / sides for k in range(sides)]

        def ring(x, rad):
            return [bm.verts.new((x, c.y + rad * math.cos(t), c.z + rad * math.sin(t))) for t in ang]
        faces = []
        if not burnt:
            out_t = ring(xo, r)
            in_t = ring(xi, r)
            out_r = ring(xo, rr)
            rim_r = ring(xo - side * 0.035, rr * 0.98)
            for k in range(sides):
                k1 = (k + 1) % sides
                faces.append((bm.faces.new((out_t[k], out_t[k1], in_t[k1], in_t[k])), tyre))
                faces.append((bm.faces.new((out_t[k], out_r[k], out_r[k1], out_t[k1])), tyre))
                faces.append((bm.faces.new((out_r[k], rim_r[k], rim_r[k1], out_r[k1])), rim))
            faces.append((bm.faces.new(rim_r), hub))
            faces.append((bm.faces.new(in_t), tyre))
        else:
            out_r = ring(xo - side * 0.03, rr)
            in_r = ring(xi + side * 0.03, rr)
            for k in range(sides):
                k1 = (k + 1) % sides
                faces.append((bm.faces.new((out_r[k], out_r[k1], in_r[k1], in_r[k])), rim))
            faces.append((bm.faces.new(out_r), hub))
            faces.append((bm.faces.new(in_r), rim))
        cols += faces
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.faces.ensure_lookup_table()
    fcol = {f: col for f, col in cols}
    order = [fcol[f] for f in bm.faces]
    o = W.mesh_from_bm(bm, name)
    bm.free()
    o.data.materials.append(palette.get_vcol_material())
    data = []
    for p, col in zip(o.data.polygons, order):
        data += list(col) + [1.0]
    flat = [0.0] * (len(o.data.loops) * 4)
    for p, col in zip(o.data.polygons, order):
        for li in p.loop_indices:
            flat[li * 4:li * 4 + 4] = list(col) + [1.0]
    W.set_col(o.data, flat)
    W.set_cls(o.data, [W.CLS["body"]] * len(o.data.polygons))
    return o


# ------------------------------------------------------------------------------------------------------------------
# anchors
# ------------------------------------------------------------------------------------------------------------------
def class_centres(obj, cname, split_x=True):
    """Centroids of the faces of class `cname` (left +X / right -X when split_x)."""
    me = obj.data
    cls = W.get_cls(me)
    groups = {1: [], -1: []} if split_x else {0: []}
    for p in me.polygons:
        if cls[p.index] == W.CLS[cname]:
            k = (1 if p.center.x >= 0 else -1) if split_x else 0
            groups[k].append((p.center.copy(), p.area))
    out = {}
    for k, lst in groups.items():
        if lst:
            A = sum(a for _, a in lst) or 1.0
            out[k] = sum((c * a for c, a in lst), Vector()) / A
    return out


def lamp_anchors(obj):
    """Headlight_L/R (lamp faces in front), Taillight_L/R (tail faces), Beacon (roof beacons)."""
    me = obj.data
    cls = W.get_cls(me)
    mn, mx = W.bounds(obj)
    res = {}
    front = {1: [], -1: []}
    for p in me.polygons:
        if cls[p.index] == W.CLS["lamp"] and p.center.y < 0 and p.center.z < mn.z + 0.6 * (mx.z - mn.z):
            front[1 if p.center.x >= 0 else -1].append(p.center.copy())
    for k, nm in ((1, "Headlight_L"), (-1, "Headlight_R")):
        if front[k]:
            res[nm] = sum(front[k], Vector()) / len(front[k])
    tails = class_centres(obj, "tail")
    for k, nm in ((1, "Taillight_L"), (-1, "Taillight_R")):
        if k in tails:
            res[nm] = tails[k]
    b = class_centres(obj, "beacon", split_x=False)
    if 0 in b:
        res["Beacon"] = b[0]
    return res


# ------------------------------------------------------------------------------------------------------------------
# door region (front-left door, rear-right door)
# ------------------------------------------------------------------------------------------------------------------
def door_faces(obj, side=1, which="front"):
    """Faces of a side door: the y span of the first (front) or last (rear) side-window cluster on that side,
    z from 0.12 m above the sill to the window top, on the outer skin of that side."""
    me = obj.data
    cls = W.get_cls(me)
    mn, mx = W.bounds(obj)
    half = (mx.x - mn.x) / 2
    wins = []
    for p in me.polygons:
        if cls[p.index] == W.CLS["glass"] and p.normal.x * side > 0.5 and p.center.x * side > 0.4 * half:
            zs = [me.vertices[i].co.z for i in p.vertices]
            ys = [me.vertices[i].co.y for i in p.vertices]
            wins.append((min(ys), max(ys), min(zs), max(zs)))
    if not wins:
        return None
    wins.sort()
    clusters = []
    for w in wins:
        if clusters and w[0] < clusters[-1][1] + 0.08:
            c = clusters[-1]
            clusters[-1] = (c[0], max(c[1], w[1]), min(c[2], w[2]), max(c[3], w[3]))
        else:
            clusters.append(w)
    y0, y1, wz0, wz1 = clusters[0] if which == "front" else clusters[-1]
    if y1 - y0 < 0.45:
        return None
    y1 = min(y1, y0 + 1.25)
    z0 = mn.z + 0.28 * (wz0 - mn.z) + 0.10
    # cut the (few, long) side faces of a low-poly body at the door lines so the door is its own faces
    bm = bmesh.new()
    bm.from_mesh(me)
    for co, no in (((0, y0, 0), (0, 1, 0)), ((0, y1, 0), (0, 1, 0)), ((0, 0, z0), (0, 0, 1)),
                   ((0, 0, wz1 + 0.01), (0, 0, 1))):
        bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], dist=1e-5, plane_co=co, plane_no=no)
    bm.to_mesh(me)
    bm.free()
    me.update()
    faces = []
    for p in me.polygons:
        c = p.center
        if y0 - 0.02 <= c.y <= y1 + 0.02 and z0 <= c.z <= wz1 + 0.02 and c.x * side > 0.55 * half \
                and p.normal.x * side > 0.35:
            faces.append(p.index)
    return (faces, y0, y1, z0, wz1) if faces else None


def open_door(obj, info, side, angle_deg, seed):
    """The door swung open about its front hinge, rebuilt as a clean closed panel (paint below the window line,
    glass above, dark trim inside); the body opening behind it turns dark (interior showing).
    Returns the panel object and the hinge point."""
    faces, y0, y1, z0, z1 = info
    me = obj.data
    cls = W.get_cls(me)
    data = W.get_col(me)
    # paint colour of the door skin (average of its body corners)
    acc, n = Vector((0, 0, 0)), 0
    xs = []
    wz = z1
    for fi in faces:
        p = me.polygons[fi]
        xs += [me.vertices[i].co.x for i in p.vertices]
        if cls[fi] == W.CLS["glass"]:
            wz = min(wz, min(me.vertices[i].co.z for i in p.vertices))
            continue
        for li in p.loop_indices:
            acc += Vector(data[li * 4:li * 4 + 3])
            n += 1
    paint = tuple(acc / max(1, n)) if n else palette.vcol_rgba("concrete_dark")[:3]
    hx = max(x * side for x in xs) * side
    L, T = y1 - y0, 0.06
    zb, zt = z0, z1
    zw = min(max(wz, zb + 0.2), zt - 0.1)             # window line
    th = math.radians(angle_deg) * side
    hinge = Vector((hx, y0, 0.0))
    rot = Matrix.Translation(hinge) @ Matrix.Rotation(-th, 4, "Z") @ Matrix.Translation(-hinge)
    bm = bmesh.new()
    cols = []

    def box(x0, x1, ya, yb, za, zb_, col):
        vs = [bm.verts.new(rot @ Vector((x, y, z))) for z in (za, zb_) for y in (ya, yb) for x in (x0, x1)]
        quads = [(0, 2, 3, 1), (4, 5, 7, 6), (0, 1, 5, 4), (2, 6, 7, 3), (0, 4, 6, 2), (1, 3, 7, 5)]
        for q in quads:
            f = bm.faces.new([vs[i] for i in q])
            cols.append((f, col))
    xo = hx
    xi = hx - side * T
    x0, x1 = (xi, xo) if side > 0 else (xo, xi)
    dark = palette.vcol_rgba("cloth_dark")[:3]
    box(x0, x1, y0, y1, zb, zw, paint)                                  # lower panel
    box(x0, x1, y0, y0 + 0.07, zw, zt, paint)                           # window frame posts + top rail
    box(x0, x1, y1 - 0.07, y1, zw, zt, paint)
    box(x0, x1, y0 + 0.07, y1 - 0.07, zt - 0.06, zt, paint)
    box(x0 + 0.02 * side * 0 + (0.015 if side < 0 else 0.0), x1 - (0.015 if side > 0 else 0.0),
        y0 + 0.07, y1 - 0.07, zw, zt - 0.06, "glass")                  # pane
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.faces.ensure_lookup_table()
    fcol = {f: c for f, c in cols}
    order = [fcol[f] for f in bm.faces]
    panel = W.mesh_from_bm(bm, "DoorPanel", like=obj)
    bm.free()
    pme = panel.data
    pcls = [W.CLS["glass"] if c == "glass" else W.CLS["body"] for c in order]
    pdata = [1.0] * (len(pme.loops) * 4)
    in_dir = Vector((-side * math.cos(th), -math.sin(th), 0.0))
    for p, c in zip(pme.polygons, order):
        col = (1.0, 1.0, 1.0) if c == "glass" else (dark if p.normal.dot(in_dir) > 0.5 else c)
        for li in p.loop_indices:
            pdata[li * 4:li * 4 + 3] = col
    W.set_col(pme, pdata)
    W.set_cls(pme, pcls)
    W.paint_faces(obj, faces, name="cloth_dark", cls_name="interior")
    return panel, Vector((hx, y0, (z0 + z1) / 2))


# ------------------------------------------------------------------------------------------------------------------
# deformations / repaints
# ------------------------------------------------------------------------------------------------------------------
def crumple_front(objs, depth, amount, seed, side=1):
    """Offset frontal impact: push the front `depth` metres back (up to `amount`, 60 % more on the `side` corner),
    buckle and lift the hood, squeeze toward the centre. Wheels (passed in objs) follow the same field."""
    mn, mx = W.bounds(objs)
    yf = mn.y
    half = max(0.3, (mx.x - mn.x) / 2)
    H = mx.z - mn.z
    off = Vector((seed * 0.37, seed * 0.11, 0.5))
    for o in objs:
        for v in o.data.vertices:
            t = (v.co.y - yf) / depth
            if t >= 1.0:
                continue
            k = (1.0 - max(0.0, t)) ** 1.3
            corner = 1.0 + 0.4 * max(-1.0, min(1.0, side * v.co.x / half))
            nz = 0.8 + 0.2 * noise.noise(v.co * 0.7 + off)          # smooth field: no folded faces
            v.co.y += amount * k * nz * corner
            upper = v.co.z > mn.z + 0.4 * H
            v.co.z += (0.16 * k * (0.5 + 0.5 * math.sin(v.co.x * 4.3 + seed)) + 0.05 * k) * upper
            v.co.x *= 1.0 - 0.07 * k
        o.data.update()


def tilt(objs, roll_deg, pitch_deg):
    m = Matrix.Rotation(math.radians(roll_deg), 4, "Y") @ Matrix.Rotation(math.radians(pitch_deg), 4, "X")
    for o in objs:
        o.data.transform(m)
        o.data.update()
    mn, _mx = W.bounds(objs)
    for o in objs:
        o.data.transform(Matrix.Translation((0, 0, -mn.z)))


def burn(obj, seed):
    """Charred ramp: soot black -> dark grey -> rust (more rust low and at the arches), glass / lamps -> black."""
    me = obj.data
    cls = W.get_cls(me)
    data = W.get_col(me)
    soot = Vector(palette.vcol_rgba("paint_black")[:3])
    ash = Vector(palette.vcol_rgba("concrete_dark")[:3])
    rust = Vector(palette.vcol_rgba("rust")[:3])
    off = Vector((seed * 0.3, seed * 0.7, 0.1))
    mn, mx = W.bounds(obj)
    for p in me.polygons:
        c = cls[p.index]
        for li, vi in zip(p.loop_indices, p.vertices):
            wp = me.vertices[vi].co
            n1 = noise.noise(wp * 1.6 + off)
            low = 1.0 - W.smooth01(mn.z, mn.z + 0.9 * (mx.z - mn.z), wp.z)
            base = soot.lerp(ash, 0.5 + 0.5 * n1)
            col = base.lerp(rust, max(0.0, 0.25 + 0.45 * low + 0.3 * noise.noise(wp * 3.7 + off)))
            data[li * 4:li * 4 + 3] = col
        if c in (W.CLS["glass"], W.CLS["lamp"], W.CLS["tail"], W.CLS["beacon"]):
            cls[p.index] = W.CLS["burnt"]
            for li in p.loop_indices:
                data[li * 4:li * 4 + 3] = soot
        elif c == W.CLS["body"] or c == W.CLS["interior"]:
            cls[p.index] = W.CLS["burnt"]
    W.set_col(me, data)
    W.set_cls(me, cls)


def frost_glass(obj, name="snow_packed", pred=None):
    """Glass faces -> frosted / crazed palette faces (class frost, material palette_vcol)."""
    me = obj.data
    cls = W.get_cls(me)
    faces = [p.index for p in me.polygons if cls[p.index] == W.CLS["glass"] and (pred is None or pred(p))]
    W.paint_faces(obj, faces, name=name, cls_name="frost")
    return len(faces)


def break_lamps(obj):
    me = obj.data
    cls = W.get_cls(me)
    faces = [p.index for p in me.polygons if cls[p.index] == W.CLS["lamp"] and p.center.y < 0]
    W.paint_faces(obj, faces, name="plastic_black", cls_name="body")


def ground_patch(cx, cy, rx, ry, colour_fn, seed, rings=4, sides=18, z=0.015):
    """Flat irregular ground patch (soot / slush) facing up, slightly above z = 0; smooth edges fade by colour."""
    bm = bmesh.new()
    rnd = random.Random(seed)
    jit = [rnd.uniform(0.8, 1.15) for _ in range(sides)]
    centre = bm.verts.new((cx, cy, z))
    prev = None
    rows = []
    for k in range(1, rings + 1):
        t = k / rings
        rows.append([bm.verts.new((cx + math.cos(2 * math.pi * i / sides) * rx * t * jit[i],
                                   cy + math.sin(2 * math.pi * i / sides) * ry * t * jit[i], z)) for i in range(sides)])
    for i in range(sides):
        bm.faces.new((centre, rows[0][i], rows[0][(i + 1) % sides]))
    for k in range(rings - 1):
        for i in range(sides):
            i1 = (i + 1) % sides
            bm.faces.new((rows[k][i], rows[k + 1][i], rows[k + 1][i1], rows[k][i1]))
    bm.normal_update()
    for f in bm.faces:
        if f.normal.z < 0:
            f.normal_flip()
    o = W.mesh_from_bm(bm, "Patch")
    bm.free()
    o.data.materials.append(palette.get_vcol_material())
    data = [1.0] * (len(o.data.loops) * 4)
    for p in o.data.polygons:
        for li, vi in zip(p.loop_indices, p.vertices):
            co = o.data.vertices[vi].co
            r = math.hypot((co.x - cx) / rx, (co.y - cy) / ry)
            data[li * 4:li * 4 + 3] = colour_fn(co, r)
    W.set_col(o.data, data)
    W.set_cls(o.data, [W.CLS["snow"]] * len(o.data.polygons))
    return o


def shards(cx, cy, spread, n, seed, name="concrete"):
    """A few glass shards / small debris lying on the ground (thin flat triangles facing up)."""
    rnd = random.Random(seed)
    bm = bmesh.new()
    for _ in range(n):
        x = cx + rnd.uniform(-spread, spread)
        y = cy + rnd.uniform(-spread * 0.6, spread * 0.6)
        s = rnd.uniform(0.05, 0.14)
        a = rnd.uniform(0, math.pi)
        vs = [bm.verts.new((x + s * math.cos(a + k * 2.1), y + s * math.sin(a + k * 2.1), 0.02)) for k in range(3)]
        f = bm.faces.new(vs)
        f.normal_update()
        if f.normal.z < 0:
            f.normal_flip()
    o = W.mesh_from_bm(bm, "Shards")
    bm.free()
    o.data.materials.append(palette.get_vcol_material())
    c = palette.vcol_rgba(name)[:3]
    W.set_col(o.data, list(c + (1.0,)) * len(o.data.loops))
    W.set_cls(o.data, [W.CLS["frost"]] * len(o.data.polygons))
    return o
