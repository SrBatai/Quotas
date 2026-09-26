"""Key-pose clips, asymmetric gaits and ground handling for the v2 humanoid rig (ASSET_SPEC_V2 §6, milestone M4).

Built on lib/anim.py (Pose FK, ActionWriter, two-bone IK, heel-toe gait internals). Used by
anims/build_zombie_anims.py (Zom_*) and anims/build_combat.py (Melee*, Act_*, Hit_*, Down_*, Death_A).

Clip model (`Clip`)
* A key = full pose at time t: FK rotations `rel` (anim.Pose convention: armature axes, relative to the parent's
  delta) merged over the clip's base pose, a Hips offset, optional planted FEET (IK), optional HAND grips (IK with
  the hand-socket frame: `shaft` = the weapon's +Z Blender / handle axis, `edge` = its -Y Blender / business end),
  `ground=True` (the lowest body point is put exactly on z = 0: lying / kneeling keys) and `two_hand=True` (the left
  hand rides the right hand's weapon shaft).
* Every key is resolved to a complete pose; in-between frames slerp the resolved rotations (arcs, not straight
  lines: good swings) with a per-segment easing (`lin`, `ease`, `in`, `in3`, `out`, `out3`, `sine`), then re-apply
  the constraints that must hold at every frame: planted feet (targets interpolated, stepping feet lift in an arc),
  the two-handed grip, and the ground (a body point under z = 0 lifts the Hips).
* `post(t, pose)` adds procedural layers (breathing, tremor, head twitches) before the constraints.
* Loops: the last key equals the first (`Clip.close()`); additive clips use base = identity (T-pose deltas).
Every frame is keyed (LINEAR), like the locomotion generator; Root never moves, only Hips translates.

Asymmetric gait (`gait_cycle`): the lib.anim heel-toe generator with per-side overrides (lift, heel / toe angles,
duty, phase offset: limps, dragged feet) and an upper-body callback (zombie arms / heads, bloated waddle). Stance
contact points still move backward at exactly `speed`, so the foot metrics of verify_chars.py hold.

Hand contacts (`hand_contact_defs`, crawls): palm point of each hand (Hand head + 0.06 m along the hand).
"""
import math

from mathutils import Quaternion, Vector

from . import anim
from . import rig
from .anim import X, Y, Z, Pose, q_axis

FPS = anim.FPS

# ------------------------------------------------------------------------------------------------
# easing
# ------------------------------------------------------------------------------------------------
EASE = {
    "lin": lambda u: u,
    "ease": lambda u: u * u * (3 - 2 * u),
    "sine": lambda u: 0.5 - 0.5 * math.cos(math.pi * u),
    "in": lambda u: u * u,
    "in3": lambda u: u * u * u,
    "out": lambda u: 1 - (1 - u) * (1 - u),
    "out3": lambda u: 1 - (1 - u) ** 3,
}


def slerp(a, b, u):
    b = b.copy()
    if a.dot(b) < 0:
        b.negate()
    return a.slerp(b, u)


# ------------------------------------------------------------------------------------------------
# body points used for the ground constraint (bone, rest point or None = head, radius)
# ------------------------------------------------------------------------------------------------
def body_points(p=None):
    j = rig.joints(p)
    s = rig.params(**(p or {}))["height"] / rig.REFERENCE_HEIGHT
    pts = [("Hips", None, 0.12), ("Hips", j["Hips"] + Vector((0, 0.06, -0.06)), 0.10),
           ("Spine", None, 0.13), ("Chest", None, 0.13), ("Chest", (j["Chest"] + j["Neck"]) * 0.5, 0.13),
           ("Neck", None, 0.06), ("Head", j["Head"] + Vector((0, 0, 0.08 * s)), 0.11),
           ("Head", j["Head"] + Vector((0, -0.05, 0.02)) * s, 0.07)]
    for side in anim.SIDES:
        pts += [(side + "UpperArm", None, 0.07), (side + "LowerArm", None, 0.055), (side + "Hand", None, 0.045),
                (side + "Hand", j[side + "HandTip"], 0.03),
                (side + "UpperLeg", None, 0.09), (side + "LowerLeg", None, 0.065),
                (side + "LowerLeg", (j[side + "LowerLeg"] + j[side + "Foot"]) * 0.5, 0.06),
                (side + "Foot", None, 0.055), (side + "Foot", j[side + "Heel"] + Vector((0, 0, 0.03)), 0.03),
                (side + "Toes", j[side + "TipSole"] + Vector((0, 0, 0.03)), 0.03)]
    return pts


def lowest(pose, pts, skip=()):
    """Lowest z of the body surface (points minus radius); `skip` = bone-name prefixes to ignore."""
    lo = 9.0
    for bone, pr, r in pts:
        if skip and bone.startswith(skip):
            continue
        q = pose.head(bone) if pr is None else pose.point(bone, pr)
        lo = min(lo, q.z - r)
    return lo


# ------------------------------------------------------------------------------------------------
# hand-socket frames (rig.build_armature): socket Y = toward the thumb, Z = along the forearm to the knuckles
# ------------------------------------------------------------------------------------------------
SOCKET_REST = {"Right": (Vector((0, -1, 0)), Vector((-1, 0, 0))), "Left": (Vector((0, -1, 0)), Vector((1, 0, 0)))}


def grip_rotation(side, shaft, edge):
    """Armature-space hand delta rotation that turns the hand socket so its Y = `shaft` (weapon handle axis,
    +Z Blender of the weapon) and its Z = `edge` (weapon -Y Blender: blade edge / business end)."""
    ry, rz = SOCKET_REST[side]
    return anim.aim_q(ry, rz, Vector(shaft), Vector(edge))


def fist_offset(pose, side):
    """Rest vector Hand head -> fist centre (the socket head)."""
    return pose.rest[side + "HandSocket"] - pose.rest[side + "Hand"]


def socket_frame(pose, side):
    """(grip centre, shaft axis, edge axis) of a hand socket in the current pose (armature space)."""
    w = pose.world(side + "Hand")
    ry, rz = SOCKET_REST[side]
    grip = pose.head(side + "Hand") + w @ fist_offset(pose, side)
    return grip, w @ ry, w @ rz


def place_grip(pose, side, grip, shaft, edge, pole):
    """IK the arm so the fist centre sits at `grip` with the socket frame (shaft, edge). Returns clamped."""
    R = grip_rotation(side, shaft, edge)
    wrist = Vector(grip) - R @ fist_offset(pose, side)
    return anim.solve_arm(pose, side, wrist, Vector(pole), hand_w=R)


def default_pole(side):
    s = 1 if side == "Left" else -1
    return Vector((s * 0.5, 0.35, -1.0))


# ------------------------------------------------------------------------------------------------
# feet
# ------------------------------------------------------------------------------------------------
def foot_target(pose, side, spec):
    """spec: dict(dx, dy, yaw, lift, heel) -> (ankle, foot_w, toes_w). dy > 0 = behind the rest spot (like
    anim.planted_foot), dx = outward; heel = degrees the heel is raised (pivot on the ball, toes flat)."""
    dx, dy = spec.get("dx", 0.0), spec.get("dy", 0.0)
    yaw, lift, heel = spec.get("yaw", 0.0), spec.get("lift", 0.0), spec.get("heel", 0.0)
    ankle, q = anim.planted_foot(pose, side, dy, dx, yaw)
    toes = q.copy()
    if heel:
        s = 1 if side == "Left" else -1
        ball = pose.j[side + "Heel"] + Vector((s * dx, dy, 0)) + q @ (pose.rest[side + "Toes"] - pose.j[side + "Heel"])
        qf = q @ q_axis(X, heel)
        ankle = ball + qf @ (pose.rest[side + "Foot"] - pose.rest[side + "Toes"])
        return ankle + Vector((0, 0, lift)), qf, toes
    return ankle + Vector((0, 0, lift)), q, toes


def lerp_foot(a, b, u):
    out = {k: a.get(k, 0.0) + (b.get(k, 0.0) - a.get(k, 0.0)) * u for k in set(a) | set(b)}
    d = math.hypot(b.get("dx", 0.0) - a.get("dx", 0.0), b.get("dy", 0.0) - a.get("dy", 0.0))
    if d > 0.03:
        out["lift"] = out.get("lift", 0.0) + min(0.12, 0.35 * d) * math.sin(math.pi * u)
    return out


# ------------------------------------------------------------------------------------------------
# clip
# ------------------------------------------------------------------------------------------------
class Key:
    def __init__(self, t, rel, hips, feet, hands, ease, ground, two_hand, support):
        self.t, self.rel, self.hips, self.feet, self.hands = t, rel, hips, feet, hands
        self.ease, self.ground, self.two_hand, self.support = ease, ground, two_hand, support
        self.pose = None


class Clip:
    """One-shot or looping key-pose clip (module docstring)."""

    def __init__(self, p=None, base=None, post=None, support=0.09):
        self.p = rig.params(**(p or {}))
        self.base = dict(base) if base is not None else anim.rest_pose()
        self.keys = []
        self.post = post
        self.pts = body_points(self.p)
        self.support = support          # left-hand distance below the right hand along the shaft (two_hand)
        self.clamped = 0

    def key(self, t, rel=None, hips=(0.0, 0.0, 0.0), feet=None, hands=None, ease="ease", ground=False,
            two_hand=False, support=None):
        self.keys.append(Key(t, dict(rel or {}), Vector(hips), feet, hands, ease, ground, two_hand,
                             self.support if support is None else support))
        return self

    def close(self, t, ease="ease"):
        """Loop: a last key at `t` equal to the first."""
        k = self.keys[0]
        self.keys.append(Key(t, dict(k.rel), k.hips.copy(), k.feet, k.hands, ease, k.ground, k.two_hand, k.support))
        return self

    # -- resolution ---------------------------------------------------------------------------------
    def _base_pose(self, rel, hips):
        pose = Pose(self.p)
        for b, q in self.base.items():
            pose.rel[b] = q.copy()
        for b, q in rel.items():
            pose.rel[b] = q.copy()
        pose.hips = hips.copy()
        return pose

    def _feet(self, pose, feet):
        for side, spec in (feet or {}).items():
            if spec is None:
                continue
            ankle, fw, tw = foot_target(pose, side, spec)
            self.clamped += anim.solve_leg(pose, side, ankle, fw, tw, pole=fw @ Vector((0, -1, 0)))

    def _hands(self, pose, hands, two_hand, support):
        for side, spec in (hands or {}).items():
            if spec is None:
                continue
            if "grip" in spec:
                place_grip(pose, side, spec["grip"], spec["shaft"], spec["edge"], spec.get("pole", default_pole(side)))
            else:
                anim.solve_arm(pose, side, Vector(spec["pos"]), Vector(spec.get("pole", default_pole(side))),
                               hand_w=spec.get("rot"))
        if two_hand:
            grip, shaft, edge = socket_frame(pose, "Right")
            place_grip(pose, "Left", grip - shaft * support, shaft, edge, Vector((0.6, 0.2, -1.0)))

    def _settle(self, pose, feet, exact):
        skip = tuple(s + k for s in (feet or {}) if (feet or {}).get(s) is not None
                     for k in ("UpperLeg", "LowerLeg", "Foot", "Toes"))
        lo = lowest(pose, self.pts, skip)
        if exact or lo < 0.0:
            pose.hips.z -= lo
            return True
        return False

    def _resolve(self, k):
        pose = self._base_pose(k.rel, k.hips)
        self._hands(pose, k.hands, k.two_hand, k.support)
        self._feet(pose, k.feet)
        if k.ground:
            self._settle(pose, k.feet, True)
            self._feet(pose, k.feet)
        k.pose = pose
        k.hips = pose.hips.copy()

    def pose_at(self, t):
        keys = self.keys
        if t <= keys[0].t:
            k0 = k1 = keys[0]
            u = 0.0
        elif t >= keys[-1].t:
            k0 = k1 = keys[-1]
            u = 0.0
        else:
            i = max(i for i in range(len(keys)) if keys[i].t <= t + 1e-9)
            k0, k1 = keys[i], keys[min(i + 1, len(keys) - 1)]
            span = max(1e-9, k1.t - k0.t)
            u = EASE[k1.ease]((t - k0.t) / span)
        pose = Pose(self.p)
        for b in rig.BONE_NAMES:
            pose.rel[b] = slerp(k0.pose.rel[b], k1.pose.rel[b], u)
        pose.hips = k0.pose.hips.lerp(k1.pose.hips, u)
        if self.post:
            self.post(t, pose)
        if k0.two_hand and k1.two_hand:
            self._hands(pose, None, True, k0.support + (k1.support - k0.support) * u)
        feet = {}
        for side in anim.SIDES:
            a = (k0.feet or {}).get(side)
            b = (k1.feet or {}).get(side)
            if a is not None and b is not None:
                feet[side] = lerp_foot(a, b, u)
        self._feet(pose, feet)
        if k0.ground or k1.ground:
            if self._settle(pose, feet, False):
                self._feet(pose, feet)
        return pose

    def write(self, arm_obj, name, length, looping=False):
        self.keys.sort(key=lambda k: k.t)
        if abs(self.keys[-1].t - length) > 1e-6:
            raise ValueError("%s: last key at %.3f, length %.3f" % (name, self.keys[-1].t, length))
        for k in self.keys:
            self._resolve(k)
        n = anim.frame_count(length)
        w = anim.ActionWriter(arm_obj, name)
        for f in range(n + 1):
            w.pose(self.pose_at(f / FPS), f)
        act = w.finish(0, n, 'LINEAR')
        act["authored_speed"] = 0.0
        act["period"] = length
        act["looping"] = looping
        act["ik_clamped_frames"] = self.clamped
        return act


def procedural(arm_obj, p, name, length, fn, looping=True):
    """Clip from a per-frame function fn(t_seconds, pose) -> feet dict {side: foot spec} or None (legs FK)."""
    p = rig.params(**(p or {}))
    n = anim.frame_count(length)
    w = anim.ActionWriter(arm_obj, name)
    clamped = 0
    for f in range(n + 1):
        pose = Pose(p)
        feet = fn(f / FPS, pose) or {}
        for side, spec in feet.items():
            if spec is None:
                continue
            ankle, fw, tw = foot_target(pose, side, spec)
            clamped += anim.solve_leg(pose, side, ankle, fw, tw, pole=fw @ Vector((0, -1, 0)))
        w.pose(pose, f)
    act = w.finish(0, n, 'LINEAR')
    act["authored_speed"] = 0.0
    act["period"] = length
    act["looping"] = looping
    act["ik_clamped_frames"] = clamped
    return act


# ------------------------------------------------------------------------------------------------
# asymmetric heel-toe gait (lib.anim internals with per-side parameters)
# ------------------------------------------------------------------------------------------------
PHASE = {"Left": 0.0, "Right": 0.5}


def side_params(g, sides):
    return {s: anim.gait_params(**dict(g, **(sides or {}).get(s, {}))) for s in anim.SIDES}


def _foot_at(gs, geo, side, t, fy0, dphase):
    g = gs[side]
    L = g["speed"] * g["period"] * g["duty"]
    ph = PHASE[side] + (dphase if side == "Right" else 0.0)
    u_ph = (t - ph) % 1.0
    if u_ph < g["duty"]:
        u = u_ph / g["duty"]
        y, z, pt, to = anim._stance(g, geo, u, fy0 + L * u)
        return y, z, pt, to, True
    v = (u_ph - g["duty"]) / (1 - g["duty"])
    y, z, pt, to = anim._swing(g, geo, v, fy0, L)
    return y, z, pt, to, False


def _hip_state(g, t, drop, limp_side, limp):
    off, q, yaw = anim._hip_state(dict(g, limp=0.0), t, drop)
    if limp:
        # the pelvis sinks while the bad leg carries the weight (its stance: phase 0 left / 0.5 right)
        ph = PHASE[limp_side]
        off.z -= limp * 0.045 * max(0.0, math.sin(2 * math.pi * (t - ph)) * 1.0)
        s = 1 if limp_side == "Left" else -1
        q = q @ q_axis(Y, -s * limp * 5.0 * max(0.0, math.sin(2 * math.pi * (t - ph))))
    return off, q, yaw


def _required_drop(p, gs, fy0, dphase, limp_side, limp, samples=240):
    rest = rig.rest_heads(p)
    geo = anim.foot_geometry(p)
    l1, l2 = rig.leg_lengths(p)
    need = -1.0
    g0 = gs["Left"]
    for i in range(samples):
        t = i / samples
        off, q, _ = _hip_state(g0, t, 0.0, limp_side, limp)
        for side in anim.SIDES:
            g = gs[side]
            R = g["reach"] * (l1 + l2)
            y, z, _, _, st = _foot_at(gs, geo, side, t, fy0, dphase)
            if not st:
                continue
            s = 1 if side == "Left" else -1
            hip = anim._hip_joint(rest, side, off, q)
            ax = rest[side + "Foot"].x + s * g["stance_width"]
            dxy2 = (hip.x - ax) ** 2 + (hip.y - y) ** 2
            if dxy2 >= R * R:
                return 9.0
            need = max(need, hip.z - (z + math.sqrt(R * R - dxy2)))
    return need


def plan_gait2(p, gs, dphase=0.0, limp_side="Right", limp=0.0):
    geo = anim.foot_geometry(p)
    L = max(gs[s]["speed"] * gs[s]["period"] * gs[s]["duty"] for s in anim.SIDES)
    c = geo["hy"] - (geo["ay"] - geo["hy"]) - 0.5 * L
    lo, hi = c - 0.5, c + 0.5
    gr = (math.sqrt(5) - 1) / 2
    f = lambda x: _required_drop(p, gs, x, dphase, limp_side, limp, 120)     # noqa: E731
    x1, x2 = hi - gr * (hi - lo), lo + gr * (hi - lo)
    f1, f2 = f(x1), f(x2)
    for _ in range(40):
        if f1 < f2:
            hi, x2, f2 = x2, x1, f1
            x1 = hi - gr * (hi - lo)
            f1 = f(x1)
        else:
            lo, x1, f1 = x1, x2, f2
            x2 = lo + gr * (hi - lo)
            f2 = f(x2)
    fy0 = 0.5 * (lo + hi)
    req = max(0.0, _required_drop(p, gs, fy0, dphase, limp_side, limp, 600))
    g = gs["Left"]
    drop = (req + g["drop_margin"]) if g["drop"] is None else g["drop"]
    drop += g["crouch"]
    return dict(fy0=fy0, drop=drop, required_drop=req)


def gait_cycle(arm_obj, p, name, gait, sides=None, dphase=0.0, limp_side="Right", limp=0.0, upper=None):
    """Cyclic in-place gait: anim.gait_pose() with per-side overrides `sides` = {side: {param: value}}, a phase
    offset of the right foot, a limp (pelvis sinks over the bad leg's stance) and `upper(t, pose, info)` that may
    rewrite the torso / arms / head after the legs are solved (info: yaw, stance flags). Returns the action with the
    same custom props as anim.locomotion()."""
    p = rig.params(**(p or {}))
    gs = side_params(gait, sides)
    g = gs["Left"]
    n = anim.frame_count(g["period"])
    plan = plan_gait2(p, gs, dphase, limp_side, limp)
    geo = anim.foot_geometry(p)
    w = anim.ActionWriter(arm_obj, name)
    clamped = 0
    for f in range(n + 1):
        t = f / n
        pose = Pose(p)
        hunch = pose.p["hunch"] if g["hunch"] is None else g["hunch"]
        lean = g["lean"] + pose.p["lean"]
        off, q_hips, yaw = _hip_state(g, t, plan["drop"], limp_side, limp)
        pose.hips = off
        pose.rel["Hips"] = q_hips
        tw = -yaw * g["twist"]
        breath = 1.5 * math.sin(4 * math.pi * t)
        pose.set_world("Spine", q_axis(Z, yaw + (tw - yaw) * 0.35) @ q_axis(X, 0.5 * (lean + hunch)))
        pose.set_world("Chest", q_axis(Z, tw) @ q_axis(X, lean + hunch + 0.3 * breath))
        pose.set_world("Neck", q_axis(Z, tw * 0.5) @ q_axis(X, 0.5 * (lean + hunch) + 0.5 * g["head_pitch"]))
        pose.set_world("Head", q_axis(Z, tw * g["head_follow"]) @ q_axis(X, g["head_pitch"]))
        info = {"yaw": yaw, "stance": {}, "t": t}
        for side in anim.SIDES:
            s = 1 if side == "Left" else -1
            gsd = gs[side]
            ph = PHASE[side] + (dphase if side == "Right" else 0.0)
            sw = -gsd["arm_swing"] * math.cos(2 * math.pi * (t - ph - gsd["arm_lag"]))
            el = gsd["elbow"] + gsd["elbow_swing"] * max(0.0, sw)
            ua, la = anim.arm_pose(side, gsd["arm_lower"], sw + gsd["arms_forward"], el, gsd["arm_twist"])
            pose.rel[side + "UpperArm"] = ua
            pose.rel[side + "LowerArm"] = la
            pose.rel[side + "Hand"] = Quaternion()
            pose.rel[side + "Shoulder"] = q_axis(Y, s * (-gsd["shrug"] + gsd["shoulder_bounce"] *
                                                          (0.5 + 0.5 * math.sin(4 * math.pi * t))))
        if upper:
            upper(t, pose, info)
        for side in anim.SIDES:
            s = 1 if side == "Left" else -1
            y, z, pitch, toes, st = _foot_at(gs, geo, side, t, plan["fy0"], dphase)
            info["stance"][side] = st
            ax = pose.rest[side + "Foot"].x + s * gs[side]["stance_width"]
            c = anim.solve_leg(pose, side, Vector((ax, y, z)), q_axis(X, pitch), q_axis(X, toes),
                               reach=gs[side]["reach"])
            clamped += bool(c and st)
        w.pose(pose, f)
    act = w.finish(0, n, 'LINEAR')
    act["authored_speed"] = g["speed"]
    act["period"] = g["period"]
    act["duty"] = g["duty"]
    act["drop"] = plan["drop"]
    act["required_drop"] = plan["required_drop"]
    act["stance_length"] = g["speed"] * g["period"] * g["duty"]
    act["ik_clamped_frames"] = clamped
    act["looping"] = True
    return act


# ------------------------------------------------------------------------------------------------
# hand contacts (crawls): palm point of each hand
# ------------------------------------------------------------------------------------------------
PALM = 0.06


def palm_rest(p, side):
    j = rig.joints(p)
    s = 1 if side == "Left" else -1
    return j[side + "Hand"] + Vector((s * PALM, 0, 0))


# ------------------------------------------------------------------------------------------------
# "alive" layer: every bone and the Hips position keep a tiny motion, so Godot's remove_immutable_tracks never drops a
# track (a missing track would blend toward the T-pose RESET in a deterministic AnimationTree)
# ------------------------------------------------------------------------------------------------
def alive(pose, t, length, amp=0.25, seed=0):
    """Tiny whole-cycle oscillation (amp degrees; integer cycles over `length`, so loops stay closed)."""
    u = t / length
    for i, b in enumerate(anim.KEYED_BONES):
        k = 1 + (i + seed) % 3
        ph = 0.37 * i + seed
        a = amp * math.sin(2 * math.pi * k * u + ph) - amp * math.sin(ph)
        pose.rel[b] = pose.rel[b] @ q_axis((X, Y, Z)[i % 3], a)
    pose.hips = pose.hips + Vector((0.0, 0.0, 0.0015 * (math.sin(2 * math.pi * u + seed) - math.sin(seed))))


def write_events(path, table):
    """Merge {clip: {event: seconds}} into data/anim_events.json (sorted, stable formatting)."""
    import json
    import os
    data = {}
    if os.path.exists(path):
        with open(path) as f:
            data = json.load(f)
    for k, v in table.items():
        data[k] = {e: round(float(x), 3) for e, x in sorted(v.items(), key=lambda kv: kv[1])}
    os.makedirs(os.path.dirname(path), exist_ok=True)
    text = "{\n" + ",\n".join('  "%s": %s' % (k, json.dumps(data[k])) for k in sorted(data)) + "\n}\n"
    old = open(path).read() if os.path.exists(path) else None
    if old != text:
        with open(path, "w") as f:
            f.write(text)
    return path
