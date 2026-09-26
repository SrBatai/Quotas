extends StaticBody3D
## World border (PLAN C6, M3): four invisible walls at ±WorldConst.WALL. The border ring before them is dense
## forest + mountains (macro map) and thickening fog (World → DayNight.fog_density_scale).


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	var b := WorldConst.WALL
	var walls := [
		[Vector3(b, 150, 0), Vector3(2, 400, b * 2 + 4)],
		[Vector3(-b, 150, 0), Vector3(2, 400, b * 2 + 4)],
		[Vector3(0, 150, b), Vector3(b * 2 + 4, 400, 2)],
		[Vector3(0, 150, -b), Vector3(b * 2 + 4, 400, 2)],
	]
	for w in walls:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = w[1]
		cs.shape = box
		cs.position = w[0]
		add_child(cs)
