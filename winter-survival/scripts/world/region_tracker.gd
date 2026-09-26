extends Node
## Client: region banner driver (M3: chunk data). When the local player enters another chunk the chunk's region
## (PoiRegistry via Regions.chunk_name) is looked up; inside the clearing the slice's small zones are polled
## every 0.5 s as before. Emits Events.region_changed on change.

var _current: String = ""
var _timer: float = 0.0
var _chunk: int = -1
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
	var k := WorldConst.key_of(p.global_position)
	var in_clearing := absf(p.global_position.x) < 96.0 and absf(p.global_position.z) < 96.0
	if k == _chunk and not in_clearing:
		return
	_chunk = k
	var region_name := Regions.name_at(p.global_position.x, p.global_position.z)
	if region_name != _current:
		_current = region_name
		Events.region_changed.emit(region_name)
