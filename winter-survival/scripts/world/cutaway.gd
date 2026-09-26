class_name Cutaway
extends Node
## Hides the roof, chimney and the camera-facing walls while the player is inside.
## Wall normals come from each wall mesh's position in the model (front = +Z in v2, ASSET_SPEC v2 §17);
## the table is only the fallback for placeholders without geometry.

const WALL_NORMALS := {
	"WallFront": Vector3(0, 0, 1), "WallBack": Vector3(0, 0, -1),
	"WallLeft": Vector3(1, 0, 0), "WallRight": Vector3(-1, 0, 0),
}

var active: bool = false
var _cabin: Node3D
var _parts: Dictionary = {}
var _normals: Dictionary = {}


func setup(cabin: Node3D, model: Node3D) -> void:
	_cabin = cabin
	for n in ["Roof", "Chimney", "WallFront", "WallBack", "WallLeft", "WallRight"]:
		var node := model.find_child(n, true, false)
		if node != null:
			_parts[n] = node
			if WALL_NORMALS.has(n):
				_normals[n] = _wall_normal(n, node, model)
	Events.camera_yaw_changed.connect(_on_yaw_changed)


## Outward normal of a wall from where its mesh sits in the model (dominant horizontal axis of its AABB centre).
static func _wall_normal(wall: String, node: Node3D, model: Node3D) -> Vector3:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mi := node as MeshInstance3D
		var c := mi.get_aabb().get_center()
		# to model space
		var n: Node3D = mi
		while n != null and n != model:
			c = n.transform * c
			n = n.get_parent() as Node3D
		if absf(c.x) > 0.5 or absf(c.z) > 0.5:
			if absf(c.z) >= absf(c.x):
				return Vector3(0, 0, signf(c.z))
			return Vector3(signf(c.x), 0, 0)
	return WALL_NORMALS[wall]


func wall_normal(wall: String) -> Vector3:
	return _normals.get(wall, WALL_NORMALS.get(wall, Vector3.ZERO))


func set_active(value: bool) -> void:
	active = value
	if value:
		_apply()
	else:
		for n in _parts:
			(_parts[n] as Node3D).visible = true


func _on_yaw_changed(_yaw: float) -> void:
	if active:
		_apply()


func _apply() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or _cabin == null:
		return
	var to_cam := cam.global_position - _cabin.global_position
	to_cam.y = 0.0
	if to_cam.length() < 0.01:
		return
	to_cam = to_cam.normalized()
	var local_dir: Vector3 = _cabin.global_transform.basis.inverse() * to_cam
	for n in _parts:
		var node := _parts[n] as Node3D
		if n == "Roof" or n == "Chimney":
			node.visible = false
		else:
			var normal: Vector3 = wall_normal(n)
			node.visible = normal.dot(local_dir) <= 0.15


func is_wall_hidden(wall: String) -> bool:
	return _parts.has(wall) and not (_parts[wall] as Node3D).visible
