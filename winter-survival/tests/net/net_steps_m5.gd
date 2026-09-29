extends "res://tests/net/net_steps.gd"
## M5 net scenarios (loaded by tests/net/net_smoke.gd for `--scenario hitscan|restart`):
##   hitscan  (PLAN M5 acceptance, 2 clients, normally behind tests/net/net_sim.gd with --net-sim 150,20,2) B walks back
##            and forth across A's line of fire 10 m away at 2.2 m/s; A (friendly_fire full) fires 15 pistol rounds at the
##            B it sees: the server rewinds B (lag compensation ≤ 200 ms) and at least 60 % of the shots must hit, more
##            than a server without the rewind would have scored (the `[EVT] shot … norewind=` counterfactual); the
##            walk, not the 6 m/s run: A sees B RTT + 100 ms interpolation in the past (≈ 280 ms at --net-sim 150,20,2)
##            and the rewind is capped at 200 ms by the spec, so a runner is 0.5 m off (> the 0.4 m hit radius); the
##            16th trigger pull with an empty magazine is refused ("sin_municion"); B's health drops (it /heal-s itself).
##   restart  (PLAN M5 + v3.8.4 acceptance, 1 client, two phases around a server restart: tests/net/run_restart_test.sh)
##            phase 1: fell a pine, place a campfire, loot the campsite container of camp_1, load and fire a pistol,
##            walk to the SE quadrant (x, z > 3000, the 96² world of W1) and place a second campfire there; the facts
##            go to user://m5_restart_phase1.json and the client disconnects. phase 2 (after save-and-quit and a new
##            server process): the player is back in the SE quadrant with the same inventory (the pistol keeps 10
##            rounds in its magazine), both campfires exist, the pine is still felled and the looted container is
##            still empty (no re-roll).

const FACTS := "user://m5_restart_phase1.json"
const SE_POS := Vector3(3500.0, 0.0, 3600.0)

var phase: int = 1
var _gun: FirearmClient
var _shots: int = 0
var _ok_shots: int = 0
var _hits_b: int = 0
var _dry_refused: bool = false
var _min_health: float = 100.0
var _facts: Dictionary = {}
var _checks: Dictionary = {}


func _run_client() -> void:
	phase = int(opts.get("phase", 1))
	super._run_client()
	Events.fire_result.connect(func(_q: int, ok: bool, reason: String, _h: int, _k: int, _c: bool) -> void:
		if ok:
			_ok_shots += 1
		elif reason == "sin_municion":
			_dry_refused = true)
	Events.hit_result.connect(func(v: int, blocked: bool, _r: String) -> void:
		var b := _player_named(tree.get_first_node_in_group("world"), "B") if tree.get_first_node_in_group("world") != null else null
		if not blocked and b != null and v == b.peer_id:
			_hits_b += 1)
	Events.stat_changed.connect(func(stat: StringName, value: float, _m: float) -> void:
		if stat == &"health":
			_min_health = minf(_min_health, value))
	if scenario == "hitscan":
		_build_hitscan_timeline()
	elif scenario == "restart":
		_build_restart_timeline()


func _firearm(lp: Player) -> FirearmClient:
	if _gun == null or not is_instance_valid(_gun):
		_gun = lp.get_node_or_null("Firearm") as FirearmClient
	return _gun


# ------------------------------------------------------------------ hitscan
const LANE := 10.0     # B walks 10 m from A
const HALF := 4.5      # ± along x


func _extra_move(ct: float, mv: Vector2) -> Vector2:
	if scenario == "hitscan" and client_name == "B" and ct > 5.5 and ct < 20.0:
		var leg := int(floor((ct - 5.5) / 1.5))
		return Vector2(1.0 if leg % 2 == 0 else -1.0, 0.0)
	return mv


func _extra_run(ct: float, run: bool) -> bool:
	if scenario == "hitscan" and client_name == "B" and ct > 5.5 and ct < 20.0:
		return false   # walk (see the header: the 200 ms rewind cap cannot cover a runner at RTT 150 ms + interpolation)
	return run


func _build_hitscan_timeline() -> void:
	var tl := []
	if client_name == "A":
		tl = [
			[1.0, func(_lp: Player, _w: Node) -> void: Chat.instance.send("/rule friendly_fire full")],
			# chat is rate limited to 2 lines per second: with 2 % loss a retransmitted reliable packet can bunch lines
			# up at the server, so every command is checked and sent again once
			[1.7, func(_lp: Player, w: Node) -> void: _tp((w as World).get_spawn_point() + Vector3(0, 0, 3.0))],
			[2.5, func(_lp: Player, _w: Node) -> void: Chat.instance.send("/give pistola 1")],
			[3.3, func(_lp: Player, _w: Node) -> void: Chat.instance.send("/give municion_9mm 15")],
			[4.2, func(lp: Player, _w: Node) -> void:
				if lp.state.count(&"pistola") == 0 and lp.state.hand_tool() != &"pistola":
					Chat.instance.send("/give pistola 1")],
			[5.0, func(lp: Player, _w: Node) -> void:
				if lp.state.count(&"municion_9mm") < 15 and int(lp.state.gun_view.get("ammo", 0)) <= 0:
					Chat.instance.send("/give municion_9mm 15")],
			[5.6, func(lp: Player, _w: Node) -> void: _equip_item(lp, &"pistola")],
			[6.2, func(lp: Player, _w: Node) -> void:
				if lp.state.hand_tool() != &"pistola":
					_equip_item(lp, &"pistola")
				Net.rpc_server(NetWorld.instance, &"request_reload", [])],
		]
		for k in 16:
			tl.append([8.0 + 0.6 * k, func(lp: Player, w: Node) -> void:
				var b := _player_named(w, "B")
				var g := _firearm(lp)
				if b == null or g == null:
					return
				g.aim_point = b.global_position + Vector3(0, 1.1, 0)
				g.aim_zombie = 0
				g.ws.last_shot = -100.0   # the harness paces the shots (0.6 s > the 0.25 s cadence)
				_shots += 1
				g.fire()])
		tl.append([19.0, func(lp: Player, _w: Node) -> void:
			var ok_n := mini(_ok_shots, 15)
			_sw["shots"] = ok_n >= 13
			_sw["hits"] = ok_n > 0 and float(_hits_b) / float(ok_n) >= 0.6
			_sw["dry"] = _dry_refused
			_log("hitscan: %d trigger pulls, %d fired, %d hits on B (%.0f %%), dry refused=%s, gun mirror=%s, rtt=%.0f ms" % [_shots, _ok_shots,
				_hits_b, 100.0 * float(_hits_b) / maxf(float(ok_n), 1.0), _dry_refused, lp.state.gun_view, float(Net.stats["rtt"])])])
	else:
		tl = [
			[1.0, func(_lp: Player, w: Node) -> void:
				_tp((w as World).get_spawn_point() + Vector3(-HALF, 0, 3.0 + LANE))],
		]
		for k in 14:
			tl.append([4.0 + 1.2 * k, func(_lp: Player, _w: Node) -> void: Chat.instance.send("/heal")])
		tl.append([19.0, func(lp: Player, _w: Node) -> void:
			_sw["hit_taken"] = _min_health < 99.0
			_log("B: min health %.0f, now %.0f at %s" % [_min_health, lp.state.health, lp.global_position.snapped(Vector3(0.1, 0.1, 0.1))])])
	tl.sort_custom(func(a, b) -> bool: return float(a[0]) < float(b[0]))
	_timeline = tl


# ------------------------------------------------------------------ restart
func _nearest_loot(pos: Vector3) -> LootContainer:
	var best: LootContainer = null
	var bd := 12.0
	for n in tree.get_nodes_in_group("loot_container"):
		var lc := n as LootContainer
		if lc == null or lc.loose:
			continue
		var d := lc.global_position.distance_to(pos)
		if d < bd:
			bd = d
			best = lc
	return best


func _camp_center() -> Vector3:
	for pad in PoiRegistry.PADS:
		if str(pad["id"]) == "camp_1":
			var c: Vector2 = pad["center"]
			return Vector3(c.x, 0.0, c.y)
	return Vector3(150, 0, 60)


func _campfire_near(pos: Vector3, r: float) -> bool:
	for c in tree.get_nodes_in_group("campfire"):
		var cp := (c as Node3D).global_position
		if c.get_parent() != null and c.get_parent().name == "Placed" and Vector2(cp.x - pos.x, cp.z - pos.z).length() < r:
			return true
	return false


func _wid(key: String) -> int:
	return str(_facts.get(key, "0")).hex_to_int()


func _storage_items(st: Storage) -> Array:
	var out := []
	for sl in st.slots:
		if not sl.is_empty():
			out.append("%s×%d" % [sl["id"], int(sl["count"])])
	out.sort()
	return out


func _place_campfire_near(lp: Player, world: Node) -> Vector3:
	for cand in [Vector3(0, 0, 3.0), Vector3(2.5, 0, 2.5), Vector3(-2.5, 0, 2.5), Vector3(0, 0, -3.0), Vector3(3.0, 0, 0), Vector3(-3.0, 0, 0)]:
		var c: Vector3 = lp.global_position + cand
		c.y = world.get_height(c.x, c.z)
		if PlacementController.check_position(lp, c):
			Net.rpc_server(NetWorld.instance, &"request_place", ["campfire", c, 0.0])
			return c
	return Vector3.INF


func _build_restart_timeline() -> void:
	var tl := []
	if phase == 1:
		tl = [
			[1.0, func(_lp: Player, world: Node) -> void:
				_pick_target_tree(world)
				Chat.instance.send("/kit")],
			[2.0, func(_lp: Player, _w: Node) -> void:
				var toward := (Vector3.ZERO - _target_tree_pos)
				toward.y = 0.0
				_tp(_target_tree_pos + toward.normalized() * 1.5)],
			[4.0, func(_lp: Player, _w: Node) -> void: _chop()],
			[4.7, func(_lp: Player, _w: Node) -> void: _chop()],
			[5.4, func(_lp: Player, _w: Node) -> void: _chop()],
			[6.1, func(_lp: Player, _w: Node) -> void: _chop()],
			[7.5, func(_lp: Player, _w: Node) -> void:
				_checks["felled"] = bool(NetWorld.instance.delta_of(_target_tree_wid).get("felled", false))
				_facts["tree_wid"] = "%x" % _target_tree_wid   # hex: JSON numbers are doubles (53-bit), wids are 64-bit
				_facts["tree_pos"] = [_target_tree_pos.x, _target_tree_pos.z, _target_tree_pos.y]
				_tp((tree.get_first_node_in_group("world") as World).get_spawn_point() + Vector3(2.5, 0, 3.0))],
			[9.0, func(lp: Player, world: Node) -> void:
				var c := _place_campfire_near(lp, world)
				_facts["fire1"] = [c.x, c.z] if c != Vector3.INF else []],
			[10.5, func(_lp: Player, _w: Node) -> void:
				_checks["fire1"] = not (_facts["fire1"] as Array).is_empty() and _campfire_near(Vector3(_facts["fire1"][0], 0, _facts["fire1"][1]), 1.0)
				var c := _camp_center()
				_tp(c + Vector3(3.0, 0, 3.0))],
			[12.5, func(lp: Player, _w: Node) -> void:
				var lc := _nearest_loot(lp.global_position)
				if lc != null:
					_facts["loot_wid"] = "%x" % WorldRegistry.wid_of(lc)
					var front := lc.global_position + lc.global_basis.z * 1.0
					_tp(front)],
			[14.0, func(lp: Player, _w: Node) -> void:
				var lc := WorldRegistry.get_object(_wid("loot_wid")) as LootContainer
				if lc != null:
					lp.interactor.send_interact(lc.interactable, &"open")],
			[15.5, func(_lp: Player, _w: Node) -> void:
				var lc := WorldRegistry.get_object(_wid("loot_wid")) as LootContainer
				if lc == null:
					return
				_facts["loot_rolled"] = _storage_items(lc.storage)
				_checks["loot_open"] = lc.storage.is_open
				for i in lc.storage.slots.size():
					if not lc.storage.slots[i].is_empty():
						Net.rpc_server(NetWorld.instance, &"request_take", [_wid("loot_wid"), i, true])],
			[17.0, func(_lp: Player, _w: Node) -> void:
				var lc := WorldRegistry.get_object(_wid("loot_wid")) as LootContainer
				if lc != null:
					_facts["loot_left"] = _storage_items(lc.storage)
					Net.rpc_server(NetWorld.instance, &"request_close_storage", [_wid("loot_wid")])],
			[17.8, func(_lp: Player, _w: Node) -> void: Chat.instance.send("/give pistola 1")],
			[18.6, func(_lp: Player, _w: Node) -> void: Chat.instance.send("/give municion_9mm 12")],
			[19.4, func(lp: Player, _w: Node) -> void: _equip_item(lp, &"pistola")],
			[20.0, func(_lp: Player, _w: Node) -> void: Net.rpc_server(NetWorld.instance, &"request_reload", [])],
			[22.5, func(lp: Player, _w: Node) -> void:
				var g := _firearm(lp)
				if g != null:
					g.aim_point = lp.global_position + lp.facing() * 8.0
					g.fire()],
			[23.2, func(lp: Player, _w: Node) -> void:
				var g := _firearm(lp)
				if g != null:
					g.aim_point = lp.global_position + lp.facing() * 8.0
					g.fire()],
			[24.0, func(lp: Player, _w: Node) -> void:
				_facts["ammo"] = int(lp.state.gun_view.get("ammo", -1))
				_checks["ammo"] = int(_facts["ammo"]) == 10
				_tp(SE_POS)],
			[24.8, func(_lp: Player, _w: Node) -> void: Chat.instance.send("/give madera 3")],
			[25.6, func(_lp: Player, _w: Node) -> void: Chat.instance.send("/give piedra 4")],
			[27.0, func(lp: Player, world: Node) -> void:
				var c := _place_campfire_near(lp, world)
				_facts["fire2"] = [c.x, c.z] if c != Vector3.INF else []],
			[29.0, func(lp: Player, _w: Node) -> void:
				_checks["se_quadrant"] = lp.global_position.x > 3000.0 and lp.global_position.z > 3000.0
				_checks["fire2"] = not (_facts["fire2"] as Array).is_empty() and _campfire_near(Vector3(_facts["fire2"][0], 0, _facts["fire2"][1]), 1.0)
				_facts["pos"] = [lp.global_position.x, lp.global_position.y, lp.global_position.z]
				var inv := {}
				for sl in lp.state.slots:
					if not sl.is_empty():
						inv[String(sl["id"])] = int(inv.get(String(sl["id"]), 0)) + int(sl["count"])
				_facts["inventory"] = inv
				var f := FileAccess.open(FACTS, FileAccess.WRITE)
				f.store_string(JSON.stringify(_facts))
				f.close()
				_log("PHASE1 facts %s checks %s" % [JSON.stringify(_facts), _checks])],
		]
	else:
		tl = [
			[1.5, func(lp: Player, _w: Node) -> void:
				var raw := FileAccess.get_file_as_string(FACTS)
				var v: Variant = JSON.parse_string(raw)
				_facts = v if v is Dictionary else {}
				var pos: Array = _facts.get("pos", [0, 0, 0])
				var saved := Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
				_checks["position"] = lp.global_position.distance_to(saved) < 1.5 and lp.global_position.x > 3000.0 and lp.global_position.z > 3000.0
				var inv := {}
				for sl in lp.state.slots:
					if not sl.is_empty():
						inv[String(sl["id"])] = int(inv.get(String(sl["id"]), 0)) + int(sl["count"])
				var want: Dictionary = _facts.get("inventory", {})
				var same := not want.is_empty()
				for k in want:
					if int(inv.get(k, 0)) != int(want[k]):
						same = false
				_checks["inventory"] = same
				_checks["ammo"] = lp.state.hand_tool() == &"pistola" and int(lp.state.gun_view.get("ammo", -1)) == int(_facts.get("ammo", -2))
				_log("PHASE2 at %s (saved %s) inventory %s (saved %s) hand %s ammo %s" % [lp.global_position.snapped(Vector3(0.1, 0.1, 0.1)),
					saved.snapped(Vector3(0.1, 0.1, 0.1)), inv, want, lp.state.hand_tool(), lp.state.gun_view.get("ammo", -1)])],
			[3.0, func(_lp: Player, _w: Node) -> void:
				var f2: Array = _facts.get("fire2", [])
				_checks["fire2"] = not f2.is_empty() and _campfire_near(Vector3(float(f2[0]), 0, float(f2[1])), 1.0)
				_tp((tree.get_first_node_in_group("world") as World).get_spawn_point() + Vector3(2.5, 0, 3.0))],
			[7.0, func(lp: Player, world: Node) -> void:
				var f1: Array = _facts.get("fire1", [])
				_checks["fire1"] = not f1.is_empty() and _campfire_near(Vector3(float(f1[0]), 0, float(f1[1])), 1.0)
				var tw := _wid("tree_wid")
				var tp: Array = _facts.get("tree_pos", [0, 0])
				var delta := NetWorld.instance.delta_of(tw)
				var stump := _stump_near(world, Vector3(float(tp[0]), float(tp[2]) if tp.size() > 2 else 0.0, float(tp[1])))
				_checks["felled"] = tw != 0 and bool(delta.get("felled", false)) and stump
				_log("PHASE2 at spawn %s: campfire at %s %s, tree %x delta %s stump %s (campfires %s)" % [lp.global_position.snapped(Vector3(0.1, 0.1, 0.1)),
					f1, _checks["fire1"], tw, delta, stump, tree.get_nodes_in_group("campfire").map(func(n: Node) -> String:
						return "%s/%s@%s" % [n.get_parent().name, n.name, (n as Node3D).global_position.snapped(Vector3(0.1, 0.1, 0.1))])])
				_tp(_camp_center() + Vector3(3.0, 0, 3.0))],
			[9.0, func(_lp: Player, _w: Node) -> void:
				var lc := WorldRegistry.get_object(_wid("loot_wid")) as LootContainer
				if lc != null:
					_tp(lc.global_position + lc.global_basis.z * 1.0)],
			[10.5, func(lp: Player, _w: Node) -> void:
				var lc := WorldRegistry.get_object(_wid("loot_wid")) as LootContainer
				if lc != null:
					lp.interactor.send_interact(lc.interactable, &"open")],
			[12.0, func(_lp: Player, _w: Node) -> void:
				var lc := WorldRegistry.get_object(_wid("loot_wid")) as LootContainer
				var now_items := _storage_items(lc.storage) if lc != null else ["?"]
				_checks["loot_kept"] = lc != null and lc.storage.is_open and now_items == (_facts.get("loot_left", ["?"]) as Array)
				_log("PHASE2 container %x now %s (left in phase 1: %s, rolled then: %s)" % [_wid("loot_wid"), now_items,
					_facts.get("loot_left"), _facts.get("loot_rolled")])
				if lc != null:
					Net.rpc_server(NetWorld.instance, &"request_close_storage", [_wid("loot_wid")])],
		]
	tl.sort_custom(func(a, b) -> bool: return float(a[0]) < float(b[0]))
	_timeline = tl


# ------------------------------------------------------------------ result
func _finish(lp: Player) -> void:
	tree.process_frame.disconnect(_client_frame)
	var bw_avg := 0.0
	for v in _bw_samples:
		bw_avg += v
	bw_avg /= maxf(float(_bw_samples.size()), 1.0)
	var keys: Array = []
	var bag: Dictionary = _sw
	if scenario == "hitscan":
		keys = ["shots", "hits", "dry"] if client_name == "A" else ["hit_taken"]
	else:
		bag = _checks
		keys = ["felled", "fire1", "loot_open", "ammo", "se_quadrant", "fire2"] if phase == 1 else ["position", "inventory", "ammo", "fire2", "fire1", "felled", "loot_kept"]
	var ok := _local_seen and lp != null
	for k in keys:
		if not bool(bag.get(k, false)):
			ok = false
	_log("RESULT %s name=%s scenario=%s phase=%d checks=%s down_kbps_avg=%.2f rtt_max=%.0f" % ["OK" if ok else "FAIL", client_name, scenario,
		phase, bag, bw_avg, _rtt_max])
	tree.quit(0 if ok else 1)
