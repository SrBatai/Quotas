extends RefCounted
## Body of tests/unit/notify_router_test.gd (H3). Headless, no game scene: a bare NotifyRouter wired to a real
## NotifyBanner (the P1 / P2 line), PickupStack (P3), HazardLine (+ its HazardStack), ZoneTitle, HudVisibility and
## SoundCaptions under a root Control; the router's clock is driven by `tick(dt)` so every timing is exact.

var tree: SceneTree
var _checks := 0
var _failed := false
var root: Control
var vis: HudVisibility
var router: NotifyRouter
var banner: NotifyBanner
var feed: PickupStack
var hazard: HazardLine
var title: ZoneTitle
var captions: SoundCaptions
var played: Array = []   # [event, at] from AudioManager.event_played


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
	print("== VENTISCA H3 notify router test (P0–P3, precedence, queue, merge, cooldown, hazards)")
	var t0 := Time.get_ticks_msec()
	UiSettings.get_instance().reset()
	_build()
	AudioManager.event_played.connect(func(e: StringName, _v: Node, at: Vector3) -> void: played.append([e, at]))
	_priorities()
	_precedence()
	_attention_short()
	_merge()
	_cooldown()
	_queue_full()
	_feed()
	_coop()
	_zone_crossing()
	_p0_lifecycle()
	_p0_sound_caption()
	_legacy()
	_p0_banner_option()
	_hazards()
	_hazard_kinds()
	UiSettings.get_instance().reset()
	root.queue_free()
	print("== %d checks, %s (%d ms)" % [_checks, "FAILED" if _failed else "ALL PASSED", Time.get_ticks_msec() - t0])
	tree.quit(1 if _failed else 0)


# ------------------------------------------------------------------ helpers
func _build() -> void:
	root = Control.new()
	root.size = Vector2(1920, 1080)
	tree.root.add_child(root)
	vis = HudVisibility.new()
	root.add_child(vis)
	for s: StringName in [&"warmth", &"health", &"hunger"]:
		vis.register(StringName("vitals." + String(s)), null, UiTokens.T_VITAL, true, &"vitals")
	banner = NotifyBanner.new()
	banner.size = Vector2(1920, 260)
	root.add_child(banner)
	feed = PickupStack.new()
	feed.size = Vector2(560, 200)
	root.add_child(feed)
	hazard = HazardLine.new()
	hazard.size = Vector2(760, 40)
	root.add_child(hazard)
	hazard.setup(vis)
	title = ZoneTitle.new()
	title.size = Vector2(1920, 1080)
	root.add_child(title)
	captions = SoundCaptions.new()
	captions.size = Vector2(1000, 110)
	root.add_child(captions)
	router = NotifyRouter.new()
	router.banner = banner
	router.feed = feed
	router.hazard = hazard
	router.zone_title = title
	router.vis = vis
	router.captions = captions
	root.add_child(router)
	hazard.router = router


## Advances every clock of the fixture by `seconds` in 50 ms steps.
func advance(seconds: float, step: float = 0.05) -> void:
	var t := 0.0
	while t < seconds - 0.0001:
		router.tick(step)
		vis._process(step)
		feed._process(step)
		hazard._process(step)
		title._process(step)
		captions._process(step)
		banner._process(step)
		t += step


func reset() -> void:
	router.clear_all()
	router.stats = {"merged": 0, "dropped": 0, "cooled": 0, "preempted": 0, "filtered": 0, "p0": 0, "shown": 0}
	router.shown_keys.clear()
	router.p0_keys.clear()
	feed.lines.clear()
	captions.clear()
	title.t = -1.0
	advance(3.5)   # past any attention window and the 0.3 s gap
	played.clear()


func n2(key: String, secs: float = 3.0) -> Dictionary:
	return {"priority": 2, "key": key, "body": "Aviso " + key, "seconds": secs}


func cur() -> String:
	return str(router.current.get("key", ""))


# ------------------------------------------------------------------ checks
func _priorities() -> void:
	reset()
	router.push(n2("a"))
	advance(0.1)
	router.push(n2("b"))
	router.push({"priority": 1, "key": "c", "body": "Misión completada", "seconds": 3.0})
	router.push(n2("d"))
	var order := router.queue.map(func(e: Dictionary) -> String: return str(e["key"]))
	check(cur() == "a" and order == ["c", "b", "d"], "priority: the P1 goes before the queued P2s, FIFO within a priority (%s, queue %s)" % [cur(), order])
	advance(2.8)
	var still_a := cur() == "a"
	advance(0.3)
	var gap := router.current.is_empty()
	advance(0.3)
	check(still_a and gap and cur() == "c" and banner.text_now() == "Misión completada", "the line is 3 s; the next (the P1) follows 300 ms later (%s)" % cur())
	advance(3.4)
	check(cur() == "b", "then the P2s in arrival order (%s)" % cur())


func _precedence() -> void:
	reset()
	router.push(n2("a", 3.0))
	advance(1.5)   # shown for > 1.2 s
	router.push(n2("x"))
	router.push({"priority": 0, "key": "p0", "title": "derribo", "body": "Ana está en el suelo", "target": &"world", "seconds": 0.0})
	var back: Dictionary = router.queue[0] if not router.queue.is_empty() else {}
	check(router.current.is_empty() and str(back.get("key", "")) == "a" and bool(back.get("preempted", false)) and int(router.stats["preempted"]) == 1,
		"precedence: a P0 takes the line from a P2 shown > 1.2 s; the P2 goes back to the queue, first of its priority (queue %s)" % [router.queue.map(func(e: Dictionary) -> String: return str(e["key"]))])
	check(router.p0.has("p0") and router.p0_active() and banner.text_now() != "Ana está en el suelo" and not banner.text_now().contains("suelo"),
		"the P0 is NOT a banner: it lives in the world (router.p0, p0_world %d)" % router.p0_world().size())
	advance(2.8)
	check(router.current.is_empty(), "the line waits while the P0 owns the attention (3 s)")
	advance(0.6)
	check(cur() == "a", "after the attention window (+300 ms) the interrupted notice comes back (%s)" % cur())
	router.end_p0("p0")
	check(not router.p0_active(), "end_p0: the condition is over")


func _attention_short() -> void:
	reset()
	router.push(n2("a", 3.0))
	advance(0.6)   # shown for < 1.2 s: it is not interrupted
	router.push({"priority": 0, "key": "p0b", "body": "hielo fino", "target": &"world", "seconds": 1.0})
	check(cur() == "a" and int(router.stats["preempted"]) == 0, "a line shown < 1.2 s is not interrupted by a P0 (%s)" % cur())
	router.push(n2("b"))
	advance(2.6)   # "a" ends at 3.0 s; the attention window runs until 3.6 s from its start at 0.6 s
	check(cur() == "", "the next line waits for the end of the P0's attention window")
	advance(1.0)
	check(cur() == "b" and not router.p0.has("p0b"), "a timed P0 (1 s) ends by itself; the queue resumes (%s)" % cur())


func _merge() -> void:
	reset()
	router.push(n2("m", 3.0))
	advance(2.0)
	router.push(n2("m", 3.0))
	check(cur() == "m" and int(router.current.get("count", 1)) == 2 and banner.text_now().ends_with("×2") and router.queue.is_empty(),
		"the same key on the line refreshes it (×2) instead of repeating it («%s»)" % banner.text_now())
	advance(2.5)
	check(cur() == "m", "…and its 3 s start again (still on the line 4.5 s after the first)")
	router.push(n2("q1"))
	router.push(n2("q1", 5.0))
	var q: Array = router.queue.filter(func(e: Dictionary) -> bool: return str(e["key"]) == "q1")
	check(q.size() == 1 and float(q[0]["seconds"]) == 5.0 and int(router.stats["merged"]) == 2, "the same key queued is updated, not duplicated")


func _cooldown() -> void:
	reset()
	router.push({"priority": 2, "key": "Inventario lleno", "body": "Inventario lleno", "seconds": 1.5})
	advance(2.2)
	router.push({"priority": 2, "key": "Inventario lleno", "body": "Inventario lleno", "seconds": 1.5})
	var cooled := int(router.stats["cooled"]) == 1 and router.queue.is_empty() and router.current.is_empty()
	advance(6.5)
	router.push({"priority": 2, "key": "Inventario lleno", "body": "Inventario lleno", "seconds": 1.5})
	advance(0.4)
	check(cooled and cur() == "Inventario lleno", "cooldown key: at most once every 8 s (second dropped, shown again after 8 s)")


func _queue_full() -> void:
	reset()
	router.push(n2("on", 30.0))
	advance(0.1)
	for i in 8:
		router.push(n2("k%d" % i))
		advance(0.01)
	router.push({"priority": 1, "key": "p1", "body": "Peligro inminente", "seconds": 3.0})
	var keys := router.queue.map(func(e: Dictionary) -> String: return str(e["key"]))
	check(router.queue.size() == UiTokens.NOTIFY_QUEUE and keys[0] == "p1" and not keys.has("k0") and not keys.has("k1") and not keys.has("k2") and keys.has("k7")
		and int(router.stats["dropped"]) == 3, "queue of 6: full → the oldest of the lowest priority goes (%s)" % [keys])
	router.push({"priority": 3, "key": "p3", "body": "Madera +1"})
	check(router.queue.size() == UiTokens.NOTIFY_QUEUE and not keys.has("p3"), "a P3 never enters the line queue")


func _feed() -> void:
	reset()
	router.push({"priority": 3, "key": "disc:granja", "body": "Ana descubrió: Granja del Molino"})
	feed.add("item:madera", "Madera", 2, 4)
	advance(0.5)
	feed.add("item:madera", "Madera", 1, 5)
	var txt := feed.text_of(feed.lines[-1]) if not feed.lines.is_empty() else "-"
	check(feed.lines.size() == 2 and txt == "Madera +3 (5)" and str(feed.lines[0]["label"]).begins_with("Ana descubrió"),
		"P3 → the pickup line; the same item within 2.5 s merges («%s»)" % txt)
	advance(6.0)
	check(feed.lines.is_empty(), "the pickup line empties after its read time (2.5 s, +1 s per merge)")


func _coop() -> void:
	reset()
	router.push({"priority": 2, "key": "lvl", "body": "Leo sube de nivel", "from_peer": 5})
	router.push({"priority": 2, "key": "ping", "body": "Leo: peligro · 40 m", "from_peer": 5, "affects_me": true})
	router.push({"priority": 2, "key": "mine", "body": "Tu aviso", "from_peer": Net.local_peer_id()})
	advance(0.4)
	var keys := [cur()] + router.queue.map(func(e: Dictionary) -> String: return str(e["key"]))
	check(int(router.stats["filtered"]) == 1 and keys.has("ping") and keys.has("mine") and not keys.has("lvl"),
		"co-op filter: from another player only what affects you (%s)" % [keys])


func _zone_crossing() -> void:
	reset()
	title.show_card({"id": &"x", "name": "Prueba", "facts": [], "first_visit": false, "card": "compact"})
	router.push(n2("z"))
	advance(1.0)
	var waited := router.current.is_empty() and title.is_showing()
	router.push({"priority": 0, "key": "p0z", "body": "derribo", "target": &"world", "seconds": 1.0})
	var p0_now := router.p0.has("p0z")
	advance(3.2)   # the compact card is 2.5 s; the P0's attention window 3 s
	check(waited and p0_now and cur() == "z", "P1 / P2 wait while a zone title is on screen; a P0 does not (%s)" % cur())


func _p0_lifecycle() -> void:
	reset()
	var still := [true]
	router.push({"priority": 0, "key": "freeze", "body": "Te estás congelando", "target": &"vital", "vital": &"warmth", "seconds": 0.0,
		"hold": func() -> bool: return still[0]})
	vis._process(0.3)
	var held := vis.is_on(&"vitals.warmth") and router.p0.has("freeze")
	advance(6.0)
	var kept := router.p0.has("freeze") and vis.is_on(&"vitals.warmth")
	still[0] = false
	advance(0.3)
	vis._process(1.0)
	check(held and kept and not router.p0.has("freeze") and not vis.is_on(&"vitals.warmth"),
		"P0 on the vital: holds the vital while the condition lasts (6 s), ends and releases it when it is over")
	var got: Array = []
	var cb := func(n: Dictionary, on: bool) -> void: got.append([str(n["key"]), on])
	Events.p0_notice.connect(cb)
	router.push({"priority": 0, "key": "w1", "body": "x", "target": &"bogus", "seconds": 0.0})
	var target: StringName = router.p0["w1"]["target"]
	router.end_p0("w1")
	router.end_p0("w1")
	Events.p0_notice.disconnect(cb)
	check(target == &"world" and got == [["w1", true], ["w1", false]], "unknown target → world; Events.p0_notice on / off once (%s)" % [got])


func _p0_sound_caption() -> void:
	reset()
	var pos := Vector3(12, 0, -5)
	router.push({"priority": 0, "key": "mate_down:7", "title": "derribo", "body": "Ana está en el suelo", "target": &"world", "peer": 7,
		"subject": "Ana", "pos": pos, "sound": &"ui_mate_down", "seconds": 0.0})
	var ev: Array = played.filter(func(p: Array) -> bool: return p[0] == &"ui_mate_down")
	var cap: Dictionary = captions.lines[-1] if not captions.lines.is_empty() else {}
	check(ev.size() == 1 and not cap.is_empty() and str(cap["text"]) == "latido y estática de radio" and str(cap["subject"]) == "Ana"
		and (cap["pos"] as Vector3) == pos, "P0 sound: ui_mate_down played once (event_played) and captioned with its subject and source (%s)" % [captions.history])
	router.push({"priority": 0, "key": "mate_down:7", "body": "Ana está en el suelo", "target": &"world", "sound": &"ui_mate_down", "seconds": 0.0})
	check(played.filter(func(p: Array) -> bool: return p[0] == &"ui_mate_down").size() == 1, "the same P0 again only refreshes it (no second cue)")
	UiSettings.get_instance().set_value("captions", &"off", false)
	var n := captions.shown
	router.end_p0("mate_down:7")
	router.push({"priority": 0, "key": "mate_down:8", "body": "Leo está en el suelo", "target": &"world", "sound": &"ui_mate_down", "seconds": 0.0, "subject": "Leo"})
	var off_ok := captions.shown == n
	UiSettings.get_instance().set_value("captions", &"all", false)
	captions._on_event(&"zombie_alert", null, Vector3(1, 0, 1))
	var all_ok := captions.shown == n + 1 and str(captions.lines[-1]["text"]).contains("te han visto")
	UiSettings.get_instance().set_value("captions", &"p0", false)
	captions._on_event(&"zombie_alert", null, Vector3(1, 0, 1))
	check(off_ok and all_ok and captions.shown == n + 1, "captions setting: off → none; all → warnings too («te han visto»); p0 (default) → only P0")
	check(SoundCaptions.dir_word(Vector2(1, 0)) == "derecha" and SoundCaptions.dir_word(Vector2(0, -1)) == "delante"
		and SoundCaptions.dir_word(Vector2(-0.7071, 0.7071)) == "detrás a la izquierda", "caption direction words by screen sector (derecha, delante, detrás a la izquierda)")


func _legacy() -> void:
	reset()
	var before: Dictionary = router.counts.duplicate()
	router.notify_text("Sin aliento", 1.2)
	router.notify_text("Fabricado: Hacha de piedra", 3.0)
	router.notify_text("La lámpara parpadea", 3.0)
	router.notify_text("¡Estás derribado! Aguanta hasta que te reanimen", 4.0)
	router.notify_text("Te estás congelando", 3.0)
	var d := func(k: StringName) -> int: return int(router.counts.get(k, 0)) - int(before.get(k, 0))
	check(d.call(&"stamina") == 1 and d.call(&"feed") == 1 and d.call(&"banner") == 1 and d.call(&"downed") == 1 and d.call(&"vitals") == 1,
		"legacy notices: stamina arc, side line, the 3 s line, own downed, the vital")
	check(router.p0.has("self_down") and router.p0.has("freezing") and router.p0["freezing"]["target"] == &"vital",
		"own downed and freezing are P0 (self / on the Calor vital), never a banner")
	advance(0.4)
	check(not router.p0.has("freezing") and not router.p0.has("self_down"), "…ended by their conditions (no local player here)")
	router.notify_text("Se acerca una ventisca…", 4.0)
	check(hazard.stack.state_of(&"blizzard") == &"soon", "«Se acerca una ventisca…» → the hazard stack (imminent)")
	hazard.stack.clear_all()


func _p0_banner_option() -> void:
	reset()
	UiSettings.get_instance().set_value("p0_banner", true, false)
	router.push({"priority": 0, "key": "pb", "body": "Ana está en el suelo", "target": &"world", "seconds": 0.0})
	advance(0.4)
	var on_line := cur() == "pb" and banner.text_now() == "Ana está en el suelo"
	advance(3.2)
	var gone := router.current.is_empty() and router.p0.has("pb")
	UiSettings.get_instance().set_value("p0_banner", false, false)
	router.end_p0("pb")
	check(on_line and gone, "«Banner P0 mínimo» (R29 plan B): the P0 also takes the line for 3 s, and stays in the world")


# ------------------------------------------------------------------ hazards
func _hazards() -> void:
	reset()
	var st := hazard.stack
	st.clear_all()
	Events.hazard_changed.emit(&"blizzard", &"forecast", {"detail": "en ~2 h"})
	var fc := " · ".join(hazard.line_parts())
	# (sounds are counted where the HazardLine raises them: AudioManager's own 0.5 s cooldown on real time would
	# hide a second ui_warn inside this fast test anyway)
	hazard.raised.clear()
	var warns := func() -> int: return hazard.raised.filter(func(r: Array) -> bool: return r[2] == &"ui_warn").size()
	Events.hazard_changed.emit(&"blizzard", &"imminent", {"seconds": 60.0})
	var soon := " · ".join(hazard.line_parts())
	var warn1: bool = warns.call() == 1
	Events.hazard_changed.emit(&"blizzard", &"soon", {"seconds": 59.5})   # the same state again (server + offline)
	var warn_once: bool = warns.call() == 1
	check(fc == "ventisca prevista · en ~2 h" and soon == "ventisca · se acerca · 1:00" and warn1 and warn_once,
		"blizzard: forecast «%s» → imminent «%s» with ui_warn once" % [fc, soon])
	advance(10.0)
	var counting := " · ".join(hazard.line_parts())
	Events.hazard_changed.emit(&"blizzard", &"active", {"seconds": 160.0})
	var act := " · ".join(hazard.line_parts())
	var haz := hazard.raised.filter(func(r: Array) -> bool: return r[2] == &"ui_hazard").size() == 1
	check(counting == "ventisca · se acerca · 0:50" and act == "ventisca · visibilidad 6 m · 2:40" and haz,
		"the countdown runs (0:50 after 10 s) → active «%s» with ui_hazard" % act)
	advance(5.9)
	check(hazard.visible and vis.alpha_of(HazardLine.EL) < 0.01 and hazard.shown_alpha > 0.99, "after 5 s the line shrinks to the icon and the time")
	advance(142.0)
	check(hazard._ending(), "the last 15 s of the countdown pulse")
	Events.hazard_changed.emit(&"blizzard", &"end", {})
	var end_txt := " · ".join(hazard.line_parts())
	advance(4.5)
	check(end_txt == "la ventisca amaina" and hazard.state == &"" and not st.has(&"blizzard"), "end → «la ventisca amaina» for 3 s, then nothing")
	# Gran Ventisca: forecast «en 1 día», active «hoy»; it outranks a plain blizzard
	Events.hazard_changed.emit(&"blizzard", &"forecast", {})
	Events.hazard_changed.emit(&"great_blizzard", &"forecast", {})
	var gf := " · ".join(hazard.line_parts())
	Events.hazard_changed.emit(&"great_blizzard", &"active", {})
	var ga := " · ".join(hazard.line_parts())
	check(gf == "gran ventisca prevista · en 1 día" and ga == "gran ventisca · hoy" and hazard.kind == &"great_blizzard" and st.ordered().size() == 2,
		"Gran Ventisca: «%s» → «%s» (the blizzard forecast is the second, compact entry)" % [gf, ga])
	Events.hazard_changed.emit(&"cold_wave", &"forecast", {})
	hazard.vis.poke(HazardLine.EL)
	advance(0.4)
	check(st.forecasts_beyond(UiTokens.HAZARD_VISIBLE) == 1, "2 entries drawn at most; the rest of the forecasts become «+1 previsto»")
	st.clear_all()


func _hazard_kinds() -> void:
	reset()
	var st := hazard.stack
	st.clear_all()
	var icons_ok := true
	for k: StringName in HazardStack.SPECS:
		if Whisper.icon(HazardStack.icon_of(k)) == null:
			icons_ok = false
	check(HazardStack.SPECS.size() >= 9 and icons_ok and HazardStack.SPECS.has(&"thin_ice") and HazardStack.SPECS.has(&"ice_storm")
		and HazardStack.SPECS.has(&"cold_wave") and HazardStack.SPECS.has(&"avalanche") and HazardStack.SPECS.has(&"blackout") and HazardStack.SPECS.has(&"fire"),
		"API kinds for E1 / E2: thin ice, ice storm, cold wave, avalanche, blackout, fire (+ extreme cold), every icon exists")
	# ordering: active before imminent before forecast
	Events.hazard_changed.emit(&"cold_wave", &"forecast", {})
	Events.hazard_changed.emit(&"ice_storm", &"soon", {"seconds": 30.0})
	Events.hazard_changed.emit(&"fire", &"active", {"detail": "humo y calor"})
	var order := st.ordered().map(func(e: Dictionary) -> String: return String(e["kind"]))
	check(order == ["fire", "ice_storm", "cold_wave"] and hazard.kind == &"fire", "order: active, imminent, forecast (%s)" % [order])
	st.clear_all()
	# thin ice underfoot: a P0 in the world with the ice crack
	var pos := Vector3(3, 0, 4)
	Events.hazard_changed.emit(&"thin_ice", &"active", {"pos": pos})
	var p0: Dictionary = router.p0.get("hazard:thin_ice", {})
	var cracked := played.filter(func(p: Array) -> bool: return p[0] == &"ice_crack").size() == 1
	check(not p0.is_empty() and p0["target"] == &"world" and (p0["pos"] as Vector3) == pos and str(p0["body"]).contains("no corras") and cracked,
		"thin ice underfoot → P0 in the world at its point («%s») with ice_crack" % p0.get("body", "-"))
	var cap: Dictionary = captions.lines[-1] if not captions.lines.is_empty() else {}
	check(str(cap.get("text", "")) == "hielo que cruje", "…and its caption «hielo que cruje»")
	Events.hazard_changed.emit(&"thin_ice", &"end", {})
	check(not router.p0.has("hazard:thin_ice"), "leaving the ice ends the P0")
	# an API hazard whose timer runs out ends by itself
	Events.hazard_changed.emit(&"fire", &"active", {"seconds": 2.0})
	advance(7.5)
	check(st.state_of(&"fire") == &"end" or not st.has(&"fire"), "an API hazard with a timer nobody ended goes away")
	# blackout is a zone hazard: no timer, line only
	var before := played.size()
	Events.hazard_changed.emit(&"blackout", &"active", {})
	check(" · ".join(hazard.line_parts()) == "sin electricidad · calles a oscuras · ascensores parados" and played.size() == before,
		"zone hazard (blackout): no timer, no alarm sound, «%s»" % " · ".join(hazard.line_parts()))
	st.clear_all()
