class_name ChoppableTree
extends StaticBody3D
## Pines, dead trees and fallen logs: chopped with the axe (action `chop`). Server authoritative
## (`server_interact` only runs there); hits / felled travel as a world delta so every client (late joiners
## included) plays the same result. The owner client previews the hit (shake + chips) while the request travels.

const STUMP_SCENE := preload("res://scenes/world/stump.tscn")

@export var variant: String = "pine_a"

@onready var visual: Node3D = $Visual
@onready var interactable: InteractableComponent = $Interactable
@onready var shape: CollisionShape3D = $Shape

var hits: int = 0
var total_hits: int = Balance.TREE_HITS
var wood: int = Balance.TREE_WOOD
var felled: bool = false
var _cooldown: float = 0.0
var _model: Node3D


func _ready() -> void:
	collision_layer = 1 | 64
	collision_mask = 0
	add_to_group("choppable")
	add_to_group("tree")
	_model = Assets.spawn_model(variant)
	visual.add_child(_model)
	var is_log := variant == "fallen_log"
	if variant == "dead_tree":
		total_hits = Balance.DEAD_TREE_HITS
		wood = Balance.DEAD_TREE_WOOD
	elif is_log:
		total_hits = Balance.LOG_HITS
		wood = Balance.LOG_WOOD
	if is_log:
		var box := BoxShape3D.new()
		box.size = Vector3(1.6, 0.4, 0.4)
		shape.shape = box
		shape.position = Vector3(0, 0.2, 0)
		var ibox := BoxShape3D.new()
		ibox.size = Vector3(1.8, 0.7, 0.7)
		interactable.set_shape(ibox, Vector3(0, 0.3, 0))
		interactable.ring_radius = 0.9
	else:
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.35
		cyl.height = 3.0
		shape.shape = cyl
		shape.position = Vector3(0, 1.5, 0)
		var icyl := CylinderShape3D.new()
		var h := 7.0 if variant == "pine_a" else (5.5 if variant == "pine_b" else 4.2)
		icyl.radius = 1.1 if variant != "dead_tree" else 0.6
		icyl.height = h
		interactable.set_shape(icyl, Vector3(0, h * 0.5, 0))
		interactable.ring_radius = 0.9
	interactable.interact_range = Balance.INTERACT_RANGE
	interactable.requires_tool = &"hacha"
	interactable.no_tool_label = "Necesitas un hacha"
	interactable.default_action = &"chop"
	if not Net.is_server and NetWorld.instance != null:
		apply_net_delta(NetWorld.instance.delta_of(WorldRegistry.wid_of(self)))


func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown -= delta


func interact_actions() -> Array:
	return [&"chop"]


func get_interact_label(_player: Node) -> String:
	if variant == "fallen_log":
		return "Cortar leña (%d/%d)" % [hits, total_hits]
	return "Talar árbol (%d/%d)" % [hits, total_hits]


func can_interact(_player: Node) -> bool:
	return not felled


## Server only (validated by NetWorld.request_interact).
func server_interact(player: Node, action: StringName, _arg: int) -> bool:
	if action != &"chop" or felled or _cooldown > 0.0 or not Net.is_server:
		return false
	_cooldown = Balance.CHOP_COOLDOWN
	hits += 1
	if player != null and player.has_method("play_chop"):
		player.play_chop(global_position)
	_hit_fx(player.global_position if player is Node3D else global_position)
	Events.tree_hit.emit(self, hits, total_hits)
	if hits >= total_hits:
		_fell(player)
	else:
		NetWorld.instance.set_delta(WorldRegistry.wid_of(self), {"hits": hits})
	return true


## Owner client: the hit is shown at once; the server's delta confirms the count.
func client_preview(player: Node, action: StringName) -> void:
	if action == &"chop" and not felled and _cooldown <= 0.0:
		_cooldown = Balance.CHOP_COOLDOWN
		_hit_fx(player.global_position if player is Node3D else global_position)


func _hit_fx(from: Vector3) -> void:
	_shake()
	if not Net.has_client:
		return
	var puff_pos := global_position + Vector3(0, 1.0 if variant != "fallen_log" else 0.3, 0)
	puff_pos += (from - global_position).normalized() * 0.4
	HitPuff.spawn(get_tree().current_scene, puff_pos)
	AudioManager.play(&"chop_hit", global_position)


func _shake() -> void:
	if not Net.has_client:
		return
	var tw := create_tween()
	var base := visual.rotation
	tw.tween_property(visual, "rotation", base + Vector3(0.04, 0, 0.03), 0.06)
	tw.tween_property(visual, "rotation", base - Vector3(0.03, 0, 0.04), 0.08)
	tw.tween_property(visual, "rotation", base, 0.1)


func _fell(player: Node) -> void:
	var away := Vector3.MODEL_FRONT
	if player is Node3D:
		away = (global_position - player.global_position)
		away.y = 0.0
		away = away.normalized() if away.length() > 0.01 else Vector3.MODEL_FRONT
	var p := player as Player
	if p != null:
		var left := p.state.inventory.add(&"madera", wood)
		if left > 0:
			_drop_wood(left)
		p.state.emit_sim(&"tree_felled", [variant])
	NetWorld.instance.set_delta(WorldRegistry.wid_of(self), {"hits": hits, "felled": true, "ax": away.x, "az": away.z})
	_fell_visual(away, true)


## Shared: disable, animate the fall, leave a stump, free. `animate` = false when restoring a saved delta.
func _fell_visual(away: Vector3, animate: bool = true) -> void:
	if felled:
		return
	felled = true
	interactable.enabled = false
	shape.set_deferred("disabled", true)
	remove_from_group("choppable")
	remove_from_group("tree")
	# baked terrain AO (G1): the tree's contact disc shrinks to the stump's (logs lose theirs)
	var world := get_tree().get_first_node_in_group("world") as World
	if world != null and world.terrain != null:
		if variant == "fallen_log":
			world.terrain.update_occluder(String(name), 0.0, 0.0)
		else:
			world.terrain.update_occluder(String(name), 0.45 * scale.x, 0.3)
	if animate:
		AudioManager.play(&"tree_fall", global_position)
	var tw := create_tween()
	if variant == "fallen_log":
		tw.tween_property(visual, "scale", Vector3(0.01, 0.01, 0.01), 0.4 if animate else 0.01).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	else:
		var axis := away.cross(Vector3.UP).normalized()
		var local_axis := global_transform.basis.inverse() * axis
		var target := Basis(local_axis.normalized(), deg_to_rad(-82.0)) * visual.basis
		tw.tween_property(visual, "basis", target, 1.0 if animate else 0.01).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		var stump := STUMP_SCENE.instantiate()
		stump.name = "stump_of_" + String(name)
		get_parent().add_child(stump)
		stump.global_position = global_position
		stump.rotation.y = rotation.y
	tw.tween_interval(0.3 if animate else 0.01)
	tw.tween_callback(queue_free)


## Replicated state (clients; the server after loading a save).
func apply_net_delta(f: Dictionary) -> void:
	if f.is_empty():
		return
	var new_hits := int(f.get("hits", hits))
	if new_hits > hits and not bool(f.get("felled", false)) and Net.has_client and is_inside_tree():
		hits = new_hits
		_hit_fx(global_position + Vector3.MODEL_FRONT)
	hits = maxi(hits, new_hits)
	if bool(f.get("felled", false)) and not felled:
		_fell_visual(Vector3(float(f.get("ax", 0.0)), 0.0, float(f.get("az", 1.0))).normalized(), Net.has_client)


func _drop_wood(n: int) -> void:
	var world := get_tree().get_first_node_in_group("world") as World
	if world == null:
		return
	for i in n:
		var ang := TAU * float(i) / float(maxi(n, 1))
		var pos := global_position + Vector3(cos(ang) * 1.2, 0.0, sin(ang) * 1.2)
		pos.y = world.get_height(pos.x, pos.z)
		world.spawn_drop(&"madera", "firewood", pos, 1)
