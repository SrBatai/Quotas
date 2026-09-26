class_name ChatBox
extends Control
## Bottom-left chat: last lines fade after a while; Enter opens the input, Esc cancels.

const SHOW_LINES := 6
const FADE_AFTER := 12.0

var _lines: VBoxContainer
var _input: LineEdit
var _entries: Array[Dictionary] = []   # {"label": Label, "t": float}
var is_typing: bool:
	get: return _input != null and _input.visible


func _ready() -> void:
	theme = UiTheme.get_theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = 16
	offset_right = 420
	offset_top = -230
	offset_bottom = -110
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.alignment = BoxContainer.ALIGNMENT_END
	vb.add_theme_constant_override("separation", 2)
	add_child(vb)
	_lines = VBoxContainer.new()
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lines.add_theme_constant_override("separation", 1)
	vb.add_child(_lines)
	_input = LineEdit.new()
	_input.placeholder_text = "Escribe y pulsa Intro…"
	_input.max_length = Balance.NET_CHAT_MAX_CHARS
	_input.visible = false
	_input.text_submitted.connect(_on_submit)
	_input.add_theme_font_size_override("font_size", 12)
	vb.add_child(_input)
	Events.chat_message.connect(_on_message)


func _on_message(who: String, text: String) -> void:
	var l := UiTheme.label("%s: %s" % [who, text], 12, UiTheme.TEXT, false)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	if who == "SERVIDOR":
		l.add_theme_color_override("font_color", UiTheme.ACCENT)
	_lines.add_child(l)
	_entries.append({"label": l, "t": 0.0})
	while _entries.size() > SHOW_LINES:
		var old: Dictionary = _entries.pop_front()
		(old["label"] as Label).queue_free()


func _process(delta: float) -> void:
	for e in _entries:
		e["t"] = float(e["t"]) + delta
		var l: Label = e["label"]
		var t := float(e["t"])
		l.modulate.a = 1.0 if is_typing else clampf((FADE_AFTER + 2.0 - t) / 2.0, 0.0, 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("chat") and not _input.visible:
		_input.visible = true
		_input.grab_focus()
		get_viewport().set_input_as_handled()
	elif _input.visible and event.is_action_pressed("cancel") and event is InputEventKey:
		_close()
		get_viewport().set_input_as_handled()


func _on_submit(text: String) -> void:
	_close()
	if text.strip_edges() != "" and Chat.instance != null:
		Chat.instance.send(text)


func _close() -> void:
	_input.text = ""
	_input.visible = false
	_input.release_focus()
