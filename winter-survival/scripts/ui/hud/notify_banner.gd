class_name NotifyBanner
extends Control
## The central notice of the HUD v2 (appendix §6.5 channel "banner", restyled for §V): no box — a line of 22 px
## Light text over a soft scrim, 104 px below the top edge, with an optional small-caps eyebrow in the tone colour
## and "2 avisos en espera" under it. Enters in 220 ms, leaves in 300 ms. Driven by `NotifyRouter`.

const TOP := 104.0
const TONES := {&"": UiTokens.INK_70, &"warn": UiTokens.WARN, &"danger": UiTokens.BLOOD, &"accent": UiTokens.ACCENT, &"cold": UiTokens.COLD}

var notice: Dictionary = {}
var waiting: int = 0
var shown: int = 0
var _a: float = 0.0
var _target: float = 0.0
var _last: Dictionary = {}
var _scrim: Scrim


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrim = Scrim.new()
	_scrim.name = "Scrim"
	_scrim.show_behind_parent = true
	add_child(_scrim)
	visible = false


func show_notice(n: Dictionary, wait: int) -> void:
	waiting = wait
	if n.is_empty():
		_target = 0.0
	else:
		notice = n
		_last = n
		_target = 1.0
		shown += 1
		visible = true
		var bw := UiStyle.text_width(&"main", str(n.get("body", "")))
		var has_title := str(n.get("title", "")) != ""
		_scrim.position = Vector2(size.x * 0.5 - bw * 0.5 - 180.0, TOP - 70.0)
		_scrim.size = Vector2(bw + 360.0, 180.0 + (26.0 if has_title else 0.0))
	queue_redraw()


func set_waiting(n: int) -> void:
	if n != waiting:
		waiting = n
		queue_redraw()


func text_now() -> String:
	return str(notice.get("body", "")) if _target > 0.0 else ""


func _process(delta: float) -> void:
	if _a == _target:
		return
	var d := UiMotion.dur(float(UiTokens.T_BANNER[0]) if _target > _a else float(UiTokens.T_BANNER[2]))
	_a = move_toward(_a, _target, delta / maxf(d, 0.001))
	modulate.a = UiMotion.ease_in_curve(_a) if _target > 0.0 else UiMotion.ease_out_curve(_a)
	if _a <= 0.0:
		visible = false
		notice = {}
	queue_redraw()


func _draw() -> void:
	var n := notice if not notice.is_empty() else _last
	if n.is_empty():
		return
	var cx := size.x * 0.5
	var y := TOP
	var title := str(n.get("title", ""))
	var body := str(n.get("body", ""))
	var bw := UiStyle.text_width(&"main", body)
	if title != "":
		var tw := UiStyle.text_width(&"smallcaps_wide", title)
		UiStyle.draw_text(self, &"smallcaps_wide", Vector2(cx - tw * 0.5, y), title, TONES.get(n.get("tone", &""), UiTokens.INK_70))
		y += 28.0
	var tone: StringName = n.get("tone", &"")
	UiStyle.draw_text(self, &"main", Vector2(cx - bw * 0.5, y + 8.0), body, UiTokens.INK if tone == &"" else Color(TONES[tone]).lerp(UiTokens.INK_RGB, 0.45))
	if waiting > 0:
		var wt := "%d %s en espera" % [waiting, "aviso" if waiting == 1 else "avisos"]
		var ww := UiStyle.text_width(&"meta", wt)
		UiStyle.draw_text(self, &"meta", Vector2(cx - ww * 0.5, y + 34.0), wt, UiTokens.INK_50)
