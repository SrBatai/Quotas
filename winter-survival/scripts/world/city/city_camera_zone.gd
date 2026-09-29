class_name CityCameraZone
extends CameraZone
## A district box of Altavega (C1): on the street it defers to the district profile the ZoneTracker confirmed (H2's
## route: 12 m / 1.5 s hysteresis, never in combat — CameraRig.zone_profile), and it switches to `rooftop` when the
## player stands more than `rooftop_height` above the TERRAIN under them (a roof, a tower floor, a mirador), not
## above the zone's origin (the casco climbs the slope of Monte Cierzo; a box origin would be wrong by 10–20 m).

var hf: HeightFunction


func profile_at(p: Vector3) -> StringName:
	if rooftop_height > 0.0 and hf != null and p.y - hf.height_at(p.x, p.z) > rooftop_height:
		return &"rooftop"
	return profile
