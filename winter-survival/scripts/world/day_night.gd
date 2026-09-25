class_name DayNight
extends Node
## Drives Sun / Moon / WorldEnvironment from GameState.hour (G1 look, docs/research/06_graficos_render.md §4.1):
## Filmic tonemap, the blue lives in the ambient and the snow albedo (the sun is a weak warm white), sun low and
## back-lit, sky-coloured exponential fog (bluer by day, LIGHTER than the snow at night), glow only with warm
## lights, SSAO / volumetric fog as far as the Quality preset allows. Blizzard blend comes from Weather. The warm
## lights (window spill, lantern, campfire) read `spill_scale` through the "window_spill" group.

## Per-key columns (sRGB hex colours). Interpolated with smoothstep between KEY_HOURS.
const K_SUN_COLOR := 0
const K_SUN_ENERGY := 1
const K_AMBIENT := 2
const K_AMBIENT_ENERGY := 3
const K_FOG := 4
const K_FOG_DENSITY := 5
const K_FOG_HEIGHT := 6
const K_FOG_HEIGHT_DENSITY := 7
const K_AERIAL := 8
const K_EXPOSURE := 9
const K_SATURATION := 10
const K_GLOW := 11           # glow intensity (0 = off)
const K_GLOW_THRESHOLD := 12
const K_GLOW_BLOOM := 13
const K_SSAO := 14           # SSAO intensity
const K_SPILL := 15          # warm light scale (windows / lantern / campfire)
const K_SKY_TOP := 16
const K_SKY_HORIZON := 17
const K_SKY_GROUND := 18
const K_SKY_ENERGY := 19
const K_SPARKLE := 20        # terrain sparkle strength

const NIGHT := [Color("#8EA0C4"), 0.0, Color("#3E4A66"), 0.42, Color("#66788C"), 0.011, -1.0, 0.020, 0.0, 0.60, 1.05,
	0.7, 1.0, 0.02, 2.0, 0.45, Color("#0B1A33"), Color("#1F3358"), Color("#66788C"), 0.25, 0.0]
const DUSK := [Color("#FFB27A"), 0.12, Color("#5A80B2"), 1.0, Color("#6E86B8"), 0.010, -1.0, 0.015, 0.15, 0.65, 1.0,
	0.55, 1.05, 0.0, 2.2, 0.3, Color("#4D4F86"), Color("#D8A488"), Color("#6E86B8"), 0.6, 0.25]
const DAY := [Color("#F8F3EA"), 0.5, Color("#6A88C4"), 1.45, Color("#A9BEDC"), 0.0040, -2.0, 0.0, 0.10, 0.55, 1.0,
	0.0, 1.05, 0.0, 2.5, 0.0, Color("#6FA6E4"), Color("#D2E1F3"), Color("#A9BEDC"), 1.0, 0.8]
## Blizzard target (blended in by `blizzard_blend`; fog gets darker at night, see NIGHT_BLIZZARD_FOG).
const BLIZZARD := [Color("#E6EAF2"), 0.25, Color("#8E9DBA"), 1.25, Color("#AEB8C9"), 0.022, 0.0, 0.0, 0.0, 0.55, 0.9,
	0.0, 1.05, 0.0, 1.6, 0.7, Color("#B4BECF"), Color("#B4BECF"), Color("#AEB8C9"), 0.8, 0.0]
const NIGHT_BLIZZARD_FOG := Color("#4A5468")
const NIGHT_BLIZZARD_AMBIENT := Color("#4E5A78")
const KEYS := {0.0: NIGHT, 4.5: NIGHT, 6.0: DUSK, 8.5: DAY, 17.0: DAY, 19.0: DUSK, 20.5: NIGHT}
const KEY_HOURS := [0.0, 4.5, 6.0, 8.5, 17.0, 19.0, 20.5, 24.0]
## Sun arc (doc 06 §3.3): rises at SUNRISE, sets at SUNSET, peaks at SUN_ELEVATION_MAX degrees (long shadows).
const SUNRISE := 6.0
const SUNSET := 20.0
const SUN_ELEVATION_MAX := 26.0
## Back-light at the default camera yaw (45°): the sun travels from screen-right to screen-top-left through the
## day and always throws the shadows toward the camera (+Z). `sun_follows_camera` keeps that offset when the
## camera rotates (a trick: shadows swing with the camera; off by default, R-G4).
const SUN_YAW_MORNING := 130.0
const SUN_YAW_NOON := 168.0
const SUN_YAW_EVENING := 205.0
const MOON_ROTATION := Vector3(-42.0, 205.0, 0.0)
const COMPAT_BLIZZARD_FOG_DENSITY := 0.035
const VOLUMETRIC_DENSITY := 0.028

var sun: DirectionalLight3D
var moon: DirectionalLight3D
var env: WorldEnvironment
var sky_mat: ProceduralSkyMaterial
var blizzard_blend: float = 0.0
## Last value written to the `snow_amount` global shader parameter (readable headless, where the dummy renderer keeps nothing).
var snow_amount: float = 0.0
## Warm light multiplier of the current hour (0 by day). Window spills / lantern / campfire follow it.
var spill_scale: float = 0.0
## Debug/tuning multipliers (screenshot flags use them).
var sun_scale: float = 1.0
var ambient_scale: float = 1.0
var sun_follows_camera: bool = false
## Hour shown when there is no WorldState (decorative world in the main menu).
var menu_hour: float = 17.75

var _camera_yaw: float = Balance.CAMERA_YAW_DEG
var _last_spill: float = -1.0
var _last_sparkle: float = -1.0
var _compat: bool = false


func _ready() -> void:
	var parent := get_parent()
	sun = parent.get_node_or_null("Sun")
	moon = parent.get_node_or_null("Moon")
	env = parent.get_node_or_null("Env")
	_compat = Quality.is_compat_renderer()
	_setup()
	Events.time_changed.connect(_on_time_changed)
	Events.camera_yaw_changed.connect(func(yaw: float) -> void: _camera_yaw = yaw)
	apply(WorldState.hour_now() if WorldState.instance != null else menu_hour)


func _setup() -> void:
	if sun != null:
		sun.shadow_enabled = true
		sun.directional_shadow_split_1 = 0.35
		sun.directional_shadow_fade_start = 0.85
		sun.shadow_bias = 0.04 if not _compat else 0.05
		sun.shadow_normal_bias = 1.8 if not _compat else 2.0
		Quality.apply_to_sun(sun)  # 2 splits, 4096 atlas (alto), PCSS angle, 50–60 m
	if moon != null:
		moon.shadow_enabled = not _compat
		moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		moon.directional_shadow_max_distance = 60.0
		moon.shadow_bias = 0.05
		moon.shadow_normal_bias = 2.0
		moon.shadow_blur = 3.0
		moon.light_angular_distance = 3.0 if not _compat else 0.0
		moon.light_color = NIGHT[K_SUN_COLOR]
		moon.light_indirect_energy = 0.5
		moon.rotation_degrees = MOON_ROTATION
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
		e.fog_sky_affect = 0.0
		e.fog_sun_scatter = 0.0
		e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		e.tonemap_white = 1.0
		e.adjustment_enabled = true
		e.adjustment_brightness = 1.0
		e.adjustment_contrast = 1.0
		e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
		e.ssao_radius = 1.4
		e.ssao_power = 1.6
		e.ssao_detail = 0.4
		e.ssao_light_affect = 0.15
		e.ssao_sharpness = 0.98
		e.volumetric_fog_albedo = Color("#D8DEE8")
		e.volumetric_fog_anisotropy = 0.35
		e.volumetric_fog_length = 64.0
		e.volumetric_fog_ambient_inject = 0.5
		e.volumetric_fog_sky_affect = 1.0
		e.volumetric_fog_temporal_reprojection_enabled = true
		env.environment = e
		Quality.apply_to_environment(e)
		env.add_to_group("quality_env")


func _on_time_changed(_day: int, hour: float, _night: bool) -> void:
	apply(hour)


func _process(_delta: float) -> void:
	# keep the blizzard blend and the menu (no clock) in sync
	apply(WorldState.hour_now() if WorldState.instance != null else menu_hour)


static func _lerp_keys(hour: float) -> Array:
	var h := fmod(hour, 24.0)
	for i in KEY_HOURS.size() - 1:
		var a: float = KEY_HOURS[i]
		var b: float = KEY_HOURS[i + 1]
		if h >= a and h < b:
			var t := (h - a) / (b - a)
			t = t * t * (3.0 - 2.0 * t)
			return _mix(KEYS[a], KEYS[b if b < 24.0 else 0.0], t)
	return DAY


static func _mix(ka: Array, kb: Array, t: float) -> Array:
	var out := []
	for j in ka.size():
		if ka[j] is Color:
			out.append((ka[j] as Color).lerp(kb[j], t))
		else:
			out.append(lerpf(ka[j], kb[j], t))
	return out


## Sun elevation in degrees for an hour (negative below the horizon).
static func sun_elevation(hour: float) -> float:
	var t := (hour - SUNRISE) / (SUNSET - SUNRISE)
	return sin(t * PI) * SUN_ELEVATION_MAX


func apply(hour: float) -> void:
	var elev := sun_elevation(hour)
	var k := _lerp_keys(hour)
	var night_amount := 1.0 - clampf((elev + 4.0) / 10.0, 0.0, 1.0)
	if blizzard_blend > 0.0:
		var bz := BLIZZARD.duplicate()
		bz[K_FOG] = (BLIZZARD[K_FOG] as Color).lerp(NIGHT_BLIZZARD_FOG, night_amount)
		bz[K_AMBIENT] = (BLIZZARD[K_AMBIENT] as Color).lerp(NIGHT_BLIZZARD_AMBIENT, night_amount)
		bz[K_AMBIENT_ENERGY] = lerpf(BLIZZARD[K_AMBIENT_ENERGY], 0.55, night_amount)
		bz[K_SKY_TOP] = bz[K_FOG]
		bz[K_SKY_HORIZON] = bz[K_FOG]
		bz[K_SKY_GROUND] = bz[K_FOG]
		bz[K_GLOW] = k[K_GLOW]
		bz[K_GLOW_THRESHOLD] = k[K_GLOW_THRESHOLD]
		bz[K_GLOW_BLOOM] = k[K_GLOW_BLOOM]
		if _compat:
			bz[K_FOG_DENSITY] = COMPAT_BLIZZARD_FOG_DENSITY
		k = _mix(k, bz, blizzard_blend)
	var t_day := (hour - SUNRISE) / (SUNSET - SUNRISE)
	if sun != null:
		var yaw := SUN_YAW_NOON
		if t_day < 0.5:
			yaw = lerpf(SUN_YAW_MORNING, SUN_YAW_NOON, clampf(t_day * 2.0, 0.0, 1.0))
		else:
			yaw = lerpf(SUN_YAW_NOON, SUN_YAW_EVENING, clampf((t_day - 0.5) * 2.0, 0.0, 1.0))
		if sun_follows_camera:
			yaw += _camera_yaw - Balance.CAMERA_YAW_DEG
		sun.rotation_degrees = Vector3(-maxf(elev, 2.0), yaw, 0)
		var energy: float = k[K_SUN_ENERGY] * clampf(elev / 4.0, 0.0, 1.0)
		sun.light_energy = energy * sun_scale * Quality.sun_scale()
		sun.visible = energy > 0.005
		sun.light_color = k[K_SUN_COLOR]
		sun.shadow_blur = lerpf(float(Quality.settings()["shadow_blur"]), 2.5, maxf(blizzard_blend, 1.0 - clampf(elev / 12.0, 0.0, 1.0)))
	if moon != null:
		var m := 0.12 * night_amount
		moon.light_energy = m * (1.0 - 0.6 * blizzard_blend)
		moon.visible = m > 0.005
	spill_scale = k[K_SPILL]
	if absf(spill_scale - _last_spill) > 0.005:
		_last_spill = spill_scale
		for n in get_tree().get_nodes_in_group("window_spill"):
			n.set_spill_scale(spill_scale)
	if env == null or env.environment == null:
		return
	var e := env.environment
	sky_mat.sky_top_color = k[K_SKY_TOP]
	sky_mat.sky_horizon_color = k[K_SKY_HORIZON]
	sky_mat.ground_bottom_color = k[K_SKY_GROUND]
	sky_mat.ground_horizon_color = k[K_SKY_GROUND]
	sky_mat.sky_energy_multiplier = k[K_SKY_ENERGY]
	e.ambient_light_color = k[K_AMBIENT]
	e.ambient_light_energy = k[K_AMBIENT_ENERGY] * ambient_scale
	e.fog_light_color = k[K_FOG]
	e.fog_density = k[K_FOG_DENSITY]
	e.fog_height = k[K_FOG_HEIGHT]
	e.fog_height_density = k[K_FOG_HEIGHT_DENSITY]
	e.fog_aerial_perspective = k[K_AERIAL]
	e.tonemap_exposure = k[K_EXPOSURE] * Quality.exposure_scale()
	e.adjustment_saturation = k[K_SATURATION]
	var glow: float = k[K_GLOW]
	e.glow_enabled = Quality.allows("glow") and glow > 0.01
	if e.glow_enabled:
		e.glow_intensity = glow
		e.glow_hdr_threshold = k[K_GLOW_THRESHOLD]
		e.glow_bloom = k[K_GLOW_BLOOM]
	e.ssao_enabled = Quality.allows("ssao")
	if e.ssao_enabled:
		e.ssao_intensity = k[K_SSAO]
	e.volumetric_fog_enabled = Quality.allows("volumetric_fog") and blizzard_blend > 0.02
	if e.volumetric_fog_enabled:
		e.volumetric_fog_density = VOLUMETRIC_DENSITY * blizzard_blend
	if absf(float(k[K_SPARKLE]) - _last_sparkle) > 0.01:
		_last_sparkle = k[K_SPARKLE]
		Assets.get_terrain_material().set_shader_parameter("sparkle_strength", _last_sparkle)
	# snow accumulates on upward faces of every world_vcol surface while the blizzard blows (PLAN C17)
	snow_amount = blizzard_blend * Quality.snow_amount_max()
	RenderingServer.global_shader_parameter_set("snow_amount", snow_amount)


func is_dark() -> bool:
	return sun_elevation(WorldState.hour_now()) < 4.0
