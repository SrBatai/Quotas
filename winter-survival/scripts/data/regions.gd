class_name Regions
## Region names for the banner (GDD §8, PLAN §4.3). Inside the hunter's clearing the slice's small zones win
## (first match; the small ones before the clearing so they are reachable where circles overlap); elsewhere the
## name of the chunk (PoiRegistry, from the macro map: towns, farms, lake, N‑140, border…).

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
const SIGNPOST_POS := Vector2(-6.5, 9.5)

## Chunk regions computed once per process (pure: PoiRegistry + road distance of the height function).
static var _chunk_names: Dictionary = {}


static func name_at(x: float, z: float) -> String:
	var p := Vector2(x, z)
	for zone in ZONES:
		if p.distance_to(zone["center"]) <= float(zone["radius"]):
			return zone["name"]
	return chunk_name(WorldConst.chunk_of(x), WorldConst.chunk_of(z))


## Region of a chunk (the clearing's own chunks answer BOSQUE PROFUNDO outside the small zones, as in the slice).
static func chunk_name(cx: int, cz: int) -> String:
	var k := WorldConst.key(cx, cz)
	if _chunk_names.has(k):
		return _chunk_names[k]
	var n := DEFAULT
	var w := World.instance
	if w != null and w.is_configured:
		var c := WorldConst.chunk_center(cx, cz)
		n = PoiRegistry.region_of_chunk(cx, cz, w.hf.road_distance(c.x, c.z, 40.0, "highway") < 32.0)
		if n == "CLARO DEL CAZADOR":
			n = DEFAULT
		_chunk_names[k] = n
	return n
