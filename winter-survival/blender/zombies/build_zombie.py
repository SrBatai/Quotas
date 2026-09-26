"""Zombies — ASSET_SPEC_V2 §4 (skeleton, rigid skin), §5.2 (recipe), §14 / doc 05 §4.5 (1 500–2 500 tris), milestone M4
(walker batch of M2 + M4 batch 1: runner, crawler, bloater, frozen).

    cd winter-survival/blender && python3 zombies/build_zombie.py                  # every variant
    python3 zombies/build_zombie.py walker_01 frozen_02                           # some variants

Exports assets/models/zombies/zombie_<kind>_<nn>.glb (+ sources/zombie_<kind>_<nn>.blend + the Godot `.import`,
template lib/export.py kind "char": humanoid retarget -> GeneralSkeleton, no animations). Same skeleton as the
survivor (lib.rig.build_armature: 22 SkeletonProfileHumanoid bones + 5 sockets, T-pose, front -Y), so the Zom_*
library (anims/zombie_anims.glb) and humanoid_loco / humanoid_combat play on every zombie. Body types change the rig
parameters height / width only (the retarget normalises the Hips track by the Hips rest height, so planted feet stay
planted); the hunched posture comes from the animations, not from the rest pose. File structure (§4.4):

    Armature
    ├─ Body        one palette_vcol surface (COLOR_0 RGBA, A = baked AO); rigid skin, except long skirts (coat, gown)
    │              that blend Hips -> Left/RightUpperLeg (<= 2 influences, BLEND_PAIRS)
    └─ Ice         frozen only: 3-5 ice shards, rigid on Chest / Head / arms, 1 palette_vcol surface (the code may hide
                   it when the frozen zombie wakes / shatters)

Recipe (§5.2): Body(params) + Clothes(outfit) + Palette(z_* desaturated, one saturated accent) + Damage (blood /
blood_dry / skin patches on clothes = tears, open bloody mouth). Gore-lite hooks: a `gore` cap closes the top of the
neck (inside the head) and the end of each upper arm (inside the forearm), so the code can "remove" the head or a
forearm by scaling the Head / Left|RightLowerArm bone pose to ~0 (the cap shows) and spawn gore/head_fragments.glb.
Kinds (verify_chars reads VARIANTS / KIND_RULES from here):
  walker_01..24   8 outfits (coat, hoodie, shirt, snowjacket, police, gown, overalls, hunter) x 3 bodies (thin / medium /
                  stocky) with alternating palettes
  runner_01..06   thin (width 0.86), sportswear (track suit, running jacket + tights, hoodie + joggers, tank top, ...)
  crawler_01..04  legless: trouser stumps with `gore` caps at mid-thigh / knee, long skinny arms, torn shirts
  bloater_01..04  width 1.34, inflated torso (belly rings), small head, yellow-green skin with boils, torn tops
  frozen_01..04   walker outfits with the frost palette (skin_frozen, frosted top faces) + the `Ice` shard mesh
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
from lib import palette  # noqa: E402
from lib import rig  # noqa: E402

SUBDIR = "zombies"
BUDGET = 2500                       # doc 05 §4.5 v2.1: zombie / NPC 1 500 - 2 500
BLEND_PAIRS = (("Hips", "LeftUpperLeg"), ("Hips", "RightUpperLeg"))
Z = palette.zombify

# ------------------------------------------------------------------------------------------------------------
# body types: rig parameters + mesh girth (torso x / y, arms, legs, head)
# ------------------------------------------------------------------------------------------------------------
BODIES = {
    "thin": dict(params=dict(height=1.83, width=0.94), gx=0.88, gy=0.86, ga=0.86, gl=0.86, gh=1.0, belly=0.0),
    "medium": dict(params=dict(height=1.78, width=1.0), gx=1.0, gy=1.0, ga=1.0, gl=1.0, gh=1.0, belly=0.01),
    "stocky": dict(params=dict(height=1.74, width=1.10), gx=1.06, gy=1.12, ga=1.12, gl=1.12, gh=1.03, belly=0.035),
    "runner": dict(params=dict(height=1.79, width=0.86), gx=0.86, gy=0.84, ga=0.84, gl=0.84, gh=0.98, belly=0.0),
    "crawler": dict(params=dict(height=1.76, width=0.95), gx=0.90, gy=0.88, ga=0.82, gl=0.9, gh=1.0, belly=0.0),
    "bloater": dict(params=dict(height=1.80, width=1.34), gx=1.0, gy=1.0, ga=1.28, gl=1.24, gh=0.9, belly=0.0),
}

# ------------------------------------------------------------------------------------------------------------
# outfits (palette names before zombify; `accent` stays saturated)
# ------------------------------------------------------------------------------------------------------------
OUTFITS = {
    "coat": dict(top="parka_brown", top_b="cloth_dark", pants="pants_dark", shoes="boots", sleeve="long",
                 skirt=0.56, collar=True, buttons="cloth_dark", accent="paint_red", accent_part="scarf",
                 hair=("short", "bald")),
    "hoodie": dict(top="cloth_gray", top_b="plastic_red", pants="denim", shoes="cloth_white", sleeve="long",
                   hood="down", pocket=True, accent="plastic_blue", accent_part="pocket", hair=("hood", "short")),
    "shirt": dict(top="cloth_white", top_b="paper", pants="pants_dark", shoes="boots", sleeve="rolled", collar=True,
                  buttons="cloth_gray", accent="paint_red", accent_part="tie", hair=("short", "long")),
    "snowjacket": dict(top="jacket_blue", top_b="jacket_green", pants="cloth_dark", shoes="boots_brown",
                       sleeve="puffy", quilt=True, collar=True, accent="hivis_orange", accent_part="yoke",
                       hair=("beanie", "short")),
    "police": dict(top="police_blue", top_b="police_blue", pants="police_blue", shoes="boots", sleeve="long",
                   collar=True, accent="paint_yellow", accent_part="vest", hair=("police_cap", "short")),
    "gown": dict(top="hospital_green", top_b="hospital_green", pants=None, shoes="sock", sleeve="short",
                 skirt=0.50, bare_legs=True, accent="cloth_white", accent_part="wristband", hair=("bald", "long"),
                 no_zombify=("top", "top_b")),
    "overalls": dict(top="cloth_gray", top_b="rust", pants="denim", shoes="boots_brown", sleeve="rolled",
                     bib=True, accent="paint_yellow", accent_part="hardhat", hair=("hardhat", "hardhat")),
    "hunter": dict(top="parka_olive", top_b="military_green", pants="military_green", shoes="boots_brown",
                   sleeve="long", collar=True, accent="hivis_orange", accent_part="vest_cap", hair=("hunter_cap", "hunter_cap")),
    # runners: sportswear
    "tracksuit": dict(top="plastic_red", top_b="plastic_red", pants="plastic_red", shoes="cloth_white", sleeve="long",
                      stripes="cloth_white", accent="cloth_white", accent_part="stripes", hair=("short",)),
    "running": dict(top="jacket_green", top_b="jacket_green", pants="plastic_black", shoes="cloth_white",
                    sleeve="long", accent="hivis_orange", accent_part="yoke", hair=("headband",)),
    "joggers": dict(top="cloth_dark", top_b="cloth_gray", pants="cloth_gray", shoes="plastic_blue", sleeve="long",
                    hood="up", accent="paint_yellow", accent_part="pocket", pocket=True, hair=("hood",)),
    "tanktop": dict(top="paint_white", top_b="paint_white", pants="plastic_blue", shoes="cloth_white", sleeve="none",
                    shorts=True, accent="paint_red", accent_part="shorts_band", hair=("long",)),
    "windbreaker": dict(top="jacket_mustard", top_b="cloth_dark", pants="plastic_black", shoes="cloth_gray",
                        sleeve="long", collar=True, accent="plastic_blue", accent_part="yoke", hair=("short",)),
    "cycling": dict(top="plastic_blue", top_b="paint_yellow", pants="plastic_black", shoes="plastic_black",
                    sleeve="short", shorts=True, accent="paint_yellow", accent_part="stripes", hair=("cap",)),
}
WALKER_OUTFITS = ("coat", "hoodie", "shirt", "snowjacket", "police", "gown", "overalls", "hunter")
SKINS = ("skin_zombie", "skin_hd", "skin_dark")         # base tones; non-green ones are zombified + mottled
HAIRS = ("beard", "cloth_dark", "hay", "cloth_gray", "wood")


def _variants():
    out = {}
    bodies = ("thin", "medium", "stocky")
    n = 0
    for bi, body in enumerate(bodies):
        for oi, outfit in enumerate(WALKER_OUTFITS):
            n += 1
            out["walker_%02d" % n] = dict(kind="walker", body=body, outfit=outfit, pal=(bi + oi) % 2,
                                          skin=SKINS[(oi + 2 * bi) % 3], hair=HAIRS[(oi + bi) % 5], seed=n)
    for k, outfit in enumerate(("tracksuit", "running", "joggers", "tanktop", "windbreaker", "cycling")):
        out["runner_%02d" % (k + 1)] = dict(kind="runner", body="runner", outfit=outfit, pal=k % 2,
                                            skin=SKINS[k % 3], hair=HAIRS[k % 5], seed=100 + k)
    for k, (outfit, cut) in enumerate((("shirt", (0.70, 0.70)), ("coat", (0.66, 0.50)), ("hoodie", (0.50, 0.50)),
                                       ("overalls", (0.72, 0.56)))):
        out["crawler_%02d" % (k + 1)] = dict(kind="crawler", body="crawler", outfit=outfit, pal=(k + 1) % 2,
                                             skin=SKINS[(k + 1) % 3], hair=HAIRS[(k + 2) % 5], seed=200 + k, cut=cut)
    for k, outfit in enumerate(("gown", "shirt", "overalls", "gown")):
        out["bloater_%02d" % (k + 1)] = dict(kind="bloater", body="bloater", outfit=outfit, pal=k % 2,
                                             skin="bloat", hair=HAIRS[(k + 3) % 5], seed=300 + k)
    for k, (outfit, body) in enumerate((("coat", "medium"), ("snowjacket", "thin"), ("hunter", "stocky"),
                                        ("police", "medium"))):
        out["frozen_%02d" % (k + 1)] = dict(kind="frozen", body=body, outfit=outfit, pal=k % 2, skin="frozen",
                                            hair=HAIRS[k % 5], seed=400 + k, shards=(4, 5, 3, 4)[k])
    return out


VARIANTS = _variants()
# verify_chars.py: per-kind height range (top of the mesh, m) and whether the feet touch the ground at the rig
# contact points (crawlers have no feet)
KIND_RULES = {
    "walker": dict(height=(1.64, 1.94), feet=True), "runner": dict(height=(1.66, 1.92), feet=True),
    "crawler": dict(height=(1.60, 1.86), feet=False), "bloater": dict(height=(1.62, 1.90), feet=True),
    "frozen": dict(height=(1.64, 1.98), feet=True),
}
MESH_NAMES = ("Body", "Ice")


def rig_params(name):
    return rig.params(**BODIES[VARIANTS[name]["body"]]["params"])


# ------------------------------------------------------------------------------------------------------------
# helpers
# ------------------------------------------------------------------------------------------------------------
def sq_ring(cx, cy, z, rx, ry, n=12, p=2.6, y_bias=0.0):
    pts = []
    for i in range(n):
        t = 2 * math.pi * i / n + math.pi / n
        c, s = math.cos(t), math.sin(t)
        x = rx * math.copysign(abs(c) ** (2 / p), c)
        y = ry * math.copysign(abs(s) ** (2 / p), s)
        if y > 0:
            y *= 1 + y_bias
        pts.append(Vector((cx + x, cy + y, z)))
    return pts


def yz_ring(x, cy, cz, ry, rz, n=10, p=2.2):
    pts = []
    for i in range(n):
        t = 2 * math.pi * i / n
        c, s = math.cos(t), math.sin(t)
        pts.append(Vector((x, cy + ry * math.copysign(abs(c) ** (2 / p), c),
                           cz + rz * math.copysign(abs(s) ** (2 / p), s))))
    return pts


def ring_axis(c, axis, r, n=8):
    return lp.ring(Vector(c), Vector(axis), r, n)


def colours(v):
    """Colour map of a variant (palette names; clothes zombified, the accent saturated)."""
    o = OUTFITS[v["outfit"]]
    nz = o.get("no_zombify", ())

    def cz(key, name):
        if name is None:
            return None
        return name if key in nz else Z(name)
    top = o["top"] if v["pal"] == 0 else o.get("top_b", o["top"])
    M = dict(top=cz("top", top), top2=Z("cloth_dark") if top != "cloth_dark" else Z("cloth_gray"),
             pants=cz("pants", o["pants"]) if o["pants"] else None, shoes=Z(o["shoes"]), sole=Z("boots"),
             accent=o["accent"], hair=Z(v["hair"]), eyes="eyes_dark", mouth="blood_dry", blood="blood",
             blood_dry="blood_dry", gore="gore", buttons=Z(o.get("buttons", "cloth_dark")),
             stripe=o.get("stripes", "cloth_white"))
    if v["skin"] == "frozen":
        M.update(skin="skin_frozen", skin2="ice", hair="snow_shadow", mouth="snow_shadow")
    elif v["skin"] == "bloat":
        M.update(skin=Z("hay"), skin2="skin_zombie", boil="moss")
    elif v["skin"] == "skin_zombie":
        M.update(skin="skin_zombie", skin2=Z("moss"))
    else:
        M.update(skin=Z(v["skin"]), skin2="skin_zombie")
    return M


def skirt_shell(mb, spec, rx0, ry0, mat, t=0.006):
    """Long skirt (coat / gown) as a thin closed shell near the hem: outer loft hem -> waist, an inward-facing lining 6 mm
    inside up to the waist, and a downward annulus joining them at the hem. No cap across the hem (with the thigh
    blend a cap folds) and no open edge (looking into the hem shows the lining, never a back face). Both shells are
    triangulated with the SAME diagonals, so the twisted quads between the thighs never intersect."""
    outer = [sq_ring(0, cy, z, rx0 + dx, ry0 + dy, y_bias=0.05) for cy, z, dx, dy in spec]
    inner = [sq_ring(0, cy, z, rx0 + dx - t, ry0 + dy - t, y_bias=0.05) for cy, z, dx, dy in spec[:4]]

    def tri(f0, flip):
        faces = mb.faces[f0:]
        del mb.faces[f0:]
        for idx, m, sn in faces:
            ts = [idx] if len(idx) == 3 else [(idx[0], idx[k], idx[k + 1]) for k in range(1, len(idx) - 1)]
            for tt in ts:
                mb.faces.append([tuple(reversed(tt)) if flip else tuple(tt), m, sn])
    f0 = len(mb.faces)
    mb.loft(outer, mat, cap_start=False, cap_end=True)
    tri(f0, False)
    f0 = len(mb.faces)
    mb.loft(inner, mat, cap_start=False, cap_end=False)
    tri(f0, True)
    f0 = len(mb.faces)
    mb.loft([outer[0], inner[0]], mat, cap_start=False, cap_end=False, seg_facing=[(0, 0, -1)])
    tri(f0, False)


def funnel(mb, rings, cy, mat, n=14, neck=0.045):
    """Collar / scarf ring (z, rx, ry) closed by an upward annulus down to the neck, so no inner (back) face shows."""
    rr = [sq_ring(0, cy, z, rx, ry, n=n) for z, rx, ry in rings]
    ztop = rings[-1][0]
    rr.append(sq_ring(0, cy * 0.5, ztop + 0.004, neck, neck, n=n))
    rr.insert(0, sq_ring(0, cy, rings[0][0] - 0.006, rings[0][1] * 0.85, rings[0][2] * 0.85, n=n))
    facing = [None] * (len(rr) - 2) + [(0, 0, 1)]
    return mb.loft(rr, mat, cap_start=True, cap_end=True, seg_facing=facing)


class Parts(dict):
    def mb(self, bone):
        return self.setdefault(bone, lp.MeshBuilder())


# ------------------------------------------------------------------------------------------------------------
# reference-proportion geometry (rig.joints() of the 1.80 m reference), mapped per bone onto the variant rig
# ------------------------------------------------------------------------------------------------------------
def build_torso(P, M, o, v, bt):
    kind = v["kind"]
    top, top2 = M["top"], M["top2"]
    pants = M["pants"] or M["skin"]
    bloat = kind == "bloater"
    # pelvis / trouser seat (Hips)
    hips = P.mb("Hips")
    hips.loft([sq_ring(0, 0.0, 0.79, 0.150, 0.108, n=12), sq_ring(0, 0.0, 0.88, 0.168, 0.118, n=12),
               sq_ring(0, 0.0, 0.97, 0.170, 0.120, n=12), sq_ring(0, 0.0, 1.01, 0.150, 0.104, n=12)], pants, cap_start=True, cap_end=True)
    if o.get("shorts"):
        hips.loft([sq_ring(0, 0.0, 0.975, 0.176, 0.126, n=12), sq_ring(0, 0.0, 1.00, 0.176, 0.126, n=12)],
                  M["accent"] if o["accent_part"] == "shorts_band" else top2, cap_start=True, cap_end=True)
    # abdomen (Spine)
    sp = P.mb("Spine")
    if bloat:
        rings = [sq_ring(0, -0.00, 0.95, 0.20, 0.15, n=12), sq_ring(0, -0.05, 1.03, 0.29, 0.25, n=12),
                 sq_ring(0, -0.07, 1.12, 0.32, 0.29, n=12), sq_ring(0, -0.05, 1.21, 0.30, 0.26, n=12),
                 sq_ring(0, -0.02, 1.27, 0.27, 0.21, n=12)]
        sp.loft(rings, M["skin"], cap_start=True, cap_end=True)
    else:
        b = bt["belly"]
        sp.loft([sq_ring(0, 0.0, 0.96, 0.175, 0.123, y_bias=0.04), sq_ring(0, -b, 1.09, 0.184 + b * 0.5, 0.13 + b,
                                                                           y_bias=0.05),
                 sq_ring(0, -b * 0.5, 1.21, 0.188, 0.131 + b * 0.5, y_bias=0.06),
                 sq_ring(0, -b * 0.3, 1.25, 0.172, 0.118 + b * 0.3, y_bias=0.05)], top, cap_start=True, cap_end=True)
    # chest
    ch = P.mb("Chest")
    if bloat:
        ch.loft([sq_ring(0, -0.02, 1.25, 0.28, 0.21, n=12), sq_ring(0, -0.01, 1.35, 0.26, 0.18, n=12),
                 sq_ring(0, 0.0, 1.43, 0.215, 0.14, n=12), sq_ring(0, 0.004, 1.48, 0.14, 0.10, n=12),
                 sq_ring(0, 0.008, 1.505, 0.085, 0.075, n=12)], M["skin"], cap_start=True, cap_end=True)
    else:
        ch.loft([sq_ring(0, 0.0, 1.21, 0.19, 0.132, y_bias=0.06), sq_ring(0, 0.0, 1.33, 0.20, 0.13, y_bias=0.07),
                 sq_ring(0, 0.0, 1.42, 0.19, 0.122, y_bias=0.05), sq_ring(0, 0.004, 1.475, 0.14, 0.10),
                 sq_ring(0, 0.008, 1.50, 0.085, 0.075)], top, cap_start=True, cap_end=True)
    # long skirt (coat / gown): Hips, blended to the thighs later
    if o.get("skirt") and kind not in ("crawler",):
        hem = o["skirt"]
        rx0 = 0.30 if bloat else 0.186
        ry0 = 0.24 if bloat else 0.134
        spec = [(0.006, hem, 0.03, 0.03), (0.006, hem + 0.02, 0.035, 0.034), (0.004, (hem + 0.96) * 0.5, 0.018, 0.02),
                (0.0, 0.96, -0.004, -0.004), (0.0, 1.00, -0.03, -0.03)]
        skirt_shell(hips, spec, rx0, ry0, top)
    elif o.get("skirt") and kind == "crawler":
        hips.loft([sq_ring(0, 0.006, 0.74, 0.20, 0.145, y_bias=0.05), sq_ring(0, 0.004, 0.86, 0.194, 0.138),
                   sq_ring(0, 0.0, 1.00, 0.18, 0.126)], top, cap_start=True, cap_end=True)
    # bloater: torn top covering only the chest / shoulders + a hanging rag
    if bloat:
        ch.loft([sq_ring(0, -0.02, 1.30, 0.285, 0.215, n=12), sq_ring(0, -0.01, 1.37, 0.265, 0.19, n=12),
                 sq_ring(0, 0.0, 1.44, 0.222, 0.146, n=12), sq_ring(0, 0.004, 1.485, 0.15, 0.108, n=12)], top,
                cap_start=True, cap_end=True)
        if not o.get("skirt"):
            hips.loft([sq_ring(0, 0.004, 0.80, 0.20, 0.15, n=12), sq_ring(0, 0.0, 0.95, 0.215, 0.158, n=12),
                       sq_ring(0, 0.0, 1.00, 0.21, 0.155, n=12)], pants if o["pants"] else top, cap_start=True, cap_end=True)
    # details: collar, placket, buttons, pockets, tie, hood, vest, bib, yoke, quilting, stripes, scarf
    if o.get("collar") and not bloat:
        funnel(ch, [(1.455, 0.125, 0.112), (1.50, 0.132, 0.12), (1.545, 0.118, 0.108)], 0.012,
               top2 if o["outfit_id"] in ("coat", "hunter") else top)
    if o.get("buttons") and not bloat:
        for bone, z0, z1 in (("Spine", 0.99, 1.21), ("Chest", 1.21, 1.43)):
            P.mb(bone).box((-0.007, -0.146, z0), (0.007, -0.118, z1), M["buttons"])
    if o.get("pocket"):
        mat = M["accent"] if o["accent_part"] == "pocket" else top2
        sp.box((-0.10, -0.152, 1.00), (0.10, -0.110, 1.10), mat)
    if o["accent_part"] == "tie":
        ch.box((-0.016, -0.152, 1.30), (0.016, -0.124, 1.44), M["accent"])
        sp.box((-0.024, -0.150, 1.07), (0.024, -0.122, 1.23), M["accent"])
    if o.get("hood") == "down":
        ch.loft([sq_ring(0, 0.12, 1.40, 0.13, 0.055, n=10), sq_ring(0, 0.14, 1.48, 0.145, 0.075, n=10),
                 sq_ring(0, 0.135, 1.555, 0.11, 0.06, n=10), sq_ring(0, 0.12, 1.59, 0.05, 0.03, n=10)],
                M["accent"] if o["accent_part"] == "hood" else top)
    if o["accent_part"] in ("vest", "vest_cap"):
        for bone, rings in (("Spine", [sq_ring(0, 0.0, 1.00, 0.192, 0.137, y_bias=0.05),
                                       sq_ring(0, 0.0, 1.23, 0.198, 0.140, y_bias=0.06)]),
                            ("Chest", [sq_ring(0, 0.0, 1.22, 0.198, 0.140, y_bias=0.06),
                                       sq_ring(0, 0.0, 1.33, 0.207, 0.138, y_bias=0.07),
                                       sq_ring(0, 0.0, 1.40, 0.195, 0.128, y_bias=0.05)])):
            P.mb(bone).loft(rings, M["accent"], cap_start=True, cap_end=True)
        for sx in (-1, 1):                                  # vest shoulder straps
            H.tube(ch, [(sx * 0.10, -0.12, 1.39), (sx * 0.11, -0.02, 1.49), (sx * 0.10, 0.10, 1.42)],
                   [(0.012, 0.035)] * 3, 4, M["accent"], cap_end=True, cap_start=True)
        if o["outfit_id"] == "police":
            ch.box((0.06, -0.150, 1.33), (0.10, -0.134, 1.37), "brass")                 # badge
    if o.get("bib"):
        pants = M["pants"]
        sp.loft([sq_ring(0, 0.0, 0.97, 0.182, 0.128, y_bias=0.04), sq_ring(0, 0.0, 1.10, 0.190, 0.134, y_bias=0.05)],
                pants, cap_start=True, cap_end=True)
        ch.box((-0.11, -0.145, 1.10), (0.11, -0.118, 1.37), pants)                   # bib front
        ch.box((-0.05, -0.150, 1.26), (0.05, -0.140, 1.33), Z("cloth_dark"))           # bib pocket
        for sx in (-1, 1):
            H.tube(ch, [(sx * 0.09, -0.14, 1.36), (sx * 0.11, -0.04, 1.495), (sx * 0.09, 0.10, 1.42),
                        (sx * 0.07, 0.14, 1.20)], [(0.008, 0.024)] * 4, 4, pants, cap_end=True, cap_start=True)
            ch.box((sx * 0.09 - 0.016, -0.152, 1.345), (sx * 0.09 + 0.016, -0.140, 1.375), "chrome")
    if o["accent_part"] == "yoke":
        ch.loft([sq_ring(0, 0.0, 1.345, 0.206, 0.136, y_bias=0.07), sq_ring(0, 0.0, 1.405, 0.198, 0.130, y_bias=0.05)],
                M["accent"], cap_start=True, cap_end=True)
    if o.get("quilt") and not bloat:
        for bone, z in (("Spine", 1.07), ("Spine", 1.16), ("Chest", 1.27)):
            P.mb(bone).loft([sq_ring(0, 0.0, z, 0.192 + 0.02 * bt["belly"], 0.137 + bt["belly"], y_bias=0.05),
                             sq_ring(0, 0.0, z + 0.022, 0.192 + 0.02 * bt["belly"], 0.137 + bt["belly"], y_bias=0.05)],
                            top2, cap_start=True, cap_end=True)
    if o["accent_part"] == "scarf":
        funnel(ch, [(1.44, 0.118, 0.112), (1.49, 0.124, 0.118), (1.53, 0.108, 0.102)], 0.012, M["accent"], n=12)
        H.tube(ch, [(0.06, -0.10, 1.47), (0.07, -0.14, 1.38), (0.085, -0.145, 1.25)], [(0.012, 0.04)] * 3, 4,
               M["accent"], cap_end=True, cap_start=True)
    if o["accent_part"] == "stripes" and o.get("stripes"):
        for sx in (-1, 1):
            sp.box((sx * 0.176, -0.02, 0.98), (sx * 0.196, 0.02, 1.22), M["stripe"])
            ch.box((sx * 0.186, -0.02, 1.22), (sx * 0.206, 0.02, 1.40), M["stripe"])
    return hips, sp, ch


def build_head(P, M, o, v, style):
    hd = P.mb("Head")
    nk = P.mb("Neck")
    # neck: tube, the top closed by a gore cap inside the head (decapitation hook)
    rings = [ring_axis((0, 0.005, 1.45), (0, 0, 1), 0.050), ring_axis((0, 0.005, 1.57), (0, 0, 1), 0.047),
             ring_axis((0, 0.005, 1.585), (0, 0, 1), 0.034)]
    nk.loft(rings, M["skin"], cap_start=True, cap_end=True, cap_mats=(None, M["gore"]))
    # skull, jaw hanging open, nose, sunken eyes, bloody mouth
    hd.loft([sq_ring(0, 0.010, 1.536, 0.040, 0.046, n=10, p=2.2), sq_ring(0, 0.006, 1.565, 0.064, 0.080, n=10, p=2.2),
             sq_ring(0, 0.006, 1.612, 0.079, 0.095, n=10, p=2.2), sq_ring(0, 0.008, 1.665, 0.080, 0.097, n=10, p=2.2),
             sq_ring(0, 0.010, 1.712, 0.066, 0.082, n=10, p=2.2), sq_ring(0, 0.012, 1.738, 0.038, 0.048, n=10, p=2.2),
             [Vector((0, 0.012, 1.746))]], M["skin"], cap_start=True, cap_end=False)
    hd.loft([sq_ring(0, -0.030, 1.525, 0.040, 0.030, n=8, p=2.2), sq_ring(0, -0.034, 1.552, 0.052, 0.046, n=8, p=2.2),
             sq_ring(0, -0.020, 1.585, 0.050, 0.050, n=8, p=2.2)], M["skin"])                      # hanging jaw
    hd.box((-0.011, -0.108, 1.60), (0.011, -0.086, 1.632), M["skin"])
    for sx in (-1, 1):
        x = sx * 0.036
        hd.poly([(x - 0.017, -0.0925, 1.640), (x + 0.017, -0.0925, 1.640), (x + 0.017, -0.0925, 1.664),
                 (x - 0.017, -0.0925, 1.664)], M["eyes"], facing=(0, -1, 0))
        hd.box((x - 0.021, -0.097, 1.667), (x + 0.021, -0.083, 1.676), M["skin2"])            # brow ridge
    hd.poly([(-0.028, -0.080, 1.548), (0.028, -0.080, 1.548), (0.024, -0.088, 1.578), (-0.024, -0.088, 1.578)],
            M["eyes"], facing=(0, -1, 0.2))                                                # open mouth
    hd.box((-0.034, -0.083, 1.525), (0.034, -0.060, 1.545), M["mouth"])                     # bloody chin
    # hair / headwear
    hair = M["hair"]
    if style in ("short", "long", "headband", "cap"):
        hd.loft([sq_ring(0, 0.018, 1.640, 0.085, 0.094, n=12, p=2.0), sq_ring(0, 0.012, 1.690, 0.086, 0.101, n=12, p=2.0),
                 sq_ring(0, 0.008, 1.728, 0.070, 0.086, n=12, p=2.0), sq_ring(0, 0.006, 1.752, 0.040, 0.050, n=12, p=2.0),
                 [Vector((0, 0.006, 1.760))]], hair, cap_start=True, cap_end=True)
        if style == "long":
            hd.loft([sq_ring(0, 0.075, 1.50, 0.075, 0.040, n=10), sq_ring(0, 0.070, 1.60, 0.088, 0.052, n=10),
                     sq_ring(0, 0.050, 1.70, 0.080, 0.056, n=10)], hair)
        if style == "headband":
            hd.loft([sq_ring(0, 0.008, 1.675, 0.089, 0.104, n=12, p=2.0), sq_ring(0, 0.008, 1.700, 0.088, 0.103, n=12,
                                                                                  p=2.0)], M["accent"],
                    cap_start=True, cap_end=True)
        if style == "cap":
            hd.loft([sq_ring(0, 0.004, 1.672, 0.090, 0.104, n=12, p=2.0), sq_ring(0, 0.004, 1.735, 0.078, 0.092, n=12,
                                                                                  p=2.0),
                     sq_ring(0, 0.004, 1.765, 0.040, 0.050, n=12, p=2.0)], M["top"], cap_start=True, cap_end=True)
            hd.box((-0.06, -0.165, 1.672), (0.06, -0.075, 1.686), M["accent"])
    elif style == "bald":
        for sx in (-1, 1):                                            # patchy hair over the ears
            hd.blob((sx * 0.072, 0.03, 1.655), (0.018, 0.05, 0.03), hair, subdiv=1, jitter=0.0)
    elif style == "beanie":
        hd.loft([sq_ring(0, 0.004, 1.645, 0.088, 0.103, n=12, p=2.0), sq_ring(0, 0.004, 1.690, 0.090, 0.105, n=12, p=2.0),
                 sq_ring(0, 0.004, 1.740, 0.076, 0.090, n=12, p=2.0), sq_ring(0, 0.004, 1.772, 0.050, 0.060, n=12, p=2.0),
                 [Vector((0, 0.004, 1.785))]], M["top2"], cap_start=True, cap_end=True)
    elif style in ("police_cap", "hunter_cap"):
        crown = M["top"] if style == "police_cap" else M["accent"]
        hd.loft([sq_ring(0, 0.004, 1.672, 0.089, 0.103, n=12, p=2.0), sq_ring(0, 0.006, 1.735, 0.092, 0.108, n=12, p=2.4),
                 sq_ring(0, 0.006, 1.768, 0.086, 0.100, n=12, p=2.4)], crown, cap_start=True, cap_end=True)
        if style == "police_cap":
            hd.loft([sq_ring(0, 0.004, 1.680, 0.091, 0.105, n=12, p=2.0), sq_ring(0, 0.004, 1.700, 0.091, 0.105, n=12,
                                                                                  p=2.0)], "iron",
                    cap_start=True, cap_end=True)
            hd.box((-0.012, -0.108, 1.705), (0.012, -0.098, 1.73), "brass")
        hd.box((-0.066, -0.170, 1.670), (0.066, -0.080, 1.684), "iron" if style == "police_cap" else crown)
    elif style == "hardhat":
        hd.blob((0, 0.004, 1.705), (0.098, 0.112, 0.08), M["accent"], subdiv=2, jitter=0.0, clamp_z=1.668)
        hd.loft([sq_ring(0, -0.004, 1.668, 0.120, 0.138, n=14, p=2.0), sq_ring(0, -0.004, 1.680, 0.120, 0.138, n=14, p=2.0)],
                M["accent"], cap_start=True, cap_end=True)
    elif style == "hood":
        hd.loft([sq_ring(0, 0.030, 1.52, 0.110, 0.095, n=12), sq_ring(0, 0.012, 1.62, 0.108, 0.118, n=12),
                 sq_ring(0, 0.012, 1.71, 0.098, 0.112, n=12), sq_ring(0, 0.020, 1.775, 0.060, 0.074, n=12),
                 [Vector((0, 0.03, 1.795))]], M["top"], cap_start=True, cap_end=True,
                inside=(0, 0.02, 1.64))
    return hd


def build_arms(P, M, o, v, bt):
    j = rig.joints()
    kind = v["kind"]
    sleeve = o.get("sleeve", "long")
    bloat = kind == "bloater"
    top = M["top"]
    skin = M["skin"]
    for s, side in ((1, "Left"), (-1, "Right")):
        la, hn = j[side + "LowerArm"], j[side + "Hand"]
        sh = P.mb(side + "Shoulder")
        sh_mat = skin if (sleeve == "none" or (bloat and v["seed"] % 2)) else top
        sh.loft([yz_ring(s * 0.10, 0.0, 1.40, 0.100, 0.085), yz_ring(s * 0.19, 0.0, 1.405, 0.090, 0.086),
                 yz_ring(s * 0.25, 0.0, 1.41, 0.078, 0.076), yz_ring(s * 0.28, 0.0, 1.412, 0.056, 0.056)], sh_mat, cap_start=True, cap_end=True)
        um = P.mb(side + "UpperArm")
        up_mat = top if sleeve in ("long", "rolled", "puffy", "short") else skin
        r0, r1, r2 = (0.084, 0.076, 0.068) if sleeve == "puffy" else (0.076, 0.068, 0.061)
        um.loft([yz_ring(s * 0.19, 0.0, 1.405, r0, r0), yz_ring(s * 0.34, 0.0, 1.42, r1, r1),
                 yz_ring(la.x + s * 0.03, 0.0, 1.43, r2, r2), yz_ring(la.x + s * 0.036, 0.0, 1.43, 0.045, 0.045)],
                up_mat, cap_start=True, cap_end=True, cap_mats=(None, M["gore"]),
                side_mats=[up_mat, up_mat, M["gore"]])
        if sleeve == "short":                                       # sleeve hem + bare lower upper-arm
            um.loft([yz_ring(s * 0.30, 0.0, 1.415, 0.074, 0.074), yz_ring(la.x + s * 0.028, 0.0, 1.43, 0.064, 0.064)],
                    skin, cap_start=True, cap_end=True)
        lm = P.mb(side + "LowerArm")
        lo_mat = top if sleeve in ("long", "puffy") else skin
        r3, r4 = (0.070, 0.062) if sleeve == "puffy" else (0.062, 0.052)
        lm.loft([yz_ring(la.x - s * 0.04, 0.0, 1.43, r3, r3), yz_ring(la.x + s * 0.12, 0.0, 1.435, r3 - 0.006, r3 - 0.008),
                 yz_ring(hn.x - s * 0.03, 0.0, 1.44, r4, r4 - 0.002)], lo_mat, cap_start=True, cap_end=True)
        if sleeve == "rolled":
            lm.loft([yz_ring(la.x - s * 0.035, 0.0, 1.43, 0.070, 0.070), yz_ring(la.x + s * 0.03, 0.0, 1.43, 0.068, 0.068)],
                    top, cap_start=True, cap_end=True)
        if sleeve == "long" and o.get("stripes") and o["accent_part"] == "stripes":
            x0, x1 = sorted((s * 0.20, la.x + s * 0.02))
            um.box((x0, -0.012, 1.476), (x1, 0.012, 1.492), M["stripe"])
        # wristband (gown)
        if o["accent_part"] == "wristband" and side == "Left":
            lm.loft([yz_ring(hn.x - s * 0.055, 0.0, 1.44, 0.055, 0.053), yz_ring(hn.x - s * 0.03, 0.0, 1.44, 0.055, 0.053)],
                    M["accent"], cap_start=True, cap_end=True)
        # hand: palm + 3 claw fingers + thumb (skin), fingertips bloody on one hand
        hm = P.mb(side + "Hand")
        hm.loft([yz_ring(hn.x - s * 0.012, 0.0, 1.44, 0.044, 0.032, n=8), yz_ring(hn.x + s * 0.045, -0.004, 1.438, 0.052, 0.027, n=8),
                 yz_ring(hn.x + s * 0.072, -0.004, 1.436, 0.048, 0.022, n=8)], skin)
        tip = M["blood_dry"] if (side == "Right") == (v["seed"] % 2 == 0) else skin
        for k, dy in enumerate((-0.030, -0.006, 0.020)):
            L = 0.062 if kind == "crawler" else 0.052
            H.tube(hm, [(hn.x + s * 0.064, dy, 1.436), (hn.x + s * (0.064 + L * 0.6), dy, 1.430),
                        (hn.x + s * (0.064 + L), dy - 0.004, 1.416)], [0.013, 0.012, 0.008], 4, tip if k == 1 else skin)
        H.tube(hm, [(hn.x + s * 0.02, -0.030, 1.44), (hn.x + s * 0.045, -0.062, 1.436)], [0.013, 0.010], 4, skin)


def build_legs(P, M, o, v, bt):
    j = rig.joints()
    kind = v["kind"]
    bare = o.get("bare_legs")
    pants = M["pants"] or M["skin"]
    for s, side in ((1, "Left"), (-1, "Right")):
        x = j[side + "UpperLeg"].x
        ul = P.mb(side + "UpperLeg")
        up_mat = M["skin"] if bare else pants
        if kind == "crawler":
            cut = v["cut"][0 if side == "Left" else 1]
            if cut >= 0.52:                 # stump above the knee: torn trouser ring + gore cap
                ul.loft([sq_ring(x, 0.0, 0.95, 0.088, 0.096, n=10, p=2.2), sq_ring(x, -0.004, cut + 0.06, 0.080, 0.088, n=10, p=2.2),
                         sq_ring(x, 0.0, cut, 0.084, 0.090, n=10, p=2.2), sq_ring(x, 0.0, cut - 0.012, 0.062, 0.066, n=10, p=2.2)],
                        up_mat, cap_start=True, cap_end=True, cap_mats=(None, M["gore"]),
                        side_mats=[up_mat, M["blood_dry"], M["gore"]])
                continue
            ul.loft([sq_ring(x, 0.0, 0.95, 0.088, 0.096, n=10, p=2.2), sq_ring(x, -0.004, 0.72, 0.080, 0.088, n=10, p=2.2),
                     sq_ring(x, 0.0, 0.47, 0.070, 0.078, n=10, p=2.2)], up_mat, cap_start=True, cap_end=True)
            P.mb(side + "LowerLeg").loft([sq_ring(x, 0.0, 0.53, 0.070, 0.077, n=10, p=2.2),
                                          sq_ring(x, 0.004, 0.47, 0.074, 0.080, n=10, p=2.2),
                                          sq_ring(x, 0.004, 0.44, 0.052, 0.056, n=10, p=2.2)],
                                         pants, cap_start=True, cap_end=True, cap_mats=(None, M["gore"]),
                                         side_mats=[M["blood_dry"], M["gore"]])
            continue
        if o.get("shorts"):
            ul.loft([sq_ring(x, 0.0, 0.95, 0.092, 0.100, n=10, p=2.2), sq_ring(x, -0.004, 0.76, 0.088, 0.094, n=10, p=2.2)],
                    pants, cap_start=True, cap_end=True)
            up_mat = M["skin"]
        ul.loft([sq_ring(x, 0.0, 0.95, 0.086, 0.094, n=10, p=2.2), sq_ring(x, -0.004, 0.72, 0.078, 0.086, n=10, p=2.2),
                 sq_ring(x, 0.0, 0.47, 0.068, 0.076, n=10, p=2.2)], up_mat, cap_start=True, cap_end=True)
        ll = P.mb(side + "LowerLeg")
        lo_mat = M["skin"] if (bare or o.get("shorts")) else pants
        ll.loft([sq_ring(x, 0.0, 0.53, 0.068, 0.075, n=10, p=2.2), sq_ring(x, 0.004, 0.36, 0.060, 0.066, n=10, p=2.2),
                 sq_ring(x, 0.006, 0.26, 0.056, 0.062, n=10, p=2.2)], lo_mat, cap_start=True, cap_end=True)
        shoe = M["shoes"]
        if kind == "bloater" or bare:
            ll.loft([sq_ring(x, 0.012, 0.09, 0.056, 0.066, n=10, p=2.4), sq_ring(x, 0.010, 0.18, 0.058, 0.066, n=10, p=2.4),
                     sq_ring(x, 0.008, 0.24, 0.058, 0.064, n=10, p=2.4)], shoe, cap_start=True, cap_end=True)
        else:
            ll.loft([sq_ring(x, 0.012, 0.09, 0.058, 0.068, n=10, p=2.4), sq_ring(x, 0.010, 0.20, 0.061, 0.068, n=10, p=2.4),
                     sq_ring(x, 0.008, 0.28, 0.063, 0.070, n=10, p=2.4)], shoe, cap_start=True, cap_end=True)
        heel_y, ball_y, tip_y = j[side + "Heel"].y, j[side + "Ball"].y, j[side + "TipSole"].y
        ft = P.mb(side + "Foot")
        ft.loft([lp.rrect((x, heel_y, 0.072), 0.054, 0.072, 0.03, 'XZ'), lp.rrect((x, 0.0, 0.068), 0.059, 0.068, 0.03, 'XZ'),
                 lp.rrect((x, ball_y + 0.01, 0.050), 0.059, 0.050, 0.025, 'XZ')], shoe)
        ft.box((x - 0.056, heel_y - 0.075, 0.0), (x + 0.056, heel_y + 0.002, 0.028), M["sole"])
        tt = P.mb(side + "Toes")
        tt.loft([lp.rrect((x, ball_y + 0.03, 0.045), 0.058, 0.045, 0.022, 'XZ'), lp.rrect((x, ball_y - 0.05, 0.043), 0.056, 0.043, 0.022, 'XZ'),
                 lp.rrect((x, tip_y + 0.012, 0.033), 0.046, 0.033, 0.02, 'XZ'), lp.rrect((x, tip_y, 0.026), 0.034, 0.026, 0.015, 'XZ')],
                shoe)


def bloater_boils(P, M, v):
    rnd = random.Random(v["seed"])
    sp = P.mb("Spine")
    for k in range(6):
        a = rnd.uniform(-2.3, 2.3)
        z = rnd.uniform(0.98, 1.22)
        rr = 0.28 + 0.02 * math.cos((z - 1.12) * 8)
        c = Vector((math.sin(a) * rr, -0.06 - math.cos(a) * rr * 0.95, z))
        r = rnd.uniform(0.022, 0.038)
        sp.blob(c, (r, r, r * 0.9), M["boil"] if k % 3 else "hay", subdiv=0, jitter=0.1, rnd=rnd)
    # navel scar / stretch marks
    sp.box((-0.012, -0.372, 1.08), (0.012, -0.355, 1.13), M["blood_dry"])


def stains(P, M, v, o):
    """Gore-lite damage painted on the clothes (tears = skin patches, blood / dried blood), deterministic."""
    rnd = random.Random(v["seed"] * 7 + 3)
    cloth = {M["top"], M["pants"], M["top2"]} - {None}
    spots = [("Chest", Vector((rnd.uniform(-0.08, 0.08), -0.13, rnd.uniform(1.28, 1.40))), 0.07, M["blood"]),
             ("Spine", Vector((rnd.uniform(-0.12, 0.12), -0.13, rnd.uniform(1.00, 1.15))), 0.06, M["blood_dry"]),
             ("Spine", Vector((rnd.choice((-1, 1)) * 0.17, rnd.uniform(-0.05, 0.08), 1.08)), 0.055, M["skin"]),
             ("Chest", Vector((rnd.uniform(-0.1, 0.1), 0.13, rnd.uniform(1.25, 1.40))), 0.06, M["skin"])]
    side = rnd.choice(("Left", "Right"))
    j = rig.joints()
    spots.append((side + "LowerArm", j[side + "LowerArm"] + Vector((0.08 if side == "Left" else -0.08, -0.04, -0.03)),
                  0.05, M["skin"]))
    spots.append((("Left" if side == "Right" else "Right") + "UpperLeg",
                  Vector((0.11 if side == "Right" else -0.11, -0.08, rnd.uniform(0.60, 0.75))), 0.06, M["skin"]))
    spots.append((side + "LowerLeg", Vector((0.11 if side == "Left" else -0.11, -0.07, 0.40)), 0.05, M["blood_dry"]))
    if v["kind"] == "frozen":
        spots = [sp for sp in spots if sp[3] != M["blood"]]
    for bone, c, r, mat in spots:
        mb = P.get(bone)
        if mb is None:
            continue
        for fi in range(len(mb.faces)):
            if mb.faces[fi][1] not in cloth:
                continue
            d = (mb.center(fi) - c).length
            if d < r * (0.75 + 0.5 * rnd.random()):
                mb.faces[fi][1] = mat


def frost(P, M):
    """Frozen zombie: faces looking up in the T-pose (shoulders, head top, arm tops, collar) get frost."""
    for bone, mb in P.items():
        for fi in range(len(mb.faces)):
            n = mb.normal(fi)
            m = mb.faces[fi][1]
            if m in ("eyes_dark", M["gore"]):
                continue
            if n.z > 0.62:
                mb.faces[fi][1] = "snow"
            elif n.z > 0.35 and m not in (M["skin"],):
                mb.faces[fi][1] = "snow_shadow"


def ice_parts(v):
    """3-5 ice shards (pointed prisms) on Chest / Head / arms, rigid on their bone."""
    rnd = random.Random(v["seed"] * 13)
    j = rig.joints()
    specs = [("Chest", Vector((0.07, 0.10, 1.40)), Vector((0.25, 0.55, 1.0)), 0.20, 0.034),
             ("Head", Vector((-0.03, 0.05, 1.72)), Vector((-0.3, 0.45, 1.0)), 0.13, 0.026),
             ("LeftUpperArm", j["LeftUpperArm"] + Vector((0.14, 0.02, 0.05)), Vector((0.2, 0.3, 1.0)), 0.15, 0.028),
             ("RightShoulder", Vector((-0.20, 0.04, 1.47)), Vector((-0.35, 0.2, 1.0)), 0.17, 0.03),
             ("Chest", Vector((-0.08, 0.11, 1.32)), Vector((-0.3, 0.8, 0.6)), 0.12, 0.024),
             ("RightLowerArm", j["RightLowerArm"] + Vector((-0.12, 0.0, -0.05)), Vector((0.05, 0.1, -1.0)), 0.12, 0.018)]
    parts = Parts()
    for bone, base, axis, length, r in specs[:v["shards"]]:
        axis = Vector(axis).normalized()
        L = length * rnd.uniform(0.85, 1.15)
        rings = [lp.ring(base - axis * 0.03, axis, r, 5, rnd.uniform(0, 60)),
                 lp.ring(base + axis * (L * 0.45), axis, r * 0.75, 5, rnd.uniform(0, 60)),
                 [base + axis * L]]
        mb = parts.mb(bone)
        f0 = len(mb.faces)
        mb.loft(rings, "ice", cap_start=True, cap_end=True)
        for fi in range(f0, len(mb.faces)):
            if fi % 3 == 0:
                mb.faces[fi][1] = "ice_thin"
    return parts


# ------------------------------------------------------------------------------------------------------------
# mapping onto the variant rig
# ------------------------------------------------------------------------------------------------------------
TORSO = ("Hips", "Spine", "Chest")


def fit_parts(parts, p, bt):
    """Reference geometry -> variant rig: every vertex of bone b: J_t[b] + S_b (v - J_r[b])."""
    jr = rig.rest_heads()
    jt = rig.rest_heads(p)
    s = p["height"] / rig.REFERENCE_HEIGHT
    W = p["width"] * s
    for bone, mb in parts.items():
        if bone in TORSO:
            S = (W * bt["gx"], s * bt["gy"], s)
        elif bone in ("Neck", "Head"):
            S = (s * bt["gh"],) * 3
        elif bone.endswith("Shoulder"):
            S = (W, s * bt["ga"], s * bt["ga"])
        elif bone.endswith(("UpperArm", "LowerArm", "Hand")):
            S = (s, s * bt["ga"], s * bt["ga"])
        elif bone.endswith(("UpperLeg", "LowerLeg")):
            S = (s * bt["gl"], s * bt["gl"], s)
        else:
            S = (s, s, s)
        o_r, o_t = jr[bone], jt[bone]
        if bone == "Head" or bone == "Neck":
            o_r, o_t = jr["Neck"], jt["Neck"]
        mb.verts = [o_t + Vector(((q.x - o_r.x) * S[0], (q.y - o_r.y) * S[1], (q.z - o_r.z) * S[2])) for q in mb.verts]


def blend_skirt(body, p):
    """Coat / gown skirt below the hips follows the thighs (Hips + one UpperLeg, <= 2 influences)."""
    s = p["height"] / rig.REFERENCE_HEIGHT
    W = p["width"] * s
    hz = rig.joints(p)["Hips"].z
    vg = {g.name: g for g in body.vertex_groups}
    for leg in ("LeftUpperLeg", "RightUpperLeg"):
        if leg not in vg:
            vg[leg] = body.vertex_groups.new(name=leg)
    hips = vg["Hips"]
    n = 0
    for vx in body.data.vertices:
        gs = [(body.vertex_groups[g.group].name, g.weight) for g in vx.groups]
        if len(gs) != 1 or gs[0][0] != "Hips" or vx.co.z > hz - 0.02:
            continue
        # side factor from the horizontal direction (not |x|): the skirt and its lining 6 mm inside get the same
        # weights, so the lining never crosses the outer shell when the thighs split
        r = math.hypot(vx.co.x, vx.co.y)
        w = H.smoothstep(hz - 0.02, hz - 0.28 * s, vx.co.z) * 0.7 * H.smoothstep(0.0, 0.6, abs(vx.co.x) / max(r, 1e-6))
        if w <= 1e-3:
            continue
        hips.add([vx.index], 1.0 - w, 'REPLACE')
        vg["LeftUpperLeg" if vx.co.x > 0 else "RightUpperLeg"].add([vx.index], w, 'REPLACE')
        n += 1
    return n


def build(name):
    v = VARIANTS[name]
    o = dict(OUTFITS[v["outfit"]], outfit_id=v["outfit"])
    bt = BODIES[v["body"]]
    p = rig.params(**bt["params"])
    M = colours(v)
    lp.new_scene()
    arm = rig.build_armature(p)
    arm["zombie_kind"] = v["kind"]
    P = Parts()
    build_torso(P, M, o, v, bt)
    styles = o["hair"]
    style = styles[(v["seed"] + v["seed"] // 8) % len(styles)] if v["kind"] != "frozen" else styles[0]
    if v["kind"] == "bloater":
        style = ("bald", "short")[v["seed"] % 2]
    if style == "hood":
        o["hood"] = "up"
    build_head(P, M, o, v, style)
    build_arms(P, M, o, v, bt)
    build_legs(P, M, o, v, bt)
    if v["kind"] == "bloater":
        bloater_boils(P, M, v)
    stains(P, M, v, o)
    if v["kind"] == "frozen":
        frost(P, M)
    fit_parts(P, p, bt)
    body = rig.skin_rigid(dict(P), arm, "Body")
    blended = blend_skirt(body, p) if o.get("skirt") and v["kind"] != "crawler" else 0
    meshes = [body]
    if v["kind"] == "frozen":
        ip = ice_parts(v)
        fit_parts(ip, p, bt)
        ice = rig.skin_rigid(dict(ip), arm, "Ice")
        meshes.append(ice)
    for m in meshes:
        H.smooth(m, angle=55)
    if v["kind"] == "frozen":
        H.flat(meshes[1])
    problems = rig.check_armature(arm, p) + rig.check_rigid_skin(body, BLEND_PAIRS)
    for m in meshes[1:]:
        problems += rig.check_rigid_skin(m)
    tris = sum(H.tris(m) for m in meshes)
    if tris > BUDGET:
        problems.append("tris %d > %d" % (tris, BUDGET))
    if problems:
        raise RuntimeError("zombie_%s: %s" % (name, "; ".join(problems)))
    glb = export.save_and_export("zombie_" + name, SUBDIR, ao=dict(distance=0.25, samples=64, ground=True))
    export.write_import(glb, "char")
    print("   zombie_%-12s kind=%-7s body=%-7s outfit=%-11s hair=%-10s tris=%d skirt_blend=%d" % (
        name, v["kind"], v["body"], v["outfit"], style, tris, blended))
    return glb


def main(argv=()):
    names = [a for a in argv if not a.startswith("-")] or list(VARIANTS)
    for n in names:
        if n not in VARIANTS:
            raise KeyError("unknown zombie variant %s (known: %s)" % (n, ", ".join(VARIANTS)))
    rig.write_bonemap(export.BONEMAP_PATH)
    return [build(n) for n in names]


if __name__ == "__main__":
    main(sys.argv[1:])
