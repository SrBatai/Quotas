"""Script-generated animation for the v2 humanoid rig (ASSET_SPEC_V2 §6). M1 production version of the PoC
generator (prototypes/animpoc/build_humanoid.py).

Model
* `Pose`: forward kinematics over rig.joints(). Each bone carries a rotation `rel[bone]` expressed in
  armature axes and relative to its parent's rotation (the "rest frame" convention of the PoC: the bone's
  armature-space rotation delta is world(parent) @ rel). `Pose.world()` / `Pose.set_world()` convert between
  armature-space deltas and `rel`; `Pose.head()` / `Pose.point()` give armature-space positions. Only `Hips`
  translates. `ActionWriter.pose()` keys a whole Pose (Root never gets keys: in place, no root motion).
* `two_bone()`: analytic 3D two-bone IK with a pole; `solve_leg()` / `solve_arm()` place a limb on a target
  and give every segment a deterministic twist (bend-plane frame mapping), so feet stay exactly where the
  generator puts them whatever the pelvis does (bob, sway, yaw, roll).

Locomotion (`locomotion()`, `plan_gait()`)
* Stance = heel-toe rocker: heel strike with the toes up (`heel_deg`), the foot rolls about the HEEL contact
  point until flat, stays flat, then rolls about the BALL (Toes joint, toes kept flat on the ground) up to
  `toe_deg` at toe-off. The ground-contact point is locked to the ground and moves backward at exactly
  `speed` (rig.CONTACT_POINTS: Heel on Foot, Ball/TipSole on Toes), so there is no sliding at any speed the
  legs can reach. The rocker lets the ankle travel ~0.1 m further than a flat foot would.
* The pelvis height follows the gait: walk = inverted pendulum (lowest in double support), run = spring
  (lowest at mid-stance). `drop=None` makes plan_gait() pick the smallest pelvis drop that keeps every
  stance frame inside `reach` x leg length (the knee never locks); the footprint is centred to minimise it.
* Swing = cubic Hermite (velocity partly matched to the stance at both ends: toe-off follow-through and a
  swing-leg retraction before heel strike) + an early-peaking lift; the foot pitches from toe-off to strike.
* Pelvis yaw / roll / lateral sway, torso counter-rotation, head stabilised in world, arms opposite to the
  legs (max excursion at heel strike). The LEFT heel strikes at t = 0 (CYCLIC_MUTABLE sync).

One-shots: `keypose_action()` (key poses, Bezier ease), e.g. `melee2h_swing()`. Standing loops:
`standing_cycle()` (upper body from a callback, feet planted by IK), `idle()`.

Metrics: `contact_metrics()` samples the evaluated armature: ankle min height, grounded contact points, their
horizontal speed (stance speed; sliding = deviation from `speed`), ground penetration, left contact at t = 0.
verify_chars.py measures the same thing on the exported .glb (what Godot plays).

Axes: Blender armature space, +X = the character's left, -Y = its front, +Z = up. q_axis(X, +a) tips an
upward bone forward and swings a downward bone backward (legs forward = q_axis(X, -a)); foot pitch
+a = toes down. arm_pose() documents the arm convention.

Self-test (in memory; a temporary .glb goes to the system temp dir):
    cd winter-survival/blender && python3 -m lib.anim --selftest
"""
import math
import re
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

from . import rig

FPS = 30
X, Y, Z = (1, 0, 0), (0, 1, 0), (0, 0, 1)
SETS = ("Loco", "Crouch", "Melee1H", "Melee2H", "Spear", "Bow", "Pistol", "LongGun", "Throw", "Act", "Hit",
        "Down", "Death", "Veh", "Emote", "Zom", "Wolf", "Deer")
NAME_RE = re.compile(r"^(%s)_[A-Z][A-Za-z0-9]*(_[A-Za-z0-9]+)*(-loop)?$" % "|".join(SETS))
GROUND_TOL = 0.005      # a contact point is on the ground below this height (m)
SIDES = ("Left", "Right")


def check_action_name(name, looping):
    """`Set_Accion[_Variante][-loop]`; `-loop` exactly on cyclic actions. Returns a list of problems."""
    out = []
    if not NAME_RE.match(name):
        out.append("action name %r does not match Set_Action[_Variant][-loop]" % name)
    if looping != name.endswith("-loop"):
        out.append("action %r: -loop suffix %s" % (name, "missing" if looping else "on a one-shot"))
    return out


# ------------------------------------------------------------------------------------------------
# small math
# ------------------------------------------------------------------------------------------------
def q_axis(axis, deg):
    return Quaternion(Vector(axis), math.radians(deg))


def smooth(t):
    t = min(1.0, max(0.0, t))
    return t * t * (3 - 2 * t)


def clamp01(t):
    return min(1.0, max(0.0, t))


def frame_count(period):
    """Frames of a cycle; the period must be a whole number of frames at FPS (loops stay exact)."""
    n = int(round(period * FPS))
    if abs(n - period * FPS) > 1e-6 or n < 2:
        raise ValueError("period %.4f s is not a whole number of frames at %d fps" % (period, FPS))
    return n


def basis_q(d, n):
    """Rotation of the orthonormal frame (x = d, y = n made orthogonal to d, z = d x n)."""
    d = Vector(d).normalized()
    n = Vector(n)
    n = (n - d * n.dot(d)).normalized()
    t = d.cross(n)
    return Matrix(((d.x, n.x, t.x), (d.y, n.y, t.y), (d.z, n.z, t.z))).to_quaternion()


def aim_q(rest_d, rest_n, new_d, new_n):
    """Rotation taking direction rest_d to new_d and the (orthogonalised) side rest_n to new_n."""
    return basis_q(new_d, new_n) @ basis_q(rest_d, rest_n).inverted()


def hermite(p0, p1, m0, m1, v):
    v2, v3 = v * v, v * v * v
    return ((2 * v3 - 3 * v2 + 1) * p0 + (v3 - 2 * v2 + v) * m0 + (-2 * v3 + 3 * v2) * p1 + (v3 - v2) * m1)


def rot_yz(vy, vz, deg):
    """(vy, vz) rotated about +X by `deg` (foot pitch: + = toes down)."""
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return vy * c - vz * s, vy * s + vz * c


# ------------------------------------------------------------------------------------------------
# pose (forward kinematics)
# ------------------------------------------------------------------------------------------------
PARENTS = dict(rig.BONE_PARENTS)
KEYED_BONES = [b for b in rig.BONE_NAMES if b != "Root"]     # 21 bones get rotation keys; Hips also location


class Pose:
    """Rotations `rel` (armature axes, relative to the parent's delta) + Hips offset; FK over rig.joints()."""

    def __init__(self, p=None):
        self.p = rig.params(**(p or {}))
        self.j = rig.joints(self.p)
        self.rest = rig.rest_heads(self.p)
        self.rel = {b: Quaternion() for b in rig.BONE_NAMES}
        self.hips = Vector((0.0, 0.0, 0.0))

    def copy(self):
        o = Pose.__new__(Pose)
        o.p, o.j, o.rest = self.p, self.j, self.rest
        o.rel = {b: q.copy() for b, q in self.rel.items()}
        o.hips = self.hips.copy()
        return o

    def world(self, bone):
        if bone is None or bone == "Root":
            return Quaternion()
        par = PARENTS.get(bone, rig.SOCKETS.get(bone))
        if bone in rig.SOCKETS:
            return self.world(par)
        return self.world(par) @ self.rel[bone]

    def set_world(self, bone, w):
        par = PARENTS.get(bone)
        self.rel[bone] = self.world(par).inverted() @ w

    def head(self, bone):
        if bone == "Root":
            return self.rest["Root"].copy()
        if bone == "Hips":
            return self.rest["Hips"] + self.hips
        par = PARENTS.get(bone, rig.SOCKETS.get(bone))
        return self.head(par) + self.world(par) @ (self.rest[bone] - self.rest[par])

    def point(self, bone, p_rest):
        """Armature-space position of a point attached to `bone` (given at rest, armature space)."""
        return self.head(bone) + self.world(bone) @ (Vector(p_rest) - self.rest[bone])


# ------------------------------------------------------------------------------------------------
# action writing
# ------------------------------------------------------------------------------------------------
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
        if self.act.name != name:
            raise RuntimeError("action name collision %s -> %s" % (name, self.act.name))
        self.act.use_fake_user = True
        if arm_obj.animation_data is None:
            arm_obj.animation_data_create()
        arm_obj.animation_data.action = self.act
        self.prev = {}
        self._rest = {b.name: b.matrix_local.to_quaternion() for b in arm_obj.data.bones}

    def rot(self, bone, q_arm, frame):
        if bone == "Root":
            raise ValueError("Root never gets keys (in-place animation)")
        pb = self.obj.pose.bones[bone]
        r = self._rest[bone]
        q = r.inverted() @ q_arm @ r
        if bone in self.prev:
            q.make_compatible(self.prev[bone])
        self.prev[bone] = q.copy()
        pb.rotation_quaternion = q
        pb.keyframe_insert("rotation_quaternion", frame=frame, group=bone)

    def loc(self, bone, offset_arm, frame):
        """Translation offset in armature space (converted to bone-local). Only `Hips` moves."""
        if bone != "Hips":
            raise ValueError("only Hips carries a position track (got %s)" % bone)
        pb = self.obj.pose.bones[bone]
        pb.location = self._rest[bone].inverted() @ Vector(offset_arm)
        pb.keyframe_insert("location", frame=frame, group=bone)

    def pose(self, pose, frame):
        for b in KEYED_BONES:
            self.rot(b, pose.rel[b], frame)
        self.loc("Hips", pose.hips, frame)

    def fcurves(self):
        return channelbag_fcurves(self.act)

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
# inverse kinematics
# ------------------------------------------------------------------------------------------------
def two_bone(root, target, l1, l2, pole, reach=0.999):
    """3D two-bone IK. Returns (mid joint, end joint, bend-plane normal, clamped). The chain bends toward
    `pole` (a direction); `clamped` = the target was out of reach (the end stops short, same direction)."""
    root, target, pole = Vector(root), Vector(target), Vector(pole)
    d = target - root
    dist = d.length
    u = d / dist if dist > 1e-9 else Vector((0, 0, -1))
    mx = reach * (l1 + l2)
    mn = abs(l1 - l2) + 1e-4
    clamped = dist > mx + 1e-9
    dc = min(max(dist, mn), mx)
    cos_a = (l1 * l1 + dc * dc - l2 * l2) / (2 * l1 * dc)
    a = math.acos(max(-1.0, min(1.0, cos_a)))
    v = pole - u * pole.dot(u)
    if v.length < 1e-6:
        v = Vector((0, -1, 0)) - u * (-u.y) if abs(u.y) < 0.9 else Vector((0, 0, 1)) - u * u.z
    v.normalize()
    mid = root + (u * math.cos(a) + v * math.sin(a)) * l1
    end = root + u * dc
    n = u.cross(v).normalized()
    return mid, end, n, clamped


def _chain_rest_normal(pose, a, c, pole):
    u = (pose.rest[c] - pose.rest[a]).normalized()
    v = Vector(pole) - u * Vector(pole).dot(u)
    return u.cross(v.normalized()).normalized()


def solve_leg(pose, side, ankle, foot_w, toes_w=None, pole=(0, -1, 0), reach=0.996):
    """Place the ankle (Foot head) at `ankle`; Foot / Toes get the armature-space rotations foot_w / toes_w
    (toes default: rigid with the foot). Returns True when the target was out of reach."""
    ul, ll, ft, to = (side + k for k in ("UpperLeg", "LowerLeg", "Foot", "Toes"))
    hip = pose.head(ul)
    l1 = (pose.rest[ll] - pose.rest[ul]).length
    l2 = (pose.rest[ft] - pose.rest[ll]).length
    rest_n = _chain_rest_normal(pose, ul, ft, (0, -1, 0))
    knee, end, n, clamped = two_bone(hip, ankle, l1, l2, pole, reach)
    pose.set_world(ul, aim_q(pose.rest[ll] - pose.rest[ul], rest_n, knee - hip, n))
    pose.set_world(ll, aim_q(pose.rest[ft] - pose.rest[ll], rest_n, end - knee, n))
    pose.set_world(ft, foot_w)
    pose.set_world(to, toes_w if toes_w is not None else foot_w)
    return clamped


def solve_arm(pose, side, hand, pole, hand_w=None, reach=0.999):
    """Place the wrist (Hand head) at `hand` with the elbow toward `pole`; hand rotation `hand_w`
    (armature space; default rigid with the forearm). Rest bend plane: elbow behind (+Y) in the T-pose."""
    ua, la, hn = (side + k for k in ("UpperArm", "LowerArm", "Hand"))
    sh = pose.head(ua)
    l1 = (pose.rest[la] - pose.rest[ua]).length
    l2 = (pose.rest[hn] - pose.rest[la]).length
    rest_n = _chain_rest_normal(pose, ua, hn, (0, 1, 0))
    elbow, end, n, clamped = two_bone(sh, hand, l1, l2, pole, reach)
    pose.set_world(ua, aim_q(pose.rest[la] - pose.rest[ua], rest_n, elbow - sh, n))
    w_la = aim_q(pose.rest[hn] - pose.rest[la], rest_n, end - elbow, n)
    pose.set_world(la, w_la)
    pose.set_world(hn, hand_w if hand_w is not None else w_la)
    return clamped


def arm_pose(side, lower_deg, swing_fwd_deg, elbow_deg, twist_deg=0.0):
    """FK arm rotations (rel, see Pose). lower: T-pose -> down; swing: forward (+) about X; elbow flexion (+)
    bends the forearm forward; twist (+) rolls the arm so the elbow points further back."""
    s = 1 if side == "Left" else -1
    q_lower = q_axis(Y, s * lower_deg)
    q_swing = q_axis(X, -swing_fwd_deg)
    q_twist = q_axis(Z, -s * twist_deg)
    ua = q_twist @ q_swing @ q_lower
    la = q_axis(Z, -s * elbow_deg)
    return ua, la


def arm(side, swing, elbow, lower=80):
    ua, la = arm_pose(side, lower, swing, elbow)
    return {side + "UpperArm": ua, side + "LowerArm": la}


def leg_ik(hip, ankle, l1, l2):
    """Sagittal 2-bone IK (kept for scripts that plan in 2D). hip/ankle as (f, z) with f = forward.
    Returns (thigh_fwd_deg, knee_flex_deg, reachable)."""
    df, dz = ankle[0] - hip[0], ankle[1] - hip[1]
    dist = math.hypot(df, dz)
    reachable = dist <= (l1 + l2) * 0.999
    d = min(dist, (l1 + l2) * 0.999)
    cos_k = (l1 * l1 + l2 * l2 - d * d) / (2 * l1 * l2)
    knee = math.pi - math.acos(max(-1.0, min(1.0, cos_k)))
    a_target = math.atan2(df, -dz)
    cos_a = (l1 * l1 + d * d - l2 * l2) / (2 * l1 * d)
    a_off = math.acos(max(-1.0, min(1.0, cos_a)))
    return math.degrees(a_target + a_off), math.degrees(knee), reachable


# ------------------------------------------------------------------------------------------------
# feet
# ------------------------------------------------------------------------------------------------
def foot_geometry(p=None):
    """Sagittal foot geometry (Blender y / z, same for both sides): ankle A, heel H, toes joint T."""
    j = rig.joints(p)
    return dict(ay=j["LeftFoot"].y, az=j["LeftFoot"].z, hy=j["LeftHeel"].y, ty=j["LeftToes"].y,
                tz=j["LeftToes"].z)


def planted_foot(pose, side, dy=0.0, dx=0.0, yaw_deg=0.0):
    """Ankle position and foot rotation of a flat foot planted `dy` behind / `dx` outward of its rest spot,
    turned `yaw_deg` toes-out (the heel point stays where a flat, unturned foot would put it + (dx, dy))."""
    s = 1 if side == "Left" else -1
    q = q_axis(Z, s * yaw_deg)
    heel_rest = pose.j[side + "Heel"]
    heel = heel_rest + Vector((s * dx, dy, 0.0))
    ankle = heel + q @ (pose.rest[side + "Foot"] - heel_rest)
    return ankle, q


# ------------------------------------------------------------------------------------------------
# locomotion generator
# ------------------------------------------------------------------------------------------------
GAIT_DEFAULTS = dict(
    speed=1.5, period=1.0, duty=0.6, style="walk",
    heel_deg=15.0, toe_deg=40.0, heel_frac=0.14, flat_end=0.55, toe_power=1.5,
    lift=0.10, lift_peak=0.38, swing_k0=0.35, swing_k1=0.55, swing_pitch_end=0.8, toe_relax=0.35,
    bob=0.03, drop=None, crouch=0.0, drop_margin=0.004, reach=0.996, stance_width=0.0,
    yaw=5.0, roll=2.0, sway=0.015, pelvis_pitch=0.0,
    lean=4.0, hunch=None, twist=1.0, head_pitch=0.0, head_follow=0.25,
    arm_swing=25.0, arm_lag=0.04, elbow=20.0, elbow_swing=0.35, arm_lower=76.0, arms_forward=0.0, arm_twist=0.0,
    shoulder_bounce=2.0, shrug=0.0, limp=0.0)


def gait_params(**kw):
    bad = set(kw) - set(GAIT_DEFAULTS)
    if bad:
        raise KeyError("unknown gait parameters %s" % sorted(bad))
    g = dict(GAIT_DEFAULTS)
    g.update(kw)
    if g["style"] not in ("walk", "run"):
        raise ValueError("style must be walk or run")
    if not 0.2 <= g["duty"] <= 0.8:
        raise ValueError("duty out of range")
    return g


def _hip_state(g, t, drop):
    """(Hips offset, Hips rel rotation) at cycle phase t for a total pelvis drop `drop` (+ bob)."""
    if g["style"] == "walk":   # inverted pendulum: lowest in double support (after each heel strike)
        t_low = 0.5 * (g["duty"] - 0.5)
        dip = 0.5 + 0.5 * math.cos(4 * math.pi * (t - t_low))
        t_mid = t_low + 0.25
    else:                      # spring: lowest at mid-stance
        dip = 0.5 + 0.5 * math.cos(4 * math.pi * (t - 0.5 * g["duty"]))
        t_mid = 0.5 * g["duty"]
    limp = g["limp"]
    hz = -drop - g["bob"] * dip - limp * 0.03 * max(0.0, math.sin(2 * math.pi * (t - 0.5)))
    hx = g["sway"] * math.sin(2 * math.pi * (t - t_mid + 0.25))          # toward the stance leg
    yaw = -g["yaw"] * math.cos(2 * math.pi * t) * (1 - 0.5 * limp)       # left hip forward at t = 0
    roll = -g["roll"] * math.sin(2 * math.pi * (t - t_mid + 0.25))        # swing-side hip drops
    q = q_axis(Z, yaw) @ q_axis(Y, roll) @ q_axis(X, g["pelvis_pitch"])
    return Vector((hx, 0.0, hz)), q, yaw


def _hip_joint(pose_rest, side, off, q):
    return pose_rest["Hips"] + off + q @ (pose_rest[side + "UpperLeg"] - pose_rest["Hips"])


def _stance(g, geo, u, fy):
    """Stance foot at stance fraction u with the flat-foot heel at fy: (ankle y, ankle z, pitch, toes pitch)."""
    ay, az, hy, ty, tz = geo["ay"], geo["az"], geo["hy"], geo["ty"], geo["tz"]
    uh, ub = g["heel_frac"], g["flat_end"]
    if u < uh and g["heel_deg"] > 0:              # heel rocker (toes up), pivot = heel contact point
        psi = -g["heel_deg"] * (1 - smooth(u / uh))
        vy, vz = rot_yz(ay - hy, az, psi)
        return fy + vy, vz, psi, psi
    if u <= ub or g["toe_deg"] <= 0:              # foot flat
        return fy + ay - hy, az, 0.0, 0.0
    w = (u - ub) / (1 - ub)                        # ball rocker (heel up), pivot = Toes joint, toes flat
    psi = g["toe_deg"] * w ** g["toe_power"]
    vy, vz = rot_yz(ay - ty, az - tz, psi)
    return fy + (ty - hy) + vy, tz + vz, psi, 0.0


def _swing(g, geo, v, fy0, L):
    """Swing foot at swing fraction v: from the toe-off state to the next heel strike."""
    Ts = g["duty"] * g["period"]
    Tw = (1 - g["duty"]) * g["period"]
    y1, z1, p1, _ = _stance(g, geo, 1.0, fy0 + L)
    y0, z0, p0, _ = _stance(g, geo, 0.0, fy0)
    e = 1e-4                                         # stance velocities (m per stance fraction -> m/s)
    ya, _, _, _ = _stance(g, geo, 1.0 - e, fy0 + L * (1 - e))
    yb, _, _, _ = _stance(g, geo, e, fy0 + L * e)
    v_off = (y1 - ya) / (e * Ts)
    v_on = (yb - y0) / (e * Ts)
    y = hermite(y1, y0, g["swing_k0"] * v_off * Tw, g["swing_k1"] * v_on * Tw, v)
    a = math.log(0.5) / math.log(g["lift_peak"])
    z = z1 + (z0 - z1) * v + g["lift"] * math.sin(math.pi * v ** a)
    k = smooth(v / g["swing_pitch_end"])
    pitch = p1 + (p0 - p1) * k
    toes = pitch - g["toe_deg"] * (1 - smooth(v / g["toe_relax"])) if g["toe_deg"] > 0 else pitch
    if v > g["toe_relax"]:
        toes = pitch
    return y, z, pitch, toes


def _foot_at(g, geo, side, t, fy0, L):
    """(ankle y, ankle z, foot pitch, toes pitch, in_stance) of `side` at cycle phase t."""
    ph = 0.0 if side == "Left" else 0.5
    u_ph = (t - ph) % 1.0
    if u_ph < g["duty"]:
        u = u_ph / g["duty"]
        y, z, pt, to = _stance(g, geo, u, fy0 + L * u)
        return y, z, pt, to, True
    v = (u_ph - g["duty"]) / (1 - g["duty"])
    y, z, pt, to = _swing(g, geo, v, fy0, L)
    return y, z, pt, to, False


def _required_drop(g, p, fy0, samples=240):
    rest = rig.rest_heads(p)
    geo = foot_geometry(p)
    l1, l2 = rig.leg_lengths(p)
    R = g["reach"] * (l1 + l2)
    L = g["speed"] * g["period"] * g["duty"]
    need = -1.0
    for i in range(samples):
        t = i / samples
        off, q, _ = _hip_state(g, t, 0.0)
        for side in SIDES:
            y, z, _, _, st = _foot_at(g, geo, side, t, fy0, L)
            if not st:
                continue
            s = 1 if side == "Left" else -1
            hip = _hip_joint(rest, side, off, q)
            ax = rest[side + "Foot"].x + s * g["stance_width"]
            dxy2 = (hip.x - ax) ** 2 + (hip.y - y) ** 2
            if dxy2 >= R * R:
                return 9.0
            need = max(need, hip.z - (z + math.sqrt(R * R - dxy2)))
    return need


def plan_gait(p, g):
    """Footprint (flat heel y at strike) and pelvis drop for gait `g`: the footprint minimising the drop
    that keeps every stance frame reachable. Returns dict(fy0, drop, required_drop, stance_length)."""
    L = g["speed"] * g["period"] * g["duty"]
    geo = foot_geometry(p)
    # golden-section search of fy0 around the centred stance
    c = geo["hy"] - (geo["ay"] - geo["hy"]) - 0.5 * L
    lo, hi = c - 0.5, c + 0.5
    gr = (math.sqrt(5) - 1) / 2
    x1, x2 = hi - gr * (hi - lo), lo + gr * (hi - lo)
    f1, f2 = _required_drop(g, p, x1, 120), _required_drop(g, p, x2, 120)
    for _ in range(40):
        if f1 < f2:
            hi, x2, f2 = x2, x1, f1
            x1 = hi - gr * (hi - lo)
            f1 = _required_drop(g, p, x1, 120)
        else:
            lo, x1, f1 = x1, x2, f2
            x2 = lo + gr * (hi - lo)
            f2 = _required_drop(g, p, x2, 120)
    fy0 = 0.5 * (lo + hi)
    req = max(0.0, _required_drop(g, p, fy0, 600))
    drop = (req + g["drop_margin"]) if g["drop"] is None else g["drop"]
    drop += g["crouch"]
    return dict(fy0=fy0, drop=drop, required_drop=req, stance_length=L)


def gait_pose(p, g, plan, t):
    """Full-body Pose of gait `g` at cycle phase t (0..1). Returns (pose, clamped_stance_legs)."""
    pose = Pose(p)
    geo = foot_geometry(p)
    L = plan["stance_length"]
    hunch = pose.p["hunch"] if g["hunch"] is None else g["hunch"]
    lean = g["lean"] + pose.p["lean"]
    off, q_hips, yaw = _hip_state(g, t, plan["drop"])
    pose.hips = off
    pose.rel["Hips"] = q_hips
    # torso: counter-rotation against the pelvis yaw, forward lean, head stabilised in world
    tw = -yaw * g["twist"]
    breath = 1.5 * math.sin(4 * math.pi * t)
    pose.set_world("Spine", q_axis(Z, yaw + (tw - yaw) * 0.35) @ q_axis(X, 0.5 * (lean + hunch)))
    pose.set_world("Chest", q_axis(Z, tw) @ q_axis(X, lean + hunch + 0.3 * breath))
    pose.set_world("Neck", q_axis(Z, tw * 0.5) @ q_axis(X, 0.5 * (lean + hunch) + 0.5 * g["head_pitch"]))
    pose.set_world("Head", q_axis(Z, tw * g["head_follow"]) @ q_axis(X, g["head_pitch"]))
    clamped = 0
    for side in SIDES:
        s = 1 if side == "Left" else -1
        ph = 0.0 if side == "Left" else 0.5
        y, z, pitch, toes, st = _foot_at(g, geo, side, t, plan["fy0"], L)
        ax = pose.rest[side + "Foot"].x + s * g["stance_width"]
        c = solve_leg(pose, side, Vector((ax, y, z)), q_axis(X, pitch), q_axis(X, toes), reach=g["reach"])
        clamped += bool(c and st)
        # arms: opposite to the leg on the same side, max excursion around heel strike
        drag = g["limp"] if side == "Right" else 0.0
        sw = -g["arm_swing"] * math.cos(2 * math.pi * (t - ph - g["arm_lag"])) * (1 - drag)
        el = g["elbow"] + g["elbow_swing"] * max(0.0, sw)
        ua, la = arm_pose(side, g["arm_lower"], sw + g["arms_forward"], el, g["arm_twist"])
        pose.rel[side + "UpperArm"] = ua
        pose.rel[side + "LowerArm"] = la
        pose.rel[side + "Hand"] = Quaternion()
        pose.rel[side + "Shoulder"] = q_axis(Y, s * (-g["shrug"] + g["shoulder_bounce"] *
                                                      (0.5 + 0.5 * math.sin(4 * math.pi * t))))
    return pose, clamped


def locomotion(arm_obj, p, name, **gait):
    """Cyclic in-place gait (module docstring). Returns the action with custom props: authored_speed,
    period, duty, drop, required_drop, stance_length, ik_clamped_frames (stance frames out of reach: must
    be 0 for a sliding-free cycle)."""
    p = rig.params(**(p or {}))
    g = gait_params(**gait)
    n = frame_count(g["period"])
    plan = plan_gait(p, g)
    w = ActionWriter(arm_obj, name)
    clamped = 0
    for f in range(n + 1):
        pose, c = gait_pose(p, g, plan, f / n)
        clamped += c
        w.pose(pose, f)
    act = w.finish(0, n, 'LINEAR')
    act["authored_speed"] = g["speed"]
    act["period"] = g["period"]
    act["duty"] = g["duty"]
    act["drop"] = plan["drop"]
    act["required_drop"] = plan["required_drop"]
    act["stance_length"] = plan["stance_length"]
    act["ik_clamped_frames"] = clamped
    return act


def max_stance_speed(p, period, duty, drop, bob=0.0, **gait):
    """Highest speed whose stance stays reachable with a fixed pelvis drop (bisection over plan_gait)."""
    lo, hi = 0.0, 12.0
    for _ in range(30):
        mid = 0.5 * (lo + hi)
        g = gait_params(speed=mid, period=period, duty=duty, bob=bob, **gait)
        if plan_gait(p, g)["required_drop"] <= drop:
            lo = mid
        else:
            hi = mid
    return lo


# ------------------------------------------------------------------------------------------------
# standing cycles and key poses
# ------------------------------------------------------------------------------------------------
def standing_cycle(arm_obj, p, name, period, body, looping=True):
    """Loop (or one-shot) with planted feet. body(t, pose) sets pose.hips / rel rotations of the upper body
    (arms by FK or solve_arm) and returns {side: (ankle, foot_w[, toes_w])} for the feet (see
    planted_foot()); the legs are solved by IK. t runs 0..1 over `period`."""
    p = rig.params(**(p or {}))
    n = frame_count(period)
    w = ActionWriter(arm_obj, name)
    clamped = 0
    for f in range(n + 1):
        pose = Pose(p)
        feet = body(f / n, pose)
        for side, spec in feet.items():
            ankle, fw = spec[0], spec[1]
            tw = spec[2] if len(spec) > 2 else None
            clamped += solve_leg(pose, side, ankle, fw, tw, pole=fw @ Vector((0, -1, 0)))
        w.pose(pose, f)
    act = w.finish(0, n, 'LINEAR')
    act["ik_clamped_frames"] = clamped
    act["authored_speed"] = 0.0
    act["period"] = period
    return act


def idle(arm_obj, p, name="Loco_Idle-loop", period=3.0):
    """Breathing / weight-shift idle (cyclic), feet planted."""
    def body(t, pose):
        br = math.sin(2 * math.pi * t)
        sw = math.sin(2 * math.pi * t + 0.6)
        pose.hips = Vector((0.012 * sw, 0, -0.02 - 0.004 * br))
        pose.rel["Hips"] = q_axis(Y, 1.5 * sw)
        pose.rel["Spine"] = q_axis(X, 2.0 - 1.0 * br) @ q_axis(Y, -1.0 * sw)
        pose.rel["Chest"] = q_axis(X, -1.5 * br)
        pose.rel["Neck"] = q_axis(X, 0.5 * br)
        pose.rel["Head"] = q_axis(X, -2.0 + 1.0 * br) @ q_axis(Z, 3.0 * math.sin(2 * math.pi * t))
        for side in SIDES:
            s = 1 if side == "Left" else -1
            ua, la = arm_pose(side, 76 - 1.5 * br, 4 + 1.0 * br, 18 + 2 * br, twist_deg=-8)
            pose.rel[side + "Shoulder"] = q_axis(Y, s * (2 + 1.5 * br))
            pose.rel[side + "UpperArm"] = ua
            pose.rel[side + "LowerArm"] = la
        return {"Left": planted_foot(pose, "Left", -0.03, 0.01, 6), "Right": planted_foot(pose, "Right", 0.02, 0.01, 6)}
    return standing_cycle(arm_obj, p, name, period, body)


def rest_pose():
    """Relaxed standing pose (arms down) as {bone: rel quaternion}."""
    ual, lal = arm_pose("Left", 80, 4, 18, -8)
    uar, lar = arm_pose("Right", 80, 4, 18, -8)
    return {"Hips": Quaternion(), "Spine": q_axis(X, 2), "Chest": Quaternion(), "Neck": Quaternion(),
            "Head": q_axis(X, -2), "LeftUpperArm": ual, "LeftLowerArm": lal, "RightUpperArm": uar,
            "RightLowerArm": lar, "RightHand": Quaternion(), "LeftHand": Quaternion(),
            "LeftShoulder": q_axis(Y, 2), "RightShoulder": q_axis(Y, -2)}


def keypose_action(arm_obj, p, name, keys, base=None):
    """One-shot action from key poses. keys = [(time_s, {bone: rel quaternion}, hip (fwd, up) or None,
    feet {side: (fwd, up, pitch)} or None)]; every key starts from `base` (default rest_pose()). Feet are
    planted by 3D IK relative to their rest spot (fwd = toward -Y). Interpolation: Bezier (ease in/out)."""
    base = base or rest_pose()
    p = rig.params(**(p or {}))
    w = ActionWriter(arm_obj, name)
    last = 0
    for tm, over, hip, feet in keys:
        f = int(round(tm * FPS))
        pose = Pose(p)
        for b, q in dict(base, **over).items():
            pose.rel[b] = q.copy()
        if hip is not None:
            pose.hips = Vector((0, -hip[0], hip[1]))
            feet = feet or {"Left": (0.03, 0.0, 0.0), "Right": (-0.02, 0.0, 0.0)}
            for side, (fw, up, pitch) in feet.items():
                ankle = pose.rest[side + "Foot"] + Vector((0, -fw, up))
                solve_leg(pose, side, ankle, q_axis(X, pitch), q_axis(X, min(pitch, 0.0)))
            w.pose(pose, f)
        else:
            for b in over:
                w.rot(b, pose.rel[b], f)
        last = max(last, f)
    return w.finish(0, last)


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
# metrics (evaluated armature)
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


def sample_points(arm_obj, act, points):
    """{key: [armature-space position per frame]} for points = {key: (bone, rest position)}; bone heads
    when the rest position is None."""
    assign(arm_obj, act)
    f0, f1 = int(act.frame_range[0]), int(act.frame_range[1])
    rest_inv = {b.name: b.matrix_local.inverted() for b in arm_obj.data.bones}
    out = {k: [] for k in points}
    sc = bpy.context.scene
    for f in range(f0, f1 + 1):
        sc.frame_set(f)
        for k, (bone, pr) in points.items():
            pb = arm_obj.pose.bones[bone]
            out[k].append(pb.head.copy() if pr is None else pb.matrix @ (rest_inv[bone] @ Vector(pr)))
    return out


def sample_bone_heads(arm_obj, act, bones):
    return sample_points(arm_obj, act, {b: (b, None) for b in bones})


def contact_point_defs(p=None):
    """{Side_Point: (bone, rest position)} for every sole contact point + the ankles."""
    j = rig.joints(p)
    out = {}
    for side in SIDES:
        out[side + "_Ankle"] = (side + "Foot", None)
        for key, bone in rig.CONTACT_POINTS.items():
            out[side + "_" + key] = (side + bone, j[side + key])
    return out


def contact_stats(tracks, speed, fps=FPS, ground_tol=GROUND_TOL):
    """Stance metrics from sampled contact-point tracks {Side_Point: [Vector per frame]} (last frame = first
    for loops). Grounded point pairs (z < tol on consecutive frames) must move backward (+Y) at `speed`."""
    ankles = [z for k, pts in tracks.items() if k.endswith("_Ankle") for z in (v.z for v in pts)]
    sole = [v.z for k, pts in tracks.items() if not k.endswith("_Ankle") for v in pts]
    vy, err, lat = [], 0.0, 0.0
    for k, pts in tracks.items():
        if k.endswith("_Ankle"):
            continue
        for a, b in zip(pts[:-1], pts[1:]):
            if a.z < ground_tol and b.z < ground_tol:
                v = (b - a) * fps
                vy.append(v.y)
                if speed is not None:
                    ref = max(speed, 0.05)
                    err = max(err, abs(v.y - speed) / ref)
                    lat = max(lat, abs(v.x) / ref)
    left0 = any(tracks["Left_" + k][0].z < ground_tol for k in rig.CONTACT_POINTS)
    right0 = any(tracks["Right_" + k][0].z < ground_tol for k in rig.CONTACT_POINTS)
    return dict(ankle_min=min(ankles), sole_min=min(sole), stance_speed=(sum(vy) / len(vy) if vy else 0.0),
                samples=len(vy), slide=err, lateral=lat, left_contact_t0=left0, right_contact_t0=right0,
                authored=speed)


def contact_metrics(arm_obj, act, speed=None, p=None):
    """contact_stats() of an action evaluated in Blender (speed defaults to act['authored_speed'])."""
    if speed is None:
        speed = act.get("authored_speed")
    return contact_stats(sample_points(arm_obj, act, contact_point_defs(p)), speed)


def foot_metrics(arm_obj, act, speed=None, contact_tol=0.004):
    """PoC-compatible summary (ankle_min, stance_speed, samples, left/right contact at t = 0)."""
    m = contact_metrics(arm_obj, act, speed)
    return dict(ankle_min=m["ankle_min"], stance_speed=m["stance_speed"], samples=m["samples"],
                left_contact_t0=m["left_contact_t0"], right_contact_t0=m["right_contact_t0"], authored=speed)


def loop_gap(arm_obj, act):
    """Largest difference (m) between first and last frame over all bone heads (0 for a perfect loop)."""
    s = sample_bone_heads(arm_obj, act, [b.name for b in arm_obj.pose.bones])
    return max((pts[0] - pts[-1]).length for pts in s.values())


def fk_error(arm_obj, act, poses):
    """Largest distance between Pose.head() predictions and Blender's evaluated heads (checks the writer)."""
    bones = [b for b in rig.BONE_NAMES if b != "Root"]
    s = sample_bone_heads(arm_obj, act, bones)
    return max((s[b][i] - pz.head(b)).length for i, pz in poses for b in bones)


# ------------------------------------------------------------------------------------------------
# M1 production gaits (ASSET_SPEC_V2 §6.2 + the M1 speed decision); anims/build_loco.py uses these
# ------------------------------------------------------------------------------------------------
LOCO_GAITS = {
    "Loco_Walk-loop": dict(speed=2.2, period=0.8, duty=0.58, style="walk", heel_deg=20.0, toe_deg=48.0,
                           heel_frac=0.14, flat_end=0.50, lift=0.11, bob=0.022, yaw=7.0, roll=2.5, sway=0.018,
                           lean=6.0, arm_swing=32.0, elbow=22.0, elbow_swing=0.5, arm_lower=74.0,
                           shoulder_bounce=2.5, head_pitch=3.0),
    "Loco_Run-loop": dict(speed=6.0, period=2.0 / 3.0, duty=0.26, style="run", heel_deg=6.0, toe_deg=55.0,
                          heel_frac=0.18, flat_end=0.40, toe_power=1.3, lift=0.22, lift_peak=0.42, bob=0.05,
                          swing_k0=0.25, swing_k1=0.5, yaw=9.0, roll=3.0, sway=0.012, pelvis_pitch=6.0,
                          lean=13.0, arm_swing=48.0, elbow=80.0, elbow_swing=0.3, arm_lower=70.0,
                          shoulder_bounce=3.0, head_pitch=4.0, twist=1.2),
    "Crouch_Walk-loop": dict(speed=1.3, period=1.0, duty=0.64, style="walk", heel_deg=12.0, toe_deg=35.0,
                             heel_frac=0.14, flat_end=0.55, lift=0.09, bob=0.015, drop=0.35, yaw=6.0, roll=2.0,
                             sway=0.02, pelvis_pitch=10.0, lean=24.0, arm_swing=18.0, elbow=45.0,
                             arm_lower=62.0, arms_forward=18.0, head_pitch=8.0, stance_width=0.02,
                             shoulder_bounce=1.5),
}


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
    acts = []
    lines = []
    # the production gaits: sliding-free at their authored speeds
    for name, kw in LOCO_GAITS.items():
        name = name.replace("_", "_Test_", 1)
        act = locomotion(arm_obj, p, name, **kw)
        acts.append(act)
        problems += check_action_name(act.name, True)
        rot_curves = {fc.data_path for fc in channelbag_fcurves(act) if fc.data_path.endswith("rotation_quaternion")}
        if len(rot_curves) < 20:
            problems.append("%s: %d rotated bones (< 20)" % (name, len(rot_curves)))
        if any('"Root"' in fc.data_path for fc in channelbag_fcurves(act)):
            problems.append("%s: Root has keys" % name)
        if int(act.frame_range[1] - act.frame_range[0]) != frame_count(kw["period"]):
            problems.append("%s: frame range %s" % (name, tuple(act.frame_range)))
        m = contact_metrics(arm_obj, act, kw["speed"], p)
        gap = loop_gap(arm_obj, act)
        lines.append("%s drop=%.3f ankle_min=%.3f sole_min=%+.4f stance=%.3f/%.2f m/s slide=%.2f%% (%d samples) "
                     "left_contact_t0=%s loop_gap=%.4f ik_clamped=%d" % (
                         name, act["drop"], m["ankle_min"], m["sole_min"], m["stance_speed"], kw["speed"],
                         100 * m["slide"], m["samples"], m["left_contact_t0"], gap, act["ik_clamped_frames"]))
        if m["ankle_min"] < 0.08:
            problems.append("%s: ankle min %.3f < 0.08" % (name, m["ankle_min"]))
        if m["sole_min"] < -0.005:
            problems.append("%s: sole under the ground (%.3f)" % (name, m["sole_min"]))
        if m["samples"] < 4 or m["slide"] > 0.05 or m["lateral"] > 0.05:
            problems.append("%s: stance speed %.3f vs %.2f (slide %.1f%%, lateral %.1f%%, %d samples)" % (
                name, m["stance_speed"], kw["speed"], 100 * m["slide"], 100 * m["lateral"], m["samples"]))
        if not m["left_contact_t0"]:
            problems.append("%s: left foot not on the ground at t = 0" % name)
        if act["ik_clamped_frames"]:
            problems.append("%s: %d stance frames out of reach" % (name, act["ik_clamped_frames"]))
        if gap > 1e-3:
            problems.append("%s: not cyclic (gap %.4f m)" % (name, gap))
    # FK model == Blender evaluation (the writer keys what Pose predicts)
    g = gait_params(**LOCO_GAITS["Loco_Walk-loop"])
    plan = plan_gait(p, g)
    n = frame_count(g["period"])
    err = fk_error(arm_obj, acts[0], [(f, gait_pose(p, g, plan, f / n)[0]) for f in (0, 5, 11, 17)])
    if err > 1e-4:
        problems.append("Pose FK differs from Blender by %.5f m" % err)
    act = idle(arm_obj, p, "Loco_Test_Idle-loop")
    acts.append(act)
    m = contact_metrics(arm_obj, act, 0.0, p)
    if loop_gap(arm_obj, act) > 1e-3 or m["slide"] * 0.05 > 0.005 or not m["left_contact_t0"]:
        problems.append("idle: not cyclic or feet moving (%.4f m/s)" % (m["slide"] * 0.05))
    act = melee2h_swing(arm_obj, p, "Melee2H_Test_Swing")
    acts.append(act)
    problems += check_action_name(act.name, False)
    if int(act.frame_range[1]) != 27:
        problems.append("swing frame range %s" % tuple(act.frame_range))
    if not check_action_name("Walk-loop", True) or not check_action_name("Loco_Walk", True):
        problems.append("name rule accepted 'Walk-loop' or a loop without -loop")
    reset_pose(arm_obj)
    vmax = max_stance_speed(p, 0.8, 0.58, 0.05, 0.0)
    tmp = tempfile.mkdtemp(prefix="anim_selftest_")
    glb = os.path.join(tmp, "humanoid_anim_test.glb")
    with export.quiet():
        export.export_gltf(glb)
    data = open(glb, "rb").read()
    gj = json.loads(data[20:20 + struct.unpack_from("<I", data, 12)[0]])
    names = sorted(a_["name"] for a_ in gj.get("animations", []))
    if names != sorted(a_.name for a_ in acts):
        problems.append("exported animations %s" % names)
    if verbose:
        for ln in lines:
            print("anim selftest:", ln)
        print("anim selftest: FK check %.2e m; max sliding-free speed at period 0.8 s / duty 0.58 / drop 0.05 = "
              "%.2f m/s" % (err, vmax))
        print("anim selftest: exported animations %s -> %s" % (names, "OK" if not problems else "FAIL"))
        for x in problems:
            print("  FAIL", x)
    return problems


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        sys.exit(1 if selftest() else 0)
    print(__doc__)
