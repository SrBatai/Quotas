extends Node3D
## Decorative closed A-frame cabin with a warm window at night.

var _model: Node3D
var _spills: Array[WindowSpill] = []


func _ready() -> void:
	_model = Assets.spawn_model("a_frame_cabin")
	$Visual.add_child(_model)
	if not Assets.is_placeholder(_model) and _model.find_child("ColBody", true, false) == null:
		Placeholders._col_convex(_model, "ColBody", PackedVector3Array([
			Vector3(-3.0, 0, -3.5), Vector3(3.0, 0, -3.5), Vector3(0, 6.0, -3.5),
			Vector3(-3.0, 0, 3.5), Vector3(3.0, 0, 3.5), Vector3(0, 6.0, 3.5)]))
	# warm spill on the snow in front of the window (spot + projector + wash; DayNight scales it by hour)
	_spills = WindowSpill.attach_to_windows(self, _model, 6.0, 8.0)
	Events.time_changed.connect(_on_time)
	_on_time(WorldState.day_now(), WorldState.hour_now(), WorldState.is_night_now())


func _on_time(_day: int, hour: float, _night: bool) -> void:
	var dark := hour >= 17.5 or hour < 6.5
	for sp in _spills:
		sp.set_enabled(dark)
	Assets.override_named(_model, "window", Assets.get_glow_material() if dark else null)
