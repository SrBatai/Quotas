class_name Cutaway
extends Node
## Hides the roof, chimney and the camera-facing walls while the player is inside.

const WALL_NORMALS := {
	"WallFront": Vector3(0, 0, -1), "WallBack": Vector3(0, 0, 1),
	"WallLeft": Vector3(-1, 0, 0), "WallRight": Vector3(1, 0, 0),
}

var active: bool = false
var _cabin: Node3D
var _parts: Dictionary = {}


func setup(cabin: Node3D, model: Node3D) -> void:
	_cabin = cabin
	for n in ["Roof", "Chimney", "WallFront", "WallBack", "WallLeft", "WallRight"]:
		var node := model.find_child(n, true, false)
		if node != null:
			_parts[n] = node
	Events.camera_yaw_changed.connect(_on_yaw_changed)


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
			var normal: Vector3 = WALL_NORMALS[n]
			node.visible = normal.dot(local_dir) <= 0.15


func is_wall_hidden(wall: String) -> bool:
	return _parts.has(wall) and not (_parts[wall] as Node3D).visible
