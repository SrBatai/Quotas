class_name ScatterCatalog
## Everything the scatter can place as a MultiMesh instance (ASSET_SPEC v2 §13 "MultiMesh‑friendly": one object,
## one `palette_vcol` surface, no children, no embedded collision — the code puts the shapes, below). Variant
## index = position in VARIANTS (stable: ScatterGen and the saved deltas refer to entries by wid, not by index,
## but keep the order to keep MultiMesh buffers identical between runs). Models are looked up by name in
## assets/models/{vegetation,props,poi,}/ (Assets.model_path); a missing one renders as its placeholder and the
## real .glb is picked up automatically once Opus delivers it.
##
## Fields: name (model), kind, chop ("" or the chop class: pine / dead / log / young), col ([type, a, b, y]:
## "cyl" r h y · "sphere" r y · "box" sx sy sz y), layer (collision layer bits: 1 world, 64 placement blocker),
## occ ([radius, strength] of the baked terrain AO disc, × scale), shadow, pick ([radius, height] of the
## hover cylinder for choppable entries).

enum Kind { TREE, LOG, ROCK, STUMP, BUSH, SNOW, DECO }

const VARIANTS := [
	{"name": "pine_a", "kind": Kind.TREE, "chop": "pine", "col": ["cyl", 0.35, 3.0, 1.5], "layer": 65, "occ": [1.7, 0.45], "shadow": true, "pick": [1.1, 7.0]},
	{"name": "pine_b", "kind": Kind.TREE, "chop": "pine", "col": ["cyl", 0.35, 3.0, 1.5], "layer": 65, "occ": [1.2, 0.45], "shadow": true, "pick": [1.1, 5.5]},
	{"name": "pine_c", "kind": Kind.TREE, "chop": "pine", "col": ["cyl", 0.35, 3.0, 1.5], "layer": 65, "occ": [1.0, 0.45], "shadow": true, "pick": [1.1, 4.2]},
	{"name": "pine_d", "kind": Kind.TREE, "chop": "pine", "col": ["cyl", 0.40, 3.0, 1.5], "layer": 65, "occ": [1.9, 0.45], "shadow": true, "pick": [1.2, 9.0]},
	{"name": "pine_e", "kind": Kind.TREE, "chop": "pine", "col": ["cyl", 0.38, 3.0, 1.5], "layer": 65, "occ": [1.8, 0.45], "shadow": true, "pick": [1.3, 7.0]},
	{"name": "pine_young", "kind": Kind.TREE, "chop": "young", "col": ["cyl", 0.16, 1.6, 0.8], "layer": 65, "occ": [0.8, 0.35], "shadow": true, "pick": [0.8, 2.6]},
	{"name": "dead_tree", "kind": Kind.TREE, "chop": "dead", "col": ["cyl", 0.35, 3.0, 1.5], "layer": 65, "occ": [0.7, 0.4], "shadow": true, "pick": [0.6, 4.2]},
	{"name": "dead_tree_b", "kind": Kind.TREE, "chop": "dead", "col": ["cyl", 0.32, 3.0, 1.5], "layer": 65, "occ": [0.7, 0.4], "shadow": true, "pick": [0.6, 4.6]},
	{"name": "fallen_log", "kind": Kind.LOG, "chop": "log", "col": ["box", 1.6, 0.4, 0.4, 0.2], "layer": 65, "occ": [1.1, 0.4], "shadow": true, "pick": [0.95, 0.8]},
	{"name": "fallen_log_b", "kind": Kind.LOG, "chop": "log", "col": ["box", 1.9, 0.45, 0.45, 0.22], "layer": 65, "occ": [1.2, 0.4], "shadow": true, "pick": [1.05, 0.8]},
	{"name": "stump", "kind": Kind.STUMP, "chop": "", "col": ["cyl", 0.3, 0.5, 0.25], "layer": 1, "occ": [0.45, 0.3], "shadow": true, "pick": []},
	{"name": "rock_a", "kind": Kind.ROCK, "chop": "", "col": ["sphere", 0.55, 0.4], "layer": 65, "occ": [0.8, 0.5], "shadow": true, "pick": []},
	{"name": "rock_b", "kind": Kind.ROCK, "chop": "", "col": ["sphere", 0.9, 0.6], "layer": 65, "occ": [1.3, 0.5], "shadow": true, "pick": []},
	{"name": "rock_c", "kind": Kind.ROCK, "chop": "", "col": ["sphere", 0.3, 0.2], "layer": 65, "occ": [0.5, 0.5], "shadow": true, "pick": []},
	{"name": "rock_d", "kind": Kind.ROCK, "chop": "", "col": ["box", 1.8, 0.45, 1.3, 0.2], "layer": 65, "occ": [1.3, 0.45], "shadow": true, "pick": []},
	{"name": "rock_e", "kind": Kind.ROCK, "chop": "", "col": ["sphere", 1.5, 0.9], "layer": 65, "occ": [2.1, 0.5], "shadow": true, "pick": []},
	{"name": "bush_a", "kind": Kind.BUSH, "chop": "", "col": ["sphere", 0.5, 0.4], "layer": 64, "occ": [0.7, 0.35], "shadow": true, "pick": []},
	{"name": "bush_b", "kind": Kind.BUSH, "chop": "", "col": ["sphere", 0.6, 0.45], "layer": 64, "occ": [0.8, 0.35], "shadow": true, "pick": []},
	{"name": "snow_pile_a", "kind": Kind.SNOW, "chop": "", "col": [], "layer": 0, "occ": [0.6, 0.2], "shadow": false, "pick": []},
	{"name": "snow_pile_b", "kind": Kind.SNOW, "chop": "", "col": [], "layer": 0, "occ": [0.8, 0.2], "shadow": false, "pick": []},
	{"name": "snow_pile_c", "kind": Kind.SNOW, "chop": "", "col": [], "layer": 0, "occ": [0.5, 0.2], "shadow": false, "pick": []},
	{"name": "snow_drift_4", "kind": Kind.SNOW, "chop": "", "col": [], "layer": 0, "occ": [0.0, 0.0], "shadow": false, "pick": []},
	{"name": "branch_pile", "kind": Kind.DECO, "chop": "", "col": [], "layer": 0, "occ": [0.5, 0.3], "shadow": false, "pick": []},
]

## Node kinds (not MultiMesh): interactive or unique objects instantiated as scenes by the chunk.
enum NodeKind { PICKUP, BERRY_BUSH, PROP }


static func index_of(variant: String) -> int:
	for i in VARIANTS.size():
		if VARIANTS[i]["name"] == variant:
			return i
	return -1


static func name_of(i: int) -> String:
	return VARIANTS[i]["name"] if i >= 0 and i < VARIANTS.size() else ""


static func is_choppable(i: int) -> bool:
	return i >= 0 and i < VARIANTS.size() and VARIANTS[i]["chop"] != ""


## [hits, wood] of a chop class (Balance values).
static func chop_stats(chop: String) -> Array:
	match chop:
		"dead", "young": return [Balance.DEAD_TREE_HITS, Balance.DEAD_TREE_WOOD]
		"log": return [Balance.LOG_HITS, Balance.LOG_WOOD]
	return [Balance.TREE_HITS, Balance.TREE_WOOD]


## Terrain AO disc of a placed variant (G1 contact AO; {} when it bakes none).
static func occluder(i: int, pos: Vector2, s: float, id: String) -> Dictionary:
	var occ: Array = VARIANTS[i]["occ"]
	if float(occ[1]) <= 0.0:
		return {}
	return {"id": id, "pos": pos, "r": float(occ[0]) * s, "strength": float(occ[1])}


## Terrain AO disc left by the stump of a felled choppable variant (logs leave none).
static func stump_occluder(i: int, s: float) -> Array:
	if VARIANTS[i]["kind"] == Kind.LOG:
		return [0.0, 0.0]
	return [0.45 * s, 0.3]
