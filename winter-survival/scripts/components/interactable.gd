class_name InteractableComponent
extends Area3D
## Marks its parent (or itself when self_owned) as clickable. Layer 4 ("interactable").
## The owner may implement get_interact_label(player), can_interact(player) and interact(player).

signal interacted(player: Node)

@export var label: String = ""
@export var interact_range: float = 2.2
@export var requires_tool: StringName = &""
@export var no_tool_label: String = ""
@export var ring_offset: Vector3 = Vector3.ZERO
@export var ring_radius: float = 0.6
@export var enabled: bool = true

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


func interact(player: Node) -> void:
	if self_owned:
		_self_interact(player)
	else:
		var t := target_node()
		if t.has_method("interact"):
			t.interact(player)
	interacted.emit(player)


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


func _self_interact(_player: Node) -> void:
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
