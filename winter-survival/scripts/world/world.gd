class_name World
extends Node3D
## Builds the level: terrain → pads → fixed props → scatter. Emits Events.world_ready. Same scene on the server
## and the client (deterministic from the seed); the server strips lights / sky / particles / footprints and the
## client disables the spawners and the weather scheduler (decisions are the server's).

@export var decorative_only: bool = false
@export var world_seed: int = 0

@onready var terrain: Terrain = $Terrain
@onready var cabin: Cabin = $Cabin
@onready var actors: Node3D = $Actors
@onready var footprints: Footprints = $Footprints

var is_ready: bool = false
var _menu_camera: Camera3D


func _ready() -> void:
	add_to_group("world")
	var s := world_seed if world_seed != 0 else Balance.TERRAIN_SEED
	if not decorative_only and Net.is_dedicated:
		s = int(Net.cfg_get("world", "seed", s))
	if not decorative_only and WorldState.instance != null and Net.is_client:
		s = WorldState.instance.world_seed if WorldState.instance.world_seed != 0 else s
	var aframe := Regions.AFRAME_POS
	var truck := Regions.TRUCK_POS
	var pads := [
		{"center": Vector2.ZERO, "radius": 14.0},
		{"center": aframe, "radius": 8.0},
		{"center": truck, "radius": 4.0},
	]
	terrain.generate(s, pads)
	_build_lake()
	_place_props(aframe, truck)
	var exclusions := [
		{"center": aframe, "radius": 8.0},
		{"center": truck, "radius": 4.5},
		{"center": Regions.SIGNPOST_POS, "radius": 1.5},
	]
	$Scatter.generate(s, terrain, exclusions)
	var server_side := Net.is_server and not decorative_only
	$WolfSpawner.enabled = server_side
	$DeerSpawner.enabled = server_side
	$Respawner.enabled = server_side
	$Weather.scheduler_enabled = server_side
	$RegionTracker.enabled = Net.has_client and not decorative_only
	if decorative_only:
		_setup_menu_camera()
	elif not Net.has_client:
		# dedicated server: nothing to render (ARQ v2 §1.5)
		for n in ["Sun", "Moon", "Env", "DayNight", "Snowfall", "Footprints"]:
			var node := get_node_or_null(n)
			if node != null:
				remove_child(node)
				node.queue_free()
		footprints = null
	call_deferred("_emit_ready")


func _emit_ready() -> void:
	is_ready = true
	Events.world_ready.emit()


func get_height(x: float, z: float) -> float:
	return terrain.get_height(x, z)


func get_spawn_point() -> Vector3:
	return cabin.get_spawn_point()


func get_spawn_yaw() -> float:
	return cabin.get_spawn_yaw()


func region_at(x: float, z: float) -> String:
	return Regions.name_at(x, z)


# ------------------------------------------------------------------ replicated runtime objects (server calls)
## Server: a ground item that did not exist in the seeded world (wolf/deer drops, crafting overflow, dawn respawns).
func spawn_drop(item_id: StringName, model: String, pos: Vector3, amount: int = 1) -> Node3D:
	if not Net.is_server or DropSpawner.instance == null:
		return null
	return DropSpawner.instance.spawn_drop(item_id, model, pos, amount)


## Server: a placed structure (campfire; tent/box in P2).
func spawn_placed(kind: String, pos: Vector3, yaw: float) -> Node3D:
	if not Net.is_server or StructureSpawner.instance == null:
		return null
	return StructureSpawner.instance.spawn_structure(kind, pos, yaw)


func _build_lake() -> void:
	var lake := $Lake as MeshInstance3D
	var disc := CylinderMesh.new()
	disc.top_radius = terrain.lake_radius * 0.78
	disc.bottom_radius = terrain.lake_radius * 0.78
	disc.height = 0.06
	disc.radial_segments = 24
	disc.rings = 0
	disc.material = Assets.material("ice")
	lake.mesh = disc
	lake.position = Vector3(terrain.lake_center.x, terrain.lake_level + 0.02, terrain.lake_center.y)
	lake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _place_props(aframe: Vector2, truck: Vector2) -> void:
	var h0 := terrain.get_height(0, 0)
	# v2 models face +Z (Vector3.MODEL_FRONT): the cabin's porch faces the camera with no rotation
	cabin.position = Vector3(0, h0, 0)
	cabin.rotation_degrees.y = 0.0
	var af := $AFrame as Node3D
	af.position = Vector3(aframe.x, terrain.get_height(aframe.x, aframe.y), aframe.y)
	var to_lake := terrain.lake_center - aframe
	af.rotation.y = atan2(to_lake.x, to_lake.y)  # +Z (front) toward the lake
	var tr := $Truck as Node3D
	tr.position = Vector3(truck.x, terrain.get_height(truck.x, truck.y), truck.y)
	tr.rotation_degrees.y = -25.0  # hood (+Z) points where the slice's 155° put it
	var sp := $Signpost as Node3D
	var spos := Regions.SIGNPOST_POS
	sp.position = Vector3(spos.x, terrain.get_height(spos.x, spos.y), spos.y)
	if sp.has_method("setup"):
		sp.setup(af.global_position, Vector3(terrain.lake_center.x, 0, terrain.lake_center.y))
	# fences: 6 segments behind/left of the house, 4 by the A-frame (screen-horizontal rows)
	var fence_scene: PackedScene = preload("res://scenes/world/fence.tscn")
	var right := Vector2(0.82, -0.57)
	var row_c := Vector2(-8.0, -11.5)
	for i in 6:
		var p := row_c + right * (float(i) - 2.5) * 2.0
		_add_fence(fence_scene, p, 35.0)
	var row2 := aframe + Vector2(-0.57, -0.82) * 6.0
	for i in 4:
		var p := row2 + right * (float(i) - 1.5) * 2.0
		_add_fence(fence_scene, p, 35.0)


func _add_fence(scene: PackedScene, p: Vector2, yaw_deg: float) -> void:
	var f: Node3D = scene.instantiate()
	$Fences.add_child(f)
	f.global_position = Vector3(p.x, terrain.get_height(p.x, p.y), p.y)
	f.rotation_degrees.y = yaw_deg


func _setup_menu_camera() -> void:
	_menu_camera = Camera3D.new()
	_menu_camera.name = "MenuCamera"
	_menu_camera.fov = 34.0
	add_child(_menu_camera)
	var focus := Vector3(-3.0, terrain.get_height(0, 0) + 1.0, 1.0)
	var offset := Vector3(0.54, 0.62, 0.54).normalized() * 30.0
	_menu_camera.global_position = focus + offset
	_menu_camera.look_at(focus, Vector3.UP)
	_menu_camera.current = true
