class_name Interactor
extends Node
## Owner client: cursor raycast → hovered InteractableComponent; click → predicted auto-walk when far, then a
## validated `NetWorld.request_interact(wid, action, arg)` with an optimistic `client_preview` (reverted on a
## denial); attack → `request_attack`. Labels use the owner's state mirror.
## M3: trees are MultiMesh instances; a ray that meets a chunk's scatter trunk, or passes through a tree's crown
## (World.pick_scatter over the scatter index), materializes that one tree so the usual component takes over.

var target: InteractableComponent
var pending: InteractableComponent
var hover_text: String = ""
var _player: Player
var _ring: HoverRing
var _previews: Dictionary = {}   # wid -> [comp, action] awaiting the server's answer


func _ready() -> void:
	_player = get_parent()
	_ring = _player.get_node_or_null("View/HoverRing")
	Events.interact_result.connect(_on_interact_result)


func _camera() -> Camera3D:
	return get_viewport().get_camera_3d()


func _active() -> bool:
	return GameFlow.in_game and not _player.dead


func _physics_process(_delta: float) -> void:
	if not _active():
		_set_hover(null, "")
		return
	if _player.placement != null and _player.placement.active:
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
		if found == null and hit.collider.has_meta("scatter_chunk"):
			var ch: WorldChunk = hit.collider.get_meta("scatter_chunk")
			var i := ch.entry_of_hit(hit.collider, int(hit.get("shape", -1)))
			if i >= 0 and ScatterCatalog.is_choppable(int(ch.data.entries[i]["v"])):
				var t := ch.materialize(i)
				found = t.interactable if t != null else null
	if found == null and World.instance != null:
		var ground: Vector3 = hit.position if not hit.is_empty() else to
		var t := World.instance.pick_scatter(from, (to - from).normalized(), ground)
		if t != null and t.is_inside_tree():
			found = t.interactable
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
	if _ring != null and is_instance_valid(_ring):
		if found != null:
			_ring.show_at(found.get_ring_position(), found.ring_radius, found.can_interact(_player))
		else:
			_ring.hide_ring()
	if text != hover_text:
		hover_text = text
		Events.hover_changed.emit(text)


func _unhandled_input(event: InputEvent) -> void:
	if not _active():
		return
	if _player.placement != null and _player.placement.active:
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
		var t := target.get_label(_player)
		if t != "":
			Events.notify.emit(t, 1.5)
		return
	_go_or_interact(target)


func _go_or_interact(comp: InteractableComponent) -> void:
	if comp.distance_to(_player) <= comp.interact_range:
		pending = null
		_player.auto_target = null
		send_interact(comp)
	else:
		pending = comp
		_player.auto_target = comp


## Sends the component's default action (or `action`) and previews it locally on a pure client.
func send_interact(comp: InteractableComponent, action: StringName = &"", arg: int = 0) -> void:
	if action == &"":
		action = comp.default_action
	_player.face_toward(comp.global_position)
	var wid := comp.wid()
	Net.rpc_server(NetWorld.instance, &"request_interact", [wid, action, arg])
	if Net.is_client:
		comp.client_preview(_player, action)
		_previews[wid] = [comp, action]


func _on_interact_result(wid: int, action: StringName, ok: bool, _reason: String) -> void:
	if not _previews.has(wid):
		return
	var e: Array = _previews[wid]
	_previews.erase(wid)
	var comp: InteractableComponent = e[0]
	if not ok and comp != null and is_instance_valid(comp):
		comp.client_preview_cancel(_player, action)


## Called by the player input when auto-walk reaches the pending target.
func perform_pending() -> void:
	if pending != null and is_instance_valid(pending) and pending.can_interact(_player):
		send_interact(pending)
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
	# M3: the nearest MultiMesh tree / log in reach counts too (materialized when chosen)
	if World.instance != null and World.instance.is_configured:
		var f := World.instance.nearest_scatter(_player.global_position, "", 0)
		if not f.is_empty():
			var ch: WorldChunk = f[0]
			var d := Vector2(ch.entry_position(f[1]).x - _player.global_position.x, ch.entry_position(f[1]).z - _player.global_position.z).length()
			if d < best_d:
				var t := ch.materialize(int(f[1]))
				if t != null and t.interactable.can_interact(_player):
					best = t.interactable
	if best != null:
		_go_or_interact(best)


## Space: swing at the nearest living animal in reach (wolves first, then deer), or in the air.
func attack_nearest() -> void:
	var best: Node = null
	var best_d := Balance.ATTACK_RANGE
	var p: Vector3 = _player.global_position
	for group in ["wolves", "deer"]:
		for w in get_tree().get_nodes_in_group(group):
			if w.has_method("is_dead") and w.is_dead():
				continue
			var d := Vector2(w.global_position.x - p.x, w.global_position.z - p.z).length()
			if d < best_d:
				best_d = d
				best = w
	if best != null:
		_player.face_toward(best.global_position)
	Net.rpc_server(NetWorld.instance, &"request_attack", [WorldRegistry.wid_of(best) if best != null else 0])
