extends RefCounted
## Body of tests/unit/zone_tracker_test.gd (H2 zones). Headless, no game scene: a bare ZoneTracker fed positions (a
## scripted mover), Locations over a HeightFunction of seed 1337 (road zones), the persistence backends on temp files.

const SEED := 1337
const DIR := "user://h2_zone_test"
## W1's 20 test points (tests/w1_world_steps.gd BANNER_POINTS) and the title the tracker must confirm there.
const TITLE_POINTS := [
	[0, 0, "Claro del cazador"],
	[192, -512, "Valdenieve"],
	[-768, 384, "Lago de las Ánimas"],
	[640, -1152, "Control militar km 12"],
	[-1408, 0, "Las Cumbres"],
	[1024, -384, "Carretera del Puerto"],
	[1536, -384, "Control del Puerto"],
	[1472, 0, "Sierra del Cierzo"],
	[2176, -512, "Catedral de Altavega"],
	[2688, -640, "Las Torres"],
	[2432, 1600, "Río Albo"],
	[2432, 1216, "Puerto fluvial del Albo"],
	[3200, -768, "Hospital Provincial"],
	[4096, 1280, "El Gran Atasco"],
	[4096, 3968, "Autovía A‐14"],
	[3264, 3520, "Base aérea de La Vega"],
	[-640, 2176, "Estación de esquí Peña Blanca"],
	[640, 2304, "Desfiladero de Peña Roya"],
	[-1024, 3072, "Ibón helado"],
	[1024, 3712, "La Vega"],
]
## Valley places used by the behaviour checks.
const FOREST := Vector3(-400, 0, -300)
const MOLINO := Vector3(-128, 0, -896)        # Granja del Molino, r 100
const HERRERIA := Vector3(-704, 0, -768)      # La Herrería, r 170
const VALDENIEVE := Vector3(176, 0, -512)     # rect 560 × 420
const MILITAR := Vector3(640, 0, -1152)       # Control militar km 12, danger 3

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
	print("== VENTISCA H2 zone test (LocationInfo, ZoneTracker, sign, discovery store, names)")
	var t0 := Time.get_ticks_msec()
	Locations.reset()
	var macro := MacroMap.load_default()
	Locations.hf_override = HeightFunction.create(SEED, macro)
	print("  (height function ready in %d ms)" % (Time.get_ticks_msec() - t0))
	_data()
	_hysteresis()
	_hierarchy()
	_cooldowns()
	_combat_p0()
	_exit_lines()
	_fast_mover()
	await _camera()
	_w1_points()
	_title_and_sign()
	_store()
	_sound()
	_names()
	Locations.reset()
	print("== %d checks, %s (%d ms)" % [_checks, "FAILED" if _failed else "ALL PASSED", Time.get_ticks_msec() - t0])
	tree.quit(1 if _failed else 0)


# ------------------------------------------------------------------ helpers
func _tracker() -> ZoneTracker:
	var zt := ZoneTracker.new()
	zt.enabled = false
	tree.root.add_child(zt)
	return zt


## Stands at `pos` for `secs` (0.25 s steps, the tracker's clock advances too).
func walk(zt: ZoneTracker, pos: Vector3, secs: float) -> void:
	var t := 0.0
	while t < secs - 0.001:
		zt.clock += 0.25
		zt.step(pos, 0.25)
		t += 0.25


## Moves in a straight line at `speed` m/s (a scripted mover), 0.25 s steps.
func move(zt: ZoneTracker, from: Vector3, to: Vector3, speed: float) -> void:
	var n := maxi(int(ceil(from.distance_to(to) / (speed * 0.25))), 1)
	for i in n + 1:
		zt.clock += 0.25
		zt.step(from.lerp(to, float(i) / float(n)), 0.25)


func _cards(log: Array, kind: String = "") -> Array:
	return log.filter(func(i: Dictionary) -> bool: return str(i["card"]) != "none" and (kind == "" or str(i["card"]) == kind))


# ------------------------------------------------------------------ LocationInfo
func _data() -> void:
	var all := Locations.all()
	var bad: Array[String] = []
	for e: Dictionary in all:
		bad.append_array(LocationInfo.validate(e))
	bad.append_array(LocationInfo.validate(Locations.DEFAULT))
	check(bad.is_empty(), "every zone is a valid LocationInfo (kind, parent, shape, danger, temperature, electricity) — %d zones %s" % [all.size(), bad])
	var w1 := 0
	var reserved := 0
	var missing: Array[String] = []
	for r: Dictionary in PoiRegistry.REGIONS:
		var e := Locations.by_id(str(r.get("id", ""))) if r.has("id") else {}
		if not r.has("id"):
			for x: Dictionary in all:
				if str(x.get("banner", "")) == str(r["name"]):
					e = x
		if e.is_empty():
			missing.append(str(r["name"]))
			continue
		if r.has("id"):
			w1 += 1
			if bool(r.get("reserved", false)):
				reserved += 1
				if not bool(e.get("reserved", false)):
					missing.append("%s not reserved" % r["id"])
			if str(e["parent"]) != str(r.get("parent", "")) or int(e["danger"]) != int(r["danger"]) or str(e["power"]) != str(r["power"]):
				missing.append("%s fields" % r["id"])
	check(missing.is_empty() and w1 == 43 and reserved >= 35, "PoiRegistry.REGIONS migrated: 16 valley places + %d W1 regions (%d reserved) %s" % [w1, reserved, missing])
	var roads_ok := true
	for rn: String in PoiRegistry.ROAD_REGIONS:
		var e := Locations.by_id(str(PoiRegistry.ROAD_REGIONS[rn]["id"]))
		roads_ok = roads_ok and not e.is_empty() and str(e["kind"]) == "road" and str((e["shape"] as Dictionary).get("fn", "")) == "road:" + rn
	check(roads_ok, "the %d named roads are zones (their own splines + 32 m)" % PoiRegistry.ROAD_REGIONS.size())
	var parents_ok := true
	for e: Dictionary in all:
		if str(e["parent"]) != "" and Locations.by_id(str(e["parent"])).is_empty():
			parents_ok = false
	var un := Locations.by_id("urbanizaciones_del_norte")
	check(parents_ok and Locations.by_id("urbanizaciones_del_norte_este") == un and (un["shape"] as Dictionary).has("multi")
		and Locations.depth(un, 2048, -1216) > 0.0 and Locations.depth(un, 3136, -1216) > 0.0,
		"parents resolve; «Urbanizaciones del norte» is one zone in two parts (alias of the east rect)")
	var torres := Locations.by_id("altavega_las_torres")
	var cat := Locations.by_id("catedral")
	check(Locations.chain_ids(cat) == ["altavega_casco_viejo", "altavega"] and torres.get("camera") == &"torres" and Locations.by_id("gran_via").get("camera") == &"city"
		and Locations.by_id("valdenieve").get("camera", &"") == &"", "hierarchy chain Catedral ⊂ Casco viejo ⊂ Altavega; urban camera profile in Altavega only (C1: Las Torres' own)")
	check(LocationInfo.de(Locations.by_id("control_militar_km_12")) == "del Control militar km 12" and LocationInfo.de(cat) == "de la Catedral de Altavega"
		and LocationInfo.de(torres) == "de Las Torres" and LocationInfo.de(Locations.by_id("valdenieve")) == "de Valdenieve",
		"Spanish articles for the exit line (del / de la / de Las Torres / de Valdenieve)")
	# every zone name (title, sign, feed) is drawable with the HUD fonts (Barlow has no U+2011 / U+2192)
	var missing_glyphs: Array[String] = []
	var fonts := [UiStyle.font_file(&"cond_extralight"), UiStyle.font_file(&"light"), UiStyle.font_file(&"medium")]
	for e: Dictionary in all + [Locations.DEFAULT]:
		var txt := str(e["name"]) + str(e["name"]).to_upper() + str((e.get("road", {}) as Dictionary).get("plate", ""))
		for i in txt.length():
			for f: Font in fonts:
				if not f.has_char(txt.unicode_at(i)) and not missing_glyphs.has(txt[i]):
					missing_glyphs.append(txt[i])
	check(missing_glyphs.is_empty(), "every zone name and road plate is drawable with Barlow / Barlow Condensed (missing %s)" % [missing_glyphs])
	var poly := LocationInfo.make("t_poly", "Prueba", "poi", {"poly": PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(100, 60), Vector2(0, 60)])})
	check(is_equal_approx(Locations.depth(poly, 50, 30), 30.0) and is_equal_approx(Locations.depth(poly, 50, -10), -10.0) and Locations.center(poly) == Vector2(50, 30),
		"polygon shapes: signed depth and centre")


# ------------------------------------------------------------------ hysteresis
func _hysteresis() -> void:
	var zt := _tracker()
	walk(zt, VALDENIEVE, 2.0)
	var e0 := zt.entries
	var ok0 := str(zt.current.get("id", "")) == "valdenieve"
	# a zigzag over Valdenieve's east border (x 456): ± 8 m every step for 30 s
	for i in 120:
		zt.clock += 0.25
		zt.step(Vector3(448.0 if i % 2 == 0 else 464.0, 0, -512), 0.25)
	# and a slow zigzag: 20 m outside for 1.25 s, back inside for 1.25 s (never 1.5 s out)
	for k in 8:
		walk(zt, Vector3(476, 0, -512), 1.25)
		walk(zt, Vector3(430, 0, -512), 1.25)
	check(ok0 and zt.entries == e0, "zigzag over a border (fast ± 8 m for 30 s, slow 20 m out for 1.25 s): %d changes" % (zt.entries - e0))
	# ≥ 12 m inside for 1.5 s: exactly one change; 11 m inside (or 13 m for 1.25 s) is not enough
	zt.forget_all()
	walk(zt, FOREST, 2.0)
	var e1 := zt.entries
	walk(zt, MOLINO + Vector3(0, 0, 100.0 - 11.0), 10.0)   # 11 m inside the 100 m circle
	var n11 := zt.entries - e1
	walk(zt, MOLINO + Vector3(0, 0, 100.0 - 13.0), 1.25)
	walk(zt, FOREST, 1.0)
	var n125 := zt.entries - e1
	walk(zt, MOLINO + Vector3(0, 0, 100.0 - 13.0), 1.75)
	check(n11 == 0 and n125 == 0 and zt.entries == e1 + 1 and str(zt.current["id"]) == "granja_del_molino",
		"≥ 12 m inside for 1.5 s = 1 change (11 m inside for 10 s: %d, 13 m for 1.25 s: %d)" % [n11, n125])
	zt.queue_free()


# ------------------------------------------------------------------ hierarchy
func _hierarchy() -> void:
	var zt := _tracker()
	var log: Array = []
	zt.entered.connect(func(i: Dictionary) -> void: log.append(i))
	walk(zt, Vector3(1850, 0, 1000), 2.0)   # Altavega, outside every district
	var city := str(zt.current.get("id", ""))
	zt.clock += 30.0
	move(zt, Vector3(1850, 0, 1000), Vector3(2048, 0, 300), 5.0)   # into the Barriada de San Lázaro
	walk(zt, Vector3(2048, 0, 300), 2.0)
	var d: Dictionary = log[-1] if not log.is_empty() else {}
	var facts: Array = d.get("facts", [])
	check(city == "altavega" and str(zt.current.get("id", "")) == "barriada_de_san_lazaro" and not facts.is_empty() and str(facts[0]) == "Altavega",
		"district over city: Altavega → «%s» with «%s» first" % [d.get("name", "-"), facts[0] if not facts.is_empty() else "-"])
	walk(zt, Vector3(2176, 0, -512), 2.0)
	var cat := str(zt.current.get("id", ""))
	walk(zt, Vector3(2688, 0, -640), 2.0)
	check(cat == "catedral" and str(zt.current.get("id", "")) == "altavega_las_torres" and str(zt.current.get("name", "")) == "Las Torres",
		"POI over district over city (Catedral ⊂ Casco viejo ⊂ Altavega), Las Torres over Ensanche")
	# the lake inside the clearing (Lago helado ⊂ Claro del cazador): the deeper place wins (H1 lost it to the clearing)
	walk(zt, Vector3(0, 0, 60), 2.0)
	walk(zt, Vector3(-42, 0, 30), 2.0)
	check(str(zt.current.get("id", "")) == "lago_helado", "Lago helado ⊂ Claro del cazador: the small zone wins (%s)" % zt.current.get("id", "-"))
	zt.queue_free()


# ------------------------------------------------------------------ cooldowns
func _cooldowns() -> void:
	var zt := _tracker()
	var cards: Array = []
	zt.card_shown.connect(func(i: Dictionary) -> void: cards.append(i))
	var log: Array = []
	zt.entered.connect(func(i: Dictionary) -> void: log.append(i))
	walk(zt, FOREST, 2.0)
	zt.clock += 30.0
	walk(zt, MOLINO, 2.0)
	var first: Dictionary = cards[-1] if not cards.is_empty() else {}
	walk(zt, FOREST, 2.0)
	walk(zt, MOLINO, 2.0)   # back within 90 s
	var re: Dictionary = log[-1] if not log.is_empty() else {}
	check(str(first.get("id", "")) == "granja_del_molino" and str(first.get("card", "")) == "full" and bool(first.get("first_visit", false))
		and str(re.get("id", "")) == "granja_del_molino" and str(re.get("card", "")) == "none",
		"first visit → full title; the re-entry within 90 s shows nothing (cooldown per zone)")
	walk(zt, FOREST, 2.0)
	zt.clock += 90.0
	walk(zt, MOLINO, 2.0)
	var re2: Dictionary = cards[-1] if not cards.is_empty() else {}
	check(str(re2.get("id", "")) == "granja_del_molino" and str(re2.get("card", "")) == "compact" and not bool(re2.get("first_visit", true)),
		"after 90 s the re-entry shows the compact title (name at 60 %, 2.5 s)")
	# 20 s between cards and a queue of 1: La Herrería then Valdenieve inside the gap → only Valdenieve is shown
	var n0 := cards.size()
	var t_molino := zt.last_card_t
	walk(zt, HERRERIA, 2.0)
	var herreria_waits := cards.size() == n0 and str(zt.queued.get("id", "")) == "la_herreria"
	walk(zt, VALDENIEVE, 2.0)
	var replaced := str(zt.queued.get("id", "")) == "valdenieve"
	walk(zt, VALDENIEVE, 20.0)
	var shown: Array = cards.slice(n0).map(func(i: Dictionary) -> String: return str(i["id"]))
	var gap := zt.last_card_t - t_molino
	check(herreria_waits and replaced and shown == ["valdenieve"] and gap >= UiTokens.ZONE_GAP and gap < UiTokens.ZONE_GAP + 0.3,
		"20 s between cards (next one after %.2f s); a queue of 1 (La Herrería waiting → replaced by Valdenieve; shown %s)" % [gap, shown])
	zt.queue_free()


# ------------------------------------------------------------------ combat and P0
func _combat_p0() -> void:
	var zt := _tracker()
	var cards: Array = []
	var zevents: Array = []
	zt.card_shown.connect(func(i: Dictionary) -> void: cards.append(i))
	zt.zone_changed.connect(func(i: Dictionary) -> void: zevents.append(str(i["id"])))
	var fighting := [false]
	var p0 := [false]
	zt.in_combat = func() -> bool: return fighting[0]
	zt.p0_active = func() -> bool: return p0[0]
	walk(zt, FOREST, 2.0)
	zt.clock += 30.0
	fighting[0] = true
	walk(zt, MOLINO, 4.0)
	var held := cards.filter(func(i: Dictionary) -> bool: return str(i["id"]) == "granja_del_molino").is_empty() and not zevents.has("granja_del_molino") \
		and str(zt.queued.get("id", "")) == "granja_del_molino" and str(zt.current.get("id", "")) == "granja_del_molino"
	fighting[0] = false
	walk(zt, MOLINO, 0.5)
	var after: Dictionary = cards[-1] if not cards.is_empty() else {}
	check(held and str(after.get("id", "")) == "granja_del_molino" and str(after.get("card", "")) == "full" and zevents.has("granja_del_molino"),
		"combat defers the title and zone_entered; both come once the fight is over")
	# in combat and the player leaves before it ends: the card is dropped
	zt.clock += 30.0
	fighting[0] = true
	walk(zt, HERRERIA, 2.0)
	walk(zt, FOREST, 2.0)
	fighting[0] = false
	walk(zt, FOREST, 1.0)
	var herreria := cards.filter(func(i: Dictionary) -> bool: return str(i["id"]) == "la_herreria")
	check(herreria.is_empty() and not zevents.has("la_herreria"), "a title deferred by combat is dropped when the player left meanwhile")
	# a P0 (downed, freezing, a P0 notice): the full title turns compact and waits
	zt.clock += 30.0
	p0[0] = true
	walk(zt, VALDENIEVE, 3.0)
	var waits := cards.filter(func(i: Dictionary) -> bool: return str(i["id"]) == "valdenieve").is_empty() and str(zt.queued.get("card", "")) == "compact"
	p0[0] = false
	walk(zt, VALDENIEVE, 0.5)
	var v: Dictionary = cards[-1] if not cards.is_empty() else {}
	check(waits and str(v.get("id", "")) == "valdenieve" and str(v.get("card", "")) == "compact", "a P0 turns the first-visit title compact and delays it")
	zt.queue_free()


# ------------------------------------------------------------------ leaving
func _exit_lines() -> void:
	var zt := _tracker()
	var lines: Array = []
	zt.exit_line.connect(func(t: String) -> void: lines.append(t))
	walk(zt, FOREST, 2.0)
	walk(zt, MOLINO, 2.0)
	walk(zt, FOREST, 2.0)   # a farm (peligro bajo) → the forest: no line
	var none_after_farm := lines.is_empty()
	walk(zt, MILITAR, 2.0)
	walk(zt, Vector3(640, 0, -960), 2.0)   # out of the checkpoint (peligro extremo) onto the N‐140 (peligro bajo)
	check(none_after_farm and lines == ["Has salido del Control militar km 12"],
		"leaving: no card; one P3 line only when it gets better (%s)" % [lines])
	# going deeper (a POI inside its district) is not leaving
	lines.clear()
	walk(zt, Vector3(3072, 0, 300), 2.0)    # Ensanche (peligro moderado… alto)
	walk(zt, Vector3(3200, 0, -768), 2.0)   # Hospital Provincial (extremo) inside the Ensanche
	walk(zt, Vector3(3072, 0, 300), 2.0)    # back out into the Ensanche
	check(lines == ["Has salido del Hospital Provincial"], "into a POI of the district: no line; out of it (extremo → alto): «%s»" % [lines])
	zt.queue_free()


# ------------------------------------------------------------------ fast mover: the highway sign
func _fast_mover() -> void:
	var zt := _tracker()
	var cards: Array = []
	zt.card_shown.connect(func(i: Dictionary) -> void: cards.append(i))
	# southbound on the A‐14 at 25 m/s (90 km/h), north of Altavega
	move(zt, Vector3(4096, 0, -1000), Vector3(4096, 0, -700), 25.0)
	var s: Dictionary = cards[-1] if not cards.is_empty() else {}
	var sg: Dictionary = s.get("sign", {})
	check(zt.speed > 20.0 and str(s.get("id", "")) == "autovia_a14" and str(s.get("card", "")) == "sign" and str(sg.get("style", "")) == "autovia"
		and str(sg.get("dest", "")) == "Altavega" and str(sg.get("dist", "")).ends_with("km") and str(sg.get("exit", "")) == "Gran Vía" and int(sg.get("exit_no", 0)) >= 1
		and str((sg.get("facts", []) as Array)[0] if not (sg.get("facts", []) as Array).is_empty() else "") == "A‐14",
		"scripted fast mover (%.0f km/h) on the A‐14: highway sign «%s %s / SALIDA %d %s →» · %s" % [zt.speed * 3.6, sg.get("dest", "-"), sg.get("dist", ""),
		int(sg.get("exit_no", 0)), sg.get("exit", "-"), sg.get("facts", [])])
	# fast into a district on the Gran Vía: the sign instead of the title
	zt.clock += 30.0
	move(zt, Vector3(3300, 0, -384), Vector3(2750, 0, -384), 25.0)
	var s2: Dictionary = cards[-1] if not cards.is_empty() else {}
	var sg2: Dictionary = s2.get("sign", {})
	check(str(s2.get("card", "")) == "sign" and str(sg2.get("dest", "")) == "Altavega" and str(sg2.get("style", "")) == "urbana" and str(s2.get("name", "")) in ["Las Torres", "Ensanche"],
		"fast on the Gran Vía into «%s»: sign «%s / SALIDA %d %s» instead of the title" % [s2.get("name", "-"), sg2.get("dest", "-"), int(sg2.get("exit_no", 0)), sg2.get("exit", "-")])
	# on foot into a place: the title; a teleport is not speed
	var zt2 := _tracker()
	var c2: Array = []
	zt2.card_shown.connect(func(i: Dictionary) -> void: c2.append(i))
	walk(zt2, Vector3(640, 0, 300), 2.0)   # N‐140 road bed, standing
	move(zt2, Vector3(640, 0, 300), Vector3(640, 0, 128), 1.5)   # walks into the Área de descanso
	walk(zt2, Vector3(640, 0, 128), 2.0)
	zt2.clock += 30.0
	walk(zt2, Vector3(640, 0, -384), 2.0)   # /tp to the Gasolinera norte (on the N‐140): a jump, not speed
	var titles: Array = c2.map(func(i: Dictionary) -> String: return "%s:%s" % [i["id"], i["card"]])
	check(titles.has("n140:sign") and titles.has("area_de_descanso:full") and titles.has("gasolinera_norte:full") and zt2.speed < 2.0,
		"on foot: the road's own sign once, titles for places; a teleport is not speed %s" % [titles])
	zt.queue_free()
	zt2.queue_free()


# ------------------------------------------------------------------ zone_entered → camera profile (C28)
func _camera() -> void:
	var holder := Node3D.new()
	holder.set_script(load("res://tests/city_bench/bench_player.gd"))
	tree.root.add_child(holder)
	holder.global_position = Vector3(2688, 0, -640)
	var rig := (load("res://tests/city_bench/bench_rig.tscn") as PackedScene).instantiate() as CameraRig
	holder.add_child(rig)
	await tree.process_frame
	rig._process(0.3)
	var before := rig.profile.id
	var zt := _tracker()
	zt.publish = true   # emits Events.zone_entered (the HUD's tracker does)
	var fighting := [true]
	zt.in_combat = func() -> bool: return fighting[0]
	walk(zt, Vector3(2688, 0, -640), 2.0)
	for i in 4:
		rig._process(0.25)
	var in_fight := rig.profile.id
	fighting[0] = false
	walk(zt, Vector3(2688, 0, -640), 0.25)
	for i in 8:
		rig._process(0.25)
	check(before == &"default" and in_fight == &"default" and rig.profile.id == &"torres" and rig.pitch_deg > -44.5,
		"zone_entered drives the camera profile: default → torres in Las Torres (C1 district profile, pitch %.1f°), never during a fight" % rig.pitch_deg)
	walk(zt, Vector3(-400, 0, -300), 2.0)
	for i in 8:
		rig._process(0.25)
	check(rig.profile.id == &"default", "back in the valley: default profile")
	zt.queue_free()
	holder.queue_free()
	await tree.process_frame


# ------------------------------------------------------------------ W1's 20 test points
func _w1_points() -> void:
	var wrong: Array[String] = []
	var zt := _tracker()
	for p in TITLE_POINTS:
		zt.forget_all()
		walk(zt, Vector3(float(p[0]), 0, float(p[1])), 2.0)
		var got := str(zt.current.get("name", "-"))
		if got != str(p[2]):
			wrong.append("(%d, %d) %s ≠ %s" % [int(p[0]), int(p[1]), got, str(p[2])])
	zt.queue_free()
	check(wrong.is_empty(), "correct titles at W1's 20 test points %s" % [wrong])


# ------------------------------------------------------------------ title and sign timelines
func _title_and_sign() -> void:
	var zc := ZoneTitle.new()
	zc.size = UiTokens.REF_SIZE
	tree.root.add_child(zc)
	zc.show_card({"id": &"x", "name": "Las Torres", "facts": ["Altavega", "sin electricidad", "−8 °C", "peligro alto"], "first_visit": true, "card": "full"})
	var f0: Dictionary = zc.frame(0.5)
	var f1: Dictionary = zc.frame(1.8)
	var f3: Dictionary = zc.frame(4.6)
	var spacing_open := UiTokens.tracking(UiTokens.ZONE_TITLE_SIZE, float(f0["em"]))
	var spacing_set := UiTokens.tracking(UiTokens.ZONE_TITLE_SIZE, float(f1["em"]))
	check(is_equal_approx(zc._total(), 5.6) and spacing_open > spacing_set and spacing_set == 32 and float(f1["facts_a"]) > 0.9 and float(f3["title_a"]) < 0.8,
		"first visit: 5.6 s, FontVariation.spacing_glyph %d → %d px (.78 → .42 em), one line of facts, fading at 4.6 s" % [spacing_open, spacing_set])
	zc.show_card({"id": &"x", "name": "Las Torres", "facts": [], "first_visit": false, "card": "compact"})
	check(is_equal_approx(zc._total(), 2.5) and is_equal_approx(float(zc.frame(1.0)["title_a"]), 0.6), "re-entry: the name at 60 % for 2.5 s")
	zc.queue_free()
	var zs := ZoneSign.new()
	zs.size = Vector2(1792, 220)
	tree.root.add_child(zs)
	zs.show_sign({"id": &"a14", "card": "sign", "sign": {"style": "autovia", "dest": "Altavega", "dist": "2 km", "exit": "Gran Vía", "exit_no": 1, "facts": ["A‐14"]}})
	check(is_equal_approx(zs.duration(), 3.0) and zs.alpha_at(1.5) == 1.0 and zs.alpha_at(2.99) < 0.05 and zs.is_showing(), "highway sign: 3 s (in 240 ms, out 500 ms)")
	check(ZoneSign.distance_text(1790) == "2 km" and ZoneSign.distance_text(4200) == "4 km" and ZoneSign.distance_text(640) == "600 m",
		"sign distances in whole km («2 km», «4 km»), hundreds of metres below 1 km")
	zs.queue_free()


# ------------------------------------------------------------------ discovery store (schema 3)
func _store() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var rec := {"by": "Ana", "token": "abc", "day": 3, "ts": 1790000000}
	var backends: Array = [["memory", MemoryBackend.new(), ""], ["file", FileBackend.new(), DIR + "/disc.json"]]
	if SqliteBackend.available():
		backends.append(["sqlite", SqliteBackend.new(), DIR + "/disc.db"])
	for b3: Array in backends:
		var tag := str(b3[0])
		var b: PersistenceBackend = b3[1]
		var path := str(b3[2])
		if path != "":
			for ext in ["", "-wal", "-shm"]:
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ext))
			b.open(path)
		b.save_discovery("group", "altavega_las_torres", rec)
		b.save_discovery("group", "altavega_las_torres", {"by": "Leo", "day": 5})   # the first one wins
		b.save_discovery("tok123", "valdenieve", {"by": "Leo", "token": "tok123", "day": 4, "ts": 1})
		b.flush()
		var d := b.load_discoveries()
		var ok := str(((d.get("group", {}) as Dictionary).get("altavega_las_torres", {}) as Dictionary).get("by", "")) == "Ana" \
			and (d.get("tok123", {}) as Dictionary).has("valdenieve") and b.schema_version() == 3
		if path != "":
			b.close()
			var b2: PersistenceBackend = FileBackend.new() if tag == "file" else SqliteBackend.new()
			ok = ok and b2.open(path) == OK and int((b2.load_discoveries().get("group", {}) as Dictionary).get("altavega_las_torres", {}).get("day", 0)) == 3
			b2.close()
		check(ok, "[%s] discoveries stored per scope (group / token), the first one wins, schema 3, survive a reopen" % tag)
	# migration from schema 2: a JSON document and a SQLite file written by M5
	var jp := DIR + "/v2.json"
	var f := FileAccess.open(jp, FileAccess.WRITE)
	f.store_string(JSON.stringify({"schema_version": 2, "world": {"day": 7, "world_version": 2}, "players": {}, "chunks": {}, "nominal": {}}))
	f.close()
	var fb := FileBackend.new()
	check(fb.open(jp) == OK and fb.loaded_schema() == 2 and fb.load_discoveries().is_empty() and fb.schema_version() == 3 and int(fb.load_world_meta().get("day", 0)) == 7,
		"[file] a schema 2 document migrates to 3 (discoveries added, the rest kept)")
	fb.close()
	if SqliteBackend.available():
		var sp := DIR + "/v2.db"
		for ext in ["", "-wal", "-shm"]:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(sp + ext))
		var db: Object = ClassDB.instantiate(&"SQLite")
		db.set("path", sp)
		db.set("verbosity_level", 0)
		db.call("open_db")
		for m in PersistenceSchema.migrations_after(0):
			if int(m.get("VERSION")) <= 2:
				for sql in (m.call("sqlite") as PackedStringArray):
					db.call("query", sql)
		db.call("query", "INSERT INTO world_meta(key, value) VALUES ('day', '9');")
		db.call("query", "PRAGMA user_version=2;")
		db.call("close_db")
		var sb := SqliteBackend.new()
		var ok := sb.open(sp) == OK and sb.loaded_schema == 2 and sb.user_version() == 3
		sb.save_discovery("group", "catedral", rec)
		ok = ok and (sb.load_discoveries().get("group", {}) as Dictionary).has("catedral") and int(sb.load_world_meta().get("day", 0)) == 9
		sb.close()
		check(ok, "[sqlite] a schema 2 store migrates to 3 (the discoveries table), the old rows kept")
	else:
		print("  (godot-sqlite not installed: SQLite store checks skipped — tools/fetch_godot_sqlite.sh)")


# ------------------------------------------------------------------ sound
func _sound() -> void:
	var s := load("res://assets/audio/ui/ui_zone_discover.wav") as AudioStream
	check(s != null and absf(s.get_length() - 1.8) < 0.05 and AudioManager.has_stream(&"ui_zone_discover")
		and FileAccess.file_exists("res://assets/audio/ui/LICENSE.txt"),
		"ui_zone_discover: placeholder 1.8 s (CC0, tools/gen_ui_sounds.py) registered in AudioManager")


# ------------------------------------------------------------------ names (C36)
func _names() -> void:
	var re := RegEx.create_from_string("(?i)albarr|\\balbar\\b")
	var hits: Array[String] = []
	var scanned := 0
	for root in ["res://data", "res://scripts", "res://scenes"]:
		scanned += _scan(root, re, hits)
	check(scanned > 200 and hits.is_empty(), "names (C36): no «Albarr» / «Albar» word in data/, scripts/, scenes/ (%d files) %s" % [scanned, hits])


func _scan(path: String, re: RegEx, hits: Array[String]) -> int:
	var n := 0
	var da := DirAccess.open(path)
	if da == null:
		return 0
	for d in da.get_directories():
		if not d.begins_with("."):
			n += _scan(path + "/" + d, re, hits)
	for fn in da.get_files():
		var ext := fn.get_extension()
		if not ext in ["gd", "tscn", "tres", "json", "cfg", "txt", "md", "csv", "gdshader"]:
			continue
		n += 1
		var text := FileAccess.get_file_as_string(path + "/" + fn)
		var m := re.search(text)
		if m != null:
			hits.append("%s/%s: %s" % [path, fn, m.get_string()])
	return n
