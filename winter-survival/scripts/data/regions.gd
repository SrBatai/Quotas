class_name Regions
## Named zones (GDD §8). Vector2 = (x, z). First match wins; the small zones are
## checked before the clearing so they are reachable even where circles overlap.

const ZONES := [
	{"name": "CABAÑA DEL PESCADOR", "center": Vector2(-21, -13), "radius": 11.0},
	{"name": "LAGO HELADO", "center": Vector2(-42, 30), "radius": 20.0},
	{"name": "CLARO", "center": Vector2(0, 0), "radius": 26.0},
]
const DEFAULT := "BOSQUE PROFUNDO"

const AFRAME_POS := Vector2(-21, -13)
const LAKE_CENTER := Vector2(-42, 30)
const LAKE_RADIUS := 20.0
const TRUCK_POS := Vector2(-11, -3)
const SIGNPOST_POS := Vector2(-7, 8)


static func name_at(x: float, z: float) -> String:
	var p := Vector2(x, z)
	for zone in ZONES:
		if p.distance_to(zone["center"]) <= float(zone["radius"]):
			return zone["name"]
	return DEFAULT
