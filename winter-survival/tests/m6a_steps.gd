extends RefCounted
## Body of tests/m6a_checks.gd (M6a, headless). See the runner for the scope.

const MIN_CHECKS := 60
const SEED := 20260927

var tree: SceneTree
var root: Node3D
var cam: Camera3D
var _checks := 0
var _failed := 0


func check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("  ok   ", msg)
	else:
		_failed += 1
		print("FAIL: ", msg)


func run(p_tree: SceneTree) -> void:
	tree = p_tree
	await tree.process_frame
	print("== VENTISCA M6a checks (kit street, CutawayManager, doors, signs)")
	root = Node3D.new()
	root.name = "M6aChecks"
	tree.root.add_child(root)
	cam = Camera3D.new()
	root.add_child(cam)
	cam.current = true
	KitBuilding.render_override = 1        # CityBuilding + cutaway even headless
	var st := await _street()
	if st != null:
		await _buildings(st)
		await _cutaway(st)
		await _doors(st)
		st.queue_free()
		await _frames(2)
		await _determinism()
	_signs()
	await _pois()
	await _headless_rule()
	KitBuilding.render_override = -1
	if _checks < MIN_CHECKS:
		_failed += 1
		print("FAIL: only %d of %d checks ran (a script error above cut a section short)" % [_checks, MIN_CHECKS])
	print("== m6a checks: %d checks, %d failed" % [_checks, _failed])
	tree.quit(0 if _failed == 0 else 1)


func _frames(n: int) -> void:
	for i in n:
		await tree.process_frame


func _make_street(parent: Node3D, pos: Vector3) -> KitStreet:
	var data := KitStreets.by_id("calle_mayor")
	if data.is_empty():
		return null
	var st := KitStreet.new()
	st.setup(data, SEED, 0.0)
	st.position = pos
	parent.add_child(st)
	st.build_all()
	return st


func _street() -> KitStreet:
	var data := KitStreets.by_id("calle_mayor")
	check(not data.is_empty(), "data/buildings/streets/calle_mayor.json loads (KitStreets.load_all)")
	if data.is_empty():
		return null
	var c := KitStreets.centre_of(data)
	var pad: Dictionary = {}
	for p in PoiRegistry.PADS:
		if str(p["id"]) == str(data.get("pad", "")):
			pad = p
	check(not pad.is_empty() and bool(pad.get("reserved", false)) and Vector2(c.x, c.z).distance_to(pad["center"]) < 1.0,
		"the street sits on the W1 reserved pad %s (flat, scatter-free: no terrain change)" % data.get("pad"))
	var st := _make_street(root, Vector3.ZERO)
	await _frames(3)
	check(st.done and st.buildings.size() == (data["lots"] as Array).size() and st.signs.size() == (data["signs"] as Array).size(),
		"KitStreet built %d buildings and %d street signs" % [st.buildings.size(), st.signs.size()])
	return st


func _buildings(st: KitStreet) -> void:
	for b in st.buildings:
		var tpl_path := "res://data/buildings/templates/%s.json" % b.template_id
		var tpl: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(tpl_path)) if FileAccess.file_exists(tpl_path) else {}
		var m := b.model
		var tag := "%s/%s" % [b.style, b.template_id]
		check(m != null and not Assets.is_placeholder(m), "%s: the kit .glb loaded (not a placeholder)" % tag)
		if m == null:
			continue
		check(int(m.get_meta("floors", 0)) == int(tpl.get("floors", -1)) and is_equal_approx(float(m.get_meta("ground_h", 0.0)), 3.3)
			and is_equal_approx(float(m.get_meta("floor_h", 0.0)), 3.0) and bool(m.get_meta("enterable", false)),
			"%s: city-building root metadata from the ShadowProxy (floors %s, ground_h 3.3, floor_h 3.0, enterable)" % [tag, m.get_meta("floors", "?")])
		var proxy := m.get_node_or_null("ShadowProxy") as GeometryInstance3D
		check(proxy != null and proxy.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY and b.city != null and b.city.has_proxy,
			"%s: ShadowProxy is the only caster (SHADOWS_ONLY), CityBuilding attached" % tag)
		var leaves := 0
		var panes := 0
		for c in m.get_children():
			if String(c.name).begins_with("Door_"):
				leaves += 1
			elif String(c.name).begins_with("Window_"):
				panes += 1
		var boxes := m.get_node_or_null("WindowBoxes")
		check(b.doors.size() == leaves and leaves > 0 and boxes != null and boxes.get_child_count() == panes,
			"%s: %d KitDoor for %d leaves, %d window boxes for %d panes" % [tag, b.doors.size(), leaves, boxes.get_child_count() if boxes else 0, panes])
		var ok_parent := true
		var n := 0
		for k in b.floors:
			var interior := m.get_node_or_null("Interior%d" % k)
			if interior == null:
				ok_parent = false
				continue
			for c in interior.get_children():
				if c is LootContainer:
					n += 1
		check(ok_parent and n == b.containers and n > 0, "%s: %d loot containers, each under the Interior<k> of its storey" % [tag, n])
		check(b.city.cutaway != null and b.city.cutaway.managed, "%s: its BuildingCutaway is managed by the CutawayManager" % tag)
	var shop: KitBuilding = null
	for b in st.buildings:
		if b.template_id == "shop_general":
			shop = b
	var shop_text := _find_text(shop.model, "Sign_sign_shop") if shop != null else null
	check(shop_text != null and shop_text.mesh.get_surface_count() == 1 and shop_text.get_aabb().size.x <= 2.31,
		"shop fascia: '%s' composed from the mesh font, %.2f m wide (board text width 2.30)" % [shop.shop_name if shop else "?", shop_text.get_aabb().size.x if shop_text else -1.0])
	var numbers := 0
	for b in st.buildings:
		if _find_text(b.model, "Sign_sign_house_number") != null:
			numbers += 1
	check(numbers == st.buildings.size(), "every building shows its house number (%d / %d)" % [numbers, st.buildings.size()])
	await _frames(1)


func _find_text(n: Node, board: String) -> MeshInstance3D:
	for s in n.find_children(board, "Node3D", true, false):
		var t := s.get_node_or_null("Text_0") as MeshInstance3D
		if t != null:
			return t
	return null


func _lot(st: KitStreet, template: String, style: String) -> KitBuilding:
	for b in st.buildings:
		if b.template_id == template and b.style == style:
			return b
	return null


func _place_camera(target: Vector3) -> void:
	cam.global_position = target + Vector3(11.3, 17.8, 11.3)
	cam.look_at(target, Vector3.UP)


func _cutaway(st: KitStreet) -> void:
	var mgr := CutawayManager.instance
	check(mgr != null and mgr.count() >= st.buildings.size(), "CutawayManager created on demand, %d buildings registered" % (mgr.count() if mgr else 0))
	if mgr == null:
		return
	var pl := Node3D.new()
	pl.name = "Player"
	root.add_child(pl)
	mgr.player_override = pl
	var h := _lot(st, "house_two_story_A", "wood_blue")
	var m := h.model
	var feet0 := h.global_transform * Vector3(-1.0, 0.32, -1.0)
	_place_camera(feet0)
	pl.global_position = feet0
	mgr.update()
	check(mgr.inside and mgr.inside_floor == 0 and mgr.is_inside(m), "inside the 2-storey house, storey 0 (inside = %s, floor %d)" % [mgr.inside, mgr.inside_floor])
	var roof := m.get_node("Roof") as GeometryInstance3D
	var proxy := m.get_node("ShadowProxy") as GeometryInstance3D
	check(not roof.visible and proxy.visible and proxy.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY,
		"storey 0: the roof is hidden and the ShadowProxy keeps casting (the room stays in the roof's shadow)")
	var hidden_up := true
	for n in ["Floor1", "Interior1", "Walls1_S", "Walls1_N", "Walls1_E", "Walls1_W"]:
		for gi in BuildingCutaway._geometries(m.get_node(n)):
			if gi.is_visible_in_tree() and gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
				hidden_up = false
	check(hidden_up, "storey 0: storey 1 (slab, interior, walls, its containers) is hidden")
	var up_door_hidden := true
	for c in m.get_children():
		if String(c.name).begins_with("Door_") and int((c.get_meta("extras", {}) as Dictionary).get("floor", 0)) == 1 and (c as Node3D).visible:
			up_door_hidden = false
	check(up_door_hidden, "storey 0: the interior doors of storey 1 go with their storey")
	check(not (m.get_node("Walls0_S") as Node3D).visible and (m.get_node("Walls0_S_Stub") as Node3D).visible
		and not (m.get_node("Walls0_E") as Node3D).visible and (m.get_node("Walls0_N") as Node3D).visible
		and (m.get_node("Walls0_W") as Node3D).visible and not (m.get_node("Walls0_N_Stub") as Node3D).visible,
		"storey 0: the camera-facing S and E facades become their stubs, N and W stay")
	var feet1 := h.global_transform * Vector3(-1.0, 3.32, -1.0)
	pl.global_position = feet1
	mgr.update()
	check(mgr.inside_floor == 1 and (m.get_node("Floor1") as Node3D).visible and not roof.visible
		and (m.get_node("Walls1_S_Stub") as Node3D).visible and (m.get_node("Walls0_S") as Node3D).visible,
		"storey 1: its slab shows, roof hidden, S facade of storey 1 stubbed, storey 0 whole")
	pl.global_position = h.global_transform * Vector3(0.0, 0.0, 14.0)
	mgr.update()
	check(not mgr.inside and roof.visible and (m.get_node("Walls0_S") as Node3D).visible and not (m.get_node("Walls0_S_Stub") as Node3D).visible
		and (m.get_node("Floor1") as Node3D).visible, "outside: everything back, stubs hidden")
	# a south-side house (yaw 180): its N facade faces the camera
	var s3 := _lot(st, "house_small_A", "brick")
	var f := s3.global_transform * Vector3(1.0, 0.32, -1.0)
	_place_camera(f)
	pl.global_position = f
	mgr.update()
	check(mgr.is_inside(s3.model) and not (s3.model.get_node("Walls0_N") as Node3D).visible and (s3.model.get_node("Walls0_S") as Node3D).visible,
		"south side (yaw 180): the camera-facing facade is its N wall")
	var apt := _lot(st, "apartment_small", "concrete")
	var f2 := apt.global_transform * Vector3(-2.0, 6.32, -2.0)
	_place_camera(f2)
	pl.global_position = f2
	mgr.update()
	check(mgr.is_inside(apt.model) and mgr.inside_floor == 2 and (apt.model.get_node("Floor2") as Node3D).visible,
		"apartment: storey 2 of 3 detected")
	var events := [0]
	var cb := func(_v: bool) -> void: events[0] += 1
	Events.shelter_changed.connect(cb)
	pl.global_position = Vector3(0, 0, 0)
	mgr.update()
	Events.shelter_changed.disconnect(cb)
	check(not mgr.inside and events[0] == 1, "leaving emits Events.shelter_changed(false) once")
	await _frames(1)


func _doors(st: KitStreet) -> void:
	var h := _lot(st, "house_two_story_A", "wood_blue")
	var door: KitDoor = null
	for d in h.doors:
		if d.exterior and (d.leaf.get_meta("extras", {}) as Dictionary).get("cut_group", "") == "Walls0_S":
			door = d
	check(door != null, "the front door (S facade) has a KitDoor")
	if door == null:
		return
	var cs := door.get_node("Box") as CollisionShape3D
	var closed_c := h.global_transform.affine_inverse() * cs.global_position
	check(absf(door.leaf.position.y) < 0.001 and door.get_meta("wid") == KitDoor.wid_for(SEED, int(h.get_meta("wid")), 0),
		"door leaf pivot at the building base (no Y offset), wid = hash64(seed, DOOR, building, index)")
	var s := door._swing_for(null)
	door.apply_net_delta({"open": true, "swing": s}, false)
	var open_c := h.global_transform.affine_inverse() * cs.global_position
	var out := door.outward
	check(door.is_open and absf(absf(door.leaf.rotation.y) - deg_to_rad(KitDoor.OPEN_DEG)) < 0.01 and open_c.dot(out) < closed_c.dot(out) - 0.3,
		"open (from a delta): leaf turned %.0f deg and its box swung INTO the house (%.2f -> %.2f along the facade normal)" % [rad_to_deg(door.leaf.rotation.y), closed_c.dot(out), open_c.dot(out)])
	door.apply_net_delta({"open": false}, true)
	for i in 30:
		door._process(1.0 / 60.0)
	check(not door.is_open and absf(door.leaf.rotation.y) < 0.001, "close (live event): animates back to 0 in %.2f s" % KitDoor.SWING_SECONDS)
	check(door.interact_actions().has(&"use") and door.get_interact_label(null) == "Abrir puerta" and door.interactable != null
		and door.interactable.default_action == &"use", "KitDoor interactable: default action `use` toggles, label «Abrir puerta»")
	await _frames(1)


func _determinism() -> void:
	var a: Array = []
	for i in 2:
		var other := Node3D.new()
		root.add_child(other)
		var st2 := _make_street(other, Vector3(0, 0, 400 * (i + 1)))
		await _frames(1)
		if i == 0:
			a = _wids(st2)
		else:
			var b := _wids(st2)
			check(a.size() > 30 and a == b, "a second build of the street gives the same %d wids (buildings, doors, containers)" % a.size())
		other.queue_free()
		await _frames(2)


func _wids(st: KitStreet) -> Array:
	var out := []
	for b in st.buildings:
		out.append(int(b.get_meta("wid")))
		for d in b.doors:
			out.append(int(d.get_meta("wid")))
		for c in b.find_children("*", "LootContainer", true, false):
			out.append(int(c.get_meta("wid")))
	return out


func _signs() -> void:
	var data := KitStreets.by_id("calle_mayor")
	var texts := ["CALLE MAYOR", "SANTA MARÍA\nDEL PUERTO", "ULTRAMARINOS", "0123456789"]
	var missing := []
	for t in texts:
		for ch in (t as String).replace("\n", "").replace(" ", ""):
			if not SignText.has_glyph(ch):
				missing.append(ch)
	check(missing.is_empty(), "mesh font covers the street texts (missing %s)" % [missing])
	var m := SignText.build("Calle Mayor", 0.40, Color.WHITE, 2.36)
	check(m.get_surface_count() == 1 and m.get_aabb().size.x <= 2.37 and absf(m.get_aabb().size.y - 0.40) < 0.02,
		"«CALLE MAYOR» on the street plate: cap 0.40 m (>= 0.30, doc 10 §7.4), %.2f m wide" % m.get_aabb().size.x)
	var two := SignText.build("Santa María\ndel Puerto", 0.45, Color.BLACK, 3.3)
	check(two.get_aabb().size.y > 0.9 and two.get_aabb().size.x <= 3.31, "two-line road sign, cap 0.45 m, fits the 3.3 m panel")
	check(SignText.build("Calle Mayor", 0.40, Color.WHITE, 2.36) == m, "text meshes are cached (one ArrayMesh per text)")


func _pois() -> void:
	for spec in [["cabin_small", Vector3(0, 0.5, 0), 0], ["lookout_tower", Vector3(0, 9.5, 0), 1]]:
		var host := Node3D.new()
		host.position = Vector3(-300, 0, -300)
		root.add_child(host)
		var model := Assets.spawn_model(str(spec[0]))
		host.add_child(model)
		var cut := CutawayManager.attach(host, model)
		await _frames(1)
		check(cut != null and cut.managed and cut.hide_mode == BuildingCutaway.HideMode.SHADOW, "%s: attached through the CutawayManager (managed, shadow mode)" % spec[0])
		var mgr := CutawayManager.instance
		var pl := mgr.player_override
		_place_camera(host.global_position)
		pl.global_position = host.global_position + (spec[1] as Vector3)
		mgr.update()
		var roof := model.get_node("Roof") as GeometryInstance3D
		check(mgr.inside_floor == int(spec[2]) and roof.visible and roof.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY,
			"%s: inside storey %d the roof goes SHADOWS_ONLY (was visible = false with PoiCutaway: the room lit by the sun)" % [spec[0], spec[2]])
		pl.global_position = host.global_position + Vector3(14, 0, 14)
		mgr.update()
		check(not mgr.inside and roof.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "%s: outside the roof casts and draws again" % spec[0])
		host.queue_free()
		await _frames(1)


func _headless_rule() -> void:
	KitBuilding.render_override = 0
	var b := KitBuilding.new()
	b.setup("house_small_B", "wood_blue", 77, SEED, 9)
	root.add_child(b)
	await _frames(1)
	var stubs_hidden := true
	for c in b.model.get_children():
		if String(c.name).ends_with("_Stub") and (c as Node3D).visible:
			stubs_hidden = false
	check(b.city == null and stubs_hidden and b.doors.size() == 2, "headless (server / tools): no CityBuilding, stubs hidden, doors and loot still built")
	b.queue_free()
	await _frames(1)
