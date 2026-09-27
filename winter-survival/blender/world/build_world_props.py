"""W1 world props for the 6 x 6 km map (PLAN_MAESTRO Part II, W1 "Arte") — ASSET_SPEC_V2 §13 + "M3" + "T2".

    cd winter-survival/blender && python3 world/build_world_props.py [crest_rock_a guardrail ...]

Exports assets/models/world/<name>.glb (+ sources/<name>.blend + `.import`, template "prop") and
assets/models/world/manifest.json. Front = -Y Blender (+Z Godot), origin = centre of the base at z = 0.

MultiMesh families (the M3 contract, lib/veg.py export_scatter): ONE mesh, ONE palette surface, no children / empties /
Col*, collision proxy in the extras + manifest (family, col, col_center, col_size, height, radius, choppable):
  crest_rock_a / crest_rock_b / crest_spire / scree_field / cliff_face / cairn   node Rock  family rock
  cornice                                                                    node Snow  family snow
  snow_pole / snow_pole_tall / road_delineator                               node Pole  family pole
  guardrail / guardrail_end / guardrail_bent / parapet_stone                 node Rail  family rail
Rails are 4 m sections along X (x -2..+2, repeat every 4 m), the ROAD SIDE is -Y Blender (+Z Godot); poles and
delineators have their reflectors toward -Y (+Z Godot, face the traffic coming from +Z).

Structures (not MultiMesh):
  tunnel_portal / tunnel_portal_collapsed   `Portal` (headwall, wing walls, lining, floor, rock-and-snow hill cap),
      [`Rubble`], `Panel` (name plate for a Label3D) + `TextPanel`, `RoadIn` (road centre at the mouth), `Inside`
      (end of the walkable gallery), Col*-convcolonly boxes; extras on Portal: road_width, clearance, depth, carve
      (Godot [x0, x1, z0, z1]: the terrain must stay at or below the road level y = 0 there), blocked.
  km_sign / km_post   `Prop` + `Panel` (face for the kilometre number) + `TextPanel` (A1 sign contract).
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import bpy  # noqa: E402,F401
from mathutils import Matrix, Vector, noise  # noqa: E402

from lib import export  # noqa: E402
from lib import hd as H  # noqa: E402
from lib import lowpoly as lp  # noqa: E402
from lib import veg as V  # noqa: E402

SUBDIR = "world"
BUDGETS = {"rock": 1000, "cliff": 1200, "snow": 500, "pole": 250, "rail": 700, "portal": 14000, "sign": 400}


def godot(p):
    return V.godot(p)


# ------------------------------------------------------------------------------------------------------------
# rocks (faceted blobs + draped snow caps, the G1 / M3 recipe) — strata tilted for the crest look
# ------------------------------------------------------------------------------------------------------------
def rock_mass(blobs, dims, seed, tilt=(0.0, 0.0), shear=0.0, jitter=0.12, sink=0.04):
    rnd = lp.rng(seed)
    mb = lp.MeshBuilder()
    for center, radii, subdiv in blobs:
        mb.blob(center, radii, "stone", subdiv=subdiv, jitter=jitter if subdiv == 1 else jitter * 0.7, rnd=rnd,
                clamp_z=0.0, drop_bottom=True)
    lp.fit_bounds(mb, dims)
    for v in mb.verts:
        h = v.z / dims[2]
        v.x += shear * h * dims[2]
        v.z += tilt[0] * v.x * h + tilt[1] * v.y * h
        v.z -= sink
    V.color_by_normal(mb, range(len(mb.faces)), side="stone", under="stone_dark", under_nz=0.10)
    for fi in range(len(mb.faces)):                       # strata bands: every other band a touch darker
        c = mb.center(fi)
        if mb.faces[fi][1] == "stone" and int((c.z + 0.25 * c.x) / 0.45) % 3 == 1:
            mb.faces[fi][1] = "stone_dark"
    return H.flat(H.mk(mb))


def caps(body, specs, seed):
    zf = V.surface_fn(body)
    out = []
    for k, (x, y, rx, ry, t) in enumerate(specs):
        out.append(H.snow_cap((x, y, 0), rx, ry, t, zf, seed=seed + k, sides=12 if rx > 0.4 else 9, rings=3,
                              droop=0.03))
    return out


def crest_rock_a():
    body = rock_mass([((-1.2, 0.0, 0.9), (1.2, 0.8, 1.3), 2), ((0.4, 0.1, 1.1), (1.1, 0.9, 1.6), 2),
                      ((1.6, -0.1, 0.6), (0.8, 0.7, 0.9), 1), ((-2.0, 0.2, 0.3), (0.6, 0.6, 0.5), 1)],
                     (4.6, 2.3, 2.9), 101, tilt=(0.10, 0.0), shear=0.25)
    parts = [body] + caps(body, [(0.35, 0.1, 0.55, 0.45, 0.10), (-1.15, 0.0, 0.5, 0.4, 0.09),
                                 (1.6, -0.1, 0.35, 0.3, 0.07)], 101)
    parts.append(H.mound((-1.6, -1.1, 0), 0.9, 0.35, seed=103, sides=10, sink=0.08, stretch=(1.3, 0.8)))
    return parts, "Rock", "rock", "box", ((0.0, 0.0, 1.3), (4.2, 2.6, 2.0))


def crest_rock_b():
    body = rock_mass([((-0.8, 0.0, 0.4), (1.3, 0.9, 0.55), 2), ((0.6, 0.2, 0.55), (1.1, 0.8, 0.7), 2),
                      ((0.1, -0.5, 0.2), (0.9, 0.6, 0.35), 1)], (3.6, 2.4, 1.6), 111, tilt=(0.18, 0.05))
    parts = [body] + caps(body, [(-0.8, 0.0, 0.85, 0.6, 0.10), (0.65, 0.2, 0.7, 0.5, 0.09)], 111)
    return parts, "Rock", "rock", "box", ((0.0, 0.0, 0.7), (3.3, 1.4, 2.1))


def crest_spire():
    body = rock_mass([((0.0, 0.0, 1.2), (0.7, 0.6, 1.5), 2), ((0.15, 0.1, 2.8), (0.45, 0.4, 1.0), 1),
                      ((-0.3, -0.2, 0.3), (0.6, 0.55, 0.5), 1)], (1.7, 1.5, 4.3), 121, shear=0.12, jitter=0.14)
    parts = [body] + caps(body, [(0.28, 0.08, 0.22, 0.2, 0.06)], 121)
    parts.append(H.mound((0.0, -0.3, 0), 0.9, 0.22, seed=122, sides=10, sink=0.08, stretch=(1.1, 0.9)))
    return parts, "Rock", "rock", "cylinder", ((0.0, 0.0, 2.1), (0.7, 4.2))


def scree_field():
    rnd = random.Random(131)
    snow = V.heap((0, 0, 0), 2.6, 1.7, 0.30, seed=131, sides=16, rings=4, sink=0.06, noise=0.10)
    blobs = []
    for k in range(16):
        a = rnd.uniform(0, 2 * math.pi)
        r = math.sqrt(rnd.uniform(0.0, 1.0))
        x, y = math.cos(a) * r * 2.3, math.sin(a) * r * 1.5
        s = rnd.uniform(0.14, 0.34) * (1.2 - 0.4 * r)
        blobs.append(((x, y, s * 0.5), (s * 1.2, s, s * 0.8), 1 if s > 0.26 else 0))
    mb = lp.MeshBuilder()
    for center, radii, subdiv in blobs:
        mb.blob(center, radii, "stone", subdiv=subdiv, jitter=0.14, rnd=rnd, clamp_z=0.0, drop_bottom=True)
    V.color_by_normal(mb, range(len(mb.faces)), top="snow", side="stone", under="stone_dark", top_nz=0.8)
    stones = H.flat(H.mk(mb))
    return [snow, stones], "Rock", "rock", "box", ((0.0, 0.0, 0.2), (4.6, 0.4, 3.0))


def cliff_face():
    """Gorge cliff chunk 8 m wide, 6 m tall, ~2.5 m deep: faceted face toward -Y, ledges with snow, top snow."""
    rnd = random.Random(141)
    nx, nz = 13, 9
    W, Hh, D = 8.0, 6.0, 2.4
    mb = lp.MeshBuilder()

    def face_pt(i, k):
        x = -W / 2 + W * i / (nx - 1)
        z = Hh * k / (nz - 1)
        n = noise.noise(Vector((x * 0.45, z * 0.5, 7.1)))
        ledge = 0.35 * max(0.0, math.sin(z * 1.6 + x * 0.2)) ** 3
        y = -D / 2 + 0.55 * n - ledge + rnd.uniform(-0.08, 0.08)
        edge = min(i, nx - 1 - i)
        if edge == 0:
            y += 0.6
        return Vector((x + rnd.uniform(-0.12, 0.12) * (0 < i < nx - 1), y, z + (rnd.uniform(-0.1, 0.1) if 0 < k < nz - 1 else 0.0)))
    grid = [[face_pt(i, k) for i in range(nx)] for k in range(nz)]
    grid[0] = [Vector((p.x, p.y, -0.2)) for p in grid[0]]
    idx = [[mb._v(p) for p in row] for row in grid]
    back = [[mb._v((p.x, D / 2 + 0.3 * math.sin(p.x), p.z)) for p in row] for row in grid]
    for k in range(nz - 1):
        for i in range(nx - 1):
            mb.add_face((idx[k][i], idx[k][i + 1], idx[k + 1][i + 1], idx[k + 1][i]), "stone", facing=(0, -1, 0.2))
            mb.add_face((back[k][i], back[k + 1][i], back[k + 1][i + 1], back[k][i + 1]), "stone_dark", facing=(0, 1, 0))
    top = nz - 1
    for i in range(nx - 1):                                                   # top (snow) strip
        mb.add_face((idx[top][i], back[top][i], back[top][i + 1], idx[top][i + 1]), "snow", facing=(0, 0, 1))
    for i0, sgn in ((0, -1), (nx - 1, 1)):                                    # side walls
        for k in range(nz - 1):
            mb.add_face((idx[k][i0], back[k][i0], back[k + 1][i0], idx[k + 1][i0]), "stone_dark", facing=(sgn, 0, 0))
    mb.triangulate_nonplanar()
    for fi in range(len(mb.faces)):
        n = mb.normal(fi)
        if mb.faces[fi][1] == "stone" and n.z > 0.45:
            mb.faces[fi][1] = "snow"
        elif mb.faces[fi][1] == "stone" and n.z < -0.2:
            mb.faces[fi][1] = "stone_dark"
    body = H.flat(H.mk(mb))
    drift = H.mound((0.5, -D / 2 - 0.6, 0), 1.6, 0.45, seed=142, sides=12, sink=0.08, stretch=(2.2, 0.8))
    return [body, drift], "Rock", "rock", "box", ((0.0, 0.0, 3.0), (7.6, 6.0, 2.4))


def cairn():
    rnd = random.Random(151)
    mb = lp.MeshBuilder()
    z = 0.0
    for k, (r, h) in enumerate(((0.55, 0.30), (0.45, 0.28), (0.36, 0.26), (0.26, 0.22), (0.17, 0.18))):
        for j in range(4 if k < 3 else (2 if k == 3 else 1)):
            a = j * math.pi / 2 + k * 0.6
            off = 0.0 if k >= 4 else r * 0.45
            c = (math.cos(a) * off, math.sin(a) * off, z + h * 0.5)
            mb.blob(c, (r * 0.62, r * 0.55, h * 0.55), "stone", subdiv=0, jitter=0.10, rnd=rnd, clamp_z=0.0,
                    drop_bottom=True)
        z += h * 0.82
    V.color_by_normal(mb, range(len(mb.faces)), top="snow", side="stone", under="stone_dark", top_nz=0.78)
    body = H.flat(H.mk(mb))
    return [body], "Rock", "rock", "cylinder", ((0.0, 0.0, 0.5), (0.55, 1.0))


def cornice():
    """Wind cornice 6 m along X: windward ramp from +Y rising to a crest over -Y with an overhanging lip (lee side
    -Y). Closed (flat bottom sunk 0.2 m); every face oriented by its own profile edge (the lip is concave)."""
    rnd = random.Random(161)
    prof = [(1.40, -0.20), (1.30, 0.10), (0.80, 0.55), (0.20, 1.00), (-0.35, 1.20), (-0.75, 1.12), (-0.92, 0.95),
            (-0.80, 0.80), (-0.55, 0.62), (-0.52, -0.20)]
    area = sum(prof[i][0] * prof[(i + 1) % len(prof)][1] - prof[(i + 1) % len(prof)][0] * prof[i][1]
               for i in range(len(prof)))
    sgn = 1.0 if area > 0 else -1.0                        # CCW in (y, z): outward normal = (dz, -dy)
    n = 9
    mb = lp.MeshBuilder()
    rings = []
    for i in range(n):
        x = -3.0 + 6.0 * i / (n - 1)
        s = 1.0 - 0.55 * (abs(x) / 3.0) ** 2.5
        row = []
        for j, (y, z) in enumerate(prof):
            jit = rnd.uniform(-0.04, 0.04) if 0 < j < len(prof) - 1 else 0.0
            zz = z if z < 0 else z * s
            row.append(mb._v((x, y * (0.75 + 0.25 * s) + jit, zz + jit)))
        rings.append(row)
    m = len(prof)
    for i in range(n - 1):
        for j in range(m):
            k = (j + 1) % m
            a, b = mb.verts[rings[i][j]], mb.verts[rings[i][k]]
            dy, dz = b.y - a.y, b.z - a.z
            out = Vector((0.0, dz, -dy)) * sgn
            mb.add_face((rings[i][j], rings[i][k], rings[i + 1][k], rings[i + 1][j]), "snow", facing=out)
    mb.add_face(tuple(rings[0]), "snow", facing=(-1, 0, 0))
    mb.add_face(tuple(reversed(rings[-1])), "snow", facing=(1, 0, 0))
    mb.triangulate_nonplanar()
    for fi in range(len(mb.faces)):
        nz = mb.normal(fi).z
        c = mb.center(fi)
        mb.faces[fi][1] = "snow_deep" if nz > 0.6 and c.z > 0.8 else ("snow_shadow" if nz < 0.0 else "snow")
    body = H.smooth(H.mk(mb), 60.0)
    return [body], "Snow", "snow", "box", ((0.0, 0.3, 0.5), (5.5, 1.0, 2.0))


# ------------------------------------------------------------------------------------------------------------
# road markers
# ------------------------------------------------------------------------------------------------------------
def banded_pole(mb, h, r, band, mats, sides=8, z0=-0.2):
    zs = [z0, 0.0]
    z = 0.0
    while z < h - 1e-6:
        z = min(h, z + band)
        zs.append(z)
    rings = [lp.ring(Vector((0, 0, zz)), Vector((0, 0, 1)), r, sides) for zz in zs]
    side = [mats[0]] + [mats[(k % 2)] for k in range(len(zs) - 2)]
    mb.loft(rings, side[0], side_mats=side, cap_mats=(mats[0], mats[1]))


def snow_pole(h=2.0, mats=("paint_red", "paint_white"), band=0.25):
    mb = lp.MeshBuilder()
    banded_pole(mb, h, 0.022 if h < 3 else 0.03, band, mats, sides=6)
    mb.box((-0.03, -0.028, h - 0.20), (0.03, -0.018, h - 0.08), "hivis_orange")             # reflector (road side)
    body = H.smooth(H.mk(mb), 50.0)
    mound = H.mound((0, 0, 0), 0.22, 0.10, seed=171, sides=8, sink=0.05)
    return [body, mound], "Pole", "pole", "cylinder", ((0.0, 0.0, h / 2), (0.05, h))


def snow_pole_tall():
    return snow_pole(4.0, ("paint_yellow", "paint_black"), band=0.5)


def road_delineator():
    """Spanish 'hito de arista': white post with a trapezoid section, black band, amber reflector toward -Y."""
    mb = lp.MeshBuilder()
    rings = []
    for z, s in ((-0.15, 1.0), (0.0, 1.0), (0.78, 0.92), (0.86, 0.90), (0.98, 0.88), (1.05, 0.70)):
        rings.append([Vector((x * s, y * s, z)) for x, y in ((0.06, 0.05), (0.03, -0.06), (-0.03, -0.06), (-0.06, 0.05))])
    mb.loft(rings, "paint_white", side_mats=["paint_white", "paint_white", "paint_black", "paint_white", "paint_white"],
            cap_mats=("paint_white", "paint_white"))
    mb.box((-0.022, -0.068, 0.87), (0.022, -0.050, 0.97), "hivis_orange")
    body = H.flat(H.mk(mb))
    return [body], "Pole", "pole", "box", ((0.0, 0.0, 0.52), (0.14, 1.05, 0.14))


# ------------------------------------------------------------------------------------------------------------
# rails (4 m sections along X, road side -Y)
# ------------------------------------------------------------------------------------------------------------
W_PROF = [(-0.02, 0.43), (-0.085, 0.47), (-0.055, 0.56), (-0.085, 0.65), (-0.02, 0.69), (0.00, 0.69), (0.00, 0.43)]


def w_beam(mb, x0, x1, z_of=None, y_of=None, segs=4):
    """W-beam along X from x0 to x1 (profile W_PROF in YZ), optionally bent: z_of(x) / y_of(x) offsets."""
    rings = []
    for k in range(segs + 1):
        x = x0 + (x1 - x0) * k / segs
        dz = z_of(x) if z_of else 0.0
        dy = y_of(x) if y_of else 0.0
        rings.append([Vector((x, y + dy, z + dz)) for y, z in W_PROF])
    faces = mb.loft(rings, "chrome", cap_start=True, cap_end=True)
    for fi in faces:
        n = mb.normal(fi)
        if n.y > 0.5:
            mb.faces[fi][1] = "metal_sheet"                           # back of the beam (not polished)
    return faces


def rail_post(mb, x, lean=0.0, h=0.78):
    top = Vector((x + lean, 0.05, h))
    mb.hexa([(x - 0.05, 0.01, -0.2), (x + 0.05, 0.01, -0.2), (x - 0.05, 0.10, -0.2), (x + 0.05, 0.10, -0.2),
             (top.x - 0.05, 0.01, h), (top.x + 0.05, 0.01, h), (top.x - 0.05, 0.10, h), (top.x + 0.05, 0.10, h)],
            "metal_sheet")
    mb.box((top.x - 0.04, -0.01, 0.50 - lean * 0.2), (top.x + 0.04, 0.012, 0.62), "iron")       # spacer block


def rail_snow(parts, x0, x1, z, seed, y=-0.042):
    parts.append(H.snow_ridge((x0, y, z), (x1, y, z), 0.09, 0.05, seed=seed, segs=5))


def guardrail():
    mb = lp.MeshBuilder()
    for x in (-1.0, 1.0):
        rail_post(mb, x)
    w_beam(mb, -2.02, 2.02)
    body = H.smooth(H.mk(mb), 35.0)
    parts = [body]
    rail_snow(parts, -2.0, 2.0, 0.69, 181)
    for x in (-1.0, 1.0):
        parts.append(H.snow_cone_cap((x, 0.055, 0.0), 0.055, 0.78, 0.82, 0.03, seed=182 + int(x), sides=6))
    parts.append(H.mound((0.2, 0.05, 0), 0.9, 0.16, seed=183, sides=10, sink=0.08, stretch=(2.0, 0.35)))
    return parts, "Rail", "rail", "box", ((0.0, 0.0, 0.4), (4.0, 0.8, 0.25))


def guardrail_end():
    """Terminal section: the beam twists down to the ground (buried end) toward +X."""
    mb = lp.MeshBuilder()
    rail_post(mb, -1.0)
    rail_post(mb, 0.6, h=0.62)

    def zdrop(x):
        return 0.0 if x < 0.4 else -0.62 * min(1.0, (x - 0.4) / 1.6) ** 1.2
    w_beam(mb, -2.02, 2.0, z_of=zdrop, y_of=lambda x: 0.0 if x < 0.4 else 0.18 * (x - 0.4) / 1.6, segs=8)
    body = H.smooth(H.mk(mb), 35.0)
    parts = [body]
    rail_snow(parts, -2.0, 0.4, 0.69, 191)
    parts.append(H.mound((1.3, 0.1, 0), 0.5, 0.20, seed=192, sides=10, sink=0.08, stretch=(1.2, 0.9)))
    return parts, "Rail", "rail", "box", ((0.0, 0.0, 0.4), (4.0, 0.8, 0.3))


def guardrail_bent():
    """Damaged section: the beam bent back (+Y) at the middle by an old impact, the middle post leaning."""
    mb = lp.MeshBuilder()
    rail_post(mb, -1.0)
    rail_post(mb, 1.0, lean=0.05)

    def bend(x):
        return 0.28 * math.exp(-((x - 0.2) / 0.7) ** 2)

    def sag(x):
        return -0.08 * math.exp(-((x - 0.2) / 0.8) ** 2)
    w_beam(mb, -2.02, 2.02, z_of=sag, y_of=bend, segs=8)
    for fi in range(len(mb.faces)):
        c = mb.center(fi)
        if mb.faces[fi][1] == "chrome" and abs(c.x - 0.2) < 0.45 and (int(c.x * 20) % 3 == 0):
            mb.faces[fi][1] = "rust"
    body = H.smooth(H.mk(mb), 35.0)
    parts = [body]
    rail_snow(parts, -2.0, -0.6, 0.69, 201)
    parts.append(H.mound((0.3, 0.3, 0), 0.9, 0.22, seed=202, sides=10, sink=0.08, stretch=(1.6, 0.5)))
    return parts, "Rail", "rail", "box", ((0.0, 0.1, 0.4), (4.0, 0.8, 0.45))


def parapet_stone():
    """Mountain road parapet: dry-stone wall 4 m x 0.45 x 0.75 with a concrete coping and snow on top."""
    rnd = random.Random(211)
    mb = lp.MeshBuilder()
    rows = [(0.0, 0.24), (0.24, 0.46), (0.46, 0.66)]
    for r, (z0, z1) in enumerate(rows):
        x = -2.0 + (0.18 if r % 2 else 0.0)
        while x < 2.0 - 1e-3:
            w = min(rnd.uniform(0.34, 0.58), 2.0 - x)
            if w < 0.12:
                break
            inset = rnd.uniform(0.0, 0.025)
            mat = "stone" if rnd.random() < 0.65 else "stone_dark"
            mb.box((x + 0.008, -0.225 + inset, z0 + 0.006), (x + w - 0.008, 0.225 - inset, z1 - 0.006), mat)
            x += w
        mb.box((-2.0, -0.20, z0), (2.0, 0.20, z1), "concrete_dark")          # mortar core
    mb.box((-2.02, -0.25, 0.66), (2.02, 0.25, 0.75), "concrete")
    body = H.flat(H.mk(mb))
    parts = [body, H.snow_strip((-2.0, 0.0, 0.75), (2.0, 0.0, 0.75), 0.46, 0.07, seed=212, overhang=0.02)]
    parts.append(H.mound((0.0, -0.3, 0), 1.3, 0.18, seed=213, sides=10, sink=0.08, stretch=(1.6, 0.4)))
    return parts, "Rail", "rail", "box", ((0.0, 0.0, 0.38), (4.0, 0.76, 0.5))


MULTIMESH = {"crest_rock_a": crest_rock_a, "crest_rock_b": crest_rock_b, "crest_spire": crest_spire,
             "scree_field": scree_field, "cliff_face": cliff_face, "cairn": cairn, "cornice": cornice,
             "snow_pole": snow_pole, "snow_pole_tall": snow_pole_tall, "road_delineator": road_delineator,
             "guardrail": guardrail, "guardrail_end": guardrail_end, "guardrail_bent": guardrail_bent,
             "parapet_stone": parapet_stone}


def build_multimesh(name):
    lp.new_scene()
    parts, node, family, col, (cc, size) = MULTIMESH[name]()
    fam_budget = "cliff" if name == "cliff_face" else family
    col_size = list(size) if col != "cylinder" else [size[0], size[1]]
    ao = dict(distance=0.12 if family in ("pole", "rail") else 0.6, samples=48, ground=True)
    glb = V.export_scatter(name, parts, node, family, col, cc, col_size, False, ao=ao, subdir=SUBDIR)
    tris = lp.scene_tris()
    if tris > BUDGETS[fam_budget]:
        raise RuntimeError("%s: tris %d > %d" % (name, tris, BUDGETS[fam_budget]))
    return glb


# ------------------------------------------------------------------------------------------------------------
# tunnel portals
# ------------------------------------------------------------------------------------------------------------
TUN_HW = 4.25            # inner half width (7 m road + 2 x 0.75 sidewalks)
TUN_WALL = 3.2           # vertical wall height
TUN_RISE = 2.6           # arch rise (crown 5.8)
TUN_DEPTH = 12.0         # walkable gallery depth (+Y)
HW_HALF = 6.5            # headwall half width
HW_H = 7.5               # headwall height
HW_T = 0.8


def arch_profile(n=10, hw=TUN_HW, wall=TUN_WALL, rise=TUN_RISE):
    """Opening outline from (-hw, 0) up the wall, over the elliptical arch, down to (hw, 0): [(x, z)]."""
    pts = [(-hw, 0.0), (-hw, wall)]
    for k in range(1, n):
        a = math.pi - math.pi * k / n
        pts.append((hw * math.cos(a), wall + rise * math.sin(a)))
    pts += [(hw, wall), (hw, 0.0)]
    return pts


def outer_profile(inner):
    """Headwall outline matched point by point to the arch outline (same count)."""
    out = []
    n = len(inner)
    for k, (x, z) in enumerate(inner):
        t = k / (n - 1)
        if t < 0.25:
            u = t / 0.25
            out.append((-HW_HALF, HW_H * u))
        elif t > 0.75:
            u = (t - 0.75) / 0.25
            out.append((HW_HALF, HW_H * (1 - u)))
        else:
            u = (t - 0.25) / 0.5
            out.append((-HW_HALF + 2 * HW_HALF * u, HW_H))
    return out


def headwall(mb, broken=False):
    inner = arch_profile()
    outer = outer_profile(inner)
    n = len(inner)
    f_in = [mb._v((x, 0.0, z)) for x, z in inner]
    f_out = [mb._v((x, 0.0, z)) for x, z in outer]
    b_in = [mb._v((x, HW_T, z)) for x, z in inner]
    b_out = [mb._v((x, HW_T, z)) for x, z in outer]
    for k in range(n - 1):
        mb.add_face((f_in[k], f_in[k + 1], f_out[k + 1], f_out[k]), "concrete", facing=(0, -1, 0))
        mb.add_face((b_in[k], b_in[k + 1], b_out[k + 1], b_out[k]), "concrete_dark", facing=(0, 1, 0))
        mb.add_face((f_in[k], f_in[k + 1], b_in[k + 1], b_in[k]), "concrete_dark",
                    facing=Vector((0, 0, TUN_WALL + 0.5)) - Vector((inner[k][0], 0, inner[k][1])))
        mb.add_face((f_out[k], f_out[k + 1], b_out[k + 1], b_out[k]), "concrete",
                    facing=Vector((outer[k][0], 0, outer[k][1] - 3.0)))
    for k in (0, n - 1):                                                      # feet of the headwall (closed)
        mb.add_face((f_in[k], f_out[k], b_out[k], b_in[k]), "concrete_dark", facing=(0, 0, -1))
    # coping + arch ring (voussoir band) + name plate frame
    mb.box((-HW_HALF - 0.15, -0.18, HW_H), (HW_HALF + 0.15, HW_T + 0.05, HW_H + 0.28), "concrete")
    ring_in = arch_profile(10, TUN_HW, TUN_WALL, TUN_RISE)
    for k in range(1, len(ring_in) - 2):
        (x0, z0), (x1, z1) = ring_in[k], ring_in[k + 1]
        c = Vector(((x0 + x1) / 2, -0.05, (z0 + z1) / 2))
        d = Vector((x1 - x0, 0, z1 - z0))
        nrm = Vector((-(z1 - z0), 0, x1 - x0)).normalized()
        if nrm.dot(Vector((c.x, 0, c.z - TUN_WALL))) < 0:
            nrm = -nrm
        p0, p1 = Vector((x0, -0.12, z0)) - nrm * 0.02, Vector((x1, -0.12, z1)) - nrm * 0.02
        q0, q1 = p0 + nrm * 0.45, p1 + nrm * 0.45
        mb.hexa([p0, p1, q0, q1, p0 + Vector((0, 0.13, 0)), p1 + Vector((0, 0.13, 0)), q0 + Vector((0, 0.13, 0)),
                 q1 + Vector((0, 0.13, 0))], "concrete_dark" if k % 2 else "concrete")
    mb.box((-1.9, -0.10, 6.25), (1.9, 0.0, 7.15), "concrete_dark")                           # plate frame


def wing_walls(mb):
    for sx in (-1, 1):
        a = Vector((sx * HW_HALF, 0.1, 0.0))
        b = Vector((sx * (HW_HALF + 3.2), -4.6, 0.0))
        d = (b - a).normalized()
        nrm = Vector((-d.y, d.x, 0.0)) * sx
        t = 0.6
        h0, h1 = HW_H - 0.2, 1.0
        pts = [a, b, a + nrm * t, b + nrm * t,
               a + Vector((0, 0, h0)), b + Vector((0, 0, h1)), a + nrm * t + Vector((0, 0, h0)),
               b + nrm * t + Vector((0, 0, h1))]
        mb.hexa([p - Vector((0, 0, 0.3)) if p.z < 0.01 else p for p in pts], "concrete")


def lining(mb, depth=TUN_DEPTH):
    inner = arch_profile()
    segs = 3
    rings = []
    for s in range(segs + 1):
        y = HW_T + (depth - HW_T) * s / segs
        rings.append([mb._v((x, y, z)) for x, z in inner])
    cen = Vector((0, 0, TUN_WALL))
    for s in range(segs):
        mat = ("concrete", "concrete_dark", "stone_dark")[s]
        for k in range(len(inner) - 1):
            mid = Vector(((inner[k][0] + inner[k + 1][0]) / 2, 0, (inner[k][1] + inner[k + 1][1]) / 2))
            mb.add_face((rings[s][k], rings[s][k + 1], rings[s + 1][k + 1], rings[s + 1][k]), mat,
                        facing=Vector((cen.x - mid.x, 0, cen.z - mid.z)))
    end = [mb._v((x, depth, z)) for x, z in inner]
    mb.add_face(tuple(end), "paint_black", facing=(0, -1, 0))                    # darkness at the end
    # floor: asphalt + sidewalks (kerbs) along both walls
    mb.box((-TUN_HW, -0.2, -0.25), (TUN_HW, depth, 0.0), "asphalt", skip=("-z",))
    for sx in (-1, 1):
        x0, x1 = sorted((sx * TUN_HW, sx * (TUN_HW - 0.75)))
        mb.box((x0, -0.2, 0.0), (x1, depth, 0.15), "concrete_dark", skip=("-z",))
    for y in (3.0, 7.0, 11.0):                                                   # dead lamp housings
        for sx in (-1, 1):
            mb.box((sx * 3.6 - 0.25, y - 0.12, 4.7), (sx * 3.6 + 0.25, y + 0.12, 4.86), "iron")


def hill_cap(mb, seed, depth=TUN_DEPTH):
    """Rock-and-snow hill over the gallery: a height field z(x, y) above the tube, with vertical rock skirts down to
    z = -1 on the sides and back and beside the headwall (the portal is cut into a rock face)."""
    rnd = random.Random(seed)
    X0, X1, Y0, Y1 = -11.0, 11.0, 0.3, depth + 5.0
    nx, ny = 15, 11

    def f(x, y):
        core = 8.2 + 1.2 * math.sin(min(1.0, (y - Y0) / 8.0) * math.pi * 0.5)
        side = max(0.0, (abs(x) - 6.8) / (X1 - 6.8))
        back = max(0.0, (y - (depth + 0.8)) / (Y1 - depth - 0.8))
        fall = max(side, back)
        z = core * (1.0 - fall ** 1.6) - 0.8 * fall
        z += 0.45 * noise.noise(Vector((x * 0.35, y * 0.35, seed * 0.1))) + rnd.uniform(-0.08, 0.08)
        if abs(x) < HW_HALF + 0.2 and y < HW_T + 0.2:
            z = max(z, HW_H + 0.25)
        return z
    grid = [[mb._v((X0 + (X1 - X0) * i / (nx - 1), Y0 + (Y1 - Y0) * j / (ny - 1),
                    f(X0 + (X1 - X0) * i / (nx - 1), Y0 + (Y1 - Y0) * j / (ny - 1)))) for i in range(nx)]
            for j in range(ny)]
    for j in range(ny - 1):
        for i in range(nx - 1):
            a, b, c, d = grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]
            mb.add_face((a, b, c), "snow", facing=(0, 0, 1))
            mb.add_face((a, c, d), "snow", facing=(0, 0, 1))

    def low(v, front=False):
        if front and abs(v.x) <= HW_HALF:
            return HW_H + 0.1                      # behind the coping: closes the slit above the headwall
        return min(-1.0, v.z - 0.2)

    def skirt(chain, facing, front=False):
        for k in range(len(chain) - 1):
            p, q = chain[k], chain[k + 1]
            pv, qv = mb.verts[p], mb.verts[q]
            lo_p = mb._v((pv.x, pv.y, low(pv, front)))
            lo_q = mb._v((qv.x, qv.y, low(qv, front)))
            mb.add_face((p, q, lo_q, lo_p), "stone_dark", facing=facing)
    skirt([grid[j][0] for j in range(ny)], (-1, 0, 0))
    skirt([grid[j][nx - 1] for j in range(ny)], (1, 0, 0))
    skirt([grid[ny - 1][i] for i in range(nx)], (0, 1, 0))
    skirt([grid[0][i] for i in range(nx)], (0, -1, 0), front=True)
    mb.triangulate_nonplanar()
    for fi in range(len(mb.faces)):
        if mb.faces[fi][1] == "snow":
            n = mb.normal(fi)
            if n.z < 0.62:
                mb.faces[fi][1] = "stone" if n.z > 0.3 else "stone_dark"


def portal_panel(pan):
    pan.box((-1.8, -0.13, 6.32), (1.8, -0.10, 7.08), "metal_blue")


def portal_snow(parts, seed):
    parts.append(H.snow_strip((-HW_HALF - 0.1, 0.33, HW_H + 0.28), (HW_HALF + 0.1, 0.33, HW_H + 0.28), 0.95, 0.12,
                              seed=seed, overhang=0.04))
    sm = lp.MeshBuilder()
    for sx in (-1, 1):
        pts = wing_col(sx)
        top = [pts[4], pts[5], pts[6], pts[7]]
        up = Vector((0, 0, 0.09))
        pad = [(p - Vector((0, 0, 0.02))) for p in top]
        sm.hexa([pad[0], pad[1], pad[2], pad[3], top[0] + up, top[1] + up, top[2] + up, top[3] + up], "snow")
        parts.append(H.mound((sx * 5.6, -1.5, 0), 1.5, 0.45, seed=seed + 8 + sx, sides=12, sink=0.1,
                             stretch=(1.0, 1.4)))
    parts.append(H.smooth(H.mk(sm), 30.0))


def rubble(mb, seed):
    """Collapsed mouth: concrete slabs + rock blocks + snow filling the opening and spilling out to y = -4."""
    rnd = random.Random(seed)
    for k in range(20):
        u = rnd.random()
        x = rnd.uniform(-TUN_HW + 0.3, TUN_HW - 0.3) * (1.0 - 0.3 * u)
        y = rnd.uniform(-3.6, 2.5)
        zmax = max(0.4, 5.2 * (1.0 - max(0.0, -y) / 4.0) * (1.0 - (abs(x) / (TUN_HW + 1.0)) ** 2))
        z = rnd.uniform(0.0, zmax)
        s = rnd.uniform(0.45, 1.1)
        if k % 3 == 0:                                                    # concrete lining slab
            rot = Matrix.Rotation(rnd.uniform(-0.8, 0.8), 3, 'X') @ Matrix.Rotation(rnd.uniform(0, 3.1), 3, 'Z')
            half = [Vector((sx * s * 0.9, sy * s * 0.6, sz * 0.14)) for sz in (-1, 1) for sy in (-1, 1) for sx in (-1, 1)]
            c = Vector((x, y, max(z, 0.14)))
            mb.hexa([c + rot @ h for h in half], "concrete")
        else:
            mb.blob((x, y, z), (s * 0.8, s * 0.7, s * 0.55), "stone", subdiv=1, jitter=0.14, rnd=rnd, clamp_z=0.0,
                    drop_bottom=True)
    mb.blob((0.0, 0.6, 0.0), (TUN_HW + 0.3, 3.0, TUN_WALL + 2.1), "stone", subdiv=2, jitter=0.10, rnd=rnd,
            clamp_z=0.0, drop_bottom=True)                                       # the fallen mass itself
    for v in mb.verts:
        v.z = max(v.z, -0.5)
    for fi in range(len(mb.faces)):
        if mb.faces[fi][1] == "stone":
            n = mb.normal(fi)
            mb.faces[fi][1] = "snow" if n.z > 0.75 else ("stone_dark" if n.z < 0.1 else "stone")


# Col boxes (Blender min / max) shared by both portals
def portal_cols(collapsed):
    cols = {
        "ColHeadwallL": ((-HW_HALF, 0.0, 0.0), (-TUN_HW, HW_T, HW_H)),
        "ColHeadwallR": ((TUN_HW, 0.0, 0.0), (HW_HALF, HW_T, HW_H)),
        "ColHeadwallTop": ((-TUN_HW, 0.0, TUN_WALL + TUN_RISE), (TUN_HW, HW_T, HW_H)),
        "ColWallL": ((-TUN_HW - 0.5, HW_T, 0.0), (-TUN_HW + 0.75, TUN_DEPTH, TUN_WALL + 1.0)),
        "ColWallR": ((TUN_HW - 0.75, HW_T, 0.0), (TUN_HW + 0.5, TUN_DEPTH, TUN_WALL + 1.0)),
        "ColRoof": ((-TUN_HW, HW_T, TUN_WALL + 1.0), (TUN_HW, TUN_DEPTH, TUN_WALL + TUN_RISE + 0.5)),
        "ColEnd": ((-TUN_HW, TUN_DEPTH - 0.3, 0.0), (TUN_HW, TUN_DEPTH + 0.3, TUN_WALL + TUN_RISE)),
        "ColFloor": ((-TUN_HW, -0.2, -0.3), (TUN_HW, TUN_DEPTH, 0.0)),
        "ColHillL": ((-11.0, 0.3, 0.0), (-HW_HALF, TUN_DEPTH + 5.0, 6.0)),
        "ColHillR": ((HW_HALF, 0.3, 0.0), (11.0, TUN_DEPTH + 5.0, 6.0)),
    }
    if collapsed:
        cols["ColRubble"] = ((-TUN_HW, -2.5, 0.0), (TUN_HW, 2.5, TUN_WALL + 1.5))
        cols["ColRubbleFront"] = ((-TUN_HW + 0.5, -3.8, 0.0), (TUN_HW - 0.5, -2.5, 1.0))
    return cols


def wing_col(sx):
    a = Vector((sx * HW_HALF, 0.1, 0.0))
    b = Vector((sx * (HW_HALF + 3.2), -4.6, 0.0))
    d = (b - a).normalized()
    nrm = Vector((-d.y, d.x, 0.0)) * sx
    t = 0.6
    return [a, b, a + nrm * t, b + nrm * t, a + Vector((0, 0, HW_H - 0.2)), b + Vector((0, 0, 1.0)),
            a + nrm * t + Vector((0, 0, HW_H - 0.2)), b + nrm * t + Vector((0, 0, 1.0))]


def build_portal(name, collapsed):
    lp.new_scene()
    mb = lp.MeshBuilder()
    headwall(mb)
    wing_walls(mb)
    lining(mb)
    hill_cap(mb, 301 if not collapsed else 311)
    portal = H.flat(H.mk(mb, "Portal"))
    parts = [portal]
    portal_snow(parts, 321 if not collapsed else 331)
    if collapsed:
        rb = lp.MeshBuilder()
        rubble(rb, 341)
        rub = H.flat(H.mk(rb, "Rubble"))
        dr = H.mound((0.0, -2.2, 0), 3.4, 1.1, seed=342, sides=14, sink=0.1, stretch=(1.25, 0.9))
        H.join([rub, dr], "Rubble")
    portal = H.join(parts, "Portal")
    pan = lp.MeshBuilder()
    portal_panel(pan)
    panel = H.flat(H.mk(pan, "Panel"))
    portal["road_width"] = 7.0
    portal["clearance"] = TUN_WALL
    portal["crown"] = TUN_WALL + TUN_RISE
    portal["depth"] = 0.0 if collapsed else TUN_DEPTH
    portal["blocked"] = bool(collapsed)
    portal["carve"] = [-HW_HALF, HW_HALF, -(TUN_DEPTH + 0.2), 0.3]
    portal["panels"] = {"Panel": [3.6, 0.76]}
    lp.add_empty("TextPanel", (0.0, -0.16, 6.70), size=0.2)
    lp.add_empty("RoadIn", (0.0, -0.5, 0.0), size=0.3)
    lp.add_empty("Inside", (0.0, TUN_DEPTH - 1.0 if not collapsed else 3.0, 0.0), size=0.3)
    for cname, (mn, mx) in portal_cols(collapsed).items():
        lp.collision_box(cname, mn, mx)
    for sx, cname in ((-1, "ColWingL"), (1, "ColWingR")):
        pts = wing_col(sx)
        faces = [lp.BOX_FACES[k] for k in lp.BOX_ORDER]
        lp.collision_prism(cname, pts, faces)
    tris = lp.scene_tris()
    if tris > BUDGETS["portal"]:
        raise RuntimeError("%s: tris %d > %d" % (name, tris, BUDGETS["portal"]))
    return export.save_and_export(name, SUBDIR, ao=dict(distance=1.2, samples=48, ground=True), import_kind="prop")


# ------------------------------------------------------------------------------------------------------------
# kilometre signs (A1 sign contract: Prop + Panel + TextPanel)
# ------------------------------------------------------------------------------------------------------------
def km_sign():
    """Autovia kilometre plate: blue 0.60 x 0.45 panel with a white border on a galvanised post, face toward -Y."""
    mb = lp.MeshBuilder()
    mb.cylinder((0, 0.02, -0.2), (0, 0.02, 1.80), 0.035, 0.032, 8, "metal_sheet", cap_mats=(None, "iron"))
    mb.box((-0.33, -0.030, 1.18), (0.33, -0.008, 1.70), "paint_white")                  # white border / back
    for z in (1.30, 1.58):
        mb.box((-0.05, -0.008, z - 0.03), (0.05, 0.02, z + 0.03), "iron")             # clamps
    pan = lp.MeshBuilder()
    pan.box((-0.30, -0.042, 1.215), (0.30, -0.030, 1.665), "metal_blue")
    prop = H.smooth(H.mk(mb, "Prop"), 40.0)
    snow = H.snow_ridge((-0.33, -0.019, 1.70), (0.33, -0.019, 1.70), 0.05, 0.035, seed=401, segs=3)
    prop = H.join([prop, snow, H.mound((0, 0, 0), 0.25, 0.09, seed=402, sides=8, sink=0.05)], "Prop")
    panel = H.flat(H.mk(pan, "Panel"))
    return prop, panel, (0.0, -0.075, 1.44), dict(col="cylinder", col_center=godot((0, 0, 0.9)), col_size=[0.07, 1.8],
                                                  panels={"Panel": [0.60, 0.45]})


def km_post():
    """National road 'hito kilometrico': white concrete post 0.40 x 0.20 x 1.0 with a red cap, face toward -Y."""
    mb = lp.MeshBuilder()
    rings = []
    for z, s in ((-0.2, 1.0), (0.0, 1.0), (0.78, 0.96), (0.86, 0.95), (0.96, 0.80), (1.0, 0.55)):
        rings.append([Vector((x * s, y, z)) for x, y in ((0.20, 0.10), (-0.20, 0.10), (-0.20, -0.10), (0.20, -0.10))])
    mb.loft(rings, "paint_white", side_mats=["paint_white", "paint_white", "paint_red", "paint_red", "paint_red"],
            cap_mats=("paint_white", "paint_red"))
    pan = lp.MeshBuilder()
    pan.box((-0.16, -0.112, 0.30), (0.16, -0.100, 0.70), "cabin_trim")
    prop = H.flat(H.mk(mb, "Prop"))
    snow = H.snow_cap((0, 0, 0), 0.12, 0.06, 0.035, V.surface_fn(prop), seed=411, sides=8, rings=2, droop=0.01)
    prop = H.join([prop, snow, H.mound((0, 0, 0), 0.34, 0.10, seed=412, sides=8, sink=0.05)], "Prop")
    panel = H.flat(H.mk(pan, "Panel"))
    return prop, panel, (0.0, -0.14, 0.50), dict(col="box", col_center=godot((0, 0, 0.5)), col_size=[0.4, 1.0, 0.2],
                                                 panels={"Panel": [0.32, 0.40]})


SIGNS = {"km_sign": km_sign, "km_post": km_post}


def build_sign(name):
    lp.new_scene()
    prop, panel, text, info = SIGNS[name]()
    for k, v in info.items():
        prop[k] = v
    prop["anchors"] = {"TextPanel": godot(text)}
    lp.add_empty("TextPanel", text, size=0.05)
    tris = lp.scene_tris()
    if tris > BUDGETS["sign"]:
        raise RuntimeError("%s: tris %d > %d" % (name, tris, BUDGETS["sign"]))
    return export.save_and_export(name, SUBDIR, ao=dict(distance=0.25, samples=48, ground=True), import_kind="prop")


STRUCTURES = {"tunnel_portal": lambda: build_portal("tunnel_portal", False),
              "tunnel_portal_collapsed": lambda: build_portal("tunnel_portal_collapsed", True),
              "km_sign": lambda: build_sign("km_sign"), "km_post": lambda: build_sign("km_post")}
ALL = list(MULTIMESH) + list(STRUCTURES)


def main(argv=()):
    names = [a for a in argv if not a.startswith("-")] or ALL
    out = []
    for n in names:
        out.append(build_multimesh(n) if n in MULTIMESH else STRUCTURES[n]())
    return out


if __name__ == "__main__":
    main(sys.argv[1:])
