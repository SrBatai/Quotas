extends StaticBody3D
## Four invisible walls at ±BOUNDS.


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	var b := Balance.BOUNDS
	var walls := [
		[Vector3(b, 20, 0), Vector3(1, 60, b * 2 + 4)],
		[Vector3(-b, 20, 0), Vector3(1, 60, b * 2 + 4)],
		[Vector3(0, 20, b), Vector3(b * 2 + 4, 60, 1)],
		[Vector3(0, 20, -b), Vector3(b * 2 + 4, 60, 1)],
	]
	for w in walls:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = w[1]
		cs.shape = box
		cs.position = w[0]
		add_child(cs)
