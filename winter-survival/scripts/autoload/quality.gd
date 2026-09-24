extends Node
## Quality presets (PLAN C5, ARQ v2 §17.2): `alto` / `medio` / `compat`. Client only: applies shadows, MSAA,
## particle density, glow/SSAO/volumetric fog flags and the snow accumulation ceiling. The preset is saved in
## user://settings.cfg; an iGPU heuristic picks the default. `compat` means the Compatibility renderer, which
## needs a restart with `--rendering-method gl_compatibility` (relaunch()).

signal preset_changed(preset: StringName)

const SETTINGS_PATH := "user://settings.cfg"
const PRESETS := {
	&"alto": {
		"shadow_size": 4096, "shadow_splits": 2, "shadow_distance": 60.0, "shadow_blur": 1.5,
		"soft_shadow": RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, "msaa": Viewport.MSAA_2X,
		"particles": 1.0, "glow": true, "ssao": true, "volumetric_fog": true, "omni_shadows": 6,
		"snow_amount_max": 0.7,
	},
	&"medio": {
		"shadow_size": 2048, "shadow_splits": 2, "shadow_distance": 50.0, "shadow_blur": 1.5,
		"soft_shadow": RenderingServer.SHADOW_QUALITY_SOFT_LOW, "msaa": Viewport.MSAA_2X,
		"particles": 0.6, "glow": false, "ssao": false, "volumetric_fog": false, "omni_shadows": 3,
		"snow_amount_max": 0.7,
	},
	&"compat": {
		"shadow_size": 2048, "shadow_splits": 2, "shadow_distance": 45.0, "shadow_blur": 1.5,
		"soft_shadow": RenderingServer.SHADOW_QUALITY_HARD, "msaa": Viewport.MSAA_2X,
		"particles": 0.35, "glow": false, "ssao": false, "volumetric_fog": false, "omni_shadows": 0,
		"snow_amount_max": 0.6,
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
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		preset = &"compat"  # the renderer decides: the other presets need Forward+
	apply()


## Heuristic: Compatibility renderer or an old/software iGPU -> compat; other integrated GPUs -> medio; else alto.
func detect() -> StringName:
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
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


func settings() -> Dictionary:
	return PRESETS.get(preset, PRESETS[&"alto"])


func particle_ratio() -> float:
	return float(settings()["particles"])


func snow_amount_max() -> float:
	return float(settings()["snow_amount_max"])


## Selects a preset, saves it and applies what can change at runtime. Switching renderer needs relaunch().
func set_preset(name: StringName) -> void:
	if not PRESETS.has(name):
		push_warning("Quality: unknown preset %s" % name)
		return
	preset = name
	_save()
	var wants_compat := name == &"compat"
	var is_compat := RenderingServer.get_current_rendering_method() == "gl_compatibility"
	restart_required = wants_compat != is_compat
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
	var vp := get_viewport()
	if vp != null:
		vp.msaa_3d = s["msaa"]
	for node in get_tree().get_nodes_in_group("quality_sun"):
		if node is DirectionalLight3D:
			apply_to_sun(node)
	for node in get_tree().get_nodes_in_group("quality_env"):
		if node is WorldEnvironment and (node as WorldEnvironment).environment != null:
			apply_to_environment((node as WorldEnvironment).environment)
	preset_changed.emit(preset)


## Directional shadow: 2 splits, 45–60 m (PLAN §3.2 camera row). Call again when the preset changes.
func apply_to_sun(sun: DirectionalLight3D) -> void:
	var s := settings()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if int(s["shadow_splits"]) == 2 else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = float(s["shadow_distance"])
	sun.shadow_blur = float(s["shadow_blur"])
	if not sun.is_in_group("quality_sun"):
		sun.add_to_group("quality_sun")


## Environment effects only available in Forward+ (glow, SSAO, volumetric fog) follow the preset.
func apply_to_environment(env: Environment) -> void:
	var s := settings()
	var compat := RenderingServer.get_current_rendering_method() == "gl_compatibility"
	env.glow_enabled = bool(s["glow"]) and not compat
	env.ssao_enabled = bool(s["ssao"]) and not compat
	env.volumetric_fog_enabled = bool(s["volumetric_fog"]) and not compat
	if env.glow_enabled:
		env.glow_intensity = 0.35
		env.glow_bloom = 0.05
		env.glow_hdr_threshold = 1.2
	if env.ssao_enabled:
		env.ssao_radius = 1.5
		env.ssao_intensity = 1.2


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
