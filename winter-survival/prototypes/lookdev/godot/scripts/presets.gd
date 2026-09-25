class_name LookdevPresets
extends RefCounted
## Environment / light presets for the look-dev scene. Every number here is a candidate for
## docs/research/06_graficos_render.md; keep them in sync when tuning.
##
## Colour conventions: sRGB hex (the same convention as day_night.gd KEYS in the game).
## Sun rotation: (pitch, yaw, 0) in degrees; the light travels along the node's -Z.
## Camera yaw 45 puts the camera at +X+Z, so screen-up = (-X,-Z) and a sun yaw near 168 is "back-lit from the
## upper right" (long shadows toward the camera, like the reference).

const PRESETS := {
	&"day": {
		"sun": {"color": "#F8F3EA", "energy": 0.5, "rot": Vector3(-23.0, 168.0, 0.0), "angular": 1.2, "blur": 1.0, "indirect": 1.0},
		"moon": null,
		"ambient": {"color": "#6A88C4", "energy": 1.45},
		"sky": {"top": "#6FA6E4", "horizon": "#D2E1F3", "ground": "#B9CBE3", "energy": 1.0},
		"fog": {"color": "#A9BEDC", "density": 0.0040, "aerial": 0.1, "height": -2.0, "height_density": 0.0, "sun_scatter": 0.0},
		# Filmic keeps the pastel blue of the snow; AgX/ACES desaturate the bright snow toward grey (measured, see doc).
		"tonemap": {"mode": "filmic", "exposure": 0.55, "white": 1.0, "agx_contrast": 1.25},
		"adjust": {"brightness": 1.0, "contrast": 1.0, "saturation": 1.0},
		"glow": {"enabled": false},
		"ssao": {"enabled": true, "radius": 1.4, "intensity": 2.5, "power": 1.6, "detail": 0.4, "light_affect": 0.15},
		"volumetric": {"enabled": false},
		"windows": false, "lantern": false, "campfire": false, "snowfall": false, "blizzard": 0.0, "spill_scale": 0.0,
	},
	&"dusk": {
		"sun": {"color": "#FFB27A", "energy": 0.12, "rot": Vector3(-6.0, 150.0, 0.0), "angular": 3.5, "blur": 2.5, "indirect": 1.0},
		"moon": null,
		"ambient": {"color": "#5A80B2", "energy": 1.0},
		"sky": {"top": "#4D4F86", "horizon": "#D8A488", "ground": "#7E7C98", "energy": 0.6},
		"fog": {"color": "#6E86B8", "density": 0.010, "aerial": 0.15, "height": -1.0, "height_density": 0.015, "sun_scatter": 0.1},
		"tonemap": {"mode": "filmic", "exposure": 0.65, "white": 1.0, "agx_contrast": 1.2},
		"adjust": {"brightness": 1.0, "contrast": 1.0, "saturation": 1.0},
		"glow": {"enabled": true, "intensity": 0.55, "bloom": 0.0, "threshold": 1.05, "blend": "softlight"},
		"ssao": {"enabled": true, "radius": 1.4, "intensity": 2.2, "power": 1.5, "detail": 0.4, "light_affect": 0.1},
		"volumetric": {"enabled": false},
		"windows": true, "lantern": true, "campfire": false, "snowfall": false, "blizzard": 0.0, "spill_scale": 0.3,
	},
	&"night": {
		"sun": null,
		"moon": {"color": "#8EA0C4", "energy": 0.12, "rot": Vector3(-42.0, 205.0, 0.0), "angular": 3.0, "blur": 3.0, "indirect": 0.5},
		"ambient": {"color": "#3E4A66", "energy": 0.42},
		"sky": {"top": "#0B1A33", "horizon": "#1F3358", "ground": "#16233B", "energy": 0.25},
		"fog": {"color": "#66788C", "density": 0.011, "aerial": 0.0, "height": -1.0, "height_density": 0.02, "sun_scatter": 0.0},
		"tonemap": {"mode": "filmic", "exposure": 0.6, "white": 1.0, "agx_contrast": 1.2},
		"adjust": {"brightness": 1.0, "contrast": 1.0, "saturation": 1.05},
		"glow": {"enabled": true, "intensity": 0.7, "bloom": 0.02, "threshold": 1.0, "blend": "softlight"},
		"ssao": {"enabled": true, "radius": 1.4, "intensity": 2.0, "power": 1.5, "detail": 0.4, "light_affect": 0.1},
		"volumetric": {"enabled": false},
		"windows": true, "lantern": true, "campfire": true, "snowfall": false, "blizzard": 0.0, "spill_scale": 0.45,
	},
	&"blizzard": {
		"sun": {"color": "#E6EAF2", "energy": 0.25, "rot": Vector3(-30.0, 168.0, 0.0), "angular": 4.0, "blur": 2.5, "indirect": 1.0},
		"moon": null,
		"ambient": {"color": "#8E9DBA", "energy": 1.25},
		"sky": {"top": "#B4BECF", "horizon": "#B4BECF", "ground": "#B4BECF", "energy": 0.8},
		"fog": {"color": "#AEB8C9", "density": 0.022, "aerial": 0.0, "height": 0.0, "height_density": 0.0, "sun_scatter": 0.0},
		"tonemap": {"mode": "filmic", "exposure": 0.55, "white": 1.0, "agx_contrast": 1.1},
		"adjust": {"brightness": 1.0, "contrast": 0.98, "saturation": 0.9},
		"glow": {"enabled": false},
		"ssao": {"enabled": true, "radius": 1.4, "intensity": 1.6, "power": 1.5, "detail": 0.3, "light_affect": 0.1},
		"volumetric": {"enabled": true, "density": 0.028, "albedo": "#D8DEE8", "anisotropy": 0.35, "length": 64.0, "ambient_inject": 0.5, "sky_affect": 1.0},
		"windows": true, "lantern": true, "campfire": false, "snowfall": true, "blizzard": 1.0, "spill_scale": 0.7,
	},
}


static func get_preset(name: StringName) -> Dictionary:
	return PRESETS.get(name, PRESETS[&"day"])


static func names() -> Array:
	return PRESETS.keys()
