class_name ToastStack
extends VBoxContainer
## Column of short notifications (max 3, default 3 s).


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 4)
	alignment = BoxContainer.ALIGNMENT_BEGIN
	Events.notify.connect(show_toast)


func show_toast(text: String, seconds: float = 3.0) -> void:
	while get_child_count() >= 3:
		get_child(0).free()
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", UiTheme.flat_box(Color("#101826", 0.85), UiTheme.BORDER, 1, 3, 6))
	var l := UiTheme.label(text, 12, UiTheme.TEXT, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	add_child(p)
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.15)
	tw.tween_interval(maxf(seconds - 0.5, 0.2))
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
	tw.tween_callback(p.queue_free)
