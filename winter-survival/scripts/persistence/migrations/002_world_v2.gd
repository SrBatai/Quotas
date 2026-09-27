extends RefCounted
## Migration 2: the v3 world (PLAN Parte II v3.8.4, M5 row; C25). The valley keeps its chunk indices in the
## 96 × 96 grid (CENTER_CHUNK 24, key = cx << 16 | cz unchanged), so rows need no remap: the store only learns
## which world layout wrote it (`world_meta.world_version`) and which city generator (`city_version`, R19: 0 = none).
## Also: loot nominal counters per region and category (C22 / GDD §9.3) and, per container, the loot table that
## rolled it and the personal bags (`personal_loot_bags` rule: one roll per player).

const VERSION := 2


func sqlite() -> PackedStringArray:
	return PackedStringArray([
		"ALTER TABLE containers ADD COLUMN table_id TEXT;",
		"ALTER TABLE containers ADD COLUMN bags_json TEXT;",
		"CREATE TABLE IF NOT EXISTS nominal(region TEXT, category TEXT, spawned INT, PRIMARY KEY(region, category));",
		"INSERT OR IGNORE INTO world_meta(key, value) VALUES ('%s', '%d');" % [PersistenceSchema.META_WORLD_VERSION, PersistenceSchema.world_version()],
		"INSERT OR IGNORE INTO world_meta(key, value) VALUES ('%s', '%d');" % [PersistenceSchema.META_CITY_VERSION, PersistenceSchema.city_version()],
	])


func document(doc: Dictionary) -> void:
	var w: Dictionary = doc.get("world", {})
	if not w.has(PersistenceSchema.META_WORLD_VERSION):
		w[PersistenceSchema.META_WORLD_VERSION] = PersistenceSchema.world_version()
	if not w.has(PersistenceSchema.META_CITY_VERSION):
		w[PersistenceSchema.META_CITY_VERSION] = PersistenceSchema.city_version()
	doc["world"] = w
	if not doc.get("nominal") is Dictionary:
		doc["nominal"] = {}
