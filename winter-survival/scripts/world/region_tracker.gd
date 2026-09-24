extends Node
## Client: polls the local player's XZ every 0.5 s and emits Events.region_changed on change.

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
	var p: Node3D = GameFlow.local_player()
	if p == null:
		return
	var region_name := Regions.name_at(p.global_position.x, p.global_position.z)
	if region_name != _current:
		_current = region_name
		Events.region_changed.emit(region_name)
