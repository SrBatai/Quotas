class_name LightFlicker
extends OmniLight3D
## Energy noise ±15 % at ~12 Hz. `shadow_priority` >= 0 enrols the light in the Quality omni-shadow budget
## (group "omni_shadow": lantern 0, campfire 1; `alto` gives shadows to the first 2, the other presets to none).

@export var base_energy: float = 2.0
@export var amount: float = 0.15
@export var shadow_priority: int = -1
var _noise := FastNoiseLite.new()
var _t: float = 0.0


func _ready() -> void:
	_noise.seed = randi()
	_noise.frequency = 1.0
	shadow_enabled = false
	shadow_blur = 2.0
	light_indirect_energy = 0.0
	light_energy = base_energy
	if shadow_priority >= 0:
		set_meta("shadow_priority", shadow_priority)
		add_to_group("omni_shadow")
		Quality.refresh_omni_shadows()


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	light_energy = base_energy * (1.0 + amount * _noise.get_noise_1d(_t * 12.0))
