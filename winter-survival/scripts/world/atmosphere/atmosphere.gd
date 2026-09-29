class_name Atmosphere
extends Node
## G2b «Atmósfera» (PLAN v3.8.2 G2b, docs/research/08_graficos_g2.md §3.5 / §3.7 / §3.9 / §3.10, ARQ v2 §9.10):
## the client-side layer over DayNight that makes every hour read like a painting — depth between towers, wind you
## can see, life that smokes. Child of DayNight (so the dedicated server, which drops DayNight, never has it), only
## with a display. DayNight calls three hooks each frame:
##   shape_keys()  the presentation-only overcast (cloud cover «nublado»: deterministic from the world seed and the
##                 clock, the same on every client; WorldState.weather keeps its meaning: clear / blizzard)
##   shape_wind()  overcast skies blow harder (snow snakes and drift ripples run without a blizzard) + gustiness
##   post_apply()  layered fog: exponential + height (dawn mist, overcast, the street haze of G2a), sun scatter at
##                 dusk; volumetric fog only on `alto` (Forward+) and only in a blizzard or at night, with local
##                 FogVolumes (FogPatches); `compat` / `medio` get the depth back through denser exp + height fog
## and on its own: the LUT grade (LutGrade, CPU blend ≤ 0.1 ms a frame, 0 at rest), the visible thaw (thaw_* shader
## globals from the heat sources), the light snowfall by cloud cover, and AmbientLife (smoke columns, beacons and
## rotating lights, circling flocks, hanging cables in the city).

static var instance: Atmosphere

## Presentation-only cloud cover 0 (clear sky) … 1 (overcast). Deterministic: cloud_cover(seed, absolute hour).
var overcast: float = 0.0
## Tests / screenshots: force the cloud cover (≥ 0) instead of the clock's.
var overcast_override: float = -1.0
## Local player's closeness to a lit fire / stove, 0..1 (the `calor` grade).
var heat: float = 0.0
## Last LUT weights asked (LutGrade.NAMES order) and whether the city grade applies here.
var lut_weights := PackedFloat32Array()
var lut_enabled: bool = true
var city_factor: float = 0.0
## What post_apply decided (checks / bench).
var volumetric_on: bool = false
var volumetric_density: float = 0.0
var compat_fog_boost: float = 0.0
## Whiteout shadow cut (the sun's shadow fades out above 75 % blizzard); the bench can turn it off to compare.
var shadow_cut: bool = true
## Thaw sources written to the globals last time: Array of Vector4 (x, y, z, melted radius).
var thaw_sources: Array[Vector4] = []

var day_night: DayNight
var lut: LutGrade
var fog_patches: FogPatches
var life: AmbientLife
var _env: Environment
var _elev: float = 20.0
var _night: float = 0.0
var _hour: float = 12.0
var _t_slow: float = 0.0
var _t_lut: float = 0.0
var _heat_seen: Dictionary = {}      # instance id -> {pos, radius, since, gone}
var _clock: float = 0.0

## Cloud-cover noise: one front every CLOUD_PERIOD game hours; overcast above COVER_LO…COVER_HI (≈ 30 % of the time).
const CLOUD_PERIOD := 9.0
const COVER_LO := 0.5
const COVER_HI := 0.82
## The first day stays clear (the tutorial morning of GDD §3).
const CLEAR_FIRST_HOURS := 30.0
## Overcast look (mixed into DayNight's keys by `overcast`).
const OVERCAST_SUN := 0.22
const OVERCAST_SUN_COLOR := Color("#D9DDE3")
const OVERCAST_AMBIENT_DAY := Color("#8B97AD")
const OVERCAST_AMBIENT_NIGHT := Color("#3A4458")
const OVERCAST_FOG_DAY := Color("#A3ADBD")
const OVERCAST_FOG_NIGHT := Color("#4B5568")
const OVERCAST_WIND := 0.65
## Morning mist: a height-fog layer that sits in the valleys from dawn to mid-morning (TLD's cold mornings).
const MIST_DENSITY := 0.012
const MIST_TOP := 1.5
## Volumetric fog at night (alto, Forward+): thin, so lamps and fires grow halos and shafts; denser in the city.
const VOL_NIGHT := 0.0045
const VOL_NIGHT_CITY := 0.009
## Compatibility / medio: what the missing volumetrics gave, as extra exponential density.
const COMPAT_NIGHT_FOG := 0.005
const COMPAT_NIGHT_CITY_FOG := 0.011
## Heat sources: melted radius grows from THAW_R0 to the source's radius over THAW_GROW s; a dead fire's wet ring
## dries in THAW_DRY s.
const THAW_MAX := 8
const THAW_R0 := 0.35
const THAW_GROW := 40.0
const THAW_DRY := 60.0
const THAW_RANGE := 60.0


static func wanted(dn: Node) -> bool:
	return DisplayServer.get_name() != "headless" and dn != null and dn.get_parent() != null


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null
	RenderingServer.global_shader_parameter_set("thaw_info", Vector4.ZERO)


func _ready() -> void:
	day_night = get_parent() as DayNight
	lut = LutGrade.new()
	lut.preload_all()   # the 8 strips (~1 ms, world setup); the float slices convert lazily inside the frame budget
	fog_patches = FogPatches.new()
	fog_patches.name = "FogPatches"
	add_child(fog_patches)
	life = AmbientLife.new()
	life.name = "AmbientLife"
	add_child(life)


# ------------------------------------------------------------------ overcast (presentation only)

## Smooth deterministic cloud cover 0..1 at an absolute game hour ((day − 1) · 24 + hour) for a world seed.
static func cloud_cover(world_seed: int, abs_hour: float) -> float:
	var x := abs_hour / CLOUD_PERIOD
	var i := int(floor(x))
	var f := x - float(i)
	f = f * f * (3.0 - 2.0 * f)
	var a := WorldConst.unit(WorldConst.hash64(world_seed, 0x6C6F7564, i))
	var b := WorldConst.unit(WorldConst.hash64(world_seed, 0x6C6F7564, i + 1))
	var c := lerpf(a, b, f)
	# a second, faster octave breaks the fronts up
	var y := abs_hour / (CLOUD_PERIOD * 0.37)
	var j := int(floor(y))
	var g := y - float(j)
	g = g * g * (3.0 - 2.0 * g)
	var d := lerpf(WorldConst.unit(WorldConst.hash64(world_seed, 0x646F7564, j)), WorldConst.unit(WorldConst.hash64(world_seed, 0x646F7564, j + 1)), g)
	return clampf(c * 0.85 + d * 0.15, 0.0, 1.0)


## Overcast amount for a seed and absolute hour (0 on the first day).
static func overcast_at(world_seed: int, abs_hour: float) -> float:
	if abs_hour < CLEAR_FIRST_HOURS:
		return 0.0
	var ramp := smoothstep(CLEAR_FIRST_HOURS, CLEAR_FIRST_HOURS + 3.0, abs_hour)
	return smoothstep(COVER_LO, COVER_HI, cloud_cover(world_seed, abs_hour)) * ramp


## The overcast the clients show now (0 without an Atmosphere, e.g. headless).
static func overcast_now() -> float:
	return instance.overcast if instance != null else 0.0


func _update_overcast() -> void:
	if overcast_override >= 0.0:
		overcast = clampf(overcast_override, 0.0, 1.0)
		return
	# a blizzard comes under its own cloud deck
	var b := day_night.blizzard_blend if day_night != null else 0.0
	if WorldState.instance == null:
		overcast = b
		return
	var abs_h := float(WorldState.day_now() - 1) * 24.0 + WorldState.hour_now()
	overcast = maxf(overcast_at(WorldState.instance.world_seed, abs_h), b)


# ------------------------------------------------------------------ DayNight hooks

## Mixes the overcast look into the hour's keys (before DayNight mixes the blizzard in).
func shape_keys(k: Array, hour: float, elev: float, night_amount: float) -> Array:
	_hour = hour
	_elev = elev
	_night = night_amount
	_update_overcast()
	var o := overcast
	if o <= 0.001:
		return k
	var out := k.duplicate()
	var day := 1.0 - night_amount
	out[DayNight.K_SUN_ENERGY] = float(k[DayNight.K_SUN_ENERGY]) * lerpf(1.0, OVERCAST_SUN, o)
	out[DayNight.K_SUN_COLOR] = (k[DayNight.K_SUN_COLOR] as Color).lerp(OVERCAST_SUN_COLOR, 0.6 * o)
	var amb := OVERCAST_AMBIENT_DAY.lerp(OVERCAST_AMBIENT_NIGHT, night_amount)
	out[DayNight.K_AMBIENT] = (k[DayNight.K_AMBIENT] as Color).lerp(amb, 0.55 * o)
	out[DayNight.K_AMBIENT_ENERGY] = float(k[DayNight.K_AMBIENT_ENERGY]) * lerpf(1.0, lerpf(0.85, 1.18, day), o)
	var fog := OVERCAST_FOG_DAY.lerp(OVERCAST_FOG_NIGHT, night_amount)
	out[DayNight.K_FOG] = (k[DayNight.K_FOG] as Color).lerp(fog, 0.6 * o)
	out[DayNight.K_FOG_DENSITY] = float(k[DayNight.K_FOG_DENSITY]) * (1.0 + 0.8 * o) + 0.002 * o
	out[DayNight.K_FOG_HEIGHT_DENSITY] = float(k[DayNight.K_FOG_HEIGHT_DENSITY]) + 0.006 * o
	out[DayNight.K_SATURATION] = float(k[DayNight.K_SATURATION]) * lerpf(1.0, 0.92, o)
	out[DayNight.K_SSAO] = float(k[DayNight.K_SSAO]) * lerpf(1.0, 1.15, o)
	out[DayNight.K_SPARKLE] = float(k[DayNight.K_SPARKLE]) * (1.0 - 0.85 * o)
	for key in [DayNight.K_SKY_TOP, DayNight.K_SKY_HORIZON, DayNight.K_SKY_GROUND]:
		out[key] = (k[key] as Color).lerp(fog, 0.7 * o)
	return out


## Wind (xy direction, z strength, w gustiness): overcast skies blow harder than the clear prevailing drift.
func shape_wind(w: Vector4) -> Vector4:
	var o := overcast
	var z := snappedf(maxf(w.z, lerpf(w.z, OVERCAST_WIND, o)), 0.01)
	var gusty := clampf(0.25 + 0.5 * o + 0.5 * (w.z - 0.3) / 0.7, 0.0, 1.0)
	return Vector4(w.x, w.y, z, snappedf(gusty, 0.05))


## After DayNight wrote the Environment: fog layers, volumetric policy, moon under clouds, snowfall density.
func post_apply(e: Environment, hour: float, elev: float, night_amount: float) -> void:
	_env = e
	_hour = hour
	_elev = elev
	_night = night_amount
	var b := day_night.blizzard_blend if day_night != null else 0.0
	var o := overcast
	var city := _city_amount()
	city_factor = city
	# --- height layer: dawn mist in the valleys (6–10 h), a thin overcast layer; the G2a street haze stays on top
	var mist := smoothstep(5.0, 6.5, hour) * (1.0 - smoothstep(8.5, 10.5, hour)) * (1.0 - b)
	e.fog_height_density += MIST_DENSITY * mist * (1.0 - 0.5 * city)
	if mist > 0.01 and e.fog_height < MIST_TOP + day_night.fog_height_offset:
		e.fog_height = lerpf(e.fog_height, MIST_TOP + day_night.fog_height_offset, mist)
	# --- sun scatter: warm fog toward a low sun (depth between towers at dusk)
	var golden := smoothstep(-4.0, 3.0, elev) * (1.0 - smoothstep(8.0, 16.0, elev))
	e.fog_sun_scatter = 0.22 * golden * (1.0 - o) * (1.0 - b)
	# --- volumetric fog: alto (Forward+) only, only in a blizzard or at night
	var can_vol := Quality.allows("volumetric_fog")
	var night_vol := lerpf(VOL_NIGHT, VOL_NIGHT_CITY, city) * smoothstep(0.5, 0.9, night_amount) * (1.0 + 0.6 * o)
	var dens := DayNight.VOLUMETRIC_DENSITY * b + night_vol * (1.0 - b)
	volumetric_on = can_vol and (b > 0.02 or night_amount > 0.5) and dens > 0.0005
	volumetric_density = dens if volumetric_on else 0.0
	e.volumetric_fog_enabled = volumetric_on
	if volumetric_on:
		e.volumetric_fog_density = dens
		# the fog lit by the ambient: pale in a daytime blizzard, dark blue at night (no glowing sheet)
		e.volumetric_fog_albedo = Color("#D8DEE8").lerp(Color("#8795AE"), night_amount)
		e.volumetric_fog_ambient_inject = lerpf(0.5, 0.25, night_amount)
	# --- depth without volumetrics (compat / medio): denser exponential fog at night, more in the city
	compat_fog_boost = 0.0
	if not can_vol:
		compat_fog_boost = lerpf(COMPAT_NIGHT_FOG, COMPAT_NIGHT_CITY_FOG, city) * smoothstep(0.5, 0.9, night_amount) * (1.0 - b)
		e.fog_density += compat_fog_boost * day_night.fog_density_scale
	# --- the moon behind clouds
	if day_night.moon != null and o > 0.0:
		day_night.moon.light_energy *= 1.0 - 0.55 * o
	# --- whiteout: under the blizzard's deck the sun (×0.22 of an already weak 0.10) casts no readable shadow; the
	# shadow fades out and its passes stop (doc 08 §5.1 budgets the blizzard's shadow at 1.0 ms vs 1.8–2.5 by day)
	if day_night.sun != null:
		var fade := smoothstep(0.75, 0.97, b) if shadow_cut else 0.0
		day_night.sun.shadow_opacity = 1.0 - fade
		var want := fade < 0.99
		if day_night.sun.shadow_enabled != want:
			day_night.sun.shadow_enabled = want
		if day_night.moon != null and not Quality.is_compat_renderer() and day_night.moon.shadow_enabled != want:
			day_night.moon.shadow_enabled = want
	fog_patches.set_state(volumetric_on, night_amount, b, city)


## 0..1: the camera is in a city profile (street haze), or a mirador / the menu skyline forced the fog colour.
func _city_amount() -> float:
	var c := day_night.city_haze if day_night != null else 0.0
	if day_night != null and day_night.fog_color_override.a > 0.0:
		c = 1.0
	return clampf(c, 0.0, 1.0)


# ------------------------------------------------------------------ LUT weights

## Grade weights (LutGrade.NAMES order) for a sun elevation, night amount, cloud cover, blizzard blend, city factor
## (camera in the city 0..1), grid power where the camera is (0 blackout … 1) and closeness to a fire. Pure.
static func lut_weights_for(elev: float, night_amount: float, o: float, b: float, city: float, power: float, h: float) -> PackedFloat32Array:
	var w := PackedFloat32Array()
	w.resize(LutGrade.NAMES.size())
	var n := clampf(night_amount, 0.0, 1.0)
	var golden := smoothstep(-6.0, 2.0, elev) * (1.0 - smoothstep(8.0, 16.0, elev)) * (1.0 - n)
	var day := maxf(1.0 - n - golden, 0.0)
	# clouds take the daylight (and most of the golden hour)
	w[0] = day * (1.0 - o)                       # dia_claro
	w[1] = (day + 0.7 * golden) * o              # nublado
	w[3] = golden * (1.0 - 0.7 * o)              # atardecer
	# night: moonlit snow, or the city at night — lit (generators, grid) or blacked out
	w[4] = n * (1.0 - city)                      # noche
	w[5] = n * city * power                      # noche_ciudad
	w[6] = n * city * (1.0 - power)              # apagon
	# a blizzard takes over (less at night: the dark stays dark)
	var bz := clampf(b, 0.0, 1.0) * (1.0 - 0.45 * n)
	for i in w.size():
		w[i] *= 1.0 - bz
	w[2] = bz                                    # ventisca
	# by the fire: up to half the grade warms up
	var hc := clampf(h, 0.0, 1.0) * 0.5
	for i in w.size():
		w[i] *= 1.0 - hc
	w[7] = hc                                    # calor
	return w


func _update_lut(force_target: bool = false) -> void:
	if not lut_enabled or lut == null or not lut.available():
		return
	# the target at 10 Hz (the grade moves in 1/128 steps anyway); the blend steps every frame only while busy
	if force_target or _t_lut <= 0.0:
		_t_lut = 0.1
		var power := 1.0
		if city_factor > 0.0:
			power = CityLights.power_at(_focus())
		lut_weights = lut_weights_for(_elev, _night, overcast, day_night.blizzard_blend if day_night != null else 0.0,
			city_factor, power, heat)
		lut.set_target(lut_weights)
	if lut.step() or (_env != null and _env.adjustment_color_correction != lut.texture and lut.texture != null):
		if _env != null:
			_env.adjustment_enabled = true
			_env.adjustment_color_correction = lut.texture


## Tests / screenshots: blend the current target now.
func flush_lut() -> void:
	if lut == null:
		return
	_update_lut(true)
	lut.flush()
	if _env != null and lut.texture != null:
		_env.adjustment_enabled = true
		_env.adjustment_color_correction = lut.texture


# ------------------------------------------------------------------ per frame

func _process(delta: float) -> void:
	_clock += delta
	_t_lut -= delta
	_update_lut()
	_t_slow -= delta
	if _t_slow > 0.0:
		return
	_t_slow = 0.25
	_update_heat()
	_update_snowfall()
	FxSprites.set_night_glow(_night, city_factor)


## Heat sources near the camera: the thaw globals (8 nearest, melted radius growing while they burn, drying after)
## and the local player's warmth for the `calor` grade.
func _update_heat() -> void:
	var focus := _focus()
	var now := _clock
	var seen := {}
	for n in get_tree().get_nodes_in_group("heat_source") + get_tree().get_nodes_in_group("thaw_source"):
		var n3 := n as Node3D
		if n3 == null or not n3.is_inside_tree():
			continue
		var p := n3.global_position
		if p.distance_to(focus) > THAW_RANGE:
			continue
		var id := n3.get_instance_id()
		seen[id] = true
		var r := float(n3.get_meta("thaw_radius", 2.6))
		var rec: Dictionary = _heat_seen.get(id, {})
		if rec.is_empty():
			rec = {"since": now}
		rec["pos"] = p
		rec["radius"] = r
		rec["gone"] = -1.0
		_heat_seen[id] = rec
	for id in _heat_seen.keys():
		var rec: Dictionary = _heat_seen[id]
		if not seen.has(id) and float(rec["gone"]) < 0.0:
			rec["gone"] = now
		if float(rec["gone"]) >= 0.0 and now - float(rec["gone"]) > THAW_DRY:
			_heat_seen.erase(id)
	var list: Array = []
	for id in _heat_seen:
		var rec: Dictionary = _heat_seen[id]
		var grow := clampf((now - float(rec["since"])) / THAW_GROW, 0.0, 1.0)
		var r := lerpf(THAW_R0, float(rec["radius"]), 1.0 - pow(1.0 - grow, 2.0))
		if float(rec["gone"]) >= 0.0:
			r *= 1.0 - clampf((now - float(rec["gone"])) / THAW_DRY, 0.0, 1.0)
		if r > 0.05:
			var p: Vector3 = rec["pos"]
			list.append([p.distance_squared_to(focus), Vector4(p.x, p.y, p.z, r)])
	list.sort_custom(func(a: Array, c: Array) -> bool: return float(a[0]) < float(c[0]))
	thaw_sources.clear()
	for i in mini(list.size(), THAW_MAX):
		thaw_sources.append(list[i][1])
	write_thaw_globals(thaw_sources)
	heat = _player_heat()


## Writes the thaw globals (up to 8 sources: x, y, z, melted radius).
static func write_thaw_globals(sources: Array[Vector4]) -> void:
	var cols: Array[Vector4] = []
	for i in 8:
		cols.append(sources[i] if i < sources.size() else Vector4.ZERO)
	RenderingServer.global_shader_parameter_set("thaw_a", Projection(cols[0], cols[1], cols[2], cols[3]))
	RenderingServer.global_shader_parameter_set("thaw_b", Projection(cols[4], cols[5], cols[6], cols[7]))
	RenderingServer.global_shader_parameter_set("thaw_info", Vector4(float(mini(sources.size(), 8)), 0.0, 0.0, 0.0))


## 0..1 closeness of the local player to a lit fire (campfire radius) or a lit stove in the same room.
func _player_heat() -> float:
	var p: Node = GameFlow.local_player()
	if p == null or not is_instance_valid(p) or not (p is Node3D):
		return move_toward(heat, 0.0, 0.25)
	var pos := (p as Node3D).global_position
	var best := 0.0
	for n in get_tree().get_nodes_in_group("heat_source"):
		var n3 := n as Node3D
		if n3 == null:
			continue
		var r := float(Balance.CAMPFIRE_HEAT_RADIUS)
		var d := n3.global_position.distance_to(pos)
		best = maxf(best, 1.0 - smoothstep(0.35 * r, r, d))
	for n in get_tree().get_nodes_in_group("stove"):
		if not bool(n.get("is_lit")):
			continue
		var d := (n as Node3D).global_position.distance_to(pos)
		best = maxf(best, 0.8 * (1.0 - smoothstep(2.0, 5.0, d)))
	return move_toward(heat, best, 0.2)


## Light snowfall follows the cloud cover: a few flakes under a clear sky, the full light snow when overcast
## (the blizzard emitter is Weather's business).
func _update_snowfall() -> void:
	var sf := day_night.get_parent().get_node_or_null("Snowfall") as Snowfall if day_night != null else null
	if sf == null or sf.light_snow == null:
		return
	sf.light_snow.amount_ratio = Quality.particle_ratio() * lerpf(0.45, 1.0, maxf(overcast, day_night.blizzard_blend))


func _focus() -> Vector3:
	var rig := CameraRig.active()
	if rig != null:
		return rig.global_position
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp != null else null
	if cam != null:
		return cam.global_position + (-cam.global_basis.z) * 20.0
	return Vector3.ZERO
