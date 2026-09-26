extends Node
## Keeps DEER_COUNT deer wandering in the forest around the players (M3: they spawn 45–90 m from a player on
## loaded ground and are removed when no player is within DESPAWN_DIST, so the herd follows the players).

const DEER_SCENE := preload("res://scenes/actors/deer.tscn")
const DESPAWN_DIST := 230.0

var enabled: bool = true
var _timer: float = 120.0
var _check: float = 10.0
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
	_check -= delta
	if _check <= 0.0:
		_check = 10.0
		_despawn_far()
	_timer -= delta
	if _timer <= 0.0:
		_timer = 120.0
		if get_tree().get_nodes_in_group("deer").size() < Balance.DEER_COUNT:
			_spawn()


func _players() -> Array:
	return get_tree().get_nodes_in_group("player")


func _despawn_far() -> void:
	var players := _players()
	if players.is_empty():
		return
	for d in get_tree().get_nodes_in_group("deer"):
		var near := false
		for p in players:
			if (p as Node3D).global_position.distance_to((d as Node3D).global_position) < DESPAWN_DIST:
				near = true
		if not near:
			d.queue_free()


func _spawn() -> void:
	var world := get_parent() as World
	var terrain: Terrain = world.terrain
	var pos := Vector3.INF
	var players := _players()
	if not players.is_empty():
		var origin: Vector3 = (players[_rng.randi() % players.size()] as Node3D).global_position
		pos = terrain.random_point_near(_rng, origin, 45.0, 90.0, 45.0)
	if pos == Vector3.INF:
		pos = terrain.random_point(_rng, 45.0)
	var deer: Deer = DEER_SCENE.instantiate()
	_counter += 1
	deer.name = "deer_%d" % _counter
	deer.net_position = pos + Vector3(0, 0.2, 0)
	get_parent().get_node("Actors").add_child(deer, true)
