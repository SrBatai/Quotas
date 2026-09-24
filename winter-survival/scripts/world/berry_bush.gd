extends StaticBody3D
## Berry bush: click → +3 berries, regrows after BUSH_REGROW seconds.

@onready var interactable: InteractableComponent = $Interactable

var has_berries: bool = true
var _regrow: float = 0.0
var _berries: Node3D


func _ready() -> void:
	collision_layer = 64
	collision_mask = 0
	var model := Assets.spawn_model("berry_bush")
	$Visual.add_child(model)
	_berries = model.find_child("Berries", true, false)
	var sh := SphereShape3D.new()
	sh.radius = 0.5
	var cs := CollisionShape3D.new()
	cs.shape = sh
	cs.position = Vector3(0, 0.4, 0)
	add_child(cs)
	var ish := SphereShape3D.new()
	ish.radius = 0.75
	interactable.set_shape(ish, Vector3(0, 0.35, 0))
	interactable.ring_radius = 0.7


func _process(delta: float) -> void:
	if has_berries:
		return
	_regrow -= delta
	if _regrow <= 0.0:
		has_berries = true
		if _berries != null:
			_berries.visible = true


func get_interact_label(_player: Node) -> String:
	return "Recoger bayas" if has_berries else "Sin bayas (rebrotan)"


func can_interact(_player: Node) -> bool:
	return has_berries


func interact(_player: Node) -> void:
	if not has_berries:
		return
	var left := Inventory.add(&"bayas", Balance.BERRIES_PER_BUSH)
	if left == Balance.BERRIES_PER_BUSH:
		Events.notify.emit("Inventario lleno", 2.0)
		return
	has_berries = false
	_regrow = Balance.BUSH_REGROW
	if _berries != null:
		_berries.visible = false
	AudioManager.play(&"pickup", global_position)
