class_name LightFlicker
extends OmniLight3D
## Energy noise ±15 % at ~12 Hz.

@export var base_energy: float = 2.0
@export var amount: float = 0.15
var _noise := FastNoiseLite.new()
var _t: float = 0.0


func _ready() -> void:
	_noise.seed = randi()
	_noise.frequency = 1.0
	shadow_enabled = false
	light_energy = base_energy


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	light_energy = base_energy * (1.0 + amount * _noise.get_noise_1d(_t * 12.0))
