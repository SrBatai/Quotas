"""Locomotion animation library — ASSET_SPEC_V2 §6.1/§6.2, milestone M1.

    cd winter-survival/blender && python3 anims/build_loco.py

Exports assets/models/anims/humanoid_loco.glb (+ sources/humanoid_loco.blend + the Godot `.import`, template
lib/export.py kind "anim": AnimationLibrary, humanoid retarget, `-loop` -> LOOP_LINEAR). The file holds the
player-proportion armature only (no mesh) and these in-place cycles (Root never keyed, Hips = the only
position track, LEFT foot on the ground at t = 0):

    name                   loop  length  authored speed   method
    Loco_Idle-loop         yes   3.0 s   0                standing_cycle (breath, weight shift)
    Loco_Idle_Cold-loop    yes   2.0 s   0                standing_cycle (arms crossed, hunched, shivering) v0
    Loco_Walk-loop         yes   0.8 s   2.2 m/s          gait generator (lib.anim.LOCO_GAITS)
    Loco_Run-loop          yes   0.667 s 6.0 m/s          gait generator
    Crouch_Idle-loop       yes   3.0 s   0                standing_cycle, pelvis -0.35
    Crouch_Walk-loop       yes   1.0 s   1.3 m/s          gait generator, pelvis -0.35

M1 speed decision (binding, overrides PLAN C19 / ASSET_SPEC_V2 §6.2): walk 2.2, run 6.0, crouch-walk 1.3 m/s;
walk / crouch-walk cycles shortened (0.8 / 1.0 s instead of 1.0 / 1.2 s) so the stride stays inside the leg
reach with a moderate pelvis drop. The stance contact points move at exactly the authored speed (no foot
sliding); AnimationTree TimeScale = v_real / v_authored. Each action carries custom props (authored_speed,
period, drop) in the .blend; LOCO_TABLE below is the contract verify_chars.py checks.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

from lib import anim  # noqa: E402
from lib import export  # noqa: E402
from lib import lowpoly as lp  # noqa: E402
from lib import rig  # noqa: E402
from lib.anim import X, Y, Z, q_axis  # noqa: E402

NAME = "humanoid_loco"
SUBDIR = "anims"
# name -> (looping, length s, authored speed m/s or 0)
LOCO_TABLE = {
    "Loco_Idle-loop": (True, 3.0, 0.0),
    "Loco_Idle_Cold-loop": (True, 2.0, 0.0),
    "Loco_Walk-loop": (True, 0.8, 2.2),
    "Loco_Run-loop": (True, 2.0 / 3.0, 6.0),
    "Crouch_Idle-loop": (True, 3.0, 0.0),
    "Crouch_Walk-loop": (True, 1.0, 1.3),
}
CROUCH_DROP = 0.35


def idle_cold(arm_obj, p, name="Loco_Idle_Cold-loop", period=2.0):
    """Cold idle v0: hunched, shoulders up, head tucked into the scarf, arms crossed hugging the chest,
    knees together; shivers (7.5 Hz, 15 cycles per loop) in two pulses, one breath, weight shift."""
    def body(t, pose):
        br = math.sin(2 * math.pi * t)
        sh = math.sin(2 * math.pi * 15 * t) * (0.55 + 0.45 * math.sin(4 * math.pi * t) ** 2)
        ws = math.sin(2 * math.pi * t + 0.8)
        pose.hips = Vector((0.010 * ws, 0.0, -0.035 - 0.004 * br + 0.002 * sh))
        pose.rel["Hips"] = q_axis(Y, 1.2 * ws) @ q_axis(X, 4.0)
        pose.set_world("Spine", q_axis(X, 8.0 + 1.0 * br) @ q_axis(Z, 0.6 * sh))
        pose.set_world("Chest", q_axis(X, 14.0 - 1.5 * br) @ q_axis(Z, 1.6 * sh) @ q_axis(Y, 0.8 * ws))
        pose.set_world("Neck", q_axis(X, 16.0) @ q_axis(Z, 1.0 * sh))
        pose.set_world("Head", q_axis(X, 12.0 - 1.5 * br) @ q_axis(Y, 1.2 * sh) @ q_axis(Z, 4.0 * ws))
        for side in anim.SIDES:
            s = 1 if side == "Left" else -1
            pose.rel[side + "Shoulder"] = q_axis(Y, -s * (9.0 + 1.5 * br + 1.2 * sh)) @ q_axis(Z, s * 6.0)
        # hands hug the opposite upper arms, forearms stacked in front of the chest (left above right)
        cw = pose.world("Chest")
        c0 = pose.head("Chest")
        for side, hand, pole in (("Left", (-0.19, -0.235, 0.155), (0.9, -0.4, -1.0)),
                                 ("Right", (0.19, -0.255, 0.075), (-0.9, -0.4, -1.0))):
            s = 1 if side == "Left" else -1
            target = c0 + cw @ Vector((hand[0], hand[1], hand[2] + 0.004 * sh))
            anim.solve_arm(pose, side, target, cw @ Vector(pole))
            pose.set_world(side + "Hand", pose.world(side + "LowerArm") @ q_axis(Z, -s * 12.0))
        return {"Left": anim.planted_foot(pose, "Left", -0.01, -0.025, -6),
                "Right": anim.planted_foot(pose, "Right", 0.01, -0.025, -6)}
    return anim.standing_cycle(arm_obj, p, name, period, body)


def crouch_idle(arm_obj, p, name="Crouch_Idle-loop", period=3.0):
    """Crouched idle: pelvis -0.35, torso leaning forward, forearms over the knees, breathing, slow look
    around (one head sweep per loop), small weight shift."""
    def body(t, pose):
        br = math.sin(2 * math.pi * t)
        look = math.sin(2 * math.pi * t)
        ws = math.sin(2 * math.pi * t + 1.2)
        pose.hips = Vector((0.012 * ws, 0.02, -CROUCH_DROP - 0.006 * br))
        pose.rel["Hips"] = q_axis(X, -12.0) @ q_axis(Y, 1.5 * ws)
        pose.set_world("Spine", q_axis(X, 18.0 + 1.0 * br) @ q_axis(Z, 3.0 * look))
        pose.set_world("Chest", q_axis(X, 26.0 - 1.5 * br) @ q_axis(Z, 6.0 * look))
        pose.set_world("Neck", q_axis(X, 14.0) @ q_axis(Z, 12.0 * look))
        pose.set_world("Head", q_axis(X, 6.0 - 1.0 * br) @ q_axis(Z, 24.0 * look))
        for side in anim.SIDES:
            s = 1 if side == "Left" else -1
            ua, la = anim.arm_pose(side, 66.0 - 1.5 * br, 34.0 + 1.0 * br, 52.0 + 2.0 * br, twist_deg=-4)
            pose.rel[side + "Shoulder"] = q_axis(Y, s * (1.0 + 1.0 * br))
            pose.rel[side + "UpperArm"] = ua
            pose.rel[side + "LowerArm"] = la
        return {"Left": anim.planted_foot(pose, "Left", -0.10, 0.05, 12),
                "Right": anim.planted_foot(pose, "Right", 0.06, 0.05, 12)}
    return anim.standing_cycle(arm_obj, p, name, period, body)


def build_actions(arm_obj, p=None):
    acts = [anim.idle(arm_obj, p, "Loco_Idle-loop", 3.0), idle_cold(arm_obj, p)]
    for name in ("Loco_Walk-loop", "Loco_Run-loop", "Crouch_Walk-loop"):
        acts.append(anim.locomotion(arm_obj, p, name, **anim.LOCO_GAITS[name]))
    acts.append(crouch_idle(arm_obj, p))
    problems = []
    for act in acts:
        looping, length, speed = LOCO_TABLE[act.name]
        problems += anim.check_action_name(act.name, looping)
        if int(act.frame_range[1]) != anim.frame_count(length):
            problems.append("%s: %d frames, want %d" % (act.name, act.frame_range[1], anim.frame_count(length)))
        if act.get("ik_clamped_frames", 0):
            problems.append("%s: %d frames out of IK reach" % (act.name, act["ik_clamped_frames"]))
        if abs(act.get("authored_speed", 0.0) - speed) > 1e-6:
            problems.append("%s: authored speed %s != %s" % (act.name, act.get("authored_speed"), speed))
        act["looping"] = looping
    if problems:
        raise RuntimeError("humanoid_loco: " + "; ".join(problems))
    return acts


def build():
    lp.new_scene()
    bpy.context.scene.render.fps = anim.FPS
    arm_obj = rig.build_armature()
    acts = build_actions(arm_obj)
    anim.reset_pose(arm_obj)
    glb = export.save_and_export(NAME, SUBDIR)
    export.write_import(glb, "anim")
    for act in acts:
        print("  %-22s frames=%-3d speed=%.1f drop=%.3f" % (act.name, act.frame_range[1],
                                                           act.get("authored_speed", 0.0), act.get("drop", 0.0)))
    return glb


def main():
    rig.write_bonemap(export.BONEMAP_PATH)
    return build()


if __name__ == "__main__":
    main()
