class_name Snowfall
extends Node3D
## Constant light snow + heavy wind-driven emitter during blizzards. GPUParticles3D (PLAN C4), follows the
## active camera. Amount scales with the Quality preset (blizzard: 2 200 / 1 320 / 770 flakes, doc 06 §3.11);
## the server/headless never instantiates this scene. Blizzard flakes are 5×22 cm quads aligned to their
## velocity (streaks read as wind), the calm snow keeps small round flakes.

var light_snow: GPUParticles3D
var heavy_snow: GPUParticles3D
var _wind_yaw: float = 0.0


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("#F1F5FA", 0.9)
	mat.albedo_texture = FireEffect.soft_dot_texture()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.disable_receive_shadows = true
	light_snow = _make(500, 8.0, Vector3(0, -1.6, 0), 0.3, 0.06, 0.10, mat, false)
	light_snow.name = "Light"
	add_child(light_snow)
	var streak := StandardMaterial3D.new()
	streak.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	streak.albedo_color = Color(0.95, 0.97, 1.0, 0.85)
	streak.albedo_texture = FireEffect.soft_dot_texture()
	streak.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	streak.cull_mode = BaseMaterial3D.CULL_DISABLED
	streak.disable_receive_shadows = true
	heavy_snow = _make(2200, 5.0, Vector3(-4.0, -3.0, 0), 1.0, 0.07, 0.28, streak, true)
	heavy_snow.name = "Heavy"
	heavy_snow.emitting = false
	add_child(heavy_snow)
	Quality.preset_changed.connect(func(_p: StringName) -> void: _apply_quality())
	_apply_quality()


func _make(amount: int, lifetime: float, gravity: Vector3, vel: float, w: float, h: float, mat: Material, streaks: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(22, 7, 22)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 30.0 if not streaks else 12.0
	pm.initial_velocity_min = vel * 0.5
	pm.initial_velocity_max = vel
	pm.gravity = gravity
	pm.scale_min = 0.6 if streaks else 1.0
	pm.scale_max = 1.2 if streaks else 1.6
	pm.particle_flag_align_y = streaks
	p.process_material = pm
	p.amount = amount
	p.lifetime = lifetime
	p.preprocess = lifetime
	if streaks:
		var q := QuadMesh.new()
		q.size = Vector2(w, h)
		q.material = mat
		p.draw_pass_1 = q
	else:
		p.draw_pass_1 = FireEffect.make_quad((w + h) * 0.5 * 2.2, mat)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# flakes fall well below the emitter over their lifetime: keep them from being culled
	p.visibility_aabb = AABB(Vector3(-45, -70, -45), Vector3(90, 90, 90))
	return p


func _apply_quality() -> void:
	var ratio := Quality.particle_ratio()
	if light_snow != null:
		light_snow.amount_ratio = ratio
	if heavy_snow != null:
		heavy_snow.amount_ratio = ratio


func set_blizzard(active: bool, wind_yaw: float = 0.0) -> void:
	_wind_yaw = wind_yaw
	if heavy_snow == null:
		return
	heavy_snow.emitting = active
	var hp := heavy_snow.process_material as ParticleProcessMaterial
	hp.gravity = Vector3(-5.0, -4.0, 0).rotated(Vector3.UP, wind_yaw)
	hp.direction = Vector3(-0.8, -1.0, 0.0).rotated(Vector3.UP, wind_yaw)
	hp.initial_velocity_min = 5.0
	hp.initial_velocity_max = 8.0
	(light_snow.process_material as ParticleProcessMaterial).gravity = Vector3(-1.5, -1.6, 0).rotated(Vector3.UP, wind_yaw) if active else Vector3(0, -1.6, 0)


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var rig := CameraRig.active()
	var target: Vector3
	if rig != null:
		target = rig.global_position
	else:
		target = cam.global_position + (-cam.global_basis.z) * 12.0
	global_position = Vector3(target.x, target.y + 6.0, target.z)
