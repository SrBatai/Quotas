extends Node3D
## Decorative closed A-frame cabin with a warm window at night.

var _model: Node3D
var _light: OmniLight3D


func _ready() -> void:
	_model = Assets.spawn_model("a_frame_cabin")
	$Visual.add_child(_model)
	if not Assets.is_placeholder(_model) and _model.find_child("ColBody", true, false) == null:
		Placeholders._col_convex(_model, "ColBody", PackedVector3Array([
			Vector3(-3.0, 0, -3.5), Vector3(3.0, 0, -3.5), Vector3(0, 6.0, -3.5),
			Vector3(-3.0, 0, 3.5), Vector3(3.0, 0, 3.5), Vector3(0, 6.0, 3.5)]))
	_light = OmniLight3D.new()
	_light.light_color = Color("#FFB454")
	_light.omni_range = 8.0
	_light.light_energy = 2.5
	_light.shadow_enabled = false
	_light.position = Vector3(-0.7, 3.0, -3.9)
	add_child(_light)
	Events.time_changed.connect(_on_time)
	_on_time(GameState.day, GameState.hour, GameState.is_night)


func _on_time(_day: int, hour: float, _night: bool) -> void:
	var dark := hour >= 17.5 or hour < 6.5
	_light.visible = dark
	Assets.override_named(_model, "window", Assets.get_glow_material() if dark else null)
