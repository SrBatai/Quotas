class_name Respawner
extends Node
## Server only (PLAN M2): every dawn up to RESPAWN_FIREWOOD_PER_DAY firewood and RESPAWN_STONE_PER_DAY stones
## reappear in the hunter's clearing as replicated drops (DropSpawner), capped at MAX_FIREWOOD / MAX_STONES on
## the clearing's ground (M3: the rest of the world has its own seeded pickups per chunk).

var enabled: bool = false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = Balance.TERRAIN_SEED + 29
	Events.day_started.connect(_on_day_started)


func count_pickups(item_id: StringName) -> int:
	var n := 0
	for c in get_tree().get_nodes_in_group("pickup"):
		var p := (c as Node3D).global_position
		if c.get("item_id") == item_id and absf(p.x) < ScatterGen.LEGACY_BOUNDS and absf(p.z) < ScatterGen.LEGACY_BOUNDS:
			n += 1
	return n


func _on_day_started(_day: int) -> void:
	if not enabled or not Net.is_server:
		return
	var world := get_parent() as World
	if world == null:
		return
	var wood_n := mini(Balance.RESPAWN_FIREWOOD_PER_DAY, Balance.MAX_FIREWOOD - count_pickups(&"madera"))
	var stone_n := mini(Balance.RESPAWN_STONE_PER_DAY, Balance.MAX_STONES - count_pickups(&"piedra"))
	for i in maxi(wood_n, 0):
		_spawn(world, &"madera", "firewood")
	for i in maxi(stone_n, 0):
		_spawn(world, &"piedra", "stone")
	print("[EVT] dawn respawn: +%d firewood, +%d stones" % [maxi(wood_n, 0), maxi(stone_n, 0)])


func _spawn(world: World, item: StringName, model: String) -> void:
	var p := ScatterGen.clearing_random_point(_rng)
	if p == Vector2.INF:
		return
	world.spawn_drop(item, model, Vector3(p.x, world.get_height(p.x, p.y), p.y), 1)
