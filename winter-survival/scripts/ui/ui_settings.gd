class_name UiSettings
extends RefCounted
## HUD / accessibility settings (docs/research/10_hud_ux.md §V.7 and appendix §5.7–5.8), saved in the
## `[hud]` section of user://settings.cfg (the same file as the video preset of `Quality`). One shared instance:
## `UiSettings.get_instance()`; `changed` fires after every `set_value`.

signal changed()

const PATH := "user://settings.cfg"
const SECTION := "hud"

## HUD presets (§V.7): Mínimo (default; everything dynamic), Estándar (vitals and hotbar always on) and
## Completo (Estándar + the one-line mission tracker and the time / temperature block fixed).
const PRESETS := [&"minimo", &"estandar", &"completo"]
const PRESET_NAMES := {&"minimo": "Mínimo", &"estandar": "Estándar", &"completo": "Completo"}
## Element modes that a preset forces to `always` (the rest stay `dynamic`).
const PRESET_ALWAYS := {
	&"minimo": [],
	&"estandar": [&"vitals", &"hotbar"],
	&"completo": [&"vitals", &"hotbar", &"tracker", &"clock"],
}
const MODES := [&"dynamic", &"always", &"hidden"]
const HUD_WIDTHS := [&"16:9", &"21:9", &"full"]

const DEFAULTS := {
	"preset": &"minimo",
	"ui_scale": 1.0,           # 0.8–1.5 in 0.05 steps (Deck: 1.15 by default)
	"screen_margin": 0.0,      # 0–0.05 of each side (TV overscan)
	"hud_width": &"16:9",      # 21:9 screens keep the corner blocks in a centred 16:9 box by default
	"info_toggle": false,      # "Pedir en lugar de mantener": Info toggles instead of hold
	"reduced_motion": false,   # fades of 200 ms, no tracking animation, no slides
	"reduced_flashes": false,  # no damage flash, no pulsing vignette
	"text_bold": false,        # "Grosor del texto: Reforzado" (Light → Regular, Regular → Medium)
	"text_bg": &"auto",        # "Fondo del texto": auto (adaptive scrim) | opaque (70 %)
	"colorblind": false,       # marker shapes per kind + Okabe–Ito player colours
	"elements": {},            # per element override: {&"vitals": &"always", …}
}

static var _instance: UiSettings

var values: Dictionary = {}


static func get_instance() -> UiSettings:
	if _instance == null:
		_instance = UiSettings.new()
		_instance.load_saved()
	return _instance


## Convenience getter on the shared instance.
static func get_value(key: String) -> Variant:
	return get_instance().values.get(key, DEFAULTS.get(key))


func load_saved() -> void:
	values = DEFAULTS.duplicate(true)
	if _is_deck():
		values["ui_scale"] = UiTokens.UI_SCALE_DECK
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for k: String in DEFAULTS:
		if cfg.has_section_key(SECTION, k):
			values[k] = _coerce(k, cfg.get_value(SECTION, k))


func set_value(key: String, value: Variant, save: bool = true) -> void:
	if not DEFAULTS.has(key):
		push_warning("UiSettings: unknown key %s" % key)
		return
	values[key] = _coerce(key, value)
	if save:
		_save()
	changed.emit()


## Restores the defaults (tests and "Restablecer").
func reset(save: bool = false) -> void:
	values = DEFAULTS.duplicate(true)
	if save:
		_save()
	changed.emit()


## Effective mode of a HUD element: explicit override > preset > dynamic.
func mode_of(element: StringName) -> StringName:
	var over: Dictionary = values.get("elements", {})
	if over.has(element):
		return StringName(over[element])
	var preset: StringName = values.get("preset", &"minimo")
	if (PRESET_ALWAYS.get(preset, []) as Array).has(element):
		return &"always"
	return &"dynamic"


func ui_scale() -> float:
	return clampf(float(values.get("ui_scale", 1.0)), UiTokens.UI_SCALE_MIN, UiTokens.UI_SCALE_MAX)


func _coerce(key: String, v: Variant) -> Variant:
	match key:
		"preset":
			var s := StringName(str(v))
			return s if PRESETS.has(s) else &"minimo"
		"hud_width":
			var w := StringName(str(v))
			return w if HUD_WIDTHS.has(w) else &"16:9"
		"text_bg":
			return &"opaque" if str(v) == "opaque" else &"auto"
		"ui_scale":
			return snappedf(clampf(float(v), UiTokens.UI_SCALE_MIN, UiTokens.UI_SCALE_MAX), 0.05)
		"screen_margin":
			return clampf(float(v), 0.0, UiTokens.SCREEN_MARGIN_MAX)
		"elements":
			var out := {}
			if v is Dictionary:
				for e in v:
					var m := StringName(str(v[e]))
					if MODES.has(m):
						out[StringName(str(e))] = m
			return out
	return bool(v)


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	for k: String in values:
		var v: Variant = values[k]
		cfg.set_value(SECTION, k, String(v) if v is StringName else v)
	cfg.save(PATH)


## Steam Deck (appendix §5.7): 1280 × 800 screen or the SteamDeck=1 variable Steam sets.
static func _is_deck() -> bool:
	if OS.get_environment("SteamDeck") == "1":
		return true
	if DisplayServer.get_name() == "headless":
		return false
	var s := DisplayServer.screen_get_size()
	return s == Vector2i(1280, 800)
