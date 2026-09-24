extends Node3D
## Abandoned pickup truck: decorative body with embedded collision + a CAMIONETA container (server state).

@onready var storage: Storage = $Storage
@onready var interactable: InteractableComponent = $Interactable


func _ready() -> void:
	var model := Assets.spawn_model("pickup_truck")
	$Visual.add_child(model)
	if Assets.is_placeholder(model) == false and model.find_child("ColChassis", true, false) == null:
		# glb without embedded collision: add the spec boxes (v2 frame: hood toward +Z, bed toward -Z)
		Placeholders._col_box(model, "ColChassis", Vector3(-1.0, 0.3, -2.5), Vector3(1.0, 1.3, 2.5))
		Placeholders._col_box(model, "ColCab", Vector3(-0.95, 1.3, -0.2), Vector3(0.95, 2.0, 1.0))
	var anchor: Node3D = model.find_child("BedAnchor", true, false)
	var sh := SphereShape3D.new()
	sh.radius = 1.6
	interactable.set_shape(sh)
	if anchor != null:
		interactable.position = anchor.position
	else:
		interactable.position = Vector3(0, 1.0, -1.35)
	interactable.ring_offset = Vector3(0, 0, 0)
	interactable.ring_radius = 1.2
	interactable.interact_range = 3.2
	storage.title = "CAMIONETA"
	storage.setup({&"madera": 3, &"lata_sopa": 1})
	if not Net.is_server and NetWorld.instance != null:
		apply_net_delta(NetWorld.instance.delta_of(WorldRegistry.wid_of(self)))


func get_interact_label(player: Node) -> String:
	if storage.open_by != 0 and player is Player and storage.open_by != player.peer_id:
		return "Camioneta en uso"
	return "Camioneta abierta" if storage.is_open else "Registrar camioneta"


func can_interact(player: Node) -> bool:
	return not storage.is_open and (storage.open_by == 0 or (player is Player and storage.open_by == player.peer_id))


## Server only.
func interact(player: Node) -> void:
	if player is Player and Net.is_server:
		NetWorld.instance.open_storage(player, storage)


func apply_net_delta(f: Dictionary) -> void:
	if f.has("open_by"):
		storage.open_by = int(f["open_by"])
