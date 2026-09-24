class_name Snowfall
extends Node3D
## Constant light snow + heavy wind-driven emitter during blizzards. Follows the active camera.

var light_snow: CPUParticles3D
var heavy_snow: CPUParticles3D
var _wind_yaw: float = 0.0


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("#F1F5FA", 0.95)
	mat.albedo_texture = FireEffect.soft_dot_texture()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.disable_receive_shadows = true
	light_snow = _make(500, 8.0, Vector3(0, -1.6, 0), 0.3, 0.06, 0.10, mat)
	light_snow.name = "Light"
	add_child(light_snow)
	heavy_snow = _make(900, 5.0, Vector3(-4.0, -3.0, 0), 1.0, 0.05, 0.09, mat)
	heavy_snow.name = "Heavy"
	heavy_snow.emitting = false
	add_child(heavy_snow)


func _make(amount: int, lifetime: float, gravity: Vector3, vel: float, smin: float, smax: float, mat: Material) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.preprocess = lifetime
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(22, 7, 22)
	p.direction = Vector3(0, -1, 0)
	p.spread = 30.0
	p.initial_velocity_min = vel * 0.5
	p.initial_velocity_max = vel
	p.gravity = gravity
	p.scale_amount_min = 1.0
	p.scale_amount_max = 1.6
	p.mesh = FireEffect.make_quad((smin + smax) * 0.5 * 2.2, mat)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


func set_blizzard(active: bool, wind_yaw: float = 0.0) -> void:
	_wind_yaw = wind_yaw
	if heavy_snow == null:
		return
	heavy_snow.emitting = active
	heavy_snow.gravity = Vector3(-4.0, -3.0, 0).rotated(Vector3.UP, wind_yaw)
	light_snow.gravity = Vector3(-1.5, -1.6, 0).rotated(Vector3.UP, wind_yaw) if active else Vector3(0, -1.6, 0)


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
