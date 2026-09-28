class_name CutawayManager
extends Node
## Client cutaway of every enterable building (M6a, ARQ v2 §9.3 / §9.9; replaces PoiCutaway in the world). One node
## per client world (created on the first attach / register, child of World.instance or the current scene): the
## buildings' BuildingCutaway components (scripts/world/city/building_cutaway.gd, `managed = true`) sit in a 32 m
## registry grid; every POLL seconds the manager takes the LOCAL player's feet, finds the building whose footprint and
## storey band contain them (floor_at) and tells it the storey (apply_floor): roof and storeys above go
## SHADOWS_ONLY (HideMode.SHADOW: they keep casting, so the room stays in the shade of its roof), the camera-facing
## facades of the storey become their `_Stub`; every other building is shown whole. Buildings further than RADIUS
## from the player are never evaluated. The camera yaw re-applies the facing rule (BuildingCutaway listens to
## Events.camera_yaw_changed), and so does the camera ending up on another side of the building (a teleport). Exposes `inside` / `inside_floor` / `inside_building` and the inside_changed signal;
## entering / leaving also emits Events.shelter_changed like the clearing cabin.
## The kit buildings (KitBuilding) are CityBuildings too: the «corte urbano» shader (CityCut) cuts their structure
## from the street; this manager only drives the cut groups (the M3 forest POIs cabin_small / lookout_tower now go
## through it as well, in shadow-preserving mode; PoiCutaway keeps the old `visible = false` mode for the W0 check).

signal inside_changed(inside: bool, building: Node3D, floor: int)

const RADIUS := 30.0
const POLL := 0.1
const GRID_CELL := 32.0

static var instance: CutawayManager

## True while the local player stands inside a registered building (inside_floor = its storey, -1 outside).
var inside: bool = false
var inside_floor: int = -1
var inside_cutaway: BuildingCutaway
## Tests / benches: follow this node instead of GameFlow.local_player().
var player_override: Node3D
## Tests / stats.
var polls: int = 0
var _cutaways: Array[BuildingCutaway] = []
var _grid: Dictionary = {}        # Vector2i -> Array[BuildingCutaway]
var _cells_of: Dictionary = {}    # BuildingCutaway -> Array[Vector2i]
var _t: float = 0.0
var _cam_side := Vector2i(9, 9)   # side of the inside building the camera was on when its storey was applied


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


## The world's manager, created on demand (clients only: nothing calls it on a dedicated server).
static func ensure(context: Node) -> CutawayManager:
	if instance != null and is_instance_valid(instance) and not instance.is_queued_for_deletion():
		return instance
	var host: Node = World.instance
	if host == null and context != null and context.is_inside_tree():
		host = context.get_tree().current_scene
		if host == null:
			host = context.get_tree().root         # tools / tests running a SceneTree script
	if host == null:
		return null
	var m := CutawayManager.new()
	m.name = "CutawayManager"
	instance = m
	host.add_child.call_deferred(m)             # never while the host is still setting up its children
	return m


## Cutaway of a building / POI model with the v2 cut-group structure (ASSET_SPEC v2 §8.4), managed, shadow mode:
## what world_chunk uses for the forest POIs (was PoiCutaway.attach). Returns null without cut groups.
static func attach(host: Node3D, model: Node3D) -> BuildingCutaway:
	if not BuildingCutaway.has_cut_groups(model):
		return null
	var cut := BuildingCutaway.new()
	cut.name = "Cutaway"
	cut.hide_mode = BuildingCutaway.HideMode.SHADOW
	host.add_child(cut)
	cut.setup(model)
	register(cut)
	return cut


## Puts an existing BuildingCutaway (e.g. CityBuilding.cutaway of a kit building) under the manager.
static func register(cut: BuildingCutaway) -> void:
	if cut == null:
		return
	var m := ensure(cut)
	if m == null:
		return
	cut.managed = true
	if cut.is_inside_tree():
		m._add(cut)
	else:
		cut.tree_entered.connect(func() -> void: m._add(cut), CONNECT_ONE_SHOT)


func _add(cut: BuildingCutaway) -> void:
	if _cutaways.has(cut) or not is_instance_valid(cut):
		return
	var model := cut.model_root()
	if model == null or not model.is_inside_tree():
		return
	_cutaways.append(cut)
	var foot := cut.footprint_aabb()
	var xf := model.global_transform
	var c := xf * foot.get_center()
	var r := Vector2(foot.size.x, foot.size.z).length() * 0.5 + 1.0
	var cells: Array = []
	for cx in range(floori((c.x - r) / GRID_CELL), floori((c.x + r) / GRID_CELL) + 1):
		for cz in range(floori((c.z - r) / GRID_CELL), floori((c.z + r) / GRID_CELL) + 1):
			var key := Vector2i(cx, cz)
			if not _grid.has(key):
				_grid[key] = []
			(_grid[key] as Array).append(cut)
			cells.append(key)
	_cells_of[cut] = cells
	cut.tree_exiting.connect(func() -> void: _remove(cut), CONNECT_ONE_SHOT)


func _remove(cut: BuildingCutaway) -> void:
	_cutaways.erase(cut)
	for key in _cells_of.get(cut, []):
		var list: Array = _grid.get(key, [])
		list.erase(cut)
		if list.is_empty():
			_grid.erase(key)
	_cells_of.erase(cut)
	if cut == inside_cutaway:
		_set_inside(null, -1)


func count() -> int:
	return _cutaways.size()


func _player() -> Node3D:
	if player_override != null:
		return player_override if is_instance_valid(player_override) and player_override.is_inside_tree() else null
	var lp := GameFlow.local_player() as Node3D
	return lp if lp != null and lp.is_inside_tree() else null


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = POLL
	update()


## One poll (tests call it directly): the building containing the local player's feet gets its storey, the one it
## left goes back to whole.
func update() -> void:
	polls += 1
	var pl := _player()
	var hit: BuildingCutaway = null
	var fl := -1
	if pl != null:
		var p := pl.global_position
		for c in _grid.get(Vector2i(floori(p.x / GRID_CELL), floori(p.z / GRID_CELL)), []):
			var cut := c as BuildingCutaway
			if not is_instance_valid(cut):
				continue
			var m := cut.model_root()
			if m == null or m.global_position.distance_to(p) > RADIUS:
				continue
			var k := cut.floor_at(p)
			if k >= 0:
				hit = cut
				fl = k
				break
	_set_inside(hit, fl)
	# the facing rule needs the camera where it is now: after a teleport / respawn inside (or any camera move that
	# puts it on another side of the building) the storey is applied again (camera_yaw_changed covers the yaw)
	if inside_cutaway != null and is_instance_valid(inside_cutaway):
		var side := _camera_side(inside_cutaway)
		if side != _cam_side:
			_cam_side = side
			inside_cutaway.apply_floor(inside_floor)


## Which side of the building (model space, the ±0.15 band of BuildingCutaway's facing rule) the camera is on.
func _camera_side(cut: BuildingCutaway) -> Vector2i:
	var m := cut.model_root()
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	if m == null or cam == null:
		return Vector2i.ZERO
	var d := cam.global_position - m.global_position
	d.y = 0.0
	if d.length() < 0.01:
		return Vector2i.ZERO
	var l := m.global_basis.inverse() * d.normalized()
	return Vector2i(int(l.x > 0.15) - int(l.x < -0.15), int(l.z > 0.15) - int(l.z < -0.15))


func _set_inside(cut: BuildingCutaway, fl: int) -> void:
	if cut == inside_cutaway and fl == inside_floor:
		return
	if inside_cutaway != null and is_instance_valid(inside_cutaway) and inside_cutaway != cut:
		inside_cutaway.apply_floor(-1)
	var was := inside
	inside_cutaway = cut
	inside_floor = fl
	inside = cut != null
	if cut != null:
		_cam_side = _camera_side(cut)
		cut.apply_floor(fl)
	var b: Node3D = cut.model_root() if cut != null else null
	inside_changed.emit(inside, b, fl)
	if was != inside:
		Events.shelter_changed.emit(inside)


## Is `model` (a building root) the one the local player is in right now?
func is_inside(model: Node3D) -> bool:
	return inside_cutaway != null and is_instance_valid(inside_cutaway) and inside_cutaway.model_root() == model
