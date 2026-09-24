class_name Footprints
extends Node3D
## Pool of footprint meshes stamped by the player; each fades over FOOTPRINT_LIFETIME.

var _pool: Array[MeshInstance3D] = []
var _ages: Array[float] = []
var _next: int = 0
var _mesh: CylinderMesh


func _ready() -> void:
	_mesh = CylinderMesh.new()
	_mesh.top_radius = 0.16
	_mesh.bottom_radius = 0.12
	_mesh.height = 0.02
	_mesh.radial_segments = 8
	_mesh.rings = 0
	for i in Balance.FOOTPRINT_POOL:
		var mi := MeshInstance3D.new()
		mi.mesh = _mesh
		var m := StandardMaterial3D.new()
		m.albedo_color = Color("#B9CBE3", 0.85)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 1.0
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_pool.append(mi)
		_ages.append(-1.0)


func stamp(pos: Vector3, yaw: float, left: bool) -> void:
	var mi := _pool[_next]
	_ages[_next] = 0.0
	_next = (_next + 1) % _pool.size()
	# character right = -X of a +Z-facing model, yawed
	var side := Vector3(-cos(yaw), 0, sin(yaw)) * (-0.15 if left else 0.15)
	mi.global_position = pos + side + Vector3(0, 0.012, 0)
	mi.rotation = Vector3(0, yaw, 0)
	mi.scale = Vector3(0.9, 1.0, 1.3)
	mi.visible = true
	(mi.material_override as StandardMaterial3D).albedo_color.a = 0.85


func _process(delta: float) -> void:
	for i in _pool.size():
		if _ages[i] < 0.0:
			continue
		_ages[i] += delta
		var t := _ages[i] / Balance.FOOTPRINT_LIFETIME
		if t >= 1.0:
			_ages[i] = -1.0
			_pool[i].visible = false
			continue
		var m := _pool[i].material_override as StandardMaterial3D
		m.albedo_color.a = 0.85 * (1.0 - t * t)
