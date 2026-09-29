"""Verify the kit buildings (ASSET_SPEC_V2 §8, §16.10 / §16.12; started in M3, cut-ready in M6a) against their
templates.

    cd winter-survival/blender && python3 verify_kits.py [template_id ...]       (exit code 0 = ALL OK)

For every kits/templates/<id>.json x style: the template is rebuilt IN MEMORY with lib/kit.py (the expected groups,
doors, windows, spawns and collision table) and compared with assets/models/buildings/<style>/<id>.glb:
  * files (.glb + .import + sources/<id>__<style>.blend + the verbatim copy data/buildings/templates/<id>.json), glTF
    contract of verify_assets (palette COLOR_0 RGBA + AO, <= 2 surfaces per mesh, materials, no UV / images, names);
  * every expected node present, top level; the v2 cutaway structure (verify_assets.cut_problems: _Stub outlines,
    cut_group / floor / floor_z props, Door_n / Window_n / Spawn_* props) with Floor<k> floor_z = 0.3 + 3 k;
  * collision: exactly the template's Col* set, each box within 0.02 m of the table, convex / closed; storeys >= 1
    have their slab boxes (ColFloor<k>_<n>) and every flight its ramp (ColStair<k>_<n>, 30-36 deg);
  * front: the exterior door on the S facade (y < 0), footprint centred on the origin, floor 0 at z = 0.30;
  * Roof holds no walls (its lowest point is above the top storey's eave minus the icicles);
  * M6a cut-ready (W0 contract, ARQ v2 §9.7): ShadowProxy (closed, 12-400 tris, root metadata floors / floor_h /
    ground_h / foundation / kind / enterable, AABB = the walls' footprint +-5 cm); every storey a closed volume (no
    horizontal ray from inside escapes: third_party/cutready.closed_problems), a slab under every floor level and the
    roof slab (verify_city.slab_problems), the corte urbano view (cutready.cut_view_problems: game-camera rays through
    the cut plane of every storey meet a slab / stub top or a back face = cap_color, never a lower storey);
  * Spawn_Sign_<n> (M6a): sign / width / cap / cut_group (an existing group) / floor props, on an outer face;
  * budgets: the template's `budget` (all visual meshes incl. the hidden stubs; v2.1 "casa del kit" 6-14 k per
    storey band) and <= 8 group surfaces per storey + 1 (panes and leaves are separate breakable nodes);
  * no visible back faces from game-camera directions (verify_assets.backface_problems) in the 8 cutaway states of
    every storey (the storeys above hidden, the camera-facing facades of the storey swapped for their stubs).
"""
import json
import math
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy  # noqa: E402,F401

import verify_assets as VA  # noqa: E402
from kits.build_buildings import templates  # noqa: E402
from lib import export  # noqa: E402
from lib import kit  # noqa: E402
from lib import lowpoly as lp  # noqa: E402
from lib import palette  # noqa: E402

GROUP_SURFACES_PER_STOREY = 8
PROXY_TRIS = (12, 400)
ROOT_META = ("floors", "floor_h", "ground_h", "foundation", "kind", "enterable")


def _cr():
    from third_party import cutready as CR
    from third_party import verify_city as VC
    return CR, VC


def storey_backface_problems(objs, floors):
    """Back faces in the cutaway states of every storey k (§9.3): Roof + Floor/Walls/Interior of storeys > k hidden,
    the camera-facing Walls<k>_* (+ their doors / windows) swapped for their stubs, the other stubs hidden."""
    meshes = [o for o in objs if o.type == 'MESH' and not VA.is_col(o) and o.name != "ShadowProxy"]
    total, bad = 0, {}
    for k in range(floors):
        for yi in range(8):
            d = VA._view_dir(48.0, 45 * yi)
            to_cam = -d
            hidden = {"Roof"}
            for o in meshes:
                m = re.match(r"^(Floor|Interior)(\d+)$", o.name)
                if m and int(m.group(2)) > k:
                    hidden.add(o.name)
                m = re.match(r"^Walls(\d+)_([NSEW])(_Stub)?$", o.name)
                if m:
                    fl, facing = int(m.group(1)), VA._FACADE_N[m.group(2)].dot(to_cam) > 0.15
                    stub = bool(m.group(3))
                    if fl > k or (fl == k and facing != stub) or (fl < k and stub):
                        hidden.add(o.name)
            for o in meshes:
                cg = o.get("cut_group")
                if o.name.startswith(("Door_", "Window_")) and cg in hidden:
                    hidden.add(o.name)
            t, b = VA._bf_hits([o for o in meshes if o.name not in hidden], [d], True, step_div=200)
            total += t
            for kk, v in b.items():
                bad["%s (storey %d)" % (kk, k)] = bad.get("%s (storey %d)" % (kk, k), 0) + v
    nb = sum(bad.values())
    if nb > VA.BF_MAX_HITS and nb > VA.BF_MAX_FRAC * total:
        return ["%d visible back-face hits of %d cutaway rays (%s)" % (nb, total, bad)]
    return []


def proxy_problems(by, tpl, vis):
    out = []
    p = by.get("ShadowProxy")
    if p is None:
        return ["no ShadowProxy"]
    t = VA.tris_of(p)
    if not PROXY_TRIS[0] <= t <= PROXY_TRIS[1]:
        out.append("ShadowProxy %d tris outside %s" % (t, PROXY_TRIS))
    for key in ROOT_META:
        if key not in p.keys():
            out.append("ShadowProxy extras lack %s" % key)
    if p.get("floors") != tpl.get("floors", 1):
        out.append("ShadowProxy floors %r != %r" % (p.get("floors"), tpl.get("floors", 1)))
    bad = VA.winding_problems(p)
    if bad:
        out.append("ShadowProxy has %d inverted parts" % bad)
    mn, mx = VA.world_bounds([p])
    W, D = tpl["footprint"]
    for v, want in ((mn.x, -W / 2 - kit.T2), (mx.x, W / 2 + kit.T2), (mn.y, -D / 2 - kit.T2), (mx.y, D / 2 + kit.T2)):
        if abs(v - want) > 0.05:
            out.append("ShadowProxy plan %.2f != wall face %.2f" % (v, want))
    if abs(mn.z) > 0.02:
        out.append("ShadowProxy base %.2f != 0" % mn.z)
    return out


def sign_problems(by, objs, groups):
    out = []
    for o in objs:
        if o.name.startswith("Spawn_Sign_"):
            for key in ("sign", "width", "cap", "cut_group", "floor"):
                if key not in o.keys():
                    out.append("%s lacks %s" % (o.name, key))
            if o.get("cut_group") not in groups:
                out.append("%s cut_group %r is not a group" % (o.name, o.get("cut_group")))
            if o.get("cap", 0) < 0.3:
                out.append("%s cap height %.2f < 0.30 m (doc 10 §7.4, readable at 24 m)" % (o.name, o.get("cap", 0)))
    return out


def cut_ready_problems(shell, tpl, expect):
    """The W0 / A1 cut-ready tests (third_party/cutready.py) with the sample grid inside the walls' footprint (inset
    0.3 m): towers have no eaves, but a pitched kit roof encloses the overhang above the gable wall too.
      closed: from points inside every storey (mid height) no horizontal ray escapes (windows / doors closed);
      slab:   a downward ray 0.3 m above every floor level (and the roof slab) meets an up face at that level
              (-8 / +30 cm) or the closed bottom of a volume (down face, -30 / +60 cm) for >= 90 % of the points;
      cut:    for every storey k the struct shader removes what is above y_cut = level + 0.4; game-camera rays
              (48 deg, 8 yaws) through that plane inside the footprint meet a front face no deeper than 0.6 m under
              the level or a back face (painted cap_color) -- never a lower storey or the ground (<= 5 %)."""
    from mathutils import Vector
    CR, _VC = _cr()
    W, D = tpl["footprint"]
    mn = Vector((-W / 2 + 0.3, -D / 2 + 0.3, 0.0))
    mx = Vector((W / 2 - 0.3, D / 2 - 0.3, expect["roof_z"]))
    bvh = CR.bvh_of(shell)
    reach = 60.0
    out = []
    levels = [0.0] + list(expect["levels"])
    for k in range(len(levels) - 1):
        zm = (levels[k] + levels[k + 1]) / 2
        pts = CR.interior_points(bvh, mn, mx, zm, reach, 5)
        esc = sum(1 for p in pts for d in CR.HDIRS16 if bvh.ray_cast(p, d, reach)[0] is None)
        if not pts:
            out.append("storey %d: no interior point" % k)
        elif esc:
            out.append("storey %d: %d of %d rays escape (not closed)" % (k, esc, 16 * len(pts)))
    flat = tpl.get("roof", {}).get("kind", "gable") == "flat"
    for k, z in enumerate(expect["levels"]):
        # M6b: above a flat roof's slab there is only sky (inside the parapet): enclosed, not covered (M6a's shop
        # passed on the single grid point under its vent box)
        top_flat = flat and k == len(expect["levels"]) - 1
        pts = CR.interior_points(bvh, mn, mx, z + 0.3, reach, 6, covered=not top_flat)
        ok = 0
        for p in pts:
            loc, nrm, _i, _d = bvh.ray_cast(p, Vector((0, 0, -1)), 2.0)
            if loc is not None and ((nrm.z > 0.5 and z - 0.08 <= loc.z <= z + 0.30) or
                                    (nrm.z < -0.5 and z - 0.30 <= loc.z <= z + 0.60)):
                ok += 1
        if not pts or ok < 0.9 * len(pts):
            out.append("level %d (z %.2f): slab found under %d of %d points" % (k + 1, z, ok, len(pts)))
    verts, polys, norms = [], [], []
    for o in shell:
        mw = o.matrix_world
        base = len(verts)
        verts += [mw @ v.co for v in o.data.vertices]
        m3 = mw.to_3x3()
        for p in o.data.polygons:
            polys.append(tuple(base + i for i in p.vertices))
            norms.append((m3 @ p.normal).normalized())
    from mathutils.bvhtree import BVHTree
    tree = BVHTree.FromPolygons(verts, polys, epsilon=0.0)
    for k, zs in enumerate(expect["levels"]):
        ycut = zs + CR.STUB
        pts = CR.interior_points(tree, mn, mx, ycut - 0.05, reach, 7)
        fails, total = 0, 0
        for yi in range(8):
            yaw, pch = math.radians(45 * yi), math.radians(48.0)
            d = -Vector((math.sin(yaw) * math.cos(pch), math.cos(yaw) * math.cos(pch), math.sin(pch)))
            for q in pts:
                loc, _n, idx, _dd = tree.ray_cast(Vector((q.x, q.y, ycut)) + d * 1e-3, d, 60.0)
                total += 1
                if idx is None or (norms[idx].dot(d) < 0 and loc.z < zs - 0.6):
                    fails += 1
        if not pts or (total and fails > 0.05 * total):
            out.append("cut at level %d (y_cut %.2f): %d of %d rays see below the slab" % (k + 1, ycut, fails, total))
    return out


def stair_problems(expect):
    out = []
    for name, (mn, mx) in expect["col"].items():
        if name.startswith("ColStair") and not name.startswith("ColStairRail"):
            run = max(mx[0] - mn[0], mx[1] - mn[1])
            ang = math.degrees(math.atan2(mx[2] - mn[2], run))
            if not 30.0 <= ang <= 36.0:
                out.append("%s slope %.1f deg outside 30-36" % (name, ang))
    return out


def verify_building(tid, tpl, style, allowed_bytes, godot_targets):
    lp.new_scene()
    expect = kit.build(tpl, style)
    glb = export.MODELS_DIR / "buildings" / style / ("%s.glb" % tid)
    blend = export.SOURCES_DIR / ("%s__%s.blend" % (tid, style))
    label = "buildings/%s/%s" % (style, tid)
    if not glb.exists() or not blend.exists():
        return False, "FAIL %s: missing %s" % (label, "glb" if not glb.exists() else "blend")
    problems = []
    if not os.path.exists(str(glb) + ".import"):
        problems.append("no .import next to the .glb")
    data_copy = os.path.join(os.path.dirname(HERE), "data", "buildings", "templates", "%s.json" % tid)
    src = os.path.join(HERE, "kits", "templates", "%s.json" % tid)
    if not os.path.exists(data_copy) or open(data_copy).read() != open(src).read():
        problems.append("data/buildings/templates/%s.json is not a verbatim copy of the template" % tid)
    floors = int(tpl.get("floors", 1))
    g, binary = VA.load_glb(glb)
    p2, surfaces = VA.gltf_problems(g, binary, godot_targets)
    problems += p2
    export.reimport(glb)
    objs = list(bpy.data.objects)
    by = {o.name: o for o in objs}
    want_nodes = expect["groups"] + expect["doors"] + expect["windows"] + expect["spawns"] + expect["extra"]
    for n in want_nodes:
        if n not in by:
            problems.append("missing %s" % n)
        elif by[n].parent is not None:
            problems.append("%s must be top level" % n)
    extra = [o.name for o in objs if not VA.is_col(o) and o.name not in set(want_nodes)]
    if extra:
        problems.append("unexpected nodes %s" % extra)
    problems += VA.cut_problems(by, objs)
    for k in range(floors):
        f = by.get("Floor%d" % k)
        if f is not None and abs(f.get("floor_z", -1) - (kit.FOUND + k * kit.STOREY)) > 1e-4:
            problems.append("Floor%d floor_z %r != %.2f" % (k, f.get("floor_z"), kit.FOUND + k * kit.STOREY))
    # collision
    col_objs = [o for o in objs if VA.is_col(o)]
    have = {o.name[:-len("-convcolonly")] for o in col_objs}
    want = set(expect["col"])
    if have != want:
        problems.append("collision set mismatch: missing %s extra %s" % (sorted(want - have), sorted(have - want)))
    for o in col_objs:
        box = expect["col"].get(o.name[:-len("-convcolonly")])
        if box:
            problems += VA.check_collision(o, box)
    for k in range(1, floors):
        if not any(n.startswith("ColFloor%d_" % k) for n in have):
            problems.append("storey %d has no slab collision" % k)
    problems += stair_problems(expect)
    # front / footprint / floor height
    doors = [by[n] for n in expect["doors"] if n in by and by[n].get("exterior")]
    if not doors or not any(d.matrix_world.translation.y < 0 for d in doors if d.get("cut_group", "").endswith("_S")):
        problems.append("no exterior door on the S facade (front = -Y)")
    vis = [o for o in objs if o.type == 'MESH' and not VA.is_col(o)]
    mn, mx = VA.world_bounds(vis)
    W, D = tpl["footprint"]
    c = (mn + mx) * 0.5
    if abs(c.x) > 0.6:
        problems.append("footprint not centred in x (%.2f)" % c.x)
    if "Roof" in by:
        # inside the walls' footprint (a porch roof in front of the ground floor belongs to Roof too)
        ro = by["Roof"]
        zs = [(ro.matrix_world @ v.co).z for v in ro.data.vertices
              if abs((ro.matrix_world @ v.co).x) < W / 2 - 0.2 and abs((ro.matrix_world @ v.co).y) < D / 2 - 0.2]
        eave = kit.FOUND + floors * kit.STOREY - kit.SLAB
        if zs and min(zs) < eave - 1.0:
            problems.append("Roof reaches down to %.2f inside the footprint (walls in the roof group?)" % min(zs))
    # M6a cut-ready
    problems += proxy_problems(by, tpl, vis)
    problems += sign_problems(by, objs, set(expect["groups"]))
    shell = [o for o in vis if o.name != "ShadowProxy" and not o.name.endswith("_Stub")]
    problems += ["cut-ready: " + p for p in cut_ready_problems(shell, tpl, expect)]
    # materials / colours / winding (as verify_assets)
    allowed_mats = export.allowed_materials()
    for o in vis:
        for m in o.data.materials:
            if m is None or m.name not in allowed_mats:
                problems.append("material %s on %s" % (m.name if m else None, o.name))
        problems += VA.colour_problems(o, allowed_bytes)
        bad = VA.winding_problems(o)
        if bad:
            problems.append("%d inverted closed part(s) in %s" % (bad, o.name))
        if len(o.data.uv_layers):
            problems.append("UV layers on %s" % o.name)
    for o in objs:
        if o.type == 'MESH' and any(abs(s - 1.0) > 1e-4 for s in o.matrix_basis.to_scale()):
            problems.append("scale on %s" % o.name)
        if o.type == 'MESH':
            r = o.matrix_basis.to_3x3().normalized()
            if any(abs(r[i][j] - (1.0 if i == j else 0.0)) > 1e-4 for i in range(3) for j in range(3)):
                problems.append("rotation on %s" % o.name)
    no_proxy = [o for o in objs if o.name != "ShadowProxy"]
    problems += VA.backface_problems(no_proxy, cutaway=True)
    problems += storey_backface_problems(no_proxy, floors)
    tris = sum(VA.tris_of(o) for o in vis if o.name != "ShadowProxy")
    visible_tris = sum(VA.tris_of(o) for o in vis if o.name != "ShadowProxy" and not o.name.endswith("_Stub"))
    budget = int(tpl.get("budget", 14000))
    if tris > budget:
        problems.append("tris %d > budget %d" % (tris, budget))
    group_surfaces = sum(len(o.data.materials) for o in vis if o.name in expect["groups"] and not o.name.endswith("_Stub"))
    if group_surfaces > GROUP_SURFACES_PER_STOREY * floors + 1:
        problems.append("%d group surfaces > %d" % (group_surfaces, GROUP_SURFACES_PER_STOREY * floors + 1))
    if problems:
        return False, "FAIL %s: %s" % (label, "; ".join(problems))
    size = mx - mn
    drawn = group_surfaces + len(expect["doors"]) + len(expect["windows"])
    return True, "OK %-34s tris=%-6d visible=%-6d floors=%d surfaces=%d (drawn: %d groups + %d leaves + %d panes = %d) " \
                 "%s dims=(%.2f,%.2f,%.2f) spawns=%d col=%d" % (
                     label, tris, visible_tris, floors, surfaces, group_surfaces, len(expect["doors"]),
                     len(expect["windows"]), drawn, VA.ao_summary(g, binary), size.x, size.y, size.z,
                     len(expect["spawns"]), len(col_objs))


def main(ids=None):
    allowed_bytes = VA.reimport_targets()
    godot_targets = {palette.target_godot_bytes(n) for n in palette.all_names()}
    failures = 0
    for tid, tpl in templates().items():
        if ids and tid not in ids:
            continue
        for style in tpl["style"]:
            ok, msg = verify_building(tid, tpl, style, allowed_bytes, godot_targets)
            print(msg, flush=True)
            failures += 0 if ok else 1
    print("ALL OK" if failures == 0 else "%d FAILURES" % failures)
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:] or None))
