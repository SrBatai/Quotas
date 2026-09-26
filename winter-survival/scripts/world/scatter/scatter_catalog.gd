class_name ScatterCatalog
## Everything the scatter can place as a MultiMesh instance (ASSET_SPEC v2 §13 / M3.2 "MultiMesh‑friendly": one
## mesh, one `palette_vcol` surface, no children, no embedded collision — the code puts the shapes). Variant index
## = position in VARIANTS (stable: new variants are appended; deltas refer to entries by wid, never by index).
## Models are looked up by name in assets/models/{vegetation,props,poi,}/ (Assets.model_path); a missing one renders
## as its placeholder and the real .glb is picked up automatically.
##
## Fields: name (model), kind, chop ("" or the chop class: pine / dead / log / young), col ({t: "cyl" | "sphere" |
## "box" | "", s: [r, h] | [r] | [x, y, z], c: centre in the model frame}), layer (collision layer bits: 1 world,
## 64 placement blocker), occ ([radius, strength] of the baked terrain AO disc, × scale), shadow, pick ([radius,
## height] of the hover cylinder for choppable entries).
## The collision proxies of the Opus assets come from assets/models/{vegetation,props}/manifest.json when present
## (`load_manifests`, called once on the main thread before any chunk job); the slice variants (pine_a/b/c,
## dead_tree, fallen_log, rock_a/b/c, stump) keep the slice's own shapes so the clearing plays exactly as before.

enum Kind { TREE, LOG, ROCK, STUMP, BUSH, SNOW, DECO }

const MANIFESTS := ["res://assets/models/vegetation/manifest.json", "res://assets/models/props/manifest.json"]
const LEGACY := ["pine_a", "pine_b", "pine_c", "dead_tree", "fallen_log", "rock_a", "rock_b", "rock_c", "stump"]

const VARIANTS := [
	{"name": "pine_a", "kind": Kind.TREE, "chop": "pine", "col": {"t": "cyl", "s": [0.35, 3.0], "c": Vector3(0, 1.5, 0)}, "layer": 65, "occ": [1.7, 0.45], "shadow": true, "pick": [1.1, 7.0]},
	{"name": "pine_b", "kind": Kind.TREE, "chop": "pine", "col": {"t": "cyl", "s": [0.35, 3.0], "c": Vector3(0, 1.5, 0)}, "layer": 65, "occ": [1.2, 0.45], "shadow": true, "pick": [1.1, 5.5]},
	{"name": "pine_c", "kind": Kind.TREE, "chop": "pine", "col": {"t": "cyl", "s": [0.35, 3.0], "c": Vector3(0, 1.5, 0)}, "layer": 65, "occ": [1.0, 0.45], "shadow": true, "pick": [1.1, 4.2]},
	{"name": "pine_d", "kind": Kind.TREE, "chop": "pine", "col": {"t": "cyl", "s": [0.33, 3.0], "c": Vector3(0, 1.5, 0)}, "layer": 65, "occ": [1.9, 0.45], "shadow": true, "pick": [1.17, 9.0]},
	{"name": "pine_e", "kind": Kind.TREE, "chop": "pine", "col": {"t": "cyl", "s": [0.32, 3.0], "c": Vector3(0, 1.5, 0)}, "layer": 65, "occ": [1.8, 0.45], "shadow": true, "pick": [1.18, 7.1]},
	{"name": "pine_young", "kind": Kind.TREE, "chop": "young", "col": {"t": "cyl", "s": [0.135, 1.6], "c": Vector3(0, 0.8, 0)}, "layer": 65, "occ": [0.8, 0.35], "shadow": true, "pick": [0.8, 2.6]},
	{"name": "dead_tree", "kind": Kind.TREE, "chop": "dead", "col": {"t": "cyl", "s": [0.35, 3.0], "c": Vector3(0, 1.5, 0)}, "layer": 65, "occ": [0.7, 0.4], "shadow": true, "pick": [0.6, 4.2]},
	{"name": "dead_tree_b", "kind": Kind.TREE, "chop": "dead", "col": {"t": "cyl", "s": [0.4, 3.0], "c": Vector3(0, 1.5, 0)}, "layer": 65, "occ": [0.8, 0.4], "shadow": true, "pick": [0.61, 5.6]},
	{"name": "fallen_log", "kind": Kind.LOG, "chop": "log", "col": {"t": "box", "s": [1.6, 0.4, 0.4], "c": Vector3(0, 0.2, 0)}, "layer": 65, "occ": [1.1, 0.4], "shadow": true, "pick": [0.95, 0.8]},
	{"name": "fallen_log_b", "kind": Kind.LOG, "chop": "log", "col": {"t": "box", "s": [3.4, 0.45, 0.5], "c": Vector3(0, 0.22, 0)}, "layer": 65, "occ": [1.6, 0.4], "shadow": true, "pick": [1.8, 0.8]},
	{"name": "stump", "kind": Kind.STUMP, "chop": "", "col": {"t": "cyl", "s": [0.3, 0.5], "c": Vector3(0, 0.25, 0)}, "layer": 1, "occ": [0.45, 0.3], "shadow": true, "pick": []},
	{"name": "rock_a", "kind": Kind.ROCK, "chop": "", "col": {"t": "sphere", "s": [0.55], "c": Vector3(0, 0.4, 0)}, "layer": 65, "occ": [0.8, 0.5], "shadow": true, "pick": []},
	{"name": "rock_b", "kind": Kind.ROCK, "chop": "", "col": {"t": "sphere", "s": [0.9], "c": Vector3(0, 0.6, 0)}, "layer": 65, "occ": [1.3, 0.5], "shadow": true, "pick": []},
	{"name": "rock_c", "kind": Kind.ROCK, "chop": "", "col": {"t": "sphere", "s": [0.3], "c": Vector3(0, 0.2, 0)}, "layer": 65, "occ": [0.5, 0.5], "shadow": true, "pick": []},
	{"name": "rock_d", "kind": Kind.ROCK, "chop": "", "col": {"t": "box", "s": [2.3, 0.5, 1.5], "c": Vector3(0, 0.25, 0)}, "layer": 65, "occ": [1.3, 0.45], "shadow": true, "pick": []},
	{"name": "rock_e", "kind": Kind.ROCK, "chop": "", "col": {"t": "box", "s": [3.0, 2.0, 2.3], "c": Vector3(0, 1.0, 0)}, "layer": 65, "occ": [2.0, 0.5], "shadow": true, "pick": []},
	{"name": "bush_a", "kind": Kind.BUSH, "chop": "", "col": {"t": "sphere", "s": [0.5], "c": Vector3(0, 0.35, 0)}, "layer": 64, "occ": [0.75, 0.35], "shadow": true, "pick": []},
	{"name": "bush_b", "kind": Kind.BUSH, "chop": "", "col": {"t": "sphere", "s": [0.45], "c": Vector3(0, 0.38, 0)}, "layer": 64, "occ": [0.65, 0.35], "shadow": true, "pick": []},
	{"name": "snow_pile_a", "kind": Kind.SNOW, "chop": "", "col": {"t": ""}, "layer": 0, "occ": [0.6, 0.2], "shadow": false, "pick": []},
	{"name": "snow_pile_b", "kind": Kind.SNOW, "chop": "", "col": {"t": ""}, "layer": 0, "occ": [0.8, 0.2], "shadow": false, "pick": []},
	{"name": "snow_pile_c", "kind": Kind.SNOW, "chop": "", "col": {"t": ""}, "layer": 0, "occ": [0.5, 0.2], "shadow": false, "pick": []},
	{"name": "snow_drift_4", "kind": Kind.SNOW, "chop": "", "col": {"t": ""}, "layer": 0, "occ": [0.0, 0.0], "shadow": false, "pick": []},
	{"name": "branch_pile", "kind": Kind.DECO, "chop": "", "col": {"t": ""}, "layer": 0, "occ": [0.5, 0.3], "shadow": false, "pick": []},
	# M3 delivery (appended: indices above stay stable)
	{"name": "pine_f", "kind": Kind.TREE, "chop": "pine", "col": {"t": "cyl", "s": [0.29, 3.0], "c": Vector3(0, 1.5, 0)}, "layer": 65, "occ": [1.6, 0.45], "shadow": true, "pick": [1.0, 6.2]},
	{"name": "dead_tree_c", "kind": Kind.TREE, "chop": "young", "col": {"t": "cyl", "s": [0.25, 2.0], "c": Vector3(0, 1.0, 0)}, "layer": 65, "occ": [0.9, 0.4], "shadow": true, "pick": [0.74, 3.5]},
	{"name": "birch", "kind": Kind.TREE, "chop": "pine", "col": {"t": "cyl", "s": [0.24, 3.0], "c": Vector3(0, 1.5, 0)}, "layer": 65, "occ": [1.2, 0.35], "shadow": true, "pick": [1.15, 7.4]},
	{"name": "rock_f", "kind": Kind.ROCK, "chop": "", "col": {"t": "box", "s": [1.6, 0.4, 1.2], "c": Vector3(0, 0.2, 0)}, "layer": 65, "occ": [1.0, 0.45], "shadow": true, "pick": []},
	{"name": "fallen_log_c", "kind": Kind.LOG, "chop": "log", "col": {"t": "box", "s": [3.1, 0.9, 1.7], "c": Vector3(0.25, 0.45, 0)}, "layer": 65, "occ": [1.7, 0.4], "shadow": true, "pick": [1.7, 1.6]},
]

## Node kinds (not MultiMesh): interactive or unique objects instantiated as scenes by the chunk.
enum NodeKind { PICKUP, BERRY_BUSH, PROP }

## Effective table (VARIANTS + manifest proxies). Filled on the main thread by load_manifests(); read-only after.
static var V: Array = []
static var manifest_names: Array = []


## Reads the Opus manifests (collision proxies, heights, choppable) over the defaults. Idempotent.
static func load_manifests() -> void:
	if not V.is_empty():
		return
	var table: Array = VARIANTS.duplicate(true)
	for path in MANIFESTS:
		if not FileAccess.file_exists(path):
			continue
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (data is Dictionary):
			continue
		for i in table.size():
			var v: Dictionary = table[i]
			var n := str(v["name"])
			if LEGACY.has(n) or not (data as Dictionary).has(n):
				continue
			var m: Dictionary = data[n]
			var c: Array = m.get("col_center", [0, 0, 0])
			var center := Vector3(float(c[0]), float(c[1]), float(c[2]))
			var size: Array = m.get("col_size", [])
			match str(m.get("col", "none")):
				"cylinder": v["col"] = {"t": "cyl", "s": [float(size[0]), float(size[1])], "c": center}
				"sphere": v["col"] = {"t": "sphere", "s": [float(size[0])], "c": center}
				"box": v["col"] = {"t": "box", "s": [float(size[0]), float(size[1]), float(size[2])], "c": center}
				_:
					v["col"] = {"t": ""}
					v["layer"] = 0
			var height := float(m.get("height", 0.0))
			var radius := float(m.get("radius", 1.0))
			if int(m.get("choppable", 0)) == 0:
				v["chop"] = ""
				v["pick"] = []
			elif str(m.get("family", "")) == "log":
				v["pick"] = [maxf(float(size[0]) if not size.is_empty() else 1.6, 1.0) * 0.55, maxf(height, 0.5) + 0.3]
			else:
				v["pick"] = [maxf(radius * 0.55, 0.6), maxf(height, 1.0)]
			manifest_names.append(n)
	V = table


static func variant(i: int) -> Dictionary:
	if V.is_empty():
		load_manifests()
	return V[i]


static func index_of(name: String) -> int:
	for i in VARIANTS.size():
		if VARIANTS[i]["name"] == name:
			return i
	return -1


static func name_of(i: int) -> String:
	return VARIANTS[i]["name"] if i >= 0 and i < VARIANTS.size() else ""


static func is_choppable(i: int) -> bool:
	return i >= 0 and i < VARIANTS.size() and variant(i)["chop"] != ""


## [hits, wood] of a chop class (Balance values; young trees and small dead trees give half the wood, M3.3).
static func chop_stats(chop: String) -> Array:
	match chop:
		"dead": return [Balance.DEAD_TREE_HITS, Balance.DEAD_TREE_WOOD]
		"young": return [Balance.DEAD_TREE_HITS, maxi(Balance.TREE_WOOD / 2, 1)]
		"log": return [Balance.LOG_HITS, Balance.LOG_WOOD]
	return [Balance.TREE_HITS, Balance.TREE_WOOD]


## Terrain AO disc of a placed variant (G1 contact AO; {} when it bakes none).
static func occluder(i: int, pos: Vector2, s: float, id: String) -> Dictionary:
	var occ: Array = variant(i)["occ"]
	if float(occ[1]) <= 0.0:
		return {}
	return {"id": id, "pos": pos, "r": float(occ[0]) * s, "strength": float(occ[1])}


## Terrain AO disc left by the stump of a felled choppable variant (logs leave none).
static func stump_occluder(i: int, s: float) -> Array:
	if variant(i)["kind"] == Kind.LOG:
		return [0.0, 0.0]
	return [0.45 * s, 0.3]
