extends Node
## Polls the player's XZ every 0.5 s and emits Events.region_changed on change.

var _current: String = ""
var _timer: float = 0.0
var enabled: bool = true


func _process(delta: float) -> void:
	if not enabled:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.5
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var p := players[0] as Node3D
	var region_name := Regions.name_at(p.global_position.x, p.global_position.z)
	if region_name != _current:
		_current = region_name
		Events.region_changed.emit(region_name)
