"""Tiny vehicle glb to test Godot's -vehicle / -wheel / -colonly import hints. Faces Blender -Y (= Godot +Z = VehicleBody3D forward)."""
import os, sys
sys.path.insert(0, "/home/user/Quotas/winter-survival/blender")
import bpy
from lib import lowpoly as lp
lp.new_scene()
import addon_utils; addon_utils.enable("io_scene_gltf2", default_set=True)
mb = lp.MeshBuilder(); mb.box((-0.9, -2.2, 0.45), (0.9, 2.2, 1.3), "truck_paint")
body = lp.to_object(mb, "Sedan-vehicle", (0, 0, 0))
for name, x, y in (("WheelFL", -0.85, -1.4), ("WheelFR", 0.85, -1.4), ("WheelRL", -0.85, 1.4), ("WheelRR", 0.85, 1.4)):
    w = lp.MeshBuilder(); w.cylinder((x - 0.12, y, 0.38), (x + 0.12, y, 0.38), 0.38, 0.38, 10, "iron")
    lp.to_object(w, name + "-wheel", (x, y, 0.38), parent=body)
c = lp.MeshBuilder(); c.box((-0.9, -2.2, 0.45), (0.9, 2.2, 1.3), None)
col = lp._collision(c, "ColBody")  # -convcolonly
col.parent = body
lp.add_empty("SeatDriver", (-0.4, -0.2, 0.9), parent=body)
lp.add_empty("HeadlightL", (-0.6, -2.21, 0.9), parent=body)
bpy.ops.export_scene.gltf(filepath=os.path.join(os.path.dirname(os.path.abspath(__file__)), "out", "sedan_test.glb"),
                          export_format='GLB', export_yup=True, export_animations=False, export_skins=False)
print("vehicle test exported")
