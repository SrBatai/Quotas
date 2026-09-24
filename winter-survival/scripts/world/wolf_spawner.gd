class_name WolfSpawner
extends Node
## Spawns wolves at night (GDD §12) and sends them away at dawn.

const WOLF_SCENE := preload("res://scenes/actors/wolf.tscn")

var enabled: bool = true
var _to_spawn: int = 0
var _timer: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	Events.night_started.connect(_on_night_started)
	Events.day_started.connect(_on_day_started)


func _on_night_started(day: int) -> void:
	if not enabled:
		return
	var count: int = Balance.WOLVES_PER_NIGHT[mini(day - 1, Balance.WOLVES_PER_NIGHT.size() - 1)]
	var now := int(ceil(float(count) / 2.0))
	for i in now:
		spawn_wolf(_random_spawn_pos())
	_to_spawn = count - now
	_timer = 60.0
	Events.notify.emit("Los lobos merodean…", 4.0)
	AudioManager.play(&"wolf_howl")
	AudioManager.set_wind(0.5)


func _on_day_started(_day: int) -> void:
	_to_spawn = 0
	for w in get_tree().get_nodes_in_group("wolves"):
		if w.has_method("leave"):
			w.leave()
	AudioManager.set_wind(0.2)


func _process(delta: float) -> void:
	if _to_spawn <= 0 or not GameState.is_night:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = 60.0
		_to_spawn -= 1
		spawn_wolf(_random_spawn_pos())


func _world() -> Node:
	return get_parent()


func _random_spawn_pos() -> Vector3:
	var world := _world()
	var terrain: Terrain = world.get_node("Terrain")
	var players := get_tree().get_nodes_in_group("player")
	var origin := Vector3.ZERO
	if not players.is_empty():
		origin = (players[0] as Node3D).global_position
	for i in 40:
		var ang := _rng.randf_range(0.0, TAU)
		var d := _rng.randf_range(Balance.WOLF_SPAWN_MIN, Balance.WOLF_SPAWN_MAX)
		var x := origin.x + cos(ang) * d
		var z := origin.z + sin(ang) * d
		if not terrain.in_bounds(x, z) or terrain.is_lake(x, z):
			continue
		if Vector2(x, z).length() < 15.0:
			continue
		return Vector3(x, terrain.get_height(x, z), z)
	var p := terrain.random_point(_rng, 30.0)
	return p


func spawn_wolf(pos: Vector3) -> Node:
	var wolf := WOLF_SCENE.instantiate()
	var actors := _world().get_node("Actors")
	actors.add_child(wolf)
	wolf.global_position = pos + Vector3(0, 0.2, 0)
	Events.wolf_spawned.emit(wolf)
	return wolf
