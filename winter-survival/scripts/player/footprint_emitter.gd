extends Node
## Stamps a footprint every FOOTPRINT_STEP meters of ground travel (client, every visible player).

var _player: Player
var _visual: Node3D
var _acc: float = 0.0
var _last_pos: Vector3 = Vector3.INF
var _left: bool = true


func setup(player: Player, visual: Node3D) -> void:
	_player = player
	_visual = visual


func _physics_process(_delta: float) -> void:
	if _player == null or (_player.is_local and not _player.is_on_floor()):
		_last_pos = _player.global_position if _player != null else Vector3.INF
		return
	var p := _player.global_position
	if _last_pos == Vector3.INF:
		_last_pos = p
		return
	var d := Vector2(p.x - _last_pos.x, p.z - _last_pos.z).length()
	_last_pos = p
	if d > 2.0:
		return  # teleport
	_acc += d
	if _acc >= Balance.FOOTPRINT_STEP:
		_acc = 0.0
		var world := get_tree().get_first_node_in_group("world")
		if world != null and world.get("footprints") != null:
			var yaw: float = _visual.rotation.y if _visual != null else 0.0
			var ground := p
			ground.y = world.get_height(p.x, p.z)
			if absf(ground.y - p.y) > 1.0:
				ground.y = p.y - 0.05  # on a porch/floor
			world.footprints.stamp(ground, yaw, _left)
			_left = not _left
		AudioManager.play(&"footstep_snow", p)
