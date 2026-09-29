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
## (roofs / miradores in the city: −40°, 20–50 m, far 130). C1: the district profiles of Altavega (definitive): the
## casco viejo's 6–8 m streets keep a steeper camera and less zoom (the cut has less room), the ensanche the city
## profile, the barriada a little flatter over its park, Las Torres the flattest and farthest (46 m: the towers read
## as tall); `far` is only the floor of the dynamic far plane (far_for).
static func preset(p_id: StringName) -> CameraProfile:
	if _presets.is_empty():
		_presets[&"default"] = make(&"default", Balance.CAMERA_PITCH_DEG, Balance.CAMERA_DIST_MIN, Balance.CAMERA_DIST_MAX, Balance.CAMERA_FAR, false)
		_presets[&"city"] = make(&"city", -43.0, 16.0, 44.0, 95.0, true)
		_presets[&"rooftop"] = make(&"rooftop", -40.0, 20.0, 50.0, 130.0, true)
		_presets[&"casco"] = make(&"casco", -46.0, 16.0, 40.0, 85.0, true)
		_presets[&"ensanche"] = make(&"ensanche", -44.0, 16.0, 42.0, 95.0, true)
		_presets[&"barriada"] = make(&"barriada", -43.0, 16.0, 44.0, 100.0, true)
		_presets[&"torres"] = make(&"torres", -42.0, 18.0, 46.0, 110.0, true)
	return _presets.get(p_id, _presets[&"default"])


## C1: LocationInfo zone id → the district camera profile (the zone's own id or any id of its parent chain).
const DISTRICT_PROFILE := {"altavega_casco_viejo": &"casco", "altavega_ensanche": &"ensanche", "barriada_de_san_lazaro": &"barriada",
	"altavega_las_torres": &"torres"}


## Camera profile of a city zone from its id and its parent chain (Locations): the district's, else `city`.
static func for_zone(ids: Array) -> StringName:
	for id in ids:
		if DISTRICT_PROFILE.has(str(id)):
			return DISTRICT_PROFILE[str(id)]
	return &"city"


## C1 «far dinámico»: the far plane that still reaches the ground at the top edge of the frame — the camera at
## `dist` m behind the pivot, pitched `pitch_deg`, FOV `fov_deg`, with the pivot `drop` m above the ground under the
## frame (a roof, a tower floor: the street is that far below) — plus a margin, never below `floor_far` (the
## profile's) and never above 420 m (the top ray of a flatter mirador camera is not this camera). Cheap: once a frame.
static func far_for(floor_far: float, dist: float, pitch_deg: float, fov_deg: float, drop: float) -> float:
	var pitch := deg_to_rad(absf(pitch_deg))
	var top := pitch - deg_to_rad(fov_deg) * 0.5
	var h := dist * sin(pitch) + maxf(drop, 0.0)
	if top <= deg_to_rad(4.0):
		return 420.0
	var reach := h / sin(top)
	return clampf(reach + 12.0, floor_far, 420.0)


static func ids() -> Array:
	preset(&"default")
	return _presets.keys()
