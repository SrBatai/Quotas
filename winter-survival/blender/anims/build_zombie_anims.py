"""Zombie animation library — ASSET_SPEC_V2 §6.1/§6.3 (every Zom_* clip of milestones M2 and M4).

    cd winter-survival/blender && python3 anims/build_zombie_anims.py

Exports assets/models/anims/zombie_anims.glb (+ sources/zombie_anims.blend + the Godot `.import`, template
lib/export.py kind "anim": AnimationLibrary, humanoid retarget, `-loop` -> LOOP_LINEAR) from the player-proportion
armature without mesh (same 27 bones / rest as the survivor and every zombie), and merges the clip events into
data/anim_events.json. In-place (Root never keyed, Hips = the only position track), 30 fps, every frame keyed
(LINEAR), LEFT foot on the ground at t = 0 in the gait cycles. Hunched posture = the animations (the zombie rest
pose is the shared T-pose). ZOMBIE_TABLE below is the contract verify_chars.py checks:

    name -> (looping, length s, authored speed m/s or 0, kind)
    kind: gait (foot metrics), crawl (hand-contact metrics), stand (feet planted), move (feet may step), ground,
    additive (delta from the T-pose rest, for an Add2 node)

M4 speed / length decisions (deviations from §6.3, like the M1 walk decision): the 1.2 m/s shamble / investigate
cycles last 1.2 s (spec 1.6: 0.96 m strides needed a 17 cm pelvis drop, a lunge rather than a shamble), the bloater
walk 1.4 s at 0.9 m/s (spec 1.8), the tired run 0.8 s at 3.0 m/s (spec 1.0). TimeScale = v_real / v_authored.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import bpy  # noqa: E402
from mathutils import Quaternion, Vector  # noqa: E402

from lib import anim  # noqa: E402
from lib import export  # noqa: E402
from lib import keyanim as ka  # noqa: E402
from lib import lowpoly as lp  # noqa: E402
from lib import rig  # noqa: E402
from lib.anim import X, Y, Z, q_axis as q  # noqa: E402

NAME = "zombie_anims"
SUBDIR = "anims"
EVENTS_PATH = export.ROOT / "data" / "anim_events.json"

ZOMBIE_TABLE = {
    "Zom_Idle_A-loop": (True, 3.0, 0.0, "stand"),
    "Zom_Idle_B-loop": (True, 3.0, 0.0, "stand"),
    "Zom_Shamble_A-loop": (True, 1.2, 1.2, "gait"),
    "Zom_Shamble_B-loop": (True, 1.2, 1.2, "gait"),
    "Zom_Shamble_C-loop": (True, 1.2, 1.2, "gait"),
    "Zom_Shamble_D-loop": (True, 1.2, 1.2, "gait"),
    "Zom_Investigate-loop": (True, 1.2, 1.2, "gait"),
    "Zom_Alert": (False, 0.6, 0.0, "move"),
    "Zom_Attack_A": (False, 1.0, 0.0, "move"),
    "Zom_Attack_B": (False, 1.0, 0.0, "move"),
    "Zom_Grab-loop": (True, 1.0, 0.0, "stand"),
    "Zom_Knock_Door-loop": (True, 1.0, 0.0, "stand"),
    "Zom_Hit": (False, 8.0 / 30.0, 0.0, "additive"),      # 8 frames (0.25 s = 7.5 frames)
    "Zom_Stagger": (False, 0.6, 0.0, "move"),
    "Zom_Knockdown": (False, 0.8, 0.0, "ground"),
    "Zom_GetUp": (False, 1.5, 0.0, "ground"),
    "Zom_Death_A": (False, 0.8, 0.0, "ground"),
    "Zom_Death_B": (False, 0.8, 0.0, "ground"),
    "Zom_Frozen_Idle-loop": (True, 4.0, 0.0, "stand"),
    "Zom_Wake": (False, 1.5, 0.0, "move"),
    "Zom_Run-loop": (True, 0.7, 5.5, "gait"),
    "Zom_Run_Tired-loop": (True, 0.8, 3.0, "gait"),
    "Zom_Crawl-loop": (True, 1.4, 1.0, "crawl"),
    "Zom_Crawl_Grab": (False, 0.8, 0.0, "ground"),
    "Zom_Crawl_Death": (False, 0.8, 0.0, "ground"),
    "Zom_Walk_Heavy-loop": (True, 1.4, 0.9, "gait"),
    "Zom_Bloat_Pop": (False, 0.5, 0.0, "move"),
}

# events (seconds) -> data/anim_events.json; *_start / *_end = server damage windows
EVENTS = {
    "Zom_Attack_A": {"hit_start": 0.34, "hit_end": 0.48, "swing": 0.30},
    "Zom_Attack_B": {"hit_start": 0.40, "hit_end": 0.56, "bite": 0.48},
    "Zom_Grab-loop": {"bite_1": 0.25, "bite_2": 0.75},
    "Zom_Knock_Door-loop": {"knock_1": 0.25, "knock_2": 0.75},
    "Zom_Alert": {"roar": 0.18},
    "Zom_Knockdown": {"ground": 0.52},
    "Zom_Death_A": {"ground": 0.62, "ragdoll": 0.55},
    "Zom_Death_B": {"ground": 0.58, "ragdoll": 0.50},
    "Zom_GetUp": {"stand": 1.20},
    "Zom_Wake": {"crack_1": 0.30, "crack_2": 0.62, "free": 1.05},
    "Zom_Crawl_Grab": {"hit_start": 0.30, "hit_end": 0.46},
    "Zom_Crawl_Death": {"ground": 0.55},
    "Zom_Bloat_Pop": {"pop": 0.34},
    "Zom_Shamble_A-loop": {"foot_l": 0.0, "foot_r": 0.667},
    "Zom_Shamble_B-loop": {"foot_l": 0.0, "foot_r": 0.533},
    "Zom_Shamble_C-loop": {"foot_l": 0.0, "foot_r": 0.6},
    "Zom_Shamble_D-loop": {"foot_l": 0.0, "foot_r": 0.6},
    "Zom_Investigate-loop": {"foot_l": 0.0, "foot_r": 0.6},
    "Zom_Run-loop": {"foot_l": 0.0, "foot_r": 0.35},
    "Zom_Run_Tired-loop": {"foot_l": 0.0, "foot_r": 0.4},
    "Zom_Walk_Heavy-loop": {"foot_l": 0.0, "foot_r": 0.7},
    "Zom_Crawl-loop": {"hand_l": 0.0, "hand_r": 0.7},
}

SIDES = anim.SIDES


def arm(side, lower, swing, elbow, twist=0.0):
    ua, la = anim.arm_pose(side, lower, swing, elbow, twist)
    return {side + "UpperArm": ua, side + "LowerArm": la}


def both(fn):
    out = {}
    for s in SIDES:
        out.update(fn(s, 1 if s == "Left" else -1))
    return out


# ------------------------------------------------------------------------------------------------------------
# the zombie stance (base of every standing key pose)
# ------------------------------------------------------------------------------------------------------------
def zbase():
    r = {"Hips": q(X, 5) @ q(Y, 2), "Spine": q(X, 10) @ q(Y, 3), "Chest": q(X, 14) @ q(Z, -4),
         "Neck": q(X, -4) @ q(Y, -3), "Head": q(X, -14) @ q(Y, 12) @ q(Z, 6),
         "LeftShoulder": q(Y, 6), "RightShoulder": q(Y, -3), "LeftHand": q(Z, -10), "RightHand": q(Z, 14)}
    r.update(arm("Left", 66, 34, 34, -8))
    r.update(arm("Right", 76, 20, 22, -4))
    return r


BASE_FEET = {"Left": dict(dy=-0.07, dx=0.02, yaw=6), "Right": dict(dy=0.09, dx=0.03, yaw=14)}
BASE_HIPS = (0.0, 0.02, -0.05)


def zpose(**over):
    r = zbase()
    r.update(over)
    return r


def post_alive(length, seed=0, amp=0.25):
    return lambda t, pose: ka.alive(pose, t, length, amp, seed)


def clip(p=None, base=None, post=None, length=1.0, seed=0):
    layers = [post_alive(length, seed)]
    if post:
        layers.append(post)

    def run(t, pose):
        for f in layers:
            f(t, pose)
    return ka.Clip(p, base=zbase() if base is None else base, post=run)


# ------------------------------------------------------------------------------------------------------------
# standing loops (procedural)
# ------------------------------------------------------------------------------------------------------------
def idle_a(arm_obj, p, name="Zom_Idle_A-loop", L=3.0):
    """Swaying on the spot, head lolling, arms dangling with lag, jaw-ish head drops."""
    def fn(tt, pose):
        u = tt / L
        s1, c1 = math.sin(2 * math.pi * u), math.cos(2 * math.pi * u)
        s2 = math.sin(4 * math.pi * u + 0.6)
        for b, qq in zbase().items():
            pose.rel[b] = qq.copy()
        pose.hips = Vector(BASE_HIPS) + Vector((0.018 * s1, 0.0, -0.006 * s2))
        pose.rel["Hips"] = q(X, 5) @ q(Y, 2 + 2.5 * s1)
        pose.rel["Spine"] = q(X, 10 + 1.5 * s2) @ q(Y, 3 - 2.0 * s1)
        pose.rel["Chest"] = q(X, 14 - 1.0 * s2) @ q(Z, -4 + 5 * c1)
        pose.rel["Head"] = q(X, -14 + 6 * max(0.0, math.sin(2 * math.pi * u * 2 + 1.0)) ** 3) @ q(Y, 12 + 6 * s1) @ \
            q(Z, 6 - 10 * c1)
        lag = math.sin(2 * math.pi * u - 0.5)
        pose.rel.update(arm("Left", 66 + 3 * lag, 34 + 6 * lag, 34 + 6 * s2, -8))
        pose.rel.update(arm("Right", 76 - 2 * lag, 20 - 6 * lag, 22 + 4 * s2, -4))
        ka.alive(pose, tt, L, 0.2, 1)
        return {"Left": BASE_FEET["Left"], "Right": BASE_FEET["Right"]}
    return ka.procedural(arm_obj, p, name, L, fn)


def idle_b(arm_obj, p, name="Zom_Idle_B-loop", L=3.0):
    """Looking around: slow head / torso turn right, a twitch, then left; weight shifts; one arm raised."""
    def fn(tt, pose):
        u = tt / L
        look = math.sin(2 * math.pi * u)
        twitch = math.exp(-((u - 0.62) / 0.03) ** 2)
        s2 = math.sin(4 * math.pi * u)
        for b, qq in zbase().items():
            pose.rel[b] = qq.copy()
        pose.hips = Vector(BASE_HIPS) + Vector((-0.02 * look, 0.0, -0.004 * s2))
        pose.rel["Hips"] = q(X, 5) @ q(Y, 2 - 2 * look) @ q(Z, -6 * look)
        pose.rel["Spine"] = q(X, 9) @ q(Z, -6 * look)
        pose.rel["Chest"] = q(X, 12 + 2 * s2) @ q(Z, -10 * look + 6 * twitch)
        pose.rel["Neck"] = q(X, -6) @ q(Z, -14 * look)
        pose.rel["Head"] = q(X, -16 - 10 * twitch) @ q(Y, 8 + 10 * twitch) @ q(Z, -26 * look + 12 * twitch)
        pose.rel.update(arm("Left", 60 - 4 * look, 44 + 4 * s2, 44, -10))
        pose.rel.update(arm("Right", 80, 12 + 4 * look, 16 + 8 * twitch, -2))
        ka.alive(pose, tt, L, 0.2, 2)
        return {"Left": dict(BASE_FEET["Left"]), "Right": dict(BASE_FEET["Right"])}
    return ka.procedural(arm_obj, p, name, L, fn)


def frozen_pose():
    r = zpose(Spine=q(X, 12) @ q(Y, 5), Chest=q(X, 16) @ q(Z, 8), Neck=q(X, 2) @ q(Y, 8),
              Head=q(X, -6) @ q(Y, 22) @ q(Z, -10), LeftShoulder=q(Y, -2), RightShoulder=q(Y, -8))
    r.update(arm("Left", 52, 62, 30, -6))
    r.update(arm("Right", 70, 38, 46, 4))
    return r


FROZEN_FEET = {"Left": dict(dy=-0.20, dx=0.01, yaw=4), "Right": dict(dy=0.16, dx=0.03, yaw=10, heel=18)}
FROZEN_HIPS = (0.0, 0.0, -0.07)


def frozen_idle(arm_obj, p, name="Zom_Frozen_Idle-loop", L=4.0):
    """Rigid mid-stride pose frozen in place; only a sub-degree creak (keeps every track alive)."""
    def fn(tt, pose):
        for b, qq in frozen_pose().items():
            pose.rel[b] = qq.copy()
        pose.hips = Vector(FROZEN_HIPS)
        ka.alive(pose, tt, L, 0.35, 3)
        return FROZEN_FEET
    return ka.procedural(arm_obj, p, name, L, fn)


# ------------------------------------------------------------------------------------------------------------
# gait cycles
# ------------------------------------------------------------------------------------------------------------
SHAMBLE = dict(speed=1.2, period=1.2, duty=0.64, style="walk", heel_deg=8.0, toe_deg=28.0, heel_frac=0.16,
               flat_end=0.55, lift=0.07, lift_peak=0.4, bob=0.025, yaw=6.0, roll=4.0, sway=0.03, lean=8.0,
               hunch=26.0, head_pitch=6.0, head_follow=0.5, twist=0.6, arm_swing=8.0, drop_margin=0.02,
               stance_width=0.015)
DRAG = dict(lift=0.05, heel_deg=4.0, toe_deg=18.0, swing_k0=0.2, swing_k1=0.35, lift_peak=0.5)


def zombie_upper(style, loll=1.0, look=0.0):
    """Upper body for the shambles: style A/B (limp side, asymmetric arms), C (arms hanging, pendulum lag),
    D (arms raised forward), I (investigate: head turned to the noise)."""
    def fn(t, pose, info):
        c = math.cos(2 * math.pi * t)
        s = math.sin(2 * math.pi * t)
        s2 = math.sin(4 * math.pi * t)
        pose.rel["Head"] = pose.rel["Head"] @ q(Y, loll * (10 + 5 * math.sin(2 * math.pi * t - 0.8))) @ \
            q(Z, 4 * math.sin(2 * math.pi * t - 0.4) + look) @ q(X, 3 * s2)
        if look:
            pose.rel["Neck"] = pose.rel["Neck"] @ q(Z, look * 0.5)
            pose.rel["Chest"] = pose.rel["Chest"] @ q(Z, look * 0.25)
        pose.rel["LeftShoulder"] = pose.rel["LeftShoulder"] @ q(Y, 4) @ q(Z, -8)
        pose.rel["RightShoulder"] = pose.rel["RightShoulder"] @ q(Z, 8)
        if style == "A":         # left leg drags; left arm hangs, right arm half raised
            pose.rel.update(arm("Left", 82, 10 + 10 * math.sin(2 * math.pi * (t - 0.15)), 14, -8))
            pose.rel.update(arm("Right", 62, 40 + 6 * c, 38 + 6 * s2, -4))
            pose.rel["RightShoulder"] = q(Y, -8)
        elif style == "B":       # right leg drags; mirrored
            pose.rel.update(arm("Right", 84, 8 + 10 * math.sin(2 * math.pi * (t - 0.65)), 12, -8))
            pose.rel.update(arm("Left", 60, 42 - 6 * c, 36 + 6 * s2, -6))
            pose.rel["LeftShoulder"] = q(Y, 8)
        elif style == "C":       # arms hanging and swinging late, head down
            pose.rel.update(arm("Left", 86, 6 + 16 * math.sin(2 * math.pi * (t - 0.62)), 8, -12))
            pose.rel.update(arm("Right", 86, 6 + 16 * math.sin(2 * math.pi * (t - 0.12)), 8, -12))
            pose.rel["Head"] = pose.rel["Head"] @ q(X, 14)
            for sd, sg in (("Left", 1), ("Right", -1)):
                pose.rel[sd + "Shoulder"] = q(Y, sg * 10)
        elif style == "D":       # classic: both arms reaching forward, bobbing
            pose.rel.update(arm("Left", 30, 66 + 6 * s, 16 + 6 * s2, 2))
            pose.rel.update(arm("Right", 32, 64 - 6 * s, 18 + 6 * s2, 2))
            pose.rel["LeftHand"] = q(X, -20)
            pose.rel["RightHand"] = q(X, -20)
            for sd, sg in (("Left", 1), ("Right", -1)):
                pose.rel[sd + "Shoulder"] = q(Y, -sg * 6)
        elif style == "I":       # investigate: arms low, head / chest toward the noise
            pose.rel.update(arm("Left", 76, 24 + 6 * c, 28, -6))
            pose.rel.update(arm("Right", 78, 22 - 6 * c, 26, -6))
    return fn


def shamble(arm_obj, p, name, style):
    g = dict(SHAMBLE)
    if style == "A":
        return ka.gait_cycle(arm_obj, p, name, g, sides={"Left": DRAG}, dphase=2.0 / 36.0, limp_side="Left", limp=1.0,
                             upper=zombie_upper("A"))
    if style == "B":
        return ka.gait_cycle(arm_obj, p, name, g, sides={"Right": DRAG}, dphase=-2.0 / 36.0, limp_side="Right", limp=1.0,
                             upper=zombie_upper("B"))
    if style == "C":
        g.update(hunch=32.0, lift=0.06, roll=5.0, sway=0.035, head_pitch=14.0)
        return ka.gait_cycle(arm_obj, p, name, g, upper=zombie_upper("C", 1.3))
    if style == "D":
        g.update(hunch=22.0, lift=0.08, head_pitch=0.0)
        return ka.gait_cycle(arm_obj, p, name, g, upper=zombie_upper("D", 0.6))
    g.update(hunch=16.0, lift=0.07, head_pitch=-4.0, sway=0.02, roll=3.0)
    return ka.gait_cycle(arm_obj, p, name, g, upper=zombie_upper("I", 0.4, look=-34.0))


def run_upper(tired):
    def fn(t, pose, info):
        c = math.cos(2 * math.pi * t)
        s2 = math.sin(4 * math.pi * t)
        if tired:
            pose.rel.update(arm("Left", 80, 10 - 26 * c, 30, -6))
            pose.rel.update(arm("Right", 80, 10 + 26 * c, 30, -6))
            pose.rel["Head"] = pose.rel["Head"] @ q(X, 10 + 6 * s2) @ q(Y, 8)
        else:                    # sprinting zombie: arms flailing forward, reaching, head thrust forward
            pose.rel.update(arm("Left", 58, 44 - 42 * c, 30 + 20 * max(0.0, c), 0))
            pose.rel.update(arm("Right", 58, 44 + 42 * c, 30 + 20 * max(0.0, -c), 0))
            pose.rel["Head"] = pose.rel["Head"] @ q(X, -6 + 4 * s2) @ q(Y, 6 * math.sin(2 * math.pi * t))
    return fn


RUN = dict(speed=5.5, period=0.7, duty=0.28, style="run", heel_deg=6.0, toe_deg=52.0, heel_frac=0.30, flat_end=0.40,
           toe_power=1.3, lift=0.20, lift_peak=0.42, bob=0.05, drop_margin=0.03, swing_k0=0.25, swing_k1=0.5,
           yaw=10.0, roll=4.0, sway=0.02, pelvis_pitch=8.0, lean=20.0, hunch=6.0, arm_swing=0.0, head_pitch=-12.0,
           twist=1.3)
RUN_TIRED = dict(speed=3.0, period=0.8, duty=0.38, style="run", heel_deg=8.0, toe_deg=40.0, heel_frac=0.25,
                 flat_end=0.45, lift=0.11, lift_peak=0.45, bob=0.04, drop_margin=0.02, yaw=8.0, roll=5.0, sway=0.03,
                 pelvis_pitch=8.0, lean=18.0, hunch=14.0, arm_swing=0.0, head_pitch=-6.0, twist=1.0)
HEAVY = dict(speed=0.9, period=1.4, duty=0.66, style="walk", heel_deg=6.0, toe_deg=22.0, heel_frac=0.18, flat_end=0.6,
             lift=0.06, bob=0.02, yaw=5.0, roll=6.0, sway=0.06, lean=-4.0, hunch=8.0, head_pitch=-8.0,
             stance_width=0.07, arm_swing=6.0, drop_margin=0.02, twist=0.5)


def heavy_upper(t, pose, info):
    c = math.cos(2 * math.pi * t)
    s2 = math.sin(4 * math.pi * t)
    # arms held out by the belly, rocking with the waddle; head small movements
    pose.rel.update(arm("Left", 58, 18 + 6 * c, 30 + 4 * s2, -16))
    pose.rel.update(arm("Right", 58, 18 - 6 * c, 30 + 4 * s2, -16))
    pose.rel["Head"] = pose.rel["Head"] @ q(Y, 6 * math.sin(2 * math.pi * t - 0.5)) @ q(X, -4)


# ------------------------------------------------------------------------------------------------------------
# key-pose one-shots
# ------------------------------------------------------------------------------------------------------------
BF = BASE_FEET
BH = BASE_HIPS


def feet(ldy=None, rdy=None, **kw):
    f = {"Left": dict(BF["Left"]), "Right": dict(BF["Right"])}
    if ldy is not None:
        f["Left"]["dy"] = ldy
    if rdy is not None:
        f["Right"]["dy"] = rdy
    for k, v in kw.items():
        side, key = k.split("_")
        f["Left" if side == "l" else "Right"][key] = v
    return f


def attack_a(arm_obj, p, name="Zom_Attack_A", L=1.0):
    """Claw swipe (right arm): 0.30 s wind-up, strike 0.30 -> 0.40, follow-through, recover."""
    c = clip(p, length=L, seed=4)
    c.key(0.0, zbase(), BH, feet())
    c.key(0.30, zpose(Hips=q(X, 0) @ q(Z, -14), Spine=q(X, 4) @ q(Z, -14), Chest=q(X, 2) @ q(Z, -22),
                      Neck=q(X, -4), Head=q(X, -10) @ q(Z, 26) @ q(Y, 6), RightShoulder=q(Y, -14) @ q(Z, -10),
                      LeftShoulder=q(Y, 2), **arm("Right", 20, -30, 96, 20), **arm("Left", 50, 60, 30, -4)),
          (0.02, 0.07, -0.08), feet(0.0, 0.14, r_yaw=20), ease="out")
    c.key(0.40, zpose(Hips=q(X, 12) @ q(Z, 14), Spine=q(X, 16) @ q(Z, 14), Chest=q(X, 22) @ q(Z, 24),
                      Neck=q(X, -8), Head=q(X, -16) @ q(Z, -16), RightShoulder=q(Y, 4) @ q(Z, 12),
                      LeftShoulder=q(Y, 8), **arm("Right", 60, 86, 18, 28), **arm("Left", 70, -10, 30, -6)),
          (-0.02, -0.10, -0.10), feet(-0.26, 0.12, l_yaw=0, r_yaw=18), ease="in")
    c.key(0.54, zpose(Hips=q(X, 14) @ q(Z, 20), Spine=q(X, 18) @ q(Z, 18), Chest=q(X, 26) @ q(Z, 30),
                      Neck=q(X, -6), Head=q(X, -14) @ q(Z, -20), RightShoulder=q(Y, 6) @ q(Z, 14),
                      **arm("Right", 82, 70, 22, 52), **arm("Left", 76, -14, 26, -6)),
          (-0.03, -0.12, -0.11), feet(-0.26, 0.12, r_yaw=18), ease="out")
    c.key(0.78, zpose(Chest=q(X, 18) @ q(Z, 6), **arm("Right", 74, 34, 30, 10)), (0.0, -0.04, -0.07),
          feet(-0.16, 0.10), ease="ease")
    c.key(L, zbase(), BH, feet(), ease="ease")
    return c.write(arm_obj, name, L)


def attack_b(arm_obj, p, name="Zom_Attack_B", L=1.0):
    """Two-handed grab + bite lunge: crouch back 0.30 s, lunge 0.30 -> 0.42, bite 0.48, pull, recover."""
    c = clip(p, length=L, seed=5)
    reach = both(lambda s, sg: arm(s, 40, 80, 24, 6))
    c.key(0.0, zbase(), BH, feet())
    c.key(0.30, zpose(Hips=q(X, -2), Spine=q(X, 4), Chest=q(X, 2), Neck=q(X, -10), Head=q(X, -18) @ q(Y, 6),
                      LeftShoulder=q(Y, -10), RightShoulder=q(Y, 10),
                      **both(lambda s, sg: arm(s, 34, 70, 70, 10))),
          (0.0, 0.08, -0.12), feet(0.02, 0.12), ease="out")
    c.key(0.42, zpose(Hips=q(X, 16), Spine=q(X, 16), Chest=q(X, 20), Neck=q(X, 14), Head=q(X, -22), **reach),
          (0.0, -0.18, -0.10), feet(-0.30, 0.12, r_heel=20), ease="in")
    c.key(0.50, zpose(Hips=q(X, 18), Spine=q(X, 18), Chest=q(X, 24), Neck=q(X, 26), Head=q(X, -4) @ q(Y, 10),
                      **both(lambda s, sg: arm(s, 46, 70, 60, 8))),
          (0.0, -0.20, -0.12), feet(-0.30, 0.12, r_heel=20), ease="out")
    c.key(0.66, zpose(Hips=q(X, 14), Spine=q(X, 14), Chest=q(X, 20), Neck=q(X, 16), Head=q(X, -8) @ q(Y, -8),
                      **both(lambda s, sg: arm(s, 50, 62, 76, 6))),
          (0.0, -0.14, -0.11), feet(-0.30, 0.12, r_heel=10), ease="ease")
    c.key(L, zbase(), BH, feet(), ease="ease")
    return c.write(arm_obj, name, L)


def grab_loop(arm_obj, p, name="Zom_Grab-loop", L=1.0):
    """Hands clamped on the victim's shoulders (0.45-0.55 m in front, chest height), pulling and biting twice."""
    c = clip(p, length=L, seed=6)
    hold = lambda d, e: both(lambda s, sg: arm(s, 44 + d, 70 - d, 66 + e, 8))   # noqa: E731
    c.key(0.0, zpose(Hips=q(X, 8), Spine=q(X, 10), Chest=q(X, 14) @ q(Z, 6), Neck=q(X, 4), Head=q(X, -12) @ q(Z, -6),
                     **hold(0, 10)), (0.0, 0.0, -0.08), feet(-0.10, 0.14))
    c.key(0.25, zpose(Hips=q(X, 14), Spine=q(X, 16), Chest=q(X, 20) @ q(Z, -4), Neck=q(X, 22), Head=q(X, 0) @ q(Y, 14),
                      **hold(-6, -14)), (0.0, -0.06, -0.10), feet(-0.10, 0.14), ease="in")
    c.key(0.5, zpose(Hips=q(X, 6), Spine=q(X, 8), Chest=q(X, 12) @ q(Z, -8), Neck=q(X, 2), Head=q(X, -14) @ q(Z, 8),
                     **hold(2, 16)), (0.0, 0.02, -0.08), feet(-0.10, 0.14), ease="out")
    c.key(0.75, zpose(Hips=q(X, 14), Spine=q(X, 16), Chest=q(X, 20) @ q(Z, 6), Neck=q(X, 22), Head=q(X, 2) @ q(Y, -12),
                      **hold(-6, -14)), (0.0, -0.06, -0.10), feet(-0.10, 0.14), ease="in")
    c.close(L, ease="out")
    return c.write(arm_obj, name, L, looping=True)


def knock_loop(arm_obj, p, name="Zom_Knock_Door-loop", L=1.0):
    """Pounding a door 0.5 m in front with alternating fists (hits at 0.25 / 0.75 s)."""
    c = clip(p, length=L, seed=7)
    up = lambda s: arm(s, 10, 64, 110, 16)       # noqa: E731
    hit = lambda s: arm(s, 34, 84, 40, 10)       # noqa: E731
    mid = lambda s: arm(s, 30, 74, 70, 12)       # noqa: E731
    chest = dict(Hips=q(X, 6), Spine=q(X, 8), Chest=q(X, 10), Neck=q(X, 2), Head=q(X, -10))
    c.key(0.0, zpose(**dict(chest, Head=q(X, -10) @ q(Z, -8)), **up("Right"), **hit("Left")), (0.0, 0.0, -0.06),
          feet(-0.08, 0.12))
    c.key(0.25, zpose(**dict(chest, Chest=q(X, 16) @ q(Z, 8)), **hit("Right"), **mid("Left")), (0.0, -0.03, -0.08),
          feet(-0.08, 0.12), ease="in")
    c.key(0.5, zpose(**dict(chest, Head=q(X, -10) @ q(Z, 8)), **up("Left"), **hit("Right")), (0.0, 0.0, -0.06),
          feet(-0.08, 0.12), ease="out")
    c.key(0.75, zpose(**dict(chest, Chest=q(X, 16) @ q(Z, -8)), **hit("Left"), **mid("Right")), (0.0, -0.03, -0.08),
          feet(-0.08, 0.12), ease="in")
    c.close(L, ease="out")
    return c.write(arm_obj, name, L, looping=True)


def hit_additive(arm_obj, p, name="Zom_Hit", L=8.0 / 30.0):
    """Additive flinch (delta from the T-pose rest): torso / head snap back at 0.06 s, arms fling, recover."""
    c = ka.Clip(p, base={}, post=post_alive(L, 8, 0.15))
    c.key(0.0, {}, (0, 0, 0))
    c.key(0.06, {"Hips": q(X, -4), "Spine": q(X, -7) @ q(Z, 4), "Chest": q(X, -10) @ q(Z, 6), "Neck": q(X, -6),
                 "Head": q(X, -16) @ q(Y, -8), "LeftShoulder": q(Y, -6), "RightShoulder": q(Y, 8),
                 "LeftUpperArm": q(X, 14) @ q(Y, -8), "RightUpperArm": q(X, 12) @ q(Y, 10),
                 "LeftLowerArm": q(Z, -12), "RightLowerArm": q(Z, 14), "LeftUpperLeg": q(X, -4), "RightUpperLeg": q(X, 3),
                 "LeftLowerLeg": q(X, 5), "RightLowerLeg": q(X, 4)}, (0.0, 0.03, -0.01), ease="out3")
    c.key(0.14, {"Spine": q(X, -3), "Chest": q(X, -4), "Head": q(X, -6) @ q(Y, -3), "LeftUpperArm": q(X, 5),
                 "RightUpperArm": q(X, 5)}, (0.0, 0.012, 0.0), ease="ease")
    c.key(L, {}, (0, 0, 0), ease="ease")
    return c.write(arm_obj, name, L)


def stagger(arm_obj, p, name="Zom_Stagger", L=0.6):
    """Reel back (torso thrown up, arms fly out), right foot steps back to catch, recover (in place)."""
    c = clip(p, length=L, seed=9)
    c.key(0.0, zbase(), BH, feet())
    c.key(0.12, zpose(Hips=q(X, -8), Spine=q(X, -6) @ q(Z, 8), Chest=q(X, -8) @ q(Z, 10), Neck=q(X, -8),
                      Head=q(X, -24) @ q(Y, -14), **arm("Left", 40, 40, 50, -20), **arm("Right", 30, 30, 40, -10)),
          (0.0, 0.10, -0.08), feet(-0.07, 0.09, r_heel=12), ease="out3")
    c.key(0.30, zpose(Hips=q(X, 2), Spine=q(X, 4) @ q(Z, 4), Chest=q(X, 6) @ q(Z, 4), Head=q(X, -10) @ q(Y, -6),
                      **arm("Left", 56, 30, 40, -14), **arm("Right", 50, 20, 30, -6)),
          (0.0, 0.14, -0.12), feet(-0.02, 0.34), ease="ease")
    c.key(0.45, zpose(Head=q(X, -12) @ q(Y, 8)), (0.0, 0.06, -0.08), feet(-0.05, 0.20), ease="ease")
    c.key(L, zbase(), BH, feet(), ease="ease")
    return c.write(arm_obj, name, L)


def lying_back():
    """On the back, arms spread, legs bent (end of Zom_Knockdown / start of Zom_GetUp / end of Zom_Death_B)."""
    r = zpose(Hips=q(X, -84), Spine=q(X, -4), Chest=q(X, -6) @ q(Z, 6), Neck=q(X, 6), Head=q(X, 10) @ q(Y, 20),
              LeftShoulder=q(Y, -6), RightShoulder=q(Y, 6),
              LeftUpperLeg=q(X, -8) @ q(Y, -6), RightUpperLeg=q(X, -2) @ q(Y, 5), LeftLowerLeg=q(X, 14),
              RightLowerLeg=q(X, 6), LeftFoot=q(X, 20), RightFoot=q(X, 30))
    r.update(arm("Left", 58, -2, 24, 0))
    r.update(arm("Right", 34, -2, 56, 0))
    return r


def lying_front():
    """Face down, head turned, arms along / under (end of Zom_Death_A, Zom_Crawl_Death)."""
    r = zpose(Hips=q(X, 88), Spine=q(X, 2), Chest=q(X, 0) @ q(Z, -4), Neck=q(X, -10), Head=q(X, -12) @ q(Z, 60),
              LeftShoulder=q(Y, 4), RightShoulder=q(Y, -4),
              LeftUpperLeg=q(X, 2) @ q(Y, -6), RightUpperLeg=q(X, 0) @ q(Y, 8), LeftLowerLeg=q(X, 10),
              RightLowerLeg=q(X, 4), LeftFoot=q(X, 70), RightFoot=q(X, 74))
    r.update(arm("Left", 80, -20, 20, 70))
    r.update(arm("Right", 30, 60, 50, -30))
    return r


def knockdown(arm_obj, p, name="Zom_Knockdown", L=0.8):
    c = clip(p, length=L, seed=10)
    c.key(0.0, zbase(), BH, feet())
    c.key(0.15, zpose(Hips=q(X, -12), Spine=q(X, -8), Chest=q(X, -12), Head=q(X, -26), **arm("Left", 30, 50, 40, -20),
                      **arm("Right", 24, 44, 50, -16)), (0.0, 0.10, -0.12), feet(-0.10, 0.12, l_heel=6), ease="out")
    c.key(0.40, zpose(Hips=q(X, -30), Spine=q(X, -10), Chest=q(X, -8), Neck=q(X, 14), Head=q(X, 16),
                      LeftUpperLeg=q(X, -70), RightUpperLeg=q(X, -50), LeftLowerLeg=q(X, 80), RightLowerLeg=q(X, 60),
                      **arm("Left", 30, 20, 50, 30), **arm("Right", 40, 30, 60, 20)),
          (0.0, 0.30, -0.60), None, ground=True, ease="in")
    c.key(0.56, zpose(Hips=q(X, -70), Spine=q(X, -6), Chest=q(X, -6), Neck=q(X, 20), Head=q(X, 24),
                      LeftUpperLeg=q(X, -50), RightUpperLeg=q(X, -30), LeftLowerLeg=q(X, 50), RightLowerLeg=q(X, 30),
                      **arm("Left", 20, 10, 40, 50), **arm("Right", 30, 0, 60, 40)),
          (0.0, 0.40, -0.70), None, ground=True, ease="in")
    c.key(L, lying_back(), (0.0, 0.45, -0.78), None, ground=True, ease="out")
    return c.write(arm_obj, name, L)


def kneel(hip_pitch, down="Right", up_thigh=-80.0):
    """Legs of a kneel with the pelvis pitched `hip_pitch`: `down` knee on the ground (thigh vertical, shin back),
    the other foot planted in front (thigh forward, shin vertical)."""
    o = "Left" if down == "Right" else "Right"
    return {down + "UpperLeg": q(X, -hip_pitch), down + "LowerLeg": q(X, 92), down + "Foot": q(X, 34),
            o + "UpperLeg": q(X, -hip_pitch + up_thigh), o + "LowerLeg": q(X, -up_thigh), o + "Foot": q(X, 0)}


def getup(arm_obj, p, name="Zom_GetUp", L=1.5):
    """Lying on the back -> sits up, hands behind -> rolls onto the right knee, hand on the left knee -> pushes up
    (stiff, jerky) -> zombie stance."""
    c = clip(p, length=L, seed=11)
    c.key(0.0, lying_back(), (0.0, 0.45, -0.78), None, ground=True)
    c.key(0.38, zpose(Hips=q(X, -30), Spine=q(X, 26), Chest=q(X, 24) @ q(Z, 8), Neck=q(X, 6), Head=q(X, -6) @ q(Y, 14),
                      LeftUpperLeg=q(X, -70), RightUpperLeg=q(X, -60) @ q(Y, 8), LeftLowerLeg=q(X, 100),
                      RightLowerLeg=q(X, 90), **arm("Left", 70, -40, 10, 0), **arm("Right", 66, -34, 20, 0)),
          (0.0, 0.30, -0.66), None, ground=True, ease="ease")
    c.key(0.58, zpose(Hips=q(X, 64) @ q(Z, 8), Spine=q(X, 8), Chest=q(X, 4), Neck=q(X, -14), Head=q(X, -22) @ q(Y, 8),
                      LeftUpperLeg=q(X, -54), RightUpperLeg=q(X, -50), LeftLowerLeg=q(X, 96), RightLowerLeg=q(X, 94),
                      LeftFoot=q(X, 30), RightFoot=q(X, 30), **arm("Left", 76, 66, 8, 0), **arm("Right", 74, 70, 10, 0)),
          (0.0, 0.06, -0.50), None, ground=True, ease="ease")
    c.key(0.84, zpose(Hips=q(X, 20) @ q(Z, 10), Spine=q(X, 22), Chest=q(X, 24) @ q(Z, 6), Neck=q(X, -8),
                      Head=q(X, -20) @ q(Y, 10), **kneel(20.0), **arm("Left", 80, 50, 40, 0),
                      **arm("Right", 70, 40, 30, 0)),
          (0.0, 0.10, -0.46), None, ground=True, ease="ease")
    c.key(1.12, zpose(Hips=q(X, 26), Spine=q(X, 22), Chest=q(X, 20), Neck=q(X, -10), Head=q(X, -24),
                      **arm("Left", 76, 36, 44, 0), **arm("Right", 72, 40, 30, 0)),
          (0.0, 0.06, -0.26), feet(-0.16, 0.16), ease="out")
    c.key(L, zbase(), BH, feet(), ease="ease")
    return c.write(arm_obj, name, L)


def death_a(arm_obj, p, name="Zom_Death_A", L=0.8):
    """Collapse forward: knees buckle, torso slumps, falls face down (ragdoll may take over from 0.55 s)."""
    c = clip(p, length=L, seed=12)
    c.key(0.0, zbase(), BH, feet())
    c.key(0.20, zpose(Hips=q(X, 14), Spine=q(X, 18), Chest=q(X, 24), Neck=q(X, 20), Head=q(X, 20) @ q(Y, 20),
                      **arm("Left", 86, 10, 10, -10), **arm("Right", 84, 16, 14, -10)),
          (0.0, -0.04, -0.28), feet(-0.07, 0.09, r_heel=20), ease="out")
    c.key(0.45, zpose(Hips=q(X, 40), Spine=q(X, 20), Chest=q(X, 20), Neck=q(X, 16), Head=q(X, 10) @ q(Y, 26),
                      LeftUpperLeg=q(X, -36), RightUpperLeg=q(X, -44), LeftLowerLeg=q(X, 92), RightLowerLeg=q(X, 96),
                      LeftFoot=q(X, 30), RightFoot=q(X, 30),
                      **arm("Left", 60, 50, 20, 0), **arm("Right", 70, 40, 20, 0)),
          (0.0, -0.10, -0.55), None, ground=True, ease="in")
    c.key(0.64, zpose(Hips=q(X, 70), Spine=q(X, 8), Chest=q(X, 6), Neck=q(X, -6), Head=q(X, -10) @ q(Z, 40),
                      LeftUpperLeg=q(X, -22), RightUpperLeg=q(X, -16), LeftLowerLeg=q(X, 40), RightLowerLeg=q(X, 30),
                      LeftFoot=q(X, 50), RightFoot=q(X, 50),
                      **arm("Left", 70, 20, 30, 40), **arm("Right", 40, 60, 40, -20)),
          (0.0, -0.40, -0.75), None, ground=True, ease="in")
    c.key(L, lying_front(), (0.0, -0.50, -0.78), None, ground=True, ease="out")
    return c.write(arm_obj, name, L)


def death_b(arm_obj, p, name="Zom_Death_B", L=0.8):
    """Head snaps back (shot), knees fold, falls on the back (ragdoll from 0.50 s)."""
    c = clip(p, length=L, seed=13)
    c.key(0.0, zbase(), BH, feet())
    c.key(0.10, zpose(Hips=q(X, -6), Spine=q(X, -10), Chest=q(X, -14), Neck=q(X, -16), Head=q(X, -36) @ q(Y, -10),
                      **arm("Left", 40, 40, 30, -20), **arm("Right", 34, 36, 30, -20)),
          (0.0, 0.08, -0.08), feet(), ease="out3")
    c.key(0.36, zpose(Hips=q(X, -24), Spine=q(X, -6), Chest=q(X, -6), Neck=q(X, 6), Head=q(X, -10) @ q(Y, 16),
                      LeftUpperLeg=q(X, -60), RightUpperLeg=q(X, -40), LeftLowerLeg=q(X, 90), RightLowerLeg=q(X, 70),
                      **arm("Left", 60, 30, 40, 20), **arm("Right", 50, 20, 30, 20)),
          (0.0, 0.26, -0.58), None, ground=True, ease="in")
    c.key(0.58, zpose(Hips=q(X, -70), Spine=q(X, -6), Chest=q(X, -4), Neck=q(X, 16), Head=q(X, 20),
                      LeftUpperLeg=q(X, -40), RightUpperLeg=q(X, -30), LeftLowerLeg=q(X, 40), RightLowerLeg=q(X, 30),
                      **arm("Left", 20, 10, 30, 50), **arm("Right", 20, 0, 40, 50)),
          (0.0, 0.40, -0.72), None, ground=True, ease="in")
    c.key(L, lying_back(), (0.0, 0.45, -0.78), None, ground=True, ease="out")
    return c.write(arm_obj, name, L)


def wake(arm_obj, p, name="Zom_Wake", L=1.5):
    """Frozen pose -> shudders and two cracking jerks -> shakes the ice off (arms out) -> zombie stance."""
    def tremor(t, pose):
        env = max(0.0, math.sin(math.pi * min(1.0, t / 1.1)))
        for i, b in enumerate(("Spine", "Chest", "Neck", "Head", "LeftUpperArm", "RightUpperArm", "LeftShoulder",
                               "RightShoulder")):
            a = 3.0 * env * math.sin(2 * math.pi * (11 + i) * t + i)
            pose.rel[b] = pose.rel[b] @ q((X, Y, Z)[i % 3], a)
    c = clip(p, base=zbase(), post=tremor, length=L, seed=14)
    c.key(0.0, frozen_pose(), FROZEN_HIPS, FROZEN_FEET)
    c.key(0.30, dict(frozen_pose(), Head=q(X, -20) @ q(Y, 30) @ q(Z, -24), Chest=q(X, 8) @ q(Z, 14)),
          FROZEN_HIPS, FROZEN_FEET, ease="in3")
    c.key(0.62, dict(frozen_pose(), Chest=q(X, 20) @ q(Z, -10), Head=q(X, 0) @ q(Y, -10),
                     **arm("Left", 30, 30, 60, -20), **arm("Right", 40, 60, 20, 0)), (0.0, 0.02, -0.08),
          FROZEN_FEET, ease="in3")
    c.key(1.05, zpose(Spine=q(X, -4), Chest=q(X, -10), Neck=q(X, -10), Head=q(X, -30) @ q(Y, 10),
                      **arm("Left", 44, 40, 64, -24), **arm("Right", 48, 36, 60, -24)), (0.0, 0.0, -0.04),
          feet(-0.14, 0.12), ease="ease")
    c.key(L, zbase(), BH, feet(), ease="ease")
    return c.write(arm_obj, name, L)


def bloat_pop(arm_obj, p, name="Zom_Bloat_Pop", L=0.5):
    """Bloater swells (arches back, arms spread), bursts at 0.34 s (violent jerk forward), knees start to fold."""
    c = clip(p, length=L, seed=15)
    c.key(0.0, zbase(), BH, feet())
    c.key(0.28, zpose(Hips=q(X, -6), Spine=q(X, -10), Chest=q(X, -16), Neck=q(X, -10), Head=q(X, -30),
                      LeftShoulder=q(Y, -14), RightShoulder=q(Y, 14), **arm("Left", 20, 20, 30, -30),
                      **arm("Right", 20, 20, 30, -30)), (0.0, 0.04, -0.02), feet(r_heel=10, l_heel=10), ease="out")
    c.key(0.36, zpose(Hips=q(X, 16), Spine=q(X, 24), Chest=q(X, 30), Neck=q(X, 20), Head=q(X, 26),
                      **arm("Left", 70, 40, 60, 10), **arm("Right", 70, 40, 60, 10)), (0.0, -0.06, -0.14), feet(),
          ease="in3")
    c.key(L, zpose(Hips=q(X, 22), Spine=q(X, 28), Chest=q(X, 30), Neck=q(X, 24), Head=q(X, 30) @ q(Y, 20),
                   **arm("Left", 86, 10, 10, 0), **arm("Right", 86, 14, 10, 0)), (0.0, -0.08, -0.36),
          feet(-0.07, 0.09, r_heel=20), ease="out")
    return c.write(arm_obj, name, L)


def alert(arm_obj, p, name="Zom_Alert", L=0.6):
    """Sharp jerk toward the stimulus: head snaps up, torso twists, roar (head back, arms flare), ready."""
    c = clip(p, length=L, seed=16)
    c.key(0.0, zbase(), BH, feet())
    c.key(0.10, zpose(Chest=q(X, 6) @ q(Z, 16), Neck=q(X, -10) @ q(Z, 10), Head=q(X, -26) @ q(Z, 24),
                      LeftShoulder=q(Y, -10), RightShoulder=q(Y, 10), **arm("Left", 60, 40, 60, -10),
                      **arm("Right", 60, 30, 60, -10)), (0.0, 0.03, -0.06), feet(), ease="out3")
    c.key(0.26, zpose(Hips=q(X, -2), Spine=q(X, 0), Chest=q(X, -8) @ q(Z, 6), Neck=q(X, -12), Head=q(X, -30),
                      LeftShoulder=q(Y, -16), RightShoulder=q(Y, 16), **arm("Left", 30, 30, 70, -30),
                      **arm("Right", 30, 30, 70, -30)), (0.0, 0.04, -0.10), feet(-0.18, 0.10), ease="out")
    c.key(0.42, zpose(Hips=q(X, 2), Spine=q(X, 2), Chest=q(X, -4), Neck=q(X, -10), Head=q(X, -26),
                      LeftShoulder=q(Y, -12), RightShoulder=q(Y, 12), **arm("Left", 34, 36, 64, -26),
                      **arm("Right", 34, 36, 64, -26)), (0.0, 0.03, -0.10), feet(-0.18, 0.10), ease="ease")
    c.key(L, zpose(**arm("Left", 50, 50, 40, -4), **arm("Right", 54, 46, 40, -4)), BH, feet(), ease="ease")
    return c.write(arm_obj, name, L)


# ------------------------------------------------------------------------------------------------------------
# crawler (prone, arms pulling; hands planted = the ground moves back at 1.0 m/s)
# ------------------------------------------------------------------------------------------------------------
CRAWL = dict(speed=1.0, period=1.4, duty=0.52, reach=0.42, x=0.24, lift=0.14)


def prone_torso(pose, t, heave=1.0):
    s = math.sin(2 * math.pi * t)
    c = math.cos(2 * math.pi * t)
    s2 = math.sin(4 * math.pi * t)
    pose.rel["Hips"] = q(X, 84) @ q(Z, 5 * s * heave) @ q(Y, 3 * c)
    pose.rel["Spine"] = q(X, -6 - 2 * s2) @ q(Z, 4 * s)
    pose.rel["Chest"] = q(X, -14 - 3 * s2) @ q(Z, 8 * s) @ q(Y, -5 * c)
    pose.rel["Neck"] = q(X, -22)
    pose.rel["Head"] = q(X, -30 + 5 * s2) @ q(Z, -6 * s) @ q(Y, 8)
    pose.rel["LeftShoulder"] = q(Z, 8 + 10 * max(0.0, c))
    pose.rel["RightShoulder"] = q(Z, -8 - 10 * max(0.0, -c))
    # legs dragging (limp, alternate small kicks)
    pose.rel["LeftUpperLeg"] = q(X, 4 + 4 * s) @ q(Y, -6)
    pose.rel["RightUpperLeg"] = q(X, 4 - 4 * s) @ q(Y, 6)
    pose.rel["LeftLowerLeg"] = q(X, 18 + 10 * max(0.0, s))
    pose.rel["RightLowerLeg"] = q(X, 18 + 10 * max(0.0, -s))
    pose.rel["LeftFoot"] = q(X, 50)
    pose.rel["RightFoot"] = q(X, 50)


HAND_FLAT = {"Left": q(Z, -90), "Right": q(Z, 90)}
ARM_POLE = {"Left": Vector((1.0, 0.4, 0.8)), "Right": Vector((-1.0, 0.4, 0.8))}
ARMS = ("LeftLowerArm", "RightLowerArm", "LeftHand", "RightHand", "LeftUpperArm", "RightUpperArm")


def crawl_hand(side, t, shoulder, cr=CRAWL):
    """(wrist target, in stance) of a crawling hand at phase t (left hand plants at t = 0). The wrist sits 3 cm above
    the ground: the palm (mesh underside) touches z = 0."""
    ph = 0.0 if side == "Left" else 0.5
    u = (t - ph) % 1.0
    L = cr["speed"] * cr["period"] * cr["duty"]
    s = 1 if side == "Left" else -1
    y_front = shoulder.y - cr["reach"]
    x = s * cr["x"]
    z = 0.030
    if u < cr["duty"]:
        return Vector((x, y_front + L * (u / cr["duty"]), z)), True
    v = (u - cr["duty"]) / (1 - cr["duty"])
    y = y_front + L + (y_front - (y_front + L)) * anim.smooth(v)
    return Vector((x + s * 0.05 * math.sin(math.pi * v), y, z + cr["lift"] * math.sin(math.pi * v) ** 0.6)), False


_CRAWL_REF = {}


def crawl_setup(p, cr=CRAWL):
    """(hips z offset keeping the prone torso / legs on the ground over the cycle, mean shoulder position)."""
    key = tuple(sorted(rig.params(**(p or {})).items()))
    if key in _CRAWL_REF:
        return _CRAWL_REF[key]
    pr = rig.params(**(p or {}))
    pts = ka.body_points(pr)
    n = anim.frame_count(cr["period"])
    lo = 9.0
    for f in range(n):
        pz = anim.Pose(pr)
        prone_torso(pz, f / n)
        lo = min(lo, ka.lowest(pz, pts, skip=ARMS))
    hips_z = -lo + 0.01
    probe = anim.Pose(pr)
    prone_torso(probe, 0.0)
    probe.hips = Vector((0, 0, hips_z))
    sh = (probe.head("RightUpperArm") + probe.head("LeftUpperArm")) * 0.5
    _CRAWL_REF[key] = (hips_z, sh)
    return hips_z, sh


def crawl_pose(p, t, cr=CRAWL):
    hips_z, sh = crawl_setup(p, cr)
    pose = anim.Pose(p)
    prone_torso(pose, t)
    pose.hips = Vector((0.0, 0.0, hips_z))
    clamped = 0
    for side in SIDES:
        target, st = crawl_hand(side, t, sh, cr)
        c = anim.solve_arm(pose, side, target, ARM_POLE[side], hand_w=HAND_FLAT[side], reach=0.999)
        clamped += bool(c and st)
    return pose, clamped


def crawl(arm_obj, p, name="Zom_Crawl-loop", cr=CRAWL, seed=17):
    """Prone arm-over-arm crawl at 1.0 m/s: each palm plants in front of its shoulder and pulls back to beside the
    chest while the body stays in place (the ground moves back at the authored speed)."""
    pr = rig.params(**(p or {}))
    hips_z, sh = crawl_setup(pr, cr)
    n = anim.frame_count(cr["period"])
    w = anim.ActionWriter(arm_obj, name)
    clamped = 0
    for f in range(n + 1):
        t = f / n
        pose, _c = crawl_pose(pr, t, cr)
        ka.alive(pose, t * cr["period"], cr["period"], 0.15, seed)
        for side in SIDES:                  # re-solve the arms after the alive layer (planted palms stay exact)
            target, st = crawl_hand(side, t, sh, cr)
            c = anim.solve_arm(pose, side, target, ARM_POLE[side], hand_w=HAND_FLAT[side], reach=0.999)
            clamped += bool(c and st)
        w.pose(pose, f)
    act = w.finish(0, n, 'LINEAR')
    act["authored_speed"] = cr["speed"]
    act["period"] = cr["period"]
    act["looping"] = True
    act["ik_clamped_frames"] = clamped
    act["hips_z"] = hips_z
    return act


def crawl_key_pose(p, t=0.0):
    """Rel rotations + Hips of the crawl at phase t (base of the crawler one-shots)."""
    pr = rig.params(**(p or {}))
    pose, _c = crawl_pose(pr, t)
    return {b: pose.rel[b].copy() for b in rig.BONE_NAMES}, pose.hips.copy()


def ground_hand(side, sh, dx, dy, lift=0.0):
    """IK spec: palm flat on the ground (wrist 3 cm up) at (dx outward, dy ahead of the shoulders)."""
    sg = 1 if side == "Left" else -1
    return dict(pos=Vector((sg * dx, sh.y - dy, 0.030 + lift)), pole=ARM_POLE[side], rot=HAND_FLAT[side])


def crawl_grab(arm_obj, p, name="Zom_Crawl_Grab", L=0.8):
    """From the crawl: rear up on the left hand, the right hand lunges forward-up to an ankle (0.28 m high, 0.6 m
    ahead of the shoulders), grabs at 0.34 s and yanks back to the ground."""
    rel0, h0 = crawl_key_pose(p, 0.0)
    _hz, sh = crawl_setup(p)
    c = ka.Clip(p, base=rel0, post=post_alive(L, 18))
    lh = ground_hand("Left", sh, 0.22, 0.34)
    c.key(0.0, rel0, h0, hands={"Left": ground_hand("Left", sh, 0.24, 0.42), "Right": ground_hand("Right", sh, 0.24, 0.10)})
    c.key(0.26, dict(rel0, Chest=q(X, -30) @ q(Z, 10), Neck=q(X, -24), Head=q(X, -26) @ q(Z, -10)),
          h0 + Vector((0, 0.06, 0.05)), hands={"Left": lh, "Right": dict(pos=Vector((-0.30, sh.y - 0.10, 0.34)),
                                                                          pole=Vector((-1.0, 0.6, 0.3)))}, ease="out")
    c.key(0.36, dict(rel0, Chest=q(X, -34) @ q(Z, -12), Neck=q(X, -18), Head=q(X, -30)),
          h0 + Vector((0, -0.08, 0.08)), hands={"Left": lh, "Right": dict(pos=Vector((-0.08, sh.y - 0.62, 0.28)),
                                                                           pole=Vector((-1.0, 0.2, 0.2)))}, ease="in3")
    c.key(0.56, dict(rel0, Chest=q(X, -22) @ q(Z, -4), Neck=q(X, -20), Head=q(X, -28)),
          h0 + Vector((0, 0.03, 0.04)), hands={"Left": lh, "Right": dict(pos=Vector((-0.16, sh.y - 0.40, 0.12)),
                                                                          pole=Vector((-1.0, 0.4, 0.3)))}, ease="out")
    c.key(L, rel0, h0, hands={"Left": ground_hand("Left", sh, 0.24, 0.42), "Right": ground_hand("Right", sh, 0.24, 0.10)},
          ease="ease")
    return c.write(arm_obj, name, L)


def crawl_death(arm_obj, p, name="Zom_Crawl_Death", L=0.8):
    """From the crawl: a last reach, the arms give way (hands slide out to the sides), chest and head drop flat."""
    rel0, h0 = crawl_key_pose(p, 0.0)
    _hz, sh = crawl_setup(p)
    c = ka.Clip(p, base=rel0, post=post_alive(L, 19))
    c.key(0.0, rel0, h0, hands={"Left": ground_hand("Left", sh, 0.24, 0.42), "Right": ground_hand("Right", sh, 0.24, 0.10)})
    c.key(0.22, dict(rel0, Chest=q(X, -26), Neck=q(X, -30), Head=q(X, -40) @ q(Y, 20)), h0 + Vector((0, 0, 0.04)),
          hands={"Left": ground_hand("Left", sh, 0.28, 0.46), "Right": ground_hand("Right", sh, 0.26, 0.30)}, ease="out")
    c.key(0.50, dict(rel0, Hips=q(X, 88), Spine=q(X, 2), Chest=q(X, 2), Neck=q(X, -8), Head=q(X, -12) @ q(Z, 50)),
          h0 + Vector((0, 0, -0.06)),
          hands={"Left": ground_hand("Left", sh, 0.46, 0.34), "Right": ground_hand("Right", sh, 0.40, 0.16)},
          ground=True, ease="in")
    c.key(L, dict(rel0, Hips=q(X, 88), Spine=q(X, 2), Chest=q(X, 2), Neck=q(X, -10), Head=q(X, -12) @ q(Z, 60)),
          h0 + Vector((0, 0, -0.08)),
          hands={"Left": ground_hand("Left", sh, 0.48, 0.30), "Right": ground_hand("Right", sh, 0.42, 0.12)},
          ground=True, ease="out")
    return c.write(arm_obj, name, L)


# ------------------------------------------------------------------------------------------------------------
def build_actions(arm_obj, p=None):
    acts = [idle_a(arm_obj, p), idle_b(arm_obj, p)]
    for st in "ABCD":
        acts.append(shamble(arm_obj, p, "Zom_Shamble_%s-loop" % st, st))
    acts.append(shamble(arm_obj, p, "Zom_Investigate-loop", "I"))
    acts += [alert(arm_obj, p), attack_a(arm_obj, p), attack_b(arm_obj, p), grab_loop(arm_obj, p),
             knock_loop(arm_obj, p), hit_additive(arm_obj, p), stagger(arm_obj, p), knockdown(arm_obj, p),
             getup(arm_obj, p), death_a(arm_obj, p), death_b(arm_obj, p), frozen_idle(arm_obj, p), wake(arm_obj, p)]
    acts.append(ka.gait_cycle(arm_obj, p, "Zom_Run-loop", RUN, upper=run_upper(False)))
    acts.append(ka.gait_cycle(arm_obj, p, "Zom_Run_Tired-loop", RUN_TIRED, sides={"Right": dict(lift=0.08)},
                              upper=run_upper(True)))
    acts += [crawl(arm_obj, p), crawl_grab(arm_obj, p), crawl_death(arm_obj, p)]
    acts.append(ka.gait_cycle(arm_obj, p, "Zom_Walk_Heavy-loop", HEAVY, upper=heavy_upper))
    acts.append(bloat_pop(arm_obj, p))
    problems = []
    for act in acts:
        looping, length, speed, _kind = ZOMBIE_TABLE[act.name]
        problems += anim.check_action_name(act.name, looping)
        if int(act.frame_range[1]) != anim.frame_count(length):
            problems.append("%s: %d frames, want %d" % (act.name, act.frame_range[1], anim.frame_count(length)))
        if act.get("ik_clamped_frames", 0):
            problems.append("%s: %d frames out of IK reach" % (act.name, act["ik_clamped_frames"]))
        if abs(act.get("authored_speed", 0.0) - speed) > 1e-6:
            problems.append("%s: authored speed %s != %s" % (act.name, act.get("authored_speed"), speed))
        act["looping"] = looping
    missing = set(ZOMBIE_TABLE) - {a.name for a in acts}
    if missing:
        problems.append("missing %s" % sorted(missing))
    if problems:
        raise RuntimeError("zombie_anims: " + "; ".join(problems))
    return acts


def build():
    lp.new_scene()
    bpy.context.scene.render.fps = anim.FPS
    arm_obj = rig.build_armature()
    acts = build_actions(arm_obj)
    anim.reset_pose(arm_obj)
    glb = export.save_and_export(NAME, SUBDIR, ao=False)
    export.write_import(glb, "anim")
    ka.write_events(EVENTS_PATH, EVENTS)
    for act in acts:
        print("  %-24s frames=%-3d speed=%.1f drop=%.3f" % (act.name, act.frame_range[1],
                                                           act.get("authored_speed", 0.0), act.get("drop", 0.0)))
    return glb


def main():
    rig.write_bonemap(export.BONEMAP_PATH)
    return build()


if __name__ == "__main__":
    main()
