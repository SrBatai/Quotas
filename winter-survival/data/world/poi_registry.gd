class_name PoiRegistry
## Points of interest of the macro map (PLAN §4.2–4.3, ARQ v2 §8.4), in world metres (x → east, z → south; the
## hunter's clearing at the origin). The ASCII map of PLAN §4.2 is the source: character (col, row) is centred at
## ((col − 12) × 128, (row − 12) × 128), so C (12, 12) is (0, 0) and the N‑140 column 17 runs along x ≈ 640.
## Pure data + pure queries: tools/gen_macro_map.gd paints the macro map from it, HeightFunction flattens the
## pads, ScatterGen keeps them clear and RegionMap names the chunks for the region banner.

## The ASCII map of PLAN §4.2 (24 × 24 characters, 1 character = 128 m, row 0 = north).
const ASCII := [
	"^^^^^^^^^^^^^^^^^^^^^^^^",
	"^^^##############X^^^^^^",
	"^################=#####^",
	"^################M#####^",
	"^################=#####^",
	"^##########f#####=#####^",
	"^#####vS###.....#=#####^",
	"^#####------TTT.-=#####^",
	"^##########.THTP-=#####^",
	"^##########.TTT.#G#####^",
	"^###########|####=##f##^",
	"^##R########|####=#####^",
	"^####D######C####=#####^",
	"^####~~##---#####A#####^",
	"^###~~~~~#|######=#####^",
	"^###~~~~~#|####f#=#####^",
	"^####~~~~v#######=#####^",
	"^#####~~#########G#####^",
	"^################=-v+##^",
	"^#############L##=#####^",
	"^################=#####^",
	"^################=#####^",
	"^^####################^^",
	"^^^^^^^^^^^^^^^^^^^^^^^^",
]
const CELL := 128.0

## Named regions (banner "REGIÓN — NOMBRE"): first match wins, so small places go before large ones.
## shape: "circle" (center, radius) or "rect" (center, size).
const REGIONS := [
	{"name": "CLARO DEL CAZADOR", "center": Vector2(0, 0), "radius": 100.0},
	{"name": "PUNTO DE EVACUACIÓN", "center": Vector2(640, -1408), "radius": 110.0},
	{"name": "CONTROL MILITAR KM 12", "center": Vector2(640, -1152), "radius": 100.0},
	{"name": "GASOLINERA NORTE", "center": Vector2(640, -384), "radius": 80.0},
	{"name": "GASOLINERA SUR", "center": Vector2(640, 640), "radius": 80.0},
	{"name": "ÁREA DE DESCANSO", "center": Vector2(640, 128), "radius": 90.0},
	{"name": "GRANJA DEL MOLINO", "center": Vector2(-128, -896), "radius": 100.0},
	{"name": "GRANJA ALTA", "center": Vector2(1024, -256), "radius": 100.0},
	{"name": "GRANJA ROMERO", "center": Vector2(384, 384), "radius": 100.0},
	{"name": "LA HERRERÍA", "center": Vector2(-704, -768), "radius": 170.0},
	{"name": "EL EMBARCADERO", "center": Vector2(-384, 512), "radius": 120.0},
	{"name": "SAN BLAS", "center": Vector2(960, 768), "radius": 150.0},
	{"name": "PRESA", "center": Vector2(-880, 20), "radius": 100.0},
	{"name": "REPETIDOR DEL PICO", "center": Vector2(-1152, -128), "radius": 170.0},
	{"name": "TORRE DE VIGILANCIA", "center": Vector2(256, 896), "radius": 90.0},
	{"name": "VALDENIEVE", "center": Vector2(176, -512), "size": Vector2(560, 420)},
]
const REGION_LAKE := "LAGO DE LAS ÁNIMAS"
const REGION_ROAD := "N-140"
const REGION_BORDER := "LAS CUMBRES"
const REGION_HIGH_FOREST := "PINOS ALTOS"
const REGION_FOREST := "BOSQUE PROFUNDO"

## Terrain pads (flattened to the natural height at their centre) + scatter exclusion. `model` = static prop
## placed on the pad by the chunk that contains `center` (Assets.spawn_model → placeholder until Opus delivers it).
## yaw in degrees (the model's +Z front = MODEL_FRONT).
const PADS := [
	{"id": "cabin_small_1", "center": Vector2(-512, -300), "radius": 12.0, "model": "cabin_small", "yaw": 160.0},
	{"id": "cabin_small_2", "center": Vector2(400, -160), "radius": 12.0, "model": "cabin_small", "yaw": -110.0},
	{"id": "cabin_small_3", "center": Vector2(-160, 720), "radius": 12.0, "model": "cabin_small", "yaw": 20.0},
	{"id": "cabin_small_4", "center": Vector2(880, 330), "radius": 12.0, "model": "cabin_small", "yaw": 75.0},
	{"id": "lookout_tower", "center": Vector2(256, 896), "radius": 10.0, "model": "lookout_tower", "yaw": 30.0},
	{"id": "camp_1", "center": Vector2(150, 60), "radius": 7.0, "model": "campsite_remains", "yaw": 200.0},
	{"id": "camp_2", "center": Vector2(230, -250), "radius": 7.0, "model": "campsite_remains", "yaw": 40.0},
	{"id": "camp_3", "center": Vector2(-340, -150), "radius": 7.0, "model": "campsite_remains", "yaw": 300.0},
	{"id": "camp_4", "center": Vector2(170, 400), "radius": 7.0, "model": "campsite_remains", "yaw": 120.0},
	{"id": "camp_5", "center": Vector2(-620, -120), "radius": 7.0, "model": "campsite_remains", "yaw": 250.0},
	{"id": "camp_6", "center": Vector2(470, 920), "radius": 7.0, "model": "campsite_remains", "yaw": 10.0},
	# future POIs (M6/M9a/M10): flat ground reserved now so the terrain does not change under them later
	{"id": "dam", "center": Vector2(-880, 20), "radius": 30.0, "model": ""},
	{"id": "repeater", "center": Vector2(-1152, -128), "radius": 22.0, "model": ""},
	{"id": "rest_area", "center": Vector2(610, 128), "radius": 40.0, "model": ""},
	{"id": "gas_north", "center": Vector2(610, -384), "radius": 30.0, "model": ""},
	{"id": "gas_south", "center": Vector2(610, 640), "radius": 30.0, "model": ""},
	{"id": "checkpoint", "center": Vector2(640, -1152), "radius": 45.0, "model": ""},
]

## Lago de las Ánimas: smooth union of discs (fast signed distance, identical everywhere). Flat, safe ice (M3).
const LAKE_DISCS := [
	[Vector2(-780, 340), 250.0],
	[Vector2(-660, 500), 190.0],
	[Vector2(-910, 460), 160.0],
	[Vector2(-720, 660), 120.0],
]
const LAKE_SMOOTH := 70.0
## Lake ice level (absolute metres; the clearing ground is ≈ 0).
const LAKE_LEVEL := -5.0
const LAKE_BBOX := Rect2(-1090, 80, 640, 720)


## World centre of an ASCII character.
static func char_center(col: int, row: int) -> Vector2:
	return Vector2(float(col - 12) * CELL, float(row - 12) * CELL)


## ASCII character at a world position ("^" outside the map).
static func char_at(x: float, z: float) -> String:
	var col := int(round(x / CELL)) + 12
	var row := int(round(z / CELL)) + 12
	if row < 0 or row >= ASCII.size() or col < 0 or col >= 24:
		return "^"
	var line: String = ASCII[row]
	return line[col] if col < line.length() else "#"


## Signed distance to the big lake's shore (m): < 0 inside.
static func lake_sdf(x: float, z: float) -> float:
	var d := INF
	for disc in LAKE_DISCS:
		var c: Vector2 = disc[0]
		var r: float = disc[1]
		var di := Vector2(x - c.x, z - c.y).length() - r
		if d == INF:
			d = di
		else:
			# polynomial smooth minimum (organic shore where the discs meet)
			var h := clampf(0.5 + 0.5 * (di - d) / LAKE_SMOOTH, 0.0, 1.0)
			d = lerpf(di, d, h) - LAKE_SMOOTH * h * (1.0 - h)
	return d


## Region name of a chunk (evaluated at its centre; RegionTracker adds the fine zones inside the clearing).
static func region_of_chunk(cx: int, cz: int, near_highway: bool) -> String:
	var c := WorldConst.chunk_center(cx, cz)
	return region_at(c.x, c.z, near_highway)


static func region_at(x: float, z: float, near_highway: bool) -> String:
	var p := Vector2(x, z)
	for r in REGIONS:
		if r.has("size"):
			var rect := Rect2((r["center"] as Vector2) - (r["size"] as Vector2) * 0.5, r["size"])
			if rect.has_point(p):
				return r["name"]
		elif p.distance_to(r["center"]) <= float(r["radius"]):
			return r["name"]
	if lake_sdf(x, z) < 40.0:
		return REGION_LAKE
	if near_highway:
		return REGION_ROAD
	var cheb := maxf(absf(x), absf(z))
	if cheb > WorldConst.BORDER_START + 96.0:
		return REGION_BORDER
	if cheb > 900.0:
		return REGION_HIGH_FOREST
	return REGION_FOREST
