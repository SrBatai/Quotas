class_name DayNight
extends Node
## Drives Sun / Moon / WorldEnvironment from GameState.hour. Blizzard blend comes from Weather.

const KEYS := {
	# hour: sky_top, sky_horizon, ground, ambient, ambient_energy, fog_color, fog_density, sky_energy
	0.0: [Color("#0B1A33"), Color("#1F3358"), Color("#16233B"), Color("#3C4D78"), 0.85, Color("#182640"), 0.014, 0.25],
	5.0: [Color("#0B1A33"), Color("#1F3358"), Color("#16233B"), Color("#3C4D78"), 0.85, Color("#182640"), 0.014, 0.25],
	6.5: [Color("#3E4C7A"), Color("#E0A886"), Color("#7C8AA6"), Color("#7C8CB0"), 0.8, Color("#9FA9C2"), 0.010, 0.6],
	12.0: [Color("#7FB3E6"), Color("#D6E6F5"), Color("#C9D8EA"), Color("#8EB0DC"), 0.8, Color("#C9D8EA"), 0.006, 1.0],
	18.5: [Color("#7FA6DC"), Color("#E8D8C8"), Color("#B8C6DA"), Color("#8AA6D0"), 0.8, Color("#C0CCDE"), 0.007, 0.9],
	19.5: [Color("#4E4A80"), Color("#E8A470"), Color("#7E7C98"), Color("#7E86A8"), 0.75, Color("#A9AEC4"), 0.010, 0.6],
	20.8: [Color("#0B1A33"), Color("#1F3358"), Color("#16233B"), Color("#3C4D78"), 0.85, Color("#182640"), 0.014, 0.25],
}
const BLIZZARD_FOG := Color("#B8C4D3")
const BLIZZARD_FOG_DENSITY := 0.045
const NIGHT_BLIZZARD_FOG := Color("#3A4556")

var sun: DirectionalLight3D
var moon: DirectionalLight3D
var env: WorldEnvironment
var sky_mat: ProceduralSkyMaterial
var blizzard_blend: float = 0.0
## Debug/tuning multipliers (screenshot flags use them).
var sun_scale: float = 1.0
var ambient_scale: float = 1.0


func _ready() -> void:
	var parent := get_parent()
	sun = parent.get_node_or_null("Sun")
	moon = parent.get_node_or_null("Moon")
	env = parent.get_node_or_null("Env")
	_setup()
	Events.time_changed.connect(_on_time_changed)
	apply(GameState.hour)


func _setup() -> void:
	if sun != null:
		sun.shadow_enabled = true
		sun.directional_shadow_max_distance = 70.0
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_split_1 = 0.35
		sun.directional_shadow_fade_start = 0.85
		sun.shadow_blur = 1.5
		sun.shadow_bias = 0.1
		sun.shadow_normal_bias = 2.5
	if moon != null:
		moon.shadow_enabled = false
		moon.light_color = Color("#7D9BD1")
		moon.rotation_degrees = Vector3(-45, 20, 0)
	if env != null:
		var e := Environment.new()
		e.background_mode = Environment.BG_SKY
		sky_mat = ProceduralSkyMaterial.new()
		sky_mat.sun_angle_max = 25.0
		sky_mat.sun_curve = 0.15
		var sky := Sky.new()
		sky.sky_material = sky_mat
		sky.process_mode = Sky.PROCESS_MODE_REALTIME
		sky.radiance_size = Sky.RADIANCE_SIZE_64
		e.sky = sky
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_sky_contribution = 0.0
		e.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
		e.fog_enabled = true
		e.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		e.fog_sky_affect = 0.35
		e.fog_aerial_perspective = 0.0
		e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		env.environment = e


func _on_time_changed(_day: int, hour: float, _night: bool) -> void:
	apply(hour)


func _process(_delta: float) -> void:
	# keep the blizzard blend and the menu (no clock) in sync
	apply(GameState.hour)


static func _lerp_keys(hour: float) -> Array:
	var keys := [0.0, 5.0, 6.5, 12.0, 18.5, 19.5, 20.8, 24.0]
	var h := fmod(hour, 24.0)
	for i in keys.size() - 1:
		var a: float = keys[i]
		var b: float = keys[i + 1]
		if h >= a and h < b:
			var t := (h - a) / (b - a)
			t = t * t * (3.0 - 2.0 * t)
			var ka: Array = KEYS[a]
			var kb: Array = KEYS[b if b < 24.0 else 0.0]
			var out := []
			for j in ka.size():
				if ka[j] is Color:
					out.append((ka[j] as Color).lerp(kb[j], t))
				else:
					out.append(lerpf(ka[j], kb[j], t))
			return out
	return KEYS[12.0]


func apply(hour: float) -> void:
	var t_sun := (hour - 6.0) / 12.0
	var elev := sin(t_sun * PI) * 38.0
	if sun != null:
		sun.rotation_degrees = Vector3(-maxf(elev, 2.0), 205.0 + t_sun * 40.0 - 20.0, 0)
		var energy := clampf(elev / 38.0, 0.0, 1.0)
		energy = sqrt(energy) * 0.26
		sun.light_energy = energy * (1.0 - 0.8 * blizzard_blend) * sun_scale
		sun.visible = energy > 0.01
		var warm := clampf(elev / 8.0, 0.0, 1.0)
		sun.light_color = Color("#FFB070").lerp(Color("#FFF4E0"), warm)
	if moon != null:
		var m := 0.45 * (1.0 - clampf(elev / 8.0, 0.0, 1.0))
		moon.light_energy = m * (1.0 - 0.5 * blizzard_blend)
		moon.visible = m > 0.01
	if env == null or env.environment == null:
		return
	var k := _lerp_keys(hour)
	var e := env.environment
	var night_amount := 1.0 - clampf((elev + 6.0) / 14.0, 0.0, 1.0)
	var blizzard_fog := BLIZZARD_FOG.lerp(NIGHT_BLIZZARD_FOG, night_amount)
	sky_mat.sky_top_color = (k[0] as Color).lerp(blizzard_fog, blizzard_blend)
	sky_mat.sky_horizon_color = (k[1] as Color).lerp(blizzard_fog, blizzard_blend)
	sky_mat.ground_bottom_color = k[2]
	sky_mat.ground_horizon_color = (k[1] as Color).lerp(blizzard_fog, blizzard_blend)
	sky_mat.sky_energy_multiplier = k[7]
	e.ambient_light_color = (k[3] as Color).lerp(blizzard_fog, blizzard_blend * 0.5)
	e.ambient_light_energy = lerpf(k[4], k[4] * 1.1, blizzard_blend) * ambient_scale
	e.fog_light_color = (k[5] as Color).lerp(blizzard_fog, blizzard_blend)
	e.fog_density = lerpf(k[6], BLIZZARD_FOG_DENSITY, blizzard_blend)


func is_dark() -> bool:
	var t_sun := (GameState.hour - 6.0) / 12.0
	return sin(t_sun * PI) * 38.0 < 6.0
