class_name AudioSettings
extends RefCounted
## Volume settings (S1): Master / Efectos / Ambiente / Interfaz / Música, 0–1 linear, saved in the `[audio]` section of
## user://settings.cfg (the same file as the video preset of `Quality` and the `[hud]` of UiSettings; the file is
## loaded before saving so the other sections survive). `apply()` sets the bus volumes; 0 mutes the bus.

const PATH := "user://settings.cfg"
const SECTION := "audio"
## setting key → bus name
const BUS_OF := {"master": "Master", "effects": "SFX", "ambience": "Ambience", "ui": "UI", "music": "Music"}
const LABELS := {"master": "Volumen general", "effects": "Efectos", "ambience": "Ambiente", "ui": "Interfaz", "music": "Música"}
const DEFAULTS := {"master": 0.9, "effects": 1.0, "ambience": 0.85, "ui": 0.8, "music": 0.7}

static var _instance: AudioSettings

var values: Dictionary = {}


static func get_instance() -> AudioSettings:
	if _instance == null:
		_instance = AudioSettings.new()
		_instance.load_saved()
	return _instance


func load_saved() -> void:
	values = DEFAULTS.duplicate()
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for k: String in DEFAULTS:
		if cfg.has_section_key(SECTION, k):
			values[k] = clampf(float(cfg.get_value(SECTION, k)), 0.0, 1.0)


func set_value(key: String, v: float, save: bool = true) -> void:
	if not DEFAULTS.has(key):
		return
	values[key] = clampf(v, 0.0, 1.0)
	apply()
	if save:
		_save()


func get_value(key: String) -> float:
	return float(values.get(key, DEFAULTS.get(key, 1.0)))


func reset(save: bool = false) -> void:
	values = DEFAULTS.duplicate()
	apply()
	if save:
		_save()


func apply() -> void:
	for k: String in BUS_OF:
		var idx := AudioServer.get_bus_index(BUS_OF[k])
		if idx < 0:
			continue
		var v := get_value(k)
		AudioServer.set_bus_mute(idx, v <= 0.001)
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.001)) + (AudioManager.BUS_BASE_DB.get(BUS_OF[k], 0.0) as float))


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	for k: String in values:
		cfg.set_value(SECTION, k, values[k])
	cfg.save(PATH)
