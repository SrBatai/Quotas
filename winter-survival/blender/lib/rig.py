"""Humanoid rig (ASSET_SPEC_V2 §4), extracted from prototypes/animpoc/build_humanoid.py.

* 22 bones with the exact Godot `SkeletonProfileHumanoid` names (Root + 21 deforming) + 5 non-deforming
  sockets = 27. T-pose rest, facing FRONT = -Y, left = +X, feet at z = 0.
* Deterministic roll: align_roll((0, -1, 0)) on vertical bones, align_roll((0, 0, 1)) on horizontal ones,
  so every humanoid shares the same rest orientation (rotations are interchangeable between characters).
* Rigid per-part skinning: each MeshBuilder part is built "for" one bone; parts are merged into one
  mesh `Body` whose vertices are 100 % weighted to their bone (never ARMATURE_AUTO).
* Proportions by parameters (height, width, leg_len, torso_len, arm_len); `hunch`/`lean` are carried in
  the parameters for the animation generator only (the rest pose is shared).

Used by chars/build_survivor.py (M1) and anims/build_loco.py. Self-test (builds a test humanoid in memory,
nothing is written to the repo):
    cd winter-survival/blender && python3 -m lib.rig --selftest
"""
import sys

import bpy
from mathutils import Vector

from . import lowpoly as lp

# name, parent, required by SkeletonProfileHumanoid
HUMANOID_BONES = [
    ("Root", None, False),
    ("Hips", "Root", True),
    ("Spine", "Hips", True),
    ("Chest", "Spine", False),
    ("Neck", "Chest", False),
    ("Head", "Neck", True),
    ("LeftShoulder", "Chest", True), ("LeftUpperArm", "LeftShoulder", True),
    ("LeftLowerArm", "LeftUpperArm", True), ("LeftHand", "LeftLowerArm", True),
    ("RightShoulder", "Chest", True), ("RightUpperArm", "RightShoulder", True),
    ("RightLowerArm", "RightUpperArm", True), ("RightHand", "RightLowerArm", True),
    ("LeftUpperLeg", "Hips", True), ("LeftLowerLeg", "LeftUpperLeg", True),
    ("LeftFoot", "LeftLowerLeg", True), ("LeftToes", "LeftFoot", False),
    ("RightUpperLeg", "Hips", True), ("RightLowerLeg", "RightUpperLeg", True),
    ("RightFoot", "RightLowerLeg", True), ("RightToes", "RightFoot", False),
]
BONE_NAMES = [b[0] for b in HUMANOID_BONES]
BONE_PARENTS = {b[0]: b[1] for b in HUMANOID_BONES}
REQUIRED_PROFILE_BONES = [b[0] for b in HUMANOID_BONES if b[2]]
DEFORM_BONES = [b for b in BONE_NAMES if b != "Root"]
# non-deforming sockets: name -> parent bone
SOCKETS = {"RightHandSocket": "RightHand", "LeftHandSocket": "LeftHand", "BackSocket": "Chest",
           "HipSocketR": "Hips", "HeadSocket": "Head"}
ALL_BONES = BONE_NAMES + list(SOCKETS)

# joint key used for each bone's head / tail
_HEAD_TAIL = {
    "Root": ("Root", None), "Hips": ("Hips", "Spine"), "Spine": ("Spine", "Chest"), "Chest": ("Chest", "Neck"),
    "Neck": ("Neck", "Head"), "Head": ("Head", "HeadTop"),
}
for _s in ("Left", "Right"):
    _HEAD_TAIL.update({
        _s + "Shoulder": (_s + "Shoulder", _s + "UpperArm"), _s + "UpperArm": (_s + "UpperArm", _s + "LowerArm"),
        _s + "LowerArm": (_s + "LowerArm", _s + "Hand"), _s + "Hand": (_s + "Hand", _s + "HandTip"),
        _s + "UpperLeg": (_s + "UpperLeg", _s + "LowerLeg"), _s + "LowerLeg": (_s + "LowerLeg", _s + "Foot"),
        _s + "Foot": (_s + "Foot", _s + "Toes"), _s + "Toes": (_s + "Toes", _s + "ToesTip"),
    })

REFERENCE_HEIGHT = 1.80
DEFAULT_PARAMS = dict(height=1.80, width=1.0, leg_len=1.0, torso_len=1.0, arm_len=1.0, hunch=0.0, lean=0.0)


def params(**kw):
    """Character parameters (ASSET_SPEC_V2 §4.2 variants). Unknown keys are rejected."""
    bad = set(kw) - set(DEFAULT_PARAMS)
    if bad:
        raise KeyError("unknown rig parameters %s" % sorted(bad))
    p = dict(DEFAULT_PARAMS)
    p.update(kw)
    return p


def joints(p=None):
    """World (Blender) joint positions of the T-pose: left = +X, front = -Y, up = +Z.
    Reference player (1.80 m): Hips 0.92, Spine 1.02, Chest 1.22, Neck 1.48, Head 1.56 (skull to 1.74),
    shoulders x +-0.20 z 1.44, arm 0.28 / 0.26 / 0.08, hips x +-0.11, legs 0.42 / 0.41, ankle z 0.09,
    toes 0.12 in front of the ankle."""
    p = params(**(p or {}))
    s = p["height"] / REFERENCE_HEIGHT
    W, L, T, A = p["width"] * s, p["leg_len"] * s, p["torso_len"] * s, p["arm_len"] * s
    ank = 0.09 * s
    knee = ank + 0.41 * L
    hip = knee + 0.42 * L
    j = {"Root": Vector((0, 0, 0)), "Hips": Vector((0, 0, hip)),
         "Spine": Vector((0, 0, hip + 0.10 * T)), "Chest": Vector((0, 0, hip + 0.30 * T)),
         "Neck": Vector((0, 0, hip + 0.56 * T)), "Head": Vector((0, 0, hip + 0.64 * T))}
    j["HeadTop"] = j["Head"] + Vector((0, 0, 0.18 * s))
    sh_z = hip + 0.52 * T
    for sx, side in ((1, "Left"), (-1, "Right")):
        j[side + "Shoulder"] = Vector((sx * 0.05 * W, 0, sh_z))
        j[side + "UpperArm"] = Vector((sx * 0.20 * W, 0, sh_z))
        j[side + "LowerArm"] = j[side + "UpperArm"] + Vector((sx * 0.28 * A, 0, 0))
        j[side + "Hand"] = j[side + "LowerArm"] + Vector((sx * 0.26 * A, 0, 0))
        j[side + "HandTip"] = j[side + "Hand"] + Vector((sx * 0.08 * A, 0, 0))
        j[side + "Fist"] = j[side + "Hand"] + Vector((sx * 0.04 * A, 0, 0))          # grip centre
        j[side + "UpperLeg"] = Vector((sx * 0.11 * W, 0, hip))
        j[side + "LowerLeg"] = Vector((sx * 0.11 * W, 0, knee))
        j[side + "Foot"] = Vector((sx * 0.11 * W, 0.02 * s, ank))
        j[side + "Toes"] = Vector((sx * 0.11 * W, -0.10 * s, 0.035 * s))
        j[side + "ToesTip"] = Vector((sx * 0.11 * W, -0.19 * s, 0.035 * s))
        # sole contact points (not bones): heel (on Foot), ball and toe tip (on Toes), all at z = 0.
        # The boot mesh must touch the ground exactly there (gait generator pivots, verify_chars metrics).
        j[side + "Heel"] = Vector((sx * 0.11 * W, 0.10 * s, 0.0))
        j[side + "Ball"] = Vector((sx * 0.11 * W, -0.10 * s, 0.0))
        j[side + "TipSole"] = Vector((sx * 0.11 * W, -0.19 * s, 0.0))
    j["BackSocket"] = Vector((0, 0.14 * s, hip + 0.38 * T))
    j["HipSocketR"] = Vector((-0.16 * W, 0, hip))
    j["HeadSocket"] = Vector((0, 0, j["Head"].z + 0.06 * s))
    return j


def leg_lengths(p=None):
    j = joints(p)
    return ((j["LeftUpperLeg"] - j["LeftLowerLeg"]).length, (j["LeftLowerLeg"] - j["LeftFoot"]).length)


def arm_lengths(p=None):
    j = joints(p)
    return ((j["LeftUpperArm"] - j["LeftLowerArm"]).length, (j["LeftLowerArm"] - j["LeftHand"]).length)


def rest_heads(p=None):
    """{bone: rest head (Blender armature space)} for the 22 profile bones and the 5 sockets."""
    j = joints(p)
    out = {b: j[_HEAD_TAIL[b][0]].copy() for b in BONE_NAMES}
    for s, par in SOCKETS.items():
        out[s] = (j[s] if s in j else j[s.replace("HandSocket", "Fist")]).copy()
    return out


# Sole contact points used by the gait generator and verify_chars: (bone that carries it, joint key).
CONTACT_POINTS = {"Heel": "Foot", "Ball": "Toes", "TipSole": "Toes"}


# ------------------------------------------------------------------------------------------------
# Godot BoneMap (identity SkeletonProfileHumanoid -> our names), ASSET_SPEC_V2 §2.9 / §7 (9)
# ------------------------------------------------------------------------------------------------
# SkeletonProfileHumanoid bone order (Godot 4.7.2); fingers, eyes, jaw and UpperChest stay unmapped.
PROFILE_HUMANOID = (
    ["Root", "Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "LeftEye", "RightEye", "Jaw"]
    + [s + b for s in ("Left",) for b in ("Shoulder", "UpperArm", "LowerArm", "Hand")]
    + ["Left" + f + k for f, ks in (("Thumb", ("Metacarpal", "Proximal", "Distal")),
                                    ("Index", ("Proximal", "Intermediate", "Distal")),
                                    ("Middle", ("Proximal", "Intermediate", "Distal")),
                                    ("Ring", ("Proximal", "Intermediate", "Distal")),
                                    ("Little", ("Proximal", "Intermediate", "Distal"))) for k in ks]
    + [s + b for s in ("Right",) for b in ("Shoulder", "UpperArm", "LowerArm", "Hand")]
    + ["Right" + f + k for f, ks in (("Thumb", ("Metacarpal", "Proximal", "Distal")),
                                     ("Index", ("Proximal", "Intermediate", "Distal")),
                                     ("Middle", ("Proximal", "Intermediate", "Distal")),
                                     ("Ring", ("Proximal", "Intermediate", "Distal")),
                                     ("Little", ("Proximal", "Intermediate", "Distal"))) for k in ks]
    + ["LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes", "RightUpperLeg", "RightLowerLeg", "RightFoot",
       "RightToes"])


def bonemap_tres_text():
    """Text of humanoid_bonemap.tres (same content Godot's ResourceSaver writes for the identity map; the
    PoC generated it with make_bonemap.gd). Every one of our 22 bones maps to the profile bone of the same
    name; the other profile bones map to nothing."""
    ours = set(BONE_NAMES)
    lines = ['[gd_resource type="BoneMap" format=3]', "",
             '[sub_resource type="SkeletonProfileHumanoid" id="SkeletonProfileHumanoid_ygixm"]', "",
             "[resource]", 'profile = SubResource("SkeletonProfileHumanoid_ygixm")']
    for b in PROFILE_HUMANOID:
        lines.append('bone_map/%s = &"%s"' % (b, b if b in ours else ""))
    return "\n".join(lines) + "\n"


def bonemap_mapping(text):
    import re
    return dict(re.findall(r'^bone_map/(\w+) = &"(\w*)"$', text, re.M))


def write_bonemap(path):
    """(Re)write the BoneMap only when its mapping differs (a uid the Godot editor may add is kept)."""
    from pathlib import Path
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    text = bonemap_tres_text()
    if (not path.exists() or bonemap_mapping(path.read_text()) != bonemap_mapping(text)
            or 'type="SkeletonProfileHumanoid"' not in path.read_text()):
        path.write_text(text)
    return path


def _roll(b):
    d = (b.tail - b.head).normalized()
    b.align_roll(Vector((0, -1, 0)) if abs(d.z) > 0.7 else Vector((0, 0, 1)))


def build_armature(p=None, name="Armature"):
    """Armature object (T-pose rest, facing -Y) with the 22 profile bones + 5 sockets; pose bones use
    quaternions. The object sits at the origin with identity transform."""
    j = joints(p)
    arm = bpy.data.armatures.new(name)
    obj = bpy.data.objects.new(name, arm)
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    eb = arm.edit_bones
    for bname, parent, _req in HUMANOID_BONES:
        hk, tk = _HEAD_TAIL[bname]
        b = eb.new(bname)
        b.head = j[hk]
        b.tail = j[tk] if tk else j[hk] + Vector((0, 0, 0.10))
        _roll(b)
        if parent:
            b.parent = eb[parent]
            b.use_connect = False
        b.use_deform = bname != "Root"
    # hand sockets at the fist centre: bone Y = grip axis (toward the thumb = -Y in the T-pose),
    # bone Z = along the forearm toward the knuckles (= weapon -Y Blender / +Z Godot: blade, muzzle)
    for side, sx in (("Right", -1), ("Left", 1)):
        s = eb.new(side + "HandSocket")
        g = j[side + "Fist"]
        s.head = g
        s.tail = g + Vector((0, -0.10, 0))
        s.align_roll(Vector((sx, 0, 0)))
        s.parent = eb[side + "Hand"]
        s.use_deform = False
    for sname in ("BackSocket", "HipSocketR", "HeadSocket"):
        s = eb.new(sname)
        s.head = j[sname]
        s.tail = j[sname] + Vector((0, 0, 0.10))
        _roll(s)
        s.parent = eb[SOCKETS[sname]]
        s.use_deform = False
    bpy.ops.object.mode_set(mode='OBJECT')
    for pb in obj.pose.bones:
        pb.rotation_mode = 'QUATERNION'
    obj["rig"] = "humanoid_v2"
    return obj


# ------------------------------------------------------------------------------------------------
# rigid skinning
# ------------------------------------------------------------------------------------------------
def frame(axis):
    """(axis, up-ish, side) orthonormal frame for chamfered tubes."""
    a = Vector(axis).normalized()
    ref = Vector((0, 0, 1)) if abs(a.z) < 0.9 else Vector((0, -1, 0))
    u = (ref - a * ref.dot(a)).normalized()
    w = a.cross(u).normalized()
    return a, u, w


def ring8(c, u, w, a, b, ch):
    ch = min(ch, a * 0.9, b * 0.9)
    pts2 = [(a, b - ch), (a - ch, b), (-a + ch, b), (-a, b - ch), (-a, -b + ch), (-a + ch, -b), (a - ch, -b),
            (a, -b + ch)]
    return [c + w * x + u * y for x, y in pts2]


def limb(mb, p0, p1, s0, s1, mat, ch=0.03, cuts=None):
    """Chamfered 8-sided tube from p0 to p1; s = (half-width across, half-height 'up') at each end.
    cuts: optional [(t, material)] splitting it into colour bands (t in 0..1)."""
    p0, p1 = Vector(p0), Vector(p1)
    _ax, u, w = frame(p1 - p0)
    ts = [0.0] + [c[0] for c in (cuts or [])] + [1.0]
    ms = [mat] + [c[1] for c in (cuts or [])]
    rings = []
    for t in ts:
        c = p0.lerp(p1, t)
        sa = s0[0] + (s1[0] - s0[0]) * t
        sb = s0[1] + (s1[1] - s0[1]) * t
        rings.append(ring8(c, u, w, sa, sb, ch))
    return mb.loft(rings, mat, side_mats=ms, cap_mats=(ms[0], ms[-1]))


def skin_rigid(parts, arm_obj, name="Body"):
    """Merge {bone: MeshBuilder} into one mesh `name` (palette_vcol + exceptions), every vertex weighted
    100 % to its bone, parented to `arm_obj` with an Armature modifier."""
    unknown = set(parts) - set(DEFORM_BONES)
    if unknown:
        raise KeyError("parts for non-deforming / unknown bones: %s" % sorted(unknown))
    merged = lp.MeshBuilder()
    owner = []
    for bone, mbp in parts.items():
        base = len(merged.verts)
        merged.extend(mbp)
        owner += [bone] * (len(merged.verts) - base)
    body = lp.to_object(merged, name, (0, 0, 0))
    groups = {bone: body.vertex_groups.new(name=bone) for bone in parts}
    by_bone = {}
    for vi, bone in enumerate(owner):
        by_bone.setdefault(bone, []).append(vi)
    for bone, idx in by_bone.items():
        groups[bone].add(idx, 1.0, 'REPLACE')
    body.parent = arm_obj
    body.matrix_parent_inverse.identity()
    mod = body.modifiers.new("Armature", 'ARMATURE')
    mod.object = arm_obj
    return body


# ------------------------------------------------------------------------------------------------
# checks (used by the self-test; verify_chars.py in M1 builds on them)
# ------------------------------------------------------------------------------------------------
def check_armature(arm_obj, p=None):
    problems = []
    bones = arm_obj.data.bones
    names = [b.name for b in bones]
    if sorted(names) != sorted(ALL_BONES):
        problems.append("bone set %s" % sorted(set(names) ^ set(ALL_BONES)))
        return problems
    for b in bones:
        want_parent = BONE_PARENTS.get(b.name, SOCKETS.get(b.name))
        got = b.parent.name if b.parent else None
        if got != want_parent:
            problems.append("%s parent %s != %s" % (b.name, got, want_parent))
        want_def = b.name in DEFORM_BONES
        if b.use_deform != want_def:
            problems.append("%s use_deform %s" % (b.name, b.use_deform))
    j = joints(p)

    def axis(bn):
        return bones[bn].matrix_local.to_3x3()

    def head(bn):
        return bones[bn].head_local
    for bn in ("Hips", "Spine", "Chest", "Neck", "Head", "LeftUpperArm", "RightUpperArm", "LeftUpperLeg",
               "LeftLowerLeg", "LeftFoot"):
        if (head(bn) - j[bn]).length > 1e-4:
            problems.append("%s head %s != %s" % (bn, tuple(head(bn)), tuple(j[bn])))
    # T-pose: arms along +-X, legs straight down; front -Y (toes ahead of the ankles); left side at +X
    if axis("LeftUpperArm").col[1].dot(Vector((1, 0, 0))) < 0.999:
        problems.append("LeftUpperArm not along +X")
    if axis("RightUpperArm").col[1].dot(Vector((-1, 0, 0))) < 0.999:
        problems.append("RightUpperArm not along -X")
    for bn in ("LeftUpperLeg", "LeftLowerLeg", "RightUpperLeg", "RightLowerLeg"):
        if axis(bn).col[1].dot(Vector((0, 0, -1))) < 0.995:
            problems.append("%s not straight down" % bn)
    if not head("LeftToes").y < head("LeftFoot").y:
        problems.append("toes not toward -Y")
    if not (head("LeftUpperLeg").x > 0 > head("RightUpperLeg").x):
        problems.append("left side not at +X")
    # deterministic roll: vertical bones have their Z axis toward -Y, horizontal ones toward +Z
    for b in bones:
        if b.name in ("LeftHandSocket", "RightHandSocket"):
            continue
        m = b.matrix_local.to_3x3()
        yv, zv = m.col[1], m.col[2]
        ref = Vector((0, -1, 0)) if abs(yv.z) > 0.7 else Vector((0, 0, 1))
        refp = (ref - yv * ref.dot(yv)).normalized()
        if zv.dot(refp) < 0.999:
            problems.append("%s roll" % b.name)
    s = axis("RightHandSocket")
    if s.col[1].dot(Vector((0, -1, 0))) < 0.999 or s.col[2].dot(Vector((-1, 0, 0))) < 0.999:
        problems.append("RightHandSocket axes (Y toward the thumb -Y, Z along the forearm -X)")
    for sn in ("BackSocket", "HipSocketR", "HeadSocket", "RightHandSocket", "LeftHandSocket"):
        key = sn if sn in j else sn.replace("HandSocket", "Fist")
        if (head(sn) - j[key]).length > 1e-4:
            problems.append("%s head" % sn)
    return problems


def check_rigid_skin(body, blend_pairs=()):
    """Every vertex: exactly one group, weight 1.0, group = a deforming bone. `blend_pairs` = bone pairs whose
    vertices may carry exactly these two influences summing to 1 (long continuous clothing, ASSET_SPEC_V2 §4.3:
    e.g. the parka skirt Hips + Left/RightUpperLeg, G1)."""
    problems = []
    gnames = {g.index: g.name for g in body.vertex_groups}
    bad = [g for g in gnames.values() if g not in DEFORM_BONES]
    if bad:
        problems.append("vertex groups for non-deforming bones %s" % bad)
    pairs = {frozenset(p) for p in blend_pairs}
    unweighted = multi = partial = 0
    for v in body.data.vertices:
        gs = [g for g in v.groups if g.weight > 0.0]
        if not gs:
            unweighted += 1
        elif len(gs) > 1:
            names = frozenset(gnames[g.group] for g in gs)
            if not (len(gs) == 2 and names in pairs and abs(sum(g.weight for g in gs) - 1.0) < 1e-4):
                multi += 1
        elif abs(gs[0].weight - 1.0) > 1e-6:
            partial += 1
    if unweighted or multi or partial:
        problems.append("skin: %d unweighted, %d multi-influence, %d partial" % (unweighted, multi, partial))
    return problems


def test_parts(p=None, mats=None):
    """A minimal clothed test humanoid, one MeshBuilder per deforming bone (self-test / examples)."""
    j = joints(p)
    M = dict(top="jacket", legs="hat", boots="boots", skin="skin", hands="scarf", eyes="eyes_dark")
    M.update(mats or {})
    parts = {}

    def mb(bone):
        return parts.setdefault(bone, lp.MeshBuilder())
    hip = j["Hips"].z
    limb(mb("Hips"), (0, 0, hip - 0.10), (0, 0, j["Spine"].z + 0.02), (0.18, 0.12), (0.19, 0.12), M["legs"], 0.04)
    limb(mb("Spine"), (0, 0, j["Spine"].z - 0.04), (0, 0, j["Chest"].z + 0.02), (0.25, 0.15), (0.25, 0.15),
         M["top"], 0.06)
    limb(mb("Chest"), (0, 0, j["Chest"].z - 0.02), (0, 0, j["Neck"].z), (0.25, 0.155), (0.20, 0.13), M["top"], 0.06)
    limb(mb("Neck"), j["Neck"], j["Head"], (0.055, 0.055), (0.05, 0.05), M["skin"], 0.015)
    hd = mb("Head")
    z0 = j["Head"].z - 0.02
    hd.box((-0.13, -0.12, z0), (0.13, 0.12, j["HeadTop"].z), M["skin"])
    for sx in (-1, 1):
        x = sx * 0.055
        hd.poly([(x - 0.02, -0.121, z0 + 0.10), (x + 0.02, -0.121, z0 + 0.10), (x + 0.02, -0.121, z0 + 0.14),
                 (x - 0.02, -0.121, z0 + 0.14)], M["eyes"], facing=(0, -1, 0))
    for sx, side in ((1, "Left"), (-1, "Right")):
        limb(mb(side + "Shoulder"), j[side + "Shoulder"], j[side + "UpperArm"], (0.10, 0.09), (0.09, 0.09),
             M["top"], 0.03)
        limb(mb(side + "UpperArm"), j[side + "UpperArm"], j[side + "LowerArm"], (0.08, 0.08), (0.07, 0.07),
             M["top"], 0.025)
        limb(mb(side + "LowerArm"), j[side + "LowerArm"], j[side + "Hand"], (0.07, 0.07), (0.065, 0.065),
             M["top"], 0.02)
        limb(mb(side + "Hand"), j[side + "Hand"], j[side + "HandTip"], (0.05, 0.055), (0.045, 0.045), M["hands"],
             0.015)
        limb(mb(side + "UpperLeg"), j[side + "UpperLeg"], j[side + "LowerLeg"], (0.09, 0.10), (0.08, 0.085),
             M["legs"], 0.03)
        limb(mb(side + "LowerLeg"), j[side + "LowerLeg"], j[side + "Foot"] + Vector((0, 0, 0.02)), (0.08, 0.085),
             (0.07, 0.075), M["legs"], 0.025, cuts=[(0.7, M["boots"])])
        ft = j[side + "Foot"]
        mb(side + "Foot").box((ft.x - 0.07, j[side + "Toes"].y, 0.0), (ft.x + 0.07, 0.10, 0.12), M["boots"])
        to = j[side + "Toes"]
        mb(side + "Toes").box((to.x - 0.065, j[side + "ToesTip"].y, 0.0), (to.x + 0.065, to.y - 0.002, 0.08),
                              M["boots"])
    return parts


def build_test_humanoid(p=None, name="Armature"):
    """Armature + rigid-skinned `Body` (in the current scene)."""
    arm = build_armature(p, name)
    body = skin_rigid(test_parts(p), arm)
    return arm, body


# ------------------------------------------------------------------------------------------------
# ASSET_SPEC_V2 §4.2 reference joints (1.80 m player), checked by the self-test
REFERENCE_JOINTS = {"Hips": (0, 0, 0.92), "Spine": (0, 0, 1.02), "Chest": (0, 0, 1.22), "Neck": (0, 0, 1.48),
                    "Head": (0, 0, 1.56), "HeadTop": (0, 0, 1.74), "LeftUpperArm": (0.20, 0, 1.44),
                    "RightUpperArm": (-0.20, 0, 1.44), "LeftLowerArm": (0.48, 0, 1.44), "LeftHand": (0.74, 0, 1.44),
                    "LeftHandTip": (0.82, 0, 1.44), "LeftUpperLeg": (0.11, 0, 0.92), "LeftLowerLeg": (0.11, 0, 0.50),
                    "RightUpperLeg": (-0.11, 0, 0.92), "BackSocket": (0, 0.14, 1.30), "HipSocketR": (-0.16, 0, 0.92),
                    "HeadSocket": (0, 0, 1.62)}


def selftest(verbose=True):
    import os
    import tempfile
    from . import export
    problems = []
    j = joints()
    for k, v in REFERENCE_JOINTS.items():
        if (j[k] - Vector(v)).length > 1e-6:
            problems.append("reference joint %s %s != %s" % (k, tuple(round(c, 4) for c in j[k]), v))
    if abs(j["LeftFoot"].z - 0.09) > 1e-6 or abs((j["LeftFoot"].y - j["LeftToes"].y) - 0.12) > 1e-6:
        problems.append("ankle z / toes offset")
    for side in ("Left", "Right"):
        for key in CONTACT_POINTS:
            if abs(j[side + key].z) > 1e-9 or abs(j[side + key].x - j[side + "Foot"].x) > 1e-9:
                problems.append("contact point %s%s not under the foot at z 0" % (side, key))
    import re
    bm = re.findall(r'^bone_map/(\w+) = &"(\w*)"$', bonemap_tres_text(), re.M)
    if len(bm) != 56 or sorted(v for _k, v in bm if v) != sorted(BONE_NAMES) or any(k != v for k, v in bm if v):
        problems.append("bonemap: %d profile bones, mapping not the identity of our 22 bones" % len(bm))
    for p in (params(), params(height=1.70, width=0.88, leg_len=1.06, arm_len=1.08, hunch=25.0),
              params(height=1.80 * 1.6, width=1.4)):
        lp.new_scene()
        arm, body = build_test_humanoid(p)
        pr = check_armature(arm, p) + check_rigid_skin(body)
        if pr:
            problems += ["params %s: %s" % (p, x) for x in pr]
    # export round trip of the reference rig (§2.8 options with an armature): 27 joints incl. sockets
    lp.new_scene()
    arm, body = build_test_humanoid()
    tmp = tempfile.mkdtemp(prefix="rig_selftest_")
    glb = os.path.join(tmp, "humanoid_test.glb")
    with export.quiet():
        export.export_gltf(glb)
    import json
    import struct
    data = open(glb, "rb").read()
    g = json.loads(data[20:20 + struct.unpack_from("<I", data, 12)[0]])
    skins = g.get("skins", [])
    joint_names = sorted(g["nodes"][i]["name"] for i in skins[0]["joints"]) if skins else []
    if sorted(n for n in ALL_BONES if n != "Root") != [n for n in joint_names if n != "Root"]:
        problems.append("exported skin joints %s" % joint_names)
    prims = [p for m in g["meshes"] for p in m["primitives"]]
    if not all("COLOR_0" in p["attributes"] and "JOINTS_0" in p["attributes"] for p in prims):
        problems.append("exported Body lacks COLOR_0/JOINTS_0")
    if len(prims) != 1:
        problems.append("Body has %d surfaces" % len(prims))
    tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
    if verbose:
        print("rig selftest: bones=%d (profile %d + sockets %d) required=%d tris=%d glb joints=%d -> %s" % (
            len(arm.data.bones), len(BONE_NAMES), len(SOCKETS), len(REQUIRED_PROFILE_BONES), tris,
            len(joint_names), "OK" if not problems else "FAIL"))
        for x in problems:
            print("  FAIL", x)
    return problems


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        sys.exit(1 if selftest() else 0)
    print(__doc__)
