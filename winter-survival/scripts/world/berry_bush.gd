extends StaticBody3D
## Berry bush: click → +3 berries, regrows after BUSH_REGROW seconds (server); state travels as a world delta.

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
	interactable.default_action = &"pick"
	if not Net.is_server and NetWorld.instance != null:
		apply_net_delta(NetWorld.instance.delta_of(WorldRegistry.wid_of(self)))


func _process(delta: float) -> void:
	if has_berries or not Net.is_server:
		return
	_regrow -= delta
	if _regrow <= 0.0:
		_set_berries(true)
		NetWorld.instance.set_delta(WorldRegistry.wid_of(self), {"berries": true})


func _set_berries(value: bool) -> void:
	has_berries = value
	if _berries != null:
		_berries.visible = value


func interact_actions() -> Array:
	return [&"pick"]


func get_interact_label(_player: Node) -> String:
	return "Recoger bayas" if has_berries else "Sin bayas (rebrotan)"


func can_interact(_player: Node) -> bool:
	return has_berries


## Server only.
func server_interact(player: Node, action: StringName, _arg: int) -> bool:
	var p := player as Player
	if action != &"pick" or not has_berries or p == null or not Net.is_server:
		return false
	var left := p.state.inventory.add(&"bayas", Balance.BERRIES_PER_BUSH)
	if left == Balance.BERRIES_PER_BUSH:
		p.state.notify("Inventario lleno", 2.0)
		return false
	_set_berries(false)
	_regrow = Balance.BUSH_REGROW
	NetWorld.instance.set_delta(WorldRegistry.wid_of(self), {"berries": false})
	AudioManager.play(&"pickup", global_position)
	return true


## Owner client: hide the berries at once; the delta (or a denial) settles it.
func client_preview(_player: Node, action: StringName) -> void:
	if action == &"pick" and _berries != null:
		_berries.visible = false


func client_preview_cancel(_player: Node, _action: StringName) -> void:
	_set_berries(has_berries)


func apply_net_delta(f: Dictionary) -> void:
	if f.has("berries"):
		_set_berries(bool(f["berries"]))
