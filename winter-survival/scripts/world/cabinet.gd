extends StaticBody3D
## Cabinet container (6 slots). Contents live on the server; opening is exclusive (NetWorld.open_storage): the
## replicated `open_by` makes every other client show "Armario en uso".

@onready var storage: Storage = $Storage
@onready var interactable: InteractableComponent = $Interactable


func _ready() -> void:
	collision_layer = 1 | 64
	collision_mask = 0
	var model := Assets.spawn_model("cabinet")
	$Visual.add_child(model)
	var box := BoxShape3D.new()
	box.size = Vector3(0.9, 1.8, 0.5)
	var cs := CollisionShape3D.new()
	cs.shape = box
	cs.position = Vector3(0, 0.9, 0)
	add_child(cs)
	var ibox := BoxShape3D.new()
	ibox.size = Vector3(1.2, 2.0, 1.0)
	interactable.set_shape(ibox, Vector3(0, 1.0, -0.2))
	interactable.ring_radius = 0.7
	interactable.interact_range = Balance.INTERACT_RANGE
	interactable.default_action = &"open"
	storage.title = "ARMARIO"
	storage.setup({&"lata_judias": 2, &"lata_sopa": 2})
	if not Net.is_server and NetWorld.instance != null:
		apply_net_delta(NetWorld.instance.delta_of(WorldRegistry.wid_of(self)))


func interact_actions() -> Array:
	return [&"open"]


func get_interact_label(player: Node) -> String:
	if storage.in_use_by_other(player):
		return "Armario en uso"
	return "Armario abierto" if storage.is_open else "Abrir armario"


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
