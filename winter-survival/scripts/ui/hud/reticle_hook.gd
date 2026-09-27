class_name ReticleHook
extends Control
## Minimal stand-in for the firearm reticle and ammo readout (M5). The real ones belong to the UI lane (H3, HUD
## «Susurro»): this hook only proves the data path and stays invisible without a firearm in hand. It listens to
## Events.reticle_changed (spread°, band, aim point, radius at the aim distance, 30 Hz) and
## Events.weapon_state_changed (ammo / magazine / reserve / jam / reload) and draws a thin ring at the aim point,
## coloured by band (green < 4°, amber 4–8°, red > 8°, grey = an ally in the line), plus "12/15 · 44" under it.
## H3 replaces it: delete this node from game.gd and read the same two signals.

const COLORS := {&"green": Color(0.45, 0.9, 0.5, 0.9), &"amber": Color(1.0, 0.71, 0.33, 0.9), &"red": Color(0.95, 0.35, 0.3, 0.9),
	&"grey": Color(0.7, 0.72, 0.75, 0.8)}

var spread: float = -1.0
var band: StringName = &"green"
var aim_point: Vector3 = Vector3.ZERO
var radius_m: float = 0.0
var data: Dictionary = {}


func _ready() -> void:
	name = "ReticleHook"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	Events.reticle_changed.connect(_on_reticle)
	Events.weapon_state_changed.connect(func(d: Dictionary) -> void:
		data = d
		queue_redraw())


func _on_reticle(p_spread: float, p_band: StringName, p_aim: Vector3, p_radius: float) -> void:
	spread = p_spread
	band = p_band
	aim_point = p_aim
	radius_m = p_radius
	visible = spread >= 0.0
	queue_redraw()


func _draw() -> void:
	if spread < 0.0:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam.is_position_behind(aim_point):
		return
	var c := cam.unproject_position(aim_point)
	var edge := cam.unproject_position(aim_point + cam.global_basis.x * maxf(radius_m, 0.05))
	var r := clampf(c.distance_to(edge), 6.0, 220.0)
	var col: Color = COLORS.get(band, COLORS[&"green"])
	draw_arc(c, r, 0.0, TAU, 48, col, 1.5, true)
	draw_circle(c, 1.5, col)
	if data.is_empty():
		return
	var txt := ""
	if bool(data.get("jammed", false)):
		txt = "ENCASQUILLADA · R"
	elif float(data.get("reload_left", -1.0)) >= 0.0:
		txt = "RECARGANDO"
	else:
		txt = "%d/%d · %d" % [int(data.get("ammo", 0)), int(data.get("mag", 0)), int(data.get("reserve", 0))]
	var font := get_theme_default_font()
	draw_string(font, c + Vector2(-40, r + 18), txt, HORIZONTAL_ALIGNMENT_CENTER, 80, 13, col)
