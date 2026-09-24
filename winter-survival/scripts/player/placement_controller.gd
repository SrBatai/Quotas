class_name PlacementController
extends Node
## Owner client: ghost placement mode for the campfire (and P2 placeables). The validity check is a static
## function shared with the server (`NetWorld.request_place` revalidates with the same code).

var active: bool = false
var kind: String = ""
var recipe: Dictionary = {}
var valid: bool = false
var ghost: Node3D
var ghost_pos: Vector3 = Vector3.ZERO
var _player: Player
var _has_hit: bool = false


func _ready() -> void:
	_player = get_parent()


func begin(place_kind: String, recipe_data: Dictionary) -> void:
	cancel()
	kind = place_kind
	recipe = recipe_data
	var model_name := "campfire" if kind == "campfire" else kind
	ghost = Node3D.new()
	ghost.name = "Ghost"
	var m := Assets.spawn_model(model_name)
	ghost.add_child(m)
	get_tree().current_scene.add_child(ghost)
	ghost.global_position = _player.global_position + _player.facing() * 2.0
	active = true
	valid = false
	_has_hit = false
	_apply_material()
	Events.placement_mode.emit(true)
	Events.hover_changed.emit("Clic: colocar · Clic derecho: cancelar")


func cancel() -> void:
	if ghost != null:
		ghost.queue_free()
		ghost = null
	if active:
		active = false
		Events.placement_mode.emit(false)
		Events.hover_changed.emit("")


func _process(_delta: float) -> void:
	if not active or ghost == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var mouse := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mouse)
	var to := from + cam.project_ray_normal(mouse) * 160.0
	var q := PhysicsRayQueryParameters3D.create(from, to, 1, [_player.get_rid()])
	q.collide_with_areas = false
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	_has_hit = true
	ghost_pos = hit.position
	ghost.global_position = ghost_pos
	valid = check_position(_player, ghost_pos)
	_apply_material()


func _apply_material() -> void:
	if ghost != null:
		Assets.override_all(ghost, Assets.get_ghost_material(valid))


## Shared validation (client preview and server authority): bounds, slope, distance, shelters, blockers.
static func check_position(player: Node3D, pos: Vector3) -> bool:
	var world := player.get_tree().get_first_node_in_group("world")
	if world == null:
		return false
	var terrain: Terrain = world.terrain
	if not terrain.in_bounds(pos.x, pos.z):
		return false
	if terrain.get_normal(pos.x, pos.z).y < cos(deg_to_rad(30.0)):
		return false
	var p := player.global_position
	if Vector2(pos.x - p.x, pos.z - p.z).length() > 6.0:
		return false
	for area in player.get_tree().get_nodes_in_group("shelter"):
		var local: Vector3 = (area as Node3D).global_transform.affine_inverse() * pos
		if absf(local.x) < 3.6 and absf(local.z) < 3.4 and local.y > -1.0 and local.y < 3.5:
			return false
	var shape := SphereShape3D.new()
	shape.radius = 1.5
	var sq := PhysicsShapeQueryParameters3D.new()
	sq.shape = shape
	sq.transform = Transform3D(Basis.IDENTITY, pos + Vector3(0, 0.5, 0))
	sq.collision_mask = 1 | 64
	sq.collide_with_areas = false
	sq.exclude = [player.get_rid()]
	var hits := player.get_world_3d().direct_space_state.intersect_shape(sq, 16)
	for h in hits:
		var c: Node = h.collider
		if c is Terrain:
			continue
		return false
	return true


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event.is_action_pressed("interact_click"):
		if _has_hit:
			confirm_at(ghost_pos)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("cancel"):
		cancel()
		get_viewport().set_input_as_handled()


## Asks the server to place the object at `pos` (local pre-check first). Test hook + click path.
func confirm_at(pos: Vector3) -> bool:
	if not check_position(_player, pos):
		Events.notify.emit("No se puede colocar aquí", 2.0)
		return false
	if not Recipes.has_materials(recipe, _player.state):
		Events.notify.emit(Recipes.STATUS_MISSING, 2.0)
		cancel()
		return false
	Net.rpc_server(NetWorld.instance, &"request_place", [kind, pos, randf() * TAU])
	cancel()
	return true
