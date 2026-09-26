"""Gore-lite props — ASSET_SPEC_V2 §13 row "Cadáveres y sangre", §18 M4 (corpse, blood decals, limb stumps, fragmented
head). Tasteful and low-poly: no viscera, only blood / dried blood / a gore-red cut face, readable from the 24 m camera.

    cd winter-survival/blender && python3 props/build_gore.py [corpse_covered ...]

Exports assets/models/gore/<prop>.glb (+ sources/<prop>.blend + a Godot `.import`, template "prop"). Every visual mesh
has one palette_vcol surface (COLOR_0 RGBA, A = baked AO); no collision (§15: the code adds shapes if it wants them).

  corpse_covered   body under an olive tarp (head bump at -Y, boots out at +Y, a hand out on the right, dried blood
                   seeping at the head end). One mesh `Corpse`, origin at the footprint centre.
  blood_splat_a/b/c  decals: irregular flat polygons 4 mm above z = 0 (blood core + blood_dry rim + droplets), one
                   mesh `Decal`, origin at the centre; a = round 0.9 m, b = small 0.6 m, c = spray 1.2 m (toward -Y)
  blood_trail      drag trail 2.2 m along Y (+Y = where the body came from), one mesh `Decal`
  limb_arm         severed forearm + hand in a torn sleeve lying on the ground (gore cap at the elbow), mesh `Limb`
  limb_leg         severed lower leg in a boot (gore cap at the knee), mesh `Limb`
  head_fragments   6 skull pieces around the origin = the head centre (spawn at the zombie's HeadSocket when the head
                   "bursts" on a critical, §7.1 GDD): meshes `Frag_0`..`Frag_5`, each with its origin at its own
                   centroid (ready for one RigidBody3D each; impulse = away from the asset origin)
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import bpy  # noqa: E402,F401
from mathutils import Vector  # noqa: E402

from lib import export  # noqa: E402
from lib import hd as H  # noqa: E402
from lib import lowpoly as lp  # noqa: E402

SUBDIR = "gore"
DECAL_Z = 0.004                 # decal layers: 4 mm (pools), 5.5 mm (overlapping splats), 7 mm (drops)
# name -> (budget, nodes); verify_assets.py reads GORE (dims are the built sizes, regression +-10 %)
GORE = {
    "corpse_covered": dict(budget=800, node="Corpse"),
    "blood_splat_a": dict(budget=150, node="Decal"),
    "blood_splat_b": dict(budget=150, node="Decal"),
    "blood_splat_c": dict(budget=150, node="Decal"),
    "blood_trail": dict(budget=200, node="Decal"),
    "limb_arm": dict(budget=300, node="Limb"),
    "limb_leg": dict(budget=300, node="Limb"),
    "head_fragments": dict(budget=400, node="Frag_0"),
}


# ------------------------------------------------------------------------------------------------------------
# corpse under a tarp
# ------------------------------------------------------------------------------------------------------------
def body_height(x, y):
    """Height of the covered body (lying on its back, head at y = -0.82, feet at y = +0.80)."""
    def bump(cx, cy, rx, ry, h):
        d = ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2
        return h * max(0.0, 1.0 - d) ** 0.6
    hgt = max(bump(0.0, -0.80, 0.12, 0.13, 0.20),            # head
              bump(0.0, -0.45, 0.26, 0.22, 0.24),            # chest / shoulders
              bump(0.0, -0.12, 0.22, 0.22, 0.21),            # belly / hips
              bump(0.10, 0.30, 0.09, 0.40, 0.15), bump(-0.10, 0.30, 0.09, 0.40, 0.15),   # legs
              bump(0.11, 0.70, 0.07, 0.10, 0.17), bump(-0.11, 0.70, 0.07, 0.10, 0.17))   # feet (toes up)
    return hgt


def build_corpse():
    rnd = random.Random(5)
    mb = lp.MeshBuilder()
    nx, ny = 11, 19
    W, L = 0.86, 2.0
    grid = []
    for j in range(ny + 1):
        row = []
        for i in range(nx + 1):
            u, v = i / nx, j / ny
            x = (u - 0.5) * W
            y = (v - 0.5) * L - 0.04
            h = body_height(x, y)
            # drape: the tarp falls from the body to the ground with a soft edge and a few folds
            edge = min(u, 1 - u, v, 1 - v)
            fold = 0.012 * math.sin(9.0 * y + 3.0 * x) + rnd.uniform(-0.006, 0.006)
            z = max(h * (0.96 + fold * 3), 0.0) + 0.015 + (0.0 if edge > 0.001 else -0.015)
            if edge < 0.001:
                z = 0.0
            row.append(mb._v((x + rnd.uniform(-0.01, 0.01) * (edge > 0.001), y, z)))
        grid.append(row)
    for j in range(ny):
        for i in range(nx):
            a, b, c, d = grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]
            mb.add_face((a, b, c, d), "military_green", facing=(0, 0, 1))
    mb.triangulate_nonplanar()
    # colours: fold shading bands, dried blood seeping at the head end
    for fi in range(len(mb.faces)):
        c = mb.center(fi)
        n = mb.normal(fi)
        if c.y < -0.55 and c.x > 0.02 and (c.x - 0.12) ** 2 + (c.y + 0.78) ** 2 < 0.05:
            mb.faces[fi][1] = "blood_dry"
        elif n.z < 0.6:
            mb.faces[fi][1] = "parka_olive"
    # boots sticking out at the foot end (toes up), a pale hand out on the right side
    for sx in (-1, 1):
        x = sx * 0.11
        mb.loft([lp.rrect((x, 0.86, 0.06), 0.055, 0.06, 0.02, 'XZ'), lp.rrect((x, 0.97, 0.07), 0.055, 0.07, 0.02, 'XZ'),
                 lp.rrect((x, 1.00, 0.12), 0.05, 0.05, 0.02, 'XZ')], "boots")
        mb.box((x - 0.05, 0.98, 0.0), (x + 0.05, 1.03, 0.16), "boots_brown")
    mb.loft([lp.ring(Vector((-0.40, -0.30, 0.03)), Vector((-1, 0.2, 0)), 0.035, 6),
             lp.ring(Vector((-0.50, -0.28, 0.03)), Vector((-1, 0.2, 0)), 0.030, 6),
             lp.ring(Vector((-0.58, -0.27, 0.025)), Vector((-1, 0.1, 0)), 0.022, 6)], "skin_hd")
    mb.box((-0.58, -0.31, 0.0), (-0.52, -0.24, 0.02), "skin_hd")
    o = H.mk(mb, "Corpse")
    H.smooth(o, 50)
    return o


# ------------------------------------------------------------------------------------------------------------
# decals
# ------------------------------------------------------------------------------------------------------------
def splat(mb, cx, cy, r, rnd, spikes=11, core="blood", rim="blood_dry", elong=(1.0, 1.0), rim_w=0.18, z=DECAL_Z):
    """Irregular star blob on the ground: core polygon + rim ring (quads) with ragged spikes. Overlapping pieces go on
    separate layers (`z`, 1.5 mm apart): coplanar overlaps would z-fight and bake black AO."""
    n = spikes * 2
    outer, inner = [], []
    for k in range(n):
        a = 2 * math.pi * k / n + rnd.uniform(-0.12, 0.12)
        rr = r * (1.0 + (0.35 if k % 2 == 0 else -0.10) * rnd.uniform(0.4, 1.3))
        dx, dy = math.cos(a) * elong[0], math.sin(a) * elong[1]
        outer.append((cx + dx * rr, cy + dy * rr, z))
        ri = rr * (1 - rim_w) * rnd.uniform(0.85, 1.0)
        inner.append((cx + dx * ri, cy + dy * ri, z))
    oi = [mb._v(p) for p in outer]
    ii = [mb._v(p) for p in inner]
    c = mb._v((cx, cy, z))
    for k in range(n):
        k2 = (k + 1) % n
        mb.add_face((ii[k], ii[k2], c), core, facing=(0, 0, 1))
        mb.add_face((oi[k], oi[k2], ii[k2], ii[k]), rim, facing=(0, 0, 1))


def drops(mb, cx, cy, spread, count, rnd, size=(0.015, 0.04), mat="blood", bias=(0.0, 0.0), z=DECAL_Z + 0.003):
    for i in range(count):
        zi = z + 0.0003 * i                          # each drop on its own sub-layer (overlaps never coplanar)
        a = rnd.uniform(0, 2 * math.pi)
        d = spread * math.sqrt(rnd.random())
        x = cx + math.cos(a) * d + bias[0] * d
        y = cy + math.sin(a) * d + bias[1] * d
        r = rnd.uniform(*size)
        pts = [(x + math.cos(2 * math.pi * k / 5 + a) * r * rnd.uniform(0.7, 1.2),
                y + math.sin(2 * math.pi * k / 5 + a) * r * rnd.uniform(0.7, 1.2), zi) for k in range(5)]
        mb.poly(pts, mat, facing=(0, 0, 1))


def build_splat(name):
    rnd = random.Random({"blood_splat_a": 1, "blood_splat_b": 2, "blood_splat_c": 3}[name])
    mb = lp.MeshBuilder()
    if name == "blood_splat_a":                     # round pool ~0.9 m
        splat(mb, 0, 0, 0.32, rnd, 11)
        splat(mb, 0.24, -0.20, 0.09, rnd, 6, z=DECAL_Z + 0.0015)
        drops(mb, 0, 0, 0.46, 8, rnd)
    elif name == "blood_splat_b":                   # small ~0.6 m
        splat(mb, 0, 0, 0.20, rnd, 9)
        drops(mb, 0, 0, 0.30, 6, rnd, (0.012, 0.03))
    else:                                           # spray ~1.2 m toward -Y
        splat(mb, 0, 0.18, 0.22, rnd, 10, elong=(0.85, 1.25))
        splat(mb, 0.05, -0.22, 0.10, rnd, 7, elong=(0.8, 1.4), z=DECAL_Z + 0.0015)
        drops(mb, 0.0, -0.30, 0.34, 12, rnd, (0.012, 0.035), bias=(0.0, -0.6))
    o = H.mk(mb, "Decal")
    return o


def build_trail():
    rnd = random.Random(9)
    mb = lp.MeshBuilder()
    # a smeared band along Y (drag), wobbling, narrowing and breaking up toward +Y, rim darker
    n = 14
    left, right, mid = [], [], []
    for k in range(n + 1):
        t = k / n
        y = -1.05 + 2.2 * t
        x = 0.05 * math.sin(4.5 * t + 0.4) + rnd.uniform(-0.01, 0.01)
        w = (0.15 - 0.09 * t) * rnd.uniform(0.8, 1.15)
        left.append(mb._v((x + w, y, DECAL_Z)))
        right.append(mb._v((x - w, y, DECAL_Z)))
        mid.append((x, y, w))
    for k in range(n):
        if k > 8 and k % 2 == 1:
            continue                                    # breaks in the smear
        mat = "blood" if 2 <= k <= 7 else "blood_dry"
        mb.add_face((right[k], right[k + 1], left[k + 1], left[k]), mat, facing=(0, 0, 1))
    splat(mb, 0.02, -1.08, 0.16, rnd, 8, z=DECAL_Z + 0.0015)
    for x, y, w in mid[8:]:
        drops(mb, x, y, w * 1.4, 2, rnd, (0.012, 0.028), "blood_dry")
    return H.mk(mb, "Decal")


# ------------------------------------------------------------------------------------------------------------
# severed limbs (lying on the ground)
# ------------------------------------------------------------------------------------------------------------
def ring_y(y, x, z, rx, rz, n=8):
    return [Vector((x + rx * math.cos(2 * math.pi * i / n), y, z + rz * math.sin(2 * math.pi * i / n))) for i in range(n)]


def build_limb_arm():
    mb = lp.MeshBuilder()
    # forearm along +Y (elbow end at y = -0.17, hand at +0.17), lying on its side on the ground
    mb.loft([ring_y(-0.17, 0.0, 0.052, 0.050, 0.048), ring_y(-0.12, 0.0, 0.055, 0.056, 0.053),
             ring_y(-0.02, 0.0, 0.050, 0.052, 0.048)], "cloth_dark", cap_mats=("gore", None))
    mb.loft([ring_y(-0.03, 0.0, 0.044, 0.042, 0.040), ring_y(0.08, 0.0, 0.040, 0.036, 0.034),
             ring_y(0.12, 0.0, 0.038, 0.034, 0.032)], "skin_zombie")
    mb.loft([ring_y(0.115, 0.0, 0.034, 0.042, 0.020), ring_y(0.17, 0.0, 0.030, 0.050, 0.018),
             ring_y(0.20, 0.0, 0.026, 0.044, 0.015)], "skin_zombie")                   # palm
    for dx in (-0.028, -0.008, 0.012, 0.030):
        H.tube(mb, [(dx, 0.195, 0.026), (dx * 1.1, 0.235, 0.022), (dx * 1.2, 0.255, 0.012)], [0.010, 0.009, 0.006], 4,
               "skin_zombie")
    # cut: bone stub + blood seep at the elbow end
    mb.cylinder((0.0, -0.17, 0.052), (0.0, -0.195, 0.054), 0.014, 0.012, 6, "cloth_white")
    mb.poly([(-0.07, -0.26, DECAL_Z), (0.07, -0.25, DECAL_Z), (0.08, -0.14, DECAL_Z), (-0.06, -0.15, DECAL_Z)],
            "blood", facing=(0, 0, 1))
    o = H.mk(mb, "Limb")
    H.smooth(o, 50)
    return o


def build_limb_leg():
    mb = lp.MeshBuilder()
    # lower leg along +Y (knee cut at y = -0.24), boot at +Y lying on its side (sole toward +X)
    mb.loft([ring_y(-0.24, 0.0, 0.066, 0.064, 0.060), ring_y(-0.16, 0.0, 0.066, 0.066, 0.062),
             ring_y(0.02, 0.0, 0.058, 0.058, 0.054)], "pants_dark", cap_mats=("gore", None))
    mb.loft([ring_y(0.0, 0.0, 0.060, 0.064, 0.062), ring_y(0.14, 0.0, 0.060, 0.066, 0.064),
             ring_y(0.20, 0.0, 0.058, 0.066, 0.062)], "boots")
    # foot: from the ankle, pointing -Z? lying on its side: toes toward -X, sole facing +Y
    mb.loft([lp.rrect((0.0, 0.215, 0.058), 0.062, 0.056, 0.02, 'XZ'),
             lp.rrect((-0.10, 0.225, 0.056), 0.060, 0.052, 0.02, 'XZ'),
             lp.rrect((-0.21, 0.225, 0.048), 0.050, 0.044, 0.02, 'XZ')][::1], "boots")
    mb.box((-0.24, 0.235, 0.004), (0.06, 0.265, 0.108), "boots_brown")                 # sole
    mb.cylinder((0.0, -0.24, 0.066), (0.0, -0.268, 0.068), 0.020, 0.017, 6, "cloth_white")
    mb.poly([(-0.09, -0.34, DECAL_Z), (0.08, -0.33, DECAL_Z), (0.10, -0.19, DECAL_Z), (-0.08, -0.20, DECAL_Z)],
            "blood", facing=(0, 0, 1))
    o = H.mk(mb, "Limb")
    H.smooth(o, 50)
    return o


# ------------------------------------------------------------------------------------------------------------
# fragmented head
# ------------------------------------------------------------------------------------------------------------
def shell_piece(mb, a0, a1, e0, e1, r_out, r_in, skin, rnd, n=3):
    """Curved skull patch (azimuth a0..a1, elevation e0..e1 in degrees) with thickness: skin outside, bone rim, gore
    inside."""
    def pt(a, e, r):
        a, e = math.radians(a), math.radians(e)
        return Vector((r * math.cos(e) * math.cos(a), r * math.cos(e) * math.sin(a) * 1.15, r * math.sin(e) * 1.2))
    outer, inner = [], []
    for i in range(n + 1):
        ro, ri = [], []
        for j in range(n + 1):
            a = a0 + (a1 - a0) * i / n
            e = e0 + (e1 - e0) * j / n
            k = rnd.uniform(0.94, 1.04)
            ro.append(mb._v(pt(a, e, r_out * k)))
            ri.append(mb._v(pt(a, e, r_in * k)))
        outer.append(ro)
        inner.append(ri)
    for i in range(n):
        for j in range(n):
            mb.add_face((outer[i][j], outer[i + 1][j], outer[i + 1][j + 1], outer[i][j + 1]), skin, inside=(0, 0, 0))
            f = mb.add_face((inner[i][j], inner[i][j + 1], inner[i + 1][j + 1], inner[i + 1][j]), "gore",
                            inside=(0, 0, 0))
            mb.faces[f][0] = tuple(reversed(mb.faces[f][0]))   # inner side faces the centre
    edges = [[(outer[i][0], inner[i][0]) for i in range(n + 1)], [(outer[i][n], inner[i][n]) for i in range(n + 1)],
             [(outer[0][j], inner[0][j]) for j in range(n + 1)], [(outer[n][j], inner[n][j]) for j in range(n + 1)]]
    for lst in edges:
        for k in range(n):
            (o0, i0), (o1, i1) = lst[k], lst[k + 1]
            pts = [mb.verts[v] for v in (o0, o1, i1, i0)]
            c = sum(pts, Vector()) / 4
            mid_piece = (pt((a0 + a1) / 2, (e0 + e1) / 2, (r_out + r_in) / 2))
            mb.add_face((o0, o1, i1, i0), "cloth_white", facing=c - mid_piece)


def build_head_fragments():
    rnd = random.Random(21)
    specs = [(-40, 40, 5, 60, "skin_zombie"), (40, 130, 0, 55, "skin_zombie"), (130, 220, 5, 60, "beard"),
             (220, 320, 0, 55, "skin_zombie"), (-40, 140, 55, 88, "beard"), (140, 320, 55, 88, "skin_zombie")]
    objs = []
    for k, (a0, a1, e0, e1, skin) in enumerate(specs):
        mb = lp.MeshBuilder()
        shell_piece(mb, a0, a1, e0, e1, 0.095, 0.082, skin, rnd)
        c = sum(mb.verts, Vector()) / len(mb.verts)
        o = H.mk(mb, "Frag_%d" % k, pivot=tuple(c))
        H.smooth(o, 45)
        objs.append(o)
    return objs


BUILDERS = {"corpse_covered": build_corpse, "blood_splat_a": lambda: build_splat("blood_splat_a"),
            "blood_splat_b": lambda: build_splat("blood_splat_b"), "blood_splat_c": lambda: build_splat("blood_splat_c"),
            "blood_trail": build_trail, "limb_arm": build_limb_arm, "limb_leg": build_limb_leg,
            "head_fragments": build_head_fragments}


def build(name):
    lp.new_scene()
    BUILDERS[name]()
    tris = lp.scene_tris()
    if tris > GORE[name]["budget"]:
        raise RuntimeError("%s: tris %d > %d" % (name, tris, GORE[name]["budget"]))
    if name == "head_fragments":
        ao = dict(distance=0.05, samples=32, ground=False)
    elif name.startswith("blood"):
        ao = dict(distance=0.1, samples=16, ground=True)
    else:
        ao = dict(distance=0.12, samples=48, ground=True)
    return export.save_and_export(name, SUBDIR, ao=ao, import_kind="prop")


def main(argv=()):
    names = [a for a in argv if not a.startswith("-")] or list(GORE)
    return [build(n) for n in names]


if __name__ == "__main__":
    main(sys.argv[1:])
