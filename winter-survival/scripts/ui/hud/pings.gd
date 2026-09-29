class_name Pings
extends Node
## Basic pings of the group (H3; docs/research/10_hud_ux.md appendix §6.4.3, GDD §12.3), replicated by the server
## (HudNet): «lugar» (⚑ in the player's colour, 30 s) and «peligro» (▲ in blood with a countdown ring, 8 s).
## Input (keyboard / mouse): middle click = a place ping at the ground under the cursor; a double middle click, or a
## middle click on a zombie, = danger. (The gamepad gets the ping wheel in H4: every pad button already has a job.)
## Arrival: the positioned sound (`ui_ping` / `ui_ping_danger`, with its caption), and from a teammate one line —
## danger as P2 on the 3 s line («Ana: peligro · 40 m»), place as P3 in the pickup line — the name in their colour.
## The WorldLayer draws `live` (on screen; off screen only with Info). The paper map (H5) will read the same list.

var router: NotifyRouter
var captions: Node
## [{id, peer, kind, pos, born, until, seconds, name, color}] (clock = this node's clock)
var live: Array = []
var clock: float = 0.0
var received: int = 0
var sent: int = 0
var _pending_t: float = -1.0
var _pending_pos: Vector3 = Vector3.ZERO
var _last_click: float = -10.0


func _ready() -> void:
	Events.ping_placed.connect(_on_ping)


# ------------------------------------------------------------------ placing
## Sends a ping to the server (validated there: ≤ 150 m, 3 per 2 s).
func place(kind: StringName, pos: Vector3) -> void:
	if HudNet.instance == null:
		return
	sent += 1
	HudNet.instance.ping(kind, pos)


func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_MIDDLE or not mb.pressed or not GameFlow.in_game or GameFlow.is_paused:
		return
	var p := GameFlow.local_player() as Player
	if p == null or p.dead:
		return
	var hit := _cursor_point(mb.position)
	if hit.is_empty():
		return
	get_viewport().set_input_as_handled()
	if bool(hit["zombie"]):
		_pending_t = -1.0
		place(&"danger", hit["pos"])
		return
	if clock - _last_click <= UiTokens.PING_DOUBLE_CLICK and _pending_t >= 0.0:
		_pending_t = -1.0
		place(&"danger", _pending_pos)
	else:
		_pending_t = clock
		_pending_pos = hit["pos"]
	_last_click = clock


## Ground (or zombie) point under a screen position: {pos, zombie} or {}.
func _cursor_point(screen: Vector2) -> Dictionary:
	var cam := get_viewport().get_camera_3d()
	var p := GameFlow.local_player() as Player
	if cam == null or p == null:
		return {}
	var from := cam.project_ray_origin(screen)
	var dir := cam.project_ray_normal(screen)
	# a zombie near the ray → danger on it
	if ZombieClient.instance != null:
		var best := 1.2
		var bz := Vector3.INF
		for id in ZombieClient.instance.records:
			var r: ZombieClient.ZRec = ZombieClient.instance.records[id]
			if r.state == ZombieKinds.State.DEAD:
				continue
			var c := r.render_pos + Vector3(0, 1.0, 0)
			var t := (c - from).dot(dir)
			if t <= 0.0:
				continue
			var dd := (from + dir * t).distance_to(c)
			if dd < best:
				best = dd
				bz = r.render_pos
		if bz != Vector3.INF:
			return {"pos": bz, "zombie": true}
	var space := p.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 400.0, 1)
	var res := space.intersect_ray(q)
	if not res.is_empty():
		return {"pos": res["position"], "zombie": false}
	# no collider: the plane at the player's height
	if absf(dir.y) > 0.001:
		var t2 := (p.global_position.y - from.y) / dir.y
		if t2 > 0.0:
			return {"pos": from + dir * t2, "zombie": false}
	return {}


# ------------------------------------------------------------------ arrivals
func _on_ping(id: int, peer: int, kind: StringName, pos: Vector3, seconds: float) -> void:
	received += 1
	var who := _player(peer)
	var nm := who.display_name if who != null else ""
	var col := who.outfit if who != null else 0
	# 3 per player at most (the server does the same)
	var mine := live.filter(func(g: Dictionary) -> bool: return int(g["peer"]) == peer)
	while mine.size() >= UiTokens.PING_PER_PLAYER:
		live.erase(mine.pop_front())
	live.append({"id": id, "peer": peer, "kind": kind, "pos": pos, "born": clock, "until": clock + seconds, "seconds": seconds,
		"name": nm, "color": col})
	var danger := kind == &"danger"
	var own := peer == Net.local_peer_id()
	if captions != null:
		captions.call("expect", &"ui_ping_danger" if danger else &"ui_ping", pos, "" if own else nm, peer)
	AudioManager.play(&"ui_ping_danger" if danger else &"ui_ping", pos)
	if own or router == null:
		return
	var me := GameFlow.local_player() as Node3D
	var dist := UiTokens.distance(Vector2(pos.x - me.global_position.x, pos.z - me.global_position.z).length()) if me != null else ""
	if danger:
		router.push({"priority": 2, "key": "ping:%d" % id, "title": "peligro", "body": "%s: peligro · %s" % [nm, dist], "seconds": 3.0,
			"tone": &"danger", "from_peer": peer, "affects_me": true})
	else:
		router.push({"priority": 3, "key": "ping:%d" % id, "body": "%s marcó un lugar · %s" % [nm, dist], "from_peer": peer, "affects_me": true})


func _player(peer: int) -> Player:
	var me := GameFlow.local_player() as Node
	if me == null or me.get_parent() == null:
		return null
	for n in me.get_parent().get_children():
		if n is Player and (n as Player).peer_id == peer:
			return n
	return null


func by_id(id: int) -> Dictionary:
	for g: Dictionary in live:
		if int(g["id"]) == id:
			return g
	return {}


func clear() -> void:
	live.clear()


func _process(delta: float) -> void:
	clock += delta
	# a single middle click becomes a place ping once the double-click window is over
	if _pending_t >= 0.0 and clock - _pending_t > UiTokens.PING_DOUBLE_CLICK:
		_pending_t = -1.0
		place(&"place", _pending_pos)
	var i := 0
	while i < live.size():
		if clock > float(live[i]["until"]):
			live.remove_at(i)
		else:
			i += 1
