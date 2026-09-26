class_name SmokeEffect
extends GPUParticles3D
## Chimney smoke column (GPUParticles3D, PLAN C4).


func _ready() -> void:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.15
	pm.direction = Vector3.UP
	pm.spread = 8.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 1.2
	pm.gravity = Vector3(0.6, 0.15, 0.2)
	pm.scale_min = 0.6
	pm.scale_max = 0.9
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.5))
	sc.add_point(Vector2(1, 2.2))
	pm.scale_curve = FireEffect.curve_tex(sc)
	var g := Gradient.new()
	g.set_color(0, Color("#C8CFD8", 0.45))
	g.set_color(1, Color("#C8CFD8", 0.0))
	pm.color_ramp = FireEffect.ramp(g)
	process_material = pm
	amount = 30
	lifetime = 4.0
	draw_pass_1 = FireEffect.make_quad(0.7, FireEffect.make_particle_material(false))
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visibility_aabb = AABB(Vector3(-4, -1, -4), Vector3(12, 12, 12))
	emitting = false


func set_active(value: bool) -> void:
	emitting = value
