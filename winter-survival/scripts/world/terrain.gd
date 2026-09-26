class_name Terrain
extends Node3D
## World ground queries (M3). The terrain itself lives in the streamed chunks (WorldChunk: HeightMapShape3D +
## smooth indexed mesh with baked AO, G1 look); this node answers height / normal / lake / bounds questions for
## any point — from the loaded chunk's samples when there is one, else from the pure HeightFunction (same
## values: the world height is the bilinear of the 1 m samples) — and forwards AO re-bakes to the chunks.
## Same API as the slice's terrain.gd so gameplay code (spawners, placement, footprints, drops) is unchanged.

var hf: HeightFunction
var streamer: WorldStreamer
## Slice lake of the clearing (the frozen pond by the A-frame).
var lake_center: Vector2 = HeightFunction.SMALL_LAKE_CENTER
var lake_radius: float = HeightFunction.SMALL_LAKE_RADIUS
var lake_level: float = 0.0
## True when a render mesh is built (any DisplayServer that is not headless).
var visual: bool = true


func _ready() -> void:
	add_to_group("terrain_facade")
	visual = DisplayServer.get_name() != "headless"


func setup(p_hf: HeightFunction, p_streamer: WorldStreamer) -> void:
	hf = p_hf
	streamer = p_streamer
	lake_level = hf.small_lake_level


func is_ready() -> bool:
	return hf != null


func get_height(x: float, z: float) -> float:
	if hf == null:
		return 0.0
	if streamer != null:
		var c := streamer.chunk_at(x, z)
		if c != null and c.data != null and not c.data.heights.is_empty():
			return c.height_at(x, z)
	return hf.height_at(x, z)


func get_normal(x: float, z: float) -> Vector3:
	var e := 0.5
	var hl := get_height(x - e, z)
	var hr := get_height(x + e, z)
	var hd := get_height(x, z - e)
	var hu := get_height(x, z + e)
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()


## The clearing pond or the Lago de las Ánimas.
func is_lake(x: float, z: float) -> bool:
	if Vector2(x, z).distance_to(lake_center) < lake_radius:
		return true
	return hf != null and hf.is_big_lake(x, z)


func in_bounds(x: float, z: float) -> bool:
	return WorldConst.in_playable(x, z)


## True when the collider under (x, z) is loaded (bodies must not simulate over a hole).
func has_collision_at(x: float, z: float) -> bool:
	return streamer != null and streamer.has_collision_at(x, z)


## Random walkable point within [min_d, max_d] of `origin`, inside loaded chunks, off lakes and the porch area.
func random_point_near(rng: RandomNumberGenerator, origin: Vector3, min_d: float, max_d: float, min_from_origin: float = 0.0) -> Vector3:
	for i in 48:
		var ang := rng.randf_range(0.0, TAU)
		var d := rng.randf_range(min_d, max_d)
		var x := origin.x + cos(ang) * d
		var z := origin.z + sin(ang) * d
		if not in_bounds(x, z) or is_lake(x, z) or not has_collision_at(x, z):
			continue
		if Vector2(x, z).length() < min_from_origin:
			continue
		return Vector3(x, get_height(x, z), z)
	return Vector3.INF


## Slice API: a random point of the clearing (±78 m) away from the cabin.
func random_point(rng: RandomNumberGenerator, min_dist_from_origin: float) -> Vector3:
	for i in 64:
		var x := rng.randf_range(-76.0, 76.0)
		var z := rng.randf_range(-76.0, 76.0)
		if Vector2(x, z).length() < min_dist_from_origin or is_lake(x, z):
			continue
		return Vector3(x, get_height(x, z), z)
	return Vector3(0, get_height(0, 0), 0)


## AO re-bake of one occluder (felled tree → stump; strength 0 = removed) in every chunk it reaches.
func update_occluder(id: String, r: float, strength: float) -> void:
	if streamer != null:
		streamer.update_occluder(id, r, strength)


## Baked AO at a world position (1 = open; 1 without a loaded render mesh).
func ao_at(x: float, z: float) -> float:
	if streamer == null:
		return 1.0
	var c := streamer.chunk_at(x, z)
	return c.ao_at(x, z) if c != null else 1.0


func surface_at(x: float, z: float) -> Color:
	return hf.surface_at(x, z) if hf != null else Color(0, 0, 0, 0)
