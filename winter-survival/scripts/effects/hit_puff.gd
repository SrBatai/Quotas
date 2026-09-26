class_name HitPuff
extends CPUParticles3D
## One-shot burst of wood chips.


func _ready() -> void:
	amount = 12
	lifetime = 0.6
	one_shot = true
	explosiveness = 1.0
	direction = Vector3.UP
	spread = 70.0
	initial_velocity_min = 1.5
	initial_velocity_max = 3.0
	gravity = Vector3(0, -9.0, 0)
	scale_amount_min = 0.5
	scale_amount_max = 0.9
	var g := Gradient.new()
	g.set_color(0, Color("#C7A16B"))
	g.set_color(1, Color("#C7A16B", 0.0))
	color_ramp = g
	mesh = FireEffect.make_quad(0.12, FireEffect.make_particle_material(false))
	emitting = true
	finished.connect(queue_free)


static func spawn(parent: Node, pos: Vector3) -> void:
	var p := HitPuff.new()
	parent.add_child(p)
	p.global_position = pos
