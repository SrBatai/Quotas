"""Does bpy.ops.object.parent_set(type='ARMATURE_AUTO') (bone heat) work in bpy-module/background mode?
Loads out/survivor.blend, strips the rigid vertex groups from a copy of Body and re-skins it automatically,
then compares the dominant bone per vertex with the rigid (ground-truth) assignment."""
import os, sys, time
import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
bpy.ops.wm.open_mainfile(filepath=os.path.join(HERE, "out", "survivor.blend"))
print("background:", bpy.app.background, "version:", bpy.app.version_string)
arm = bpy.data.objects["Armature"]
body = bpy.data.objects["Body"]
rigid = {}
for v in body.data.vertices:
    g = max(v.groups, key=lambda g: g.weight)
    rigid[v.index] = body.vertex_groups[g.group].name

auto = body.copy(); auto.data = body.data.copy(); auto.name = "BodyAuto"
bpy.context.scene.collection.objects.link(auto)
auto.vertex_groups.clear()
auto.modifiers.clear()
auto.parent = None
for mode in ("raw", "merged"):
    if mode == "merged":
        # second attempt: weld coincident verts (parts touching) - still disjoint islands
        import bmesh
        bm = bmesh.new(); bm.from_mesh(auto.data)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0005)
        bm.to_mesh(auto.data); bm.free()
        auto.vertex_groups.clear(); auto.modifiers.clear(); auto.parent = None
    bpy.ops.object.select_all(action='DESELECT')
    auto.select_set(True); arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    t0 = time.time()
    res = bpy.ops.object.parent_set(type='ARMATURE_AUTO')
    dt = time.time() - t0
    n = len(auto.data.vertices)
    unweighted = sum(1 for v in auto.data.vertices if not any(g.weight > 1e-4 for g in v.groups))
    multi = sum(1 for v in auto.data.vertices if sum(1 for g in v.groups if g.weight > 0.05) > 1)
    match = 0
    if mode == "raw":
        for v in auto.data.vertices:
            if v.groups:
                g = max(v.groups, key=lambda g: g.weight)
                if auto.vertex_groups[g.group].name == rigid[v.index]:
                    match += 1
    print("ARMATURE_AUTO[%s]: result=%s time=%.2fs verts=%d groups=%d unweighted=%d (%.0f%%) multi-influence=%d dominant==rigid: %s"
          % (mode, res, dt, n, len(auto.vertex_groups), unweighted, 100.0 * unweighted / n, multi,
             ("%.0f%%" % (100.0 * match / n)) if mode == "raw" else "n/a"))
