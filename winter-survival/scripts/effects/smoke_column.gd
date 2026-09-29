class_name SmokeColumn
extends Node3D
## G2b «vida que humea» (doc 08 §3.9): a smouldering source — a burnt car, a brazier at a checkpoint, a ruin — with a
## tall lit smoke plume (Kenney sprites, FxSprites) that drifts downwind, an ember glow (emissive quad + a dim
## flickering light at night) and, if `thaw`, a melted wet ring on the snow (Atmosphere's thaw globals via the
## `thaw_source` group; render only — it does not warm anybody, that is the server's HeatZone). One or two draw
## calls; the light only exists at night and on `alto` / `medio` (Quality lamp budget > 0), like the street lamps.
## V1 places the story ones from the server; G2b puts a few in the C0 block (AmbientLife).

@export var height: float = 1.0          # plume scale (1 ≈ 8–10 m column)
@export var darkness: float = 0.5        # 0 white steam … 1 black oil smoke
@export var embers: bool = true
@export var thaw: bool = true
@export var thaw_radius: float = 2.2

var plume: GPUParticles3D
var glow: MeshInstance3D
var light: LightFlicker
var _pm: ParticleProcessMaterial
var _t: float = 0.0


func _ready() -> void:
	_pm = ParticleProcessMaterial.new()
	_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_pm.emission_sphere_radius = 0.35 * height
	_pm.direction = Vector3.UP
	_pm.spread = 10.0
	_pm.initial_velocity_min = 1.0 * height
	_pm.initial_velocity_max = 1.6 * height
	_pm.damping_min = 0.1
	_pm.damping_max = 0.25
	_pm.gravity = FxSprites.wind_gravity(0.3 * height, 1.2 * height)
	_pm.scale_min = 0.9 * height
	_pm.scale_max = 1.3 * height
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.5))
	sc.add_point(Vector2(0.35, 1.5))
	sc.add_point(Vector2(1, 3.4))
	_pm.scale_curve = FireEffect.curve_tex(sc)
	var dark := Color("#2B2C30").lerp(Color("#8E949C"), 1.0 - darkness)
	var light_c := Color("#6E737A").lerp(Color("#C4CAD2"), 1.0 - darkness)
	var g := Gradient.new()
	g.set_color(0, Color(dark, 0.0))
	g.set_color(1, Color(light_c, 0.0))
	g.add_point(0.06, Color(dark, 0.85))
	g.add_point(0.45, Color(dark.lerp(light_c, 0.5), 0.55))
	_pm.color_ramp = FireEffect.ramp(g)
	FxSprites.randomize_frames(_pm, 18.0)
	plume = GPUParticles3D.new()
	plume.name = "Plume"
	plume.process_material = _pm
	plume.amount = int(56 * clampf(height, 0.5, 2.0))
	plume.lifetime = 7.0
	plume.preprocess = 7.0
	plume.draw_pass_1 = FireEffect.make_quad(2.6, FxSprites.smoke_material())
	plume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plume.visibility_aabb = AABB(Vector3(-30, -2, -30), Vector3(60, 30, 60))
	plume.amount_ratio = clampf(Quality.particle_ratio() * 1.4, 0.35, 1.0)
	add_child(plume)
	if embers:
		glow = MeshInstance3D.new()
		glow.name = "Embers"
		var q := QuadMesh.new()
		q.size = Vector2(1.3, 1.3)
		q.orientation = PlaneMesh.FACE_Y
		glow.mesh = q
		glow.material_override = load("res://assets/materials/ember_glow.tres")
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		glow.position = Vector3(0, 0.25, 0)
		add_child(glow)
		light = LightFlicker.new()
		light.name = "Glow"
		light.light_color = Color("#FF8A3D")
		light.base_energy = 0.6
		light.amount = 0.35
		light.omni_range = 4.5
		light.omni_attenuation = 1.6
		light.light_volumetric_fog_energy = 2.0
		light.position = Vector3(0, 0.9, 0)
		add_child(light)
	if thaw:
		set_meta("thaw_radius", thaw_radius)
		add_to_group("thaw_source")


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.5
	_pm.gravity = FxSprites.wind_gravity(0.3 * height, 1.2 * height)
	if light != null:
		# like the street lamps: real light only at night and where the preset allows real lamp lights
		light.visible = CityLights.night() > 0.3 and Quality.lamp_light_budget() > 0
