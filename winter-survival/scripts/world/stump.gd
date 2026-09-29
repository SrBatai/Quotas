extends StaticBody3D
## Leftover stump after felling a tree.


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	$Visual.add_child(Assets.spawn_model("stump"))
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.3
	cyl.height = 0.5
	var cs := CollisionShape3D.new()
	cs.shape = cyl
	cs.position = Vector3(0, 0.25, 0)
	add_child(cs)
