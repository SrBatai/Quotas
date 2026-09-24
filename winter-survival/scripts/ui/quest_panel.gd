class_name QuestPanel
extends PanelContainer
## Right-side quest tracker: title, index/total, progress bar, previous / current / next steps.

var _small: Label
var _big: Label
var _counter: Label
var _bar: ProgressBar
var _rows: VBoxContainer
var _flash: float = 0.0


func _ready() -> void:
	theme = UiTheme.get_theme()
	custom_minimum_size = Vector2(250, 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vb)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(head)
	_small = UiTheme.label("PRIMER DÍA", 9, UiTheme.TEXT_2, false, true, true)
	head.add_child(_small)
	head.add_child(UiTheme.hspacer())
	_counter = UiTheme.label("0/8", 9, UiTheme.TEXT_2, true)
	head.add_child(_counter)
	_big = UiTheme.label("SOBREVIVE", 17, UiTheme.TEXT, false, true, true)
	vb.add_child(_big)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(0, 3)
	_bar.show_percentage = false
	_bar.min_value = 0
	_bar.max_value = 1
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(_bar)
	vb.add_child(UiTheme.spacer(2, 4))
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 4)
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(_rows)
	UiTheme.add_ice_edge(self)
	Events.quest_updated.connect(_on_quest_updated)
	Events.quest_step_completed.connect(func(_i: int) -> void: _flash = 0.5)
	var st: PlayerState = GameFlow.local_state()
	if st != null and not st.quest_state.is_empty():
		_on_quest_updated(st.quest_state)
	else:
		_on_quest_updated({"title_small": "", "title_big": "SOBREVIVE", "index": 0, "total": 0, "steps": [], "day_completed": false})


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash -= delta
		modulate = Color(1, 1, 1).lerp(Color(1.6, 1.5, 1.2), clampf(_flash * 2.0, 0.0, 1.0))
	elif modulate != Color.WHITE:
		modulate = Color.WHITE


func _on_quest_updated(state: Dictionary) -> void:
	_small.text = state["title_small"]
	_big.text = state["title_big"]
	var total: int = state["total"]
	var idx: int = state["index"]
	_counter.text = "%d/%d" % [idx, total]
	_bar.value = float(idx) / float(maxi(total, 1))
	for c in _rows.get_children():
		c.queue_free()
	var steps: Array = state["steps"]
	if bool(state.get("day_completed", false)) or idx >= total:
		if total > 0:
			_rows.add_child(_row(steps[total - 1], 2))
		var done := UiTheme.label("¡Día completado!", 12, UiTheme.ACCENT, true)
		_rows.add_child(done)
		return
	if idx > 0:
		_rows.add_child(_row(steps[idx - 1], 2))
	_rows.add_child(_row(steps[idx], 1))
	if idx + 1 < total:
		_rows.add_child(_row(steps[idx + 1], 0))


## kind: 2 = done, 1 = current, 0 = next
func _row(step: Dictionary, kind: int) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mark := Control.new()
	mark.custom_minimum_size = Vector2(12, 12)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.set_script(preload("res://scripts/ui/quest_mark.gd"))
	mark.set("kind", kind)
	hb.add_child(mark)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(vb)
	var color := UiTheme.TEXT if kind == 1 else UiTheme.TEXT_2
	if kind == 0:
		color = Color("#93A6BF", 0.7)
	var title := UiTheme.label(step["title"], 11, color, kind == 1)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(title)
	if kind == 2:
		var strike := ColorRect.new()
		strike.color = UiTheme.TEXT_2
		strike.mouse_filter = Control.MOUSE_FILTER_IGNORE
		strike.position = Vector2(0, 8)
		strike.size = Vector2(title.get_theme_font("font").get_string_size(title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x, 1)
		title.add_child(strike)
	if kind == 1:
		var hint := UiTheme.label(step["hint"], 9, UiTheme.TEXT_2)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(hint)
	return hb
