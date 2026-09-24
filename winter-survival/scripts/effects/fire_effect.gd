class_name FireEffect
extends Node3D
## Flames + smoke (CPUParticles3D) + flickering OmniLight. Works in Compatibility.

@export var scale_factor: float = 1.0
@export var light_range: float = 9.0
@export var light_energy: float = 2.0

var flames: CPUParticles3D
var smoke: CPUParticles3D
var light: LightFlicker
var _active: bool = true


static func make_particle_material(additive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.disable_receive_shadows = true
	m.no_depth_test = false
	return m


static func make_quad(size: float, material: Material) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = material
	return q


func _ready() -> void:
	flames = CPUParticles3D.new()
	flames.name = "Flames"
	flames.amount = 40
	flames.lifetime = 0.7
	flames.direction = Vector3.UP
	flames.spread = 12.0
	flames.initial_velocity_min = 1.0 * scale_factor
	flames.initial_velocity_max = 1.4 * scale_factor
	flames.gravity = Vector3.ZERO
	flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	flames.emission_sphere_radius = 0.16 * scale_factor
	flames.scale_amount_min = 0.9 * scale_factor
	flames.scale_amount_max = 1.2 * scale_factor
	var sc := Curve.new()
	sc.add_point(Vector2(0, 1.0))
	sc.add_point(Vector2(0.6, 0.55))
	sc.add_point(Vector2(1, 0.0))
	flames.scale_amount_curve = sc
	var g := Gradient.new()
	g.set_color(0, Color("#FFD166"))
	g.set_color(1, Color("#E63B12", 0.0))
	g.add_point(0.45, Color("#FF8C2A"))
	flames.color_ramp = g
	flames.mesh = make_quad(0.35, make_particle_material(true))
	add_child(flames)

	smoke = CPUParticles3D.new()
	smoke.name = "Smoke"
	smoke.amount = 20
	smoke.lifetime = 2.5
	smoke.direction = Vector3.UP
	smoke.spread = 10.0
	smoke.initial_velocity_min = 0.6 * scale_factor
	smoke.initial_velocity_max = 0.9 * scale_factor
	smoke.gravity = Vector3(0.2, 0.25, 0.1)
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = 0.12 * scale_factor
	smoke.position = Vector3(0, 0.5 * scale_factor, 0)
	smoke.scale_amount_min = 0.5 * scale_factor
	smoke.scale_amount_max = 0.8 * scale_factor
	var ssc := Curve.new()
	ssc.add_point(Vector2(0, 0.5))
	ssc.add_point(Vector2(1, 1.6))
	smoke.scale_amount_curve = ssc
	var sg := Gradient.new()
	sg.set_color(0, Color("#9AA3AD", 0.35))
	sg.set_color(1, Color("#9AA3AD", 0.0))
	smoke.color_ramp = sg
	smoke.mesh = make_quad(0.6, make_particle_material(false))
	add_child(smoke)

	light = LightFlicker.new()
	light.name = "Light"
	light.light_color = Color("#FFB454")
	light.base_energy = light_energy
	light.omni_range = light_range
	light.omni_attenuation = 1.4
	light.position = Vector3(0, 0.5 * scale_factor, 0)
	add_child(light)
	set_active(_active)


func set_active(value: bool) -> void:
	_active = value
	if flames == null:
		return
	flames.emitting = value
	smoke.emitting = value
	light.visible = value
