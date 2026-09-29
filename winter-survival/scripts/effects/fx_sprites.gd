class_name FxSprites
extends RefCounted
## G2b particle sprites (Kenney *Particle Pack* 1.1, CC0 — assets/textures/fx/manifest.json, tools/fetch_fx_sprites.py):
## 2 × 2 flipbook atlases of smoke puffs and flame tongues, white with alpha (the colour ramps tint them). Shared
## materials (one per look, so the renderer batches by material):
##   smoke_material()  lit per vertex (the sun, the ambient and nearby fires light the smoke; it goes dark at night
##                     like the real thing), alpha blend, particle billboard with a random frame and spin per puff,
##                     soft edge against the ground on Forward+ (proximity fade), none in Compatibility
##   flame_material()  unshaded, additive (glow picks it up)
## plus the wind drift every emitter shares (DayNight.current_wind): wind_gravity().

const SMOKE := "res://assets/textures/fx/smoke_atlas.png"
const FLAME := "res://assets/textures/fx/flame_atlas.png"

static var _smoke: StandardMaterial3D
static var _flame: StandardMaterial3D


static func has_sprites() -> bool:
	return ResourceLoader.exists(SMOKE) and ResourceLoader.exists(FLAME)


static func smoke_material() -> StandardMaterial3D:
	if _smoke != null:
		return _smoke
	var m := StandardMaterial3D.new()
	m.resource_name = "fx_smoke"
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.disable_receive_shadows = true
	m.roughness = 1.0
	m.metallic_specular = 0.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if ResourceLoader.exists(SMOKE):
		m.albedo_texture = load(SMOKE)
		m.particles_anim_h_frames = 2
		m.particles_anim_v_frames = 2
		m.particles_anim_loop = false
	else:
		m.albedo_texture = FireEffect.soft_dot_texture()
	# soft contact with the ground and walls (depth texture): Forward+ only
	if not Quality.is_compat_renderer():
		m.proximity_fade_enabled = true
		m.proximity_fade_distance = 0.8
	# at night a lit plume would vanish into the dark: it picks up the sky / city glow (Atmosphere sets the energy)
	m.emission_enabled = true
	m.emission = Color("#8A93A6")
	m.emission_energy_multiplier = 0.0
	_smoke = m
	return m


## Atmosphere (4 Hz): the smoke's own glow at night (0 by day), a little more in the city (street light and haze).
static func set_night_glow(night: float, city: float) -> void:
	if _smoke == null:
		return
	var e := clampf(night, 0.0, 1.0) * lerpf(0.10, 0.18, clampf(city, 0.0, 1.0))
	if absf(_smoke.emission_energy_multiplier - e) > 0.005:
		_smoke.emission_energy_multiplier = e


static func flame_material() -> StandardMaterial3D:
	if _flame != null:
		return _flame
	var m := StandardMaterial3D.new()
	m.resource_name = "fx_flame"
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.disable_receive_shadows = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if ResourceLoader.exists(FLAME):
		m.albedo_texture = load(FLAME)
		m.particles_anim_h_frames = 2
		m.particles_anim_v_frames = 2
		m.particles_anim_loop = false
	else:
		m.albedo_texture = FireEffect.soft_dot_texture()
	_flame = m
	return m


## A random atlas frame and a random spin per particle (for the flipbook materials above).
static func randomize_frames(pm: ParticleProcessMaterial, spin: float = 20.0) -> void:
	pm.anim_speed_min = 0.0
	pm.anim_speed_max = 0.0
	pm.anim_offset_min = 0.0
	pm.anim_offset_max = 1.0
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -spin
	pm.angular_velocity_max = spin


## Gravity that carries a plume downwind: `rise` m/s² up, plus the wind (DayNight.current_wind: xy direction,
## z strength 0.3 calm … 1 blizzard) scaled by `drift`. Calm air leaves an almost straight column; a blizzard lays
## it flat along the ground.
static func wind_gravity(rise: float, drift: float) -> Vector3:
	var w := DayNight.current_wind
	var s := clampf(w.z, 0.0, 1.5)
	var k := drift * (0.25 + 1.6 * s * s)
	return Vector3(w.x * k, rise * (1.0 - 0.55 * smoothstep(0.5, 1.0, s)), w.y * k)
