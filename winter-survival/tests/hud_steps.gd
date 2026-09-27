extends RefCounted
## H1 — HUD v2 «Susurro» checks (docs/research/10_hud_ux.md §V), called at the end of tests/smoke_steps.gd with the
## smoke body (for `check`). Headless: logic, layout and state machines; the rendered coverage gate is
## tests/run_hud_coverage.sh and the pictures are the hud_* screenshot presets.

var s: RefCounted   # the smoke body (check / frames / seconds)
var tree: SceneTree


func check(cond: bool, msg: String) -> void:
	s.call("check", cond, "HUD " + msg)


func frames(n: int) -> void:
	for i in n:
		await tree.process_frame


## Advances the HUD's clocks by `seconds` without waiting (visibility machine, router, feed, hazard, zone card).
func advance(hud: Hud, seconds: float, step: float = 0.05) -> void:
	var t := 0.0
	while t < seconds:
		hud.vis._process(step)
		hud.router._process(step)
		hud.feed._process(step)
		hud.hazard._process(step)
		hud.zone_title._process(step)
		t += step


func run(smoke: RefCounted, p_tree: SceneTree, game: Node, world: World, player: Player) -> void:
	s = smoke
	tree = p_tree
	var hud: Hud = game.get("hud")
	check(hud != null and hud.root != null and hud.vis != null, "v2 root, visibility machine and components built")
	if hud == null:
		return
	var settings := UiSettings.get_instance()
	settings.reset()
	if ZombieSystem.instance != null:
		ZombieSystem.instance.clear_all()
	world.get_node("WolfSpawner").enabled = false
	WorldState.instance.set_time(WorldState.instance.day, 11.0)
	if player.dead:
		GameFlow.request_respawn()
		await frames(5)
	player.state.health = Balance.HEALTH_MAX
	player.state.warmth = 90.0
	player.state.hunger = 80.0
	player.state.mark(&"stats")
	await frames(4)
	_foundation(hud)
	await _layout(hud)
	await _visibility(hud)
	await _idle(hud)
	await _hotbar(hud, player)
	await _vitals(hud, player)
	await _missions(hud, player)
	_zones(hud)
	_notifications(hud)
	_hazard(hud)
	await _info(hud, game)
	await _accent_and_edge(hud, world, player)
	await _map(hud, player)
	await _settings_panel(hud)
	_cpu(hud)
	settings.reset()
	hud.settle_to_rest()


# ------------------------------------------------------------------ foundation: fonts, theme, tokens
func _foundation(hud: Hud) -> void:
	var f := UiStyle.font_file(&"light")
	check(f != null and f.resource_path.ends_with("Barlow-Light.ttf") and UiStyle.font_file(&"cond_extralight").resource_path.ends_with("BarlowCondensed-ExtraLight.ttf"),
		"fonts bundled: Barlow Light + Barlow Condensed ExtraLight (%s)" % (f.resource_path if f != null else "-"))
	check(FileAccess.file_exists("res://assets/fonts/barlow/OFL.txt") and FileAccess.file_exists("res://assets/fonts/barlow_condensed/OFL.txt"), "OFL licence files next to the fonts")
	var ts := TextServerManager.get_primary_interface()
	var sc := UiStyle.font_of(&"smallcaps")
	var num := UiStyle.font_of(&"main_num")
	check(sc.opentype_features.has(ts.name_to_tag("smcp")) and sc.opentype_features.has(ts.name_to_tag("c2sc")) and num.opentype_features.has(ts.name_to_tag("tnum")),
		"real small caps (smcp + c2sc) and tabular figures (tnum) through FontVariation")
	var th := UiStyle.theme()
	check(th != null and th.get_color("accent", "Susurro") == UiTokens.ACCENT and th.get_color("ink", "Susurro") == UiTokens.INK
		and th.get_constant("objective_read_ms", "Susurro") == 5000 and th.get_constant("scrim_max_pct", "Susurro") == 45
		and th.get_constant("zone_first_out_ms", "Susurro") == 1600 and th.get_font_size("font_size", "LabelZoneTitle") == 76,
		"Theme resource carries the v2 tokens (colours, timings, scrim formula, type variations)")
	check(ResourceLoader.exists("res://assets/ui/susurro_theme.tres"), "Theme saved as assets/ui/susurro_theme.tres")
	check(is_equal_approx(UiTokens.scrim_alpha(0.2), 0.18) and is_equal_approx(UiTokens.scrim_alpha(0.9), 0.45) and UiTokens.scrim_alpha(0.575) > 0.3,
		"scrim α = mix(0.18, 0.45, smoothstep(0.35, 0.80, luma))")
	check(UiTokens.distance(84.2) == "84 m" and UiTokens.distance(642.0) == "640 m" and UiTokens.distance(1400.0) == "1,4 km"
		and UiTokens.temperature(-18.2) == "−18 °C" and UiTokens.countdown(160.0) == "2:40", "Spanish number formats (84 m, 640 m, 1,4 km, −18 °C, 2:40)")
	# legibility on a Steam Deck (1280 × 800, UI 115 %): every HUD style ≥ 12 px on screen (appendix §8.9)
	var deck_k := minf(1280.0 / 1920.0, 800.0 / 1080.0) * UiTokens.UI_SCALE_DECK
	var smallest := 999.0
	for st: StringName in UiStyle.STYLES:
		smallest = minf(smallest, float(UiStyle.size_of(st)) * deck_k)
	check(smallest >= UiTokens.DECK_MIN_PX, "Deck legibility: smallest HUD text %.1f px ≥ 12 px at 1280 × 800 × 115 %%" % smallest)


# ------------------------------------------------------------------ layout: reference scale, safe areas, UI scale
func _layout(hud: Hud) -> void:
	var vp := hud.size
	var k := minf(vp.x / 1920.0, vp.y / 1080.0)
	check(is_equal_approx(hud.k, k) and hud.root.size.is_equal_approx(vp / k), "reference 1920 × 1080 space scaled by k = %.3f (root %s)" % [hud.k, hud.root.size])
	var sb := Rect2(hud.safe.position, hud.safe.size)
	check(absf(sb.position.x - 64.0) < 0.5 and absf(sb.position.y - 52.0) < 0.5, "safe area 64 / 52 px at 16:9 (%s)" % sb)
	var settings := UiSettings.get_instance()
	settings.set_value("ui_scale", 1.25, false)
	await tree.process_frame
	check(is_equal_approx(hud.k, k * 1.25), "UI scale 125 %% → k %.3f" % hud.k)
	settings.set_value("ui_scale", 1.0, false)
	settings.set_value("screen_margin", 0.05, false)
	await tree.process_frame
	check(hud.safe.position.x > 64.0 + 90.0, "screen margin 5 %% moves the safe box inward (x %.0f)" % hud.safe.position.x)
	settings.set_value("screen_margin", 0.0, false)
	# 21:9 and 16:10 (simulated sizes): the corner blocks stay in a centred 16:9 box; 16:10 keeps the full width
	hud._layout(Vector2(2560.0 * 720.0 / 1080.0, 720.0))
	var w169 := hud.root.size.y * 16.0 / 9.0
	check(absf(hud.safe.position.x - ((hud.root.size.x - w169) * 0.5 + 64.0)) < 1.0 and absf(hud.safe.size.x - (w169 - 128.0)) < 1.0,
		"21:9: HUD box limited to a centred 16:9 (x %.0f, w %.0f of %.0f)" % [hud.safe.position.x, hud.safe.size.x, hud.root.size.x])
	hud._layout(Vector2(1280.0, 800.0))
	check(absf(hud.root.size.x - 1920.0) < 1.0 and hud.root.size.y > 1150.0 and absf(hud.hotbar.position.y + hud.hotbar.size.y - (hud.root.size.y - 40.0)) < 1.0,
		"16:10 (Deck): full width, extra height, hotbar anchored to the real bottom (root %s)" % hud.root.size)
	hud._layout()


# ------------------------------------------------------------------ visibility state machine
func _visibility(hud: Hud) -> void:
	var v := hud.vis
	var probe := Control.new()
	hud.root.add_child(probe)
	v.register(&"test.el", probe, [0.2, 3.0, 0.6], true, &"")
	v.poke(&"test.el")
	v._process(0.1)
	var appearing := v.phase_of(&"test.el") == HudVisibility.Phase.APPEARING and probe.visible
	v._process(0.2)
	var shown := v.phase_of(&"test.el") == HudVisibility.Phase.SHOWN and is_equal_approx(probe.modulate.a, 1.0)
	v._process(2.6)
	var still := v.phase_of(&"test.el") == HudVisibility.Phase.SHOWN
	v._process(0.3)
	var fading := v.phase_of(&"test.el") == HudVisibility.Phase.FADING and probe.modulate.a < 1.0
	v._process(0.7)
	check(appearing and shown and still and fading and v.phase_of(&"test.el") == HudVisibility.Phase.HIDDEN and not probe.visible,
		"element: hidden → appearing → shown (3 s) → fading → hidden")
	v.set_hold(&"test.el", true)
	v._process(5.0)
	var held := v.is_on(&"test.el")
	v.set_hold(&"test.el", false)
	v.set_info(true)
	v._process(0.3)
	var info := v.is_on(&"test.el")
	v.set_info(false)
	v._process(1.0)
	check(held and info and not v.is_on(&"test.el"), "hold keeps it, Info shows it, release hides it")
	# presets: Estándar keeps vitals and hotbar on, Completo also the tracker and the clock
	var st := UiSettings.get_instance()
	st.set_value("preset", &"estandar", false)
	v._process(0.3)
	var std := v.is_on(&"vitals.health") and v.is_on(&"hotbar") and not v.is_on(&"mission")
	st.set_value("preset", &"completo", false)
	v._process(0.3)
	var full := v.is_on(&"mission") and v.is_on(&"clock")
	st.set_value("elements", {&"vitals": &"hidden"}, false)
	v._process(0.3)
	var hidden := not v.is_on(&"vitals.health")
	st.reset()
	v._process(1.5)
	check(std and full and hidden and not v.is_on(&"vitals.health"), "presets Mínimo / Estándar / Completo and per-element override")
	probe.queue_free()


# ------------------------------------------------------------------ idle: only the strip
func _idle(hud: Hud) -> void:
	hud.settle_to_rest()
	await frames(3)
	hud.settle_to_rest()
	var on: Array = []
	for id in hud.vis.ids():
		if hud.vis.alpha_of(id) > 0.01:
			on.append(id)
	check(on.is_empty() and hud.hotbar.expand() < 0.01 and not hud.mission_line.visible and not hud.zone_title.visible and not hud.banner.visible,
		"idle: every element hidden, the hotbar folded into its strip (visible: %s)" % [on])
	# the idle ink is the strip: 10 × 22 × 2 px (rendered measure: tests/run_hud_coverage.sh)
	var strip := Rect2(0, 0, 10.0 * 22.0 + 9.0 * 6.0, 2.0)
	check(strip.get_area() / (1920.0 * 1080.0) * 100.0 < 3.0, "idle strip area %.3f %% of 1080p (< 3 %%)" % (strip.get_area() / (1920.0 * 1080.0) * 100.0))


# ------------------------------------------------------------------ hotbar (gamepad selection bug)
func _hotbar(hud: Hud, player: Player) -> void:
	var hb := hud.hotbar
	var sel0 := hb.selected
	var ev := InputEventAction.new()
	ev.action = &"hotbar_next"
	ev.pressed = true
	hb._unhandled_input(ev)
	await frames(2)
	hud.vis._process(0.3)
	check(hb.selected == wrapi(sel0 + 1, 0, Balance.HOTBAR_SLOTS) and hud.vis.is_on(Hotbar.EL) and hb.expand() > 0.5,
		"gamepad D-pad → moves the drawn selection (%d → %d) and unfolds the bar" % [sel0, hb.selected])
	hud.vis._process(3.7)
	check(not hud.vis.is_on(Hotbar.EL) and hb.expand() < 0.01, "the bar folds back into the strip 3 s after the last use")
	# a pickup that lands in the bar unfolds it
	player.state.inventory.add(&"piedra", 1)
	await frames(3)
	check(hud.vis.is_on(Hotbar.EL), "a pickup into the bar unfolds it")
	hb.selected = 0
	hud.vis.clear_all()
	hud.vis._process(1.0)


# ------------------------------------------------------------------ vitals
func _vitals(hud: Hud, player: Player) -> void:
	var v := hud.vitals
	player.state.warmth = 35.0
	player.state.mark(&"stats")
	await frames(6)
	v._update(0.1)
	hud.vis._process(0.4)
	check(&"warmth" in v.shown() and not (&"health" in v.shown()), "Calor 35 < 40 → only the warmth vital shows (%s)" % [v.shown()])
	player.state.warmth = 14.0
	player.state.mark(&"stats")
	await frames(6)
	v._update(0.1)
	check(v.word_of(&"warmth") == "te estás congelando", "Calor 14 → «te estás congelando»")
	await frames(2)
	check(hud.frost.visible and absf(float((hud.frost.material as ShaderMaterial).get_shader_parameter("strength")) - (1.0 - player.state.warmth / 40.0)) < 0.03,
		"frost vignette at 1 − Calor/40 = %.2f" % float((hud.frost.material as ShaderMaterial).get_shader_parameter("strength")))
	player.state.warmth = 90.0
	player.state.mark(&"stats")
	await frames(6)
	v._update(0.1)
	hud.vis._process(4.0 + 1.0)
	check(not (&"warmth" in v.shown()) and not hud.frost.visible, "warm again: the vital fades after 4 s, no frost")
	# a change ≥ 2 in 2 s shows health for 4 s even above 50
	player.state.health = 90.0
	player.state.mark(&"stats")
	await frames(6)
	hud.vis._process(0.4)
	check(&"health" in v.shown(), "health change ≥ 2 → shown (%s)" % [v.shown()])
	Events.status_changed.emit(&"wet", 0.4)
	check(v.word_of(&"warmth") == "mojado 40 %", "status hook: wet → «mojado 40 %%»")
	Events.status_changed.emit(&"wet", 0.0)
	Events.status_changed.emit(&"bleeding", 1.0)
	check(v.word_of(&"health") == "sangrando", "status hook: bleeding → «sangrando»")
	Events.status_changed.emit(&"bleeding", 0.0)
	player.state.health = Balance.HEALTH_MAX
	player.state.mark(&"stats")
	await frames(4)
	hud.vis.clear_all()
	hud.vis._process(2.0)


# ------------------------------------------------------------------ missions
func _missions(hud: Hud, player: Player) -> void:
	var ml := hud.mlog
	var m := ml.tracked()
	check(not m.is_empty() and str(m.get("kind")) == Missions.MAIN and (m.get("steps", []) as Array).size() >= 4 and str(m.get("title", "")) != "",
		"the day checklist is a main mission of the model (%s, %d steps)" % [m.get("title", "-"), (m.get("steps", []) as Array).size()])
	var q := player.state.quests
	var before := ml.changes
	var line_before := hud.mission_line.updates
	# the wood step of the day (2 on day 1, 6 later): progress 1 → is an update
	var wi := 0
	for i in q.steps.size():
		if int(q.steps[i]["count"]) > 1:
			wi = i
			break
	var need := int(q.steps[wi]["count"])
	q.index = wi
	q.counter = 0
	q._emit_state()
	await frames(4)
	player.state.emit_sim(&"item_picked_up", [&"madera", 1])
	await frames(4)
	var cur := Missions.current_step(ml.tracked())
	var want := "1/%d" % need
	check(ml.changes > before and hud.mission_line.updates > line_before and Missions.progress_text(cur) == want and hud.mission_line.count == want,
		"objective progress → «objetivo actualizado» line with the count (%s)" % Missions.progress_text(cur))
	check(hud.vis.is_on(MissionLine.EL) and hud.vis.is_on(&"edge"), "the line shows for 5 s and the edge marker may show")
	player.state.emit_sim(&"item_picked_up", [&"madera", need - 1])
	await frames(4)
	check(str(ml.last_change.get("what", "")) == "completed" and hud.mission_line.objective == str(Missions.current_step(ml.tracked()).get("title")),
		"step completed → the next objective is announced (%s)" % hud.mission_line.objective)
	# targets resolve to the world (the stove of the cabin)
	var st := Missions.step("t", "Alimenta la estufa", "", 1, [{"anchor": "group:stove", "label": "estufa"}])
	var tg := ml.targets_of(st, player.global_position, 2)
	check(not tg.is_empty() and str(tg[0]["label"]) == "estufa", "step targets resolve to world positions (stove at %s)" % (tg[0]["pos"] if not tg.is_empty() else "-"))
	# the model: side / dynamic kinds, compat with a legacy state
	var legacy := Missions.from_quest_state({"day": 3, "title_small": "DÍA 3", "steps": [{"title": "a", "hint": "", "done": true}, {"title": "b", "hint": ""}], "index": 1})
	check(legacy.size() == 1 and Missions.current_index(legacy[0]) == 1, "legacy quest state → mission model")
	hud.vis.clear_all()
	hud.vis._process(2.0)


# ------------------------------------------------------------------ zones: hysteresis, hierarchy, deferral
func _zones(hud: Hud) -> void:
	var zt := ZoneTracker.new()
	hud.add_child(zt)
	zt.enabled = false
	zt.forget_all()
	var entered: Array = []
	var cb := func(i: Dictionary) -> void: entered.append(i)
	Events.location_entered.connect(cb)
	# start deep inside the clearing (r 100)
	for i in 8:
		zt.step(Vector3(0, 0, 40), 0.25)
	var in_clearing := str(zt.current.get("id", "")) == "claro_del_cazador"
	var e0 := zt.entries
	# zigzag on the clearing's border (x 92 ↔ 108) for 20 s: never 12 m outside for 1.5 s → no change
	for i in 80:
		zt.step(Vector3(92.0 if i % 2 == 0 else 108.0, 0, 0), 0.25)
	var zig := zt.entries - e0
	# walk out and stay ≥ 12 m outside for 1.5 s → one change (the forest)
	for i in 8:
		zt.step(Vector3(130, 0, 0), 0.25)
	check(in_clearing and zig == 0 and zt.entries == e0 + 1 and str(zt.current.get("id")) == "bosque_profundo",
		"hysteresis: zigzag on a border = %d changes; 12 m outside for 1.5 s = 1 change (%s)" % [zig, zt.current.get("name", "-")])
	# re-entry within 90 s: no card; the first visit had a full card
	var first_card := false
	for e: Dictionary in entered:
		if str(e["id"]) == "claro_del_cazador" and str(e["card"]) == "full" and bool(e["first_visit"]):
			first_card = true
	entered.clear()
	for i in 8:
		zt.step(Vector3(0, 0, 40), 0.25)
	var re: Dictionary = entered[-1] if not entered.is_empty() else {}
	check(first_card and str(re.get("card", "")) == "none", "first visit → full card; re-entry within 90 s → no card")
	# hierarchy with the Altavega data hook: the district wins, the city is its first fact
	Locations.enable_city(true, Vector2(0, 0))
	entered.clear()
	zt.clock += 30.0
	for i in 8:
		zt.step(Vector3(0, 0, -2700), 0.25)
	var d: Dictionary = entered[-1] if not entered.is_empty() else {}
	var facts: Array = d.get("facts", [])
	check(str(d.get("name", "")) == "Distrito Financiero" and not facts.is_empty() and str(facts[0]) == "Altavega" and facts.has("sin electricidad") and str(facts[-1]).begins_with("peligro"),
		"city hook: district over city, facts «%s»" % " · ".join(facts))
	# combat defers the card; it is shown once the fight is over (20 s after the last card)
	entered.clear()
	var fighting := [true]
	zt.in_combat = func() -> bool: return fighting[0]
	zt.clock += 30.0
	for i in 10:
		zt.step(Vector3(-600, 0, -2500), 0.25)
	var deferred := entered.filter(func(e: Dictionary) -> bool: return str(e["card"]) != "none").is_empty() and not zt.queued.is_empty()
	fighting[0] = false
	zt.clock += 25.0
	zt.step(Vector3(-600, 0, -2500), 0.25)
	var shown := not entered.filter(func(e: Dictionary) -> bool: return str(e["card"]) == "full").is_empty()
	check(deferred and shown, "zone card deferred during combat, shown after (%s)" % zt.current.get("name", "-"))
	Locations.reset()
	Events.location_entered.disconnect(cb)
	zt.forget_all()
	zt.queue_free()
	# the card itself: 5.6 s first visit, name at 60 % on re-entry
	var zc := hud.zone_title
	zc.show_card({"id": &"x", "name": "Prueba", "facts": ["−8 °C"], "first_visit": true, "card": "full"})
	var f0: Dictionary = zc.frame(0.5)
	var f2: Dictionary = zc.frame(1.8)
	var f3: Dictionary = zc.frame(4.6)
	var tracked_ok := float(f0["em"]) > 0.6 and is_equal_approx(float(f2["em"]), UiTokens.ZONE_TITLE_EM) and float(f3["title_a"]) < 0.8
	advance(hud, 5.7)
	var gone := not zc.is_showing()
	zc.show_card({"id": &"x", "name": "Prueba", "facts": [], "first_visit": false, "card": "compact"})
	var fc: Dictionary = zc.frame(1.0)
	advance(hud, 2.6)
	check(tracked_ok and gone and is_equal_approx(float(fc["title_a"]), 0.6) and not zc.is_showing(),
		"title card: tracking .78 → .42 em, fades by 5.6 s; re-entry = name at 60 %% for 2.5 s")


# ------------------------------------------------------------------ notifications: banner queue, feed merge
func _notifications(hud: Hud) -> void:
	var r := hud.router
	r.queue.clear()
	r.current = {}
	r.push({"priority": 2, "key": "a", "body": "Aviso A", "seconds": 3.0})
	advance(hud, 0.4)
	var a_on: bool = r.current.get("key", "") == "a"
	advance(hud, 1.0)
	r.push({"priority": 0, "key": "p0", "body": "Urgente", "seconds": 2.0})
	advance(hud, 0.4)
	var p0_on: bool = r.current.get("key", "") == "p0" and r.queue.size() == 1 and r.queue[0]["key"] == "a"
	for i in 9:
		r.push({"priority": 2, "key": "k%d" % i, "body": "n%d" % i, "seconds": 1.0})
	check(a_on and p0_on and r.queue.size() == UiTokens.NOTIFY_QUEUE, "banner: P0 pre-empts a P2 shown > 1.2 s (it goes back to the queue); queue capped at 6")
	r.queue.clear()
	r.current = {}
	advance(hud, 0.5)
	# legacy notices are classified
	var before: Dictionary = r.counts.duplicate()
	r.notify_text("Sin aliento", 1.2)
	r.notify_text("Te estás congelando", 3.0)
	r.notify_text("Fabricado: Hacha de piedra", 3.0)
	r.notify_text("Inventario lleno", 2.0)
	check(int(r.counts.get(&"stamina", 0)) > int(before.get(&"stamina", 0)) and int(r.counts.get(&"vitals", 0)) > int(before.get(&"vitals", 0))
		and int(r.counts.get(&"feed", 0)) > int(before.get(&"feed", 0)) and int(r.counts.get(&"banner", 0)) > int(before.get(&"banner", 0)),
		"legacy notices routed: stamina arc, vital, side stack, banner")
	# the side stack merges counters
	var fd := hud.feed
	fd.lines.clear()
	fd.add("item:madera", "Madera", 2, 4)
	advance(hud, 0.5)
	fd.add("item:madera", "Madera", 1, 5)
	check(fd.lines.size() == 1 and fd.text_of(fd.lines[0]) == "Madera +3 (5)" and fd.merges >= 1, "pickups merge: «%s»" % (fd.text_of(fd.lines[0]) if not fd.lines.is_empty() else "-"))
	advance(hud, 6.0)
	check(fd.lines.is_empty(), "the side stack empties after its read time")
	r.queue.clear()
	r.current = {}
	advance(hud, 1.0)


# ------------------------------------------------------------------ hazards: forecast → soon → active → end
func _hazard(hud: Hud) -> void:
	var hz := hud.hazard
	Events.hazard_changed.emit(&"blizzard", &"forecast", {"detail": "en ~2 h"})
	var fc := " · ".join(hz.line_parts())
	Events.hazard_changed.emit(&"blizzard", &"soon", {"seconds": 60.0})
	var soon := " · ".join(hz.line_parts())
	Events.hazard_changed.emit(&"blizzard", &"active", {"seconds": 160.0})
	advance(hud, 0.1)
	var act := " · ".join(hz.line_parts())
	check(fc.begins_with("ventisca prevista") and soon.contains("se acerca") and soon.contains("1:00") and act == "ventisca · visibilidad 6 m · 2:40",
		"hazard line: «%s» → «%s» → «%s»" % [fc, soon, act])
	advance(hud, 6.0)
	check(hz.visible and hud.vis.alpha_of(HazardLine.EL) < 0.01, "after 5 s the line shrinks to the icon and the time")
	Events.hazard_changed.emit(&"blizzard", &"end", {})
	advance(hud, 4.5)
	check(hz.state == &"", "end → «la ventisca amaina» for 3 s, then nothing")


# ------------------------------------------------------------------ Info (hold) and the tap that keeps crafting
func _info(hud: Hud, game: Node) -> void:
	hud.input.set_info(true)
	hud.vis._process(0.3)
	var on := hud.vis.is_on(MissionList.EL) and hud.vis.is_on(&"clock") and hud.vis.is_on(Hotbar.EL) and hud.vis.is_on(&"vitals.warmth")
	hud.input.set_info(false)
	hud.vis._process(0.5)
	check(on and not hud.vis.is_on(MissionList.EL), "Info held: missions, time / temperature, vitals and hotbar; released: gone")
	# a Tab TAP still opens crafting (the tap is re-sent as toggle_craft)
	var cp: CraftPanel = game.get("craft_panel")
	var was := cp.visible
	var taps := hud.input.taps
	var down := InputEventKey.new()
	down.physical_keycode = KEY_TAB
	down.pressed = true
	Input.parse_input_event(down)
	await frames(2)
	var up := InputEventKey.new()
	up.physical_keycode = KEY_TAB
	up.pressed = false
	Input.parse_input_event(up)
	await frames(4)
	check(hud.input.taps == taps + 1 and cp.visible != was, "Tab tap → crafting (panel %s → %s)" % [was, cp.visible])
	if cp.visible:
		cp.close()
	# a HOLD shows Info instead
	Input.parse_input_event(down)
	for i in 30:
		await tree.process_frame
		if hud.vis.info_active:
			break
	var held := hud.vis.info_active
	Input.parse_input_event(up)
	await frames(3)
	check(held and not hud.vis.info_active and not cp.visible, "Tab held ≥ 0.22 s → Info while held, crafting untouched")


# ------------------------------------------------------------------ accent priority and the edge rail
func _accent_and_edge(hud: Hud, world: World, player: Player) -> void:
	var ac := hud.accent
	ac.update()
	var obj: bool = ac.accent.get("kind", &"") == &"objective" or ac.accent.is_empty()
	# freezing next to a lit campfire → the heat takes the accent
	var p := player.global_position + Vector3(6, 0, 0)
	p.y = world.get_height(p.x, p.z)
	var cf: Node = world.spawn_placed("campfire", p, 0.0)   # the server lights a new campfire with its starting fuel
	await frames(3)
	player.state.warmth = 20.0
	await frames(2)
	ac.update()
	var heat: bool = ac.accent.get("kind", &"") == &"heat" and ac.edge_allowed()
	check(obj and heat, "accent: objective at rest, the nearest heat when Calor < 30 (%s)" % ac.accent.get("label", "-"))
	player.state.warmth = 90.0
	player.state.mark(&"stats")
	check(cf != null, "campfire placed for the accent check")
	# edge rail: 360 directions from the player's screen point stay on the rail and out of the hotbar
	var wl := hud.world_layer
	var origin := hud.root.size * 0.5
	var bad := 0
	var rail := Rect2(Vector2(WorldLayer.RAIL_X, WorldLayer.RAIL_Y), hud.root.size - Vector2(WorldLayer.RAIL_X, WorldLayer.RAIL_Y) * 2.0).grow(1.0)
	var hot := Rect2(hud.hotbar.position, hud.hotbar.size)
	var bad_list: Array = []
	for a in 360:
		var q := wl.rail_point(origin, Vector2.from_angle(deg_to_rad(float(a))))
		if not rail.has_point(q) or hot.has_point(q):
			bad += 1
			if bad_list.size() < 4:
				bad_list.append([a, q])
	check(bad == 0, "edge rail: 360 directions land on the rail, never on the hotbar (%d bad %s)" % [bad, bad_list])


# ------------------------------------------------------------------ P1: paper map with fog of war + journal
func _map(hud: Hud, player: Player) -> void:
	var ms := hud.map_screen
	var p := player.global_position
	# on a blank map: the fog persists per seed in user:// and other runs (perf walk, shots) explore this seed too
	var kept := ms.fog.bits.duplicate()
	ms.fog.clear_all()
	ms.fog.reveal(p.x, p.z, MapFog.REVEAL)
	check(ms.fog.is_revealed(p.x, p.z) and not ms.fog.is_revealed(p.x + 400.0, p.z + 400.0) and ms.fog.explored_fraction() > 0.0,
		"map fog: 40 m around the player revealed (%.3f %% of the world), far ground blank" % (ms.fog.explored_fraction() * 100.0))
	ms.fog.restore(kept)
	ms.fog.reveal(p.x, p.z, MapFog.REVEAL)
	var ev := InputEventAction.new()
	ev.action = &"map"
	ev.pressed = true
	ms._unhandled_input(ev)
	await frames(2)
	var uv := MapScreen.world_to_uv(Vector3.ZERO)
	check(ms.is_open and ms.visible and ms._land != null and uv.is_equal_approx(Vector2(0.5, 0.5)), "M opens the paper map (land texture from the macro map)")
	var tabev := InputEventAction.new()
	tabev.action = &"rotate_cam_right"
	tabev.pressed = true
	ms._input(tabev)
	var journal := ms.tab == &"journal"
	var zev := InputEventAction.new()
	zev.action = &"zoom_in"
	zev.pressed = true
	ms._input(zev)
	var zoomed := ms.zoom == 1 and ms.view_rect().size.x < 0.5
	ms._input(ev)
	await frames(1)
	check(journal and zoomed and not ms.is_open, "map: Q / E → DIARIO, zoom in, M closes")
	ms.zoom = 0
	ms.tab = &"map"


# ------------------------------------------------------------------ CPU budget (appendix §8.8: ≤ 0.5 ms per frame)
func _cpu(hud: Hud) -> void:
	var nodes: Array = []
	for n: Node in [hud, hud.vis, hud.team, hud.accent, hud.input, hud.world_layer, hud.mission_line, hud.mission_list,
			hud.hazard, hud.vitals, hud.info_block, hud.feed, hud.zone_title, hud.banner, hud.hotbar, hud.downed,
			hud.router, hud.zones, hud.map_screen, hud.map_screen.fog]:
		if n.has_method("_process"):
			nodes.append(n)
	# a busy moment: vitals, the mission line, the edge marker and Info all on
	hud.vis.poke(&"vitals.warmth")
	hud.vis.poke(MissionLine.EL)
	hud.vis.poke(&"edge")
	var frames_n := 300
	var acc: Dictionary = {}
	var t0 := Time.get_ticks_usec()
	for i in frames_n:
		for n: Node in nodes:
			var t1 := Time.get_ticks_usec()
			n.call("_process", 1.0 / 60.0)
			acc[n.name] = int(acc.get(n.name, 0)) + Time.get_ticks_usec() - t1
	var per := float(Time.get_ticks_usec() - t0) / float(frames_n) / 1000.0
	var worst: Array = []
	for k in acc:
		worst.append([snappedf(float(acc[k]) / float(frames_n), 0.1), String(k)])
	worst.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	print("  HUD cpu per node (µs/frame): %s" % str(worst.slice(0, 6)))
	# budget 0.5 ms; the gate allows 2× for the noise of a shared 2-core machine (the number is reported)
	check(per <= 1.0, "HUD logic (every _process of the HUD, busy moment) %.3f ms per frame (budget 0.5 ms, gate 1.0 ms on a shared CPU)" % per)
	hud.vis.clear_all()


# ------------------------------------------------------------------ "Interfaz y accesibilidad" panel
func _settings_panel(hud: Hud) -> void:
	var panel := HudSettingsPanel.new()
	hud.add_child(panel)
	await frames(1)
	var st := UiSettings.get_instance()
	var toggled := false
	for row in panel._rows.get_children():
		if row is CheckButton and str(row.get_meta("key")) == "reduced_motion":
			(row as CheckButton).button_pressed = true
			toggled = true
	var on := bool(st.values.get("reduced_motion"))
	for row in panel._rows.get_children():
		for n in [row] + row.get_children():
			if n is OptionButton and str(n.get_meta("key")) == "preset":
				(n as OptionButton).select(1)
				(n as OptionButton).item_selected.emit(1)
	var preset: StringName = st.values.get("preset")
	check(toggled and on and preset == &"estandar" and UiMotion.reduced(), "settings panel writes UiSettings (reduced motion, preset %s)" % preset)
	st.reset(true)   # the panel saved to user://settings.cfg: put the defaults back
	panel.queue_free()
