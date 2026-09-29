class_name LocationInfo
## One named zone of the world (H2, PLAN C35; docs/research/10_hud_ux.md appendix §8.6): the record the zone title,
## the highway sign, the paper map, the mission anchors, the camera profile and the group discovery read. Records are
## plain Dictionaries (network / JSON friendly, cheap to copy) built by `Locations` from PoiRegistry (REGIONS,
## ROAD_REGIONS, the lake, the border ring…) and the slice's small zones; this script is their schema:
##   id        stable id (slug; the W1 regions keep PoiRegistry's `id`) — discovery is stored by it
##   name      display name in Spanish, display case ("Las Torres")
##   banner    the upper-case region banner name of PoiRegistry ("ALTAVEGA — LAS TORRES"; "" for fn-only zones)
##   kind      city | district | town | village | farm | poi | natural | road
##   parent    id of the enclosing zone ("" = top level): POI ⊂ district ⊂ city
##   shape     {"circle": [centre, radius]} | {"rect": [centre, size]} | {"poly": PackedVector2Array} |
##             {"multi": [shape, …]} (one zone drawn as several parts) | {"fn": &"lake" | &"border" | &"high_forest" |
##             &"default" | &"water:<id>" | &"road:<BANNER>"} (exact shapes computed by Locations)
##   danger    0–3 (bajo, moderado, alto, extremo; +1 at night on the card)
##   power     "" (unknown: no fact) | "off" (sin electricidad) | "generator" (con generador) | "on"
##   temp      °C added to the air temperature
##   zombies   [min, max] per chunk (doc 09 §4.3; PopulationTable reads PoiRegistry directly)
##   milestone the milestone that builds its content; reserved = only terrain + pad so far (W1)
##   tier      order tier (below): the most specific zone wins, like the region banner (PoiRegistry.region_at)
##   camera    camera profile id while the player is in it (C28: &"city" in Altavega's districts; &"" = default)
##   article   "el" | "la" | "los" | "las" | "" — for Spanish sentences ("Has salido del Hospital Provincial")
##   road      road zones: {"kind": highway | avenue | road | rail, "plate": "A‑14" | "N‑140" | ""}
##   aliases   other ids of the same zone (W1 draws «Urbanizaciones del norte» as two rects)

## Order tiers, most specific first (the banner order of PoiRegistry.region_at): places (POIs, districts, towns…),
## water, named roads, broad areas (the city, the sierras, La Vega), the border ring, the valley's high forest, the
## forest everywhere else.
enum Tier { PLACE, WATER, ROAD, BROAD, BORDER, HIGH_FOREST, DEFAULT }

const KINDS := ["city", "district", "town", "village", "farm", "poi", "natural", "road"]
const POWER_VALUES := ["", "off", "generator", "on"]
## Inside the PLACE tier: POIs before farms, villages / towns and districts (a POI ⊂ its district).
const KIND_RANK := {"poi": 0, "road": 0, "farm": 1, "natural": 2, "village": 2, "town": 2, "district": 3, "city": 4}
const REQUIRED := ["id", "name", "kind", "parent", "shape", "danger", "power", "temp", "tier"]

## Grammatical article by the first word of a common-noun name (names that start with El / La / Los / Las keep theirs;
## towns and villages have none).
const ARTICLE_OF_WORD := {
	"área": "el", "avión": "el", "bosque": "el", "casco": "el", "centro": "el", "claro": "el", "control": "el",
	"desfiladero": "el", "embalse": "el", "ensanche": "el", "estadio": "el", "ferrocarril": "el", "hospital": "el",
	"ibón": "el", "lago": "el", "parque": "el", "polígono": "el", "puente": "el", "puerto": "el", "punto": "el",
	"repetidor": "el", "río": "el", "túnel": "el",
	"autovía": "la", "barriada": "la", "base": "la", "cabaña": "la", "carretera": "la", "catedral": "la",
	"central": "la", "estación": "la", "gasolinera": "la", "granja": "la", "gran": "la", "jefatura": "la",
	"presa": "la", "ronda": "la", "sierra": "la", "torre": "la", "universidad": "la", "urbanización": "la",
	"urbanizaciones": "las", "químicas": "las", "pinos": "los",
}


## A record with every field (defaults for the missing ones).
static func make(id: String, display: String, kind: String, shape: Dictionary, data: Dictionary = {}) -> Dictionary:
	display = display.replace("\u2011", "\u2010")   # Barlow has no U+2011 (non-breaking hyphen): «N‐140», «A‐14»
	var e := {
		"id": id, "name": display, "banner": str(data.get("banner", "")), "kind": kind,
		"parent": str(data.get("parent", "")), "shape": shape, "danger": clampi(int(data.get("danger", 1)), 0, 3),
		"power": str(data.get("power", "")), "temp": float(data.get("temp", 0.0)),
		"zombies": data.get("zombies", [0, 0]), "milestone": str(data.get("milestone", "")),
		"reserved": bool(data.get("reserved", false)), "tier": int(data.get("tier", Tier.PLACE)),
		"camera": StringName(data.get("camera", &"")), "enabled": true,
	}
	e["article"] = str(data["article"]) if data.has("article") else guess_article(display, kind)
	if data.has("road"):
		e["road"] = data["road"]
	if data.has("aliases"):
		e["aliases"] = data["aliases"]
	return e


## Problems of a record ([] = valid): required fields, known kind / power, a usable shape.
static func validate(e: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for f in REQUIRED:
		if not e.has(f):
			out.append("%s: no %s" % [e.get("id", "?"), f])
	if out.is_empty():
		if not KINDS.has(str(e["kind"])):
			out.append("%s: kind %s" % [e["id"], e["kind"]])
		if not POWER_VALUES.has(str(e["power"])):
			out.append("%s: power %s" % [e["id"], e["power"]])
		if int(e["danger"]) < 0 or int(e["danger"]) > 3:
			out.append("%s: danger %s" % [e["id"], e["danger"]])
		var s: Dictionary = e["shape"]
		if not (s.has("circle") or s.has("rect") or s.has("poly") or s.has("multi") or s.has("fn")):
			out.append("%s: shape %s" % [e["id"], s.keys()])
		if str(e["name"]).strip_edges() == "":
			out.append("%s: empty name" % e["id"])
	return out


## Sort key, most specific first: the tier, then inside the PLACE tier the deeper level of the hierarchy (`level` =
## number of ancestors: a POI of a district of the city before the district, the district before a top-level place)
## and the kind (a POI before a district at the same level). Callers keep the source order for ties.
static func order_key(e: Dictionary, level: int) -> int:
	var tier := int(e.get("tier", Tier.PLACE))
	if tier != Tier.PLACE:
		return tier * 1000
	return (9 - clampi(level, 0, 9)) * 10 + int(KIND_RANK.get(str(e.get("kind", "poi")), 1))


# ------------------------------------------------------------------ geometry (fn shapes: Locations.depth)
## Signed depth (m) of (x, z) in a geometric shape: > 0 inside (distance to the border), < 0 outside. NAN for "fn".
static func shape_depth(shape: Dictionary, x: float, z: float) -> float:
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
	if shape.has("poly"):
		var poly: PackedVector2Array = shape["poly"]
		var best := INF
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			best = minf(best, Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p))
		return best if Geometry2D.is_point_in_polygon(p, poly) else -best
	if shape.has("multi"):
		var best := -INF
		for s: Dictionary in shape["multi"]:
			best = maxf(best, shape_depth(s, x, z))
		return best
	return NAN


## Representative point of a shape (map label, mission anchor, sign distance): the centre, the polygon's centroid,
## the largest part of a multi shape. Vector2.INF for "fn" shapes.
static func shape_center(shape: Dictionary) -> Vector2:
	if shape.has("circle"):
		return shape["circle"][0]
	if shape.has("rect"):
		return shape["rect"][0]
	if shape.has("poly"):
		var poly: PackedVector2Array = shape["poly"]
		var c := Vector2.ZERO
		for q in poly:
			c += q
		return c / maxf(float(poly.size()), 1.0)
	if shape.has("multi"):
		var best := Vector2.INF
		var best_a := -1.0
		for s: Dictionary in shape["multi"]:
			var a := shape_area(s)
			if a > best_a:
				best_a = a
				best = shape_center(s)
		return best
	return Vector2.INF


static func shape_area(shape: Dictionary) -> float:
	if shape.has("circle"):
		return PI * pow(float(shape["circle"][1]), 2.0)
	if shape.has("rect"):
		var s: Vector2 = shape["rect"][1]
		return s.x * s.y
	if shape.has("poly"):
		var poly: PackedVector2Array = shape["poly"]
		var a := 0.0
		for i in poly.size():
			a += poly[i].cross(poly[(i + 1) % poly.size()])
		return absf(a) * 0.5
	if shape.has("multi"):
		var t := 0.0
		for s: Dictionary in shape["multi"]:
			t += shape_area(s)
		return t
	return INF


## Smallest dimension (m) of a shape (the entry inset of small places); INF for "fn" shapes.
static func shape_min_size(shape: Dictionary) -> float:
	if shape.has("circle"):
		return float(shape["circle"][1]) * 2.0
	if shape.has("rect"):
		var s: Vector2 = shape["rect"][1]
		return minf(s.x, s.y)
	if shape.has("poly"):
		var poly: PackedVector2Array = shape["poly"]
		var r := Rect2(poly[0], Vector2.ZERO)
		for q in poly:
			r = r.expand(q)
		return minf(r.size.x, r.size.y)
	if shape.has("multi"):
		var m := INF
		for s: Dictionary in shape["multi"]:
			m = minf(m, shape_min_size(s))
		return m
	return INF


# ------------------------------------------------------------------ Spanish
static func guess_article(display: String, kind: String) -> String:
	if kind in ["city", "town", "village"]:
		return ""
	var first := display.strip_edges().split(" ")[0]
	if first in ["El", "La", "Los", "Las"]:
		return ""   # part of the proper name ("Las Torres", "El Embarcadero")
	return str(ARTICLE_OF_WORD.get(first.to_lower(), ""))


## "del Hospital Provincial", "de la Catedral de Altavega", "de Las Torres", "de Valdenieve".
static func de(e: Dictionary) -> String:
	var n := str(e.get("name", ""))
	match str(e.get("article", "")):
		"el":
			return "del " + n
		"la":
			return "de la " + n
		"los":
			return "de los " + n
		"las":
			return "de las " + n
	return "de " + n
