"""Verify the kit buildings (ASSET_SPEC_V2 §8, §16.10 / §16.12; started in M3) against their templates.

    cd winter-survival/blender && python3 verify_kits.py        (exit code 0 = ALL OK)

For every kits/templates/<id>.json x style: the template is rebuilt IN MEMORY with lib/kit.py (the expected groups,
doors, windows, spawns and collision table) and compared with assets/models/buildings/<style>/<id>.glb:
  * files (.glb + sources/<id>__<style>.blend), glTF contract of verify_assets (palette COLOR_0 RGBA + AO, <= 2
    surfaces per mesh, materials, no UV / images, names);
  * every expected node present, top level; the v2 cutaway structure (verify_assets.cut_problems: _Stub outlines,
    cut_group / floor / floor_z props, Door_n / Window_n / Spawn_* props);
  * collision: exactly the template's Col* set, each box within 0.02 m of the table, convex / closed;
  * front: the exterior door on the S facade (y < 0), footprint centred on the origin, floor 0 at z = 0.30;
  * Roof holds no walls (its lowest point is above the eave minus the icicles);
  * budgets (doc 05 §4.5 "casa del kit" 6-14 k) and VISIBLE surfaces (everything but the hidden _Stub) <= 20;
  * no visible back faces from game-camera directions (verify_assets.backface_problems).
"""
import os
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

BUDGET = 14000
MAX_VISIBLE_SURFACES = 20


def verify_building(tid, tpl, style, allowed_bytes, godot_targets):
    lp.new_scene()
    expect = kit.build(tpl, style)
    glb = export.MODELS_DIR / "buildings" / style / ("%s.glb" % tid)
    blend = export.SOURCES_DIR / ("%s__%s.blend" % (tid, style))
    label = "buildings/%s/%s" % (style, tid)
    if not glb.exists() or not blend.exists():
        return False, "FAIL %s: missing %s" % (label, "glb" if not glb.exists() else "blend")
    g, binary = VA.load_glb(glb)
    problems, surfaces = VA.gltf_problems(g, binary, godot_targets)
    export.reimport(glb)
    objs = list(bpy.data.objects)
    by = {o.name: o for o in objs}
    for n in expect["groups"] + expect["doors"] + expect["windows"] + expect["spawns"]:
        if n not in by:
            problems.append("missing %s" % n)
        elif by[n].parent is not None:
            problems.append("%s must be top level" % n)
    extra = [o.name for o in objs if not VA.is_col(o) and o.name not in
             set(expect["groups"] + expect["doors"] + expect["windows"] + expect["spawns"])]
    if extra:
        problems.append("unexpected nodes %s" % extra)
    problems += VA.cut_problems(by, objs)
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
    # front / footprint / floor height
    doors = [by[n] for n in expect["doors"] if n in by and by[n].get("exterior")]
    if not doors or any(d.matrix_world.translation.y >= 0 for d in doors if d.get("cut_group", "").endswith("_S")):
        problems.append("no exterior door on the S facade (front = -Y)")
    vis = [o for o in objs if o.type == 'MESH' and not VA.is_col(o)]
    mn, mx = VA.world_bounds(vis)
    W, D = tpl["footprint"]
    c = (mn + mx) * 0.5
    if abs(c.x) > 0.6:
        problems.append("footprint not centred in x (%.2f)" % c.x)
    if "Floor0" in by and abs(by["Floor0"].get("floor_z", -1) - kit.FOUND) > 1e-4:
        problems.append("Floor0 floor_z %r != %.2f" % (by["Floor0"].get("floor_z"), kit.FOUND))
    if "Roof" in by:
        rmn, _rmx = VA.world_bounds([by["Roof"]])
        eave = kit.FOUND + tpl.get("floors", 1) * kit.STOREY - kit.SLAB
        if rmn.z < eave - 1.0:
            problems.append("Roof reaches down to %.2f (walls in the roof group?)" % rmn.z)
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
    problems += VA.backface_problems(objs, cutaway=True)
    tris = sum(VA.tris_of(o) for o in vis)
    if tris > BUDGET:
        problems.append("tris %d > %d" % (tris, BUDGET))
    visible = sum(len(o.data.materials) for o in vis if not o.name.endswith("_Stub"))
    if visible > MAX_VISIBLE_SURFACES:
        problems.append("%d visible surfaces > %d" % (visible, MAX_VISIBLE_SURFACES))
    if problems:
        return False, "FAIL %s: %s" % (label, "; ".join(problems))
    size = mx - mn
    return True, "OK %-32s tris=%-6d surfaces=%d (visible %d) %s dims=(%.2f,%.2f,%.2f) groups=%d doors=%d " \
                 "windows=%d spawns=%d col=%d" % (label, tris, surfaces, visible, VA.ao_summary(g, binary), size.x,
                                                 size.y, size.z, len(expect["groups"]), len(expect["doors"]),
                                                 len(expect["windows"]), len(expect["spawns"]), len(col_objs))


def main():
    allowed_bytes = VA.reimport_targets()
    godot_targets = {palette.target_godot_bytes(n) for n in palette.all_names()}
    failures = 0
    for tid, tpl in templates().items():
        for style in tpl["style"]:
            ok, msg = verify_building(tid, tpl, style, allowed_bytes, godot_targets)
            print(msg)
            failures += 0 if ok else 1
    print("ALL OK" if failures == 0 else "%d FAILURES" % failures)
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
