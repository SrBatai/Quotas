class_name Loot
## Loot rolls (ARQ v2 §9.6, PLAN C22, GDD v2 §9; M5). `roll` is a PURE function of (world seed, container wid,
## table, day, salt): the same world always fills the same container with the same things (tests: determinism),
## and nothing is stored until somebody opens it (only the result is persisted, as the container's delta).
##   shared (default)        one roll per container: whoever opens it first finds everything, the others what is left.
##   personal_loot_bags rule one roll per player (salt = the player's identity hash): everybody finds their own bag.
## Nominal caps (LootTables.NOMINAL, per region and item, scaled by players) cut ammo / weapons AFTER the pure roll;
## the counters live in world_meta-side storage (backend nominal table) and never decrease (C22: ammo never respawns).
## Restock (C22 / GDD §9.3, simplified): a container untouched for LOOT_RESTOCK_DAYS game days rolls again with
## probability `loot_respawn`, 60 % of a roll, never ammo.

const GEN_LOOT := 0x4C4F4F54        # "LOOT": generator id of container wids and rolls
const GEN_RESTOCK := 0x5245534B     # "RESK"

## "region|item" -> spawned so far (server; loaded from the backend at start, saved by the autosave).
static var nominal: Dictionary = {}
static var _nominal_dirty: Dictionary = {}
## Tests / stats.
static var rolls: int = 0
static var capped: int = 0


static func reset() -> void:
	nominal.clear()
	_nominal_dirty.clear()
	rolls = 0
	capped = 0


## Deterministic contents: [{id, count[, dur][, ammo]}]. `scale` multiplies the entry count (restock 0.6).
static func roll(world_seed: int, wid: int, table_id: StringName, day: int, salt: int = 0, scale: float = 1.0, no_ammo: bool = false) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var t := LootTables.table(table_id)
	if t.is_empty():
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = WorldConst.hash64(world_seed, wid, GEN_LOOT, day, salt)
	if rng.randf() >= float(t.get("chance", Balance.LOOT_CHANCE)):
		return out
	var cnt: Array = t.get("count", [1, 3])
	var n := maxi(int(round(float(rng.randi_range(int(cnt[0]), int(cnt[1]))) * scale)), 1)
	var entries: Array = t["entries"]
	var total := 0
	for e in entries:
		total += int(e["w"])
	for k in n:
		var pick := rng.randi_range(0, maxi(total - 1, 0))
		var chosen: Dictionary = entries[0]
		for e in entries:
			pick -= int(e["w"])
			if pick < 0:
				chosen = e
				break
		var id := StringName(chosen["id"])
		var amount := rng.randi_range(int(chosen["n"][0]), int(chosen["n"][1]))
		if no_ammo and Items.is_ammo(id):
			continue
		var merged := false
		if Items.stack_max(id) > 1:
			for it in out:
				if it["id"] == id:
					it["count"] = int(it["count"]) + amount
					merged = true
					break
		if merged:
			continue
		var item := {"id": id, "count": amount}
		if Items.has_durability(id):
			item["dur"] = rng.randi_range(35, 100)   # found weapons are worn
		if Firearms.is_firearm(id) and not Firearms.is_bow(id):
			item["ammo"] = rng.randi_range(0, maxi(Firearms.mag_of(id) / 2, 0))   # a few rounds left in it, maybe
		out.append(item)
	rolls += 1
	return out


## Applies the nominal caps of `region` (players = connected players for the scale) and counts what stays.
static func apply_nominal(items: Array[Dictionary], region: String, players: int) -> Array[Dictionary]:
	var scale := 1.0 + 0.25 * float(clampi(players, 1, 4) - 1)
	var out: Array[Dictionary] = []
	for it in items:
		var id: StringName = it["id"]
		if not LootTables.NOMINAL.has(id):
			out.append(it)
			continue
		var key := "%s|%s" % [region, id]
		var cap := int(round(float(LootTables.NOMINAL[id]) * scale))
		var have := int(nominal.get(key, 0))
		var n := mini(int(it["count"]), cap - have)
		if n <= 0:
			capped += 1
			continue
		if n < int(it["count"]):
			capped += 1
		var kept: Dictionary = it.duplicate()
		kept["count"] = n
		out.append(kept)
		nominal[key] = have + n
		_nominal_dirty[key] = have + n
	return out


## Counters changed since the last call (PlayerManager.save_all writes them).
static func take_dirty_nominal() -> Dictionary:
	var d := _nominal_dirty.duplicate()
	_nominal_dirty.clear()
	return d


## Salt of a player's personal bag (the first 15 hex digits of the identity hash: a non-negative int).
static func bag_salt(token_hash: String) -> int:
	if token_hash.length() < 15:
		return token_hash.hash() & 0x7FFFFFFF
	return token_hash.substr(0, 15).hex_to_int()


## Restock decision for a container rolled on `rolled_day` and last opened on `opened_day` (pure).
static func restock_due(world_seed: int, wid: int, day: int, opened_day: int, respawn: float) -> bool:
	if respawn <= 0.0 or day - opened_day < Balance.LOOT_RESTOCK_DAYS:
		return false
	return WorldConst.unit(WorldConst.hash64(world_seed, wid, GEN_RESTOCK, day)) < respawn


## Every item of `items` as a readable line (logs / tests).
static func describe(items: Array) -> String:
	var parts: PackedStringArray = []
	for it in items:
		parts.append("%s×%d" % [it["id"], int(it["count"])])
	return ", ".join(parts) if not parts.is_empty() else "(vacío)"
