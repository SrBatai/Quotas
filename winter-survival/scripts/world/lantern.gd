class_name Lantern
extends Node3D
## Porch lantern: warm flickering light at night, glass glows.

var light: LightFlicker
var _model: Node3D


func _ready() -> void:
	_model = Assets.spawn_model("lantern")
	add_child(_model)
	light = LightFlicker.new()
	light.light_color = Color("#FFB454")
	light.base_energy = 0.5  # lights the porch, not the clearing (doc 06 §2 d: low energy)
	light.omni_range = 5.5
	light.omni_attenuation = 1.3
	light.amount = 0.12
	light.shadow_priority = 0  # first in the omni-shadow budget (alto: railing shadows on the snow)
	add_child(light)
	var anchor: Node3D = _model.find_child("LightAnchor", true, false)
	light.position = anchor.position if anchor != null else Vector3(0, -0.23, 0)
	Events.time_changed.connect(_on_time)
	_on_time(WorldState.day_now(), WorldState.hour_now(), WorldState.is_night_now())


func _on_time(_day: int, hour: float, _night: bool) -> void:
	var dark := hour >= 17.5 or hour < 6.5
	light.visible = dark
	Assets.override_named(_model, "window", Assets.get_lantern_glow_material() if dark else null)
