extends Node
## Keeps DEER_COUNT deer wandering in the deep forest.

const DEER_SCENE := preload("res://scenes/actors/deer.tscn")

var enabled: bool = true
var _timer: float = 120.0
var _counter: int = 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = Balance.TERRAIN_SEED + 5
	Events.world_ready.connect(_on_world_ready)


func _on_world_ready() -> void:
	if not enabled:
		return
	for i in Balance.DEER_COUNT:
		_spawn()


func _process(delta: float) -> void:
	if not enabled:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = 120.0
		if get_tree().get_nodes_in_group("deer").size() < Balance.DEER_COUNT:
			_spawn()


func _spawn() -> void:
	var terrain: Terrain = get_parent().get_node("Terrain")
	var pos := terrain.random_point(_rng, 45.0)
	var deer: Deer = DEER_SCENE.instantiate()
	_counter += 1
	deer.name = "deer_%d" % _counter
	deer.net_position = pos + Vector3(0, 0.2, 0)
	get_parent().get_node("Actors").add_child(deer, true)
