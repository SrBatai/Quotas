class_name SmokeEffect
extends GPUParticles3D
## Chimney smoke column (GPUParticles3D, PLAN C4; G2b: Kenney smoke sprites, lit, drifting downwind). One draw call.
## The puffs rise, widen and thin out; the wind (DayNight.current_wind) bends the column — a straight thread on a calm
## morning, a smear along the roofs in a blizzard. `set_active` keeps the M2 API (the cabin's stove).

const WIND_REFRESH := 0.5

@export var column_height: float = 1.0   # scales speed / size (1 = a house chimney)
var _pm: ParticleProcessMaterial
var _t: float = 0.0


func _ready() -> void:
	_pm = ParticleProcessMaterial.new()
	_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_pm.emission_sphere_radius = 0.15
	_pm.direction = Vector3.UP
	_pm.spread = 8.0
	_pm.initial_velocity_min = 0.7 * column_height
	_pm.initial_velocity_max = 1.1 * column_height
	_pm.damping_min = 0.15
	_pm.damping_max = 0.3
	_pm.gravity = FxSprites.wind_gravity(0.18, 0.9)
	_pm.scale_min = 0.8 * column_height
	_pm.scale_max = 1.1 * column_height
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.45))
	sc.add_point(Vector2(0.4, 1.3))
	sc.add_point(Vector2(1, 2.6))
	_pm.scale_curve = FireEffect.curve_tex(sc)
	var g := Gradient.new()
	g.set_color(0, Color("#C9D0D9", 0.0))
	g.set_color(1, Color("#B8C0CA", 0.0))
	g.add_point(0.08, Color("#D2D8E0", 0.7))
	g.add_point(0.55, Color("#C3CAD3", 0.4))
	_pm.color_ramp = FireEffect.ramp(g)
	FxSprites.randomize_frames(_pm, 25.0)
	process_material = _pm
	amount = 40
	lifetime = 6.0
	preprocess = 3.0
	draw_pass_1 = FireEffect.make_quad(1.5, FxSprites.smoke_material())
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visibility_aabb = AABB(Vector3(-14, -2, -14), Vector3(28, 18, 28))
	emitting = false


func _process(delta: float) -> void:
	if not emitting:
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = WIND_REFRESH
	_pm.gravity = FxSprites.wind_gravity(0.18 * column_height, 0.9)


func set_active(value: bool) -> void:
	emitting = value
