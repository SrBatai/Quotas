class_name CityLots
extends RefCounted
## Altavega lot data (C0 «Escaparate de Altavega», PLAN v3.8.2 C0 / C26; doc 09 §4.5): reads
## data/world/city/altavega_lots.json (v0, written by hand, `city_version` 0 = WorldConst.CITY_VERSION) and turns
## it into per-chunk items for the streamer. The city is DATA, the same bytes on every client and server (doc 09 §4.4
## «Determinismo»): the layout never depends on the world seed; only the dressing does (the Gran Vía jam: model,
## variant, spacing by hash64(seed, GEN_CITY, jam, lane, slot)). Heights come from the HeightFunction (pure).
##
## Items (Dictionary, metres, world space; `k` = Kind):
##   PODIUM   non-enterable zócalo (CityProcedural building: Base / Roof / ShadowProxy), roof walkable, optional stair
##   TOWER    A1 tower assembled by TowerAssembler (Base + N floor groups + Roof + ShadowProxy) on its podium's roof
##   BRIDGE   one chunk-long segment of the provisional Puente de Hierro (deck profile from the terrain at its ends)
##   VEHICLE  static wreck (A1 car, variant); jam cars carry the seed dressing
##   PROP     street furniture / barriers / lamps (`lamp`: a CityLights lamp at `bulb`)
## An item belongs to the chunk that contains its centre (a podium is ≤ 52 m: its chunk is always in ring 1 of any
## point of it); the bridge is split per chunk. load_default() must run on the main thread before any ChunkJob
## (World.configure does it); afterwards everything here is read-only and safe from the worker threads.

const PATH := "res://data/world/city/altavega_lots.json"
## Hash generator id of the city ("CITY"): wids and the seeded dressing (PLAN C26: hash64(seed, GEN_CITY, lot, …)).
const GEN_CITY := 0x43495459
enum Kind { PODIUM, TOWER, BRIDGE, VEHICLE, PROP }
const FACING := {"west": -90.0, "east": 90.0, "north": 180.0, "south": 0.0}
const VARIANTS := ["clean", "snowed", "crashed", "doors", "burnt"]
## Parapet height of the podium roofs (m, CityProcedural) and the stair landing depth.
const PARAPET := 1.1
const LANDING := 3.0

static var _data: Dictionary = {}
static var _loaded: bool = false
static var _problems := PackedStringArray()
static var _file_sha: String = ""
static var _content_sha: String = ""
static var _static_by_chunk: Dictionary = {}     # chunk key -> Array[Dictionary] (layout items, no heights)
static var _chunks_with_jam: Dictionary = {}     # chunk key -> true (a jam lane crosses it)
static var _podiums: Dictionary = {}             # id -> podium record
static var _footprints: Array = []               # [Rect2 (world, axis-aligned bounds), kind] of buildings and vehicles
static var _clear: Array[Rect2] = []
static var _bridge: Dictionary = {}


# ------------------------------------------------------------------ loading
## Loads and validates the lot file once (main thread). False when it is missing or does not validate.
static func load_default() -> bool:
	if _loaded:
		return _problems.is_empty()
	_loaded = true
	if not FileAccess.file_exists(PATH):
		_problems.append("missing %s" % PATH)
		return false
	var bytes := FileAccess.get_file_as_bytes(PATH)
	_file_sha = _sha(bytes)
	var parsed = JSON.parse_string(bytes.get_string_from_utf8())
	if not (parsed is Dictionary):
		_problems.append("%s is not a JSON object" % PATH)
		return false
	_data = parsed
	# content hash: the parsed data re-serialised with sorted keys (line endings / whitespace do not matter)
	_content_sha = _sha(JSON.stringify(_data, "", true, true).to_utf8_buffer())
	_problems = validate(_data)
	if not _problems.is_empty():
		for p in _problems:
			push_error("CityLots: %s" % p)
		return false
	_index()
	return true


static func is_loaded() -> bool:
	return _loaded and _problems.is_empty() and not _data.is_empty()


static func problems() -> PackedStringArray:
	return _problems


static func data() -> Dictionary:
	return _data


## SHA-256 of the file bytes (hex).
static func file_hash() -> String:
	return _file_sha


## SHA-256 of the parsed content with sorted keys (hex): what client and server compare (CRLF checkouts agree).
static func content_hash() -> String:
	return _content_sha


static func city_version() -> int:
	return int(_data.get("city_version", -1))


static func _sha(bytes: PackedByteArray) -> String:
	var hc := HashingContext.new()
	hc.start(HashingContext.HASH_SHA256)
	hc.update(bytes)
	return hc.finish().hex_encode()


static func cm(v) -> float:
	return float(v) / 100.0


static func v2(a) -> Vector2:
	return Vector2(cm(a[0]), cm(a[1]))


static func rect_of(a) -> Rect2:
	var p0 := Vector2(cm(a[0]), cm(a[1]))
	var p1 := Vector2(cm(a[2]), cm(a[3]))
	return Rect2(p0, p1 - p0).abs()


## Problems of a lot file (empty = valid): version, ids, families, groups, references, models.
static func validate(d: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	if str(d.get("format", "")) != "altavega_lots":
		out.append("format is not altavega_lots")
	if int(d.get("city_version", -1)) != WorldConst.CITY_VERSION:
		out.append("city_version %s != WorldConst.CITY_VERSION %d" % [d.get("city_version"), WorldConst.CITY_VERSION])
	var ids := {}
	var families: Dictionary = d.get("families", {})
	var models: Dictionary = d.get("models", {})
	var podiums := {}
	for p in d.get("podiums", []):
		podiums[int(p["id"])] = p
	for list_name in ["podiums", "towers", "vehicles", "props", "rows", "jams", "miradores", "camera_zones"]:
		for it in d.get(list_name, []):
			var id := int(it.get("id", -1))
			if id <= 0 or ids.has(id):
				out.append("%s: id %s missing or duplicated" % [list_name, it.get("id")])
			ids[id] = true
	for t in d.get("towers", []):
		var f := str(t.get("family", ""))
		if not families.has(f):
			out.append("tower %s: unknown family %s" % [t["id"], f])
			continue
		if int(t.get("groups", 0)) < int(families[f]["full_groups"]):
			out.append("tower %s: groups %d < the family's %d (only extra floor groups can be stacked)" % [t["id"], int(t["groups"]), int(families[f]["full_groups"])])
		if not podiums.has(int(t.get("on", -1))):
			out.append("tower %s: podium %s not found" % [t["id"], t.get("on")])
	for list_name in ["vehicles", "props", "rows"]:
		for it in d.get(list_name, []):
			if not models.has(str(it.get("model", ""))):
				out.append("%s %s: model %s not in models" % [list_name, it.get("id"), it.get("model")])
	for j in d.get("jams", []):
		for m in j.get("models", {}):
			if not models.has(str(m)):
				out.append("jam %s: model %s not in models" % [j["id"], m])
		for v in j.get("variants", {}):
			if not VARIANTS.has(str(v)):
				out.append("jam %s: unknown variant %s" % [j["id"], v])
	for m in d.get("miradores", []):
		if not podiums.has(int(m.get("on", -1))):
			out.append("mirador %s: podium %s not found" % [m["id"], m.get("on")])
	return out


## Floors of an assembled tower: 4 (Base) + 4 per floor group + the family's partial top group + 1 (Roof floor).
static func tower_floors(t: Dictionary) -> int:
	var f: Dictionary = _data["families"][str(t["family"])]
	return 4 + 4 * int(t["groups"]) + int(f["top_floors"]) + 1


## Extra height of an assembled tower over its family model (m): the floor groups stacked on top of the model's.
static func tower_shift(t: Dictionary) -> float:
	var f: Dictionary = _data["families"][str(t["family"])]
	return float(int(t["groups"]) - int(f["full_groups"])) * 4.0 * cm(f["floor_h"])


static func podium(id: int) -> Dictionary:
	return _podiums.get(id, {})


## Roof slab level of a podium over its base (m).
static func podium_roof(p: Dictionary) -> float:
	return cm(p["ground_h"]) + float(int(p["floors"]) - 1) * cm(p["floor_h"])


# ------------------------------------------------------------------ static index (layout, seed independent)
static func _index() -> void:
	_static_by_chunk.clear()
	_footprints.clear()
	_clear.clear()
	_podiums.clear()
	for c in _data.get("clear", []):
		_clear.append(rect_of(c))
	for p in _data.get("podiums", []):
		_podiums[int(p["id"])] = p
		var it := {"k": Kind.PODIUM, "id": int(p["id"]), "pos": v2(p["pos"]), "yaw": float(p.get("yaw", 0.0)),
			"size": v2(p["size"]), "floors": int(p["floors"]), "ground_h": cm(p["ground_h"]), "floor_h": cm(p["floor_h"]),
			"style": str(p.get("style", "concrete")), "generator": bool(p.get("generator", false)), "stair": p.get("stair", {}),
			"wid": WorldConst.hash64(GEN_CITY, WorldConst.CITY_VERSION, int(p["id"]), 0)}
		_add(it)
		_footprints.append([_obb_bounds(it["pos"], it["size"], it["yaw"]), Kind.PODIUM])
	for t in _data.get("towers", []):
		var fam: Dictionary = _data["families"][str(t["family"])]
		var it := {"k": Kind.TOWER, "id": int(t["id"]), "pos": v2(t["pos"]), "yaw": float(t.get("yaw", 0.0)),
			"family": str(t["family"]), "model": str(fam["model"]), "groups": int(t["groups"]), "on": int(t["on"]),
			"floors": tower_floors(t), "shift": tower_shift(t), "generator": bool(t.get("generator", false)),
			"wid": WorldConst.hash64(GEN_CITY, WorldConst.CITY_VERSION, int(t["id"]), 0)}
		_add(it)
	for v in _data.get("vehicles", []):
		var it := _model_item(Kind.VEHICLE, v, v2(v["pos"]), float(v.get("yaw", 0.0)), 0)
		it["variant"] = str(v.get("variant", "snowed"))
		_add(it)
		var sz := model_size(str(v["model"]))
		_footprints.append([_obb_bounds(it["pos"], Vector2(sz.x, sz.z), it["yaw"]), Kind.VEHICLE])
	for p in _data.get("props", []):
		_add(_model_item(Kind.PROP, p, v2(p["pos"]), float(p.get("yaw", 0.0)), 0))
	for r in _data.get("rows", []):
		var a := v2(r["from"])
		var b := v2(r["to"])
		var step := cm(r["step"])
		var n := int(floor(a.distance_to(b) / step + 0.001)) + 1
		for i in n:
			var p := a + (b - a).normalized() * step * float(i) if a.distance_to(b) > 0.01 else a
			_add(_model_item(Kind.PROP, r, p, float(r.get("yaw", 0.0)), i))
	_bridge = _data.get("bridge", {})
	if not _bridge.is_empty():
		var x0 := cm(_bridge["x_from"])
		var x1 := cm(_bridge["x_to"])
		var z := cm(_bridge["axis_z"])
		var cz := WorldConst.chunk_of(z)
		for cx in range(WorldConst.chunk_of(x0), WorldConst.chunk_of(x1) + 1):
			var r := WorldConst.chunk_rect(cx, cz)
			var sx0 := maxf(x0, r.position.x)
			var sx1 := minf(x1, r.end.x)
			if sx1 - sx0 < 0.01:
				continue
			var key := WorldConst.key(cx, cz)
			if not _static_by_chunk.has(key):
				_static_by_chunk[key] = []
			(_static_by_chunk[key] as Array).append({"k": Kind.BRIDGE, "id": int(_bridge["id"]), "x0": sx0, "x1": sx1, "pos": Vector2((sx0 + sx1) * 0.5, z),
				"wid": WorldConst.hash64(GEN_CITY, WorldConst.CITY_VERSION, int(_bridge["id"]), cx)})
	for j in _data.get("jams", []):
		var x0 := cm(j["x_from"])
		var x1 := cm(j["x_to"])
		for lane in j["lanes"]:
			var z := cm(j["axis_z"]) + cm(lane)
			for cx in range(WorldConst.chunk_of(x0 - 8.0), WorldConst.chunk_of(x1 + 8.0) + 1):
				_chunks_with_jam[WorldConst.key(cx, WorldConst.chunk_of(z))] = true


static func _model_item(kind: int, src: Dictionary, pos: Vector2, yaw: float, index: int) -> Dictionary:
	var m := str(src["model"])
	var md: Dictionary = _data["models"][m]
	var it := {"k": kind, "id": int(src["id"]), "model": m, "dir": str(md.get("dir", "props")), "pos": pos, "yaw": yaw,
		"lamp": bool(src.get("lamp", false)),
		"wid": WorldConst.hash64(GEN_CITY, WorldConst.CITY_VERSION, int(src["id"]), index)}
	return it


static func _add(it: Dictionary) -> void:
	var p: Vector2 = it["pos"]
	var key := WorldConst.key(WorldConst.chunk_of(p.x), WorldConst.chunk_of(p.y))
	if not _static_by_chunk.has(key):
		_static_by_chunk[key] = []
	(_static_by_chunk[key] as Array).append(it)


## World AABB (xz) of a footprint `size` centred at `pos`, turned by `yaw_deg`.
static func _obb_bounds(pos: Vector2, size: Vector2, yaw_deg: float) -> Rect2:
	var a := deg_to_rad(yaw_deg)
	var ex := absf(cos(a)) * size.x * 0.5 + absf(sin(a)) * size.y * 0.5
	var ez := absf(sin(a)) * size.x * 0.5 + absf(cos(a)) * size.y * 0.5
	return Rect2(pos - Vector2(ex, ez), Vector2(ex, ez) * 2.0)


## [width x, height y, length z] of a model (m) for colliders and fallbacks.
static func model_size(m: String) -> Vector3:
	var md: Dictionary = _data.get("models", {}).get(m, {})
	var s: Array = md.get("size", [100, 100, 100])
	return Vector3(cm(s[0]), cm(s[1]), cm(s[2]))


static func model_info(m: String) -> Dictionary:
	return _data.get("models", {}).get(m, {})


## Chunks that have city items (static layout or a jam lane): the streamer / tests.
static func chunk_keys() -> Array:
	var out := {}
	for k in _static_by_chunk:
		out[k] = true
	for k in _chunks_with_jam:
		out[k] = true
	var arr := out.keys()
	arr.sort()
	return arr


static func has_chunk(cx: int, cz: int) -> bool:
	var k := WorldConst.key(cx, cz)
	return _static_by_chunk.has(k) or _chunks_with_jam.has(k)


# ------------------------------------------------------------------ queries used by the ChunkJob (worker threads)
## Is (x, z) inside the city area where the procedural scatter is not placed (streets, block, bridge approaches)?
static func is_cleared(x: float, z: float) -> bool:
	for r in _clear:
		if r.has_point(Vector2(x, z)):
			return true
	return false


static func clears_rect(rect: Rect2) -> bool:
	for r in _clear:
		if r.intersects(rect):
			return true
	return false


## Is (x, z) inside a building or a static vehicle footprint (+ margin)? Zombie spawns, tests.
static func occupied(x: float, z: float, margin: float = 0.5) -> bool:
	var p := Vector2(x, z)
	for f in _footprints:
		if (f[0] as Rect2).grow(margin).has_point(p):
			return true
	return false


## Street surface rects crossing `rect`: [Rect2, kind ("road" | "walk"), axis ("x" | "z")].
static func streets_in(rect: Rect2) -> Array:
	var out: Array = []
	for s in _data.get("streets", []):
		var r := rect_of(s["rect"])
		if r.intersects(rect):
			out.append([r, str(s["kind"]), str(s.get("axis", "x"))])
	return out


## Deck height of the Puente de Hierro at x (terrain heights at its two ends from `hf`). NAN off the bridge.
static func bridge_deck(hf: HeightFunction, x: float, z: float) -> float:
	if _bridge.is_empty():
		return NAN
	var x0 := cm(_bridge["x_from"])
	var x1 := cm(_bridge["x_to"])
	if x < x0 or x > x1 or absf(z - cm(_bridge["axis_z"])) > cm(_bridge["width"]) * 0.5 + 0.01:
		return NAN
	return deck_profile(x, bridge_ends(hf))


## [terrain height at the west end, at the east end] of the bridge (the ramps meet the ground there).
static func bridge_ends(hf: HeightFunction) -> Vector2:
	var z := cm(_bridge["axis_z"])
	return Vector2(hf.height_at(cm(_bridge["x_from"]), z), hf.height_at(cm(_bridge["x_to"]), z))


static func deck_profile(x: float, ends: Vector2) -> float:
	var x0 := cm(_bridge["x_from"])
	var x1 := cm(_bridge["x_to"])
	var h := cm(_bridge["deck_y"])
	var ramp := cm(_bridge["ramp"])
	if x < x0 + ramp:
		return lerpf(ends.x, h, clampf((x - x0) / ramp, 0.0, 1.0))
	if x > x1 - ramp:
		return lerpf(h, ends.y, clampf((x - (x1 - ramp)) / ramp, 0.0, 1.0))
	return h


static func bridge() -> Dictionary:
	return _bridge


## Base height of a podium: the lowest terrain sample of its footprint corners and centre (it never floats; the
## plinth below 0 hides the higher corners). Pure: every chunk that needs it (the podium's, a tower's) agrees.
static func podium_base(hf: HeightFunction, p_id: int) -> float:
	var p: Dictionary = _podiums.get(p_id, {})
	if p.is_empty():
		return 0.0
	var c := v2(p["pos"])
	var s := v2(p["size"]) * 0.5
	var a := deg_to_rad(float(p.get("yaw", 0.0)))
	var h := hf.height_at(c.x, c.y)
	for q in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var o := Vector2(q.x * s.x, q.y * s.y).rotated(-a)
		h = minf(h, hf.height_at(c.x + o.x, c.y + o.y))
	return h - 0.05


## Every city item of chunk (cx, cz) with its heights, for the world seed (layout + seeded jam dressing).
## `height` = Callable(x, z) -> float for points inside the chunk (ChunkJob.height_local: bilinear on its samples).
static func chunk_items(hf: HeightFunction, cx: int, cz: int, height: Callable) -> Array:
	var key := WorldConst.key(cx, cz)
	var out: Array = []
	if not is_loaded():
		return out
	var ends := Vector2(NAN, NAN)
	var need_ends := false
	for it in _static_by_chunk.get(key, []):
		var e: Dictionary = (it as Dictionary).duplicate()
		var p: Vector2 = e["pos"]
		match int(e["k"]):
			Kind.PODIUM:
				e["y"] = podium_base(hf, int(e["id"]))
			Kind.TOWER:
				var pod: Dictionary = _podiums[int(e["on"])]
				e["y"] = podium_base(hf, int(e["on"])) + podium_roof(pod)
			Kind.BRIDGE:
				need_ends = true
			_:
				e["y"] = NAN
		out.append(e)
	var jams: Array = []
	if _chunks_with_jam.has(key):
		jams = jam_items(hf.world_seed, WorldConst.chunk_rect(cx, cz))
		out.append_array(jams)
	for e in out:
		if int(e["k"]) == Kind.BRIDGE:
			continue
		if e.has("y") and not is_nan(float(e["y"])):
			continue
		var p: Vector2 = e["pos"]
		if not _bridge.is_empty() and absf(p.y - cm(_bridge["axis_z"])) <= cm(_bridge["width"]) * 0.5 and p.x >= cm(_bridge["x_from"]) and p.x <= cm(_bridge["x_to"]):
			need_ends = true
	if need_ends:
		ends = bridge_ends(hf)
	for e in out:
		var p: Vector2 = e["pos"]
		if int(e["k"]) == Kind.BRIDGE:
			e["ends"] = ends
			e["y"] = deck_profile(p.x, ends)
			continue
		if e.has("y") and not is_nan(float(e["y"])):
			continue
		var on_deck := not _bridge.is_empty() and absf(p.y - cm(_bridge["axis_z"])) <= cm(_bridge["width"]) * 0.5 \
			and p.x >= cm(_bridge["x_from"]) and p.x <= cm(_bridge["x_to"])
		e["y"] = deck_profile(p.x, ends) if on_deck else float(height.call(p.x, p.y))
	return out


## Items (no heights) of the chunks around `rect` whose footprint may reach it, + the jam cars in it: contact AO.
static func items_near(seed_v: int, rect: Rect2) -> Array:
	var out: Array = []
	if not is_loaded():
		return out
	var g := rect.grow(40.0)
	for cz in range(WorldConst.chunk_of(g.position.y), WorldConst.chunk_of(g.end.y) + 1):
		for cx in range(WorldConst.chunk_of(g.position.x), WorldConst.chunk_of(g.end.x) + 1):
			for it in _static_by_chunk.get(WorldConst.key(cx, cz), []):
				out.append(it)
	for j in jam_items(seed_v, rect.grow(4.0)):
		out.append(j)
	return out


## Jam cars (seeded dressing) whose centre lies in `rect`. Pure: hash64(seed, GEN_CITY, jam id, lane, slot).
static func jam_items(seed_v: int, rect: Rect2) -> Array:
	var out: Array = []
	for j in _data.get("jams", []):
		var x0 := cm(j["x_from"])
		var x1 := cm(j["x_to"])
		if rect.end.x < x0 - 8.0 or rect.position.x > x1 + 8.0:
			continue
		var models: Dictionary = j["models"]
		var variants: Dictionary = j["variants"]
		var facing := float(FACING.get(str(j.get("facing", "west")), -90.0))
		var gap: Array = j["gap"]
		var lanes: Array = j["lanes"]
		for li in lanes.size():
			var z := cm(j["axis_z"]) + cm(lanes[li])
			if z < rect.position.y - 3.0 or z > rect.end.y + 3.0:
				continue
			# the queue's head is the end it faces (west: x_from); cars stack back from it
			var cursor := 0.0
			var length := x1 - x0
			var slot := 0
			while cursor < length and slot < 400:
				var h := WorldConst.hash64(seed_v, GEN_CITY, int(j["id"]), li, slot)
				slot += 1
				var m := _pick(models, WorldConst.unit(WorldConst.hash64(h, 1)))
				var sz := model_size(m)
				var g := cm(gap[0]) + WorldConst.unit(WorldConst.hash64(h, 3)) * (cm(gap[1]) - cm(gap[0]))
				if WorldConst.unit(WorldConst.hash64(h, 0)) < float(j.get("skip", 0.0)):
					cursor += sz.z + g   # an empty place in the queue
					continue
				var along := cursor + sz.z * 0.5
				cursor += sz.z + g
				if along > length:
					break
				var x := x0 + along if facing < 0.0 else x1 - along
				var lat := (WorldConst.unit(WorldConst.hash64(h, 4)) - 0.5) * 2.0 * cm(j.get("jitter", 0))
				var p := Vector2(x, z + lat)
				if not rect.has_point(p):
					continue
				var yaw := facing + (WorldConst.unit(WorldConst.hash64(h, 5)) - 0.5) * 2.0 * float(j.get("yaw_jitter", 0.0))
				if WorldConst.unit(WorldConst.hash64(h, 6)) < float(j.get("askew", 0.0)):
					yaw += (20.0 + 20.0 * WorldConst.unit(WorldConst.hash64(h, 7))) * (1.0 if (h >> 9) & 1 == 1 else -1.0)
				var v := _pick(variants, WorldConst.unit(WorldConst.hash64(h, 2)))
				if _blocked(p, sz):
					continue
				var md: Dictionary = _data["models"][m]
				out.append({"k": Kind.VEHICLE, "id": int(j["id"]), "model": m, "dir": str(md.get("dir", "vehicles")), "variant": v,
					"pos": p, "yaw": snappedf(yaw, 0.01), "lamp": false, "jam": true, "wid": WorldConst.hash64(seed_v, GEN_CITY, int(j["id"]), li, slot)})
	return out


## A jam car would sit on a fixed vehicle or a barrier (circle test with the fixed items of its chunk and the next).
static func _blocked(p: Vector2, sz: Vector3) -> bool:
	var r := maxf(sz.x, sz.z) * 0.5
	for dx in [-1, 0, 1]:
		var key := WorldConst.key(WorldConst.chunk_of(p.x) + dx, WorldConst.chunk_of(p.y))
		for it in _static_by_chunk.get(key, []):
			var k := int(it["k"])
			if k != Kind.VEHICLE and k != Kind.PROP:
				continue
			var s2 := model_size(str(it["model"]))
			var r2 := maxf(s2.x, s2.z) * 0.5
			if (it["pos"] as Vector2).distance_to(p) < (r + r2) * 0.8:
				return true
	return false


static func _pick(weights: Dictionary, u: float) -> String:
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	var acc := 0.0
	var keys := weights.keys()
	for k in keys:
		acc += float(weights[k]) / total
		if u < acc:
			return str(k)
	return str(keys[keys.size() - 1])


# ------------------------------------------------------------------ world-level records (not streamed)
static func miradores() -> Array:
	return _data.get("miradores", [])


static func camera_zones() -> Array:
	return _data.get("camera_zones", [])


static func silhouettes() -> Dictionary:
	return _data.get("silhouettes", {})


static func families() -> Dictionary:
	return _data.get("families", {})


static func towers() -> Array:
	return _data.get("towers", [])


static func podiums() -> Array:
	return _data.get("podiums", [])


## Power of the city v0: grid level (0 = blackout) and the lot ids with a generator.
static func power() -> Dictionary:
	return _data.get("power", {"grid": 0.0, "generators": []})


## Canonical text of every item of the city for a seed (tests: client vs server): one line per item, cm integers.
static func items_digest(hf: HeightFunction) -> String:
	var hc := HashingContext.new()
	hc.start(HashingContext.HASH_SHA256)
	var n := 0
	for key in chunk_keys():
		var cx := WorldConst.key_cx(key)
		var cz := WorldConst.key_cz(key)
		for e in chunk_items(hf, cx, cz, func(x: float, z: float) -> float: return hf.height_at(x, z)):
			hc.update(item_line(e).to_utf8_buffer())
			n += 1
	return "%s items=%d" % [hc.finish().hex_encode(), n]


static func item_line(e: Dictionary) -> String:
	var p: Vector2 = e["pos"]
	return "%d %d %s %s %d %d %d %d %d\n" % [int(e["k"]), int(e["id"]), str(e.get("model", e.get("family", ""))), str(e.get("variant", "")),
		int(round(p.x * 100.0)), int(round(p.y * 100.0)), int(round(float(e.get("y", 0.0)) * 100.0)), int(round(float(e.get("yaw", 0.0)) * 100.0)), int(e["wid"])]
