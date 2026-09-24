class_name Pickup
extends InteractableComponent
## Ground item (firewood, stone, meat, pelt). The Area3D itself is the interactable.

@export var item_id: StringName = &"madera"
@export var model: String = "firewood"
@export var amount: int = 1

var _visual: Node3D
var _t: float = 0.0
var _base_y: float = 0.0


func _init() -> void:
	self_owned = true


func _ready() -> void:
	super()
	add_to_group("pickup")
	var sh := SphereShape3D.new()
	sh.radius = 0.45
	set_shape(sh, Vector3(0, 0.25, 0))
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	_visual.add_child(Assets.spawn_model(model))
	_t = randf() * TAU
	interact_range = Balance.INTERACT_RANGE
	ring_radius = 0.5


func _process(delta: float) -> void:
	_t += delta
	if _visual != null:
		_visual.position.y = 0.03 + 0.03 * sin(_t * 2.0)
		_visual.rotation.y += delta * 0.4


func _self_label(_player: Node) -> String:
	match item_id:
		&"madera": return "Recoger leña"
		&"piedra": return "Recoger piedra"
		&"carne_cruda": return "Recoger carne"
		&"piel": return "Recoger piel"
	return "Recoger %s" % Items.display_name(item_id).to_lower()


func _self_interact(_player: Node) -> void:
	var left := Inventory.add(item_id, amount)
	if left == amount:
		Events.notify.emit("Inventario lleno", 2.0)
		return
	AudioManager.play(&"pickup", global_position)
	if left > 0:
		amount = left
	else:
		enabled = false
		queue_free()
