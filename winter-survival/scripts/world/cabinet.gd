extends StaticBody3D
## Cabinet container (6 slots).

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
	storage.title = "ARMARIO"
	storage.setup({&"lata_judias": 2, &"lata_sopa": 2})


func get_interact_label(_player: Node) -> String:
	return "Armario abierto" if storage.is_open else "Abrir armario"


func can_interact(_player: Node) -> bool:
	return not storage.is_open


func interact(_player: Node) -> void:
	Events.storage_opened.emit(storage)
	AudioManager.play(&"ui_open")
