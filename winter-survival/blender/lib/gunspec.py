"""Firearm / bow contract shared by weapons/build_firearms.py, anims/build_firearms.py and the verifiers
(ASSET_SPEC_V2 §12 + "T2").

Weapon frame (Blender, like every §12 weapon): origin = centre of the RIGHT fist on the main grip, +Z = handle axis
(toward the thumb = RightHandSocket Y), -Y = muzzle / business end (along the forearm = RightHandSocket Z). Mounted with
IDENTITY on RightHandSocket and the muzzle forward, weapon +X is the SHOOTER'S LEFT (the character's left is +X, §2.1):
parts on the shooter's right (ejection ports, the bolt handle) sit at -X, the revolver cylinder swings out to +X.
(§12 "+X = right side of the weapon" is the side seen in Blender's Front view, i.e. looking at the muzzle.)
The right hand never leaves the weapon: the left hand works slides, pumps, bolts, cylinders, magazines and strings.

All values are METRES in the final weapon frame (the x1.2 of the small arms is already applied), so the animation
builder can put the LEFT fist (LeftHandSocket = fist centre) exactly where a part is:

* SUPPORT[cls]    left fist on the weapon while aiming / shooting (the `SupportGrip` empty, TwoBoneIK3D target);
* LEFT_FRAME[cls] orientation of the left fist there, (shaft, edge) = the LeftHandSocket Y / Z axes in weapon axes
  (keyanim.grip convention: socket Y = shaft, socket Z = edge);
* loose parts (Magazine, Round, Arrow) have their ORIGIN at the left fist centre that carries them and no rotation:
  the code attaches them with identity to LeftHandSocket while carried, and at the insert event (mag_in / shell_in)
  the left socket frame coincides with the part's rest transform in the weapon (the clips are authored that way).
"""
import math

from mathutils import Matrix, Vector

PISTOL_SCALE = 1.2          # §12: x1.2 on small arms (pistol, revolver); already applied to every number below
SHOOTER_RIGHT = -1.0        # sign of X on the shooter's right side


def _grip_axis(deg):
    a = math.radians(deg)
    return Vector((0.0, -math.sin(a), math.cos(a)))      # up the grip: its bottom leans back (+Y)


# ---- class Pistol (pistol + revolver share every Pistol_* clip) ------------------------------------------------
PISTOL_BORE_Z = 0.074
SUPPORT_PISTOL = (0.040, -0.012, -0.030)                          # left fist wrapped over the right one (thumbs fwd)
LEFT_FRAME_PISTOL = ((0.0, -0.8, 0.6), (0.0, -0.6, -0.8))
GRIP_TILT_DEG = 17.0
GRIP_AXIS = _grip_axis(GRIP_TILT_DEG)
PISTOL_GRIP_T = (-0.090, 0.048)                                   # grip span along GRIP_AXIS
PISTOL_MAG_T = (-0.097, 0.030)                                    # magazine: base plate bottom .. top
PISTOL_MAG_HOLD = 0.024                                           # fist centre below the base plate
PISTOL_MAG = tuple(GRIP_AXIS * (PISTOL_MAG_T[0] - PISTOL_MAG_HOLD))
PISTOL_SLIDE = (-0.152, 0.083)                                    # slide y span (muzzle face .. rear)
PISTOL_SLIDE_TRAVEL = 0.036
PISTOL_RACK = (0.0, 0.064, 0.120)                                 # left fist gripping the slide rear (overhand)

# revolver: the cylinder (+ crane) swings out to the shooter's LEFT (+X) about the crane hinge (parallel to the bore)
REVOLVER_CYL_Z = 0.060                                            # cylinder axis (the bore = top chamber, 0.074)
REVOLVER_CYL_Y = (-0.060, -0.006)                                 # cylinder y span
REVOLVER_CYL_R = 0.026
REVOLVER_HINGE = (0.006, -0.033, 0.024)                           # `Cylinder` origin (on the hinge axis)
REVOLVER_SWING_DEG = 85.0


def revolver_swing():
    """Rotation (Blender, about the hinge axis = +Y) that swings the cylinder out to +X."""
    return Matrix.Rotation(math.radians(REVOLVER_SWING_DEG), 3, 'Y')


def revolver_open_center():
    h = Vector(REVOLVER_HINGE)
    c = Vector((0.0, h.y, REVOLVER_CYL_Z))
    return h + revolver_swing() @ (c - h)


REVOLVER_PUSH = (0.034, -0.040, 0.030)          # left fist (thumb) pushing the cylinder out / closing it
REVOLVER_ROUND = tuple(revolver_open_center() + Vector((0.0, 0.046, 0.004)))   # left fist at a chamber mouth

# ---- class LongGun (shotgun + rifle share LongGun_Aim / Shoot / Idle) --------------------------------------------
SUPPORT_LONG = (0.0, -0.320, 0.036)
LEFT_FRAME_LONG = ((0.82, -0.42, 0.38), (-0.40, -0.88, 0.20))    # palm up under the forend, fingers over its far side
PUMP_TRAVEL = 0.085                                               # shotgun Pump slides back (+Y Blender = -Z Godot)
SHOTGUN_BORE_Z = 0.088
SHOTGUN_LOAD = (0.0, -0.150, -0.030)                              # Round (shell) origin: left fist under the port
RIFLE_BORE_Z = 0.084
RIFLE_BOLT = (0.0, -0.022, RIFLE_BORE_Z)                          # `Bolt` origin on the bore axis
RIFLE_BOLT_KNOB = (-0.052, -0.004, 0.058)                         # bolt knob (closed), shooter's right
RIFLE_BOLT_LIFT_DEG = 60.0                                        # rotation about +Y Blender (handle up)
RIFLE_BOLT_TRAVEL = 0.080                                         # then back along +Y Blender


def rifle_bolt_knob(lift=0.0, back=0.0):
    """Bolt knob position for a lift fraction (0..1 of RIFLE_BOLT_LIFT_DEG) and a travel fraction (0..1)."""
    o = Vector(RIFLE_BOLT)
    r = Matrix.Rotation(math.radians(RIFLE_BOLT_LIFT_DEG * lift), 3, 'Y')
    return o + r @ (Vector(RIFLE_BOLT_KNOB) - o) + Vector((0.0, RIFLE_BOLT_TRAVEL * back, 0.0))


RIFLE_ROUND = (-0.072, -0.080, 0.096)                             # Round origin: left fist right of the port
LONG_MAG = (0.0, -0.090, -0.170)                                  # future carbine_556 Magazine origin (Reload_Mag)

# ---- class Bow (held in the RIGHT hand like every weapon; the left hand nocks and draws) -------------------------
BOW_NOCK_Z = 0.030
BOW_BRACE = 0.180
BOW_DRAW = 0.620
SUPPORT_BOW = (0.0, 0.200, 0.008)                                 # left fist on the string at brace (nocking)
DRAW_POINT = (0.0, 0.640, 0.008)                                  # left fist at full draw
LEFT_FRAME_BOW = ((0.0, 0.0, 1.0), (0.0, -1.0, 0.0))
ARROW_LEN = 0.70

SUPPORT = {"Pistol": SUPPORT_PISTOL, "LongGun": SUPPORT_LONG, "Bow": SUPPORT_BOW}
LEFT_FRAME = {"Pistol": LEFT_FRAME_PISTOL, "LongGun": LEFT_FRAME_LONG, "Bow": LEFT_FRAME_BOW}
IDENTITY_FRAME = ((0.0, 0.0, 1.0), (0.0, -1.0, 0.0))             # left fist frame = weapon frame (loose parts)

# ---- per weapon: class, built length (m), caliber, capacity, anchors (weapon frame, final metres) ----------------
# Muzzle = bore exit (projectile / flash origin, local -Y out), Sight = eye line point, EjectPort / LoadPort.
FIREARMS = {
    "pistol": dict(cls="Pistol", length=0.24, caliber="9mm", capacity=15,
                   anchors={"Grip": (0, 0, 0), "Muzzle": (0.0, PISTOL_SLIDE[0] - 0.001, PISTOL_BORE_Z),
                            "SupportGrip": SUPPORT_PISTOL, "EjectPort": (-0.016, -0.020, 0.086),
                            "Sight": (0.0, 0.072, 0.100)},
                   parts={"Slide": (0.0, 0.0, PISTOL_BORE_Z), "Magazine": PISTOL_MAG}),
    "revolver": dict(cls="Pistol", length=0.32, caliber="357", capacity=6,
                     anchors={"Grip": (0, 0, 0), "Muzzle": (0.0, -0.252, PISTOL_BORE_Z),
                              "SupportGrip": SUPPORT_PISTOL, "Sight": (0.0, 0.034, 0.104)},
                     parts={"Cylinder": REVOLVER_HINGE, "Round": REVOLVER_ROUND}),
    "shotgun": dict(cls="LongGun", length=1.0, caliber="12g", capacity=6,
                    anchors={"Grip": (0, 0, 0), "Muzzle": (0.0, -0.701, SHOTGUN_BORE_Z),
                             "SupportGrip": SUPPORT_LONG, "EjectPort": (-0.022, -0.120, 0.098),
                             "LoadPort": (0.0, -0.150, 0.050), "Sight": (0.0, -0.690, 0.110)},
                    parts={"Pump": (0.0, SUPPORT_LONG[1], 0.060), "Round": SHOTGUN_LOAD}),
    "rifle_hunting": dict(cls="LongGun", length=1.1, caliber="308", capacity=5,
                          anchors={"Grip": (0, 0, 0), "Muzzle": (0.0, -0.791, RIFLE_BORE_Z),
                                   "SupportGrip": SUPPORT_LONG, "EjectPort": (-0.018, -0.080, 0.096),
                                   "Sight": (0.0, 0.060, 0.142)},
                          parts={"Bolt": RIFLE_BOLT, "Scope": (0.0, -0.075, 0.142), "Round": RIFLE_ROUND}),
    "bow": dict(cls="Bow", length=1.26, caliber="arrow", capacity=1,
                anchors={"Grip": (0, 0, 0), "Muzzle": (0.0, -0.030, BOW_NOCK_Z), "SupportGrip": SUPPORT_BOW,
                         "DrawPoint": DRAW_POINT},
                parts={"String": (0, 0, 0), "StringDrawn": (0, 0, 0), "Arrow": (0.0, BOW_BRACE, BOW_NOCK_Z)}),
}


def weapon_basis(shaft, edge):
    """World axes (ex, ey, ez) of the weapon frame whose +Z = `shaft` and -Y = `edge` (keyanim.grip convention)."""
    ez = Vector(shaft).normalized()
    ey = -Vector(edge).normalized()
    ey = (ey - ez * ey.dot(ez)).normalized()
    ex = ey.cross(ez).normalized()
    return ex, ey, ez


def to_world(grip, shaft, edge, local):
    """Weapon-frame point `local` -> world, for a weapon whose grip / shaft / edge are known."""
    ex, ey, ez = weapon_basis(shaft, edge)
    lx, ly, lz = local
    return Vector(grip) + ex * lx + ey * ly + ez * lz


def dir_to_world(shaft, edge, local_dir):
    ex, ey, ez = weapon_basis(shaft, edge)
    lx, ly, lz = local_dir
    return (ex * lx + ey * ly + ez * lz).normalized()
