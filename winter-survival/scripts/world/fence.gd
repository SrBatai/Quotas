extends StaticBody3D
## One 2 m fence segment.


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	$Visual.add_child(Assets.spawn_model("fence"))
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 1.0, 0.15)
	var cs := CollisionShape3D.new()
	cs.shape = box
	cs.position = Vector3(0, 0.5, 0)
	add_child(cs)
