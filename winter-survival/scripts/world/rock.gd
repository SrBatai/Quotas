extends StaticBody3D
## Decorative boulder with a sphere collider sized per variant.

@export var variant: String = "rock_a"


func _ready() -> void:
	collision_layer = 1 | 64
	collision_mask = 0
	var model := Assets.spawn_model(variant)
	$Visual.add_child(model)
	var sh := SphereShape3D.new()
	var y := 0.4
	match variant:
		"rock_b":
			sh.radius = 0.9
			y = 0.6
		"rock_c":
			sh.radius = 0.3
			y = 0.2
		_:
			sh.radius = 0.55
	var cs := CollisionShape3D.new()
	cs.shape = sh
	cs.position = Vector3(0, y, 0)
	add_child(cs)
