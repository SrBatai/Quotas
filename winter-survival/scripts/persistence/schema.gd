class_name PersistenceSchema
## Schema version and migrations of the server's persistent store (ARQ v2 §15.2, M5), shared by SqliteBackend
## (production: `PRAGMA user_version`) and FileBackend (the JSON document's `schema_version`). Every migration is
## one file under scripts/persistence/migrations/NNN_<name>.gd with `VERSION`, `sqlite()` (statements run in one
## transaction, then `PRAGMA user_version = VERSION`) and `document(doc)` (the same change on the JSON document), so
## both backends walk the same numbered steps. A store newer than VERSION is refused (never downgraded).
##   1  the §15.2 tables (+ a `data_json` / `profile_json` column per table that holds the whole entry, so any field
##      the game adds later round-trips without a migration; the typed columns are for queries and admins)
##   2  v3 world (PLAN v3.8.4 M5): `world_meta.world_version` / `city_version`, loot nominal counters, container
##      loot table + personal bags. The valley keeps its chunk indices in the 96² grid (C25), so no key remap.
##   3  zone discovery (H2, C35): `discoveries(scope, zone_id, by_token, by_name, day, ts)`, scope "group" when the
##      `shared_discovery` rule is on, else the discoverer's token hash.

const VERSION := 3
const MIGRATIONS := [
	"res://scripts/persistence/migrations/001_initial.gd",
	"res://scripts/persistence/migrations/002_world_v2.gd",
	"res://scripts/persistence/migrations/003_discoveries.gd",
]
## world_meta keys every save carries (stamped by the backends).
const META_WORLD_VERSION := "world_version"
const META_CITY_VERSION := "city_version"
const META_SCHEMA := "schema_version"


## `WorldConst.WORLD_VERSION` (W1: 2 = the 6 × 6 km world, 96² chunks); 1 before W1 defined it (48² grid).
static func world_version() -> int:
	return int((WorldConst as Script).get_script_constant_map().get("WORLD_VERSION", 1))


## `WorldConst.CITY_VERSION` when the city generator exists (C1+, R19); 0 = no city generated yet.
static func city_version() -> int:
	return int((WorldConst as Script).get_script_constant_map().get("CITY_VERSION", 0))


## The migration objects from version `from` (exclusive) up to VERSION, in order.
static func migrations_after(from: int) -> Array[RefCounted]:
	var out: Array[RefCounted] = []
	for p in MIGRATIONS:
		var s: GDScript = load(p)
		if s == null:
			push_warning("PersistenceSchema: cannot load %s" % p)
			continue
		var m: RefCounted = s.new()
		if int(m.get("VERSION")) > from:
			out.append(m)
	out.sort_custom(func(a: RefCounted, b: RefCounted) -> bool: return int(a.get("VERSION")) < int(b.get("VERSION")))
	return out


## Adds the version keys every world_meta row set must carry (world_version, city_version, schema_version).
static func stamp_meta(meta: Dictionary) -> Dictionary:
	var out := meta.duplicate(true)
	out[META_WORLD_VERSION] = world_version()
	if not out.has(META_CITY_VERSION):
		out[META_CITY_VERSION] = city_version()
	out[META_SCHEMA] = VERSION
	return out
