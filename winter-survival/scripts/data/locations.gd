class_name Locations
## Named places for the zone title card (docs/research/10_hud_ux.md §V.4.4, appendix §6.1 and §8.6). One entry
## per place, most specific first (the first entry the player is ≥ inset metres inside wins):
##   {id, name (display case), kind, parent, shape, danger 0–3, power, temp (°C offset), enabled}
## kind: city | district | town | village | farm | poi | natural | road.
## shape: {"circle": [center, radius]} | {"rect": [center, size]} | {"fn": &"lake"|&"road"|&"border"|&"high_forest"}
## power: "" (unknown: no fact) | "off" (sin electricidad) | "generator" (con generador) | "on" (con electricidad).
## Sources: the slice's small zones (Regions.ZONES), PoiRegistry.REGIONS (macro map) and the natural regions of
## PoiRegistry.region_at, evaluated at the player's position (not the chunk centre: no per-chunk flicker).
##
## Data hook for the city (PLAN: «Altavega» and its districts are not in the world yet): `CITY` below is disabled;
## when the world has it, set the real shapes and call `Locations.enable_city()` (or `register()` any entry at
## runtime, e.g. from the chunk that builds a district). Districts come before the city, so the card shows the
## district with the city as its first fact ("Altavega · sin electricidad · −18 °C · peligro alto").

const DANGER_NAMES := ["peligro bajo", "peligro moderado", "peligro alto", "peligro extremo"]
const POWER_NAMES := {"off": "sin electricidad", "generator": "con generador", "on": "con electricidad"}
## Card on the first visit / on re-entry per kind (§V.3: full card 5.6 s, re-entry = the name at 60 % 2.5 s).
const CARD := {
	"city": ["full", "compact"], "district": ["full", "compact"], "town": ["full", "compact"],
	"village": ["full", "compact"], "farm": ["full", "compact"], "poi": ["full", "compact"],
	"natural": ["full", "none"], "road": ["full", "none"],
}
## Specificity (lower = deeper in the hierarchy city → district → POI); ties keep the list order.
const RANK := {"poi": 0, "farm": 1, "village": 2, "town": 2, "district": 3, "city": 4, "natural": 5, "road": 6}

## The city of the PLAN (not built yet). Shapes are placeholders until the world agent places it.
const CITY := {
	"id": "altavega", "name": "Altavega", "kind": "city", "parent": "", "danger": 2, "power": "off", "temp": -2.0,
	"shape": {"rect": [Vector2(0, -2600), Vector2(1800, 1200)]}, "enabled": false,
	"districts": [
		{"id": "altavega_financiero", "name": "Distrito Financiero", "danger": 2, "power": "off",
			"shape": {"rect": [Vector2(0, -2700), Vector2(600, 500)]}},
		{"id": "altavega_casco", "name": "Casco Antiguo", "danger": 1, "power": "off",
			"shape": {"rect": [Vector2(-600, -2500), Vector2(500, 500)]}},
		{"id": "altavega_estacion", "name": "Estación", "danger": 2, "power": "off",
			"shape": {"rect": [Vector2(600, -2450), Vector2(500, 400)]}},
		{"id": "altavega_poligono", "name": "Polígono Industrial", "danger": 1, "power": "generator",
			"shape": {"rect": [Vector2(0, -2150), Vector2(900, 300)]}},
	],
}

## Display names and per-place data of the existing regions (PoiRegistry keeps upper-case names).
const KNOWN := {
	"CLARO DEL CAZADOR": {"name": "Claro del cazador", "kind": "poi", "danger": 0},
	"CABAÑA DEL PESCADOR": {"name": "Cabaña del pescador", "kind": "poi", "danger": 0, "parent": "claro"},
	"LAGO HELADO": {"name": "Lago helado", "kind": "natural", "danger": 0, "parent": "claro", "temp": -2.0},
	"PUNTO DE EVACUACIÓN": {"name": "Punto de evacuación", "kind": "poi", "danger": 2, "power": "generator"},
	"CONTROL MILITAR KM 12": {"name": "Control militar km 12", "kind": "poi", "danger": 3, "power": "generator"},
	"GASOLINERA NORTE": {"name": "Gasolinera norte", "kind": "poi", "danger": 1, "power": "off"},
	"GASOLINERA SUR": {"name": "Gasolinera sur", "kind": "poi", "danger": 1, "power": "off"},
	"ÁREA DE DESCANSO": {"name": "Área de descanso", "kind": "poi", "danger": 1, "power": "off"},
	"GRANJA DEL MOLINO": {"name": "Granja del Molino", "kind": "farm", "danger": 1, "power": "off"},
	"GRANJA ALTA": {"name": "Granja Alta", "kind": "farm", "danger": 1, "power": "off"},
	"GRANJA ROMERO": {"name": "Granja Romero", "kind": "farm", "danger": 1, "power": "off"},
	"LA HERRERÍA": {"name": "La Herrería", "kind": "village", "danger": 1, "power": "off"},
	"EL EMBARCADERO": {"name": "El Embarcadero", "kind": "village", "danger": 1, "power": "off"},
	"SAN BLAS": {"name": "San Blas", "kind": "village", "danger": 2, "power": "off"},
	"PRESA": {"name": "Presa", "kind": "poi", "danger": 2, "power": "off", "temp": -3.0},
	"REPETIDOR DEL PICO": {"name": "Repetidor del Pico", "kind": "poi", "danger": 1, "power": "off", "temp": -6.0},
	"TORRE DE VIGILANCIA": {"name": "Torre de vigilancia", "kind": "poi", "danger": 1},
	"VALDENIEVE": {"name": "Valdenieve", "kind": "town", "danger": 2, "power": "off"},
}
## Natural regions of PoiRegistry.region_at, most specific first; Bosque profundo is the default.
const NATURAL := [
	{"id": "lago_animas", "name": "Lago de las Ánimas", "kind": "natural", "danger": 1, "temp": -3.0, "shape": {"fn": &"lake"}},
	{"id": "n140", "name": "N‑140", "kind": "road", "danger": 1, "temp": 0.0, "shape": {"fn": &"road"}},
	{"id": "las_cumbres", "name": "Las Cumbres", "kind": "natural", "danger": 1, "temp": -8.0, "shape": {"fn": &"border"}},
	{"id": "pinos_altos", "name": "Pinos Altos", "kind": "natural", "danger": 1, "temp": -3.0, "shape": {"fn": &"high_forest"}},
]
const DEFAULT := {"id": "bosque_profundo", "name": "Bosque profundo", "kind": "natural", "danger": 1, "temp": 0.0,
	"shape": {"fn": &"default"}}

static var _list: Array = []
static var _extra: Array = []
static var _city_enabled: bool = false


## All entries, most specific first (built once; `register` / `enable_city` rebuild it).
static func all() -> Array:
	if _list.is_empty():
		_build()
	return _list


static func by_id(id: String) -> Dictionary:
	for e: Dictionary in all():
		if str(e["id"]) == id:
			return e
	return DEFAULT if id == str(DEFAULT["id"]) else {}


## Adds (or replaces, same id) a place at runtime.
static func register(entry: Dictionary) -> void:
	var e := entry.duplicate(true)
	e["enabled"] = true
	for i in _extra.size():
		if str((_extra[i] as Dictionary)["id"]) == str(e["id"]):
			_extra[i] = e
			_list.clear()
			return
	_extra.append(e)
	_list.clear()


## Turns the Altavega city and its districts on (optionally moving the whole city by `offset`).
static func enable_city(on: bool = true, offset: Vector2 = Vector2.ZERO) -> void:
	_city_enabled = on
	_city_offset = offset
	_list.clear()


static var _city_offset: Vector2 = Vector2.ZERO


## Test hook: back to the static data.
static func reset() -> void:
	_extra.clear()
	_city_enabled = false
	_city_offset = Vector2.ZERO
	_list.clear()


static func _build() -> void:
	var out: Array = []
	# the slice's small zones inside the clearing (Regions.ZONES; "CLARO" folds into the clearing below)
	for z: Dictionary in Regions.ZONES:
		var n := str(z["name"])
		if not KNOWN.has(n):
			continue
		out.append(_entry(n, {"circle": [z["center"], float(z["radius"])]}))
	for r: Dictionary in PoiRegistry.REGIONS:
		var n := str(r["name"])
		var shape := {"rect": [r["center"], r["size"]]} if r.has("size") else {"circle": [r["center"], float(r["radius"])]}
		out.append(_entry(n, shape))
	if _city_enabled or bool(CITY.get("enabled", false)):
		for d: Dictionary in CITY["districts"]:
			var e := d.duplicate(true)
			e["kind"] = "district"
			e["parent"] = CITY["id"]
			e["temp"] = float(d.get("temp", CITY["temp"]))
			e["shape"] = _offset_shape(d["shape"], _city_offset)
			e["enabled"] = true
			out.append(e)
		var c := CITY.duplicate(true)
		c.erase("districts")
		c["shape"] = _offset_shape(CITY["shape"], _city_offset)
		c["enabled"] = true
		out.append(c)
	for e: Dictionary in _extra:
		out.append(e)
	for n: Dictionary in NATURAL:
		out.append(n.duplicate(true))
	# stable sort by specificity (districts before their city, POIs before villages…)
	var ranked: Array = []
	for i in out.size():
		ranked.append([int(RANK.get(str((out[i] as Dictionary).get("kind", "poi")), 5)), i, out[i]])
	ranked.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	_list = []
	for r: Array in ranked:
		_list.append(r[2])


static func _entry(region_name: String, shape: Dictionary) -> Dictionary:
	var k: Dictionary = KNOWN.get(region_name, {})
	var parent := str(k.get("parent", ""))
	if parent == "claro":
		parent = "claro_del_cazador"
	return {
		"id": _slug(str(k.get("name", region_name))), "name": str(k.get("name", region_name.capitalize())),
		"kind": str(k.get("kind", "poi")), "parent": parent, "danger": int(k.get("danger", 1)),
		"power": str(k.get("power", "")), "temp": float(k.get("temp", 0.0)), "shape": shape, "enabled": true,
	}


static func _offset_shape(shape: Dictionary, off: Vector2) -> Dictionary:
	var s := shape.duplicate(true)
	if s.has("rect"):
		s["rect"] = [(s["rect"][0] as Vector2) + off, s["rect"][1]]
	elif s.has("circle"):
		s["circle"] = [(s["circle"][0] as Vector2) + off, s["circle"][1]]
	return s


static func _slug(s: String) -> String:
	var t := s.to_lower()
	for pair in [["á", "a"], ["é", "e"], ["í", "i"], ["ó", "o"], ["ú", "u"], ["ñ", "n"], ["‑", "-"]]:
		t = t.replace(pair[0], pair[1])
	return t.replace(" ", "_").replace("-", "")


## Signed depth (m) of a point inside an entry: > 0 inside (distance to the border), < 0 outside.
static func depth(e: Dictionary, x: float, z: float) -> float:
	var shape: Dictionary = e["shape"]
	var p := Vector2(x, z)
	if shape.has("circle"):
		return float(shape["circle"][1]) - p.distance_to(shape["circle"][0])
	if shape.has("rect"):
		var c: Vector2 = shape["rect"][0]
		var h: Vector2 = (shape["rect"][1] as Vector2) * 0.5
		var d := (p - c).abs() - h
		if d.x <= 0.0 and d.y <= 0.0:
			return -maxf(d.x, d.y)
		return -Vector2(maxf(d.x, 0.0), maxf(d.y, 0.0)).length()
	match StringName(shape.get("fn", &"")):
		&"lake":
			return 40.0 - PoiRegistry.lake_sdf(x, z)
		&"road":
			var w := World.instance
			if w == null or not w.is_configured or w.hf == null:
				return -INF
			return 32.0 - w.hf.road_distance(x, z, 40.0, "highway")
		&"border":
			return maxf(absf(x), absf(z)) - (WorldConst.BORDER_START + 96.0)
		&"high_forest":
			return maxf(absf(x), absf(z)) - 900.0
		&"default":
			return INF
	return -INF


## Inset (m) the player must be inside before the place counts (12 m; half the size for small places).
static func inset(e: Dictionary) -> float:
	var shape: Dictionary = e["shape"]
	if shape.has("circle"):
		return minf(UiTokens.ZONE_INSET, float(shape["circle"][1]) * 0.5)
	if shape.has("rect"):
		var s: Vector2 = shape["rect"][1]
		return minf(UiTokens.ZONE_INSET, minf(s.x, s.y) * 0.25)
	return UiTokens.ZONE_INSET


## Chain of parents (display names), nearest first.
static func parents(e: Dictionary) -> Array:
	var out: Array = []
	var p := str(e.get("parent", ""))
	var guard := 0
	while p != "" and guard < 4:
		var pe := by_id(p)
		if pe.is_empty():
			break
		out.append(str(pe["name"]))
		p = str(pe.get("parent", ""))
		guard += 1
	return out


## Danger right now (0–3): the place's base, +1 at night.
static func danger_now(e: Dictionary, night: bool) -> int:
	return clampi(int(e.get("danger", 1)) + (1 if night else 0), 0, 3)


## The one-line facts of a card: parent · electricity · temperature · danger, as available (§V.4.4).
static func facts(e: Dictionary, air_c: float, night: bool) -> Array:
	var out: Array = []
	var ps := parents(e)
	var kind := str(e.get("kind", "poi"))
	if not ps.is_empty() and kind != "natural":
		out.append(ps[0])
	var power := str(e.get("power", ""))
	if POWER_NAMES.has(power):
		out.append(POWER_NAMES[power])
	out.append(UiTokens.temperature(air_c + float(e.get("temp", 0.0))))
	if kind != "natural" and kind != "road":
		out.append(DANGER_NAMES[danger_now(e, night)])
	return out
