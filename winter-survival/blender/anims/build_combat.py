"""Player combat animation library — ASSET_SPEC_V2 §6.1/§6.2 (every M4 row: melee, shove, stomp, execute, revive, hits,
downed, death).

    cd winter-survival/blender && python3 anims/build_combat.py

Exports assets/models/anims/humanoid_combat.glb (+ sources/humanoid_combat.blend + the Godot `.import`, template
lib/export.py kind "anim") from the player-proportion armature without mesh (the survivor rest), and merges the hit
windows / events into data/anim_events.json. In-place, 30 fps, every frame keyed (LINEAR), Root never keyed.

Weapon convention (§12, identity on RightHandSocket): the hand pose of every swing is authored through the socket
frame — `shaft` = the weapon handle axis (+Z Blender of the weapon = socket Y, toward the thumb), `edge` = the weapon's
-Y Blender (blade edge / business end = socket Z): the edge leads every strike. Two-handed clips keep the left fist on
the shaft 9 cm below the right one (= SupportGrip of bat / bat_nailed). Style (§6.1): anticipation >= 0.25 s, impact
<= 0.12 s, exaggerated shoulders / head / arms. Most of the body twist lives in Spine / Chest, so the swings still read
when the code plays them through the torso filter (OneShot "action", §6.5).

COMBAT_TABLE (name -> looping, length s, authored speed, kind) is the contract verify_chars.py checks. Lengths that
are not a whole number of frames at 30 fps use the nearest frame: Melee1H_Light_A/B 17 frames (0.567 s for 0.55),
Hit_Front / Hit_Back 8 frames (0.267 s for 0.25; additive: delta from the T-pose rest, for an Add2 node).
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

from lib import anim  # noqa: E402
from lib import export  # noqa: E402
from lib import keyanim as ka  # noqa: E402
from lib import lowpoly as lp  # noqa: E402
from lib import rig  # noqa: E402
from lib.anim import X, Y, Z, q_axis as q  # noqa: E402

NAME = "humanoid_combat"
SUBDIR = "anims"
EVENTS_PATH = export.ROOT / "data" / "anim_events.json"
F17 = 17.0 / 30.0
F8 = 8.0 / 30.0

COMBAT_TABLE = {
    "Melee1H_Light_A": (False, F17, 0.0, "move"),
    "Melee1H_Light_B": (False, F17, 0.0, "move"),
    "Melee2H_Swing_A": (False, 0.9, 0.0, "move"),
    "Melee2H_Swing_B": (False, 0.9, 0.0, "move"),
    "Melee_Charged": (False, 1.3, 0.0, "move"),
    "Act_Shove": (False, 0.5, 0.0, "move"),
    "Act_Stomp": (False, 1.0, 0.0, "move"),
    "Act_Execute": (False, 1.5, 0.0, "move"),
    "Act_Revive-loop": (True, 2.0, 0.0, "ground"),
    "Hit_Front": (False, F8, 0.0, "additive"),
    "Hit_Back": (False, F8, 0.0, "additive"),
    "Hit_Stagger": (False, 0.6, 0.0, "move"),
    "Hit_Grabbed-loop": (True, 1.0, 0.0, "stand"),
    "Down_Fall": (False, 0.8, 0.0, "ground"),
    "Down_Idle-loop": (True, 2.0, 0.0, "ground"),
    "Down_Crawl-loop": (True, 1.2, 0.8, "crawl"),
    "Down_Revived": (False, 1.5, 0.0, "ground"),
    "Death_A": (False, 0.5, 0.0, "ground"),
}

EVENTS = {
    "Melee1H_Light_A": {"swing": 0.22, "hit_start": 0.27, "hit_end": 0.37},
    "Melee1H_Light_B": {"swing": 0.22, "hit_start": 0.27, "hit_end": 0.37},
    "Melee2H_Swing_A": {"swing": 0.32, "hit_start": 0.36, "hit_end": 0.48},
    "Melee2H_Swing_B": {"swing": 0.32, "hit_start": 0.36, "hit_end": 0.48},
    "Melee_Charged": {"hold_start": 0.55, "hold_end": 0.72, "swing": 0.74, "hit_start": 0.78, "hit_end": 0.90},
    "Act_Shove": {"hit_start": 0.25, "hit_end": 0.36},
    "Act_Stomp": {"hit_start": 0.46, "hit_end": 0.56, "stomp": 0.50},
    "Act_Execute": {"grab": 0.35, "stab": 0.70, "stab_2": 1.00, "kill": 1.00},
    "Act_Revive-loop": {"press_1": 0.5, "press_2": 1.5},
    "Down_Fall": {"knees": 0.36, "ground": 0.62},
    "Down_Revived": {"stand": 1.20},
    "Death_A": {"ragdoll": 0.35},
    "Down_Crawl-loop": {"hand_l": 0.0, "hand_r": 0.6},
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


def V(*a):
    return Vector(a).normalized() if len(a) == 3 else Vector(a[0]).normalized()


def grip(pos, shaft, edge, pole=None):
    d = dict(grip=Vector(pos), shaft=V(*shaft), edge=V(*edge))
    if pole is not None:
        d["pole"] = Vector(pole)
    return d


# ------------------------------------------------------------------------------------------------------------
# stances
# ------------------------------------------------------------------------------------------------------------
def pbase():
    r = anim.rest_pose()
    r.update({"Hips": q(Z, -6), "Spine": q(X, 4) @ q(Z, 3), "Chest": q(X, 3) @ q(Z, 3), "Head": q(X, -2) @ q(Z, 4)})
    r.update(arm("Left", 70, 20, 40, -8))
    return r


READY_FEET = {"Left": dict(dy=-0.09, dx=0.03, yaw=4), "Right": dict(dy=0.10, dx=0.04, yaw=18)}
READY_HIPS = (0.0, 0.02, -0.05)
READY_GRIP = grip((-0.23, -0.30, 1.02), (0.0, -0.55, 0.83), (0.0, -0.83, -0.55), (-0.6, 0.6, -0.8))
READY_2H = grip((-0.10, -0.34, 1.02), (0.12, -0.55, 0.83), (0.0, -0.83, -0.55), (-0.7, 0.5, -0.6))


def feet(ldy=None, rdy=None, **kw):
    f = {"Left": dict(READY_FEET["Left"]), "Right": dict(READY_FEET["Right"])}
    if ldy is not None:
        f["Left"]["dy"] = ldy
    if rdy is not None:
        f["Right"]["dy"] = rdy
    for k, v in kw.items():
        side, key = k.split("_")
        f["Left" if side == "l" else "Right"][key] = v
    return f


def pp(**over):
    r = pbase()
    r.update(over)
    return r


def clip(p=None, length=1.0, seed=0, base=None, post=None, support=0.09):
    layers = [lambda t, pose: ka.alive(pose, t, length, 0.25, seed)]
    if post:
        layers.append(post)

    def run(t, pose):
        for f in layers:
            f(t, pose)
    return ka.Clip(p, base=pbase() if base is None else base, post=run, support=support)


# ------------------------------------------------------------------------------------------------------------
# one-handed light attacks
# ------------------------------------------------------------------------------------------------------------
def light_a(arm_obj, p, name="Melee1H_Light_A", L=F17):
    """Forehand diagonal slash, upper right -> lower left. Wind-up 0 -> 0.25, strike 0.25 -> 0.35 (hit 0.27-0.37)."""
    c = clip(p, L, 21)
    c.key(0.0, pbase(), READY_HIPS, feet(), {"Right": READY_GRIP})
    c.key(0.25, pp(Hips=q(Z, -22), Spine=q(X, -2) @ q(Z, -16), Chest=q(X, -6) @ q(Z, -22), Neck=q(Z, 10),
                   Head=q(X, -4) @ q(Z, 16), RightShoulder=q(Y, -10) @ q(Z, -10), **arm("Left", 58, 56, 40, -6)),
          (0.02, 0.06, -0.06), feet(-0.05, 0.14, r_heel=12),
          {"Right": grip((-0.34, 0.06, 1.62), (-0.35, 0.55, 0.75), (0.45, -0.5, 0.25), (-1.0, 0.5, -0.3))}, ease="out")
    c.key(0.35, pp(Hips=q(Z, 12), Spine=q(X, 8) @ q(Z, 12), Chest=q(X, 12) @ q(Z, 22), Neck=q(Z, -8),
                   Head=q(X, 2) @ q(Z, -12), RightShoulder=q(Y, 2) @ q(Z, 12), **arm("Left", 76, -20, 30, -8)),
          (-0.02, -0.08, -0.09), feet(-0.22, 0.12),
          {"Right": grip((-0.02, -0.58, 1.12), (0.55, -0.75, -0.2), (0.6, 0.25, -0.75), (-0.8, 0.4, -0.6))}, ease="in")
    c.key(0.43, pp(Hips=q(Z, 18), Spine=q(X, 10) @ q(Z, 16), Chest=q(X, 14) @ q(Z, 28), Neck=q(Z, -10),
                   Head=q(X, 4) @ q(Z, -14), RightShoulder=q(Y, 4) @ q(Z, 14), **arm("Left", 80, -26, 26, -8)),
          (-0.03, -0.09, -0.10), feet(-0.22, 0.12),
          {"Right": grip((0.24, -0.34, 0.86), (0.75, 0.1, -0.65), (0.2, 0.3, -0.9), (-0.4, 0.3, -1.0))}, ease="out")
    c.key(L, pbase(), READY_HIPS, feet(), {"Right": READY_GRIP}, ease="ease")
    return c.write(arm_obj, name, L)


def light_b(arm_obj, p, name="Melee1H_Light_B", L=F17):
    """Backhand slash, left -> right at chest height (the return swing)."""
    c = clip(p, L, 22)
    c.key(0.0, pbase(), READY_HIPS, feet(), {"Right": READY_GRIP})
    c.key(0.25, pp(Hips=q(Z, 14), Spine=q(X, 6) @ q(Z, 16), Chest=q(X, 8) @ q(Z, 26), Neck=q(Z, -12),
                   Head=q(X, 2) @ q(Z, -18), RightShoulder=q(Y, 6) @ q(Z, 16), **arm("Left", 76, -10, 30, -6)),
          (-0.01, 0.02, -0.07), feet(-0.12, 0.12),
          {"Right": grip((0.20, -0.12, 1.34), (0.8, 0.45, 0.35), (-0.3, -0.2, 0.9), (0.2, 0.8, -0.6))}, ease="out")
    c.key(0.35, pp(Hips=q(Z, -10), Spine=q(X, 6) @ q(Z, -10), Chest=q(X, 8) @ q(Z, -18), Neck=q(Z, 8),
                   Head=q(X, 0) @ q(Z, 12), RightShoulder=q(Y, -4) @ q(Z, -6), **arm("Left", 64, 30, 40, -6)),
          (0.0, -0.08, -0.08), feet(-0.22, 0.10),
          {"Right": grip((-0.10, -0.60, 1.22), (-0.55, -0.83, 0.05), (-0.85, 0.5, 0.0), (-0.9, 0.3, -0.4))}, ease="in")
    c.key(0.43, pp(Hips=q(Z, -20), Spine=q(X, 4) @ q(Z, -16), Chest=q(X, 4) @ q(Z, -28), Neck=q(Z, 12),
                   Head=q(X, 0) @ q(Z, 18), RightShoulder=q(Y, -8) @ q(Z, -12), **arm("Left", 60, 44, 44, -6)),
          (0.01, -0.06, -0.08), feet(-0.22, 0.10),
          {"Right": grip((-0.48, -0.22, 1.14), (-0.85, 0.35, 0.2), (0.0, 0.3, -0.9), (-0.8, 0.6, -0.4))}, ease="out")
    c.key(L, pbase(), READY_HIPS, feet(), {"Right": READY_GRIP}, ease="ease")
    return c.write(arm_obj, name, L)


# ------------------------------------------------------------------------------------------------------------
# two-handed swings
# ------------------------------------------------------------------------------------------------------------
BASE2H = None


def base2h():
    return pp(Hips=q(Z, -14), Spine=q(X, 4) @ q(Z, -4), Chest=q(X, 4) @ q(Z, -6), Head=q(X, -2) @ q(Z, 10))


def swing_a(arm_obj, p, name="Melee2H_Swing_A", L=0.9):
    """Overhead two-handed chop: wind-up 0 -> 0.30 (weapon behind the head), strike 0.30 -> 0.42, follow-through,
    recover. Left fist rides the shaft."""
    c = clip(p, L, 23, base=base2h())
    c.key(0.0, base2h(), READY_HIPS, feet(), {"Right": READY_2H}, two_hand=True)
    c.key(0.30, pp(Hips=q(X, -6) @ q(Z, -8), Spine=q(X, -8) @ q(Z, -6), Chest=q(X, -12) @ q(Z, -8), Neck=q(X, 6),
                   Head=q(X, 6) @ q(Z, 6), LeftShoulder=q(Y, -12), RightShoulder=q(Y, 12)),
          (0.0, 0.05, -0.05), feet(-0.10, 0.12, l_heel=8),
          {"Right": grip((-0.06, 0.00, 1.84), (0.05, 0.55, 0.83), (0.0, -0.83, 0.55), (-1.0, 0.2, 0.2))},
          two_hand=True, ease="out")
    c.key(0.42, pp(Hips=q(X, 10) @ q(Z, 4), Spine=q(X, 14) @ q(Z, 2), Chest=q(X, 20) @ q(Z, 4), Neck=q(X, -6),
                   Head=q(X, -8), LeftShoulder=q(Y, 6), RightShoulder=q(Y, -6)),
          (0.0, -0.08, -0.12), feet(-0.30, 0.12),
          {"Right": grip((-0.06, -0.52, 1.00), (0.05, -0.80, -0.60), (0.0, 0.6, -0.8), (-1.0, 0.4, -0.5))},
          two_hand=True, ease="in")
    c.key(0.55, pp(Hips=q(X, 14) @ q(Z, 6), Spine=q(X, 18) @ q(Z, 4), Chest=q(X, 24) @ q(Z, 6), Neck=q(X, -8),
                   Head=q(X, -10), LeftShoulder=q(Y, 8), RightShoulder=q(Y, -8)),
          (0.0, -0.10, -0.14), feet(-0.30, 0.12),
          {"Right": grip((-0.05, -0.46, 0.80), (0.05, -0.55, -0.83), (0.0, 0.83, -0.55), (-1.0, 0.4, -0.6))},
          two_hand=True, ease="out")
    c.key(L, base2h(), READY_HIPS, feet(), {"Right": READY_2H}, two_hand=True, ease="ease")
    return c.write(arm_obj, name, L)


def swing_b(arm_obj, p, name="Melee2H_Swing_B", L=0.9):
    """Horizontal two-handed swing right -> left at waist height (bat swing / chopping a trunk)."""
    c = clip(p, L, 24, base=base2h())
    c.key(0.0, base2h(), READY_HIPS, feet(), {"Right": READY_2H}, two_hand=True)
    c.key(0.30, pp(Hips=q(Z, -30), Spine=q(X, 2) @ q(Z, -20), Chest=q(X, 0) @ q(Z, -30), Neck=q(Z, 18),
                   Head=q(X, 0) @ q(Z, 30), LeftShoulder=q(Z, -12), RightShoulder=q(Y, -6)),
          (0.03, 0.06, -0.08), feet(-0.10, 0.14, l_heel=14),
          {"Right": grip((-0.26, 0.10, 1.38), (-0.25, 0.65, 0.72), (0.5, -0.6, 0.3), (-1.0, 0.6, -0.4))},
          two_hand=True, ease="out")
    c.key(0.42, pp(Hips=q(Z, 10), Spine=q(X, 8) @ q(Z, 8), Chest=q(X, 10) @ q(Z, 12), Neck=q(Z, -4),
                   Head=q(X, 0) @ q(Z, -8), LeftShoulder=q(Z, 6), RightShoulder=q(Z, 10)),
          (-0.02, -0.06, -0.12), feet(-0.30, 0.12),
          {"Right": grip((-0.02, -0.46, 1.05), (0.35, -0.94, 0.0), (0.94, 0.35, 0.0), (-1.0, 0.3, -0.6))},
          two_hand=True, ease="in")
    c.key(0.56, pp(Hips=q(Z, 24), Spine=q(X, 8) @ q(Z, 18), Chest=q(X, 8) @ q(Z, 28), Neck=q(Z, -8),
                   Head=q(X, 0) @ q(Z, -14), LeftShoulder=q(Z, 10), RightShoulder=q(Z, 16)),
          (-0.03, -0.06, -0.12), feet(-0.30, 0.12, r_heel=20),
          {"Right": grip((0.28, -0.26, 1.10), (0.85, 0.45, 0.1), (0.4, -0.85, 0.0), (-0.3, 0.6, -0.8))},
          two_hand=True, ease="out")
    c.key(L, base2h(), READY_HIPS, feet(), {"Right": READY_2H}, two_hand=True, ease="ease")
    return c.write(arm_obj, name, L)


def charged(arm_obj, p, name="Melee_Charged", L=1.3):
    """Held power attack: slow coil 0 -> 0.55, hold 0.55 -> 0.72 (the code may pause here while charging), heavy
    diagonal slam 0.72 -> 0.84, deep follow-through, recover."""
    def tremble(t, pose):
        env = 1.0 if 0.5 < t < 0.74 else 0.0
        pose.rel["Chest"] = pose.rel["Chest"] @ q(Z, 0.8 * env * math.sin(2 * math.pi * 14 * t))
    c = clip(p, L, 25, post=tremble)
    coil = pp(Hips=q(X, -4) @ q(Z, -30), Spine=q(X, -6) @ q(Z, -20), Chest=q(X, -12) @ q(Z, -30), Neck=q(Z, 16),
              Head=q(X, -2) @ q(Z, 26), RightShoulder=q(Y, -16) @ q(Z, -14), **arm("Left", 40, 74, 10, 0))
    wind = grip((-0.34, 0.16, 1.86), (-0.25, 0.7, 0.66), (0.4, -0.55, 0.35), (-1.0, 0.5, 0.2))
    c.key(0.0, pbase(), READY_HIPS, feet(), {"Right": READY_GRIP})
    c.key(0.55, coil, (0.03, 0.08, -0.10), feet(-0.10, 0.16, l_heel=10), {"Right": wind}, ease="out")
    c.key(0.72, coil, (0.03, 0.09, -0.11), feet(-0.10, 0.16, l_heel=10), {"Right": wind}, ease="ease")
    c.key(0.84, pp(Hips=q(X, 10) @ q(Z, 14), Spine=q(X, 16) @ q(Z, 12), Chest=q(X, 22) @ q(Z, 24), Neck=q(Z, -10),
                   Head=q(X, -6) @ q(Z, -12), RightShoulder=q(Y, 6) @ q(Z, 14), **arm("Left", 80, -30, 30, -8)),
          (-0.02, -0.14, -0.16), feet(-0.36, 0.12, r_heel=18),
          {"Right": grip((0.04, -0.58, 0.96), (0.45, -0.78, -0.45), (0.5, 0.2, -0.85), (-0.8, 0.4, -0.6))}, ease="in3")
    c.key(0.98, pp(Hips=q(X, 12) @ q(Z, 22), Spine=q(X, 18) @ q(Z, 16), Chest=q(X, 24) @ q(Z, 30), Neck=q(Z, -12),
                   Head=q(X, -6) @ q(Z, -16), RightShoulder=q(Y, 8) @ q(Z, 16), **arm("Left", 82, -34, 26, -8)),
          (-0.03, -0.14, -0.17), feet(-0.36, 0.12, r_heel=20),
          {"Right": grip((0.30, -0.30, 0.74), (0.7, 0.1, -0.7), (0.3, 0.4, -0.85), (-0.4, 0.3, -1.0))}, ease="out")
    c.key(L, pbase(), READY_HIPS, feet(), {"Right": READY_GRIP}, ease="ease")
    return c.write(arm_obj, name, L)


# ------------------------------------------------------------------------------------------------------------
# shove, stomp, execute
# ------------------------------------------------------------------------------------------------------------
def shove(arm_obj, p, name="Act_Shove", L=0.5):
    """Two-handed push: pull in 0 -> 0.25 (anticipation), shove 0.25 -> 0.33, hold, recover."""
    c = clip(p, L, 26)
    c.key(0.0, pbase(), READY_HIPS, feet(), {"Right": READY_GRIP})
    c.key(0.25, pp(Hips=q(X, -4), Spine=q(X, -4), Chest=q(X, -8), Head=q(X, -4), LeftShoulder=q(Z, 10),
                   RightShoulder=q(Z, -10)), (0.0, 0.07, -0.07), feet(-0.08, 0.14),
          {"Right": dict(pos=Vector((-0.17, -0.14, 1.26)), pole=Vector((-0.8, 0.8, -0.6))),
           "Left": dict(pos=Vector((0.17, -0.14, 1.26)), pole=Vector((0.8, 0.8, -0.6)))}, ease="out")
    c.key(0.33, pp(Hips=q(X, 8), Spine=q(X, 10), Chest=q(X, 14), Head=q(X, -10), LeftShoulder=q(Z, -12),
                   RightShoulder=q(Z, 12)), (0.0, -0.14, -0.08), feet(-0.34, 0.12, r_heel=16),
          {"Right": dict(pos=Vector((-0.17, -0.66, 1.28)), pole=Vector((-1.0, 0.2, -0.6))),
           "Left": dict(pos=Vector((0.17, -0.66, 1.28)), pole=Vector((1.0, 0.2, -0.6)))}, ease="in")
    c.key(0.40, pp(Hips=q(X, 8), Spine=q(X, 10), Chest=q(X, 12), Head=q(X, -8)), (0.0, -0.12, -0.08),
          feet(-0.34, 0.12, r_heel=10),
          {"Right": dict(pos=Vector((-0.18, -0.62, 1.24)), pole=Vector((-1.0, 0.2, -0.6))),
           "Left": dict(pos=Vector((0.18, -0.62, 1.24)), pole=Vector((1.0, 0.2, -0.6)))}, ease="out")
    c.key(L, pbase(), READY_HIPS, feet(), {"Right": READY_GRIP}, ease="ease")
    return c.write(arm_obj, name, L)


def stomp(arm_obj, p, name="Act_Stomp", L=1.0):
    """Knee high 0 -> 0.40, stomp 0.40 -> 0.50 on a downed target 0.4 m ahead, grind, recover."""
    c = clip(p, L, 27)
    c.key(0.0, pbase(), READY_HIPS, feet(), {"Right": READY_GRIP})
    c.key(0.40, pp(Hips=q(X, -6), Spine=q(X, -4), Chest=q(X, -6), Head=q(X, 14), RightUpperLeg=q(X, -80),
                   RightLowerLeg=q(X, 86), RightFoot=q(X, -10), **arm("Left", 40, 30, 40, -20)),
          (0.0, 0.02, -0.04), {"Left": dict(dy=-0.02, dx=0.02, yaw=4)},
          {"Right": grip((-0.40, -0.08, 1.20), (-0.3, -0.3, 0.9), (-0.9, 0.0, -0.3), (-0.8, 0.6, -0.4))}, ease="out")
    c.key(0.50, pp(Hips=q(X, 10), Spine=q(X, 12), Chest=q(X, 14), Head=q(X, 24), **arm("Left", 70, 10, 20, -10)),
          (0.0, -0.10, -0.12), feet(-0.02, -0.32, r_yaw=0),
          {"Right": grip((-0.34, -0.12, 0.98), (0.0, -0.55, 0.83), (-0.2, -0.83, -0.5), (-0.8, 0.6, -0.8))}, ease="in3")
    c.key(0.64, pp(Hips=q(X, 12) @ q(Z, 8), Spine=q(X, 14), Chest=q(X, 14) @ q(Z, 6), Head=q(X, 26),
                   **arm("Left", 72, 10, 24, -10)), (0.0, -0.11, -0.14), feet(-0.02, -0.32, r_yaw=14),
          {"Right": grip((-0.34, -0.14, 0.96), (0.0, -0.55, 0.83), (-0.2, -0.83, -0.5), (-0.8, 0.6, -0.8))}, ease="ease")
    c.key(L, pbase(), READY_HIPS, feet(), {"Right": READY_GRIP}, ease="ease")
    return c.write(arm_obj, name, L)


def execute(arm_obj, p, name="Act_Execute", L=1.5):
    """Silent knife execution of a standing / frozen zombie 0.5 m ahead: step in and grab the head (0.35), raise,
    stab down into the neck (0.70), second stab (1.00), release, recover."""
    c = clip(p, L, 28)
    grab = dict(pos=Vector((0.06, -0.50, 1.52)), pole=Vector((1.0, 0.3, -0.4)))
    up = grip((-0.22, -0.26, 1.74), (0.0, -0.35, -0.94), (0.0, -0.94, 0.35), (-1.0, 0.3, 0.0))
    stab = grip((-0.04, -0.50, 1.48), (0.1, -0.55, -0.83), (0.0, -0.83, 0.55), (-1.0, 0.2, -0.4))
    c.key(0.0, pbase(), READY_HIPS, feet(), {"Right": READY_GRIP})
    c.key(0.35, pp(Hips=q(X, 4), Spine=q(X, 6), Chest=q(X, 8) @ q(Z, 6), Head=q(X, 6) @ q(Z, -6)),
          (0.0, -0.14, -0.06), feet(-0.34, 0.08), {"Right": up, "Left": grab}, ease="ease")
    c.key(0.58, pp(Hips=q(X, 2), Spine=q(X, 2), Chest=q(X, -2) @ q(Z, -6), Head=q(X, 4)),
          (0.0, -0.12, -0.04), feet(-0.34, 0.08), {"Right": grip((-0.24, -0.20, 1.86), (0.0, -0.2, -0.98),
                                                               (0.0, -0.98, 0.2), (-1.0, 0.3, 0.2)), "Left": grab},
          ease="out")
    c.key(0.70, pp(Hips=q(X, 8), Spine=q(X, 10), Chest=q(X, 14) @ q(Z, 6), Head=q(X, 12)),
          (0.0, -0.16, -0.10), feet(-0.34, 0.08), {"Right": stab, "Left": grab}, ease="in3")
    c.key(0.86, pp(Hips=q(X, 4), Spine=q(X, 6), Chest=q(X, 6), Head=q(X, 8)),
          (0.0, -0.14, -0.07), feet(-0.34, 0.08), {"Right": up, "Left": grab}, ease="out")
    c.key(1.00, pp(Hips=q(X, 8), Spine=q(X, 10), Chest=q(X, 14) @ q(Z, 6), Head=q(X, 12)),
          (0.0, -0.16, -0.10), feet(-0.34, 0.08), {"Right": stab, "Left": grab}, ease="in3")
    c.key(1.18, pp(Hips=q(X, 6), Spine=q(X, 6), Chest=q(X, 8), Head=q(X, 16)), (0.0, -0.12, -0.10),
          feet(-0.34, 0.08), {"Right": grip((-0.20, -0.38, 1.30), (0.0, -0.55, -0.83), (0.0, -0.83, 0.55),
                                            (-1.0, 0.3, -0.4)),
                              "Left": dict(pos=Vector((0.20, -0.42, 1.20)), pole=Vector((1.0, 0.3, -0.6)))},
          ease="ease")
    c.key(L, pbase(), READY_HIPS, feet(), {"Right": READY_GRIP}, ease="ease")
    return c.write(arm_obj, name, L)


# ------------------------------------------------------------------------------------------------------------
# hits
# ------------------------------------------------------------------------------------------------------------
def hit_add(arm_obj, p, name, sign, L=F8, seed=30):
    """Additive flinch (delta from the T-pose rest): sign +1 = hit from the front (snap back), -1 = from behind."""
    k = sign
    c = ka.Clip(p, base={}, post=lambda t, pose: ka.alive(pose, t, L, 0.15, seed))
    c.key(0.0, {}, (0, 0, 0))
    c.key(0.06, {"Hips": q(X, -4 * k), "Spine": q(X, -6 * k) @ q(Z, 3), "Chest": q(X, -10 * k) @ q(Z, 4),
                 "Neck": q(X, -5 * k), "Head": q(X, -14 * k) @ q(Y, -5), "LeftShoulder": q(Y, -5), "RightShoulder": q(Y, 5),
                 "LeftUpperArm": q(X, 10 * k), "RightUpperArm": q(X, 10 * k), "LeftLowerArm": q(Z, -8),
                 "RightLowerArm": q(Z, 8), "LeftUpperLeg": q(X, -3 * k), "RightUpperLeg": q(X, 2 * k),
                 "LeftLowerLeg": q(X, 4), "RightLowerLeg": q(X, 3)}, (0.0, 0.025 * k, -0.01), ease="out3")
    c.key(0.15, {"Spine": q(X, -2 * k), "Chest": q(X, -3 * k), "Head": q(X, -5 * k)}, (0.0, 0.01 * k, 0.0))
    c.key(L, {}, (0, 0, 0))
    return c.write(arm_obj, name, L)


def stagger(arm_obj, p, name="Hit_Stagger", L=0.6):
    """Big hit: torso thrown back, arms up, step back to catch the balance, recover (in place)."""
    c = clip(p, L, 31)
    c.key(0.0, pbase(), READY_HIPS, feet(), {"Right": READY_GRIP})
    c.key(0.12, pp(Hips=q(X, -8) @ q(Z, 8), Spine=q(X, -8) @ q(Z, 6), Chest=q(X, -12) @ q(Z, 10), Neck=q(X, -8),
                   Head=q(X, -20) @ q(Y, -10), **arm("Left", 40, 36, 60, -20)), (0.0, 0.10, -0.08),
          feet(-0.09, 0.10, l_heel=14), {"Right": grip((-0.40, -0.10, 1.30), (-0.3, -0.2, 0.95), (-0.9, 0.3, -0.2),
                                                       (-0.8, 0.6, -0.4))}, ease="out3")
    c.key(0.30, pp(Hips=q(X, 2), Spine=q(X, 4), Chest=q(X, 6), Head=q(X, -6) @ q(Y, -4),
                   **arm("Left", 56, 30, 40, -14)), (0.0, 0.14, -0.13), feet(0.02, 0.36),
          {"Right": grip((-0.34, -0.14, 1.12), (-0.1, -0.5, 0.85), (-0.2, -0.85, -0.5), (-0.8, 0.6, -0.6))}, ease="ease")
    c.key(0.45, pp(Head=q(X, -4)), (0.0, 0.06, -0.08), feet(-0.04, 0.22), {"Right": READY_GRIP}, ease="ease")
    c.key(L, pbase(), READY_HIPS, feet(), {"Right": READY_GRIP}, ease="ease")
    return c.write(arm_obj, name, L)


def grabbed_loop(arm_obj, p, name="Hit_Grabbed-loop", L=1.0):
    """Struggling against a zombie holding the player: forearms pushing its chest away, torso twisting, head away."""
    c = clip(p, L, 32)
    push = lambda dx, dy, dz: {  # noqa: E731
        "Right": dict(pos=Vector((-0.16 + dx, -0.40 + dy, 1.32 + dz)), pole=Vector((-1.0, 0.4, -0.5))),
        "Left": dict(pos=Vector((0.16 + dx, -0.40 - dy, 1.30 - dz)), pole=Vector((1.0, 0.4, -0.5)))}
    c.key(0.0, pp(Hips=q(X, -6), Spine=q(X, -8) @ q(Z, 10), Chest=q(X, -10) @ q(Z, 12), Neck=q(Z, -10),
                  Head=q(X, -12) @ q(Z, -24)), (0.0, 0.06, -0.08), feet(-0.02, 0.20), push(0.0, -0.02, 0.0))
    c.key(0.5, pp(Hips=q(X, -4), Spine=q(X, -6) @ q(Z, -10), Chest=q(X, -8) @ q(Z, -12), Neck=q(Z, 10),
                  Head=q(X, -14) @ q(Z, 24)), (0.0, 0.04, -0.09), feet(-0.02, 0.20), push(0.0, 0.03, 0.02),
          ease="sine")
    c.close(L, ease="sine")
    return c.write(arm_obj, name, L, looping=True)


# ------------------------------------------------------------------------------------------------------------
# downed (prone, propped on the forearms) + revive
# ------------------------------------------------------------------------------------------------------------
def prone_rel(t=0.0, heave=1.0):
    s = math.sin(2 * math.pi * t)
    br = math.sin(4 * math.pi * t)
    r = pbase()
    r.update({"Hips": q(X, 86) @ q(Z, 3 * s), "Spine": q(X, -8 - 1.5 * br * heave), "Chest": q(X, -22 - 2 * br * heave),
              "Neck": q(X, -22), "Head": q(X, -26 + 3 * br) @ q(Z, 10 * s),
              "LeftUpperLeg": q(X, 2) @ q(Y, -8), "RightUpperLeg": q(X, 0) @ q(Y, 8),
              "LeftLowerLeg": q(X, 14 + 20 * max(0.0, s)), "RightLowerLeg": q(X, 10), "LeftFoot": q(X, 46),
              "RightFoot": q(X, 50)})
    return r


FOREARM = {"Left": q(Z, -90) @ q(X, 0), "Right": q(Z, 90)}


def prone_arms(pose, sh_ref, spread=0.20, fwd=0.30):
    """Forearms on the ground in front of the shoulders (elbows down): the wrist 3.5 cm above the ground."""
    for side in SIDES:
        s = 1 if side == "Left" else -1
        target = Vector((s * spread, sh_ref.y - fwd, 0.035))
        anim.solve_arm(pose, side, target, Vector((s * 0.4, 0.5, -1.0)), hand_w=FOREARM[side], reach=0.999)


def prone_setup(p):
    pr = rig.params(**(p or {}))
    pts = ka.body_points(pr)
    lo = 9.0
    for f in range(60):
        pz = anim.Pose(pr)
        for b, qq in prone_rel(f / 60).items():
            pz.rel[b] = qq.copy()
        lo = min(lo, ka.lowest(pz, pts, skip=("LeftLowerArm", "RightLowerArm", "LeftHand", "RightHand",
                                               "LeftUpperArm", "RightUpperArm")))
    hz = -lo + 0.12                      # chest propped up on the forearms
    pz = anim.Pose(pr)
    for b, qq in prone_rel(0.0).items():
        pz.rel[b] = qq.copy()
    pz.hips = Vector((0, 0, hz))
    sh = (pz.head("LeftUpperArm") + pz.head("RightUpperArm")) * 0.5
    return hz, sh


def down_idle(arm_obj, p, name="Down_Idle-loop", L=2.0):
    """Downed: prone, propped on the forearms, head up, heavy breathing, one knee dragging."""
    pr = rig.params(**(p or {}))
    hz, sh = prone_setup(pr)

    def fn(tt, pose):
        u = tt / L
        for b, qq in prone_rel(u).items():
            pose.rel[b] = qq.copy()
        pose.hips = Vector((0.0, 0.0, hz + 0.015 * math.sin(4 * math.pi * u)))
        ka.alive(pose, tt, L, 0.2, 33)
        prone_arms(pose, sh)
        return None
    return ka.procedural(arm_obj, pr, name, L, fn)


def prone_pose(p, t=0.0):
    pr = rig.params(**(p or {}))
    hz, sh = prone_setup(pr)
    pose = anim.Pose(pr)
    for b, qq in prone_rel(t).items():
        pose.rel[b] = qq.copy()
    pose.hips = Vector((0.0, 0.0, hz))
    prone_arms(pose, sh)
    return {b: pose.rel[b].copy() for b in rig.BONE_NAMES}, pose.hips.copy()


DCRAWL = dict(speed=0.8, period=1.2, duty=0.55, reach=0.40, x=0.22, lift=0.10)


def down_crawl(arm_obj, p, name="Down_Crawl-loop", cr=DCRAWL):
    """Army crawl at 0.8 m/s: forearms alternate pulling (palms planted, moving back at the authored speed), the knee
    on the pulling side draws up."""
    pr = rig.params(**(p or {}))
    hz, sh = prone_setup(pr)
    hz -= 0.06
    n = anim.frame_count(cr["period"])
    L = cr["speed"] * cr["period"] * cr["duty"]
    w = anim.ActionWriter(arm_obj, name)
    clamped = 0
    for f in range(n + 1):
        t = f / n
        pose = anim.Pose(pr)
        for b, qq in prone_rel(t, 0.5).items():
            pose.rel[b] = qq.copy()
        s = math.sin(2 * math.pi * t)
        pose.rel["Chest"] = pose.rel["Chest"] @ q(Z, 8 * s)
        pose.rel["LeftUpperLeg"] = q(X, -20 * max(0.0, s)) @ q(Y, -10 - 14 * max(0.0, s))
        pose.rel["RightUpperLeg"] = q(X, -20 * max(0.0, -s)) @ q(Y, 10 + 14 * max(0.0, -s))
        pose.rel["LeftLowerLeg"] = q(X, 20 + 50 * max(0.0, s))
        pose.rel["RightLowerLeg"] = q(X, 20 + 50 * max(0.0, -s))
        pose.hips = Vector((0.0, 0.0, hz))
        ka.alive(pose, t * cr["period"], cr["period"], 0.15, 34)
        for side in SIDES:
            ph = 0.0 if side == "Left" else 0.5
            u = (t - ph) % 1.0
            sg = 1 if side == "Left" else -1
            y_front = sh.y - cr["reach"]
            if u < cr["duty"]:
                target, st = Vector((sg * cr["x"], y_front + L * u / cr["duty"], 0.03)), True
            else:
                v = (u - cr["duty"]) / (1 - cr["duty"])
                target = Vector((sg * (cr["x"] + 0.04 * math.sin(math.pi * v)), y_front + L - L * anim.smooth(v),
                                 0.03 + cr["lift"] * math.sin(math.pi * v) ** 0.6))
                st = False
            c = anim.solve_arm(pose, side, target, Vector((sg * 0.6, 0.5, -0.9)), hand_w=FOREARM[side], reach=0.999)
            clamped += bool(c and st)
        w.pose(pose, f)
    act = w.finish(0, n, 'LINEAR')
    act["authored_speed"] = cr["speed"]
    act["period"] = cr["period"]
    act["looping"] = True
    act["ik_clamped_frames"] = clamped
    return act


def down_fall(arm_obj, p, name="Down_Fall", L=0.8):
    """Standing -> knees buckle (both knees down at 0.36) -> falls forward onto the forearms (downed pose)."""
    rel_end, h_end = prone_pose(p, 0.0)
    c = clip(p, L, 35)
    c.key(0.0, pbase(), READY_HIPS, feet(), {"Right": READY_GRIP})
    c.key(0.18, pp(Hips=q(X, 10), Spine=q(X, 14), Chest=q(X, 18), Head=q(X, 16) @ q(Z, 10),
                   **arm("Left", 84, 10, 20, -6), **arm("Right", 84, 12, 24, -6)),
          (0.0, 0.0, -0.22), feet(-0.07, 0.10, l_heel=10, r_heel=10), ease="out")
    c.key(0.36, pp(Hips=q(X, 6), Spine=q(X, 14), Chest=q(X, 16), Head=q(X, 20), LeftUpperLeg=q(X, 10),
                   RightUpperLeg=q(X, 12), LeftLowerLeg=q(X, 100), RightLowerLeg=q(X, 100), LeftFoot=q(X, 40),
                   RightFoot=q(X, 40), **arm("Left", 70, 40, 20, -4), **arm("Right", 70, 40, 24, -4)),
          (0.0, 0.0, -0.45), None, ground=True, ease="in")
    c.key(0.56, pp(Hips=q(X, 50), Spine=q(X, 10), Chest=q(X, 4), Neck=q(X, -10), Head=q(X, -20),
                   LeftUpperLeg=q(X, -20), RightUpperLeg=q(X, -16), LeftLowerLeg=q(X, 80), RightLowerLeg=q(X, 70),
                   LeftFoot=q(X, 40), RightFoot=q(X, 40), **arm("Left", 50, 80, 30, 0), **arm("Right", 50, 80, 30, 0)),
          (0.0, -0.20, -0.60), None, ground=True, ease="in")
    c.key(L, rel_end, h_end, None, ground=True, ease="out")
    return c.write(arm_obj, name, L)


def down_revived(arm_obj, p, name="Down_Revived", L=1.5):
    """Downed pose -> push up to the knees (0.6) -> one foot planted (0.9) -> stand (1.2) -> ready stance."""
    rel0, h0 = prone_pose(p, 0.0)
    c = clip(p, L, 36)
    c.key(0.0, rel0, h0, None, ground=True)
    c.key(0.35, pp(Hips=q(X, 60), Spine=q(X, 8), Chest=q(X, 4), Neck=q(X, -12), Head=q(X, -20),
                   LeftUpperLeg=q(X, -40), RightUpperLeg=q(X, -30), LeftLowerLeg=q(X, 110), RightLowerLeg=q(X, 100),
                   LeftFoot=q(X, 40), RightFoot=q(X, 40), **arm("Left", 70, 70, 10, 0), **arm("Right", 70, 70, 10, 0)),
          (0.0, -0.10, -0.55), None, ground=True, ease="ease")
    c.key(0.60, pp(Hips=q(X, 16), Spine=q(X, 12), Chest=q(X, 10), Head=q(X, 4), LeftUpperLeg=q(X, 4),
                   RightUpperLeg=q(X, 4), LeftLowerLeg=q(X, 100), RightLowerLeg=q(X, 100), LeftFoot=q(X, 40),
                   RightFoot=q(X, 40), **arm("Left", 80, 20, 30, -4), **arm("Right", 80, 20, 30, -4)),
          (0.0, 0.0, -0.45), None, ground=True, ease="ease")
    c.key(0.90, pp(Hips=q(X, 16), Spine=q(X, 14), Chest=q(X, 10), Head=q(X, 4), RightUpperLeg=q(X, 4),
                   RightLowerLeg=q(X, 100), RightFoot=q(X, 40), LeftUpperLeg=q(X, -80), LeftLowerLeg=q(X, 80),
                   **arm("Left", 84, 30, 30, -4), **arm("Right", 80, 20, 30, -4)),
          (0.0, 0.0, -0.40), None, ground=True, ease="ease")
    c.key(1.20, pp(Hips=q(X, 8), Spine=q(X, 10), Chest=q(X, 8), Head=q(X, 0)), (0.0, 0.02, -0.14),
          feet(-0.12, 0.12), ease="ease")
    c.key(L, pbase(), READY_HIPS, feet(), {"Right": READY_GRIP}, ease="ease")
    return c.write(arm_obj, name, L)


def revive_loop(arm_obj, p, name="Act_Revive-loop", L=2.0):
    """Kneeling on the right knee beside a downed player (0.6 m ahead), both hands pressing / pulling on their back
    twice per loop, a glance around once."""
    def kneel(press, look):
        r = pp(Hips=q(X, 12), Spine=q(X, 18 + 8 * press), Chest=q(X, 20 + 8 * press) @ q(Z, 6 * look),
               Neck=q(X, 4) @ q(Z, 14 * look), Head=q(X, 10 - 10 * abs(look)) @ q(Z, 30 * look),
               RightUpperLeg=q(X, 4), RightLowerLeg=q(X, 96), RightFoot=q(X, 36))
        return r
    hands = lambda press: {  # noqa: E731
        "Right": dict(pos=Vector((-0.12, -0.58, 0.32 - 0.05 * press)), pole=Vector((-1.0, 0.5, -0.3)),
                      rot=q(Z, 90) @ q(Y, -40)),
        "Left": dict(pos=Vector((0.10, -0.60, 0.32 - 0.05 * press)), pole=Vector((1.0, 0.5, -0.3)),
                     rot=q(Z, -90) @ q(Y, 40))}
    left_foot = {"Left": dict(dy=-0.34, dx=0.04, yaw=4)}
    c = clip(p, L, 37)
    c.key(0.0, kneel(0.0, 0.0), (0.0, 0.10, -0.40), left_foot, hands(0.0), ground=True)
    c.key(0.5, kneel(1.0, 0.0), (0.0, 0.08, -0.44), left_foot, hands(1.0), ground=True, ease="in")
    c.key(0.9, kneel(0.0, 0.5), (0.0, 0.10, -0.40), left_foot, hands(0.0), ground=True, ease="ease")
    c.key(1.5, kneel(1.0, -0.2), (0.0, 0.08, -0.44), left_foot, hands(1.0), ground=True, ease="in")
    c.close(L, ease="ease")
    return c.write(arm_obj, name, L, looping=True)


def death_a(arm_obj, p, name="Death_A", L=0.5):
    """Short collapse (knees fold, torso slumps to the right); the code switches to the ragdoll from ~0.35 s."""
    c = clip(p, L, 38)
    c.key(0.0, pbase(), READY_HIPS, feet(), {"Right": READY_GRIP})
    c.key(0.12, pp(Hips=q(X, -4) @ q(Y, -4), Spine=q(X, -6), Chest=q(X, -10) @ q(Y, -6), Neck=q(X, -10),
                   Head=q(X, -22) @ q(Y, -14), **arm("Left", 60, 30, 40, -20), **arm("Right", 64, 30, 40, -20)),
          (0.0, 0.06, -0.10), feet(-0.09, 0.10, l_heel=10), ease="out3")
    c.key(0.32, pp(Hips=q(X, 14) @ q(Y, -12), Spine=q(X, 14) @ q(Y, -10), Chest=q(X, 18) @ q(Y, -12), Neck=q(X, 20),
                   Head=q(X, 26) @ q(Y, -20), **arm("Left", 84, 10, 16, -6), **arm("Right", 86, 6, 12, -6)),
          (-0.06, 0.02, -0.40), feet(-0.07, 0.10, l_heel=24, r_heel=16), ease="in")
    c.key(L, pp(Hips=q(X, 24) @ q(Y, -20), Spine=q(X, 18) @ q(Y, -14), Chest=q(X, 20) @ q(Y, -16), Neck=q(X, 24),
                Head=q(X, 30) @ q(Y, -24), LeftUpperLeg=q(X, 30), RightUpperLeg=q(X, 40), LeftLowerLeg=q(X, 100),
                RightLowerLeg=q(X, 110), **arm("Left", 86, 4, 10, -6), **arm("Right", 88, 2, 10, -6)),
          (-0.10, 0.0, -0.62), None, ground=True, ease="in")
    return c.write(arm_obj, name, L)


# ------------------------------------------------------------------------------------------------------------
def build_actions(arm_obj, p=None):
    acts = [light_a(arm_obj, p), light_b(arm_obj, p), swing_a(arm_obj, p), swing_b(arm_obj, p), charged(arm_obj, p),
            shove(arm_obj, p), stomp(arm_obj, p), execute(arm_obj, p), revive_loop(arm_obj, p),
            hit_add(arm_obj, p, "Hit_Front", 1, seed=30), hit_add(arm_obj, p, "Hit_Back", -1, seed=39),
            stagger(arm_obj, p), grabbed_loop(arm_obj, p), down_fall(arm_obj, p), down_idle(arm_obj, p),
            down_crawl(arm_obj, p), down_revived(arm_obj, p), death_a(arm_obj, p)]
    problems = []
    for act in acts:
        looping, length, speed, _kind = COMBAT_TABLE[act.name]
        problems += anim.check_action_name(act.name, looping)
        if int(act.frame_range[1]) != anim.frame_count(length):
            problems.append("%s: %d frames, want %d" % (act.name, act.frame_range[1], anim.frame_count(length)))
        if act.get("ik_clamped_frames", 0):
            problems.append("%s: %d frames out of IK reach" % (act.name, act["ik_clamped_frames"]))
        if abs(act.get("authored_speed", 0.0) - speed) > 1e-6:
            problems.append("%s: authored speed %s != %s" % (act.name, act.get("authored_speed"), speed))
        act["looping"] = looping
    missing = set(COMBAT_TABLE) - {a.name for a in acts}
    if missing:
        problems.append("missing %s" % sorted(missing))
    if problems:
        raise RuntimeError("humanoid_combat: " + "; ".join(problems))
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
        print("  %-22s frames=%-3d speed=%.1f" % (act.name, act.frame_range[1], act.get("authored_speed", 0.0)))
    return glb


def main():
    rig.write_bonemap(export.BONEMAP_PATH)
    return build()


if __name__ == "__main__":
    main()
