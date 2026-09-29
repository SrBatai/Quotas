"""Player firearm / bow animation library — ASSET_SPEC_V2 §6.2 (the M5 rows: Pistol_*, LongGun_*, Bow_*, reloads,
Act_Unjam) + "T2".

    cd winter-survival/blender && python3 anims/build_firearms.py

Exports assets/models/anims/humanoid_firearms.glb (+ sources/humanoid_firearms.blend + the Godot `.import`, template
lib/export.py kind "anim") from the survivor-proportion armature without mesh, and merges the events into
data/anim_events.json. In place, 30 fps, every frame keyed (LINEAR), Root never keyed, only Hips translates.

Weapon convention (§12 + lib/gunspec.py): the weapon hangs with IDENTITY on RightHandSocket (the right hand never
leaves it); the LEFT fist is solved every frame onto weapon-frame points (keyanim `follow`): SupportGrip while aiming,
the magazine / shell / cartridge insert points (loose parts carried with identity on LeftHandSocket coincide with their
rest transform in the weapon at mag_in / shell_in), the pistol slide, the shotgun pump, the rifle bolt knob, the
revolver cylinder, the bow string (SupportGrip at brace -> DrawPoint at full draw). Torso filter friendly (§6.5):
Hips never rotate (only the alive layer), the blade / lean / recoil live in Spine / Chest / Neck / Head / arms, so the
upper body reads the same over any locomotion clip.

Aim poses point the muzzle along -Y Blender (+Z Godot, the model front) at chest / eye height; Pistol_* clips are shared
by pistol and revolver (same Grip / SupportGrip), LongGun_* by shotgun and rifle_hunting (same SupportGrip). Shoot clips
are ADDITIVE (for an Add2 / OneShot add, amount 1): per-bone local deltas measured against the Aim pose (T-pose rest =
identity at both ends), so Aim + Shoot = the recoil pose exactly. Bow: held in the right fist, the left hand nocks and
draws (a left-handed archer's silhouette; weapons all mount on RightHandSocket).

FIREARMS_TABLE (name -> looping, length s, authored speed, kind) is the contract verify_chars.py checks.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

from lib import anim  # noqa: E402
from lib import export  # noqa: E402
from lib import gunspec as G  # noqa: E402
from lib import keyanim as ka  # noqa: E402
from lib import lowpoly as lp  # noqa: E402
from lib import rig  # noqa: E402
from lib.anim import X, Y, Z, q_axis as q  # noqa: E402

NAME = "humanoid_firearms"
SUBDIR = "anims"
EVENTS_PATH = export.ROOT / "data" / "anim_events.json"
FPS = anim.FPS

FIREARMS_TABLE = {
    "Pistol_Idle-loop": (True, 3.0, 0.0, "stand"),
    "Pistol_Aim-loop": (True, 2.0, 0.0, "stand"),
    "Pistol_Shoot": (False, 0.2, 0.0, "additive"),
    "Pistol_Reload": (False, 1.6, 0.0, "move"),
    "Pistol_Reload_Revolver": (False, 3.0, 0.0, "move"),
    "LongGun_Idle-loop": (True, 3.0, 0.0, "stand"),
    "LongGun_Aim-loop": (True, 2.0, 0.0, "stand"),
    "LongGun_Shoot": (False, 0.3, 0.0, "additive"),
    "LongGun_Shoot_Shotgun": (False, 0.3, 0.0, "additive"),
    "LongGun_Pump": (False, 0.6, 0.0, "move"),
    "LongGun_Bolt_Rack": (False, 1.0, 0.0, "move"),
    "LongGun_Reload_Shell-loop": (True, 0.7, 0.0, "stand"),
    "LongGun_Reload_Bolt": (False, 3.5, 0.0, "move"),
    "LongGun_Reload_Mag": (False, 2.2, 0.0, "move"),
    "Act_Unjam": (False, 1.5, 0.0, "move"),
    "Act_Unjam_LongGun": (False, 1.5, 0.0, "move"),
    "Bow_Aim-loop": (True, 2.0, 0.0, "stand"),
    "Bow_Draw": (False, 1.4, 0.0, "move"),
    "Bow_Hold-loop": (True, 2.0, 0.0, "stand"),
    "Bow_Release": (False, 0.3, 0.0, "move"),
}

REV_SHELLS = [1.00, 1.25, 1.50, 1.75, 2.00, 2.25]
RIFLE_SHELLS = [1.05, 1.45, 1.85, 2.25, 2.65]
EVENTS = {
    "Pistol_Shoot": {"fire": 0.0, "recovered": 0.13},
    "LongGun_Shoot": {"fire": 0.0, "recovered": 0.20},
    "LongGun_Shoot_Shotgun": {"fire": 0.0, "recovered": 0.22},
    "Pistol_Reload": {"mag_out": 0.35, "mag_grab": 0.55, "mag_in": 1.10, "slide": 1.40},
    "Pistol_Reload_Revolver": dict({"cyl_open": 0.30, "mag_out": 0.60, "shell_grab": 0.85, "cyl_close": 2.45,
                                    "mag_in": 2.50},
                                   **{"shell_in_%d" % (k + 1): t for k, t in enumerate(REV_SHELLS)}),
    "LongGun_Pump": {"pump_back": 0.20, "eject": 0.21, "pump_fwd": 0.34},
    "LongGun_Bolt_Rack": {"bolt_open": 0.38, "eject": 0.50, "bolt_back": 0.50, "bolt_fwd": 0.62, "bolt_close": 0.70},
    "LongGun_Reload_Shell-loop": {"shell_grab": 0.08, "shell_in": 0.46},
    "LongGun_Reload_Bolt": dict({"bolt_open": 0.40, "bolt_back": 0.55, "shell_grab": 0.72, "bolt_fwd": 2.85,
                                 "bolt_close": 2.95, "mag_in": 2.95},
                                **{"shell_in_%d" % (k + 1): t for k, t in enumerate(RIFLE_SHELLS)}),
    "LongGun_Reload_Mag": {"mag_out": 0.40, "mag_grab": 0.75, "mag_in": 1.35, "bolt_back": 1.72, "bolt_close": 1.80},
    "Act_Unjam": {"tap": 0.35, "rack": 0.85, "clear": 1.00},
    "Act_Unjam_LongGun": {"tap": 0.35, "rack": 0.75, "clear": 0.95},
    "Bow_Draw": {"nock": 0.30, "draw_start": 0.55, "draw_full": 1.20},
    "Bow_Release": {"release": 0.03, "fire": 0.03},
}

SIDES = anim.SIDES


# ------------------------------------------------------------------------------------------------------------
# helpers
# ------------------------------------------------------------------------------------------------------------
def V(*a):
    return Vector(a)


def gframe(pitch=0.0, yaw=0.0, roll=0.0):
    """(shaft, edge) of a weapon whose muzzle is pitched up `pitch`, yawed left `yaw` (deg, +Z) and rolled `roll`
    (deg, + = top toward the shooter's right) — identity = level, pointing forward (-Y)."""
    r = (Matrix.Rotation(math.radians(yaw), 3, 'Z') @ Matrix.Rotation(math.radians(-pitch), 3, 'X')
         @ Matrix.Rotation(math.radians(roll), 3, Vector((0.0, -1.0, 0.0))))
    return r @ Vector((0.0, 0.0, 1.0)), r @ Vector((0.0, -1.0, 0.0))


def grip(pos, fr=None, pole=(-0.5, 0.3, -1.0)):
    shaft, edge = fr if fr is not None else gframe()
    return dict(grip=Vector(pos), shaft=Vector(shaft).normalized(), edge=Vector(edge).normalized(),
                pole=Vector(pole))


def fol(offset, frame=None, pole=(0.6, 0.3, -1.0)):
    """Left fist pinned to a weapon-frame point (keyanim follow). frame = (shaft, edge) in weapon axes."""
    shaft, edge = frame if frame is not None else G.IDENTITY_FRAME
    return {"Left": dict(offset=tuple(offset), shaft=shaft, edge=edge, pole=pole)}


def add(a, b):
    return tuple(x + y for x, y in zip(a, b))


def lhand(pos, pole=(0.7, 0.4, -0.8), rot=None):
    d = dict(pos=Vector(pos), pole=Vector(pole))
    if rot is not None:
        d["rot"] = rot
    return d


GUN_FEET = {"Left": dict(dy=-0.12, dx=0.02, yaw=-4), "Right": dict(dy=0.12, dx=0.05, yaw=24)}
BOW_FEET = {"Left": dict(dy=0.06, dx=0.07, yaw=-30), "Right": dict(dy=-0.10, dx=0.03, yaw=10)}
HIPS = (0.0, 0.0, -0.035)
RACK_FRAME = ((0.0, 1.0, 0.0), (-1.0, 0.0, 0.0))            # left fist overhand on top, knuckles to the right


def feet(base=None):
    b = base or GUN_FEET
    return {"Left": dict(b["Left"]), "Right": dict(b["Right"])}


def body(sp=(0, 0, 0), ch=(0, 0, 0), nk=(0, 0, 0), hd=(0, 0, 0), ls=0.0, rs=0.0):
    """Torso rel rotations: each tuple = (yaw about Z, pitch forward about X, roll about Y) in degrees; ls / rs =
    shoulder protraction (brings that shoulder forward). Hips never rotate (torso filter)."""
    r = anim.rest_pose()

    def rq(t):
        return q(X, t[1]) @ q(Z, t[0]) @ q(Y, t[2])
    r.update({"Spine": rq(sp), "Chest": rq(ch), "Neck": rq(nk), "Head": rq(hd),
              "LeftShoulder": q(Z, -ls), "RightShoulder": q(Z, rs)})
    return r


def clip(p, length, seed, post=None, alive_amp=0.25):
    layers = [lambda t, pose: ka.alive(pose, t, length, alive_amp, seed)]
    if post:
        layers.append(post)

    def run(t, pose):
        for f in layers:
            f(t, pose)
    c = ka.Clip(p, base=anim.rest_pose(), post=run)
    c.count_hands = True
    return c


def breathing(length, amp=0.9, sway=0.0):
    def f(t, pose):
        u = 2 * math.pi * t / length
        pose.rel["Chest"] = pose.rel["Chest"] @ q(X, amp * math.sin(u)) @ q(Z, sway * math.sin(u + 1.1))
        pose.rel["Spine"] = pose.rel["Spine"] @ q(X, 0.4 * amp * math.sin(u + 0.4))
    return f


def resolved(c):
    c.keys.sort(key=lambda k: k.t)
    for k in c.keys:
        c._resolve(k)
    return c


# ------------------------------------------------------------------------------------------------------------
# stances
# ------------------------------------------------------------------------------------------------------------
PISTOL_BODY = dict(sp=(-3, 2, 0), ch=(-5, 5, 0), nk=(3, 2, 0), hd=(5, 8, 0), ls=16, rs=14)
PISTOL_AIM = grip((-0.035, -0.505, 1.40), pole=(-0.5, 0.3, -1.0))
PISTOL_SUP = fol(G.SUPPORT_PISTOL, G.LEFT_FRAME_PISTOL, pole=(0.6, 0.3, -1.0))

LONG_BODY = dict(sp=(-16, 4, 0), ch=(-24, 5, 0), nk=(18, 6, 0), hd=(22, 12, -9), ls=18, rs=6)
LONG_AIM = grip((-0.105, -0.345, 1.375), pole=(-1.0, 0.25, -0.35))
LONG_SUP = fol(G.SUPPORT_LONG, G.LEFT_FRAME_LONG, pole=(0.45, 0.2, -1.0))

BOW_READY_BODY = dict(sp=(6, 3, 0), ch=(10, 4, 0), nk=(-6, 2, 0), hd=(-8, 6, 0), ls=6, rs=10)
BOW_READY = grip((-0.10, -0.40, 1.17), gframe(pitch=-18, yaw=4, roll=-24), pole=(-0.9, 0.4, -0.7))
BOW_SUP = fol(G.SUPPORT_BOW, G.LEFT_FRAME_BOW, pole=(0.9, 0.5, -0.6))
BOW_FULL_BODY = dict(sp=(18, 1, 0), ch=(28, 2, 0), nk=(-22, 6, 0), hd=(-24, 12, 6), ls=0, rs=14)
BOW_FULL = grip((0.07, -0.700, 1.445), pole=(-0.9, 0.3, -0.4))
BOW_DRAWN = fol(G.DRAW_POINT, G.LEFT_FRAME_BOW, pole=(1.0, 0.35, -0.05))


def key_pose(c, t, bodyd, right, follow=None, left=None, hips=HIPS, ft=None, ease="ease"):
    hands = {"Right": right}
    if left is not None:
        hands["Left"] = left
    c.key(t, body(**bodyd), hips, feet(ft), hands, ease=ease, follow=follow)


def lerp_body(a, b, u):
    out = {}
    for k in a:
        va, vb = a[k], b[k]
        if isinstance(va, tuple):
            out[k] = tuple(x + (y - x) * u for x, y in zip(va, vb))
        else:
            out[k] = va + (vb - va) * u
    return out


def shifted(g, d=(0, 0, 0), fr=None):
    out = dict(g)
    out["grip"] = g["grip"] + Vector(d)
    if fr is not None:
        out["shaft"], out["edge"] = Vector(fr[0]).normalized(), Vector(fr[1]).normalized()
    return out


# ------------------------------------------------------------------------------------------------------------
# loops: idle / aim
# ------------------------------------------------------------------------------------------------------------
def standing_loop(arm_obj, p, name, L, bodyd, right, follow, seed, ft=None, amp=0.9, sway=0.4, post=None):
    extra = [breathing(L, amp, sway)] + ([post] if post else [])

    def layers(t, pose):
        for f in extra:
            f(t, pose)
    c = clip(p, L, seed, post=layers)
    key_pose(c, 0.0, bodyd, right, follow, ft=ft)
    key_pose(c, L / 2, bodyd, right, follow, ft=ft, ease="sine")
    c.close(L, ease="sine")
    return c.write(arm_obj, name, L, looping=True)


def pistol_idle(arm_obj, p):
    b = dict(sp=(-2, 3, 0), ch=(-3, 3, 0), nk=(2, 4, 0), hd=(2, 8, 0), ls=8, rs=6)
    g = grip((-0.05, -0.30, 1.08), gframe(pitch=-48, yaw=6), pole=(-0.4, 0.4, -1.0))
    return standing_loop(arm_obj, p, "Pistol_Idle-loop", 3.0, b, g, PISTOL_SUP, 41, amp=1.0, sway=0.5)


def pistol_aim(arm_obj, p):
    return standing_loop(arm_obj, p, "Pistol_Aim-loop", 2.0, PISTOL_BODY, PISTOL_AIM, PISTOL_SUP, 42, amp=0.6,
                         sway=0.3)


def long_idle(arm_obj, p):
    b = dict(sp=(-14, 5, 0), ch=(-20, 5, 0), nk=(14, 3, 0), hd=(16, 6, 0), ls=18, rs=4)
    g = grip((-0.11, -0.25, 1.16), gframe(pitch=-26, yaw=18, roll=6), pole=(-0.8, 0.4, -0.7))
    return standing_loop(arm_obj, p, "LongGun_Idle-loop", 3.0, b, g, LONG_SUP, 43, amp=1.0, sway=0.5)


def long_aim(arm_obj, p):
    return standing_loop(arm_obj, p, "LongGun_Aim-loop", 2.0, LONG_BODY, LONG_AIM, LONG_SUP, 44, amp=0.5, sway=0.3)


def bow_aim(arm_obj, p):
    return standing_loop(arm_obj, p, "Bow_Aim-loop", 2.0, BOW_READY_BODY, BOW_READY, BOW_SUP, 45, amp=0.8,
                         sway=0.4, ft=BOW_FEET)


def bow_hold(arm_obj, p):
    def tremble(t, pose):
        a = 0.35 * math.sin(2 * math.pi * 7 * t / 2.0) + 0.2 * math.sin(2 * math.pi * 11 * t / 2.0)
        pose.rel["RightUpperArm"] = pose.rel["RightUpperArm"] @ q(X, a)
    return standing_loop(arm_obj, p, "Bow_Hold-loop", 2.0, BOW_FULL_BODY, BOW_FULL, BOW_DRAWN, 46, amp=0.4,
                         sway=0.2, ft=BOW_FEET, post=tremble)


# ------------------------------------------------------------------------------------------------------------
# additive recoil (deltas against the aim pose)
# ------------------------------------------------------------------------------------------------------------
def additive(arm_obj, p, name, L, bodyd, aim, sup, peaks, seed):
    """peaks = [(t, dict(grip=(dx, dy, dz), pitch=deg, body=dict(...) deltas))]: recoil keys over the aim pose."""
    pr = rig.params(**(p or {}))
    base = ka.Clip(pr, base=anim.rest_pose())
    base.count_hands = True
    key_pose(base, 0.0, bodyd, aim, sup)
    key_pose(base, L, bodyd, aim, sup)
    rec = ka.Clip(pr, base=anim.rest_pose())
    rec.count_hands = True
    key_pose(rec, 0.0, bodyd, aim, sup)
    for t, spec in peaks:
        bd = {k: (tuple(x + y for x, y in zip(v, spec.get("body", {}).get(k, (0, 0, 0))))
                  if isinstance(v, tuple) else v + spec.get("body", {}).get(k, 0.0)) for k, v in bodyd.items()}
        sh, ed = aim["shaft"], aim["edge"]
        rot = Matrix.Rotation(math.radians(spec.get("pitch", 0.0)), 3, sh.cross(ed).normalized())
        g = dict(aim)
        g["grip"] = aim["grip"] + Vector(spec.get("grip", (0, 0, 0)))
        g["shaft"], g["edge"] = rot @ sh, rot @ ed
        key_pose(rec, t, bd, g, sup, ease=spec.get("ease", "ease"))
    key_pose(rec, L, bodyd, aim, sup, ease="ease")
    resolved(base)
    resolved(rec)
    n = anim.frame_count(L)
    w = anim.ActionWriter(arm_obj, name)
    for f in range(n + 1):
        t = f / FPS
        pb, pt = base.pose_at(t), rec.pose_at(t)
        d = anim.Pose(pr)
        for b in rig.BONE_NAMES:
            d.rel[b] = pb.rel[b].inverted() @ pt.rel[b]
        d.hips = pt.hips - pb.hips
        ka.alive(d, t, L, 0.15, seed)
        w.pose(d, f)
    act = w.finish(0, n, 'LINEAR')
    act["authored_speed"] = 0.0
    act["period"] = L
    act["looping"] = False
    act["ik_clamped_frames"] = base.clamped + rec.clamped
    if base.hand_clamped + rec.hand_clamped:
        act["hand_clamped_frames"] = base.hand_clamped + rec.hand_clamped
    act["additive_base"] = "Pistol_Aim" if name.startswith("Pistol") else "LongGun_Aim"
    return act


def pistol_shoot(arm_obj, p):
    peaks = [(0.033, dict(grip=(0.0, 0.030, 0.022), pitch=15.0, ease="out3",
                          body={"ch": (0, -2.5, 0), "hd": (0, -2, 0)})),
             (0.100, dict(grip=(0.0, 0.010, 0.008), pitch=5.0, body={"ch": (0, -1, 0)}))]
    return additive(arm_obj, p, "Pistol_Shoot", 0.2, PISTOL_BODY, PISTOL_AIM, PISTOL_SUP, peaks, 51)


def long_shoot(arm_obj, p):
    peaks = [(0.050, dict(grip=(0.0, 0.045, 0.018), pitch=7.0, ease="out3",
                          body={"sp": (2, -2, 0), "ch": (3, -3, 0), "hd": (0, -4, 0)})),
             (0.140, dict(grip=(0.0, 0.015, 0.006), pitch=2.5, body={"ch": (1, -1, 0)}))]
    return additive(arm_obj, p, "LongGun_Shoot", 0.3, LONG_BODY, LONG_AIM, LONG_SUP, peaks, 52)


def shotgun_shoot(arm_obj, p):
    peaks = [(0.050, dict(grip=(0.0, 0.075, 0.035), pitch=13.0, ease="out3",
                          body={"sp": (4, -4, 0), "ch": (6, -6, 0), "nk": (0, -3, 0), "hd": (0, -6, 0), "rs": -4})),
             (0.160, dict(grip=(0.0, 0.025, 0.012), pitch=4.0, body={"sp": (1, -1, 0), "ch": (2, -2, 0)}))]
    return additive(arm_obj, p, "LongGun_Shoot_Shotgun", 0.3, LONG_BODY, LONG_AIM, LONG_SUP, peaks, 53)


# ------------------------------------------------------------------------------------------------------------
# pistol reloads / unjam
# ------------------------------------------------------------------------------------------------------------
PISTOL_WORK = grip((-0.05, -0.36, 1.30), gframe(pitch=22, yaw=10, roll=24), pole=(-0.6, 0.4, -1.0))
PISTOL_WORK_BODY = dict(sp=(-2, 4, 0), ch=(-3, 6, 0), nk=(2, 8, 0), hd=(4, 16, 0), ls=6, rs=6)
POUCH_L = (0.17, -0.07, 1.00)
d_grip = G.GRIP_AXIS


def pistol_reload(arm_obj, p, L=1.6):
    c = clip(p, L, 61)
    below = add(G.PISTOL_MAG, tuple(d_grip * -0.05))
    key_pose(c, 0.00, PISTOL_BODY, PISTOL_AIM, PISTOL_SUP)
    key_pose(c, 0.18, PISTOL_WORK_BODY, PISTOL_WORK, left=lhand((0.14, -0.30, 1.16)), ease="out")
    key_pose(c, 0.35, PISTOL_WORK_BODY, shifted(PISTOL_WORK, (0, 0, -0.02)), left=lhand(POUCH_L))
    key_pose(c, 0.55, PISTOL_WORK_BODY, PISTOL_WORK, left=lhand(add(POUCH_L, (0.01, 0.0, -0.03))))
    key_pose(c, 0.90, PISTOL_WORK_BODY, PISTOL_WORK, fol(below))
    key_pose(c, 1.10, PISTOL_WORK_BODY, shifted(PISTOL_WORK, (0, 0, 0.012)), fol(G.PISTOL_MAG), ease="in")
    key_pose(c, 1.24, PISTOL_WORK_BODY, PISTOL_WORK, fol(G.PISTOL_RACK, RACK_FRAME, pole=(0.9, 0.3, -0.3)))
    key_pose(c, 1.36, PISTOL_WORK_BODY, shifted(PISTOL_WORK, (0, -0.02, 0)),
             fol(add(G.PISTOL_RACK, (0, G.PISTOL_SLIDE_TRAVEL + 0.02, 0)), RACK_FRAME, pole=(0.9, 0.3, -0.3)),
             ease="in")
    key_pose(c, 1.42, PISTOL_WORK_BODY, PISTOL_WORK, left=lhand((0.20, -0.26, 1.36)), ease="out")
    key_pose(c, L, PISTOL_BODY, PISTOL_AIM, PISTOL_SUP)
    return c.write(arm_obj, "Pistol_Reload", L)


def revolver_reload(arm_obj, p, L=3.0):
    c = clip(p, L, 62)
    work = grip((-0.05, -0.34, 1.28), gframe(pitch=10, yaw=10, roll=-30), pole=(-0.6, 0.4, -1.0))
    up = grip((-0.06, -0.30, 1.30), gframe(pitch=70, yaw=6, roll=-10), pole=(-0.7, 0.3, -1.0))
    down = grip((-0.05, -0.33, 1.24), gframe(pitch=-58, yaw=8, roll=-24), pole=(-0.6, 0.4, -1.0))
    oc = tuple(G.revolver_open_center())
    push = G.REVOLVER_PUSH
    wb = PISTOL_WORK_BODY
    key_pose(c, 0.00, PISTOL_BODY, PISTOL_AIM, PISTOL_SUP)
    key_pose(c, 0.18, wb, work, fol(push), ease="out")
    key_pose(c, 0.30, wb, work, fol(add(push, (0.030, 0.0, 0.004))), ease="in")
    key_pose(c, 0.50, wb, up, fol(add(oc, (0.0, -0.050, 0.0))))
    key_pose(c, 0.60, wb, shifted(up, (0, 0, 0.01)), fol(add(oc, (0.0, -0.080, 0.0))), ease="in")
    key_pose(c, 0.85, wb, down, left=lhand(POUCH_L))
    for k, t in enumerate(REV_SHELLS):
        key_pose(c, t - 0.10, wb, down, fol(add(G.REVOLVER_ROUND, (0.020, 0.045, -0.020))), ease="ease")
        key_pose(c, t, wb, down, fol(G.REVOLVER_ROUND), ease="in")
    key_pose(c, 2.36, wb, work, fol(add(push, (0.030, 0.0, 0.004))))
    key_pose(c, 2.46, wb, work, fol(push), ease="in")
    key_pose(c, 2.60, wb, work, left=lhand((0.16, -0.30, 1.22)), ease="out")
    key_pose(c, L, PISTOL_BODY, PISTOL_AIM, PISTOL_SUP)
    return c.write(arm_obj, "Pistol_Reload_Revolver", L)


def pistol_unjam(arm_obj, p, L=1.5):
    c = clip(p, L, 63)
    work = grip((-0.05, -0.38, 1.32), gframe(pitch=12, yaw=8, roll=20), pole=(-0.6, 0.4, -1.0))
    eject = grip((-0.06, -0.38, 1.30), gframe(pitch=8, yaw=6, roll=-40), pole=(-0.6, 0.4, -1.0))
    below = add(G.PISTOL_MAG, tuple(d_grip * -0.06))
    key_pose(c, 0.00, PISTOL_BODY, PISTOL_AIM, PISTOL_SUP)
    key_pose(c, 0.22, PISTOL_WORK_BODY, work, fol(below), ease="out")
    key_pose(c, 0.35, PISTOL_WORK_BODY, shifted(work, (0, 0, 0.015)), fol(G.PISTOL_MAG), ease="in3")
    key_pose(c, 0.60, PISTOL_WORK_BODY, eject, fol(G.PISTOL_RACK, RACK_FRAME, pole=(0.9, 0.3, -0.3)))
    key_pose(c, 0.85, PISTOL_WORK_BODY, shifted(eject, (0, -0.02, 0)),
             fol(add(G.PISTOL_RACK, (0, G.PISTOL_SLIDE_TRAVEL + 0.025, 0)), RACK_FRAME, pole=(0.9, 0.3, -0.3)),
             ease="in")
    key_pose(c, 1.00, PISTOL_WORK_BODY, work, left=lhand((0.22, -0.26, 1.38)), ease="out")
    key_pose(c, L, PISTOL_BODY, PISTOL_AIM, PISTOL_SUP)
    return c.write(arm_obj, "Act_Unjam", L)


# ------------------------------------------------------------------------------------------------------------
# long guns: pump, bolt, reloads, unjam
# ------------------------------------------------------------------------------------------------------------
LONG_WORK_BODY = dict(sp=(-10, 5, 0), ch=(-14, 7, 0), nk=(8, 8, 0), hd=(10, 16, 0), ls=12, rs=4)
POUCH_LG = (0.16, -0.13, 1.00)


def long_pump(arm_obj, p, L=0.6):
    c = clip(p, L, 64)
    back = add(G.SUPPORT_LONG, (0.0, G.PUMP_TRAVEL, 0.0))
    dip = shifted(LONG_AIM, (0.0, 0.01, -0.012), gframe(pitch=-3, yaw=0, roll=4))
    key_pose(c, 0.00, LONG_BODY, LONG_AIM, LONG_SUP)
    key_pose(c, 0.10, LONG_BODY, dip, LONG_SUP, ease="out")
    key_pose(c, 0.20, LONG_BODY, dip, fol(back, G.LEFT_FRAME_LONG, pole=(0.45, 0.2, -1.0)), ease="in")
    key_pose(c, 0.24, LONG_BODY, dip, fol(back, G.LEFT_FRAME_LONG, pole=(0.45, 0.2, -1.0)))
    key_pose(c, 0.34, LONG_BODY, dip, LONG_SUP, ease="in")
    key_pose(c, L, LONG_BODY, LONG_AIM, LONG_SUP)
    return c.write(arm_obj, "LongGun_Pump", L)


def knob(lift, back):
    return tuple(G.rifle_bolt_knob(lift, back))


BOLT_POLE = (0.8, 0.2, -0.6)


def long_bolt_cycle(arm_obj, p, L=1.0):
    c = clip(p, L, 65)
    cant = shifted(LONG_AIM, (0.0, 0.015, -0.01), gframe(pitch=-2, yaw=0, roll=-10))
    key_pose(c, 0.00, LONG_BODY, LONG_AIM, LONG_SUP)
    key_pose(c, 0.26, LONG_BODY, cant, fol(knob(0, 0), RACK_FRAME, BOLT_POLE), ease="out")
    key_pose(c, 0.38, LONG_BODY, cant, fol(knob(1, 0), RACK_FRAME, BOLT_POLE))
    key_pose(c, 0.50, LONG_BODY, cant, fol(knob(1, 1), RACK_FRAME, BOLT_POLE), ease="in")
    key_pose(c, 0.62, LONG_BODY, cant, fol(knob(1, 0), RACK_FRAME, BOLT_POLE), ease="in")
    key_pose(c, 0.70, LONG_BODY, cant, fol(knob(0, 0), RACK_FRAME, BOLT_POLE))
    key_pose(c, 0.86, LONG_BODY, LONG_AIM, LONG_SUP, ease="ease")
    key_pose(c, L, LONG_BODY, LONG_AIM, LONG_SUP)
    return c.write(arm_obj, "LongGun_Bolt_Rack", L)


def shell_loop(arm_obj, p, L=0.7):
    c = clip(p, L, 66)
    work = grip((-0.13, -0.27, 1.14), gframe(pitch=8, yaw=12, roll=62), pole=(-0.8, 0.4, -0.8))
    under = add(G.SHOTGUN_LOAD, (0.0, 0.0, -0.045))
    key_pose(c, 0.00, LONG_WORK_BODY, work, left=lhand(POUCH_LG))
    key_pose(c, 0.20, LONG_WORK_BODY, work, left=lhand((0.10, -0.28, 1.04)))
    key_pose(c, 0.34, LONG_WORK_BODY, work, fol(under), ease="out")
    key_pose(c, 0.46, LONG_WORK_BODY, work, fol(G.SHOTGUN_LOAD), ease="in")
    key_pose(c, 0.52, LONG_WORK_BODY, work, fol(add(G.SHOTGUN_LOAD, (0.0, 0.0, 0.012))), ease="out")
    c.close(L, ease="ease")
    return c.write(arm_obj, "LongGun_Reload_Shell-loop", L, looping=True)


def rifle_reload(arm_obj, p, L=3.5):
    c = clip(p, L, 67)
    work = grip((-0.12, -0.28, 1.18), gframe(pitch=10, yaw=10, roll=-34), pole=(-0.8, 0.4, -0.8))
    away = add(G.RIFLE_ROUND, (-0.030, 0.050, 0.035))
    key_pose(c, 0.00, LONG_BODY, LONG_AIM, LONG_SUP)
    key_pose(c, 0.28, LONG_WORK_BODY, work, fol(knob(0, 0), RACK_FRAME, BOLT_POLE), ease="out")
    key_pose(c, 0.40, LONG_WORK_BODY, work, fol(knob(1, 0), RACK_FRAME, BOLT_POLE))
    key_pose(c, 0.55, LONG_WORK_BODY, work, fol(knob(1, 1), RACK_FRAME, BOLT_POLE), ease="in")
    key_pose(c, 0.72, LONG_WORK_BODY, work, left=lhand(POUCH_LG))
    for t in RIFLE_SHELLS:
        key_pose(c, t - 0.16, LONG_WORK_BODY, work, fol(away), ease="ease")
        key_pose(c, t, LONG_WORK_BODY, work, fol(G.RIFLE_ROUND), ease="in")
    key_pose(c, 2.76, LONG_WORK_BODY, work, fol(knob(1, 1), RACK_FRAME, BOLT_POLE))
    key_pose(c, 2.85, LONG_WORK_BODY, work, fol(knob(1, 0), RACK_FRAME, BOLT_POLE), ease="in")
    key_pose(c, 2.95, LONG_WORK_BODY, work, fol(knob(0, 0), RACK_FRAME, BOLT_POLE))
    key_pose(c, 3.22, LONG_BODY, shifted(LONG_AIM, (0, 0.02, -0.03)), LONG_SUP, ease="ease")
    key_pose(c, L, LONG_BODY, LONG_AIM, LONG_SUP)
    return c.write(arm_obj, "LongGun_Reload_Bolt", L)


def mag_reload(arm_obj, p, L=2.2):
    """LongGun_Reload_Mag (for the future carbine_556: Magazine origin at gunspec.LONG_MAG)."""
    c = clip(p, L, 68)
    work = grip((-0.12, -0.30, 1.20), gframe(pitch=12, yaw=10, roll=20), pole=(-0.8, 0.4, -0.8))
    below = add(G.LONG_MAG, (0.0, 0.0, -0.06))
    key_pose(c, 0.00, LONG_BODY, LONG_AIM, LONG_SUP)
    key_pose(c, 0.24, LONG_WORK_BODY, work, fol(G.LONG_MAG), ease="out")
    key_pose(c, 0.40, LONG_WORK_BODY, work, fol(add(G.LONG_MAG, (0.0, 0.0, -0.07))), ease="in")
    key_pose(c, 0.75, LONG_WORK_BODY, work, left=lhand(POUCH_LG))
    key_pose(c, 1.15, LONG_WORK_BODY, work, fol(below))
    key_pose(c, 1.35, LONG_WORK_BODY, shifted(work, (0, 0, 0.012)), fol(G.LONG_MAG), ease="in")
    key_pose(c, 1.60, LONG_WORK_BODY, work, fol(knob(0, 0), RACK_FRAME, BOLT_POLE))
    key_pose(c, 1.72, LONG_WORK_BODY, work, fol(knob(0, 1), RACK_FRAME, BOLT_POLE), ease="in")
    key_pose(c, 1.86, LONG_BODY, shifted(LONG_AIM, (0, 0.02, -0.03)), left=lhand((0.20, -0.30, 1.30)), ease="out")
    key_pose(c, L, LONG_BODY, LONG_AIM, LONG_SUP)
    return c.write(arm_obj, "LongGun_Reload_Mag", L)


def long_unjam(arm_obj, p, L=1.5):
    c = clip(p, L, 69)
    cant = grip((-0.12, -0.32, 1.26), gframe(pitch=6, yaw=10, roll=-38), pole=(-0.8, 0.4, -0.8))
    tap = add(G.SHOTGUN_LOAD, (0.0, 0.0, -0.01))
    back = add(G.SUPPORT_LONG, (0.0, G.PUMP_TRAVEL, 0.0))
    key_pose(c, 0.00, LONG_BODY, LONG_AIM, LONG_SUP)
    key_pose(c, 0.24, LONG_WORK_BODY, cant, fol(add(tap, (0.0, 0.0, -0.07))), ease="out")
    key_pose(c, 0.35, LONG_WORK_BODY, shifted(cant, (0, 0, 0.012)), fol(tap), ease="in3")
    key_pose(c, 0.58, LONG_WORK_BODY, cant, LONG_SUP)
    key_pose(c, 0.75, LONG_WORK_BODY, cant, fol(back, G.LEFT_FRAME_LONG, pole=(0.45, 0.2, -1.0)), ease="in")
    key_pose(c, 0.80, LONG_WORK_BODY, cant, fol(back, G.LEFT_FRAME_LONG, pole=(0.45, 0.2, -1.0)))
    key_pose(c, 0.95, LONG_WORK_BODY, cant, LONG_SUP, ease="in")
    key_pose(c, L, LONG_BODY, LONG_AIM, LONG_SUP)
    return c.write(arm_obj, "Act_Unjam_LongGun", L)


# ------------------------------------------------------------------------------------------------------------
# bow
# ------------------------------------------------------------------------------------------------------------
def bow_draw(arm_obj, p, L=1.4):
    c = clip(p, L, 70)
    mid_b = lerp_body(BOW_READY_BODY, BOW_FULL_BODY, 0.45)
    mid = grip((-0.03, -0.60, 1.36), gframe(pitch=-4, yaw=2, roll=-8), pole=(-0.9, 0.35, -0.5))
    key_pose(c, 0.00, BOW_READY_BODY, BOW_READY, BOW_SUP, ft=BOW_FEET)
    key_pose(c, 0.30, BOW_READY_BODY, shifted(BOW_READY, (0, -0.02, 0.03)),
             fol(add(G.SUPPORT_BOW, (0, 0.012, 0)), G.LEFT_FRAME_BOW, pole=(0.9, 0.5, -0.6)), ft=BOW_FEET)
    key_pose(c, 0.60, mid_b, mid, fol(add(G.SUPPORT_BOW, (0, 0.12, 0)), G.LEFT_FRAME_BOW, pole=(1.0, 0.7, -0.2)),
             ft=BOW_FEET)
    key_pose(c, 1.20, BOW_FULL_BODY, BOW_FULL, BOW_DRAWN, ft=BOW_FEET, ease="ease")
    key_pose(c, L, BOW_FULL_BODY, BOW_FULL, BOW_DRAWN, ft=BOW_FEET)
    return c.write(arm_obj, "Bow_Draw", L)


def bow_release(arm_obj, p, L=0.3):
    c = clip(p, L, 71)
    after_b = dict(BOW_FULL_BODY, ch=(26, 0, 0), hd=(-22, 8, 6))
    key_pose(c, 0.00, BOW_FULL_BODY, BOW_FULL, BOW_DRAWN, ft=BOW_FEET)
    key_pose(c, 0.03, BOW_FULL_BODY, BOW_FULL, BOW_DRAWN, ft=BOW_FEET)
    key_pose(c, 0.10, after_b, shifted(BOW_FULL, (0.0, -0.01, -0.03), gframe(pitch=-4, yaw=-2, roll=6)),
             fol(add(G.DRAW_POINT, (0.03, 0.06, 0.03)), G.LEFT_FRAME_BOW, pole=(1.0, 0.35, -0.05)), ft=BOW_FEET,
             ease="out3")
    key_pose(c, L, after_b, shifted(BOW_FULL, (0.0, 0.0, -0.05), gframe(pitch=-6, yaw=-2, roll=4)),
             fol(add(G.DRAW_POINT, (0.05, 0.08, 0.04)), G.LEFT_FRAME_BOW, pole=(1.0, 0.35, -0.05)), ft=BOW_FEET)
    return c.write(arm_obj, "Bow_Release", L)


# ------------------------------------------------------------------------------------------------------------
def build_actions(arm_obj, p=None):
    acts = [pistol_idle(arm_obj, p), pistol_aim(arm_obj, p), pistol_shoot(arm_obj, p), pistol_reload(arm_obj, p),
            revolver_reload(arm_obj, p), long_idle(arm_obj, p), long_aim(arm_obj, p), long_shoot(arm_obj, p),
            shotgun_shoot(arm_obj, p), long_pump(arm_obj, p), long_bolt_cycle(arm_obj, p), shell_loop(arm_obj, p),
            rifle_reload(arm_obj, p), mag_reload(arm_obj, p), pistol_unjam(arm_obj, p), long_unjam(arm_obj, p),
            bow_aim(arm_obj, p), bow_draw(arm_obj, p), bow_hold(arm_obj, p), bow_release(arm_obj, p)]
    problems = []
    for act in acts:
        looping, length, speed, _kind = FIREARMS_TABLE[act.name]
        problems += anim.check_action_name(act.name, looping)
        if int(act.frame_range[1]) != anim.frame_count(length):
            problems.append("%s: %d frames, want %d" % (act.name, act.frame_range[1], anim.frame_count(length)))
        if act.get("ik_clamped_frames", 0):
            problems.append("%s: %d frames with feet out of IK reach" % (act.name, act["ik_clamped_frames"]))
        if act.get("hand_clamped_frames", 0):
            problems.append("%s: %d frames with hands out of IK reach" % (act.name, act["hand_clamped_frames"]))
        act["looping"] = looping
    missing = set(FIREARMS_TABLE) - {a.name for a in acts}
    if missing:
        problems.append("missing %s" % sorted(missing))
    if problems:
        raise RuntimeError("humanoid_firearms: " + "; ".join(problems))
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
        print("  %-26s frames=%-3d" % (act.name, act.frame_range[1]))
    return glb


def main():
    rig.write_bonemap(export.BONEMAP_PATH)
    return build()


if __name__ == "__main__":
    main()
