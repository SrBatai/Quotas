extends SceneTree
func dump(n: Node, d := 0):
	var extra = ""
	if n is Node3D:
		extra = " pos=%s" % [n.position]
	if n is VehicleWheel3D:
		extra += " wheel_radius=%.2f use_as_steering=%s use_as_traction=%s" % [n.wheel_radius, n.use_as_steering, n.use_as_traction]
	print("  ".repeat(d), "- ", n.name, " <", n.get_class(), ">", extra)
	for c in n.get_children():
		dump(c, d + 1)
func _init():
	var s = load("res://models/sedan_test.glb").instantiate()
	dump(s)
	quit()
