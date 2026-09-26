class_name Corpse
extends Node3D
## A dead survivor's body (GDD v2 §12.2 "el cadáver guarda todo 48 h", ARQ v2 §11.5): spawned by the
## StructureSpawner (kind "corpse", replicated, persisted in the ChunkDelta `structures` table, contents in
## `containers`) with the whole inventory. Any player opens it like a container ("Recoger mochila de <nombre>",
## exclusive use). It disappears when emptied and closed, or after Balance.CORPSE_DAYS days of game time.
## Model `gore/corpse_covered` (ASSET_SPEC v2 M4 gore-lite) or a lying placeholder.

const MODEL := "gore/corpse_covered"

var owner_name: String = ""
var expires_day: int = 0
var storage: Storage
var interactable: InteractableComponent
var _check_t: float = 0.0


func _ready() -> void:
	add_to_group("corpse")
	storage = Storage.new()
	storage.name = "Storage"
	storage.slot_count = Balance.HOTBAR_SLOTS
	storage.title = ("MOCHILA DE %s" % owner_name.to_upper()) if owner_name != "" else "MOCHILA"
	add_child(storage)
	interactable = InteractableComponent.new()
	interactable.name = "Interactable"
	add_child(interactable)
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.9, 0.6, 1.9)
	interactable.set_shape(sh, Vector3(0, 0.3, 0))
	interactable.interact_range = Balance.INTERACT_RANGE
	interactable.ring_radius = 0.9
	interactable.default_action = &"open"
	var model: Node3D
	if Assets.has_model(MODEL) and not Assets.force_placeholders:
		model = Assets.spawn_model(MODEL)
	else:
		model = _placeholder()
	model.name = "Model"
	add_child(model)
	if not Net.is_server and NetWorld.instance != null:
		apply_net_delta(NetWorld.instance.delta_of(WorldRegistry.wid_of(self)))


func _placeholder() -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.28
	cap.height = 1.7
	body.mesh = cap
	body.rotation.x = PI * 0.5
	body.position = Vector3(0, 0.22, 0)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("#4F4135")
	m.roughness = 1.0
	body.material_override = m
	root.add_child(body)
	var cover := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.8, 0.08, 1.4)
	cover.mesh = bm
	cover.position = Vector3(0, 0.44, -0.1)
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color("#7A6A58")
	cm.roughness = 1.0
	cover.material_override = cm
	root.add_child(cover)
	return root


func interact_actions() -> Array:
	return [&"open"]


func get_interact_label(player: Node) -> String:
	if storage.in_use_by_other(player):
		return "Mochila en uso"
	var who := owner_name if owner_name != "" else "un superviviente"
	if player is Player and (player as Player).display_name == owner_name:
		return "Recuperar tu mochila"
	return "Recoger mochila de %s" % who


func can_interact(player: Node) -> bool:
	return not storage.is_open and not storage.in_use_by_other(player)


## Server only.
func server_interact(player: Node, action: StringName, _arg: int) -> bool:
	if action != &"open" or not (player is Player) or not Net.is_server:
		return false
	return NetWorld.instance.open_storage(player, storage)


func apply_net_delta(f: Dictionary) -> void:
	if f.has("open_by"):
		storage.open_by = int(f["open_by"])


func _process(delta: float) -> void:
	if not Net.is_server:
		return
	_check_t -= delta
	if _check_t > 0.0:
		return
	_check_t = 2.0
	var expired := expires_day > 0 and WorldState.day_now() >= expires_day
	if expired or (storage.is_empty() and storage.open_by == 0):
		if NetWorld.instance != null:
			NetWorld.instance.remove_structure(self)
		else:
			queue_free()
