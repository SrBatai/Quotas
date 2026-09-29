class_name Silhouettes
extends Node
## Character silhouettes through walls (W0, doc 09 §3.1 layer D, §3.5), client only. Sets
## `material_overlay` = a silhouette material (assets/shaders/silhouette.gdshader: depth_test_inverted, only where
## something > 0.45 m in front hides the character) on the meshes of:
##   * every player, always, in the colour of their jacket (never lose the group, pillar «Nunca separes al grupo»);
##   * zombies only while PERCEIVED by the local player (`perceive_filter`; default: within 24 m and with a clear
##     line of sight from the player's eyes on the `world` layer), in amber — a silhouette is never a wallhack.
## Per-instance overlay: the shared world_vcol material is untouched (one material per tint, 5 in total). A mesh
## that already carries another overlay (the frozen zombies' ice) is left alone. Polls at 5 Hz (≤ 30 rays/poll).

const PERIOD := 0.2
const PERCEIVE_RANGE := 24.0
const EYE := 1.5
const CHEST := 1.1
## Jacket colours of the four survivor variants (CharacterVisual.VARIANTS: red, blue, green, mustard), brightened.
const PLAYER_TINTS := [Color(1.0, 0.42, 0.36, 0.62), Color(0.40, 0.66, 1.0, 0.62), Color(0.45, 0.9, 0.55, 0.62), Color(1.0, 0.82, 0.35, 0.62)]
const ZOMBIE_TINT := Color(1.0, 0.62, 0.18, 0.5)
const SHADER := "res://assets/shaders/silhouette.gdshader"

static var instance: Silhouettes
static var _mats: Dictionary = {}

var enabled: bool = true
var zombies_enabled: bool = true
## Callable(player: Node3D, zombie_pos: Vector3) -> bool. Replace when the honest-visibility system lands (GDD §3.1).
var perceive_filter: Callable
## Tests / bench: extra characters {root: Node3D, kind: "player"|"zombie", variant: int}.
var extra: Array[Dictionary] = []
## Tests (visibility gate): {"player": Color, "zombie": Color} replace the tints (pure key colours, alpha 1).
var tint_override: Dictionary = {}
## Counters of the last poll (tests).
var last_players: int = 0
var last_zombies: int = 0
var _t: float = 0.0
var _ray := PhysicsRayQueryParameters3D.new()


static func material(tint: Color) -> ShaderMaterial:
	var key := tint.to_html()
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = load(SHADER)
		m.set_shader_parameter("tint", tint)
		m.resource_name = "silhouette_" + key
		_mats[key] = m
	return _mats[key]


static func player_material(variant: int) -> ShaderMaterial:
	return material(PLAYER_TINTS[posmod(variant, PLAYER_TINTS.size())])


static func zombie_material() -> ShaderMaterial:
	return material(ZOMBIE_TINT)


static func is_silhouette(m: Material) -> bool:
	return m != null and m.resource_name.begins_with("silhouette_")


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	enabled = Quality.silhouettes_enabled()
	Quality.preset_changed.connect(func(_p: StringName) -> void: enabled = Quality.silhouettes_enabled())
	if not perceive_filter.is_valid():
		perceive_filter = _default_perceived
	_ray.collision_mask = 1
	_ray.collide_with_areas = false


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = PERIOD
	poll()


## One pass over the characters (also called directly by the tests / bench).
func poll() -> void:
	last_players = 0
	last_zombies = 0
	var local := _local_player()
	for p in get_tree().get_nodes_in_group("player"):
		var view: Variant = p.get("view")
		var model: Node = null
		if view != null and is_instance_valid(view) and (view as Node).get("visual") != null:
			model = (view as Node).get("visual").get("model")
		if model != null:
			_set_overlay(model, _player_mat(int(p.get("outfit"))) if enabled else null)
			last_players += 1
	if ZombieClient.instance != null:
		for v in ZombieClient.instance.views:
			if v.model == null:
				continue
			var on := enabled and zombies_enabled and v.visible and v.id != 0 and not v.dead and local != null \
				and bool(perceive_filter.call(local, v.global_position))
			_set_overlay(v.model, _zombie_mat() if on else null)
			if on:
				last_zombies += 1
	for e in extra:
		var root: Node3D = e.get("root")
		if root == null or not is_instance_valid(root):
			continue
		if str(e.get("kind", "player")) == "player":
			_set_overlay(root, _player_mat(int(e.get("variant", 0))) if enabled else null)
			last_players += 1
		else:
			var on := enabled and zombies_enabled and local != null and bool(perceive_filter.call(local, root.global_position))
			_set_overlay(root, _zombie_mat() if on else null)
			if on:
				last_zombies += 1


func _player_mat(variant: int) -> ShaderMaterial:
	return material(tint_override["player"]) if tint_override.has("player") else player_material(variant)


func _zombie_mat() -> ShaderMaterial:
	return material(tint_override["zombie"]) if tint_override.has("zombie") else zombie_material()


func _local_player() -> Node3D:
	var cc := CityCut.instance
	if cc != null and cc.player_override != null and is_instance_valid(cc.player_override):
		return cc.player_override
	var rig := CameraRig.active()
	if rig != null and rig.player != null:
		return rig.player
	return GameFlow.local_player() as Node3D


func _default_perceived(player: Node3D, pos: Vector3) -> bool:
	var from := player.global_position + Vector3(0, EYE, 0)
	var to := pos + Vector3(0, CHEST, 0)
	if from.distance_to(to) > PERCEIVE_RANGE:
		return false
	if not player.is_inside_tree():
		return false
	_ray.from = from
	_ray.to = to
	if player is CollisionObject3D:
		_ray.exclude = [(player as CollisionObject3D).get_rid()]
	return player.get_world_3d().direct_space_state.intersect_ray(_ray).is_empty()


## Geometry list per character root, cached (a zombie view keeps its model until it is set up again: the cache
## is keyed by the model node and dropped when that node is freed).
static var _geo_cache: Dictionary = {}


static func _geometries_of(root: Node) -> Array[GeometryInstance3D]:
	var key := root.get_instance_id()
	var cached: Variant = _geo_cache.get(key)
	if cached != null:
		return cached
	if _geo_cache.size() > 256:
		for k in _geo_cache.keys():
			if not is_instance_id_valid(int(k)):
				_geo_cache.erase(k)
	var list := BuildingCutaway._geometries(root)
	_geo_cache[key] = list
	return list


static func _set_overlay(root: Node, m: Material) -> void:
	for gi in _geometries_of(root):
		if not is_instance_valid(gi):
			_geo_cache.erase(root.get_instance_id())
			_set_overlay(root, m)
			return
		if gi.material_overlay == m:
			continue
		if gi.material_overlay != null and not is_silhouette(gi.material_overlay):
			continue   # another overlay (frozen ice) wins
		gi.material_overlay = m
