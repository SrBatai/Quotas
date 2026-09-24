class_name SmokeEffect
extends CPUParticles3D
## Chimney smoke column.


func _ready() -> void:
	amount = 30
	lifetime = 4.0
	direction = Vector3.UP
	spread = 8.0
	initial_velocity_min = 0.8
	initial_velocity_max = 1.2
	gravity = Vector3(0.6, 0.15, 0.2)
	emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	emission_sphere_radius = 0.15
	scale_amount_min = 0.6
	scale_amount_max = 0.9
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.5))
	sc.add_point(Vector2(1, 2.2))
	scale_amount_curve = sc
	var g := Gradient.new()
	g.set_color(0, Color("#C8CFD8", 0.45))
	g.set_color(1, Color("#C8CFD8", 0.0))
	color_ramp = g
	mesh = FireEffect.make_quad(0.7, FireEffect.make_particle_material(false))
	emitting = false


func set_active(value: bool) -> void:
	emitting = value
