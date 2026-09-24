"""Script-generated animation for the v2 humanoid rig (ASSET_SPEC_V2 §6), extracted from
prototypes/animpoc/build_humanoid.py.

* ActionWriter: keys pose bones through their T-pose (armature-space) frame; Blender 5.0 slotted actions.
* locomotion(): cyclic in-place gait generator. The stance foot is ground-locked and moves backward at
  exactly `speed` (no sliding when the body moves at `speed`); swing = raised sin^0.8 arc; legs solved by
  analytic 2-bone IK; pelvis with two dips per cycle, torso counter-rotation, arms opposite to the legs.
  The LEFT foot is in contact at t = 0 (CYCLIC_MUTABLE sync). In place: `Root` never gets keys.
* keypose_action(): one-shot actions from key poses with Bezier easing (e.g. melee2h_swing()).
* Metrics (foot_metrics) and name rules (check_action_name) used by the self-test / verify_chars (M1).

Rotations are given in the rest frame (armature space) of each bone: +X = the character's left, +Y = its
back (it faces -Y), +Z = up. q_axis(X, +a) tips an upward bone (spine, neck) forward; a downward bone (leg)
swings forward with q_axis(X, -a); see arm_pose() / leg_ik() for the arm and leg conventions.

Not used by any asset yet (M1+). Self-test (in memory; a temporary .glb goes to the system temp dir):
    cd winter-survival/blender && python3 -m lib.anim --selftest
"""
import math
import re
import sys

import bpy
from mathutils import Quaternion, Vector

from . import rig

FPS = 30
X, Y, Z = (1, 0, 0), (0, 1, 0), (0, 0, 1)
SETS = ("Loco", "Crouch", "Melee1H", "Melee2H", "Spear", "Bow", "Pistol", "LongGun", "Throw", "Act", "Hit",
        "Down", "Death", "Veh", "Emote", "Zom", "Wolf", "Deer")
NAME_RE = re.compile(r"^(%s)_[A-Z][A-Za-z0-9]*(_[A-Za-z0-9]+)*(-loop)?$" % "|".join(SETS))


def check_action_name(name, looping):
    """`Set_Accion[_Variante][-loop]`; `-loop` exactly on cyclic actions. Returns a list of problems."""
    out = []
    if not NAME_RE.match(name):
        out.append("action name %r does not match Set_Action[_Variant][-loop]" % name)
    if looping != name.endswith("-loop"):
        out.append("action %r: -loop suffix %s" % (name, "missing" if looping else "on a one-shot"))
    return out


def q_axis(axis, deg):
    return Quaternion(Vector(axis), math.radians(deg))


def rest_q(arm_obj, bone):
    return arm_obj.data.bones[bone].matrix_local.to_quaternion()


def local_from_rest_frame(arm_obj, bone, q_arm):
    """Rotation expressed in the bone's T-pose (armature-space) frame -> pose-bone local quaternion."""
    r = rest_q(arm_obj, bone)
    return r.inverted() @ q_arm @ r


def smooth(t):
    return t * t * (3 - 2 * t)


class ActionWriter:
    """Writes keys through pose bones (Blender 5.0 creates the slot + channelbag automatically)."""

    def __init__(self, arm_obj, name):
        self.obj = arm_obj
        self.act = bpy.data.actions.new(name)
        if self.act.name != name:
            raise RuntimeError("action name collision %s -> %s" % (name, self.act.name))
        self.act.use_fake_user = True
        if arm_obj.animation_data is None:
            arm_obj.animation_data_create()
        arm_obj.animation_data.action = self.act
        self.prev = {}

    def rot(self, bone, q_arm, frame):
        if bone == "Root":
            raise ValueError("Root never gets keys (in-place animation)")
        pb = self.obj.pose.bones[bone]
        q = local_from_rest_frame(self.obj, bone, q_arm)
        if bone in self.prev:
            q.make_compatible(self.prev[bone])
        self.prev[bone] = q.copy()
        pb.rotation_quaternion = q
        pb.keyframe_insert("rotation_quaternion", frame=frame, group=bone)

    def loc(self, bone, offset_arm, frame):
        """Translation offset in armature space (converted to bone-local). Only `Hips` should move."""
        if bone == "Root":
            raise ValueError("Root never gets keys (in-place animation)")
        pb = self.obj.pose.bones[bone]
        r = rest_q(self.obj, bone)
        pb.location = r.inverted() @ Vector(offset_arm)
        pb.keyframe_insert("location", frame=frame, group=bone)

    def fcurves(self):
        from bpy_extras import anim_utils
        cb = anim_utils.action_get_channelbag_for_slot(self.act, self.act.slots[0])
        return list(cb.fcurves)

    def finish(self, f0, f1, interpolation=None):
        self.act.use_frame_range = True
        self.act.frame_start = f0
        self.act.frame_end = f1
        if interpolation:
            for fc in self.fcurves():
                for kp in fc.keyframe_points:
                    kp.interpolation = interpolation
        return self.act


def channelbag_fcurves(act):
    from bpy_extras import anim_utils
    if not len(act.slots):
        return []
    return list(anim_utils.action_get_channelbag_for_slot(act, act.slots[0]).fcurves)


def reset_pose(arm_obj):
    if arm_obj.animation_data:
        arm_obj.animation_data.action = None
    for pb in arm_obj.pose.bones:
        pb.rotation_quaternion = Quaternion()
        pb.location = Vector()


# ------------------------------------------------------------------------------------------------
# kinematics
# ------------------------------------------------------------------------------------------------
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
    """Sagittal 2-bone IK. hip/ankle as (f, z) with f = forward. Returns (thigh_fwd_deg, knee_flex_deg,
    reachable)."""
    df, dz = ankle[0] - hip[0], ankle[1] - hip[1]
    dist = math.hypot(df, dz)
    reachable = dist <= (l1 + l2) * 0.999
    d = min(dist, (l1 + l2) * 0.999)
    cos_k = (l1 * l1 + l2 * l2 - d * d) / (2 * l1 * l2)
    knee = math.pi - math.acos(max(-1.0, min(1.0, cos_k)))
    a_target = math.atan2(df, -dz)  # angle of hip->ankle from straight down, forward positive
    cos_a = (l1 * l1 + d * d - l2 * l2) / (2 * l1 * d)
    a_off = math.acos(max(-1.0, min(1.0, cos_a)))
    thigh = a_target + a_off  # knee in front of the line
    return math.degrees(thigh), math.degrees(knee), reachable


def max_stance_speed(p, period, duty, drop, bob=0.0):
    """Highest authored speed whose ground-locked stance the legs can still reach (IK not clamped) for a
    given cycle; useful to pick (speed, period) pairs. stance length = speed * period * duty."""
    j = rig.joints(p)
    l1, l2 = rig.leg_lengths(p)
    dz = (j["LeftUpperLeg"].z - drop - bob) - j["LeftFoot"].z
    reach = (l1 + l2) * 0.999
    if dz >= reach:
        return 0.0
    half = math.sqrt(reach * reach - dz * dz)
    # stance runs from +half(+f0) to -half(+f0); f0 = ankle offset behind the hip in the rest pose
    f0 = -j["LeftFoot"].y
    half = min(half - f0, half + f0)
    return 2.0 * half / (period * duty)


def plant_legs(w, p, f, hip_off, feet):
    """Solve both legs by IK. hip_off = (fwd, up) pelvis offset; feet[side] = (ankle_fwd, ankle_up,
    foot_pitch_deg (+ = toes down))."""
    j = rig.joints(p)
    l1, l2 = rig.leg_lengths(p)
    hip_rest = j["LeftUpperLeg"].z
    ankle_z = j["LeftFoot"].z
    a_f0 = -j["LeftFoot"].y
    for side, (af, az, pitch) in feet.items():
        thigh, knee, _ok = leg_ik((hip_off[0], hip_rest + hip_off[1]), (a_f0 + af, ankle_z + az), l1, l2)
        w.rot(side + "UpperLeg", q_axis(X, -thigh), f)
        w.rot(side + "LowerLeg", q_axis(X, knee), f)
        w.rot(side + "Foot", q_axis(X, pitch - (-thigh + knee)), f)
        w.rot(side + "Toes", q_axis(X, -max(0.0, pitch - 5) * 0.8), f)


# ------------------------------------------------------------------------------------------------
# generators
# ------------------------------------------------------------------------------------------------
def locomotion(arm_obj, p, name, speed, period, duty, lift, bob, drop, lean, arm_swing, elbow, arm_lower=78.0,
               limp=0.0, arms_forward=0.0, hunch=None, head_tilt=0.0, sway=0.01):
    """Cyclic in-place gait (see module docstring). `hunch` defaults to the rig parameter p["hunch"].
    Returns the action; action["ik_clamped_frames"] counts frames whose stance/swing target was out of reach
    (> 0 means the feet slide: lower the speed or the period)."""
    p = rig.params(**(p or {}))
    hunch = p["hunch"] if hunch is None else hunch
    lean = lean + p["lean"]
    j = rig.joints(p)
    l1, l2 = rig.leg_lengths(p)
    hip_rest = j["LeftUpperLeg"].z
    ankle_z = j["LeftFoot"].z
    ankle_f0 = -j["LeftFoot"].y  # the ankle sits slightly behind the hip in the rest pose
    stance_len = speed * period * duty
    n = int(round(period * FPS))
    w = ActionWriter(arm_obj, name)
    clamped = 0
    for f in range(n + 1):
        t = f / n
        # pelvis: two dips per cycle (lowest shortly after each contact); limp adds an asymmetric dip
        dip = 0.5 - 0.5 * math.cos(4 * math.pi * (t - 0.08))
        hz = -drop - bob * dip - limp * 0.03 * max(0.0, math.sin(2 * math.pi * t))
        hx = sway * math.sin(2 * math.pi * t)
        w.loc("Hips", (hx, 0, hz), f)
        pelvis_yaw = 4.0 * math.sin(2 * math.pi * t) * (1 - limp * 0.5)
        w.rot("Hips", q_axis(Z, pelvis_yaw), f)
        frame_clamped = False
        for side, ph in (("Left", 0.0), ("Right", 0.5)):
            u_ph = (t + ph) % 1.0
            drag = limp if side == "Right" else 0.0
            if u_ph < duty:  # stance: ankle moves backward at `speed`
                u = u_ph / duty
                fwd = stance_len * (0.5 - u)
                up = 0.0
                foot_pitch = -8.0 * (1 - smooth(min(1, u * 4))) + 25.0 * smooth(max(0.0, (u - 0.7) / 0.3))
            else:  # swing: arc forward
                u = (u_ph - duty) / (1 - duty)
                fwd = stance_len * (-0.5 + smooth(u))
                up = lift * (1 - drag * 0.8) * math.sin(math.pi * u) ** 0.8
                foot_pitch = 25.0 * (1 - smooth(min(1, u * 2.5))) - 10.0 * smooth(max(0.0, (u - 0.6) / 0.4))
            thigh, knee, ok = leg_ik((0.0, hip_rest + hz), (fwd + ankle_f0, ankle_z + up), l1, l2)
            frame_clamped = frame_clamped or not ok
            w.rot(side + "UpperLeg", q_axis(X, -thigh), f)
            w.rot(side + "LowerLeg", q_axis(X, knee), f)
            glob = -thigh + knee  # accumulated X rotation of the shin
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
        clamped += frame_clamped
        twist = -6.0 * math.sin(2 * math.pi * t) * (1 - limp * 0.5)
        w.rot("Spine", q_axis(X, lean * 0.5 + hunch * 0.5) @ q_axis(Z, twist * 0.5), f)
        w.rot("Chest", q_axis(X, lean * 0.5 + hunch * 0.5 + 1.5 * math.sin(4 * math.pi * t)) @ q_axis(Z, twist), f)
        w.rot("Neck", q_axis(X, -lean * 0.5 - hunch * 0.2) @ q_axis(Y, head_tilt * 0.5), f)
        w.rot("Head", q_axis(X, -lean * 0.4 - hunch * 0.3) @ q_axis(Z, -twist * 1.2) @ q_axis(Y, head_tilt), f)
    act = w.finish(0, n, 'LINEAR')
    act["authored_speed"] = speed
    act["ik_clamped_frames"] = clamped
    return act


def idle(arm_obj, p, name="Loco_Idle-loop", period=3.0):
    """Breathing / weight-shift idle (cyclic)."""
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
        plant_legs(w, p, f, (0.0, dz), {"Left": (0.03, 0.0, 0.0), "Right": (-0.02, 0.0, 0.0)})
    return w.finish(0, n, 'LINEAR')


def rest_pose():
    """Relaxed standing pose (arms down) as {bone: rest-frame quaternion}."""
    ual, lal = arm_pose("Left", 80, 4, 18, -8)
    uar, lar = arm_pose("Right", 80, 4, 18, -8)
    return {"Hips": Quaternion(), "Spine": q_axis(X, 2), "Chest": Quaternion(), "Neck": Quaternion(),
            "Head": q_axis(X, -2), "LeftUpperArm": ual, "LeftLowerArm": lal, "RightUpperArm": uar,
            "RightLowerArm": lar, "RightHand": Quaternion(), "LeftHand": Quaternion(),
            "LeftShoulder": q_axis(Y, 2), "RightShoulder": q_axis(Y, -2)}


def keypose_action(arm_obj, p, name, keys, base=None):
    """One-shot action from key poses. keys = [(time_s, {bone: rest-frame quaternion}, hip (fwd, up) or None,
    feet {side: (fwd, up, pitch)} or None)]; every key starts from `base` (default rest_pose()).
    Interpolation between keys: Blender's default Bezier (ease in/out)."""
    base = base or rest_pose()
    w = ActionWriter(arm_obj, name)
    last = 0
    for tm, over, hip, feet in keys:
        f = int(round(tm * FPS))
        pose = dict(base)
        pose.update(over)
        for b, q in pose.items():
            w.rot(b, q, f)
        if hip is not None:
            w.loc("Hips", (0, -hip[0], hip[1]), f)
            plant_legs(w, p, f, hip, feet or {"Left": (0.03, 0.0, 0.0), "Right": (-0.02, 0.0, 0.0)})
        last = max(last, f)
    return w.finish(0, last)


def arm(side, swing, elbow, lower=80):
    ua, la = arm_pose(side, lower, swing, elbow)
    return {side + "UpperArm": ua, side + "LowerArm": la}


def melee2h_swing(arm_obj, p, name="Melee2H_Swing_A"):
    """Overhead two-handed chop (the PoC 'Attack'): anticipation 0.30 s, impact 0.42-0.55 s, recover 0.90 s."""
    rest_feet = {"Left": (0.03, 0.0, 0.0), "Right": (-0.02, 0.0, 0.0)}
    step_feet = {"Left": (0.24, 0.0, 0.0), "Right": (-0.16, 0.0, 0.0)}
    keys = [
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
    return keypose_action(arm_obj, p, name, keys)


# ------------------------------------------------------------------------------------------------
# metrics
# ------------------------------------------------------------------------------------------------
def assign(arm_obj, act):
    if arm_obj.animation_data is None:
        arm_obj.animation_data_create()
    arm_obj.animation_data.action = act
    try:
        if arm_obj.animation_data.action_slot is None and len(act.slots):
            arm_obj.animation_data.action_slot = act.slots[0]
    except AttributeError:
        pass


def sample_bone_heads(arm_obj, act, bones):
    """{bone: [armature-space head per frame]} over the action's frame range."""
    assign(arm_obj, act)
    f0, f1 = int(act.frame_range[0]), int(act.frame_range[1])
    out = {b: [] for b in bones}
    sc = bpy.context.scene
    for f in range(f0, f1 + 1):
        sc.frame_set(f)
        for b in bones:
            out[b].append(arm_obj.pose.bones[b].head.copy())
    return out


def foot_metrics(arm_obj, act, speed=None, contact_tol=0.004):
    """Ankle min height and stance speed (mean |dy/dt| of an ankle while it is on the ground), plus the
    contact state of each foot at t = 0."""
    s = sample_bone_heads(arm_obj, act, ["LeftFoot", "RightFoot"])
    zmin = min(min(v.z for v in s[b]) for b in s)
    speeds = []
    for b, pts in s.items():
        for k in range(len(pts) - 1):
            if pts[k].z < zmin + contact_tol and pts[k + 1].z < zmin + contact_tol:
                speeds.append(abs(pts[k + 1].y - pts[k].y) * FPS)
    stance = sum(speeds) / len(speeds) if speeds else 0.0
    left0 = s["LeftFoot"][0].z < zmin + contact_tol
    right0 = s["RightFoot"][0].z < zmin + contact_tol
    return dict(ankle_min=zmin, stance_speed=stance, samples=len(speeds), left_contact_t0=left0,
                right_contact_t0=right0, authored=speed)


def loop_gap(arm_obj, act):
    """Largest difference (m) between first and last frame over all bone heads (0 for a perfect loop)."""
    s = sample_bone_heads(arm_obj, act, [b.name for b in arm_obj.pose.bones])
    return max((pts[0] - pts[-1]).length for pts in s.values())


# ------------------------------------------------------------------------------------------------
def selftest(verbose=True):
    import json
    import os
    import struct
    import tempfile
    from . import export
    from . import lowpoly as lp
    problems = []
    lp.new_scene()
    bpy.context.scene.render.fps = FPS
    p = rig.params()
    arm_obj, _body = rig.build_test_humanoid(p)
    # feasible test gaits (Loco_Walk at 3.0 m/s x 1.0 s needs a 3 m stride: see max_stance_speed)
    cases = [("Loco_Test_Walk-loop", dict(speed=1.6, period=1.0, duty=0.62, lift=0.10, bob=0.025, drop=0.035,
                                           lean=4.0, arm_swing=22.0, elbow=18.0)),
             ("Loco_Test_Run-loop", dict(speed=4.0, period=0.70, duty=0.38, lift=0.22, bob=0.05, drop=0.08,
                                          lean=12.0, arm_swing=38.0, elbow=80.0, arm_lower=70))]
    acts = []
    lines = []
    for name, kw in cases:
        act = locomotion(arm_obj, p, name, **kw)
        acts.append(act)
        problems += check_action_name(act.name, True)
        rot_curves = {fc.data_path for fc in channelbag_fcurves(act) if fc.data_path.endswith("rotation_quaternion")}
        if len(rot_curves) < 20:
            problems.append("%s: %d rotated bones (< 20)" % (name, len(rot_curves)))
        if any('"Root"' in fc.data_path for fc in channelbag_fcurves(act)):
            problems.append("%s: Root has keys" % name)
        if int(act.frame_range[1] - act.frame_range[0]) != int(round(kw["period"] * FPS)):
            problems.append("%s: frame range %s" % (name, tuple(act.frame_range)))
        m = foot_metrics(arm_obj, act, kw["speed"])
        gap = loop_gap(arm_obj, act)
        lines.append("%s ankle_min=%.3f stance=%.2f/%.2f m/s (%d samples) left_contact_t0=%s loop_gap=%.4f "
                     "ik_clamped=%d" % (name, m["ankle_min"], m["stance_speed"], kw["speed"], m["samples"],
                                        m["left_contact_t0"], gap, act["ik_clamped_frames"]))
        if m["ankle_min"] < 0.08:
            problems.append("%s: ankle min %.3f < 0.08" % (name, m["ankle_min"]))
        if abs(m["stance_speed"] - kw["speed"]) > 0.05 * kw["speed"]:
            problems.append("%s: stance speed %.2f vs %.2f" % (name, m["stance_speed"], kw["speed"]))
        if gap > 1e-3:
            problems.append("%s: not cyclic (gap %.4f m)" % (name, gap))
        # INFO only (PoC behaviour kept): with 0.83 m legs the ground-locked stance of these gaits is only
        # reachable mid-stance, so the ankle lifts at the stance extremes (ik_clamped > 0) and the left heel
        # hovers at t = 0. M1 (verify_chars) must fix this (heel-toe roll / cadence) before Loco_* ship.
    act = idle(arm_obj, p, "Loco_Test_Idle-loop")
    acts.append(act)
    if loop_gap(arm_obj, act) > 1e-3:
        problems.append("idle not cyclic")
    act = melee2h_swing(arm_obj, p, "Melee2H_Test_Swing")
    acts.append(act)
    problems += check_action_name(act.name, False)
    if int(act.frame_range[1]) != 27:
        problems.append("swing frame range %s" % tuple(act.frame_range))
    if not check_action_name("Walk-loop", True) or not check_action_name("Loco_Walk", True):
        problems.append("name rule accepted 'Walk-loop' or a loop without -loop")
    reset_pose(arm_obj)
    vmax = max_stance_speed(p, 1.0, 0.62, 0.035, 0.025)
    # export with actions (§2.8): animations named like the actions
    tmp = tempfile.mkdtemp(prefix="anim_selftest_")
    glb = os.path.join(tmp, "humanoid_anim_test.glb")
    with export.quiet():
        export.export_gltf(glb)
    data = open(glb, "rb").read()
    g = json.loads(data[20:20 + struct.unpack_from("<I", data, 12)[0]])
    names = sorted(a_["name"] for a_ in g.get("animations", []))
    if names != sorted(a_.name for a_ in acts):
        problems.append("exported animations %s" % names)
    if verbose:
        for ln in lines:
            print("anim selftest:", ln)
        print("anim selftest: max ground-locked walk speed at period 1.0 s / duty 0.62 = %.2f m/s" % vmax)
        print("anim selftest: exported animations %s -> %s" % (names, "OK" if not problems else "FAIL"))
        for x in problems:
            print("  FAIL", x)
    return problems


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        sys.exit(1 if selftest() else 0)
    print(__doc__)
