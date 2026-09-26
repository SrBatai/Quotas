"""terrain_tile_hd (+ footprint_hd) - HD look-dev snow terrain (guidelines v2.1).

    cd winter-survival/prototypes/lookdev/blender && python3 build_terrain_hd.py

A 44 x 44 m tile centred on the cabin plot (cabin at the origin, porch toward -Y Blender = +Z Godot):
  * rolling snow (two octaves of noise, 0.35 m + 0.12 m), flattened under the cabin footprint;
  * a trodden footpath from the porch steps (1.4 m wide, 12 cm deep, packed-snow colour) with soft berms;
  * a plowed track (3 m) with 0.45 m snowbanks crossing the plot diagonally (the long ridges of the reference);
  * three wind drifts (asymmetric profile: long windward ramp, short steep lee side);
  * `Footprints`: a trail of boot prints with raised rims along the footpath (geometry ON the surface: rim ring +
    darker floor, the shape the game's trail system can instance). footprint_hd.glb = one print (MultiMesh).
Smooth normals everywhere (the comparison file terrain_flat_1m_ref.glb = same heights sampled at 1 m, flat shaded,
like the game's terrain_chunk today). Grid 0.4 m (look-dev); in game: 0.5 m within ~30 m of the camera.
"""
import json
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import hdlib as H  # noqa: E402
from hdlib import lp  # noqa: E402
from mathutils import Vector  # noqa: E402

SIZE = 44.0
CENTER = (2.0, -4.0)
STEP = 0.4

PATH = [(0.9, -5.35), (0.75, -7.2), (0.1, -9.4), (-1.4, -11.6), (-3.8, -13.9), (-7.0, -16.4), (-11.0, -19.2),
        (-16.0, -22.5)]
ROAD_A, ROAD_B = Vector((-18.0, -31.0)), Vector((22.0, 3.0))
DRIFTS = [((-9.5, 3.5), (0.83, 0.55), 8.0, 2.4, 0.65), ((11.0, 9.0), (0.83, 0.55), 7.0, 2.0, 0.55),
          ((12.5, -12.0), (0.83, 0.55), 6.0, 2.2, 0.5)]
CABIN = (-3.35, -5.45, 3.95, 2.85)          # x0, y0, x1, y1 footprint incl. porch, steps, chimney


def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
    return (p - (a + ab * t)).length, t


def path_dist(p):
    best = (1e9, 0.0, Vector((1, 0)))
    acc = 0.0
    total = 0.0
    for a, b in zip(PATH, PATH[1:]):
        total += (Vector(b) - Vector(a)).length
    for a, b in zip(PATH, PATH[1:]):
        a, b = Vector(a), Vector(b)
        d, t = seg_dist(p, a, b)
        if d < best[0]:
            best = (d, (acc + t * (b - a).length) / total, (b - a).normalized())
        acc += (b - a).length
    return best


def rect_dist(x, y, r):
    x0, y0, x1, y1 = r
    dx = max(x0 - x, 0.0, x - x1)
    dy = max(y0 - y, 0.0, y - y1)
    return math.hypot(dx, dy)


def height(x, y):
    """Analytic height (m) and packed-snow weight 0..1 (paths, track bed)."""
    p = Vector((x, y))
    h = 0.35 * H.fbm(x / 14.0, y / 14.0, 2, 3.1) + 0.12 * H.fbm(x / 4.5, y / 4.5, 2, 7.7)
    h += 0.018 * (x + 4) - 0.012 * y                              # gentle overall slope
    # flatten the cabin plot
    dc = rect_dist(x, y, CABIN)
    k = H.smoothstep(0.0, 2.5, dc)
    h = h * k
    tag = 0.0
    # footpath (starts at the steps: no berm before t=0.02)
    d, t, _ = path_dist(p)
    if d < 3.0:
        depth = 0.12 * (1 - H.smoothstep(0.45, 0.78, d))
        berm = 0.13 * math.exp(-((d - 1.05) / 0.35) ** 2) * H.smoothstep(0.0, 0.05, t)
        h += berm - depth
        tag = max(tag, 1 - H.smoothstep(0.35, 0.85, d))
    # plowed track with snowbanks
    d2, t2 = seg_dist(p, ROAD_A, ROAD_B)
    if d2 < 4.5:
        bed = 1 - H.smoothstep(1.3, 1.7, d2)
        crest = 0.45 + 0.08 * H.fbm(t2 * 25.0, 0.5, 2, 1.0)
        bank = crest * math.exp(-((d2 - 2.25) / 0.55) ** 2)
        h = h * (1 - bed) + (-0.10) * bed + bank
        tag = max(tag, 1 - H.smoothstep(1.1, 1.8, d2))
    # wind drifts
    for (cx, cy), (wx, wy), L, W, Hd in DRIFTS:
        w = Vector((wx, wy)).normalized()
        n = Vector((-w.y, w.x))
        q = p - Vector((cx, cy))
        a, b = q.dot(w) / (L / 2), q.dot(n) / (W / 2)
        if abs(a) < 1.3 and abs(b) < 1.6:
            along = math.exp(-a * a * 2.2)
            across = math.exp(-(b / (0.55 if b > 0 else 1.1)) ** 2 * 2.0)     # steep lee side (b > 0)
            h += Hd * along * across
    return h, tag


def build_tile(step=STEP, smooth_normals=True, name="Terrain"):
    n = int(round(SIZE / step))
    x0, y0 = CENTER[0] - SIZE / 2, CENTER[1] - SIZE / 2
    mb = lp.MeshBuilder()
    rows, tags = [], []
    for j in range(n + 1):
        r, tr = [], []
        for i in range(n + 1):
            x, y = x0 + i * step, y0 + j * step
            h, tag = height(x, y)
            r.append(Vector((x, y, h)))
            tr.append(tag)
        rows.append(r)
        tags.append(tr)

    H.grid_quads(mb, rows, "snow", (0, 0, 1))
    o = H.mk(mb, name)
    # terrain exception to "one palette colour per face": packed snow is blended PER VERTEX (like the game's
    # terrain shader does with its surface mask), so path edges are soft instead of saw-toothed.
    flat_w = [w for r in tags for w in r]
    me = o.data
    col = me.color_attributes[H.palette.VCOL_ATTR]
    a, b = H.palette.vcol_rgba("snow"), H.palette.vcol_rgba("snow_packed")
    data = [0.0] * (len(me.loops) * 4)
    col.data.foreach_get("color", data)
    vi = [0] * len(me.loops)
    me.loops.foreach_get("vertex_index", vi)
    for li, v in enumerate(vi):
        w = flat_w[v]
        for k in range(3):
            data[li * 4 + k] = a[k] + (b[k] - a[k]) * w
    col.data.foreach_set("color", data)
    if smooth_normals:
        H.smooth(o)
    else:
        H.flat(o)
    return o


def footprint_mb(mb, cx, cy, heading, rnd, hfun=None, scale=1.0, left=True):
    """One boot print: oval rim ring (raised 6 cm) + darker floor, sitting on the surface."""
    a, b = 0.22 * scale, 0.13 * scale
    segs = 12
    c, s = math.cos(heading), math.sin(heading)

    def P(u, v, dz):
        x = cx + u * c - v * s
        y = cy + u * s + v * c
        z = (hfun(x, y)[0] if hfun else 0.0) + dz
        return Vector((x, y, z))
    rings = []
    for k, (sc, dz) in enumerate(((1.42, -0.02), (1.16, 0.045), (0.94, 0.03), (0.80, 0.006))):
        ring = []
        for i in range(segs):
            t = 2 * math.pi * i / segs
            wob = 1.0 + (0.06 * rnd.uniform(-1, 1) if k < 2 else 0.0)
            # boot shape: slightly narrower heel (u < 0)
            bb = b * (0.85 if math.cos(t) < 0 else 1.0)
            ring.append(P(a * sc * wob * math.cos(t), bb * sc * wob * math.sin(t), dz))
        rings.append(ring)
    f0 = len(mb.faces)
    mb.loft(rings, "snow", cap_start=False, cap_end=False, inside=P(0, 0, -0.5))
    for fi in range(f0, len(mb.faces)):
        mb.faces[fi][2] = False
    centre = P(0, 0, 0.004)
    last = rings[-1]
    for i in range(segs):
        mb.poly([last[i], last[(i + 1) % segs], centre], "snow_hole", facing=(0, 0, 1))
    # the inner wall of the rim takes the floor colour too, so the print reads as a hole
    for fi in range(f0 + 2 * segs, f0 + 3 * segs):
        mb.faces[fi][1] = "snow_shadow"
    return mb


def build_footprints(rnd):
    mb = lp.MeshBuilder()
    # walk the footpath from the steps: prints every 0.72 m alternating +-0.13 m
    pts = [Vector(p) for p in PATH]
    dist = 0.5
    step = 0.72
    k = 0
    seg_len = [(b - a).length for a, b in zip(pts, pts[1:])]
    total = sum(seg_len)
    while dist < min(total, 19.0):
        acc, i = 0.0, 0
        while i < len(seg_len) - 1 and acc + seg_len[i] < dist:
            acc += seg_len[i]
            i += 1
        t = (dist - acc) / seg_len[i]
        p = pts[i].lerp(pts[i + 1], t)
        d = (pts[i + 1] - pts[i]).normalized()
        nrm = Vector((-d.y, d.x))
        side = 1 if k % 2 == 0 else -1
        q = p + nrm * (0.13 * side) + d * rnd.uniform(-0.04, 0.04)
        heading = math.atan2(d.y, d.x) + rnd.uniform(-0.12, 0.12)
        footprint_mb(mb, q.x, q.y, heading, rnd, height, 1.0, side > 0)
        dist += step * rnd.uniform(0.92, 1.08)
        k += 1
    o = H.smooth(H.mk(mb, "Footprints"))
    return o, k


def build():
    H.new_scene()
    rnd = random.Random(12)
    terrain = build_tile()
    fp, count = build_footprints(rnd)
    t = H.bake_ao([terrain, fp], distance=1.2, samples=48, ground=False)
    print("AO bake %.1f s, %d footprints" % (t, count))
    glb, tris, surf, per = H.export_hd("terrain_tile_hd")
    H.write_manifest_entry("terrain_tile_hd", {
        "file": "terrain_tile_hd.glb", "tris": tris, "parts": per,
        "extent_m": [CENTER[0] - SIZE / 2, CENTER[1] - SIZE / 2, CENTER[0] + SIZE / 2, CENTER[1] + SIZE / 2],
        "placement": "origin = cabin_hd origin (cabin plot flattened to z=0; porch steps at Godot (0.9, 0, 5.35))",
        "note": "look-dev reference for terrain.gdshader/terrain_chunk: smooth normals, 0.4 m grid, path/berms/"
                "snowbanks/drifts; Footprints = rim-ring prints on the path"})
    # placements for scene renders (trees on the terrain) -------------------------------------------------
    place = {"pine_hd_a": [(-8.0, 6.5), (7.5, 9.5), (-13.0, -4.0), (13.5, 1.0), (-2.5, 12.5)],
             "pine_hd_b": [(-6.0, 1.5), (9.5, 5.0), (-11.0, 9.5), (4.0, 13.0), (15.0, -6.5), (-15.5, 2.5)],
             "bare_tree_hd": [(-6.5, -9.0), (8.5, -3.0), (5.5, 7.5), (-14.0, -12.5)]}
    out = {k: [(x, y, round(height(x, y)[0], 3)) for x, y in v] for k, v in place.items()}
    out["survivor"] = [(0.55, -8.2, round(height(0.55, -8.2)[0], 3))]
    with open(os.path.join(H.OUT_DIR, "lookdev_layout.json"), "w") as f:
        json.dump({"comment": "Blender coords (x, y, z); Godot = (x, z, -y). Suggested look-dev layout.",
                   "items": out}, f, indent=1)
    # single print for MultiMesh / trail stamping --------------------------------------------------------
    H.new_scene()
    mb = lp.MeshBuilder()
    footprint_mb(mb, 0.0, 0.0, -math.pi / 2, random.Random(3))    # toe toward -Y (model front)
    o = H.smooth(H.mk(mb, "Footprint"))
    H.bake_ao([o], distance=0.25, samples=48, ground=True, ground_z=-0.001)
    H.export_hd("footprint_hd")
    H.write_manifest_entry("footprint_hd", {"file": "footprint_hd.glb", "tris": 2 * 12 * 3 + 12,
                                            "note": "one boot print, toe toward +Z Godot, rim 5.5 cm; sits on the "
                                                    "surface (no hole needed)"})
    # comparison: same heights, 1 m grid, flat shaded (≈ the game's terrain_chunk today) -------------------
    H.new_scene()
    build_tile(step=1.0, smooth_normals=False, name="TerrainFlat")
    kw = dict(H.export.export_kwargs(False, False), filepath=os.path.join(H.SCRATCH, "terrain_flat_1m_ref.glb"),
              export_vertex_color='NAME', export_vertex_color_name="Col")
    with H.export.quiet():
        import bpy
        bpy.ops.export_scene.gltf(**kw)


if __name__ == "__main__":
    build()
