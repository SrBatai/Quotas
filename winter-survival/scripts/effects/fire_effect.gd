class_name FireEffect
extends Node3D
## Flames + smoke (GPUParticles3D, PLAN C4) + flickering OmniLight. Works in Forward+ and Compatibility.

@export var scale_factor: float = 1.0
@export var light_range: float = 9.0
@export var light_energy: float = 1.8  # G1: Filmic at exposure 0.6 burns anything brighter (doc 06 §2 d)
@export var shadow_priority: int = -1

var flames: GPUParticles3D
var smoke: GPUParticles3D
var light: LightFlicker
var _active: bool = true


static var _soft_tex: ImageTexture


## 32x32 radial soft dot (alpha) so untextured quads read as flakes / glows.
static func soft_dot_texture() -> ImageTexture:
	if _soft_tex != null:
		return _soft_tex
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(16, 16)) / 16.0
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_soft_tex = ImageTexture.create_from_image(img)
	return _soft_tex


static func make_particle_material(additive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = soft_dot_texture()
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


## Gradient -> texture usable as ParticleProcessMaterial.color_ramp.
static func ramp(g: Gradient) -> GradientTexture1D:
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 64
	return t


## Curve -> texture usable as ParticleProcessMaterial.scale_curve.
static func curve_tex(c: Curve) -> CurveTexture:
	var t := CurveTexture.new()
	t.curve = c
	t.width = 64
	return t


## Continuous GPU emitter with the usual spherical emission (flames, smoke, embers).
static func make_emitter(amount: int, lifetime: float, radius: float, direction: Vector3, spread: float,
		vel_min: float, vel_max: float, gravity: Vector3, scale_min: float, scale_max: float,
		scale_curve: Curve, color: Gradient, quad_size: float, additive: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = maxf(radius, 0.001)
	pm.direction = direction
	pm.spread = spread
	pm.initial_velocity_min = vel_min
	pm.initial_velocity_max = vel_max
	pm.gravity = gravity
	pm.scale_min = scale_min
	pm.scale_max = scale_max
	if scale_curve != null:
		pm.scale_curve = curve_tex(scale_curve)
	if color != null:
		pm.color_ramp = ramp(color)
	p.process_material = pm
	p.amount = amount
	p.lifetime = lifetime
	p.draw_pass_1 = make_quad(quad_size, make_particle_material(additive))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 10, 8))
	return p


func _ready() -> void:
	var sc := Curve.new()
	sc.add_point(Vector2(0, 1.0))
	sc.add_point(Vector2(0.6, 0.55))
	sc.add_point(Vector2(1, 0.0))
	var g := Gradient.new()
	g.set_color(0, Color("#FFD166"))
	g.set_color(1, Color("#E63B12", 0.0))
	g.add_point(0.45, Color("#FF8C2A"))
	flames = make_emitter(40, 0.7, 0.16 * scale_factor, Vector3.UP, 12.0, 1.0 * scale_factor, 1.4 * scale_factor,
		Vector3.ZERO, 0.9 * scale_factor, 1.2 * scale_factor, sc, g, 0.35, true)
	flames.name = "Flames"
	add_child(flames)

	var ssc := Curve.new()
	ssc.add_point(Vector2(0, 0.5))
	ssc.add_point(Vector2(1, 1.6))
	var sg := Gradient.new()
	sg.set_color(0, Color("#9AA3AD", 0.35))
	sg.set_color(1, Color("#9AA3AD", 0.0))
	smoke = make_emitter(20, 2.5, 0.12 * scale_factor, Vector3.UP, 10.0, 0.6 * scale_factor, 0.9 * scale_factor,
		Vector3(0.2, 0.25, 0.1), 0.5 * scale_factor, 0.8 * scale_factor, ssc, sg, 0.6, false)
	smoke.name = "Smoke"
	smoke.position = Vector3(0, 0.5 * scale_factor, 0)
	add_child(smoke)

	light = LightFlicker.new()
	light.name = "Light"
	light.light_color = Color("#FF9A3C")
	light.base_energy = light_energy
	light.omni_range = light_range
	light.omni_attenuation = 1.3
	light.shadow_priority = shadow_priority
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
