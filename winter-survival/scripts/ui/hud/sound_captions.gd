class_name SoundCaptions
extends Control
## Sound captions with direction (H3; docs/research/10_hud_ux.md §V.7: «con un HUD que se oculta, los rótulos de
## sonido … de los avisos P0 pasan a ser imprescindibles»; appendix §5.8). Listens to `AudioManager.event_played`
## (event, voice, position): a captioned event becomes one whisper line bottom centre, above the hotbar —
##   "latido y estática de radio · Ana   ➚ 38 m"
## the description in ink small caps, the subject in the player's colour, then a 6 px arrow toward the source as seen
## on screen (the camera's yaw, like the edge rail) and its distance. A 2D UI sound (ui_mate_down) has no position:
## the NotifyRouter says where it comes from with `expect(event, pos, subject, peer)` right before playing it.
## 3 s per line, 3 lines at most, the same event + subject within 1.5 s refreshes its line ("×2"). Setting
## `captions`: p0 (default: the P0 ones) | all (also warnings, pings, gunfire, «te han visto») | off.
## `text_of(line)` gives the same caption as plain text with the direction in words (tests, TTS in H6).

## event -> [description, level (0 = P0, 1 = with "all")]
const CAPTIONS := {
	&"ui_mate_down": ["latido y estática de radio", 0],
	&"ui_radio_static": ["estática de radio", 0],
	&"ice_crack": ["hielo que cruje", 0],
	&"ice_break": ["hielo que se rompe", 0],
	&"ui_ping_danger": ["aviso de peligro", 1],
	&"ui_ping": ["marca", 1],
	&"ui_hazard": ["ráfaga y radio", 1],
	&"ui_warn": ["pitido de radio", 1],
	&"zombie_alert": ["gruñido: te han visto", 1],
	&"stinger_danger": ["una horda cerca", 1],
	&"gun_pistol": ["disparo", 1],
	&"gun_revolver": ["disparo", 1],
	&"gun_shotgun": ["escopetazo", 1],
	&"gun_rifle": ["disparo de rifle", 1],
	&"car_alarm": ["alarma de coche", 1],
	&"wolf_howl": ["aullido", 1],
}
const LINE_H := 30.0
## Direction words (screen sectors of 45°, 0 = right, clockwise with y down).
const DIR_WORDS := ["derecha", "detrás a la derecha", "detrás", "detrás a la izquierda", "izquierda",
	"delante a la izquierda", "delante", "delante a la derecha"]

## [{key, event, text, subject, color, pos, born, until, count, a}]
var lines: Array = []
var clock: float = 0.0
var shown: int = 0
## Tests: every caption made (plain text), newest last.
var history: Array = []
var _expect: Dictionary = {}   # event -> {pos, subject, peer, t}
var _scrim: Scrim


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrim = Scrim.new()
	_scrim.name = "Scrim"
	_scrim.show_behind_parent = true
	_scrim.strength = 0.9
	_scrim.visible = false
	add_child(_scrim)
	if not AudioManager.event_played.is_connected(_on_event):
		AudioManager.event_played.connect(_on_event)


func _exit_tree() -> void:
	if AudioManager.event_played.is_connected(_on_event):
		AudioManager.event_played.disconnect(_on_event)


## The next `event` played comes from `pos` (Vector3.INF = unknown) and is about `subject` (a player's name).
func expect(event: StringName, pos: Vector3, subject: String, peer: int = 0) -> void:
	_expect[event] = {"pos": pos, "subject": subject, "peer": peer, "t": clock}
	# the same cue may already be on screen without its source (another system played it first — CombatAudio also
	# cues a teammate's down — and the event's cooldown will drop ours): complete that line instead
	for l: Dictionary in lines:
		if l["event"] == event and str(l["subject"]) == "" and (l["pos"] as Vector3) == Vector3.INF and clock - float(l["born"]) < 1.0:
			l["subject"] = subject
			l["pos"] = pos
			l["key"] = String(event) + "|" + subject
			if subject != "":
				l["color"] = _color_of(peer, subject)
			_expect.erase(event)
			if not history.is_empty():
				history[-1] = text_of(l)
			queue_redraw()
			return


static func mode() -> StringName:
	return StringName(str(UiSettings.get_value("captions")))


func _on_event(event: StringName, _voice: Node, at: Vector3) -> void:
	if not CAPTIONS.has(event):
		return
	var lvl := int(CAPTIONS[event][1])
	var m := mode()
	if m == &"off" or (m == &"p0" and lvl > 0):
		return
	var ctx: Dictionary = _expect.get(event, {})
	if not ctx.is_empty() and clock - float(ctx["t"]) > 1.0:
		ctx = {}
	_expect.erase(event)
	var pos: Vector3 = at if at != Vector3.INF else ctx.get("pos", Vector3.INF)
	add(event, str(CAPTIONS[event][0]), str(ctx.get("subject", "")), pos, int(ctx.get("peer", 0)))


## Adds (or refreshes) a caption line.
func add(event: StringName, text: String, subject: String, pos: Vector3, peer: int = 0) -> void:
	var key := String(event) + "|" + subject
	var read := float(UiTokens.T_CAPTION[1])
	for l: Dictionary in lines:
		if clock - float(l["born"]) >= UiTokens.CAPTION_MERGE + read or l["event"] != event:
			continue
		if str(l["key"]) == key:
			l["until"] = clock + read
			l["count"] = int(l["count"]) + 1
			l["pos"] = pos
			queue_redraw()
			return
		if subject == "" or str(l["subject"]) == "":
			# the same cue replayed without its source by another system (or the source arriving late): one line
			if str(l["subject"]) == "" and subject != "":
				l["subject"] = subject
				l["key"] = key
				l["color"] = _color_of(peer, subject)
			if (l["pos"] as Vector3) == Vector3.INF:
				l["pos"] = pos
			l["until"] = maxf(float(l["until"]), clock + read)
			queue_redraw()
			return
	var col := UiTokens.INK
	if subject != "":
		col = _color_of(peer, subject)
	var l := {"key": key, "event": event, "text": text, "subject": subject, "color": col, "pos": pos, "born": clock,
		"until": clock + read, "count": 1, "a": 0.0}
	lines.append(l)
	while lines.size() > UiTokens.CAPTION_LINES:
		lines.pop_front()
	shown += 1
	history.append(text_of(l))
	if history.size() > 32:
		history.pop_front()
	queue_redraw()


func _color_of(peer: int, subject: String) -> Color:
	var me := GameFlow.local_player() as Player
	if me != null and me.get_parent() != null:
		for n in me.get_parent().get_children():
			var o := n as Player
			if o != null and (o.peer_id == peer or (peer == 0 and o.display_name == subject)):
				return UiTokens.player_text_color(o.outfit)
	return UiTokens.INK


## Screen direction toward `pos` from the local player (unit vector, y down), or Vector2.ZERO when unknown.
func direction_of(pos: Vector3) -> Vector2:
	var me := GameFlow.local_player() as Node3D
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if pos == Vector3.INF or me == null or cam == null:
		return Vector2.ZERO
	return WorldLayer.dir_on_screen(cam, me.global_position, pos)


func distance_of(pos: Vector3) -> float:
	var me := GameFlow.local_player() as Node3D
	if pos == Vector3.INF or me == null:
		return -1.0
	return Vector2(pos.x - me.global_position.x, pos.z - me.global_position.z).length()


static func dir_word(d: Vector2) -> String:
	if d == Vector2.ZERO:
		return ""
	var a := fposmod(atan2(d.y, d.x), TAU)
	return DIR_WORDS[int(round(a / (TAU / 8.0))) % 8]


## Plain-text caption: "latido y estática de radio · Ana · derecha, 38 m".
func text_of(l: Dictionary) -> String:
	var s := str(l["text"])
	if str(l["subject"]) != "":
		s += " · " + str(l["subject"])
	var pos: Vector3 = l["pos"]
	var dist := distance_of(pos)
	if dist >= 0.0:
		var w := dir_word(direction_of(pos))
		s += " · " + (w + ", " if w != "" and dist > 2.0 else "") + UiTokens.distance(dist)
	if int(l.get("count", 1)) > 1:
		s += " ×%d" % int(l["count"])
	return s


func clear() -> void:
	lines.clear()
	queue_redraw()


func _process(delta: float) -> void:
	clock += delta
	if lines.is_empty():
		if _scrim.visible:
			_scrim.visible = false
		return
	var tin := UiMotion.dur(float(UiTokens.T_CAPTION[0]))
	var tout := UiMotion.dur(float(UiTokens.T_CAPTION[2]))
	var i := 0
	var maxa := 0.0
	while i < lines.size():
		var l: Dictionary = lines[i]
		if clock < float(l["until"]):
			l["a"] = minf(float(l["a"]) + delta / tin, 1.0)
		else:
			l["a"] = float(l["a"]) - delta / tout
		if float(l["a"]) <= 0.0 and clock >= float(l["until"]):
			lines.remove_at(i)
			continue
		maxa = maxf(maxa, float(l["a"]))
		i += 1
	_scrim.visible = maxa > 0.002
	_scrim.modulate.a = maxa
	_scrim.position = Vector2(size.x * 0.5 - 420.0, size.y - LINE_H * lines.size() - 60.0)
	_scrim.size = Vector2(840.0, LINE_H * lines.size() + 110.0)
	queue_redraw()


func _draw() -> void:
	var y := size.y
	for idx in range(lines.size() - 1, -1, -1):
		var l: Dictionary = lines[idx]
		var a := float(l["a"])
		if a <= 0.002:
			y -= LINE_H
			continue
		var ease := UiMotion.ease_in_curve(a) if clock < float(l["until"]) else UiMotion.ease_out_curve(a)
		var desc := str(l["text"])
		var subj := (" · " + str(l["subject"])) if str(l["subject"]) != "" else ""
		var pos: Vector3 = l["pos"]
		var dist := distance_of(pos)
		var dir := direction_of(pos)
		var dtxt := UiTokens.distance(dist) if dist >= 0.0 else ""
		if int(l["count"]) > 1:
			dtxt += " ×%d" % int(l["count"])
		var wd := UiStyle.text_width(&"smallcaps", desc)
		var ws := UiStyle.text_width(&"whisper", subj)
		var wt := UiStyle.text_width(&"text_num", dtxt)
		var arrow_w := 22.0 if dir != Vector2.ZERO and dist > 2.0 else 0.0
		var total := wd + ws + (arrow_w + wt if dtxt != "" else 0.0) + (12.0 if dtxt != "" else 0.0)
		var x := size.x * 0.5 - total * 0.5
		var by := y - 8.0
		UiStyle.draw_text(self, &"smallcaps", Vector2(x, by), desc, UiTokens.INK_70, HORIZONTAL_ALIGNMENT_LEFT, -1.0, ease)
		x += wd
		if subj != "":
			UiStyle.draw_text(self, &"whisper", Vector2(x, by), subj, l["color"], HORIZONTAL_ALIGNMENT_LEFT, -1.0, ease)
			x += ws
		if dtxt != "":
			x += 12.0
			if arrow_w > 0.0:
				_dir_arrow(Vector2(x + 9.0, by - 6.0), dir, UiTokens.INK, ease)
				x += arrow_w
			UiStyle.draw_text(self, &"text_num", Vector2(x, by), dtxt, UiTokens.INK, HORIZONTAL_ALIGNMENT_LEFT, -1.0, ease)
		y -= LINE_H


## A readable direction arrow (a 1.5 px stem and a filled head, 14 px long) pointing along `d` (screen, y down).
func _dir_arrow(c: Vector2, d: Vector2, col: Color, a: float) -> void:
	var u := d.normalized()
	var n := Vector2(-u.y, u.x)
	var tail := c - u * 7.0
	var tip := c + u * 7.0
	var head := PackedVector2Array([tip, tip - u * 6.0 + n * 4.0, tip - u * 6.0 - n * 4.0])
	var sh := PackedVector2Array()
	for q in head:
		sh.append(q + Vector2(0, 1))
	draw_line(tail + Vector2(0, 1), tip - u * 4.0 + Vector2(0, 1), Color(0, 0, 0, 0.5 * a), 3.0, true)
	draw_colored_polygon(sh, Color(0, 0, 0, 0.5 * a))
	draw_line(tail, tip - u * 4.0, Color(col, col.a * a), 1.5, true)
	draw_colored_polygon(head, Color(col, col.a * a))
