extends RefCounted
## Body of tests/unit/m5_units_test.gd (M5 pure functions: loot + firearms).

class FakeBody:
	extends Node3D
	var peer_id: int = 7


var tree: SceneTree
var _checks := 0
var _failed := false


func check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("  ok   ", msg)
	else:
		_failed = true
		print("FAIL: ", msg)


func run(p_tree: SceneTree) -> void:
	tree = p_tree
	await tree.process_frame
	print("== VENTISCA M5 unit test (loot + firearms)")
	_loot()
	_firearms()
	_history()
	_items()
	print("== %d checks, %s" % [_checks, "FAILED" if _failed else "ALL PASSED"])
	tree.quit(1 if _failed else 0)


# ------------------------------------------------------------------ loot (C22, GDD §9)
func _loot() -> void:
	var seed_v := 1337
	var a := Loot.roll(seed_v, 123456789, &"campsite", 3)
	var b := Loot.roll(seed_v, 123456789, &"campsite", 3)
	check(str(a) == str(b), "loot: same seed + wid + day -> same contents (%s)" % Loot.describe(a))
	# across many containers: identical twice, and the seed / wid / day each change the results
	var same := true
	var diff_seed := 0
	var diff_wid := 0
	var diff_day := 0
	var empty := 0
	var n := 400
	var ids := {}
	for i in n:
		var wid := WorldConst.hash64(seed_v, Loot.GEN_LOOT, 900 + i, 1)
		var r1 := Loot.roll(seed_v, wid, &"campsite", 2)
		var r2 := Loot.roll(seed_v, wid, &"campsite", 2)
		same = same and str(r1) == str(r2)
		if str(Loot.roll(seed_v + 1, wid, &"campsite", 2)) != str(r1):
			diff_seed += 1
		if str(Loot.roll(seed_v, wid + 1, &"campsite", 2)) != str(r1):
			diff_wid += 1
		if str(Loot.roll(seed_v, wid, &"campsite", 5)) != str(r1):
			diff_day += 1
		if r1.is_empty():
			empty += 1
		for it in r1:
			ids[it["id"]] = true
			if not Items.exists(it["id"]) or int(it["count"]) < 1:
				same = false
	check(same, "loot: %d containers rolled twice give identical contents; every id exists, counts ≥ 1" % n)
	check(diff_seed > n / 2 and diff_wid > n / 2 and diff_day > n / 2, "loot: another seed / wid / day changes most rolls (%d / %d / %d of %d)" % [diff_seed, diff_wid, diff_day, n])
	var empty_pct := 100.0 * float(empty) / float(n)
	check(empty_pct > 25.0 and empty_pct < 45.0, "loot: 'campsite' is empty %.0f %% of the time (chance 65 %%, GDD §9.2)" % empty_pct)
	check(ids.size() >= 8, "loot: the table's variety shows up (%d distinct items)" % ids.size())
	# every table of the tables file rolls valid items (weapons carry durability, guns a few rounds)
	var ok_tables := true
	for t in LootTables.TABLES:
		for i in 60:
			for it in Loot.roll(seed_v, 77 + i, StringName(t), 1):
				if not Items.exists(it["id"]):
					ok_tables = false
				if Items.has_durability(it["id"]) and not it.has("dur"):
					ok_tables = false
				if Firearms.is_firearm(it["id"]) and not Firearms.is_bow(it["id"]) and (not it.has("ammo") or int(it["ammo"]) > Firearms.mag_of(it["id"])):
					ok_tables = false
	check(ok_tables, "loot: all %d tables roll known items (weapons with durability, guns with 0..mag/2 rounds)" % LootTables.TABLES.size())
	check(Loot.roll(seed_v, 1, &"no_such_table", 1).is_empty(), "loot: unknown table -> nothing")
	# nominal caps (per region and item, scaled by players; counters only grow)
	Loot.reset()
	var ammo_in := 0
	var kept := 0
	for i in 120:
		var items: Array[Dictionary] = [{"id": &"municion_308", "count": 3}]
		ammo_in += 3
		for it in Loot.apply_nominal(items, "TEST", 1):
			kept += int(it["count"])
	check(kept == int(LootTables.NOMINAL[&"municion_308"]) and Loot.capped > 0, "nominal: .308 capped at %d in a region for 1 player (%d offered, %d kept)" % [LootTables.NOMINAL[&"municion_308"], ammo_in, kept])
	var four: Array[Dictionary] = [{"id": &"municion_308", "count": 100}]
	var kept4 := 0
	for it in Loot.apply_nominal(four, "OTRA", 4):
		kept4 += int(it["count"])
	check(kept4 == int(round(float(LootTables.NOMINAL[&"municion_308"]) * 1.75)), "nominal: ×1.75 with 4 players (%d)" % kept4)
	var free: Array[Dictionary] = [{"id": &"lata_sopa", "count": 50}]
	check(int(Loot.apply_nominal(free, "TEST", 1)[0]["count"]) == 50, "nominal: food is not capped")
	var dirty := Loot.take_dirty_nominal()
	check(dirty.has("TEST|municion_308") and Loot.take_dirty_nominal().is_empty(), "nominal: dirty counters handed to the autosave once")
	# personal bags: another salt = another bag, same salt = same bag
	var s1 := Loot.bag_salt("a1b2c3d4e5f60718293a4b5c6d7e8f90")
	var s2 := Loot.bag_salt("ffffeeee000011112222333344445555")
	var diff_bags := 0
	for i in 50:
		if str(Loot.roll(seed_v, 5000 + i, &"lookout", 1, s1)) != str(Loot.roll(seed_v, 5000 + i, &"lookout", 1, s2)):
			diff_bags += 1
	check(s1 > 0 and s2 > 0 and diff_bags > 25 and str(Loot.roll(seed_v, 5000, &"lookout", 1, s1)) == str(Loot.roll(seed_v, 5000, &"lookout", 1, s1)),
		"personal bags: each identity rolls its own deterministic bag (%d / 50 differ)" % diff_bags)
	# restock: never before 3 days, never with loot_respawn 0, deterministic after
	check(not Loot.restock_due(seed_v, 42, 3, 2, 1.0) and not Loot.restock_due(seed_v, 42, 30, 2, 0.0), "restock: not before %d days, never with loot_respawn 0" % Balance.LOOT_RESTOCK_DAYS)
	var due := 0
	for i in 200:
		if Loot.restock_due(seed_v, 1000 + i, 10, 2, 0.6):
			due += 1
	check(due > 90 and due < 150 and Loot.restock_due(seed_v, 1003, 10, 2, 0.6) == Loot.restock_due(seed_v, 1003, 10, 2, 0.6),
		"restock: ~60 %% of the untouched containers restock (%d / 200), deterministically" % due)
	var no_ammo := true
	for i in 100:
		for it in Loot.roll(seed_v, 7000 + i, &"lookout", 9, 1, Balance.LOOT_RESTOCK_FRACTION, true):
			if Items.is_ammo(it["id"]):
				no_ammo = false
	check(no_ammo, "restock rolls never contain ammunition (GDD §7.2)")
	Loot.reset()


# ------------------------------------------------------------------ firearms (GDD §7.4–§7.6)
func _firearms() -> void:
	var rows := {&"pistola": [25.0, 15, 80.0, 1.5, 2.0], &"revolver": [45.0, 6, 90.0, 1.2, 4.0], &"escopeta": [8.0, 6, 150.0, 1.5, 9.0],
		&"rifle": [90.0, 5, 120.0, 0.5, 6.0], &"arco": [40.0, 1, 5.0, 1.0, 1.0]}
	var ok := true
	for id in rows:
		var f := Firearms.of(id)
		var r: Array = rows[id]
		if not is_equal_approx(float(f["dmg"]), r[0]) or int(f["mag"]) != int(r[1]) or not is_equal_approx(float(f["noise"]), r[2]) \
				or not is_equal_approx(float(f["spread_min"]), r[3]) or not is_equal_approx(float(f["recoil"]), r[4]) or not Items.exists(id) \
				or not Items.exists(StringName(f["ammo"])):
			ok = false
			print("  row mismatch ", id)
	check(ok, "firearms: damage / magazine / noise / minimum spread / recoil match GDD §7.4–§7.6; items and ammo exist")
	check(int(Firearms.of(&"escopeta")["pellets"]) == 12 and is_equal_approx(float(Firearms.of(&"escopeta")["cone"]), 10.0)
		and int(Firearms.of(&"revolver")["pierce"]) == 2 and int(Firearms.of(&"rifle")["pierce"]) == 2, "shotgun 8 × 12 pellets in a 10° cone; revolver / rifle pierce 2")
	# spread: standing still closes to the minimum in ≤ 0.8 s; walking / running open it; cold ×1.5
	var s := 12.0
	var t := 0.0
	while s > Firearms.target_spread(&"pistola", 0.0, false, false, 80.0) + 0.001 and t < 3.0:
		s = Firearms.step_spread(s, Firearms.target_spread(&"pistola", 0.0, false, false, 80.0), 1.0 / 60.0)
		t += 1.0 / 60.0
	check(t <= Balance.GUN_SPREAD_CLOSE_TIME + 0.02, "spread closes from 12° (a run + recoil) to the minimum in %.2f s standing still (GDD: 0.8 s)" % t)
	check(is_equal_approx(Firearms.target_spread(&"pistola", 2.2, false, false, 80.0), 4.5) and is_equal_approx(Firearms.target_spread(&"pistola", 6.0, true, false, 80.0), 9.5)
		and is_equal_approx(Firearms.target_spread(&"pistola", 0.0, false, true, 80.0), 0.75) and is_equal_approx(Firearms.target_spread(&"pistola", 0.0, false, false, 10.0), 2.25),
		"spread targets: walk +3°, run +8°, crouched −1° (floor ½ min), Calor < 15 ×1.5")
	var open := 1.5
	for k in 12:
		open = Firearms.step_spread(open, 9.5, 1.0 / 60.0)
	check(open > 6.0, "starting to run opens the reticle fast (%.1f° after 0.2 s)" % open)
	check(Firearms.band(2.0) == Firearms.Band.GREEN and Firearms.band(5.0) == Firearms.Band.AMBER and Firearms.band(9.0) == Firearms.Band.RED,
		"bands: green < 4° ≤ amber ≤ 8° < red")
	check(is_equal_approx(Firearms.falloff(&"pistola", 10.0), 1.0) and Firearms.falloff(&"pistola", 30.0) < 1.0 and Firearms.falloff(&"pistola", 30.0) > 0.5
		and Firearms.falloff(&"pistola", 41.0) == 0.0, "falloff: full to the effective range, 50 %% at max range, nothing beyond")
	var y1 := Firearms.shot_yaws(&"escopeta", 0.3, 2.0, 99)
	var y2 := Firearms.shot_yaws(&"escopeta", 0.3, 2.0, 99)
	var y3 := Firearms.shot_yaws(&"escopeta", 0.3, 2.0, 100)
	var within := true
	for y in y1:
		if absf(angle_difference(0.3, y)) > deg_to_rad(10.0 + 6.0):
			within = false
	check(y1 == y2 and y1 != y3 and y1.size() == 12 and within, "pellet yaws: seeded (same seed = same pellets), 12 of them inside the 10° cone")
	var devs := 0.0
	for k in 400:
		devs += absf(angle_difference(0.0, Firearms.shot_yaws(&"rifle", 0.0, 0.5, k)[0]))
	check(rad_to_deg(devs / 400.0) < 0.5, "rifle at 0.5° spread: mean deviation %.2f°" % rad_to_deg(devs / 400.0))
	# reload / unjam times come from the delivered clips' events (art T2, data/anim_events.json)
	var pistol_t := Firearms.reload_time(&"pistola")
	var shell_t := Firearms.reload_time(&"escopeta")
	check((AnimEvents.has("Pistol_Reload", "mag_in") and is_equal_approx(pistol_t, AnimEvents.at("Pistol_Reload", "mag_in", 0.0))) or is_equal_approx(pistol_t, 1.6),
		"pistol reload counts at Pistol_Reload mag_in (%.2f s)" % pistol_t)
	check(shell_t > 0.2 and shell_t <= 0.7 and Firearms.unjam_time() > 0.5, "shotgun loads a shell every %.2f s; unjam %.2f s" % [shell_t, Firearms.unjam_time()])
	# the hitscan segment test (2D circles)
	var o := Vector2.ZERO
	var dir := Vector2(0, 1)
	check(absf(Hitscan._t_on_segment(o, dir, Vector2(0.2, 10.0), 20.0, 0.4) - (10.0 - sqrt(0.16 - 0.04))) < 0.001, "hitscan: circle 0.2 m off the line at 10 m is hit at its near edge")
	check(Hitscan._t_on_segment(o, dir, Vector2(0.5, 10.0), 20.0, 0.4) < 0.0 and Hitscan._t_on_segment(o, dir, Vector2(0.0, 25.0), 20.0, 0.4) < 0.0
		and Hitscan._t_on_segment(o, dir, Vector2(0.0, -3.0), 20.0, 0.4) < 0.0, "hitscan: misses beside, beyond the wall and behind the muzzle")


# ------------------------------------------------------------------ lag compensation history
func _history() -> void:
	HitHistory.clear()
	var p := FakeBody.new()
	tree.root.add_child(p)
	var t0 := 100.0
	for k in 40:
		p.global_position = Vector3(float(k) * 0.2, 0, 0)   # 6 m/s along +X, sampled at 30 Hz
		HitHistory.record([p], t0 + float(k) / 30.0)
	var now := t0 + 39.0 / 30.0
	var back := HitHistory.pos_ago(p, 0.2, now)
	check(absf(back.x - (39.0 - 6.0) * 0.2) < 0.05, "hit history: 200 ms ago the runner was %.2f m back (expected 1.20)" % (p.global_position.x - back.x))
	check(HitHistory.size() == 30 and HitHistory.pos_ago(p, 0.0, now) == p.global_position, "hit history: 30 samples (1 s); no rewind = live position")
	var very_old := HitHistory.pos_ago(p, 5.0, now)
	check(very_old.x >= (39.0 - 29.0) * 0.2 - 0.01, "hit history: a rewind beyond 1 s clamps to the oldest sample (x %.2f)" % very_old.x)
	p.queue_free()
	HitHistory.clear()


# ------------------------------------------------------------------ items / weight
func _items() -> void:
	var missing := []
	for id in Items.DB:
		if not (Items.DB[id] as Dictionary).has("w"):
			missing.append(id)
	check(missing.is_empty(), "every item has a weight (GDD §9.4) %s" % str(missing))
	check(Items.is_firearm(&"pistola") and Items.is_ammo(&"cartuchos") and Items.is_medicine(&"vendas") and Items.is_clothing(&"abrigo") and Items.is_throwable(&"bengala")
		and Items.category(&"rifle") == "weapon", "item kinds: firearm, ammo, medicine, clothing, throwable; categories for the loot caps")
	check(Items.has_durability(&"escopeta") and Items.describe(&"pistola").contains("munición 9 mm"), "firearms carry durability; describe(): %s" % Items.describe(&"pistola"))
