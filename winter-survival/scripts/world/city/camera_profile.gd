class_name CameraProfile
extends RefCounted
## Per-region camera settings (W0, doc 09 §3.7): the default follow camera of the game, and the city profiles that
## let skyscrapers read as tall — a slightly lower pitch, more zoom-out, a longer far plane — while the «corte
## urbano» (CityCut scales its corridor / zone / capsule with the camera) keeps the player visible. CameraRig blends
## pitch and far toward the active profile (time constant BLEND_TAU) and clamps the zoom to its range; CameraZone
## nodes (or CameraRig.profile_override) pick the profile. The camera never collides nor turns by itself.

const BLEND_TAU := 0.45

var id: StringName = &"default"
var pitch_deg: float = Balance.CAMERA_PITCH_DEG
var dist_min: float = Balance.CAMERA_DIST_MIN
var dist_max: float = Balance.CAMERA_DIST_MAX
var far: float = Balance.CAMERA_FAR
## Capsule cut on city props (lamps, cars, foliage: world_vcol_capsule) while this profile is active.
var props_capsule: bool = false

static var _presets: Dictionary = {}


static func make(p_id: StringName, p_pitch: float, p_min: float, p_max: float, p_far: float, p_props: bool) -> CameraProfile:
	var p := CameraProfile.new()
	p.id = p_id
	p.pitch_deg = p_pitch
	p.dist_min = p_min
	p.dist_max = p_max
	p.far = p_far
	p.props_capsule = p_props
	return p


## `default` (the game camera: −48°, 16–38 m, far 70), `city` (districts: −43°, 16–44 m, far 95) and `rooftop`
## (roofs / miradores in the city: −40°, 20–50 m, far 130).
static func preset(p_id: StringName) -> CameraProfile:
	if _presets.is_empty():
		_presets[&"default"] = make(&"default", Balance.CAMERA_PITCH_DEG, Balance.CAMERA_DIST_MIN, Balance.CAMERA_DIST_MAX, Balance.CAMERA_FAR, false)
		_presets[&"city"] = make(&"city", -43.0, 16.0, 44.0, 95.0, true)
		_presets[&"rooftop"] = make(&"rooftop", -40.0, 20.0, 50.0, 130.0, true)
	return _presets.get(p_id, _presets[&"default"])


static func ids() -> Array:
	preset(&"default")
	return _presets.keys()
