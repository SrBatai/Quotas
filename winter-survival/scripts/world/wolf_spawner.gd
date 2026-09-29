class_name WolfSpawner
extends Node
## Server: spawns wolves at night (GDD §12) around a random player and sends them away at dawn. The
## ActorSpawner replicates the bodies to the clients.

const WOLF_SCENE := preload("res://scenes/actors/wolf.tscn")

var enabled: bool = true
var _to_spawn: int = 0
var _timer: float = 0.0
var _counter: int = 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	Events.night_started.connect(_on_night_started)
	Events.day_started.connect(_on_day_started)


func _on_night_started(day: int) -> void:
	if not enabled or not Net.is_server:
		return
	var count: int = Balance.WOLVES_PER_NIGHT[mini(day - 1, Balance.WOLVES_PER_NIGHT.size() - 1)]
	var now := int(ceil(float(count) / 2.0))
	for i in now:
		spawn_wolf(_random_spawn_pos())
	_to_spawn = count - now
	_timer = 60.0
	WorldState.instance.notify_all("Los lobos merodean…", 4.0)
	AudioManager.play(&"wolf_howl")
	AudioManager.set_wind(0.5)


func _on_day_started(_day: int) -> void:
	if not Net.is_server:
		return
	_to_spawn = 0
	for w in get_tree().get_nodes_in_group("wolves"):
		if w.has_method("leave"):
			w.leave()
	AudioManager.set_wind(0.2)


func _process(delta: float) -> void:
	if not enabled or _to_spawn <= 0 or not WorldState.is_night_now():
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = 60.0
		_to_spawn -= 1
		spawn_wolf(_random_spawn_pos())


func _world() -> Node:
	return get_parent()


func _random_spawn_pos() -> Vector3:
	var world := _world() as World
	var terrain: Terrain = world.terrain
	var players := get_tree().get_nodes_in_group("player")
	var origin := Vector3.ZERO
	if not players.is_empty():
		origin = (players[_rng.randi() % players.size()] as Node3D).global_position
	# M3: around a player, on loaded ground, off the lakes, never inside the clearing's 15 m around the cabin
	var p := terrain.random_point_near(_rng, origin, Balance.WOLF_SPAWN_MIN, Balance.WOLF_SPAWN_MAX, 15.0)
	if p != Vector3.INF:
		return p
	return terrain.random_point(_rng, 30.0)


func spawn_wolf(pos: Vector3) -> Node:
	var wolf: Wolf = WOLF_SCENE.instantiate()
	_counter += 1
	wolf.name = "wolf_%d" % _counter
	wolf.net_position = pos + Vector3(0, 0.2, 0)
	var actors := _world().get_node("Actors")
	actors.add_child(wolf, true)
	Events.wolf_spawned.emit(wolf)
	return wolf
