class_name NetDebugHud
extends Label
## F3: RTT, packet loss, kB/s in/out, prediction corrections per second, peers, pending inputs (ARQ v2 §18).

var _corrections_last: int = 0
var _corr_per_s: float = 0.0
var _timer: float = 0.0


func _ready() -> void:
	theme = UiTheme.get_theme()
	add_theme_font_size_override("font_size", 11)
	add_theme_color_override("font_color", Color("#DCEBFA"))
	add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	add_theme_constant_override("shadow_offset_x", 1)
	add_theme_constant_override("shadow_offset_y", 1)
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(12, 12)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = OS.get_cmdline_user_args().has("--net-hud")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("net_debug"):
		visible = not visible


func _process(delta: float) -> void:
	if not visible:
		return
	_timer += delta
	var p := GameFlow.local_player()
	if _timer >= 1.0:
		_timer = 0.0
		if p != null:
			var c: int = p.net.corrections
			_corr_per_s = float(c - _corrections_last)
			_corrections_last = c
	var s := Net.stats
	var role := {Net.Role.NONE: "none", Net.Role.OFFLINE: "offline (local server)", Net.Role.SERVER: "server", Net.Role.CLIENT: "client"}[Net.role]
	var lines := ["RED: %s  peers=%d" % [role, int(s["peers"])]]
	if Net.is_client:
		lines.append("RTT %.0f ms  pérdida %.1f %%" % [float(s["rtt"]), float(s["loss"])])
	lines.append("bajada %.2f kB/s  subida %.2f kB/s" % [float(s["in_kbps"]), float(s["out_kbps"])])
	if p != null:
		lines.append("correcciones/s %.0f (total %d, último error %.3f m)  inputs pendientes %d" % [
			_corr_per_s, p.net.corrections, p.net.last_error, p.net.pending_count()])
		lines.append("pos %s  yaw %.2f" % [p.global_position.snapped(Vector3(0.01, 0.01, 0.01)), p.aim_yaw])
	text = "\n".join(lines)
