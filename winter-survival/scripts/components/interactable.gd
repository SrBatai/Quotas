class_name InteractableComponent
extends Area3D
## Marks its parent (or itself when self_owned) as clickable. Layer 4 ("interactable"). Registers the owner in
## the WorldRegistry so every request travels by `wid` (ARQ v2 §8.7). The owner may implement:
##   get_interact_label(player) · can_interact(player) · interact_actions() -> Array[StringName]
##   server_interact(player, action, arg) -> bool   (server only, after NetWorld validated the request)
##   client_preview(player, action) / client_preview_cancel(player, action)   (owner client, optimistic feedback)

signal interacted(player: Node, action: StringName)

@export var label: String = ""
@export var interact_range: float = 2.2
@export var requires_tool: StringName = &""
@export var no_tool_label: String = ""
@export var ring_offset: Vector3 = Vector3.ZERO
@export var ring_radius: float = 0.6
@export var enabled: bool = true
## Action sent by a plain click when the owner declares none.
@export var default_action: StringName = &"use"

var self_owned: bool = false


func _ready() -> void:
	collision_layer = 8
	collision_mask = 0
	monitoring = false
	monitorable = true
	var t := target_node()
	t.add_to_group("interactable")
	t.set_meta("interactable", self)
	WorldRegistry.register(t)   # stable id for request_interact / world deltas (deterministic node paths)


func target_node() -> Node:
	return self if self_owned else get_parent()


func wid() -> int:
	return WorldRegistry.wid_of(target_node())


## Adds a collision shape (owners call this from _ready with their own dimensions).
func set_shape(shape: Shape3D, offset: Vector3 = Vector3.ZERO) -> void:
	for c in get_children():
		if c is CollisionShape3D:
			c.queue_free()
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = offset
	add_child(cs)


static func _hand_of(player: Node) -> StringName:
	if player is Player:
		return (player as Player).state.hand_tool()
	return &""


## Actions the owner accepts (validated by NetWorld.request_interact).
func actions() -> Array[StringName]:
	var t := target_node()
	if not self_owned and t.has_method("interact_actions"):
		var out: Array[StringName] = []
		for a in t.interact_actions():
			out.append(StringName(a))
		return out
	return [default_action]


func get_label(player: Node) -> String:
	if requires_tool != &"" and _hand_of(player) != requires_tool and no_tool_label != "":
		return no_tool_label
	if self_owned:
		return _self_label(player)
	var t := target_node()
	if t.has_method("get_interact_label"):
		return t.get_interact_label(player)
	return label


func can_interact(player: Node) -> bool:
	if not enabled:
		return false
	if requires_tool != &"" and _hand_of(player) != requires_tool:
		return false
	if self_owned:
		return _self_can_interact(player)
	var t := target_node()
	if t.has_method("can_interact"):
		return t.can_interact(player)
	return true


## Server: performs the (already validated) action. Returns false when the owner refused it.
func server_interact(player: Node, action: StringName, arg: int) -> bool:
	var ok := true
	if self_owned:
		ok = _self_interact(player, action, arg)
	else:
		var t := target_node()
		if t.has_method("server_interact"):
			ok = bool(t.server_interact(player, action, arg))
	if ok:
		interacted.emit(player, action)
	return ok


## Owner client: optimistic feedback while the request travels (pure clients only; offline runs the real thing).
func client_preview(player: Node, action: StringName) -> void:
	var t := target_node()
	if not self_owned and t.has_method("client_preview"):
		t.client_preview(player, action)
	elif self_owned:
		_self_preview(player, action)


func client_preview_cancel(player: Node, action: StringName) -> void:
	var t := target_node()
	if not self_owned and t.has_method("client_preview_cancel"):
		t.client_preview_cancel(player, action)
	elif self_owned:
		_self_preview_cancel(player, action)


func get_ring_position() -> Vector3:
	var t := target_node()
	if t is Node3D:
		return (t as Node3D).global_position + ring_offset
	return global_position + ring_offset


## Horizontal distance from a node to this component.
func distance_to(node: Node3D) -> float:
	var a := node.global_position
	var b := global_position
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


# Overridable hooks for self-owned components (pickups).
func _self_label(_player: Node) -> String:
	return label


func _self_can_interact(_player: Node) -> bool:
	return true


func _self_interact(_player: Node, _action: StringName, _arg: int) -> bool:
	return false


func _self_preview(_player: Node, _action: StringName) -> void:
	pass


func _self_preview_cancel(_player: Node, _action: StringName) -> void:
	pass


static func find_from(node: Node) -> InteractableComponent:
	var n := node
	while n != null:
		if n is InteractableComponent:
			return n
		if n.has_meta("interactable"):
			var c = n.get_meta("interactable")
			if c is InteractableComponent and is_instance_valid(c):
				return c
		n = n.get_parent()
	return null
