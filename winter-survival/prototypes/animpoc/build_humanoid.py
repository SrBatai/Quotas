"""PoC: skeletal low-poly humanoid built 100 % by bpy (Blender 5.0.1 as a Python module).

- Reuses the VENTISCA helpers (lib/lowpoly.MeshBuilder + lib/palette) read-only from the repo.
- Armature with bone names == Godot SkeletonProfileHumanoid names (22 bones + 1 socket).
- Character faces Blender -Y  (= glTF +Z = Godot +Z = Vector3.MODEL_FRONT), T-pose rest, left = +X.
- Rigid skinning: every low-poly part is weighted 100 % to one bone (one skinned mesh "Body").
- Actions written by script (Blender 5.0 slotted actions), exported to one .glb (export_animation_mode=ACTIONS):
    Idle-loop, Walk-loop, Run-loop, ZombieShamble-loop  (cyclic generator: foot trajectory + analytic 2-bone IK)
    Attack                                               (key poses + Bezier interpolation)
usage: python3 build_humanoid.py            -> out/survivor.glb, out/zombie.glb (+ .blend)
"""
import math
import os
import sys
import time

REPO_BLENDER = "/home/user/Quotas/winter-survival/blender"
sys.path.insert(0, REPO_BLENDER)

import bpy  # noqa: E402
from mathutils import Matrix, Quaternion, Vector  # noqa: E402

from lib import lowpoly as lp  # noqa: E402
from lib import palette  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
FPS = 30

# PoC-only colours (in memory; the repo palette file is NOT modified)
palette.PALETTE.update({
    "zombie_skin": "#8E9C86", "zombie_shirt": "#51606E", "zombie_pants": "#5A4B3A",
    "blood": "#6B1F1F", "hair": "#2B2522",
})


# ----------------------------------------------------------------------------------------------
# character parameters
# ----------------------------------------------------------------------------------------------
SURVIVOR = dict(name="survivor", leg=1.0, torso=1.0, arm=1.0, width=1.0,
                mats=dict(top="jacket", top2="hat", legs="hat", boots="boots", hands="scarf", skin="skin",
                          scarf="scarf", hat="hat", pompom="snow", cuff="cloth"))
ZOMBIE = dict(name="zombie", leg=1.06, torso=1.02, arm=1.08, width=0.88,
              mats=dict(top="zombie_shirt", top2="blood", legs="zombie_pants", boots="boots", hands="zombie_skin",
                        skin="zombie_skin", scarf=None, hat="hair", pompom=None, cuff="zombie_pants"))


def joints(P):
    """World (Blender) joint positions of the T-pose. Left = +X, forward = -Y, up = +Z."""
    L, T, A, W = P["leg"], P["torso"], P["arm"], P["width"]
    ank = 0.09
    knee = ank + 0.41 * L
    hip = knee + 0.42 * L
    j = {}
    j["Root"] = Vector((0, 0, 0))
    j["Hips"] = Vector((0, 0, hip + 0.03))
    j["Spine"] = Vector((0, 0, hip + 0.10 * T))
    j["Chest"] = Vector((0, 0, hip + 0.26 * T))
    j["Neck"] = Vector((0, 0, hip + 0.52 * T))
    j["Head"] = Vector((0, 0, hip + 0.58 * T))
    j["HeadTop"] = Vector((0, 0, hip + 0.86 * T))
    sh_z = hip + 0.47 * T
    for s, side in ((1, "Left"), (-1, "Right")):
        j[side + "Shoulder"] = Vector((s * 0.05 * W, 0, sh_z))
        j[side + "UpperArm"] = Vector((s * 0.20 * W, 0, sh_z))
        j[side + "LowerArm"] = Vector((s * (0.20 * W + 0.29 * A), 0, sh_z))
        j[side + "Hand"] = Vector((s * (0.20 * W + 0.55 * A), 0, sh_z))
        j[side + "HandTip"] = Vector((s * (0.20 * W + 0.55 * A + 0.14), 0, sh_z))
        j[side + "UpperLeg"] = Vector((s * 0.11 * W, 0, hip))
        j[side + "LowerLeg"] = Vector((s * 0.11 * W, 0, knee))
        j[side + "Foot"] = Vector((s * 0.11 * W, 0.02, ank))
        j[side + "Toes"] = Vector((s * 0.11 * W, -0.12, 0.035))
        j[side + "ToesTip"] = Vector((s * 0.11 * W, -0.21, 0.035))
    return j


# ----------------------------------------------------------------------------------------------
# mesh parts (world coordinates, T-pose) -> {bone: MeshBuilder}
# ----------------------------------------------------------------------------------------------
def frame(axis):
    a = axis.normalized()
    ref = Vector((0, 0, 1)) if abs(a.z) < 0.9 else Vector((0, -1, 0))
    u = (ref - a * ref.dot(a)).normalized()   # 'up'-ish side
    w = a.cross(u).normalized()
    return a, u, w


def ring8(c, u, w, a, b, ch):
    ch = min(ch, a * 0.9, b * 0.9)
    pts2 = [(a, b - ch), (a - ch, b), (-a + ch, b), (-a, b - ch), (-a, -b + ch), (-a + ch, -b), (a - ch, -b),
            (a, -b + ch)]
    return [c + w * x + u * y for x, y in pts2]


def limb(mb, p0, p1, s0, s1, mat, ch=0.03, mats=None, cuts=None):
    """Chamfered tube from p0 to p1; s = (half-width across, half-height 'up') at each end.
    cuts: optional list of (t, material) to split into bands (t in 0..1)."""
    p0, p1 = Vector(p0), Vector(p1)
    ax, u, w = frame(p1 - p0)
    ts = [0.0] + [c[0] for c in (cuts or [])] + [1.0]
    ms = [mat] + [c[1] for c in (cuts or [])]
    rings = []
    for t in ts:
        c = p0.lerp(p1, t)
        sa = s0[0] + (s1[0] - s0[0]) * t
        sb = s0[1] + (s1[1] - s0[1]) * t
        rings.append(ring8(c, u, w, sa, sb, ch))
    mb.loft(rings, mat, side_mats=ms, cap_mats=(ms[0], ms[-1]))


def build_parts(P):
    j = joints(P)
    M = P["mats"]
    W = P["width"]
    parts = {}

    def mb(bone):
        parts.setdefault(bone, lp.MeshBuilder())
        return parts[bone]

    hip = j["LeftUpperLeg"].z
    # pelvis (pants) on Hips
    limb(mb("Hips"), (0, 0, hip - 0.10), (0, 0, j["Spine"].z + 0.02), (0.18 * W, 0.12), (0.19 * W, 0.12),
         M["legs"], ch=0.04)
    # lower torso on Spine: jacket hem .. waist
    limb(mb("Spine"), (0, 0, hip - 0.06), (0, 0, j["Chest"].z + 0.02), (0.26 * W, 0.16), (0.255 * W, 0.155),
         M["top"], ch=0.06, cuts=[(0.18, M["top"])])
    # chest on Chest: waist .. shoulders, rounded top
    ch_mb = mb("Chest")
    zc0, zc1 = j["Chest"].z - 0.02, j["Neck"].z - 0.02
    rings = [lp.rrect((0, 0, zc0), 0.255 * W, 0.155, 0.06), lp.rrect((0, 0, zc1 - 0.10), 0.25 * W, 0.155, 0.06),
             lp.rrect((0, 0, zc1 - 0.02), 0.22 * W, 0.14, 0.06), lp.rrect((0, 0, zc1 + 0.03), 0.13 * W, 0.10, 0.04)]
    ch_mb.loft(rings, M["top"])
    if M["scarf"]:
        ch_mb.loft([lp.rrect((0, 0, zc1 - 0.03), 0.15, 0.13, 0.05), lp.rrect((0, 0, zc1 + 0.07), 0.14, 0.12, 0.05)],
                   M["scarf"])
        ch_mb.hexa([(0.04, -0.157, zc0 + 0.12), (0.10, -0.157, zc0 + 0.13), (0.04, -0.185, zc0 + 0.12),
                    (0.10, -0.185, zc0 + 0.13), (0.03, -0.142, zc1 + 0.02), (0.09, -0.142, zc1 + 0.02),
                    (0.03, -0.172, zc1 + 0.02), (0.09, -0.172, zc1 + 0.02)], M["scarf"])
        ch_mb.box((-0.012, -0.168, zc0 + 0.02), (0.012, -0.152, zc1 - 0.06), M["top2"], skip=('+y',))  # zip
    else:  # zombie: torn shirt with blood patches
        ch_mb.box((-0.14 * W, -0.162, zc0 + 0.06), (0.02, -0.150, zc0 + 0.20), M["top2"], skip=('+y',))
        mb("Spine").box((0.06, -0.170, hip), (0.20 * W, -0.155, hip + 0.10), M["top2"], skip=('+y',))
    # neck
    limb(mb("Neck"), j["Neck"] + Vector((0, 0, -0.02)), j["Head"] + Vector((0, 0, 0.03)), (0.055, 0.055),
         (0.05, 0.05), M["skin"], ch=0.015)
    # head
    hd = mb("Head")
    z0 = j["Head"].z - 0.02
    hd.box((-0.14, -0.13, z0), (0.14, 0.13, z0 + 0.24), M["skin"])
    hd.box((-0.022, -0.165, z0 + 0.09), (0.022, -0.13, z0 + 0.135), M["skin"], skip=('+y',))  # nose
    for sx in (-1, 1):
        x = sx * 0.06
        hd.poly([(x - 0.02, -0.131, z0 + 0.14), (x + 0.02, -0.131, z0 + 0.14), (x + 0.02, -0.131, z0 + 0.18),
                 (x - 0.02, -0.131, z0 + 0.18)], "eyes_dark" if M["pompom"] else "eyes", facing=(0, -1, 0))
    if M["pompom"]:  # beanie
        hd.box((-0.165, -0.155, z0 + 0.20), (0.165, 0.155, z0 + 0.265), M["hat"])
        hd.tapered_box(z0 + 0.265, z0 + 0.34, (0.31, 0.29), (0.23, 0.21), M["hat"], skip=('-z',))
        hd.blob((0, 0, z0 + 0.37), 0.055, M["pompom"], subdiv=0, jitter=0.0)
    else:  # zombie: messy hair cap + jaw wound
        hd.tapered_box(z0 + 0.20, z0 + 0.28, (0.30, 0.28), (0.24, 0.22), M["hat"], skip=('-z',))
        hd.box((-0.07, -0.135, z0 + 0.03), (0.07, -0.128, z0 + 0.07), "blood", skip=('+y',))
    # arms (T-pose along +-X)
    for s, side in ((1, "Left"), (-1, "Right")):
        sh, ua, la, hn, tip = (j[side + k] for k in ("Shoulder", "UpperArm", "LowerArm", "Hand", "HandTip"))
        limb(mb(side + "Shoulder"), sh + Vector((s * 0.06, 0, -0.02)), ua + Vector((s * 0.05, 0, -0.01)),
             (0.12, 0.10), (0.10, 0.10), M["top"], ch=0.04)
        limb(mb(side + "UpperArm"), ua, la + Vector((s * 0.03, 0, 0)), (0.085, 0.085), (0.075, 0.075), M["top"],
             ch=0.03)
        limb(mb(side + "LowerArm"), la - Vector((s * 0.01, 0, 0)), hn + Vector((s * 0.01, 0, 0)), (0.075, 0.075),
             (0.068, 0.068), M["top"], ch=0.025, cuts=[(0.80, M["cuff"])])
        hmb = mb(side + "Hand")
        limb(hmb, hn, tip, (0.055, 0.06), (0.05, 0.05), M["hands"], ch=0.02)
        tb = hn + Vector((s * 0.04, -0.07, -0.01))
        hmb.cbox(tb, (0.05, 0.05, 0.045), M["hands"])  # thumb (forward, -Y)
        # legs
        ul, ll, ft, to, tt = (j[side + k] for k in ("UpperLeg", "LowerLeg", "Foot", "Toes", "ToesTip"))
        limb(mb(side + "UpperLeg"), ul + Vector((0, 0, 0.04)), ll - Vector((0, 0, 0.03)), (0.10 * W, 0.11),
             (0.085, 0.09), M["legs"], ch=0.03)
        limb(mb(side + "LowerLeg"), ll + Vector((0, 0, 0.02)), Vector((ll.x, 0.01, 0.08)), (0.085, 0.09),
             (0.08, 0.085), M["legs"], ch=0.025, cuts=[(0.60, M["boots"]), (0.64, M["cuff"]), (0.74, M["boots"])])
        fmb = mb(side + "Foot")
        fmb.box((ft.x - 0.075, -0.13, 0.0), (ft.x + 0.075, 0.10, 0.13), M["boots"])
        mb(side + "Toes").hexa([(to.x - 0.07, -0.21, 0.0), (to.x + 0.07, -0.21, 0.0), (to.x - 0.075, -0.125, 0.0),
                                (to.x + 0.075, -0.125, 0.0), (to.x - 0.065, -0.20, 0.07),
                                (to.x + 0.065, -0.20, 0.07), (to.x - 0.07, -0.125, 0.10),
                                (to.x + 0.07, -0.125, 0.10)], M["boots"])
    return parts


# ----------------------------------------------------------------------------------------------
# armature
# ----------------------------------------------------------------------------------------------
BONES = [  # name, parent, head key, tail key
    ("Root", None, "Root", None),
    ("Hips", "Root", "Hips", "Spine"),
    ("Spine", "Hips", "Spine", "Chest"),
    ("Chest", "Spine", "Chest", "Neck"),
    ("Neck", "Chest", "Neck", "Head"),
    ("Head", "Neck", "Head", "HeadTop"),
]
for _side in ("Left", "Right"):
    BONES += [(_side + "Shoulder", "Chest", _side + "Shoulder", _side + "UpperArm"),
              (_side + "UpperArm", _side + "Shoulder", _side + "UpperArm", _side + "LowerArm"),
              (_side + "LowerArm", _side + "UpperArm", _side + "LowerArm", _side + "Hand"),
              (_side + "Hand", _side + "LowerArm", _side + "Hand", _side + "HandTip"),
              (_side + "UpperLeg", "Hips", _side + "UpperLeg", _side + "LowerLeg"),
              (_side + "LowerLeg", _side + "UpperLeg", _side + "LowerLeg", _side + "Foot"),
              (_side + "Foot", _side + "LowerLeg", _side + "Foot", _side + "Toes"),
              (_side + "Toes", _side + "Foot", _side + "Toes", _side + "ToesTip")]


def build_armature(P):
    j = joints(P)
    arm = bpy.data.armatures.new("Armature")
    obj = bpy.data.objects.new("Armature", arm)
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    eb = arm.edit_bones
    for name, parent, hk, tk in BONES:
        b = eb.new(name)
        b.head = j[hk]
        b.tail = j[tk] if tk else j[hk] + Vector((0, 0, 0.10))
        # deterministic roll: bone Z axis toward character forward (-Y) for vertical bones; up for others
        ref = Vector((0, -1, 0)) if abs((b.tail - b.head).normalized().z) > 0.7 else Vector((0, 0, 1))
        b.align_roll(ref)
        if parent:
            b.parent = eb[parent]
            b.use_connect = False
        b.use_deform = name != "Root"
    # non-deforming weapon socket at the grip centre of the right mitten. Bone Y = grip axis (thumb side,
    # = weapon +Z Blender / +Y Godot), bone Z = along the forearm (= weapon -Y Blender / +Z Godot: blade, muzzle)
    s = eb.new("RightHandSocket")
    g = j["RightHand"] + Vector((-0.07, 0, 0))
    s.head = g
    s.tail = g + Vector((0, -0.10, 0))
    s.align_roll(Vector((-1, 0, 0)))
    s.parent = eb["RightHand"]
    s.use_deform = False
    bpy.ops.object.mode_set(mode='OBJECT')
    for pb in obj.pose.bones:
        pb.rotation_mode = 'QUATERNION'
    return obj


def build_body(P, arm_obj):
    parts = build_parts(P)
    merged = lp.MeshBuilder()
    owner = []  # bone per vertex
    for bone, mbp in parts.items():
        base = len(merged.verts)
        merged.extend(mbp)
        owner += [bone] * (len(merged.verts) - base)
    body = lp.to_object(merged, "Body", (0, 0, 0))
    for bone in parts:
        body.vertex_groups.new(name=bone)
    for vi, bone in enumerate(owner):
        body.vertex_groups[bone].add([vi], 1.0, 'REPLACE')
    body.parent = arm_obj
    mod = body.modifiers.new("Armature", 'ARMATURE')
    mod.object = arm_obj
    return body


# ----------------------------------------------------------------------------------------------
# animation helpers
# ----------------------------------------------------------------------------------------------
def q_axis(axis, deg):
    return Quaternion(Vector(axis), math.radians(deg))


def rest_q(arm_obj, bone):
    return arm_obj.data.bones[bone].matrix_local.to_quaternion()


def local_from_rest_frame(arm_obj, bone, q_arm):
    """Rotation expressed in the bone's T-pose (armature-space) frame -> pose-bone local quaternion."""
    r = rest_q(arm_obj, bone)
    return r.inverted() @ q_arm @ r


class ActionWriter:
    """Writes keys through pose bones (Blender 5.0 creates the slot + channelbag automatically)."""

    def __init__(self, arm_obj, name):
        self.obj = arm_obj
        self.act = bpy.data.actions.new(name)
        self.act.use_fake_user = True
        if arm_obj.animation_data is None:
            arm_obj.animation_data_create()
        arm_obj.animation_data.action = self.act
        self.prev = {}

    def rot(self, bone, q_arm, frame):
        pb = self.obj.pose.bones[bone]
        q = local_from_rest_frame(self.obj, bone, q_arm)
        if bone in self.prev:
            q.make_compatible(self.prev[bone])
        self.prev[bone] = q.copy()
        pb.rotation_quaternion = q
        pb.keyframe_insert("rotation_quaternion", frame=frame, group=bone)

    def loc(self, bone, offset_arm, frame):
        """Translation offset in armature space (converted to bone-local)."""
        pb = self.obj.pose.bones[bone]
        r = rest_q(self.obj, bone)
        pb.location = r.inverted() @ Vector(offset_arm)
        pb.keyframe_insert("location", frame=frame, group=bone)

    def finish(self, f0, f1, interpolation=None):
        self.act.use_frame_range = True
        self.act.frame_start = f0
        self.act.frame_end = f1
        if interpolation:
            from bpy_extras import anim_utils
            cb = anim_utils.action_get_channelbag_for_slot(self.act, self.act.slots[0])
            for fc in cb.fcurves:
                for kp in fc.keyframe_points:
                    kp.interpolation = interpolation
        return self.act


X, Y, Z = (1, 0, 0), (0, 1, 0), (0, 0, 1)


def arm_pose(side, lower_deg, swing_fwd_deg, elbow_deg, twist_deg=0.0):
    """Arm rotations in rest-frame (armature) space. lower: T-pose -> down; swing: forward (+) about X;
    elbow flexion (+) bends the forearm forward."""
    s = 1 if side == "Left" else -1
    q_lower = q_axis(Y, s * lower_deg)
    q_swing = q_axis(X, -swing_fwd_deg)
    q_twist = q_axis(Z, -s * twist_deg)
    ua = q_twist @ q_swing @ q_lower
    la = q_axis(Z, -s * elbow_deg)
    return ua, la


def leg_ik(hip, ankle, l1, l2):
    """Sagittal 2-bone IK. hip/ankle as (f, z) with f = forward. Returns (thigh_fwd_deg, knee_flex_deg)."""
    df, dz = ankle[0] - hip[0], ankle[1] - hip[1]
    d = min(math.hypot(df, dz), (l1 + l2) * 0.999)
    cos_k = (l1 * l1 + l2 * l2 - d * d) / (2 * l1 * l2)
    knee = math.pi - math.acos(max(-1.0, min(1.0, cos_k)))
    a_target = math.atan2(df, -dz)  # angle of hip->ankle from straight down, forward positive
    cos_a = (l1 * l1 + d * d - l2 * l2) / (2 * l1 * d)
    a_off = math.acos(max(-1.0, min(1.0, cos_a)))
    thigh = a_target + a_off  # knee in front of the line
    return math.degrees(thigh), math.degrees(knee)


def smooth(t):
    return t * t * (3 - 2 * t)


# ----------------------------------------------------------------------------------------------
# procedural actions
# ----------------------------------------------------------------------------------------------
def locomotion(arm_obj, P, name, speed, period, duty, lift, bob, drop, lean, arm_swing, elbow, arm_lower=78,
               limp=0.0, arms_forward=0.0, hunch=0.0, head_tilt=0.0, sway=0.01):
    """Cyclic in-place gait: feet follow a ground-locked stance trajectory (no sliding when the body
    moves at `speed`), swing = raised arc; legs solved by analytic IK; upper body counter-motion."""
    j = joints(P)
    l1 = (j["LeftUpperLeg"] - j["LeftLowerLeg"]).length
    l2 = (j["LeftLowerLeg"] - j["LeftFoot"]).length
    hip_rest = j["LeftUpperLeg"].z
    ankle_z = j["LeftFoot"].z
    ankle_f0 = -j["LeftFoot"].y  # ankle is 2 cm behind the hip in rest
    stance_len = speed * period * duty
    n = int(round(period * FPS))
    w = ActionWriter(arm_obj, name)
    for f in range(n + 1):
        t = f / n
        # pelvis: two dips per cycle (lowest shortly after each contact); limp adds an asymmetric dip
        dip = 0.5 - 0.5 * math.cos(4 * math.pi * (t - 0.08))
        hz = -drop - bob * dip - limp * 0.03 * max(0.0, math.sin(2 * math.pi * t))
        hx = sway * math.sin(2 * math.pi * t)
        w.loc("Hips", (hx, 0, hz), f)
        pelvis_yaw = 4.0 * math.sin(2 * math.pi * t) * (1 - limp * 0.5)
        w.rot("Hips", q_axis(Z, pelvis_yaw), f)
        for side, ph in (("Left", 0.0), ("Right", 0.5)):
            p = (t + ph) % 1.0
            drag = limp if side == "Right" else 0.0
            if p < duty:  # stance: ankle moves backward at `speed`
                u = p / duty
                fwd = stance_len * (0.5 - u)
                up = 0.0
                foot_pitch = -8.0 * (1 - smooth(min(1, u * 4))) + 25.0 * smooth(max(0.0, (u - 0.7) / 0.3))
            else:  # swing: arc forward
                u = (p - duty) / (1 - duty)
                fwd = stance_len * (-0.5 + smooth(u))
                up = lift * (1 - drag * 0.8) * math.sin(math.pi * u) ** 0.8
                foot_pitch = 25.0 * (1 - smooth(min(1, u * 2.5))) - 10.0 * smooth(max(0.0, (u - 0.6) / 0.4))
            hip_pt = (0.0, hip_rest + hz)
            ankle_pt = (fwd + ankle_f0, ankle_z + up)
            thigh, knee = leg_ik(hip_pt, ankle_pt, l1, l2)
            thigh_q = q_axis(X, -thigh)
            w.rot(side + "UpperLeg", thigh_q, f)
            w.rot(side + "LowerLeg", q_axis(X, knee), f)
            # foot: keep global pitch = foot_pitch (compensate thigh - knee chain)
            glob = -thigh + knee  # accumulated X rotation of the shin (deg, +X = toes down side)
            w.rot(side + "Foot", q_axis(X, foot_pitch - glob), f)
            w.rot(side + "Toes", q_axis(X, -max(0.0, foot_pitch - 5) * 0.8), f)
            # arms: opposite phase to the leg on the same side
            s = 1 if side == "Left" else -1
            sw = -arm_swing * math.sin(2 * math.pi * (t + ph)) * (1 - drag)
            ua, la = arm_pose(side, arm_lower, sw + arms_forward, elbow + abs(sw) * 0.25)
            w.rot(side + "UpperArm", ua, f)
            w.rot(side + "LowerArm", la, f)
            w.rot(side + "Shoulder", q_axis(Y, s * (3 + 2 * math.sin(4 * math.pi * t))), f)
            w.rot(side + "Hand", Quaternion(), f)
        twist = -6.0 * math.sin(2 * math.pi * t) * (1 - limp * 0.5)
        w.rot("Spine", q_axis(X, lean * 0.5 + hunch * 0.5) @ q_axis(Z, twist * 0.5), f)
        w.rot("Chest", q_axis(X, lean * 0.5 + hunch * 0.5 + 1.5 * math.sin(4 * math.pi * t)) @ q_axis(Z, twist), f)
        w.rot("Neck", q_axis(X, -lean * 0.5 - hunch * 0.2) @ q_axis(Y, head_tilt * 0.5), f)
        w.rot("Head", q_axis(X, -lean * 0.4 - hunch * 0.3) @ q_axis(Z, -twist * 1.2) @ q_axis(Y, head_tilt), f)
    return w.finish(0, n, 'LINEAR')


def plant_legs(w, P, f, hip_off, feet):
    """Solve both legs by IK. hip_off = (f, z) pelvis offset (forward, up); feet[side] = (ankle_fwd, ankle_up,
    foot_pitch_deg (+ = toes down))."""
    j = joints(P)
    l1 = (j["LeftUpperLeg"] - j["LeftLowerLeg"]).length
    l2 = (j["LeftLowerLeg"] - j["LeftFoot"]).length
    hip_rest = j["LeftUpperLeg"].z
    ankle_z = j["LeftFoot"].z
    a_f0 = -j["LeftFoot"].y
    for side, (af, az, pitch) in feet.items():
        thigh, knee = leg_ik((hip_off[0], hip_rest + hip_off[1]), (a_f0 + af, ankle_z + az), l1, l2)
        w.rot(side + "UpperLeg", q_axis(X, -thigh), f)
        w.rot(side + "LowerLeg", q_axis(X, knee), f)
        w.rot(side + "Foot", q_axis(X, pitch - (-thigh + knee)), f)
        w.rot(side + "Toes", q_axis(X, -max(0.0, pitch - 5) * 0.8), f)


def idle(arm_obj, P, name="Idle-loop", period=3.0):
    n = int(round(period * FPS))
    w = ActionWriter(arm_obj, name)
    for f in range(n + 1):
        t = f / n
        br = math.sin(2 * math.pi * t)          # breath
        sw = math.sin(2 * math.pi * t + 0.6)    # weight shift
        dz = -0.02 - 0.004 * br
        w.loc("Hips", (0.012 * sw, 0, dz), f)
        w.rot("Hips", q_axis(Y, 1.5 * sw), f)
        w.rot("Spine", q_axis(X, 2.0 - 1.0 * br) @ q_axis(Y, -1.0 * sw), f)
        w.rot("Chest", q_axis(X, -1.5 * br), f)
        w.rot("Neck", q_axis(X, 0.5 * br), f)
        w.rot("Head", q_axis(X, -2.0 + 1.0 * br) @ q_axis(Z, 3.0 * math.sin(2 * math.pi * t)), f)
        for side in ("Left", "Right"):
            s = 1 if side == "Left" else -1
            ua, la = arm_pose(side, 80 - 1.5 * br, 4 + 1.0 * br, 18 + 2 * br, twist_deg=-8)
            w.rot(side + "Shoulder", q_axis(Y, s * (2 + 1.5 * br)), f)
            w.rot(side + "UpperArm", ua, f)
            w.rot(side + "LowerArm", la, f)
            w.rot(side + "Hand", Quaternion(), f)
        plant_legs(w, P, f, (0.0, dz), {"Left": (0.03, 0.0, 0.0), "Right": (-0.02, 0.0, 0.0)})
    return w.finish(0, n, 'LINEAR')


def attack(arm_obj, P, name="Attack"):
    """One-shot overhead axe chop: key poses at given times (s), Bezier easing between keys (Blender default)."""
    def rest():
        ual, lal = arm_pose("Left", 80, 4, 18, -8)
        uar, lar = arm_pose("Right", 80, 4, 18, -8)
        return {"Hips": Quaternion(), "Spine": q_axis(X, 2), "Chest": Quaternion(), "Neck": Quaternion(),
                "Head": q_axis(X, -2), "LeftUpperArm": ual, "LeftLowerArm": lal, "RightUpperArm": uar,
                "RightLowerArm": lar, "RightHand": Quaternion(), "LeftHand": Quaternion(),
                "LeftShoulder": q_axis(Y, 2), "RightShoulder": q_axis(Y, -2)}

    def arm(side, swing, elbow, lower=80):
        ua, la = arm_pose(side, lower, swing, elbow)
        return {side + "UpperArm": ua, side + "LowerArm": la}

    rest_feet = {"Left": (0.03, 0.0, 0.0), "Right": (-0.02, 0.0, 0.0)}
    step_feet = {"Left": (0.24, 0.0, 0.0), "Right": (-0.16, 0.0, 0.0)}
    keys = [  # time, overrides, hip offset (fwd, up), feet
        (0.00, {}, (0.0, -0.02), rest_feet),
        (0.30, dict(Spine=q_axis(X, -8) @ q_axis(Z, -12), Chest=q_axis(X, -10) @ q_axis(Z, -15), Head=q_axis(X, 8),
                    RightHand=q_axis(Z, -40), Hips=q_axis(Z, -8), **arm("Right", 140, 100), **arm("Left", 55, 70)),
         (-0.03, -0.04), {"Left": (0.12, 0.05, 10.0), "Right": (-0.10, 0.0, 0.0)}),
        (0.42, dict(Spine=q_axis(X, 10) @ q_axis(Z, 8), Chest=q_axis(X, 12) @ q_axis(Z, 10), Head=q_axis(X, -8),
                    RightHand=q_axis(Z, -65), Hips=q_axis(Z, 6), **arm("Right", 78, 5), **arm("Left", 30, 35)),
         (0.05, -0.07), dict(step_feet, Right=(-0.16, 0.0, 15.0))),
        (0.55, dict(Spine=q_axis(X, 14) @ q_axis(Z, 10), Chest=q_axis(X, 14) @ q_axis(Z, 12), Head=q_axis(X, -10),
                    RightHand=q_axis(Z, -70), Hips=q_axis(Z, 8), **arm("Right", 58, 10), **arm("Left", 20, 30)),
         (0.06, -0.08), dict(step_feet, Right=(-0.16, 0.0, 18.0))),
        (0.90, {}, (0.0, -0.02), rest_feet),
    ]
    w = ActionWriter(arm_obj, name)
    for tm, over, hip, feet in keys:
        f = round(tm * FPS)
        pose = rest()
        pose.update(over)
        for b, q in pose.items():
            w.rot(b, q, f)
        w.loc("Hips", (0, -hip[0], hip[1]), f)
        plant_legs(w, P, f, hip, feet)
    return w.finish(0, round(0.90 * FPS))


# ----------------------------------------------------------------------------------------------
# build + export
# ----------------------------------------------------------------------------------------------
def to_vertex_colors(body):
    """Single-material variant: palette colour per face -> CORNER colour attribute, one white material.
    Result: 1 surface (1 draw call) instead of one per palette material."""
    me = body.data
    cols = [palette.hex_to_linear_rgba(palette.PALETTE[m.name]) for m in me.materials]
    attr = me.color_attributes.new("Color", 'FLOAT_COLOR', 'CORNER')
    data = [0.0] * (len(me.loops) * 4)
    for poly in me.polygons:
        c = cols[poly.material_index]
        for li in poly.loop_indices:
            data[li * 4:li * 4 + 4] = c
    attr.data.foreach_set("color", data)
    me.color_attributes.active_color = attr
    me.materials.clear()
    mat = bpy.data.materials.new("palette_vcol")
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    node = nt.nodes.new("ShaderNodeVertexColor")
    node.layer_name = "Color"
    nt.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.9
    me.materials.append(mat)
    me.polygons.foreach_set("material_index", [0] * len(me.polygons))


def export_glb(path, animations=True):
    kw = dict(filepath=path, export_format='GLB', export_yup=True, export_apply=False,
              export_animations=animations, export_animation_mode='ACTIONS', export_force_sampling=True,
              export_frame_step=1, export_optimize_animation_size=True, export_anim_single_armature=True,
              export_reset_pose_bones=True, export_rest_position_armature=True, export_def_bones=False,
              export_leaf_bone=False, export_skins=True, export_morph=False, export_materials='EXPORT',
              export_image_format='NONE', export_vertex_color='MATERIAL', export_all_vertex_colors=False, export_normals=True, export_texcoords=False, export_cameras=False,
              export_lights=False, export_extras=False, use_selection=False, use_visible=False)
    bpy.ops.export_scene.gltf(**kw)


def build(P, with_actions=True, vcol=False):
    lp.new_scene()
    bpy.context.scene.render.fps = FPS
    import addon_utils
    addon_utils.enable("io_scene_gltf2", default_set=True)
    arm_obj = build_armature(P)
    body = build_body(P, arm_obj)
    if vcol:
        to_vertex_colors(body)
        P = dict(P, name=P["name"] + "_vcol")
    acts = []
    if with_actions:
        acts.append(idle(arm_obj, P))
        acts.append(locomotion(arm_obj, P, "Walk-loop", speed=1.6, period=1.0, duty=0.62, lift=0.10, bob=0.025,
                               drop=0.035, lean=4.0, arm_swing=22.0, elbow=18.0))
        acts.append(locomotion(arm_obj, P, "Run_loop", speed=4.0, period=0.70, duty=0.38, lift=0.22, bob=0.05,
                               drop=0.08, lean=12.0, arm_swing=38.0, elbow=80.0, arm_lower=70))
        acts.append(locomotion(arm_obj, P, "ZombieShamble-loop", speed=0.8, period=1.6, duty=0.70, lift=0.06,
                               bob=0.03, drop=0.07, lean=6.0, arm_swing=6.0, elbow=25.0, limp=0.8,
                               arms_forward=62.0, hunch=26.0, head_tilt=18.0, sway=0.04))
        acts.append(attack(arm_obj, P))
        arm_obj.animation_data.action = None
        for pb in arm_obj.pose.bones:
            pb.rotation_quaternion = Quaternion()
            pb.location = Vector()
    os.makedirs(OUT, exist_ok=True)
    tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, P["name"] + ".blend"), compress=True)
    t0 = time.time()
    export_glb(os.path.join(OUT, P["name"] + ".glb"), animations=with_actions)
    print("BUILT %s: bones=%d tris=%d materials=%d actions=%s export=%.2fs" % (
        P["name"], len(arm_obj.data.bones), tris, len(body.data.materials),
        [(a.name, tuple(a.frame_range), len(a.slots)) for a in acts], time.time() - t0))


if __name__ == "__main__":
    build(SURVIVOR, with_actions=True)
    build(ZOMBIE, with_actions=False)
    build(SURVIVOR, with_actions=False, vcol=True)
