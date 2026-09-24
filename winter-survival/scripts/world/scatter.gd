class_name Scatter
extends Node3D
## Deterministic rejection-sampled placement of trees, rocks, bushes and pickups.

const TREE_SCENE := preload("res://scenes/world/tree.tscn")
const ROCK_SCENE := preload("res://scenes/world/rock.tscn")
const BUSH_SCENE := preload("res://scenes/world/berry_bush.tscn")
const PICKUP_SCENE := preload("res://scenes/world/pickup.tscn")
const STUMP_SCENE := preload("res://scenes/world/stump.tscn")

var _rng := RandomNumberGenerator.new()
var _terrain: Terrain
var _placed: Array[Vector2] = []
var _exclusions: Array = []  # [{"center": Vector2, "radius": float}]


func generate(seed_value: int, terrain: Terrain, exclusions: Array) -> void:
	_rng.seed = seed_value + 11
	_terrain = terrain
	_exclusions = exclusions
	# trees
	var pine_weights := {"pine_a": 0.5, "pine_b": 0.3, "pine_c": 0.2}
	var placed_trees := 0
	var attempts := 0
	while placed_trees < 330 and attempts < 20000:
		attempts += 1
		var p := _sample(2.6, 11.5, true, true)
		if p == Vector2.INF:
			continue
		var edge := maxf(absf(p.x), absf(p.y)) > 66.0
		if not edge and _rng.randf() < 0.28:
			continue  # thinner interior; ring stays dense
		_spawn_tree(_pick(pine_weights), p, _rng.randf_range(0.9, 1.15))
		placed_trees += 1
	for i in 40:
		var p := _sample(2.2, 11.5, true, true)
		if p != Vector2.INF:
			_spawn_tree("dead_tree", p, _rng.randf_range(0.9, 1.15))
	for i in 15:
		var p := _sample(1.5, 9.0, true, false)
		if p != Vector2.INF:
			_spawn_simple(STUMP_SCENE, p, {}, _rng.randf_range(0.9, 1.1))
	# rocks
	var rock_weights := {"rock_a": 0.5, "rock_b": 0.25, "rock_c": 0.25}
	for i in 110:
		var p := _sample(1.8, 9.0, false, false)
		if p != Vector2.INF:
			_spawn_simple(ROCK_SCENE, p, {"variant": _pick(rock_weights)}, _rng.randf_range(0.9, 1.15))
	# bushes
	for i in 40:
		var p := _sample(1.5, 9.0, true, false)
		if p != Vector2.INF:
			_spawn_simple(BUSH_SCENE, p, {}, 1.0)
	# pickups
	for i in 45:
		var p := _sample(1.0, 9.0, false, false)
		if p != Vector2.INF:
			spawn_pickup(&"madera", "firewood", p)
	for i in 30:
		var p := _sample(1.0, 9.0, false, false)
		if p != Vector2.INF:
			spawn_pickup(&"piedra", "stone", p)
	# a few near the porch so the first quest is easy
	for off in [Vector2(3.5, 8.5), Vector2(-4.0, 6.5), Vector2(6.0, 5.0), Vector2(-3.0, 11.0), Vector2(8.0, 9.0)]:
		spawn_pickup(&"madera", "firewood", off)
	for off in [Vector2(5.5, 10.5), Vector2(-6.0, 12.0), Vector2(7.5, 3.5), Vector2(-9.0, 9.0)]:
		spawn_pickup(&"piedra", "stone", off)
	# fallen logs: 4 within 20 m of the cabin, rest anywhere
	var logs := 0
	attempts = 0
	while logs < 4 and attempts < 500:
		attempts += 1
		var ang := _rng.randf_range(0.0, TAU)
		var d := _rng.randf_range(11.0, 20.0)
		var p := Vector2(cos(ang) * d, sin(ang) * d)
		if _ok(p, 1.5, 9.0, false, false):
			_spawn_tree("fallen_log", p, 1.0)
			logs += 1
	for i in 10:
		var p := _sample(1.5, 9.0, false, false)
		if p != Vector2.INF:
			_spawn_tree("fallen_log", p, 1.0)


func _pick(weights: Dictionary) -> String:
	var r := _rng.randf()
	var acc := 0.0
	for k in weights:
		acc += float(weights[k])
		if r <= acc:
			return k
	return weights.keys()[0]


func _ok(p: Vector2, spacing: float, cabin_r: float, avoid_lake: bool, allow_lake_shore: bool) -> bool:
	if absf(p.x) > Balance.BOUNDS - 1.0 or absf(p.y) > Balance.BOUNDS - 1.0:
		return false
	if p.length() < cabin_r:
		return false
	for ex in _exclusions:
		if p.distance_to(ex["center"]) < float(ex["radius"]):
			return false
	if avoid_lake and _terrain.is_lake(p.x, p.y):
		return false
	if not avoid_lake and _terrain.is_lake(p.x, p.y) and p.distance_to(_terrain.lake_center) < _terrain.lake_radius * 0.8:
		return false
	for q in _placed:
		if q.distance_squared_to(p) < spacing * spacing:
			return false
	return true


func _sample(spacing: float, cabin_r: float, avoid_lake: bool, allow_lake_shore: bool) -> Vector2:
	for i in 30:
		var p := Vector2(_rng.randf_range(-Balance.BOUNDS + 1.0, Balance.BOUNDS - 1.0), _rng.randf_range(-Balance.BOUNDS + 1.0, Balance.BOUNDS - 1.0))
		if _ok(p, spacing, cabin_r, avoid_lake, allow_lake_shore):
			return p
	return Vector2.INF


func _spawn_tree(variant: String, p: Vector2, s: float) -> void:
	var t := TREE_SCENE.instantiate()
	t.variant = variant
	add_child(t)
	t.global_position = Vector3(p.x, _terrain.get_height(p.x, p.y), p.y)
	t.rotation.y = _rng.randf_range(0.0, TAU)
	t.scale = Vector3.ONE * s
	_placed.append(p)


func _spawn_simple(scene: PackedScene, p: Vector2, props: Dictionary, s: float) -> Node3D:
	var n: Node3D = scene.instantiate()
	for k in props:
		n.set(k, props[k])
	add_child(n)
	n.global_position = Vector3(p.x, _terrain.get_height(p.x, p.y), p.y)
	n.rotation.y = _rng.randf_range(0.0, TAU)
	n.scale = Vector3.ONE * s
	_placed.append(p)
	return n


func spawn_pickup(item_id: StringName, model: String, p: Vector2, amount: int = 1) -> Node3D:
	var n: Node3D = PICKUP_SCENE.instantiate()
	n.item_id = item_id
	n.model = model
	n.amount = amount
	add_child(n)
	n.global_position = Vector3(p.x, _terrain.get_height(p.x, p.y), p.y)
	n.rotation.y = _rng.randf_range(0.0, TAU)
	return n


func spawn_random_pickup(item_id: StringName, model: String) -> void:
	var p := _sample(1.0, 9.0, false, false)
	if p != Vector2.INF:
		spawn_pickup(item_id, model, p)


func count_pickups(item_id: StringName) -> int:
	var n := 0
	for c in get_tree().get_nodes_in_group("pickup"):
		if c.get("item_id") == item_id:
			n += 1
	return n
