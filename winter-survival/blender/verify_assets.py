"""Verify every exported slice .glb against docs/v2/ASSET_SPEC_V2.md (§2, §16, §17) + the slice
contract it inherits (docs/ASSET_SPEC.md §4-§6: names, hierarchy, pivots, sizes, budgets, collision).

Run:  cd winter-survival/blender && python3 verify_assets.py      (exit code 0 = ALL OK)
Prints one line per asset (`OK name tris=.. surfaces=.. dims=.. objects=[..]` or `FAIL name: reason`) and
ends with `ALL OK` or `N FAILURES`.

v2 checks on top of the slice ones:
  * front = -Y Blender (+Z Godot): front anchors (Muzzle, BreathAnchor, DoorAnchor, StoveAnchor, TextTop, ...)
    at y < 0; the stone_axe blade toward -Y;
  * glTF level: every primitive of a mesh whose material is palette_vcol carries COLOR_0; <= 2 primitives
    (surfaces) per mesh; only palette_vcol + the named exception materials; no TEXCOORD, no images;
    no '.' in any node/mesh/material name (no `.001`); every COLOR_0 value, as Godot stores it (RGBA8
    linear, truncated), is exactly the nearest 8-bit linear value of a palette colour (white on exception
    primitives) -- see lib/palette.py GODOT_BIAS;
  * re-import: exactly one corner colour attribute on every mesh that uses palette_vcol; one colour per
    face; palette_vcol faces carry a palette colour (+-1/255 of the stored value); exception faces white;
  * cabin <= 12 surfaces (cutaway groups + window panes).
Assets marked R180 were authored in the slice convention and rotated 180 degrees about Z by lib.lowpoly
(new_scene(authored_front="+Y")); their slice pivots/collision boxes below are rotated the same way here.
"""
import json
import math
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
from mathutils import Euler, Vector  # noqa: E402

from lib import export  # noqa: E402
from lib import palette  # noqa: E402

PIVOT_TOL = 0.03
DIM_TOL = 0.10
COL_TOL = 0.02
TOTAL_BUDGET = 12000
BUDGET_SLACK = 1.2
MAX_SURFACES_PER_MESH = 2

ZERO = (0.0, 0.0, 0.0)


def a(pri, budget, pivots, parents=None, dims=None, minz=0.0, extra=None, col=None, dims_of=None, r180=False,
      max_surfaces=None):
    return dict(pri=pri, budget=budget, pivots=pivots, parents=parents or {}, dims=dims or {}, minz=minz,
                extra=extra or {}, col=col or {}, dims_of=dims_of or {}, r180=r180, max_surfaces=max_surfaces)


QUAD_PARENTS = {"Head": "Body", "Tail": "Body", "LegFL": "Body", "LegFR": "Body", "LegBL": "Body",
                "LegBR": "Body", "Muzzle": "Head"}

# slice coordinates (porch toward +Y); the cabin is R180 -> e.g. ColWallFrontL x 1.4..3.0, y -2.5..-2.32
CABIN_COL = {
    "ColFoundation": ((-3.0, -2.5, 0.0), (3.0, 2.5, 0.30)),
    "ColPorch": ((-3.0, 2.5, 0.0), (3.0, 4.5, 0.30)),
    "ColSteps": ((-1.5, 4.5, 0.0), (-0.3, 5.3, 0.30)),
    "ColWallBack": ((-3.0, -2.5, 0.30), (3.0, -2.32, 3.0)),
    "ColWallLeft": ((-3.0, -2.5, 0.30), (-2.82, 2.5, 3.0)),
    "ColWallRight": ((2.82, -2.5, 0.30), (3.0, 2.5, 3.0)),
    "ColWallFrontL": ((-3.0, 2.32, 0.30), (-1.4, 2.5, 3.0)),
    "ColWallFrontR": ((-0.4, 2.32, 0.30), (3.0, 2.5, 3.0)),
    "ColDoorTop": ((-1.4, 2.32, 2.40), (-0.4, 2.5, 3.0)),
    "ColChimney": ((-3.7, 0.25, 0.0), (-3.0, 0.95, 3.0)),
    "ColRailFrontL": ((-3.0, 4.42, 0.30), (-1.5, 4.5, 1.3)),
    "ColRailFrontR": ((-0.3, 4.42, 0.30), (3.0, 4.5, 1.3)),
    "ColRailLeft": ((-3.0, 2.5, 0.30), (-2.92, 4.5, 1.3)),
    "ColRailRight": ((2.92, 2.5, 0.30), (3.0, 4.5, 1.3)),
}

ASSETS = {
    "player": a(0, 700, {"Hips": (0, 0, 0.80), "Torso": (0, 0, 0.80), "Head": (0, 0, 1.36),
                         "BreathAnchor": (0, 0.20, 1.52), "ArmL": (-0.36, 0, 1.32), "ArmR": (0.36, 0, 1.32),
                         "ToolSocket": (0.36, 0.05, 0.80), "LegL": (-0.12, 0, 0.80), "LegR": (0.12, 0, 0.80)},
                parents={"ToolSocket": "ArmR", "BreathAnchor": "Head", "Head": "Torso", "ArmL": "Torso",
                         "ArmR": "Torso", "Torso": "Hips", "LegL": "Hips", "LegR": "Hips"},
                dims={"z": 1.80}, extra={"forward": ["BreathAnchor"]}, r180=True),
    "wolf": a(0, 600, {"Body": (0, 0, 0.55), "Head": (0, 0.45, 0.62), "Muzzle": (0, 0.93, 0.58),
                       "Tail": (0, -0.45, 0.62), "LegFL": (-0.13, 0.30, 0.42), "LegFR": (0.13, 0.30, 0.42),
                       "LegBL": (-0.13, -0.30, 0.42), "LegBR": (0.13, -0.30, 0.42)},
              parents=QUAD_PARENTS, dims={"y": 1.85, "x": 0.36}, dims_of={"Body": {"zmax": 0.75}},
              extra={"forward": ["Muzzle"]}, r180=True),
    "deer": a(1, 800, {"Body": (0, 0, 0.90), "Head": (0, 0.60, 1.00), "Muzzle": (0, 1.05, 1.35),
                       "LegFL": (-0.14, 0.42, 0.70), "LegFR": (0.14, 0.42, 0.70),
                       "LegBL": (-0.14, -0.42, 0.70), "LegBR": (0.14, -0.42, 0.70), "Tail": None},
              parents=QUAD_PARENTS, dims={"z": 1.65}, extra={"forward": ["Muzzle"]}, r180=True),
    "pine_a": a(0, 350, {"Tree": ZERO}, dims={"z": 7.0}),
    "pine_b": a(0, 300, {"Tree": ZERO}, dims={"z": 5.5}),
    "pine_c": a(0, 300, {"Tree": ZERO}, dims={"z": 4.0}),
    "dead_tree": a(0, 250, {"Tree": ZERO}, dims={"z": 4.5}),
    "stump": a(0, 80, {"Stump": ZERO}, dims={"x": 0.6, "y": 0.6, "z": 0.45}),
    "rock_a": a(0, 160, {"Rock": ZERO}, dims={"x": 1.2, "y": 1.0, "z": 0.7}),
    "rock_b": a(0, 160, {"Rock": ZERO}, dims={"x": 2.2, "y": 1.8, "z": 1.2}),
    "rock_c": a(1, 160, {"Rock": ZERO}, dims={"x": 0.6, "y": 0.5, "z": 0.35}),
    "stone": a(0, 40, {"Stone": ZERO}, dims={"x": 0.30, "y": 0.25, "z": 0.20}),
    "berry_bush": a(0, 400, {"Bush": ZERO, "Berries": ZERO}, parents={"Berries": "Bush"},
                    dims={"x": 1.0, "y": 1.0, "z": 0.55}),
    "firewood": a(0, 120, {"Firewood": ZERO}, dims={"x": 0.55, "y": 0.55, "z": 0.22}),
    "fallen_log": a(0, 120, {"Log": ZERO}, dims={"x": 1.6, "z": 0.40}),
    "campfire": a(0, 400, {"Stones": ZERO, "Logs": ZERO, "FlameAnchor": (0, 0, 0.18)},
                  dims={"x": 1.2, "y": 1.2, "z": 0.35}),
    # weapon convention (v2 §12): origin at the grip, handle +Z, useful end (blade) toward -Y
    "stone_axe": a(0, 100, {"Handle": ZERO, "Blade": ZERO}, dims={"z": 0.55}, minz=-0.05,
                   extra={"useful_end": "Blade"}),
    "torch": a(0, 80, {"Handle": ZERO, "Head": ZERO, "FlameAnchor": (0, 0, 0.54)}, dims={"z": 0.52}),
    "cabin": a(0, 2500, {"Floor": ZERO, "WallFront": ZERO, "WindowsFront": ZERO, "WallBack": ZERO,
                         "WallLeft": ZERO, "WindowsLeft": ZERO, "WallRight": ZERO, "Roof": ZERO, "Chimney": ZERO,
                         "Porch": ZERO, "DoorAnchor": (-0.9, 3.2, 0.30), "LanternSocket": (-1.6, 4.3, 2.35)},
               parents={"WindowsFront": "WallFront", "WindowsLeft": "WallLeft"},
               dims={"x": 7.1, "y": 8.2, "z": 5.3}, col=CABIN_COL,
               extra={"forward": ["DoorAnchor", "LanternSocket"], "window": ["WindowsFront", "WindowsLeft"],
                      "front_mesh": {"WallFront": "<", "WallBack": ">", "WallLeft": "x>", "WallRight": "x<",
                                     "Chimney": "x>", "Porch": "<"}},
               r180=True, max_surfaces=12),
    "wood_stove": a(0, 250, {"Body": ZERO, "Door": ZERO, "Pipe": ZERO, "StoveAnchor": (0, 0.35, 0.45),
                             "PipeTop": (0, -0.15, 2.70)},
                    dims={"x": 0.66, "y": 0.66, "z": 2.70}, extra={"forward": ["StoveAnchor"], "ember": ["Door"]},
                    r180=True),
    # depth checked against the 0.56 cornice (the spec's own cornice is deeper than the 0.50 body)
    "cabinet": a(0, 120, {"Cabinet": ZERO}, dims={"x": 0.90, "y": 0.56, "z": 1.80}, r180=True),
    "bed": a(1, 150, {"Bed": ZERO}, dims={"x": 1.0, "y": 2.0}, r180=True),
    "desk": a(1, 150, {"Desk": ZERO}, dims={"x": 1.40, "y": 0.60}, r180=True),
    "chair": a(1, 120, {"Chair": ZERO}, dims={"x": 0.45, "y": 0.45, "z": 0.90}, r180=True),
    "shelf": a(1, 250, {"Shelf": ZERO, "Jars": ZERO}, parents={"Jars": "Shelf"}, dims={"x": 0.90, "y": 0.25},
               minz=None, extra={"front_mesh": {"Shelf": "<"}}, r180=True),
    "clock": a(1, 120, {"Clock": ZERO, "HourHand": (0, 0.07, 0), "MinuteHand": (0, 0.075, 0)},
               dims={"x": 0.36, "z": 0.36}, minz=None, extra={"forward": ["HourHand", "MinuteHand"]}, r180=True),
    "a_frame_cabin": a(1, 600, {"Body": ZERO, "Front": ZERO, "WindowsFront": ZERO, "Deck": ZERO},
                       parents={"WindowsFront": "Front"}, dims={"x": 6.0, "y": 8.5, "z": 6.0},
                       col={"ColBody": ((-3.0, -3.5, 0.0), (3.0, 3.5, 6.0)),
                            "ColDeck": ((-2.0, 3.5, 0.0), (2.0, 5.0, 0.25))},
                       extra={"window": ["WindowsFront"], "front_mesh": {"Deck": "<", "WindowsFront": "<"}},
                       r180=True),
    "pickup_truck": a(1, 900, {"Body": ZERO, "Wheels": ZERO, "Snow": ZERO, "BedAnchor": (0, -1.35, 1.0)},
                      dims={"x": 2.0, "y": 5.0, "z": 1.95},
                      col={"ColChassis": ((-1.0, -2.5, 0.3), (1.0, 2.5, 1.3)),
                           "ColCab": ((-0.95, -0.2, 1.3), (0.95, 1.0, 2.0))},
                      extra={"back": ["BedAnchor"], "window": ["Body"]}, r180=True),
    # authored directly in v2: boards point to +X, text faces -Y, text empties unrotated
    "signpost": a(1, 150, {"Post": ZERO, "BoardTop": (0, 0, 1.84), "BoardBottom": (0, 0, 1.44),
                           "TextTop": (0.28, -0.125, 1.84), "TextBottom": (0.28, -0.125, 1.44)},
                  parents={"TextTop": "BoardTop", "TextBottom": "BoardBottom"}, dims={"z": 2.2},
                  extra={"forward": ["TextTop", "TextBottom"], "tip": "BoardTop",
                         "front_mesh": {"BoardTop": "<", "BoardBottom": "<"}}),
    "fence": a(1, 120, {"Fence": ZERO}, dims={"x": 2.0, "z": 1.1}),
    "lantern": a(1, 120, {"Lantern": ZERO, "LightAnchor": (0, 0, -0.23)}, dims={"z": 0.40}, minz=-0.40,
                 extra={"maxz": 0.0, "window": ["Lantern"]}),
    "tent": a(2, 250, {"Tent": ZERO}, dims={"x": 2.4, "y": 2.6, "z": 1.7},
              col={"ColBack": ((-1.2, -1.3, 0.0), (1.2, -1.2, 1.7))}, r180=True),
    "storage_box": a(2, 150, {"Box": ZERO}, dims={"x": 0.8, "y": 0.6, "z": 0.6}, r180=True),
}

# final (exported) XYZ Euler degrees of the only rotated empty
ROTATED = dict(export.ROTATED_SOCKETS)


def rot180(p):
    return (-p[0], -p[1], p[2])


def rot180_box(box):
    mn, mx = box
    return ((-mx[0], -mx[1], mn[2]), (-mn[0], -mn[1], mx[2]))


def final_spec(spec):
    """Expected values in final (FRONT = -Y) coordinates."""
    if not spec["r180"]:
        return spec
    s = dict(spec)
    s["pivots"] = {k: (rot180(v) if v is not None else None) for k, v in spec["pivots"].items()}
    s["col"] = {k: rot180_box(v) for k, v in spec["col"].items()}
    return s


def is_col(o):
    return export.is_col(o.name)


def world_bounds(objs):
    mn = Vector((1e9, 1e9, 1e9))
    mx = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        for v in o.data.vertices:
            w = o.matrix_world @ v.co
            for i in range(3):
                mn[i] = min(mn[i], w[i])
                mx[i] = max(mx[i], w[i])
    return mn, mx


def tris_of(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def winding_problems(o):
    """Closed components (vertices merged by position) must be consistently wound with positive volume."""
    me = o.data
    key = {}
    vid = []
    for v in me.vertices:
        k = tuple(round(c, 4) for c in v.co)
        vid.append(key.setdefault(k, len(key)))
    pos = {i: Vector(k) for k, i in key.items()}
    polys = [[vid[i] for i in p.vertices] for p in me.polygons]
    edges = {}
    for pi, p in enumerate(polys):
        for i in range(len(p)):
            e = (p[i], p[(i + 1) % len(p)])
            edges.setdefault(frozenset(e), []).append((pi, e))
    parent = list(range(len(polys)))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x
    for lst in edges.values():
        for (pa, _), (pb, _) in zip(lst, lst[1:]):
            parent[find(pa)] = find(pb)
    comps = {}
    for pi in range(len(polys)):
        comps.setdefault(find(pi), []).append(pi)
    bad = 0
    for faces in comps.values():
        fs = set(faces)
        closed = True
        consistent = True
        for lst in edges.values():
            if lst[0][0] not in fs:
                continue
            if len(lst) != 2:
                closed = False
                break
            if lst[0][1] == lst[1][1]:
                consistent = False
        if not closed:
            continue
        vol = 0.0
        for pi in faces:
            p = polys[pi]
            for i in range(1, len(p) - 1):
                vol += pos[p[0]].dot(pos[p[i]].cross(pos[p[i + 1]])) / 6.0
        if not consistent or vol < -1e-9:
            bad += 1
    return bad


def check_collision(o, box):
    problems = []
    if o.parent is not None:
        problems.append("%s has a parent" % o.name)
    pts = {tuple(round(c, 4) for c in (o.matrix_world @ v.co)) for v in o.data.vertices}
    if len(pts) not in (6, 8):
        problems.append("%s has %d unique vertices" % (o.name, len(pts)))
    planes = []
    mw = o.matrix_world
    for p in o.data.polygons:
        n = (mw.to_3x3() @ p.normal).normalized()
        d = n.dot(mw @ o.data.vertices[p.vertices[0]].co)
        if not any((n - q[0]).length < 1e-3 and abs(d - q[1]) < 1e-3 for q in planes):
            planes.append((n, d))
    if len(planes) not in (5, 6):
        problems.append("%s has %d faces" % (o.name, len(planes)))
    for n, d in planes:
        if any(n.dot(Vector(p)) - d > 1e-3 for p in pts):
            problems.append("%s is not convex/outward" % o.name)
            break
    mn = [min(p[i] for p in pts) for i in range(3)]
    mx = [max(p[i] for p in pts) for i in range(3)]
    for i in range(3):
        if abs(mn[i] - box[0][i]) > COL_TOL or abs(mx[i] - box[1][i]) > COL_TOL:
            problems.append("%s bounds %s..%s != %s..%s" % (o.name, [round(x, 3) for x in mn],
                                                              [round(x, 3) for x in mx], box[0], box[1]))
            break
    return problems


# ------------------------------------------------------------------------------------------------
# glTF JSON level (what Godot actually receives)
# ------------------------------------------------------------------------------------------------
def load_glb(path):
    """(json, BIN chunk bytes)."""
    b = open(path, "rb").read()
    n = struct.unpack_from("<I", b, 12)[0]
    g = json.loads(b[20:20 + n])
    off = 20 + n
    binary = b""
    if off + 8 <= len(b):
        blen = struct.unpack_from("<I", b, off)[0]
        binary = b[off + 8:off + 8 + blen]
    return g, binary


def read_accessor(g, binary, idx):
    acc = g["accessors"][idx]
    bv = g["bufferViews"][acc["bufferView"]]
    fmt, size, norm = {5126: ("f", 4, 1.0), 5121: ("B", 1, 255.0), 5123: ("H", 2, 65535.0)}[acc["componentType"]]
    ncomp = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[acc["type"]]
    stride = bv.get("byteStride", size * ncomp)
    off = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    out = []
    for i in range(acc["count"]):
        vals = struct.unpack_from("<%d%s" % (ncomp, fmt), binary, off + i * stride)
        out.append(tuple(v / norm for v in vals) if fmt != "f" else vals)
    return out


def gltf_problems(g, binary, godot_targets):
    problems = []
    allowed = export.allowed_materials()
    for key in ("images", "textures", "samplers"):
        if g.get(key):
            problems.append("glTF has %s" % key)
    for coll in ("nodes", "meshes", "materials"):
        for item in g.get(coll, []):
            if "." in item.get("name", ""):
                problems.append("dotted %s name %s" % (coll[:-1], item["name"]))
    mats = g.get("materials", [])
    for m in mats:
        if m.get("name") not in allowed:
            problems.append("material %s not allowed" % m.get("name"))
    surfaces = 0
    by_mesh = {}
    for nd in g["nodes"]:
        if "mesh" not in nd or export.is_col(nd["name"]):
            continue
        mesh = g["meshes"][nd["mesh"]]
        prims = mesh["primitives"]
        surfaces += len(prims)
        by_mesh[nd["name"]] = len(prims)
        if len(prims) > MAX_SURFACES_PER_MESH:
            problems.append("%s has %d surfaces (max %d)" % (nd["name"], len(prims), MAX_SURFACES_PER_MESH))
        names = [mats[p["material"]]["name"] if "material" in p else None for p in prims]
        if len(set(names)) != len(names):
            problems.append("%s has duplicated materials %s" % (nd["name"], names))
        for p, mn in zip(prims, names):
            if mn is None:
                problems.append("%s: primitive without material" % nd["name"])
            if any(k.startswith("TEXCOORD") for k in p["attributes"]):
                problems.append("%s has UVs" % nd["name"])
            if mn == palette.VCOL_MATERIAL and "COLOR_0" not in p["attributes"]:
                problems.append("%s: palette_vcol primitive without COLOR_0" % nd["name"])
            if "COLOR_1" in p["attributes"]:
                problems.append("%s has more than one colour set" % nd["name"])
            if "COLOR_0" in p["attributes"]:
                got = {palette.godot_bytes(c) for c in read_accessor(g, binary, p["attributes"]["COLOR_0"])}
                want = godot_targets if mn == palette.VCOL_MATERIAL else {(255, 255, 255)}
                bad = sorted(got - want)
                if bad:
                    problems.append("%s[%s]: %d COLOR_0 value(s) off the palette as Godot stores them, e.g. %s"
                                    % (nd["name"], mn, len(bad), bad[:3]))
    return problems, surfaces


def reimport_targets():
    """sRGB bytes the Blender importer gives back for every palette colour (from the stored biased value)."""
    def srgb(x):
        return 12.92 * x if x <= 0.0031308 else 1.055 * x ** (1 / 2.4) - 0.055
    return {n: tuple(int(round(srgb(c) * 255)) for c in palette.vcol_rgba(n)[:3]) for n in palette.all_names()}


def colour_problems(o, allowed_bytes):
    """Every palette_vcol face: one palette colour (+-1/255 of the stored value); exception faces: white."""
    me = o.data
    uses_vcol = any(m is not None and m.name == palette.VCOL_MATERIAL for m in me.materials)
    attrs = list(me.color_attributes)
    if not uses_vcol:
        return []
    if len(attrs) != 1:
        return ["%s has %d colour attributes (want 1)" % (o.name, len(attrs))]
    attr = attrs[0]
    if attr.domain != 'CORNER' and attr.domain != 'POINT':
        return ["%s colour attribute domain %s" % (o.name, attr.domain)]
    n = len(attr.data)
    flat = [0.0] * (n * 4)
    key = "color_srgb" if hasattr(attr.data[0], "color_srgb") else "color"
    attr.data.foreach_get(key, flat)

    def col_of(i):
        c = flat[i * 4:i * 4 + 3]
        if key == "color":
            c = [(1.055 * x ** (1 / 2.4) - 0.055) if x > 0.0031308 else 12.92 * x for x in c]
        return tuple(int(round(x * 255)) for x in c)
    bad_face = bad_col = bad_exc = 0
    allowed = list(allowed_bytes.values())
    cache = {}
    for p in me.polygons:
        idx = p.loop_indices if attr.domain == 'CORNER' else [me.loops[li].vertex_index for li in p.loop_indices]
        cols = {col_of(i) for i in idx}
        if len(cols) != 1:
            bad_face += 1
            continue
        c = cols.pop()
        mat = me.materials[p.material_index]
        if mat is not None and mat.name == palette.VCOL_MATERIAL:
            if c not in cache:
                cache[c] = any(all(abs(c[k] - b[k]) <= 1 for k in range(3)) for b in allowed)
            if not cache[c]:
                bad_col += 1
        elif c != (255, 255, 255):
            bad_exc += 1
    out = []
    if bad_face:
        out.append("%d faces of %s with mixed corner colours" % (bad_face, o.name))
    if bad_col:
        out.append("%d palette_vcol faces of %s with a non-palette colour" % (bad_col, o.name))
    if bad_exc:
        out.append("%d exception-material faces of %s not white" % (bad_exc, o.name))
    return out


def front_mesh_problems(by, rules):
    """Coarse position checks of whole parts (e.g. the cabin's WallFront must be at y < 0)."""
    out = []
    for n, rule in rules.items():
        if n not in by:
            continue
        mn, mx = world_bounds([by[n]])
        c = (mn + mx) * 0.5
        ok = {"<": c.y < 0, ">": c.y > 0, "x>": c.x > 0, "x<": c.x < 0}[rule]
        if not ok:
            out.append("%s centre %s violates %s (front = -Y)" % (n, tuple(round(v, 2) for v in c), rule))
    return out


def verify(name, spec0, allowed_bytes, godot_targets):
    """Returns (status, message, tris, surfaces)."""
    spec = final_spec(spec0)
    glb = export.MODELS_DIR / ("%s.glb" % name)
    blend = export.SOURCES_DIR / ("%s.blend" % name)
    if not glb.exists() or not blend.exists():
        if spec["pri"] >= 2:
            return "SKIP", "SKIP %s (P2, not built)" % name, 0, 0
        return "FAIL", "FAIL %s: missing %s" % (name, "glb" if not glb.exists() else "blend"), 0, 0
    with open(glb, "rb") as f:
        head = f.read(4)
    if glb.stat().st_size <= 1024 or head != b"glTF":
        return "FAIL", "FAIL %s: glb too small or bad header" % name, 0, 0

    g, binary = load_glb(glb)
    problems, surfaces = gltf_problems(g, binary, godot_targets)
    if spec["max_surfaces"] is not None and surfaces > spec["max_surfaces"]:
        problems.append("%d surfaces > %d" % (surfaces, spec["max_surfaces"]))

    export.reimport(glb)
    objs = list(bpy.data.objects)
    by = {o.name: o for o in objs}

    # names
    for req in spec["pivots"]:
        if req not in by:
            problems.append("missing %s" % req)
    for o in objs:
        if "." in o.name:
            problems.append("dotted name %s" % o.name)
        if "-" in o.name and not is_col(o):
            problems.append("bad suffix %s" % o.name)
        if o.name.startswith("Col") and not is_col(o):
            problems.append("Col object without -convcolonly: %s" % o.name)
        if o.type not in ('MESH', 'EMPTY'):
            problems.append("stray %s %s" % (o.type, o.name))
    col_objs = [o for o in objs if is_col(o)]
    want_col = set(n + "-convcolonly" for n in spec["col"])
    have_col = set(o.name for o in col_objs)
    if want_col != have_col:
        problems.append("collision set mismatch: missing %s extra %s" % (sorted(want_col - have_col),
                                                                       sorted(have_col - want_col)))
    # hierarchy
    for child, par in spec["parents"].items():
        if child in by and (by[child].parent is None or by[child].parent.name != par):
            problems.append("%s parent is %s, expected %s" % (
                child, by[child].parent.name if by[child].parent else None, par))
    # pivots
    for n, piv in spec["pivots"].items():
        if piv is None or n not in by:
            continue
        w = by[n].matrix_world.translation
        if (w - Vector(piv)).length > PIVOT_TOL:
            problems.append("pivot %s at %s, expected %s" % (n, tuple(round(c, 3) for c in w), piv))
    # front = -Y
    for n in spec["extra"].get("forward", []):
        if n in by and by[n].matrix_world.translation.y >= 0:
            problems.append("%s not in front (-Y)" % n)
    for n in spec["extra"].get("back", []):
        if n in by and by[n].matrix_world.translation.y <= 0:
            problems.append("%s not at the back (+Y)" % n)
    problems += front_mesh_problems(by, spec["extra"].get("front_mesh", {}))
    tip = spec["extra"].get("tip")
    if tip and tip in by:
        mx = max((by[tip].matrix_world @ v.co).x for v in by[tip].data.vertices)
        if mx <= 0.8:
            problems.append("%s tip max x %.2f <= 0.8" % (tip, mx))
    ue = spec["extra"].get("useful_end")
    if ue and ue in by:
        mn_ue, mx_ue = world_bounds([by[ue]])
        if mn_ue.y > -0.15 or mx_ue.y > 0.06:
            problems.append("%s not toward -Y (y %.2f..%.2f)" % (ue, mn_ue.y, mx_ue.y))
    # dimensions
    vis = [o for o in objs if o.type == 'MESH' and not is_col(o)]
    mn, mx = world_bounds(vis)
    size = mx - mn
    for ax, want in spec["dims"].items():
        got = size["xyz".index(ax)]
        if abs(got - want) > DIM_TOL * want:
            problems.append("size %s %.3f vs %.3f" % (ax, got, want))
    for n, d in spec["dims_of"].items():
        if n in by and "zmax" in d:
            z = world_bounds([by[n]])[1].z
            if abs(z - d["zmax"]) > DIM_TOL * d["zmax"]:
                problems.append("%s top %.3f vs %.3f" % (n, z, d["zmax"]))
    if spec["minz"] is not None and abs(mn.z - spec["minz"]) > 0.02:
        problems.append("min z %.3f, expected %.2f" % (mn.z, spec["minz"]))
    if "maxz" in spec["extra"] and abs(mx.z - spec["extra"]["maxz"]) > 0.02:
        problems.append("max z %.3f, expected %.2f" % (mx.z, spec["extra"]["maxz"]))
    # transforms
    for o in objs:
        want = ROTATED.get(o.name, (0.0, 0.0, 0.0))
        r = o.matrix_basis.to_3x3().normalized()
        target = Euler(tuple(math.radians(x) for x in want)).to_matrix()
        if any(abs(r[i][j] - target[i][j]) > 1e-3 for i in range(3) for j in range(3)):
            problems.append("rotation on %s %s" % (o.name, tuple(round(math.degrees(x), 1)
                                                                 for x in o.matrix_basis.to_euler())))
        if any(abs(s - 1.0) > 1e-4 for s in o.matrix_basis.to_scale()):
            problems.append("scale on %s" % o.name)
    # shading / colours / materials
    if len(bpy.data.images):
        problems.append("image datablocks present")
    allowed_mats = export.allowed_materials()
    for o in objs:
        if o.type != 'MESH':
            continue
        me = o.data
        # Flat shading: every corner normal must equal its polygon's normal. (The importer's own
        # use_smooth guess uses a 1e-7 threshold that misfires on tiny planar faces through float32
        # rounding, so a polygon flagged smooth only fails when its normals really differ.)
        cn = me.corner_normals
        not_flat = sum(1 for p in me.polygons if p.use_smooth and
                       min(cn[li].vector.dot(p.normal) for li in p.loop_indices) < 0.9999)
        if not_flat:
            problems.append("%d smooth-shaded faces on %s" % (not_flat, o.name))
        if len(me.uv_layers):
            problems.append("UV layers on %s" % o.name)
        if is_col(o):
            if len(me.color_attributes):
                problems.append("colour attribute on collision %s" % o.name)
            continue
        if len(me.materials) == 0:
            problems.append("no material on %s" % o.name)
        if len(me.materials) > MAX_SURFACES_PER_MESH:
            problems.append("%d materials on %s" % (len(me.materials), o.name))
        for m in me.materials:
            if m is None or m.name not in allowed_mats:
                problems.append("material %s on %s not allowed" % (m.name if m else None, o.name))
        nm = len(me.materials)
        if any(p.material_index >= nm for p in me.polygons):
            problems.append("bad material index on %s" % o.name)
        problems += colour_problems(o, allowed_bytes)
        bad = winding_problems(o)
        if bad:
            problems.append("%d inverted/inconsistent closed part(s) in %s" % (bad, o.name))
    for key in ("window", "ember", "glass"):
        for n in spec["extra"].get(key, []):
            if n in by and key not in [m.name for m in by[n].data.materials if m]:
                problems.append("%s does not use material %s" % (n, key))
    # budget
    tris = sum(tris_of(o) for o in vis)
    if tris > spec["budget"] * BUDGET_SLACK:
        problems.append("tris %d > %d x %.1f" % (tris, spec["budget"], BUDGET_SLACK))
    # collision
    for o in col_objs:
        box = spec["col"].get(o.name[:-len("-convcolonly")])
        if box:
            problems += check_collision(o, box)

    if problems:
        return "FAIL", "FAIL %s: %s" % (name, "; ".join(problems)), tris, surfaces
    names = sorted(o.name for o in objs)
    return "OK", "OK %-14s tris=%-5d surfaces=%-3d dims=(%.2f,%.2f,%.2f)  objects=[%s]" % (
        name, tris, surfaces, size.x, size.y, size.z, ", ".join(names)), tris, surfaces


def main():
    failures = 0
    total = 0
    total_surf = 0
    allowed_bytes = reimport_targets()
    godot_targets = {palette.target_godot_bytes(n) for n in palette.all_names()}
    for name, spec in ASSETS.items():
        status, msg, tris, surfaces = verify(name, spec, allowed_bytes, godot_targets)
        total += tris
        total_surf += surfaces
        print(msg)
        if status == "FAIL":
            failures += 1
    print("TOTAL tris=%d (budget %d) surfaces=%d" % (total, TOTAL_BUDGET, total_surf))
    if total > TOTAL_BUDGET:
        print("FAIL total triangle budget exceeded")
        failures += 1
    print("ALL OK" if failures == 0 else "%d FAILURES" % failures)
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
