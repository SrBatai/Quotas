class_name ReticleHook
extends Control
## Firearm reticle of the HUD v2 «Susurro» (H3, the M5 hook; ARQ v2 §15.5 "Dispersión"). Class and node name are
## the M5 stand-in's (game.gd adds it to the UI layer as "ReticleHook"; the M5 smoke checks it exists), the drawing
## is now the HUD's: a thin 1.5 px ring at the aim point whose radius is the spread cone at the aim distance, four
## short ticks and a centre dot, coloured by band — green < 4°, amber 4–8°, red > 8°, grey = an ally in the line
## (Events.reticle_changed, 30 Hz) — with the HUD's soft shadow. While reloading a second arc fills around it; a jam
## says «encasquillada · R» under it in warn small caps. The ammo count lives on the hotbar line (Hotbar).
## Drawn in 1920 × 1080 reference pixels scaled like the HUD (k = min(w/1920, h/1080) × UI scale). Hidden without a
## firearm in hand (spread < 0).

const COLORS := {&"green": UiTokens.RETICLE_GREEN, &"amber": UiTokens.RETICLE_AMBER, &"red": UiTokens.RETICLE_RED,
	&"grey": UiTokens.RETICLE_GREY}

var spread: float = -1.0
var band: StringName = &"green"
var aim_point: Vector3 = Vector3.ZERO
var radius_m: float = 0.0
var data: Dictionary = {}
## Tests: the ring radius (reference px) and colour of the last draw.
var drawn_radius: float = 0.0
var drawn_color: Color = Color.TRANSPARENT
var draws: int = 0
var _k: float = 1.0


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
	_process(0.0)   # the scale is right on the first draw too
	queue_redraw()


func color_of(b: StringName) -> Color:
	return COLORS.get(b, UiTokens.RETICLE_GREEN)


func _process(_delta: float) -> void:
	if not visible:
		return
	var vp := get_viewport_rect().size
	_k = maxf(minf(vp.x / UiTokens.REF_SIZE.x, vp.y / UiTokens.REF_SIZE.y) * UiSettings.get_instance().ui_scale(), 0.05)


func _draw() -> void:
	if spread < 0.0:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam.is_position_behind(aim_point):
		return
	var k := _k
	var c := cam.unproject_position(aim_point)
	var edge := cam.unproject_position(aim_point + cam.global_basis.x * maxf(radius_m, 0.05))
	var r := clampf(c.distance_to(edge), 7.0 * k, 220.0 * k)
	var col := color_of(band)
	var w := UiTokens.RETICLE_STROKE * maxf(k, 0.7)
	draws += 1
	drawn_radius = r / k
	drawn_color = col
	# shadow, ring, ticks, dot
	draw_arc(c + Vector2(0, 1), r, 0.0, TAU, 56, Color(0, 0, 0, 0.45), w + 1.5, true)
	draw_arc(c, r, 0.0, TAU, 56, Color(col, 0.9), w, true)
	var tick := 5.0 * k
	for i in 4:
		var d := Vector2.from_angle(PI * 0.5 * float(i))
		draw_line(c + d * (r + 2.0 * k) + Vector2(0, 1), c + d * (r + 2.0 * k + tick) + Vector2(0, 1), Color(0, 0, 0, 0.45), w + 1.0, true)
		draw_line(c + d * (r + 2.0 * k), c + d * (r + 2.0 * k + tick), Color(col, 0.9), w, true)
	draw_circle(c + Vector2(0, 1), 2.2 * k, Color(0, 0, 0, 0.45))
	draw_circle(c, 1.6 * k, Color(col, 0.95))
	if data.is_empty():
		return
	# reload progress: a second arc just outside the ring
	var rl := float(data.get("reload_left", -1.0))
	var rt := float(data.get("reload_total", 0.0))
	if rl >= 0.0 and rt > 0.0:
		var f := clampf(1.0 - rl / rt, 0.0, 1.0)
		draw_arc(c, r + 9.0 * k, -PI * 0.5, -PI * 0.5 + TAU * f, 48, Color(UiTokens.INK_RGB, 0.85), w, true)
	if bool(data.get("jammed", false)):
		var txt := "encasquillada · R"
		var ls := UiStyle.settings(&"smallcaps")
		var fs := int(round(float(UiStyle.size_of(&"smallcaps")) * k))
		var font: Font = ls.font if ls != null and ls.font != null else get_theme_default_font()
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var p := c + Vector2(-tw * 0.5, r + 26.0 * k)
		draw_string(font, p + Vector2(0, 1), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.6))
		draw_string(font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTokens.WARN)
