extends Node
## Quality presets (PLAN C5, ARQ v2 §17.2, G1 table in docs/research/06_graficos_render.md §4.2):
## `alto` / `medio` / `compat`. Client only: shadows (atlas, filter, PCSS angle, blur), MSAA, particle density,
## glow / SSAO / volumetric-fog permissions, window projectors, the omni-shadow budget (lantern, campfire), the
## per-renderer exposure and sun scale (Compatibility renders brighter, doc 06 §3.13) and the snow accumulation
## ceiling. DayNight owns the per-hour values and asks this preset what it may enable. The preset is saved in
## user://settings.cfg; an iGPU heuristic picks the default. `compat` means the Compatibility renderer, which
## needs a restart with `--rendering-method gl_compatibility` (relaunch()).

signal preset_changed(preset: StringName)

const SETTINGS_PATH := "user://settings.cfg"
const PRESETS := {
	&"alto": {
		"shadow_size": 4096, "shadow_splits": 2, "shadow_distance": 60.0, "shadow_blur": 1.0, "pcss_angular": 1.2,
		"soft_shadow": RenderingServer.SHADOW_QUALITY_SOFT_HIGH, "msaa": Viewport.MSAA_2X,
		"particles": 1.0, "glow": true, "ssao": true, "ssao_quality": RenderingServer.ENV_SSAO_QUALITY_MEDIUM,
		"volumetric_fog": true, "projectors": true, "omni_shadows": 2, "terrain_shadows": true,
		"exposure_scale": 1.0, "sun_scale": 1.0, "trail_backend": "drawable", "snow_amount_max": 0.7,
	},
	&"medio": {
		"shadow_size": 2048, "shadow_splits": 2, "shadow_distance": 60.0, "shadow_blur": 1.5, "pcss_angular": 0.0,
		"soft_shadow": RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, "msaa": Viewport.MSAA_2X,
		"particles": 0.6, "glow": true, "ssao": true, "ssao_quality": RenderingServer.ENV_SSAO_QUALITY_LOW,
		"volumetric_fog": false, "projectors": true, "omni_shadows": 0, "terrain_shadows": false,
		"exposure_scale": 1.0, "sun_scale": 1.0, "trail_backend": "drawable", "snow_amount_max": 0.7,
	},
	&"compat": {
		"shadow_size": 2048, "shadow_splits": 2, "shadow_distance": 50.0, "shadow_blur": 2.0, "pcss_angular": 0.0,
		"soft_shadow": RenderingServer.SHADOW_QUALITY_SOFT_LOW, "msaa": Viewport.MSAA_2X,
		"particles": 0.35, "glow": true, "ssao": false, "ssao_quality": RenderingServer.ENV_SSAO_QUALITY_VERY_LOW,
		"volumetric_fog": false, "projectors": false, "omni_shadows": 0, "terrain_shadows": false,
		"exposure_scale": 0.5, "sun_scale": 0.75, "trail_backend": "drawable", "snow_amount_max": 0.6,
	},
}
## Adapter-name fragments of iGPUs that only run the game acceptably in Compatibility.
const OLD_IGPU_PATTERNS := ["intel(r) hd graphics", "intel hd graphics", "ivybridge", "haswell", "broadwell",
	"skylake", "kabylake", "kaby lake", "apollolake", "geminilake", "braswell", "bay trail", "cherry trail",
	"radeon vega 3", "radeon r2", "radeon r3", "radeon r4", "radeon r5", "llvmpipe", "softpipe", "swiftshader",
	"software rasterizer", "mali-4", "mali-t", "adreno 3", "adreno 4", "powervr"]

var preset: StringName = &"alto"
var detected: StringName = &"alto"
var restart_required: bool = false
var _is_client: bool = true


func _ready() -> void:
	_is_client = DisplayServer.get_name() != "headless" and not OS.has_feature("dedicated_server")
	detected = detect()
	var saved := _load_saved()
	preset = saved if saved != &"" and PRESETS.has(saved) else detected
	if is_compat_renderer():
		preset = &"compat"  # the renderer decides: the other presets need Forward+
	apply()


## Heuristic: Compatibility renderer or an old/software iGPU -> compat; other integrated GPUs -> medio; else alto.
func detect() -> StringName:
	if is_compat_renderer():
		return &"compat"
	var adapter := RenderingServer.get_video_adapter_name().to_lower()
	var type := RenderingServer.get_video_adapter_type()
	for p in OLD_IGPU_PATTERNS:
		if adapter.contains(p):
			return &"compat"
	if type == RenderingDevice.DEVICE_TYPE_CPU:
		return &"compat"
	if type == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU or type == RenderingDevice.DEVICE_TYPE_VIRTUAL_GPU:
		return &"medio"
	return &"alto"


static func is_compat_renderer() -> bool:
	return RenderingServer.get_current_rendering_method() == "gl_compatibility"


func settings() -> Dictionary:
	return PRESETS.get(preset, PRESETS[&"alto"])


func particle_ratio() -> float:
	return float(settings()["particles"])


func snow_amount_max() -> float:
	return float(settings()["snow_amount_max"])


## Tonemap exposure multiplier (Compatibility blends the shadowed lights in sRGB and comes out brighter: ×0.5).
func exposure_scale() -> float:
	return float(settings()["exposure_scale"])


## Sun energy multiplier that goes with exposure_scale (×0.75 in Compatibility).
func sun_scale() -> float:
	return float(settings()["sun_scale"])


## Whether the preset allows a feature: "glow", "ssao", "volumetric_fog", "projectors", "terrain_shadows".
func allows(feature: String) -> bool:
	var s := settings()
	if not s.has(feature):
		return false
	var v := bool(s[feature])
	if is_compat_renderer() and feature in ["ssao", "volumetric_fog", "projectors"]:
		return false  # not implemented by that renderer (SSAO has no effect in 4.7.2 Compatibility)
	return v


func omni_shadow_budget() -> int:
	return int(settings()["omni_shadows"])


func trail_backend() -> String:
	return String(settings()["trail_backend"])


## Selects a preset, saves it and applies what can change at runtime. Switching renderer needs relaunch().
func set_preset(name: StringName) -> void:
	if not PRESETS.has(name):
		push_warning("Quality: unknown preset %s" % name)
		return
	preset = name
	_save()
	var wants_compat := name == &"compat"
	restart_required = wants_compat != is_compat_renderer()
	apply()


func rendering_method_for(name: StringName) -> String:
	return "gl_compatibility" if name == &"compat" else "forward_plus"


## Restarts the game with the renderer of the current preset (the only way to switch Forward+ <-> Compatibility).
func relaunch() -> void:
	var args := ["--rendering-method", rendering_method_for(preset)]
	args.append_array(OS.get_cmdline_args())
	OS.create_process(OS.get_executable_path(), args)
	get_tree().quit()


func apply() -> void:
	if not _is_client:
		return
	var s := settings()
	RenderingServer.directional_shadow_atlas_set_size(int(s["shadow_size"]), true)
	RenderingServer.directional_soft_shadow_filter_set_quality(s["soft_shadow"])
	RenderingServer.positional_soft_shadow_filter_set_quality(s["soft_shadow"])
	if not is_compat_renderer():
		RenderingServer.environment_set_ssao_quality(s["ssao_quality"], true, 0.5, 2, 50.0, 300.0)
	var vp := get_viewport()
	if vp != null:
		vp.msaa_3d = s["msaa"]
	for node in get_tree().get_nodes_in_group("quality_sun"):
		if node is DirectionalLight3D:
			apply_to_sun(node)
	for node in get_tree().get_nodes_in_group("quality_env"):
		if node is WorldEnvironment and (node as WorldEnvironment).environment != null:
			apply_to_environment((node as WorldEnvironment).environment)
	refresh_omni_shadows()
	preset_changed.emit(preset)


## Directional shadow: 2 splits, 50–60 m, PCSS angle and blur per preset. Call again when the preset changes.
func apply_to_sun(sun: DirectionalLight3D) -> void:
	var s := settings()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if int(s["shadow_splits"]) == 2 else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = float(s["shadow_distance"])
	sun.shadow_blur = float(s["shadow_blur"])
	sun.light_angular_distance = float(s["pcss_angular"]) if not is_compat_renderer() else 0.0
	if not sun.is_in_group("quality_sun"):
		sun.add_to_group("quality_sun")


## Environment effects only available in Forward+ follow the preset. DayNight refines them per hour
## (glow only with warm lights, volumetric fog only in blizzards) but never beyond what the preset allows.
func apply_to_environment(env: Environment) -> void:
	env.glow_enabled = allows("glow")
	env.ssao_enabled = allows("ssao")
	env.volumetric_fog_enabled = allows("volumetric_fog")


## Omni shadows (lantern, campfire): the first `omni_shadows` lights of the "omni_shadow" group by priority
## (meta "shadow_priority", lower first) cast shadows, the rest do not. Lights call this when they enter the tree.
func refresh_omni_shadows() -> void:
	if not _is_client:
		return
	var lights: Array = get_tree().get_nodes_in_group("omni_shadow")
	lights.sort_custom(func(a: Node, b: Node) -> bool:
		return int(a.get_meta("shadow_priority", 10)) < int(b.get_meta("shadow_priority", 10)))
	var budget := omni_shadow_budget()
	for i in lights.size():
		var l := lights[i] as Light3D
		if l != null:
			l.shadow_enabled = i < budget


func _load_saved() -> StringName:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return &""
	return StringName(str(cfg.get_value("video", "preset", "")))


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("video", "preset", String(preset))
	cfg.set_value("video", "rendering_method", rendering_method_for(preset))
	cfg.save(SETTINGS_PATH)
