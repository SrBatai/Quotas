class_name Interactor
extends Node
## Cursor raycast → hovered InteractableComponent; click to interact (auto-walk if far); attack.

var target: InteractableComponent
var pending: InteractableComponent
var hover_text: String = ""
var _player: Node
var _ring: HoverRing
var _hover_hold: bool = false


func _ready() -> void:
	_player = get_parent()
	_ring = _player.get_node_or_null("HoverRing")


func _camera() -> Camera3D:
	return get_viewport().get_camera_3d()


func _physics_process(_delta: float) -> void:
	if GameState.is_game_over or not GameState.is_running:
		_set_hover(null, "")
		return
	if bool(_player.placement.active):
		_set_hover(null, "")
		return
	if get_viewport().gui_get_hovered_control() != null:
		_set_hover(null, "")
		return
	var cam := _camera()
	if cam == null:
		return
	var mouse := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mouse)
	var to := from + cam.project_ray_normal(mouse) * 120.0
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 4 | 8, [_player.get_rid()])
	q.collide_with_areas = true
	q.collide_with_bodies = true
	var hit: Dictionary = _player.get_world_3d().direct_space_state.intersect_ray(q)
	var found: InteractableComponent = null
	if not hit.is_empty() and hit.collider != null:
		found = InteractableComponent.find_from(hit.collider)
	if found != null and not is_instance_valid(found):
		found = null
	var text := ""
	if found != null:
		text = found.get_label(_player)
		if found.can_interact(_player) and found.distance_to(_player) > found.interact_range:
			text += " · acércate"
	_set_hover(found, text)


func _set_hover(found: InteractableComponent, text: String) -> void:
	target = found
	if _ring != null:
		if found != null:
			_ring.show_at(found.get_ring_position(), found.ring_radius, found.can_interact(_player))
		else:
			_ring.hide_ring()
	if text != hover_text:
		hover_text = text
		Events.hover_changed.emit(text)


func _unhandled_input(event: InputEvent) -> void:
	if GameState.is_game_over or not GameState.is_running:
		return
	if bool(_player.placement.active):
		return
	if event.is_action_pressed("interact_click"):
		_click()
	elif event.is_action_pressed("interact"):
		_interact_nearest()
	elif event.is_action_pressed("attack"):
		attack_nearest()


func _click() -> void:
	if target == null or not is_instance_valid(target):
		return
	if not target.can_interact(_player):
		# show why (e.g. needs an axe)
		var t := target.get_label(_player)
		if t != "":
			Events.notify.emit(t, 1.5)
		return
	_go_or_interact(target)


func _go_or_interact(comp: InteractableComponent) -> void:
	if comp.distance_to(_player) <= comp.interact_range:
		pending = null
		_player.auto_target = null
		_player.face_toward(comp.global_position)
		comp.interact(_player)
	else:
		pending = comp
		_player.auto_target = comp


## Called by the player when auto-walk reaches the pending target.
func perform_pending() -> void:
	if pending != null and is_instance_valid(pending) and pending.can_interact(_player):
		_player.face_toward(pending.global_position)
		pending.interact(_player)
	pending = null


func _interact_nearest() -> void:
	var best: InteractableComponent = null
	var best_d := 2.6
	for n in get_tree().get_nodes_in_group("interactable"):
		var comp := InteractableComponent.find_from(n)
		if comp == null or not comp.can_interact(_player):
			continue
		var d := comp.distance_to(_player)
		if d < best_d:
			best_d = d
			best = comp
	if best != null:
		_go_or_interact(best)


func attack_nearest() -> void:
	var best: Node = null
	var best_d := Balance.ATTACK_RANGE
	var p: Vector3 = _player.global_position
	for w in get_tree().get_nodes_in_group("wolves"):
		if w.get("state") != null and w.state == w.State.DEAD:
			continue
		var d := Vector2(w.global_position.x - p.x, w.global_position.z - p.z).length()
		if d < best_d:
			best_d = d
			best = w
	_player.attack(best)
