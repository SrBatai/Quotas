class_name WorldLayer
extends Control
## Everything of the HUD v2 that is anchored to the 3D world (docs/research/10_hud_ux.md §V.3–§V.4, mockups
## v2_b, v2_d, v2_e, v2_f), drawn in one canvas item at 30 Hz in 1080p reference pixels:
## - the tracked objective: a 10 px diamond on screen within 300 m, no text (name · distance on focus / Info),
##   hidden within 6 m (the interaction prompt takes over), and a ✓ with a widening ring when a step completes;
## - AT MOST ONE edge marker (6 px arrow + filled diamond + distance) for the accent target of `AccentArbiter`
##   (downed teammate > nearest heat while freezing > tracked objective); with Info, the other destinations show
##   as faint diamonds on the rail;
## - heat sources while freezing ("refugio 4 m"), up to 2;
## - teammates only when far (> 25 m; 10 m in a blizzard), hurt, talking (their chat line, 6 s) or with Info;
## - a downed teammate: ONE indicator in the accent — ground ring, a 46 px ring that drains with the bleed-out,
##   a line skull, "Ana 38 s" and "mantén X para reanimar · 6 m" (the hold ring fills while reviving);
## - the damage arc on the ground ellipse toward the attacker (600 ms) and the stamina arc at the shoulder
##   (26 px, only below 100, fades 1 s after refilling);
## - interaction prompts within 2.5 m, anchored 1.2 m above the object, with the device glyph and a hold ring;
##   the mouse keeps the context label next to the cursor (appendix §6.9).
## H3: the damage arc comes only from `Events.player_hit_from` (HitDirection resolves the attacker); pings (danger ▲
## with its 8 s countdown ring, place ⚑ in the player's colour, name · distance; off screen only with Info, faint on
## the rail); the P0 notices of the NotifyRouter that live in the world at a point (thin ice "!" at the feet); the
## downed indicator records when it was first drawn (`downed_seen`: the ≤ 0.2 s gate of the `team` net scenario).

const PERIOD := 1.0 / 30.0
const RAIL_X := 40.0
const RAIL_Y := 48.0

var hud: Node   # Hud (untyped to avoid a cyclic class reference)
var vis: HudVisibility
var accent: AccentArbiter
var team: TeamTracker
var mlog: MissionLog
## Test / screenshot hooks.
var last_edge: Dictionary = {}
var edge_count: int = 0
var prompt_text: String = ""
var downed_drawn: int = 0
## H3: peer -> Time.get_ticks_msec() when its downed indicator (world or edge) was first drawn; cleared when up.
var downed_seen: Dictionary = {}
## H3: ping id -> true once drawn on screen; P0 world markers drawn.
var pings_drawn: Dictionary = {}
var p0_drawn: int = 0
## H3 (set by the HUD): the pings model and the router (P0 in the world).
var pings: Node
var router: Node

var _acc: float = 0.0
var _t: float = 0.0
var _hits: Array = []           # [{t, angle (screen rad) or NAN, amount}]
var _last_hit_t: float = -10.0
var _stamina_full_t: float = -10.0
var _stamina_a: float = 0.0
var _checks: Array = []         # [{pos, t}]
var _mate_a: Dictionary = {}    # peer -> alpha
var _prompt_target: Node3D
var _prompt_label: String = ""
var _prompt_a: float = 0.0
var _scan_t: float = 0.0
var _cursor_text: String = ""
var _placement_text: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Events.player_hit_from.connect(_on_hit_from)
	Events.objective_updated.connect(_on_objective)
	Events.hover_changed.connect(func(t: String) -> void: _cursor_text = t)
	Events.placement_mode.connect(func(on: bool) -> void:
		_placement_text = "Clic: colocar · Clic derecho: cancelar" if on else "")


func setup(h: Node, v: HudVisibility, a: AccentArbiter, t: TeamTracker, l: MissionLog) -> void:
	hud = h
	vis = v
	accent = a
	team = t
	mlog = l


# ------------------------------------------------------------------ projection helpers
func _cam() -> Camera3D:
	return get_viewport().get_camera_3d()


func _k() -> float:
	return float(hud.get("k")) if hud != null else 1.0


## World → reference pixels; Vector2.INF when behind the camera.
func project(p: Vector3) -> Vector2:
	var cam := _cam()
	if cam == null or cam.is_position_behind(p):
		return Vector2.INF
	return cam.unproject_position(p) / _k()


func _on_screen(q: Vector2, margin: float = 24.0) -> bool:
	return q != Vector2.INF and Rect2(Vector2.ZERO, size).grow(-margin).has_point(q)


## Screen direction toward a world point from the player (works for points far away / behind: appendix §6.4.2).
func screen_dir(from: Vector3, to: Vector3) -> Vector2:
	var cam := _cam()
	if cam == null:
		return Vector2.RIGHT
	return dir_on_screen(cam, from, to)


## Screen direction (unit, y down) of `to` seen from `from` with the camera's yaw and the 48° pitch (captions, rail).
static func dir_on_screen(cam: Camera3D, from: Vector3, to: Vector3) -> Vector2:
	var right := cam.global_basis.x
	right.y = 0.0
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	right = right.normalized()
	fwd = fwd.normalized()
	var d := to - from
	d.y = 0.0
	var v := Vector2(d.dot(right), -d.dot(fwd) * sin(deg_to_rad(48.0)))
	return v.normalized() if v.length() > 0.001 else Vector2.RIGHT


## Point of the rail (a rectangle inside the screen) hit by the ray from `origin` along `dir`, slid out of the
## exclusion rectangles (hotbar, vitals, mission line).
func rail_point(origin: Vector2, dir: Vector2) -> Vector2:
	var r := Rect2(Vector2(RAIL_X, RAIL_Y), size - Vector2(RAIL_X, RAIL_Y) * 2.0)
	var o := origin.clamp(r.position + Vector2.ONE, r.end - Vector2.ONE)
	var tmin := INF
	if dir.x > 0.0001:
		tmin = minf(tmin, (r.end.x - o.x) / dir.x)
	elif dir.x < -0.0001:
		tmin = minf(tmin, (r.position.x - o.x) / dir.x)
	if dir.y > 0.0001:
		tmin = minf(tmin, (r.end.y - o.y) / dir.y)
	elif dir.y < -0.0001:
		tmin = minf(tmin, (r.position.y - o.y) / dir.y)
	var p := o + dir * (tmin if tmin != INF else 0.0)
	var ex := _exclusions()
	if not _excluded(p, ex):
		return p
	# slide along the rail (both ways, 8 px steps) to the nearest free point
	var per := 2.0 * (r.size.x + r.size.y)
	var t0 := _rail_param(r, p)
	var step := 8.0
	var k := 1
	while float(k) * step < per * 0.5:
		for sgn: float in [1.0, -1.0]:
			var q := _rail_at(r, fposmod(t0 + sgn * float(k) * step, per))
			if not _excluded(q, ex):
				return q
		k += 1
	return p


func _excluded(p: Vector2, ex: Array) -> bool:
	for e: Rect2 in ex:
		if e.has_point(p):
			return true
	return false


## Perimeter parameter of a point on the rail rectangle (clockwise from the top-left corner).
func _rail_param(r: Rect2, p: Vector2) -> float:
	var d := [absf(p.y - r.position.y), absf(p.x - r.end.x), absf(p.y - r.end.y), absf(p.x - r.position.x)]
	var side := 0
	for i in 4:
		if float(d[i]) < float(d[side]):
			side = i
	match side:
		0: return clampf(p.x - r.position.x, 0.0, r.size.x)
		1: return r.size.x + clampf(p.y - r.position.y, 0.0, r.size.y)
		2: return r.size.x + r.size.y + clampf(r.end.x - p.x, 0.0, r.size.x)
	return 2.0 * r.size.x + r.size.y + clampf(r.end.y - p.y, 0.0, r.size.y)


func _rail_at(r: Rect2, t: float) -> Vector2:
	if t < r.size.x:
		return Vector2(r.position.x + t, r.position.y)
	t -= r.size.x
	if t < r.size.y:
		return Vector2(r.end.x, r.position.y + t)
	t -= r.size.y
	if t < r.size.x:
		return Vector2(r.end.x - t, r.end.y)
	t -= r.size.x
	return Vector2(r.position.x, r.end.y - minf(t, r.size.y))


func _exclusions() -> Array:
	var out: Array = []
	if hud == null:
		return out
	var list: Array = hud.call("exclusion_rects")
	for e: Rect2 in list:
		out.append(e)
	return out


# ------------------------------------------------------------------ events
func _on_hit_from(dir: Vector3, amount: float) -> void:
	var p := GameFlow.local_player() as Player
	if p == null or dir.length() < 0.001:
		return
	_hits.append({"t": _t, "angle": _ground_angle(p.global_position, p.global_position + dir), "amount": amount})
	_last_hit_t = _t


## Angle (rad) on the screen ground ellipse from `a` toward `b`.
func _ground_angle(a: Vector3, b: Vector3) -> float:
	var sd := screen_dir(a, b)
	return atan2(sd.y / UiTokens.GROUND_RATIO, sd.x)


func _on_objective(_m: StringName, step_id: StringName, what: StringName) -> void:
	if what != &"completed" and what != &"mission_done" and what != &"progress":
		return
	var p := GameFlow.local_player() as Player
	if p == null or mlog == null:
		return
	var pos := p.global_position + Vector3(0, 2.2, 0)
	for m: Dictionary in mlog.missions:
		for s: Dictionary in m.get("steps", []):
			if str(s.get("id")) == String(step_id) and what != &"progress":
				var t := mlog.targets_of(s, p.global_position, 1)
				if not t.is_empty() and (t[0]["pos"] as Vector3).distance_to(p.global_position) < 30.0:
					pos = (t[0]["pos"] as Vector3) + Vector3(0, 1.2, 0)
	_checks.append({"pos": pos, "t": _t})


# ------------------------------------------------------------------ update
func _process(delta: float) -> void:
	_t += delta
	var p := GameFlow.local_player() as Player
	# stamina arc alpha: visible below 100, 1 s after refilling it fades
	if p != null and p.state != null:
		if p.state.stamina < Balance.STAMINA_MAX - 0.5:
			_stamina_full_t = _t
			_stamina_a = minf(_stamina_a + delta / UiTokens.T_VITAL[0], 1.0)
		elif _t - _stamina_full_t > UiTokens.T_STAMINA_FULL:
			_stamina_a = maxf(_stamina_a - delta / UiTokens.T_VITAL[2], 0.0)
	# prompt target (nearest interactable within 2.5 m, or the hovered one when close), 5 Hz
	_scan_t += delta
	if _scan_t >= 0.2:
		_scan_t = 0.0
		_scan_prompt(p)
	var want := _prompt_target != null and is_instance_valid(_prompt_target)
	_prompt_a = move_toward(_prompt_a, 1.0 if want else 0.0, delta / (UiTokens.T_PROMPT[0] if want else UiTokens.T_PROMPT[2]))
	# teammate fades
	if team != null:
		var seen := {}
		for m: Dictionary in team.mates:
			var o := TeamTracker.player_of(m)
			if o == null:
				continue
			var id := o.peer_id
			seen[id] = true
			var on := _mate_wanted(m)
			var a := float(_mate_a.get(id, 0.0))
			_mate_a[id] = move_toward(a, 1.0 if on else 0.0, delta / (UiTokens.T_TEAM[0] if on else UiTokens.T_TEAM[2]))
		for id in _mate_a.keys():
			if not seen.has(id):
				_mate_a.erase(id)
		for id in downed_seen.keys():
			var still := false
			for m: Dictionary in team.mates:
				var o2 := TeamTracker.player_of(m)
				if o2 != null and o2.peer_id == int(id) and bool(m["downed"]):
					still = true
			if not still:
				downed_seen.erase(id)
	_acc += delta
	if _acc >= PERIOD or delta == 0.0:   # 30 Hz; every frame while the clock is frozen (time_scale 0)
		_acc = 0.0
		queue_redraw()


func _mate_wanted(m: Dictionary) -> bool:
	if bool(m["downed"]):
		return false   # the downed indicator takes over
	if vis != null and vis.info_active:
		return true
	var far := UiTokens.TEAM_FAR if WorldState.weather_now() != &"blizzard" else 10.0
	return float(m["dist"]) > far or bool(m["hurt"]) or bool(m["talking"])


func _scan_prompt(p: Player) -> void:
	_prompt_target = null
	_prompt_label = ""
	if p == null or p.dead or p.downed or p.interactor == null or not GameFlow.in_game:
		return
	if p.placement != null and p.placement.active:
		return
	var it: Interactor = p.interactor
	var best: InteractableComponent = null
	if it.target != null and is_instance_valid(it.target) and it.target.distance_to(p) <= UiTokens.INTERACT_RANGE and it.target.can_interact(p):
		best = it.target
	else:
		var bd := UiTokens.INTERACT_RANGE
		for n in get_tree().get_nodes_in_group("interactable"):
			var comp := InteractableComponent.find_from(n)
			if comp == null or not is_instance_valid(comp) or not comp.can_interact(p):
				continue
			var d := comp.distance_to(p)
			if d < bd:
				bd = d
				best = comp
	if best != null:
		_prompt_target = best
		_prompt_label = best.get_label(p)
	prompt_text = _prompt_label


# ------------------------------------------------------------------ draw
func _draw() -> void:
	var p := GameFlow.local_player() as Player
	if p == null or not p.is_inside_tree() or hud == null:
		return
	var me := p.global_position
	var feet := project(me)
	var info := vis != null and vis.info_active
	var acc: Dictionary = accent.accent if accent != null else {}
	var acc_kind: StringName = acc.get("kind", &"")
	# --- damage arcs on the ground ellipse around the survivor
	if feet != Vector2.INF:
		var rx := _ground_rx(me, 1.8)
		var i := 0
		while i < _hits.size():
			var h: Dictionary = _hits[i]
			var age := _t - float(h["t"])
			if age > UiTokens.T_DAMAGE_ARC:
				_hits.remove_at(i)
				continue
			var ang := float(h["angle"])
			if not is_nan(ang):
				var a := 1.0 - age / UiTokens.T_DAMAGE_ARC
				var w := clampf(2.0 + float(h["amount"]) * 0.12, 2.0, 5.0)
				Whisper.ground_arc(self, feet, rx, ang - 0.42, ang + 0.42, Color(UiTokens.BLOOD, 0.18 * a), w + 6.0)
				Whisper.ground_arc(self, feet, rx, ang - 0.42, ang + 0.42, Color(UiTokens.BLOOD, 0.95 * a), w)
			i += 1
		# --- stamina arc at the right shoulder
		if _stamina_a > 0.002 and p.state != null:
			var cam := _cam()
			var sp := project(me + (cam.global_basis.x if cam != null else Vector3.RIGHT) * 0.5 + Vector3(0, 1.55, 0))
			if sp != Vector2.INF:
				var v := p.state.stamina / Balance.STAMINA_MAX
				var col := UiTokens.WARN if p.state.stamina < Balance.STAMINA_MIN_RUN else UiTokens.INK_RGB
				draw_arc(sp, UiTokens.STAMINA_RING * 0.5, 0.0, TAU, 32, Color(UiTokens.INK_RGB, 0.25 * _stamina_a), 2.0, true)
				draw_arc(sp, UiTokens.STAMINA_RING * 0.5, -PI * 0.5, -PI * 0.5 + TAU * clampf(v, 0.0, 1.0), 32, Color(col, _stamina_a), 2.0, true)
	# --- completed step ✓ with a widening ring (600 ms)
	var ci := 0
	while ci < _checks.size():
		var c: Dictionary = _checks[ci]
		var age := _t - float(c["t"])
		if age > 1.2:
			_checks.remove_at(ci)
			continue
		var q := project(c["pos"])
		if q != Vector2.INF:
			var a := clampf(1.0 - maxf(age - 0.6, 0.0) / 0.6, 0.0, 1.0)
			var ring_k := clampf(age / 0.6, 0.0, 1.0)
			draw_arc(q, 12.0 * (1.0 + 0.8 * ring_k), 0.0, TAU, 32, Color(UiTokens.ACCENT, (1.0 - ring_k) * 0.9), 1.5, true)
			Whisper.draw_icon(self, "check", q, 20.0, UiTokens.ACCENT_TEXT, a)
		ci += 1
	# --- heat sources while freezing
	if accent != null:
		for hi in accent.heat.size():
			var h: Dictionary = accent.heat[hi]
			var hq := project((h["pos"] as Vector3) + Vector3(0, 1.0, 0))
			if not _on_screen(hq):
				continue
			var is_acc := acc_kind == &"heat" and hi == 0
			var col := UiTokens.ACCENT if is_acc else UiTokens.INK_70
			Whisper.marker(self, hq, &"heat", UiTokens.DIAMOND, col, is_acc)
			var label := str(h["label"])
			var dist := UiTokens.distance(float(h["dist"]))
			var lw := UiStyle.text_width(&"item_name", label + "  ")
			var dw := UiStyle.text_width(&"text_num", dist)
			var x0 := hq.x - (lw + dw) * 0.5
			UiStyle.draw_text(self, &"item_name", Vector2(x0, hq.y + 30.0), label, UiTokens.ACCENT_TEXT if is_acc else UiTokens.INK_70)
			UiStyle.draw_text(self, &"text_num", Vector2(x0 + lw, hq.y + 30.0), dist, UiTokens.INK)
	# --- tracked objective on screen (unless a heat marker already sits there: the stove is both)
	var obj := mlog.tracked_target(me) if mlog != null else {}
	if not obj.is_empty():
		var op: Vector3 = obj["pos"]
		var od := Vector2(op.x - me.x, op.z - me.z).length()
		var oq := project(op + Vector3(0, 1.0, 0))
		var covered := false
		if accent != null:
			for h: Dictionary in accent.heat:
				if (h["pos"] as Vector3).distance_to(op) < 3.0:
					covered = true
		if not covered and od > UiTokens.MARKER_NEAR and od <= UiTokens.MARKER_RANGE and _on_screen(oq):
			var is_acc := acc_kind == &"objective"
			Whisper.marker(self, oq, &"objective", UiTokens.DIAMOND, UiTokens.ACCENT if is_acc else UiTokens.INK, true, 1.0 if is_acc else 0.85)
			var mouse := get_local_mouse_position()
			if info or (not HudInput.gamepad and mouse.distance_to(oq) < 48.0):
				var t := "%s · %s" % [str(obj["label"]), UiTokens.distance(od)]
				var tw := UiStyle.text_width(&"name", t)
				UiStyle.draw_text(self, &"name", Vector2(oq.x - tw * 0.5, oq.y - 14.0), t, UiTokens.INK)
		# the step's other targets as faint diamonds with Info
		if info and mlog != null:
			var m := mlog.tracked()
			var extra := mlog.targets_of(Missions.current_step(m), me, 3)
			for ti in range(1, extra.size()):
				var eq := project((extra[ti]["pos"] as Vector3) + Vector3(0, 1.0, 0))
				if _on_screen(eq):
					Whisper.diamond(self, eq, 9.0, UiTokens.INK_50, false)
	# --- teammates (far, hurt, talking, Info) and the downed indicator
	if team != null:
		var cb := bool(UiSettings.get_value("colorblind"))
		for m: Dictionary in team.mates:
			var o := TeamTracker.player_of(m)
			if o == null:
				continue
			if bool(m["downed"]):
				_draw_downed(p, m, acc_kind == &"downed" and acc.get("player") == o)
				continue
			var a := float(_mate_a.get(o.peer_id, 0.0))
			if a <= 0.002:
				continue
			var q := project(o.global_position + Vector3(0, 2.1, 0))
			if not _on_screen(q):
				continue
			var col := UiTokens.player_color(int(m["color"]), cb)
			draw_circle(q + Vector2(0, 1), UiTokens.PLAYER_DOT * 0.5 + 1.0, Color(0, 0, 0, 0.4 * a))
			draw_circle(q, UiTokens.PLAYER_DOT * 0.5, Color(col, a))
			draw_circle(q, UiTokens.PLAYER_DOT * 0.5 + 3.0, Color(col, 0.18 * a))
			var nm := str(m["name"])
			var dist := UiTokens.distance(float(m["dist"]))
			var nw := UiStyle.text_width(&"name", nm + " ")
			var dw := UiStyle.text_width(&"name", dist)
			var x0 := q.x - (nw + dw) * 0.5
			UiStyle.draw_text(self, &"name", Vector2(x0, q.y + 26.0), nm, UiTokens.player_text_color(int(m["color"])), HORIZONTAL_ALIGNMENT_LEFT, -1.0, a)
			UiStyle.draw_text(self, &"name", Vector2(x0 + nw, q.y + 26.0), dist, UiTokens.INK, HORIZONTAL_ALIGNMENT_LEFT, -1.0, a)
			if bool(m["hurt"]):
				Whisper.draw_icon(self, "thermo" if o.cold else "heart", Vector2(x0 - 12.0, q.y + 20.0), 14.0, UiTokens.COLD if o.cold else UiTokens.BLOOD, a)
			if bool(m["talking"]):
				var tx := str(m["text"])
				if tx.length() > 42:
					tx = tx.substr(0, 41) + "…"
				var tw := UiStyle.text_width(&"whisper", tx)
				UiStyle.draw_text(self, &"whisper", Vector2(q.x - tw * 0.5, q.y - 12.0), tx, UiTokens.INK, HORIZONTAL_ALIGNMENT_LEFT, -1.0, a)
	# --- H3: pings and the P0 notices that live in the world
	_draw_pings(p, info)
	_draw_p0(p)
	# --- interaction prompt (within 2.5 m) / cursor context label (mouse)
	_draw_prompt(p)
	# --- the one edge marker (+ faint destinations with Info)
	_draw_edge(p, feet, acc, info)


func _bleed_of(acc: Dictionary) -> int:
	var v: Variant = acc.get("player")
	if v == null or not is_instance_valid(v):
		return 0
	return int((v as Player).bleed)


func _ground_rx(at: Vector3, metres: float) -> float:
	var cam := _cam()
	var a := project(at)
	var b := project(at + (cam.global_basis.x if cam != null else Vector3.RIGHT) * metres)
	if a == Vector2.INF or b == Vector2.INF:
		return 90.0
	return clampf(a.distance_to(b), 30.0, 240.0)


func _draw_downed(me: Player, m: Dictionary, is_accent: bool) -> void:
	var o := TeamTracker.player_of(m)
	if o == null:
		return
	var col := UiTokens.ACCENT if is_accent else UiTokens.INK_70
	var ground := project(o.global_position)
	if not _on_screen(ground, 0.0):
		return
	downed_drawn += 1
	if not downed_seen.has(o.peer_id):
		downed_seen[o.peer_id] = Time.get_ticks_msec()
	var rx := _ground_rx(o.global_position, UiTokens.DOWNED_RING_M)
	Whisper.ground_ellipse(self, ground, rx, Color(col, 0.85), 1.5)
	var c := ground + Vector2(0, rx * UiTokens.GROUND_RATIO + 28.0)
	var maxb := Balance.DOWNED_BLEED
	var frac := clampf(float(m["bleed"]) / maxb, 0.0, 1.0)
	var being_revived := o.revive_by != 0
	Whisper.ring(self, c, UiTokens.RING_DOWNED, (float(o.revive_pct) / 100.0) if being_revived else frac, col, 2.0)
	Whisper.draw_icon(self, "skull", c, 22.0, UiTokens.ACCENT_TEXT if is_accent else UiTokens.INK)
	var nm := str(m["name"]) + " "
	var secs := "%d s" % int(m["bleed"]) if not being_revived else "%d %%" % o.revive_pct
	var nw := UiStyle.text_width(&"name_l", nm)
	var sw := UiStyle.text_width(&"name_l", secs)
	UiStyle.draw_text(self, &"name_l", Vector2(c.x - (nw + sw) * 0.5, c.y + 46.0), nm, UiTokens.ACCENT_TEXT if is_accent else UiTokens.INK)
	UiStyle.draw_text(self, &"name_l", Vector2(c.x - (nw + sw) * 0.5 + nw, c.y + 46.0), secs, UiTokens.INK)
	# "mantén X para reanimar · 6 m" (the hold ring fills while this player revives)
	var d := Vector2(o.global_position.x - me.global_position.x, o.global_position.z - me.global_position.z).length()
	var pad := HudInput.gamepad
	var g := "X" if pad else "R"
	var t1 := "mantén"
	var t2 := "para reanimar"
	var t3 := " · %s" % UiTokens.distance(d) if d > Balance.REVIVE_RANGE else ""
	var w1 := UiStyle.text_width(&"whisper", t1)
	var w2 := UiStyle.text_width(&"whisper", t2)
	var w3 := UiStyle.text_width(&"text_num", t3)
	var gw := 26.0
	var total := w1 + 8.0 + gw + 8.0 + w2 + w3
	var x := c.x - total * 0.5
	var y := c.y + 74.0
	UiStyle.draw_text(self, &"whisper", Vector2(x, y), t1, UiTokens.INK)
	x += w1 + 8.0
	var reviving := me.interactor != null and int(me.interactor.get("_reviving")) == o.peer_id
	var gc := Vector2(x + gw * 0.5, y - 6.0)
	Whisper.glyph(self, gc, g, pad, 1.0, 24.0)
	if reviving:
		Whisper.hold_ring(self, gc, float(o.revive_pct) / 100.0, 1.0, 34.0)
	x += gw + 8.0
	UiStyle.draw_text(self, &"whisper", Vector2(x, y), t2, UiTokens.INK)
	x += w2
	if t3 != "":
		UiStyle.draw_text(self, &"text_num", Vector2(x, y), t3, UiTokens.INK_70)


func _draw_prompt(p: Player) -> void:
	var gp := HudInput.gamepad
	if _prompt_a > 0.002 and _prompt_target != null and is_instance_valid(_prompt_target):
		var anchor: Vector3 = (_prompt_target as InteractableComponent).get_ring_position() + Vector3(0, 1.2, 0)
		var q := project(anchor)
		if q != Vector2.INF:
			q = q.clamp(Vector2(UiTokens.SAFE_X, UiTokens.SAFE_Y + 20.0), size - Vector2(UiTokens.SAFE_X, UiTokens.SAFE_Y + 20.0))
			var text := _prompt_label
			var tw := UiStyle.text_width(&"whisper", text)
			var gw := 26.0 if gp else maxf(26.0, UiStyle.text_width(&"meta", "R") + 12.0)
			var total := gw + 10.0 + tw
			var x := q.x - total * 0.5
			Whisper.glyph(self, Vector2(x + gw * 0.5, q.y - 6.0), "X" if gp else "R", gp, _prompt_a)
			UiStyle.draw_text(self, &"whisper", Vector2(x + gw + 10.0, q.y), text, UiTokens.INK, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _prompt_a)
	# mouse: context label next to the cursor (hover far away, a zombie, placement)
	if gp:
		return
	var ct := _placement_text if _placement_text != "" else _cursor_text
	if ct == "" or (ct == _prompt_label and _prompt_a > 0.5):
		return
	var mp := get_local_mouse_position() + Vector2(20.0, 30.0)
	UiStyle.draw_text(self, &"whisper", mp, ct, UiTokens.INK)


func _draw_edge(p: Player, feet: Vector2, acc: Dictionary, info: bool) -> void:
	last_edge = {}
	if accent == null:
		return
	var me := p.global_position
	var origin := feet if feet != Vector2.INF else size * 0.5
	if not acc.is_empty() and accent.edge_allowed():
		var pos: Vector3 = acc["pos"]
		var q := project(pos + Vector3(0, 1.0, 0))
		if not _on_screen(q, 40.0):
			var dir := screen_dir(me, pos)
			var rp := rail_point(origin, dir)
			var kind: StringName = acc["kind"]
			var d := float(acc.get("dist", 0.0))
			var txt := UiTokens.distance(d)
			if kind == &"downed":
				txt = "%s %d s · %s" % [str(acc["label"]), _bleed_of(acc), txt]
				var dp: Variant = acc.get("player")
				if dp != null and is_instance_valid(dp) and not downed_seen.has((dp as Player).peer_id):
					downed_seen[(dp as Player).peer_id] = Time.get_ticks_msec()
			elif info or kind == &"heat":
				txt = "%s · %s" % [str(acc["label"]), txt]
			# arrow outside, diamond, then the text toward the inside of the screen
			var inward := (size * 0.5 - rp).normalized()
			Whisper.arrow(self, rp - inward * 2.0, -inward, UiTokens.ACCENT)
			var dp := rp + inward * 14.0
			Whisper.marker(self, dp, kind, UiTokens.DIAMOND, UiTokens.ACCENT, true)
			var tw := UiStyle.text_width(&"text_num", txt)
			var tx := dp.x + 14.0 if inward.x >= -0.2 else dp.x - 14.0 - tw
			var ty := dp.y + 6.0
			if absf(inward.y) > 0.8:
				tx = dp.x - tw * 0.5
				ty = dp.y + (26.0 if inward.y > 0.0 else -14.0)
			UiStyle.draw_text(self, &"text_num", Vector2(tx, ty), txt, UiTokens.INK)
			last_edge = {"kind": kind, "point": rp, "text": txt}
			edge_count += 1
	if not info or mlog == null:
		return
	# Info: the other destinations as faint diamonds on the rail
	for m: Dictionary in mlog.missions:
		if Missions.is_done(m):
			continue
		for t: Dictionary in mlog.targets_of(Missions.current_step(m), me, 3):
			var tp: Vector3 = t["pos"]
			if not acc.is_empty() and tp.is_equal_approx(acc["pos"]):
				continue
			if _on_screen(project(tp + Vector3(0, 1.0, 0)), 40.0):
				continue
			var rp2 := rail_point(origin, screen_dir(me, tp))
			Whisper.diamond(self, rp2, 9.0, UiTokens.INK_50, false)


# ------------------------------------------------------------------ H3: pings and world P0
## Pings (appendix §6.4.3): danger = ▲ in `blood` with a countdown ring (8 s); place = ⚑ in the player's colour
## (30 s); "Ana · 40 m" under it. On screen always; off screen only with Info, as a faint mark on the rail (the one
## edge marker stays the accent's, §V.1 rule 5).
func _draw_pings(p: Player, info: bool) -> void:
	if pings == null:
		return
	var list: Array = pings.get("live")
	if list.is_empty():
		return
	var me := p.global_position
	var origin := project(me)
	if origin == Vector2.INF:
		origin = size * 0.5
	var cb := bool(UiSettings.get_value("colorblind"))
	var now := float(pings.get("clock"))
	for g: Dictionary in list:
		var pos: Vector3 = g["pos"]
		var q := project(pos + Vector3(0, 1.0, 0))
		var danger: bool = g["kind"] == &"danger"
		var col: Color = UiTokens.BLOOD if danger else UiTokens.player_color(int(g.get("color", 0)), cb)
		var left := clampf((float(g["until"]) - now) / maxf(float(g["seconds"]), 0.1), 0.0, 1.0)
		var fade := clampf((float(g["until"]) - now) / 0.6, 0.0, 1.0) * clampf((now - float(g["born"])) / 0.2, 0.0, 1.0)
		if _on_screen(q, 30.0):
			pings_drawn[int(g["id"])] = true
			if danger:
				_alert_glyph(q, col, fade)
				Whisper.ring(self, q, UiTokens.PING_SIZE * 2.6, left, col, 1.5, fade, true)
			else:
				_flag_glyph(q, col, fade)
			var d := Vector2(pos.x - me.x, pos.z - me.z).length()
			var nm := str(g.get("name", ""))
			var dist := UiTokens.distance(d)
			var nw := UiStyle.text_width(&"name", nm + " ") if nm != "" else 0.0
			var dw := UiStyle.text_width(&"name", dist)
			var x0 := q.x - (nw + dw) * 0.5
			if nm != "":
				UiStyle.draw_text(self, &"name", Vector2(x0, q.y + 30.0), nm, UiTokens.player_text_color(int(g.get("color", 0))), HORIZONTAL_ALIGNMENT_LEFT, -1.0, fade)
			UiStyle.draw_text(self, &"name", Vector2(x0 + nw, q.y + 30.0), dist, UiTokens.INK, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fade)
		elif info:
			var rp := rail_point(origin, screen_dir(me, pos))
			if danger:
				_alert_glyph(rp, Color(col, 0.7), fade * 0.8, 0.7)
			else:
				Whisper.diamond(self, rp, 9.0, Color(col, 0.6), false, fade)


## ▲ with a "!" drawn with lines (Barlow has the glyph, but a drawn one keeps the stroke of the line icons).
func _alert_glyph(c: Vector2, col: Color, a: float, k: float = 1.0) -> void:
	var h := UiTokens.PING_SIZE * k
	var pts := PackedVector2Array([c + Vector2(0, -h), c + Vector2(h * 0.95, h * 0.72), c + Vector2(-h * 0.95, h * 0.72), c + Vector2(0, -h)])
	var sh := PackedVector2Array()
	for v in pts:
		sh.append(v + Vector2(0, 1))
	draw_polyline(sh, Color(0, 0, 0, 0.5 * a), 3.5, true)
	draw_polyline(pts, Color(col, col.a * a), 1.8, true)
	draw_line(c + Vector2(0, -h * 0.42), c + Vector2(0, h * 0.18), Color(col, col.a * a), 1.8, true)
	draw_circle(c + Vector2(0, h * 0.44), 1.3 * k, Color(col, col.a * a))


## ⚑ (a pole and a small pennant) in the player's colour.
func _flag_glyph(c: Vector2, col: Color, a: float) -> void:
	var h := UiTokens.PING_SIZE
	var base := c + Vector2(-h * 0.35, h * 0.8)
	var top := c + Vector2(-h * 0.35, -h * 0.9)
	draw_line(base + Vector2(0, 1), top + Vector2(0, 1), Color(0, 0, 0, 0.5 * a), 3.0, true)
	draw_line(base, top, Color(col, col.a * a), 1.6, true)
	var flag := PackedVector2Array([top, top + Vector2(h * 1.1, h * 0.35), top + Vector2(0, h * 0.75)])
	draw_colored_polygon(flag, Color(col, 0.85 * col.a * a))
	draw_arc(base, h * 0.55, 0.0, TAU, 20, Color(col, 0.5 * a), 1.2, true)


## P0 notices in the world with a point (thin ice underfoot: "!" and the words at the feet; a teammate's downed
## P0 has its own indicator, so it is skipped here).
func _draw_p0(p: Player) -> void:
	if router == null:
		return
	var list: Array = router.call("p0_world")
	for e: Dictionary in list:
		if int(e.get("peer", 0)) != 0:
			continue   # a teammate's P0: the downed indicator draws it
		var pos: Vector3 = e.get("pos", p.global_position)
		var q := project(pos + Vector3(0, 0.1, 0))
		if not _on_screen(q, 20.0):
			continue
		p0_drawn += 1
		var pl := 0.7 + 0.3 * UiMotion.pulse(_t, 1.0)
		var rx := _ground_rx(pos, 1.3)
		Whisper.ground_ellipse(self, q, rx, Color(UiTokens.WARN, 0.8 * pl), 1.5)
		var c := q + Vector2(0, rx * UiTokens.GROUND_RATIO + 26.0)
		_alert_glyph(c, UiTokens.WARN, 1.0, 0.9)
		var title := str(e.get("title", ""))
		var body := str(e.get("body", ""))
		var tw := UiStyle.text_width(&"smallcaps", title)
		UiStyle.draw_text(self, &"smallcaps", Vector2(c.x - tw * 0.5, c.y + 34.0), title, UiTokens.WARN)
		var sub := body.substr(body.find(" · ") + 3) if body.contains(" · ") else ""
		if sub != "":
			var sw := UiStyle.text_width(&"whisper", sub)
			UiStyle.draw_text(self, &"whisper", Vector2(c.x - sw * 0.5, c.y + 58.0), sub, UiTokens.INK)
