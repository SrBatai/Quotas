extends StaticBody3D
## World border (PLAN C6, M3; W1 C25): four invisible walls, per axis at WorldConst.WALL_MIN / WALL_MAX
## (−1450 … +4420 m). The border ring before each is mountains (macro map) and thickening fog
## (World.border_fog_scale → DayNight.fog_density_scale, by the distance to the nearest wall).


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	var lo := WorldConst.WALL_MIN
	var hi := WorldConst.WALL_MAX
	var mid := (lo + hi) * 0.5
	var span := hi - lo + 4.0
	var walls := [
		[Vector3(hi, 150, mid), Vector3(2, 400, span)],
		[Vector3(lo, 150, mid), Vector3(2, 400, span)],
		[Vector3(mid, 150, hi), Vector3(span, 400, 2)],
		[Vector3(mid, 150, lo), Vector3(span, 400, 2)],
	]
	for w in walls:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = w[1]
		cs.shape = box
		cs.position = w[0]
		add_child(cs)
