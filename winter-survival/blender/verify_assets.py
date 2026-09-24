"""Verify every exported .glb against docs/ASSET_SPEC.md §6 (re-import round trip).

Run:  cd winter-survival/blender && python3 verify_assets.py      (exit code 0 = ALL OK)
Prints one line per asset (`OK name tris=.. dims=.. objects=[..]` or `FAIL name: reason`) and ends
with `ALL OK` or `N FAILURES`.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
from mathutils import Euler, Vector  # noqa: E402

from lib import export  # noqa: E402
from lib.palette import PALETTE  # noqa: E402

PIVOT_TOL = 0.03
DIM_TOL = 0.10
COL_TOL = 0.02
TOTAL_BUDGET = 12000
BUDGET_SLACK = 1.2

ZERO = (0.0, 0.0, 0.0)


def a(pri, budget, pivots, parents=None, dims=None, minz=0.0, extra=None, col=None, dims_of=None):
    return dict(pri=pri, budget=budget, pivots=pivots, parents=parents or {}, dims=dims or {}, minz=minz,
                extra=extra or {}, col=col or {}, dims_of=dims_of or {})


QUAD_PARENTS = {"Head": "Body", "Tail": "Body", "LegFL": "Body", "LegFR": "Body", "LegBL": "Body",
                "LegBR": "Body", "Muzzle": "Head"}

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
                dims={"z": 1.80}, extra={"forward": ["BreathAnchor"]}),
    "wolf": a(0, 600, {"Body": (0, 0, 0.55), "Head": (0, 0.45, 0.62), "Muzzle": (0, 0.93, 0.58),
                       "Tail": (0, -0.45, 0.62), "LegFL": (-0.13, 0.30, 0.42), "LegFR": (0.13, 0.30, 0.42),
                       "LegBL": (-0.13, -0.30, 0.42), "LegBR": (0.13, -0.30, 0.42)},
              parents=QUAD_PARENTS, dims={"y": 1.85, "x": 0.36}, dims_of={"Body": {"zmax": 0.75}},
              extra={"forward": ["Muzzle"]}),
    "deer": a(1, 800, {"Body": (0, 0, 0.90), "Head": (0, 0.60, 1.00), "Muzzle": (0, 1.05, 1.35),
                       "LegFL": (-0.14, 0.42, 0.70), "LegFR": (0.14, 0.42, 0.70),
                       "LegBL": (-0.14, -0.42, 0.70), "LegBR": (0.14, -0.42, 0.70), "Tail": None},
              parents=QUAD_PARENTS, dims={"z": 1.65}, extra={"forward": ["Muzzle"]}),
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
    "stone_axe": a(0, 100, {"Handle": ZERO, "Blade": ZERO}, dims={"z": 0.55}, minz=-0.05),
    "torch": a(0, 80, {"Handle": ZERO, "Head": ZERO, "FlameAnchor": (0, 0, 0.54)}, dims={"z": 0.52}),
    "cabin": a(0, 2500, {"Floor": ZERO, "WallFront": ZERO, "WindowsFront": ZERO, "WallBack": ZERO,
                         "WallLeft": ZERO, "WindowsLeft": ZERO, "WallRight": ZERO, "Roof": ZERO, "Chimney": ZERO,
                         "Porch": ZERO, "DoorAnchor": (-0.9, 3.2, 0.30), "LanternSocket": (-1.6, 4.3, 2.35)},
               parents={"WindowsFront": "WallFront", "WindowsLeft": "WallLeft"},
               dims={"x": 7.1, "y": 8.2, "z": 5.3}, col=CABIN_COL,
               extra={"forward": ["DoorAnchor"], "window": ["WindowsFront", "WindowsLeft"]}),
    "wood_stove": a(0, 250, {"Body": ZERO, "Door": ZERO, "Pipe": ZERO, "StoveAnchor": (0, 0.35, 0.45),
                             "PipeTop": (0, -0.15, 2.70)},
                    dims={"x": 0.66, "y": 0.66, "z": 2.70}, extra={"forward": ["StoveAnchor"], "ember": ["Door"]}),
    # depth checked against the 0.56 cornice (the spec's own cornice is deeper than the 0.50 body)
    "cabinet": a(0, 120, {"Cabinet": ZERO}, dims={"x": 0.90, "y": 0.56, "z": 1.80}),
    "bed": a(1, 150, {"Bed": ZERO}, dims={"x": 1.0, "y": 2.0}),
    "desk": a(1, 150, {"Desk": ZERO}, dims={"x": 1.40, "y": 0.60}),
    "chair": a(1, 120, {"Chair": ZERO}, dims={"x": 0.45, "y": 0.45, "z": 0.90}),
    "shelf": a(1, 250, {"Shelf": ZERO, "Jars": ZERO}, parents={"Jars": "Shelf"}, dims={"x": 0.90, "y": 0.25},
               minz=None),
    "clock": a(1, 120, {"Clock": ZERO, "HourHand": (0, 0.07, 0), "MinuteHand": (0, 0.075, 0)},
               dims={"x": 0.36, "z": 0.36}, minz=None),
    "a_frame_cabin": a(1, 600, {"Body": ZERO, "Front": ZERO, "WindowsFront": ZERO, "Deck": ZERO},
                       parents={"WindowsFront": "Front"}, dims={"x": 6.0, "y": 8.5, "z": 6.0},
                       col={"ColBody": ((-3.0, -3.5, 0.0), (3.0, 3.5, 6.0)),
                            "ColDeck": ((-2.0, 3.5, 0.0), (2.0, 5.0, 0.25))},
                       extra={"window": ["WindowsFront"]}),
    "pickup_truck": a(1, 900, {"Body": ZERO, "Wheels": ZERO, "Snow": ZERO, "BedAnchor": (0, -1.35, 1.0)},
                      dims={"x": 2.0, "y": 5.0, "z": 1.95},
                      col={"ColChassis": ((-1.0, -2.5, 0.3), (1.0, 2.5, 1.3)),
                           "ColCab": ((-0.95, -0.2, 1.3), (0.95, 1.0, 2.0))}),
    "signpost": a(1, 150, {"Post": ZERO, "BoardTop": (0, 0, 1.84), "BoardBottom": (0, 0, 1.44),
                           "TextTop": (0.28, 0.125, 1.84), "TextBottom": (0.28, 0.125, 1.44)},
                  parents={"TextTop": "BoardTop", "TextBottom": "BoardBottom"}, dims={"z": 2.2},
                  extra={"forward": ["TextTop"], "tip": "BoardTop"}),
    "fence": a(1, 120, {"Fence": ZERO}, dims={"x": 2.0, "z": 1.1}),
    "lantern": a(1, 120, {"Lantern": ZERO, "LightAnchor": (0, 0, -0.23)}, dims={"z": 0.40}, minz=-0.40,
                 extra={"maxz": 0.0}),
    "tent": a(2, 250, {"Tent": ZERO}, dims={"x": 2.4, "y": 2.6, "z": 1.7},
              col={"ColBack": ((-1.2, -1.3, 0.0), (1.2, -1.2, 1.7))}),
    "storage_box": a(2, 150, {"Box": ZERO}, dims={"x": 0.8, "y": 0.6, "z": 0.6}),
}

ROTATED = {"ToolSocket": (-90.0, 0.0, 0.0), "TextTop": (0.0, 0.0, 180.0), "TextBottom": (0.0, 0.0, 180.0)}


def is_col(o):
    return o.name.startswith("Col") and o.name.endswith("-convcolonly")


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
    # components by shared edges
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


def verify(name, spec):
    """Returns (status, message, tris)."""
    glb = export.MODELS_DIR / ("%s.glb" % name)
    blend = export.SOURCES_DIR / ("%s.blend" % name)
    if not glb.exists() or not blend.exists():
        if spec["pri"] >= 2:
            return "SKIP", "SKIP %s (P2, not built)" % name, 0
        return "FAIL", "FAIL %s: missing %s" % (name, "glb" if not glb.exists() else "blend"), 0
    with open(glb, "rb") as f:
        head = f.read(4)
    if glb.stat().st_size <= 1024 or head != b"glTF":
        return "FAIL", "FAIL %s: glb too small or bad header" % name, 0

    export.reimport(glb)
    objs = list(bpy.data.objects)
    by = {o.name: o for o in objs}
    problems = []

    # 3. names
    for req in spec["pivots"]:
        if req not in by:
            problems.append("missing %s" % req)
    for o in objs:
        if "." in o.name:
            problems.append("dotted name %s" % o.name)
        if "-" in o.name and not is_col(o):
            problems.append("bad suffix %s" % o.name)
        if o.name.startswith("Col") and not o.name.endswith("-convcolonly"):
            problems.append("Col object without -convcolonly: %s" % o.name)
        if o.type not in ('MESH', 'EMPTY'):
            problems.append("stray %s %s" % (o.type, o.name))
    col_objs = [o for o in objs if is_col(o)]
    want_col = set(n + "-convcolonly" for n in spec["col"])
    have_col = set(o.name for o in col_objs)
    if want_col != have_col:
        problems.append("collision set mismatch: missing %s extra %s" % (sorted(want_col - have_col),
                                                                       sorted(have_col - want_col)))
    # 4. hierarchy
    for child, par in spec["parents"].items():
        if child in by and (by[child].parent is None or by[child].parent.name != par):
            problems.append("%s parent is %s, expected %s" % (
                child, by[child].parent.name if by[child].parent else None, par))
    # 5. pivots
    for n, piv in spec["pivots"].items():
        if piv is None or n not in by:
            continue
        w = by[n].matrix_world.translation
        if (w - Vector(piv)).length > PIVOT_TOL:
            problems.append("pivot %s at %s, expected %s" % (n, tuple(round(c, 3) for c in w), piv))
    # 6. forward axis
    for n in spec["extra"].get("forward", []):
        if n in by and by[n].matrix_world.translation.y <= 0:
            problems.append("%s not in front (+Y)" % n)
    tip = spec["extra"].get("tip")
    if tip and tip in by:
        mx = max((by[tip].matrix_world @ v.co).x for v in by[tip].data.vertices)
        if mx <= 0.8:
            problems.append("%s tip max x %.2f <= 0.8" % (tip, mx))
    # 7. dimensions
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
    # 8. transforms
    for o in objs:
        want = ROTATED.get(o.name, (0.0, 0.0, 0.0))
        r = o.matrix_basis.to_3x3().normalized()
        target = Euler(tuple(math.radians(x) for x in want)).to_matrix()
        if any(abs(r[i][j] - target[i][j]) > 1e-3 for i in range(3) for j in range(3)):
            problems.append("rotation on %s %s" % (o.name, tuple(round(math.degrees(x), 1)
                                                                 for x in o.matrix_basis.to_euler())))
        if any(abs(s - 1.0) > 1e-4 for s in o.matrix_basis.to_scale()):
            problems.append("scale on %s" % o.name)
    # 9. shading / 10. materials
    if len(bpy.data.images):
        problems.append("image datablocks present")
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
        if len(me.uv_layers) or len(me.color_attributes):
            problems.append("UV/colour attributes on %s" % o.name)
        if is_col(o):
            continue
        if len(me.materials) == 0:
            problems.append("no material on %s" % o.name)
        for m in me.materials:
            if m is None or m.name not in PALETTE:
                problems.append("material %s on %s not in palette" % (m.name if m else None, o.name))
        nm = len(me.materials)
        if any(p.material_index >= nm for p in me.polygons):
            problems.append("bad material index on %s" % o.name)
        bad = winding_problems(o)
        if bad:
            problems.append("%d inverted/inconsistent closed part(s) in %s" % (bad, o.name))
    for n in spec["extra"].get("window", []):
        if n in by and "window" not in [m.name for m in by[n].data.materials if m]:
            problems.append("%s does not use material window" % n)
    for n in spec["extra"].get("ember", []):
        if n in by and "ember" not in [m.name for m in by[n].data.materials if m]:
            problems.append("%s does not use material ember" % n)
    # 11. budget
    tris = sum(tris_of(o) for o in vis)
    if tris > spec["budget"] * BUDGET_SLACK:
        problems.append("tris %d > %d x %.1f" % (tris, spec["budget"], BUDGET_SLACK))
    # 12. collision
    for o in col_objs:
        box = spec["col"].get(o.name[:-len("-convcolonly")])
        if box:
            problems += check_collision(o, box)

    if problems:
        return "FAIL", "FAIL %s: %s" % (name, "; ".join(problems)), tris
    names = sorted(o.name for o in objs)
    return "OK", "OK %-14s tris=%-5d dims=(%.2f,%.2f,%.2f)  objects=[%s]" % (
        name, tris, size.x, size.y, size.z, ", ".join(names)), tris


def main():
    failures = 0
    total = 0
    for name, spec in ASSETS.items():
        status, msg, tris = verify(name, spec)
        total += tris
        print(msg)
        if status == "FAIL":
            failures += 1
    print("TOTAL tris=%d (budget %d)" % (total, TOTAL_BUDGET))
    if total > TOTAL_BUDGET:
        print("FAIL total triangle budget exceeded")
        failures += 1
    print("ALL OK" if failures == 0 else "%d FAILURES" % failures)
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
