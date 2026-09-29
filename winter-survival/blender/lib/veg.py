"""Vegetation / ground-cover generators shared by build_trees.py (G1 pines, dead_tree) and the M3 scatter families in
vegetation/ (docs/research/05_graficos_arte.md §4.3, ASSET_SPEC_V2 §13 + "M3").

Everything here builds into the CURRENT scene (lowpoly.new_scene()) and returns Blender objects that the caller joins
into the single MultiMesh object (`Tree`, `Bush`, `Rock`, `Snow`, `Log`). The defaults of `pine_tier`, `trunk`,
`base_mound` and `bare_tree` reproduce the G1 pine_a/b/c and dead_tree exactly (same random call order).

  * pines: star tiers (drooping tips, concave `pine_dark` underside, `pine_mid` top) capped by a snow shell computed ON
    the green surface (never intersects), faceted; smooth bark trunk; smooth mound sunk 0.2 m. Per-tier centre offset
    and point count (double crown, narrow spruce), per-tree snow load (`snow_t`, `tcut`: how far the shell reaches
    toward the tips);
  * bare trees: recursive branching of bent tapered tubes (4-7 sides, radius >= 1.4 cm), snow on the upper faces of
    the trunk and main limbs; options for a broken snag top, short broken limbs, birch bark banding;
  * lobes (bush / rock bodies), draped snow caps (`surface_fn` + hd.snow_cap), logs with ring caps, heightfield piles.
"""
import math
import random

import bpy  # noqa: F401  (must precede mathutils)
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

from . import hd as H
from . import lowpoly as lp

Z = Vector((0, 0, 1))


# ------------------------------------------------------------------------------------------------------------
# pines
# ------------------------------------------------------------------------------------------------------------
def star(z0, R, n, phase, rnd, inner=0.50, droop=0.10, h=1.0, jit=0.07):
    """2n points: tips at R (drooping), notches at inner * R."""
    pts = []
    for i in range(2 * n):
        a = math.radians(phase) + math.pi * i / n
        tip = i % 2 == 0
        r = R * rnd.uniform(1 - jit, 1 + jit) if tip else R * inner * rnd.uniform(0.92, 1.05)
        z = z0 - (droop * h * rnd.uniform(0.8, 1.2) if tip else -0.03 * h)
        pts.append(Vector((math.cos(a) * r, math.sin(a) * r, z)))
    return pts


def pine_tier(mb, z0, R, h, n, snow_t, rnd, top=False, center=(0.0, 0.0), droop=0.12, inner=0.60,
              tcut=(0.20, 0.04), mid=0.50):
    """One star tier into `mb`. center = (x, y) of the tier axis; droop = tip droop (fraction of h); tcut = where the
    snow shell starts along each spoke (tips, notches: 0 = at the tip / notch, 1 = at the inner ring)."""
    phase = rnd.uniform(0, 360)
    s0 = star(z0, R, n, phase, rnd, inner=inner, droop=droop, h=h)
    s1 = [Vector((p.x * mid, p.y * mid, z0 + 0.44 * h + (0.0 if i % 2 == 0 else 0.02 * h))) for i, p in enumerate(s0)]
    apex = Vector((0, 0, z0 + h))
    c = Vector((center[0], center[1], 0.0))
    if c.length > 0:
        s0 = [p + c for p in s0]
        s1 = [p + c for p in s1]
        apex = apex + c
    mb.loft([s0, s1, [apex]], "pine_mid", cap_start=False, cap_end=False, inside=c + Vector((0, 0, z0 + 0.2 * h)))
    under = c + Vector((0, 0, z0 + 0.16 * h))                      # concave underside
    m = len(s0)
    for i in range(m):
        mb.poly([s0[i], s0[(i + 1) % m], under], "pine_dark", facing=(0, 0, -1))
    # snow shell on the green surface: starts tcut up each spoke, thickness snow_t
    tc = [tcut[0] if i % 2 == 0 else tcut[1] for i in range(m)]
    b0 = [s0[i].lerp(s1[i], tc[i]) + Vector((0, 0, -0.01)) for i in range(m)]
    t0 = [p + Vector((0, 0, snow_t * (1.0 if i % 2 == 0 else 0.85))) for i, p in enumerate(b0)]
    t1 = [p + Vector((0, 0, snow_t * 0.9)) for p in s1]
    ap = apex + Vector((0, 0, snow_t * (1.4 if top else 0.8)))
    mb.loft([b0, t0], "snow", cap_start=False, cap_end=False, inside=c + Vector((0, 0, z0 + 0.3 * h)))
    mb.loft([t0, t1, [ap]], "snow", cap_start=False, cap_end=False, inside=c + Vector((0, 0, z0)))


def trunk(pts, radii, sides=7, mat="bark"):
    tr = lp.MeshBuilder()
    H.tube(tr, pts, radii, sides, mat, cap_end=True)
    return H.smooth(H.mk(tr))


def pine_trunk(r0, r1, top_z, base=(0.0, 0.0)):
    bx, by = base
    return trunk([(bx, by, -0.1), (bx + 0.01, by, 0.6), (bx, by + 0.01, top_z * 0.5), (bx, by, top_z)],
                 [r0 * 1.15, r0, (r0 + r1) / 2, r1])


def base_mound(rnd, radius0, seed, height=0.24, sides=14, sink=0.2, center=(0, 0, 0), stretch=(1.0, 1.0)):
    """Smooth snow mound around a trunk base (radius from the lowest tier radius, like the G1 pines)."""
    ang = rnd.uniform(0, 360)
    rad = radius0 * 0.42 + 0.1 * math.sin(ang)
    return H.mound(center, rad, height, seed=seed, sides=sides, sink=sink, stretch=stretch)


def pine_tiers(cfg):
    """All star tiers of `cfg` as one flat object -> (object, rnd) (rnd continues the tree's random stream).
    cfg: tiers [(z0, R, h) or (z0, R, h, n) or (z0, R, h, n, cx, cy)], points, snow_t, seed, optional droop, tcut,
    inner, tops (indices of the tiers that carry the thicker apex snow; default: the last)."""
    rnd = random.Random(cfg["seed"])
    mb = lp.MeshBuilder()
    last = cfg["tiers"][-1][0]
    tops = cfg.get("tops")
    for i, t in enumerate(cfg["tiers"]):
        z0, R, h = t[:3]
        n = t[3] if len(t) > 3 else cfg["points"]
        c = (t[4], t[5]) if len(t) > 5 else (0.0, 0.0)
        top = (i in tops) if tops is not None else (z0 == last)
        pine_tier(mb, z0, R, h, n, cfg["snow_t"], rnd, top=top, center=c,
                  droop=cfg.get("droop", 0.12), inner=cfg.get("inner", 0.60), tcut=cfg.get("tcut", (0.20, 0.04)))
    return H.flat(H.mk(mb)), rnd


def pine(cfg):
    """Standard pine (G1 recipe) into the current scene -> [tiers, trunk, mound] objects.
    Extra cfg keys: trunk (r0, r1), mound_h, trunk_top (z; default = the second-highest tier base)."""
    tiers, rnd = pine_tiers(cfg)
    r0, r1 = cfg["trunk"]
    top_z = cfg.get("trunk_top", cfg["tiers"][-2][0])
    tr = pine_trunk(r0, r1, top_z)
    mound = base_mound(rnd, cfg["tiers"][0][1], cfg["seed"], height=cfg.get("mound_h", 0.24))
    return [tiers, tr, mound]


# ------------------------------------------------------------------------------------------------------------
# bare trees
# ------------------------------------------------------------------------------------------------------------
def rot_towards(d, az, el):
    d = d.normalized()
    ref = Vector((0, 0, 1)) if abs(d.z) < 0.95 else Vector((1, 0, 0))
    side = d.cross(ref).normalized()
    return (Matrix.Rotation(math.radians(az), 3, d) @ (Matrix.Rotation(math.radians(el), 3, side) @ d)).normalized()


def radius_at(pts, radii, t):
    f = t * (len(pts) - 1)
    i = min(int(f), len(pts) - 2)
    u = f - i
    return pts[i].lerp(pts[i + 1], u), radii[i] + (radii[i + 1] - radii[i]) * u, (pts[i + 1] - pts[i]).normalized()


class Brancher:
    """Recursive bent-tube branching into one MeshBuilder (the G1 dead_tree generator, parametrized).
    `mat` = bark colour; `bark_fn(depth)` may override it per depth; `snowy` collects face ranges (depth <= 1) that
    get snow on their upper faces."""

    def __init__(self, rnd, mat="bark_grey", min_r=0.014):
        self.rnd = rnd
        self.mb = lp.MeshBuilder()
        self.snowy = []
        self.mat = mat
        self.min_r = min_r
        self.bands = []            # (face range, depth) for birch banding

    def limb(self, p0, d, length, r0, depth, segs, mat=None, taper=0.28, up=None, cap_mat=None):
        rnd = self.rnd
        pts, radii = [Vector(p0)], [r0]
        dd = d.normalized()
        r1 = max(self.min_r, r0 * taper)
        for k in range(1, segs + 1):
            wob = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-0.4, 0.7))) * 0.22
            dd = (dd + wob + Vector((0, 0, (0.06 if depth < 2 else -0.04) if up is None else up))).normalized()
            pts.append(pts[-1] + dd * (length / segs))
            radii.append(r0 + (r1 - r0) * k / segs)
        sides = 7 if r0 > 0.12 else 6 if r0 > 0.06 else 5 if r0 > 0.03 else 4
        f0 = len(self.mb.faces)
        H.tube(self.mb, pts, radii, sides, mat or self.mat, cap_end=True)
        if cap_mat is not None:
            self.mb.faces[-1][1] = cap_mat
        if depth <= 1:
            self.snowy.append((f0, len(self.mb.faces)))
        self.bands.append(((f0, len(self.mb.faces)), depth))
        return pts, radii

    def snow(self, zmin, nz=0.72):
        for a, b in self.snowy:
            self.mb.recolor(lambda n, c, m: n.z > nz and c.z > zmin, "snow", faces=range(a, b))


def bare_tree(seed=5, height=4.5, n1=9, n2=3, n3=2, top_twigs=4, trunk_r=0.27, trunk_len=6.2, lean=(0.05, 0.02),
              limb_k=1.0, t_range=(0.30, 0.62), mat="bark_grey", br=None, base=(0.0, 0.0), el_range=(38, 62),
              limb_cap=None, trunk_segs=5, trunk_taper=0.28):
    """The G1 dead_tree (defaults) as a Brancher; returns (brancher, trunk points, trunk radii, k_len).
    base = trunk foot (x, y); el_range = limb angle away from the trunk (deg); limb_cap = cap colour of the main
    limbs (e.g. "wood_light" for broken-off limbs)."""
    rnd = random.Random(seed)
    br = br or Brancher(rnd, mat)
    k_len = height / 6.4                              # the look-dev tree is 6.4 m tall
    tpts, trad = br.limb((base[0], base[1], -0.15), Vector((lean[0], lean[1], 1)), trunk_len * k_len, trunk_r, 0,
                         trunk_segs, taper=trunk_taper)
    for k in range(n1):
        t = t_range[0] + t_range[1] * k / max(1, n1 - 1) + rnd.uniform(-0.03, 0.03)
        p, r, d = radius_at(tpts, trad, t)
        dir1 = rot_towards(d, k * 137.5 + rnd.uniform(-20, 20), rnd.uniform(*el_range) - 18 * t)
        L1 = (2.4 - 1.5 * t) * rnd.uniform(0.85, 1.15) * (0.35 + 0.65 * k_len) * limb_k
        p1, r1 = br.limb(p, dir1, L1, max(0.035, r * 0.55), 1, 3, cap_mat=limb_cap)
        for j in range(n2):
            q, rq, dq = radius_at(p1, r1, 0.35 + 0.22 * j + rnd.uniform(-0.05, 0.05))
            dir2 = rot_towards(dq, rnd.uniform(0, 360), rnd.uniform(28, 55))
            p2, r2 = br.limb(q, dir2, L1 * rnd.uniform(0.4, 0.6), max(0.022, rq * 0.62), 2, 2)
            for m in range(n3):
                q3, rq3, dq3 = radius_at(p2, r2, 0.45 + 0.4 * m)
                dir3 = rot_towards(dq3, rnd.uniform(0, 360), rnd.uniform(25, 50))
                br.limb(q3, dir3, L1 * rnd.uniform(0.22, 0.32), max(0.014, rq3 * 0.7), 3, 2)
    for k in range(top_twigs):
        p, r, d = radius_at(tpts, trad, 0.96)
        br.limb(p, rot_towards(d, k * 90 + 20, 30), 0.8 * k_len, 0.03, 3, 2)
    return br, tpts, trad, k_len


# ------------------------------------------------------------------------------------------------------------
# surfaces, caps, lobes
# ------------------------------------------------------------------------------------------------------------
def surface_fn(objs, default=0.0):
    """z(x, y) of the top of `objs` (ray cast straight down against all of them)."""
    if not isinstance(objs, (list, tuple)):
        objs = [objs]
    verts, polys = [], []
    for o in objs:
        mw = o.matrix_world
        base = len(verts)
        verts += [mw @ v.co for v in o.data.vertices]
        polys += [tuple(base + i for i in p.vertices) for p in o.data.polygons]
    tree = BVHTree.FromPolygons(verts, polys)

    def z(x, y):
        hit = tree.ray_cast(Vector((x, y, 50.0)), Vector((0, 0, -1)), 100.0)
        return hit[0].z if hit[0] is not None else default
    return z


def color_by_normal(mb, faces, top="snow", side="stone", under="stone_dark", top_nz=None, under_nz=0.12):
    for fi in faces:
        nz = mb.normal(fi).z
        if top_nz is not None and nz > top_nz:
            mb.faces[fi][1] = top
        elif nz < under_nz:
            mb.faces[fi][1] = under
        else:
            mb.faces[fi][1] = side


def lobes(specs, rnd, mat="pine_light", under="pine_dark", under_nz=-0.15, clamp=0.0, jitter=0.12):
    """Faceted jittered icosphere lobes (bush clumps / boulders): specs [(centre, radii, subdiv)] -> MeshBuilder."""
    mb = lp.MeshBuilder()
    for center, radii, subdiv in specs:
        f0 = len(mb.faces)
        mb.blob(center, radii, mat, subdiv=subdiv, jitter=jitter, rnd=rnd, clamp_z=clamp, drop_bottom=True)
        for fi in range(f0, len(mb.faces)):
            if mb.normal(fi).z < under_nz:
                mb.faces[fi][1] = under
    return mb


def heap(center, rx, ry, height, seed=0, sides=16, rings=5, sink=0.05, lobes_=(), noise=0.08, crest=None,
         mat="snow", crest_mat="snow_deep", yaw=0.0):
    """Smooth snow heap: radial grid (rings x sides) with a bell profile + extra gaussian lobes
    [(dx, dy, r, h)] + fbm noise; rim sunk `sink` below z; faces above `crest` (height fraction) coloured crest_mat.
    Open bottom, smooth shaded."""
    c = Vector(center)
    rnd = random.Random(seed)
    jit = [rnd.uniform(0.9, 1.1) for _ in range(sides)]
    cy, sy = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))

    def hgt(x, y):
        u = x / rx
        v = y / ry
        d2 = u * u + v * v
        z = height * max(0.0, 1.0 - d2) ** 1.4
        for dx, dy, r, hh in lobes_:
            z += hh * math.exp(-((x - dx) ** 2 + (y - dy) ** 2) / (r * r))
        z *= 1.0 + noise * H.fbm(x * 0.9 + seed, y * 0.9, 2, seed)
        return z
    mb = lp.MeshBuilder()
    rows = []
    zmax = 0.0
    for k in range(rings + 1):
        t = k / rings
        if k == rings:
            z = hgt(0.0, 0.0)
            rows.append([c + Vector((0, 0, z))])
            zmax = max(zmax, z)
            break
        row = []
        for i in range(sides):
            a = 2 * math.pi * i / sides
            s = (1.0 - t) ** 0.85
            x = math.cos(a) * rx * s * jit[i]
            y = math.sin(a) * ry * s * jit[i]
            z = hgt(x, y) if k else -sink
            zmax = max(zmax, z)
            row.append(c + Vector((x * cy - y * sy, x * sy + y * cy, z)))
        rows.append(row)
    faces = mb.loft(rows, mat, cap_start=False, cap_end=False, inside=c + Vector((0, 0, -1.0)))
    if crest is not None:
        for fi in faces:
            if mb.center(fi).z > crest * zmax and mb.normal(fi).z > 0.8:
                mb.faces[fi][1] = crest_mat
    return H.smooth(H.mk(mb))


def log_body(p0, p1, r0, r1, sides=10, mat="bark", segs=3, bend=0.0, seed=0, cap0="rings", cap1="rings",
             wobble=0.015):
    """Smooth bark tube from p0 to p1 (slightly bent), end caps: "rings" (sawn face with growth rings, flat),
    "broken" (splintered cone), None (open). Returns list of objects."""
    rnd = random.Random(seed)
    p0, p1 = Vector(p0), Vector(p1)
    ax = (p1 - p0)
    L = ax.length
    d = ax.normalized()
    side = d.cross(Z).normalized() if abs(d.z) < 0.95 else Vector((1, 0, 0))
    pts, radii = [], []
    for k in range(segs + 1):
        t = k / segs
        off = side * (bend * math.sin(math.pi * t)) + Vector((rnd.uniform(-wobble, wobble), rnd.uniform(-wobble, wobble),
                                                              0.0 if k in (0, segs) else rnd.uniform(-wobble, wobble)))
        pts.append(p0 + d * (L * t) + off)
        radii.append(r0 + (r1 - r0) * t)
    mb = lp.MeshBuilder()
    rings = []
    for i, p in enumerate(pts):
        if i == 0:
            t = pts[1] - pts[0]
        elif i == len(pts) - 1:
            t = pts[-1] - pts[-2]
        else:
            t = pts[i + 1] - pts[i - 1]
        rings.append(lp.ring(p, t, radii[i], sides, rnd.uniform(0, 30)))
    mb.loft(rings, mat, cap_start=False, cap_end=False)
    out = [H.smooth(H.mk(mb), angle=70)]
    for cap, ring_, p, tangent in ((cap0, rings[0], pts[0], pts[0] - pts[1]), (cap1, rings[-1], pts[-1], pts[-1] - pts[-2])):
        if cap == "rings":
            out.append(ring_cap(ring_, p, tangent.normalized()))
        elif cap == "broken":
            out.append(broken_cap(ring_, p, tangent.normalized(), rnd))
    return out, pts, radii


def ring_cap(ring_, center, normal, inset=0.004):
    """Flat sawn face closing `ring_`: bark rim -> sapwood -> ring -> heart (growth rings)."""
    c = Vector(center)
    n = Vector(normal).normalized()
    mb = lp.MeshBuilder()
    radii = [(1.0, "bark"), (0.86, "wood_light"), (0.62, "wood"), (0.52, "wood_light"), (0.24, "wood")]
    prev = None
    for k, (f, mat) in enumerate(radii):
        ring = [c + (p - c) * f - n * (inset if k else 0.0) for p in ring_]
        if prev is not None:
            mb.loft([prev[0], ring], prev[1], cap_start=False, cap_end=False, seg_facing=[n])
        prev = (ring, mat)
    mb.loft([prev[0], [c - n * inset]], prev[1], cap_start=False, cap_end=False, seg_facing=[n])
    return H.flat(H.mk(mb))


def broken_cap(ring_, center, normal, rnd, length=0.22):
    """Splintered end: jagged spikes from the rim (wood_light inside, bark tips)."""
    c = Vector(center)
    n = Vector(normal).normalized()
    mb = lp.MeshBuilder()
    m = len(ring_)
    tips = []
    for i in range(m):
        p = ring_[i]
        k = rnd.uniform(0.15, 1.0) if i % 2 == 0 else rnd.uniform(0.0, 0.35)
        tips.append(c.lerp(p, 0.55) + n * (length * k))
    for i in range(m):
        a, b = ring_[i], ring_[(i + 1) % m]
        mb.add_face((mb._v(a), mb._v(b), mb._v(tips[(i + 1) % m]), mb._v(tips[i])), "wood_light",
                    inside=c - n * 0.05)
    mb.loft([tips, [c + n * (length * 0.15)]], "wood_light", cap_start=False, cap_end=False, seg_facing=[n])
    return H.flat(H.mk(mb))


def snow_on_log(pts, radii, width_k=1.2, thick=0.07, seed=0, trim=0.08):
    """Rounded snow line along the top of a (nearly horizontal) log."""
    a, b = Vector(pts[0]), Vector(pts[-1])
    d = (b - a).normalized()
    a = a + d * trim
    b = b - d * trim
    r = (radii[0] + radii[-1]) / 2
    top_a = a + Vector((0, 0, radii[0] * 0.92))
    top_b = b + Vector((0, 0, radii[-1] * 0.92))
    return H.snow_strip(top_a, top_b, r * width_k, thick, seed=seed, overhang=0.0, droop=0.03)


# ------------------------------------------------------------------------------------------------------------
# MultiMesh export (ASSET_SPEC_V2 §13 + "M3"): one object, one surface, no children / empties / collision.
# The collision PROXY the code builds per variant travels as node extras (Godot: get_meta("extras")) and in
# assets/models/vegetation/manifest.json, in the model's GODOT local frame (Y up, +Z = front):
#   col = "cylinder" (col_size = [radius, height]) | "sphere" ([radius]) | "box" ([sx, sy, sz]) | "none",
#   col_center = [x, y, z] (centre of the shape), family, height (m, top), radius (m, footprint for spacing),
#   choppable (1 = axe interaction like the slice trees / logs).
# ------------------------------------------------------------------------------------------------------------
MANIFEST_KEYS = ("family", "height", "radius", "col", "col_center", "col_size", "choppable")


def godot(p):
    """Blender (x, y, z) -> Godot (x, z, -y)."""
    return [round(float(p[0]), 3) + 0.0, round(float(p[2]), 3) + 0.0, round(-float(p[1]), 3) + 0.0]


def scatter_meta(obj, family, col, col_center_bl=(0, 0, 0), col_size=(), choppable=False):
    """Custom props (-> glTF extras) on the single MultiMesh object. col_center_bl in Blender coordinates."""
    from .hd import scene_bounds
    mn, mx = scene_bounds([obj])
    obj["family"] = family
    obj["height"] = round(float(mx.z), 3)
    obj["radius"] = round(float(max(abs(mn.x), abs(mx.x), abs(mn.y), abs(mx.y))), 3)
    obj["col"] = col
    obj["col_center"] = godot(col_center_bl)
    obj["col_size"] = [round(float(v), 3) for v in col_size]
    obj["choppable"] = 1 if choppable else 0
    return obj


def export_scatter(asset, parts, obj_name, family, col, col_center_bl=(0, 0, 0), col_size=(), choppable=False,
                   ao=None, subdir="vegetation"):
    """Join `parts` into the one object `obj_name`, attach the scatter metadata, bake AO, export
    assets/models/<subdir>/<asset>.glb (+ .import template) and record it in <subdir>/manifest.json."""
    import json
    from . import export
    obj = H.join(parts, obj_name)
    scatter_meta(obj, family, col, col_center_bl, col_size, choppable)
    glb = export.save_and_export(asset, subdir=subdir, ao=ao if ao is not None else True, import_kind="prop")
    man = export.MODELS_DIR / subdir / "manifest.json"
    data = {}
    if man.exists():
        try:
            data = json.loads(man.read_text())
        except ValueError:
            data = {}
    rec = {k: obj[k] if not hasattr(obj[k], "to_list") else obj[k].to_list() for k in MANIFEST_KEYS}
    rec["path"] = "res://assets/models/%s/%s.glb" % (subdir, asset)
    rec["node"] = obj_name
    rec["tris"] = lp.scene_tris()
    data[asset] = rec
    text = json.dumps(dict(sorted(data.items())), indent=1, sort_keys=True) + "\n"
    if not man.exists() or man.read_text() != text:
        man.write_text(text)
    return glb
