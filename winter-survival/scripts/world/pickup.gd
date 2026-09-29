class_name Pickup
extends InteractableComponent
## Ground item (firewood, stone, meat, pelt). The Area3D itself is the interactable (action `take`). Seeded
## pickups exist on both sides (taken = world delta "removed"); runtime drops live under World/Drops through the
## DropSpawner (taken = despawn + drops table). The owner client hides it while the request travels.

@export var item_id: StringName = &"madera"
@export var model: String = "firewood"
@export var amount: int = 1

var _visual: Node3D
var _t: float = 0.0
var _base_y: float = 0.0


func _init() -> void:
	self_owned = true
	default_action = &"take"


func _ready() -> void:
	super()
	add_to_group("pickup")
	var sh := SphereShape3D.new()
	sh.radius = 0.45
	set_shape(sh, Vector3(0, 0.25, 0))
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	if Net.has_client:
		_visual.add_child(Assets.spawn_model(model))
	_t = randf() * TAU
	interact_range = Balance.INTERACT_RANGE
	ring_radius = 0.5
	if not Net.is_server and NetWorld.instance != null:
		apply_net_delta(NetWorld.instance.delta_of(WorldRegistry.wid_of(self)))


func _process(delta: float) -> void:
	_t += delta
	if _visual != null:
		_visual.position.y = 0.03 + 0.03 * sin(_t * 2.0)
		_visual.rotation.y += delta * 0.4


func is_drop() -> bool:
	return get_parent() != null and get_parent().name == "Drops"


func _self_label(_player: Node) -> String:
	match item_id:
		&"madera": return "Recoger leña"
		&"piedra": return "Recoger piedra"
		&"carne_cruda": return "Recoger carne"
		&"piel": return "Recoger piel"
	return "Recoger %s" % Items.display_name(item_id).to_lower()


## Server only.
func _self_interact(player: Node, action: StringName, _arg: int) -> bool:
	var p := player as Player
	if p == null or action != &"take" or not Net.is_server:
		return false
	var left := p.state.inventory.add(item_id, amount)
	if left == amount:
		p.state.notify("Inventario lleno", 2.0)
		return false
	AudioManager.play(&"pickup", global_position)
	var wid := WorldRegistry.wid_of(self)
	if left > 0:
		amount = left
		if is_drop():
			NetWorld.instance.register_drop(wid, {"amount": amount})
		else:
			NetWorld.instance.set_delta(wid, {"amount": amount})
	else:
		enabled = false
		if is_drop():
			NetWorld.instance.erase_drop(wid)
		else:
			NetWorld.instance.set_delta(wid, {"removed": true})
		queue_free()
	return true


func _self_preview(_player: Node, action: StringName) -> void:
	if action == &"take" and _visual != null:
		_visual.visible = false


func _self_preview_cancel(_player: Node, _action: StringName) -> void:
	if _visual != null:
		_visual.visible = true


func apply_net_delta(f: Dictionary) -> void:
	if f.is_empty():
		return
	if f.has("amount"):
		amount = int(f["amount"])
	if bool(f.get("removed", false)):
		enabled = false
		queue_free()
