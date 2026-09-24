extends StaticBody3D
## Generic interior decor: bed, desk, chair, shelf, clock. Collision from a small table.

@export var model: String = "bed"

const SHAPES := {
	"bed": [Vector3(1.0, 0.5, 2.0), Vector3(0, 0.25, 0)],
	"desk": [Vector3(1.4, 0.75, 0.6), Vector3(0, 0.375, 0)],
	"chair": [Vector3(0.45, 0.9, 0.45), Vector3(0, 0.45, 0)],
}


func _ready() -> void:
	collision_layer = 1 | 64
	collision_mask = 0
	var m := Assets.spawn_model(model)
	$Visual.add_child(m)
	if SHAPES.has(model):
		var box := BoxShape3D.new()
		box.size = SHAPES[model][0]
		var cs := CollisionShape3D.new()
		cs.shape = box
		cs.position = SHAPES[model][1]
		add_child(cs)
