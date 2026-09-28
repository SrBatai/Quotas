extends RefCounted
## S1 part of the smoke test (step 20, called by tests/smoke_steps.gd after H2): the audio in the running game.
##   listener   an AudioListener3D at the local player's head, turned with the camera's yaw;
##   gunfire    the local predicted shot (Events.local_shot) plays a 3D voice at the pistol's muzzle + its tail; another
##              player's replicated shot 30 m away (Events.shot_fired) plays close + distant layers and its impacts;
##   loops      the lit cabin stove has its loop; start_loop / stop_loop on a world node;
##   director   the city bed in Altavega, the forest bed in a valley forest, the interior bed inside;
##   budget     50 zombies around the player: never more than 6 zombie vocalisations at once, and they do groan;
##   footsteps  a step resolves its surface under the player.
## No SCRIPT ERROR on the way (run_smoke.sh greps them).

var s: RefCounted   # tests/smoke_steps.gd (check / frames / seconds)
var tree: SceneTree


func run(p_smoke: RefCounted, p_tree: SceneTree, game: Node, world: World, player: Player) -> void:
	s = p_smoke
	tree = p_tree
	print("-- S1: audio (listener, gunfire, loops, ambience director, zombie voice budget)")
	var am := AudioManager
	await s.frames(2)
	var head := player.global_position + Vector3(0, AudioManager.LISTENER_HEIGHT, 0)
	var cam := tree.root.get_viewport().get_camera_3d()
	var right_ok := true
	if cam != null:
		var cr := cam.global_basis.x
		cr.y = 0.0
		right_ok = cr.length() < 0.01 or am.listener.global_basis.x.dot(cr.normalized()) > 0.95
	s.check(am.enabled and am.listener.is_current() and am.listener.global_position.distance_to(head) < 0.6 and right_ok,
		"listener: current, at the local player's head (%.2f m off), right ear = the camera's right" % am.listener.global_position.distance_to(head))
	# --- gunfire: the owner's predicted shot → a 3D voice at the muzzle
	var fx := FirearmFx.instance
	var muzzle := fx._muzzle_of(player) if fx != null else player.global_position
	Events.local_shot.emit(&"pistola", 1.0)
	await s.frames(1)
	var v := instance_from_id(int(am.last_voice.get(&"gun_pistol:close", -1))) as AudioStreamPlayer3D
	s.check(fx != null and v != null and am.voice_active(v.get_instance_id()) and v.bus == &"Weapons" and v.global_position.distance_to(muzzle) < 0.3,
		"local pistol shot: a 3D voice on the Weapons bus at the muzzle (%.2f m)" % (v.global_position.distance_to(muzzle) if v != null else -1.0))
	s.check(am.voices_of(&"gun_pistol:tail").size() >= 1, "…and its %s tail" % am.env_at(muzzle))
	# another player's shotgun 30 m away (the replicated path every client in reach gets)
	var fwd := player.facing()
	var from := player.global_position + Vector3(fwd.z, 0, -fwd.x) * 30.0 + Vector3(0, 1.3, 0)
	var ends := PackedVector3Array()
	for k in 3:
		var e := player.global_position + fwd * 8.0 + Vector3(k - 1.0, 0.0, 0.0)
		e.y = world.get_height(e.x, e.z) + 0.05
		ends.append(e)
	var impacts0: int = am.combat.impacts
	Events.shot_fired.emit(4242, &"escopeta", from, ends, 0)
	await s.frames(1)
	s.check(am.voices_of(&"gun_shotgun:close").size() >= 1 and am.voices_of(&"gun_shotgun:far").size() >= 1,
		"a remote shotgun 30 m away: close + distant layers (the other players' shots are heard)")
	await s.seconds(0.2)
	s.check(am.combat.impacts > impacts0, "its pellets hit the snow: %d impacts" % (am.combat.impacts - impacts0))
	# --- loops
	var stove: Node = world.cabin.get_node_or_null("Stove")
	s.check(stove != null and am.is_loop_playing(&"stove_loop", stove), "the lit cabin stove plays its loop (a 3D voice attached to it)")
	var fire := Node3D.new()
	world.add_child(fire)
	fire.global_position = player.global_position + fwd * 3.0
	am.start_loop(&"fire_loop", fire)
	await s.frames(2)
	var on := am.is_loop_playing(&"fire_loop", fire)
	am.stop_loop(&"fire_loop", fire)
	await s.seconds(0.45)
	s.check(on and not am.is_loop_playing(&"fire_loop", fire), "start_loop / stop_loop on a world node (fire_loop)")
	fire.queue_free()
	# --- ambience director: Altavega → city bed; a valley forest → forest bed; inside → interior
	var d := am.director
	var alt := Locations.by_id(Locations.CITY_ID)
	var c := Locations.center(alt) if not alt.is_empty() else Vector2(1500, -1500)
	d.forced_pos = Vector3(c.x, world.get_height(c.x, c.y) + 1.7, c.y)
	d._poll_t = 0.0
	await s.frames(2)
	var city_bed := &"city_night" if WorldState.is_night_now() else &"city_day"
	s.check(d.family == &"city" and float(d.targets.get(String(city_bed), 0.0)) >= 0.5,
		"director: Altavega (%.0f, %.0f) → %s bed (family %s, %s)" % [c.x, c.y, city_bed, d.family, str(d.family_weights)])
	var fpos := _forest_point(world, player.global_position)
	d.forced_pos = fpos
	d._poll_t = 0.0
	await s.frames(2)
	var forest_bed := &"forest_night" if WorldState.is_night_now() else &"forest_day"
	s.check(d.family == &"forest" and float(d.targets.get(String(forest_bed), 0.0)) >= 0.5,
		"director: a valley forest (%.0f, %.0f) → %s bed" % [fpos.x, fpos.z, forest_bed])
	d.forced_pos = Vector3.INF
	var was_in := player.in_house
	player.in_house = true
	d._poll_t = 0.0
	await s.frames(2)
	s.check(d.inside and float(d.targets.get("interior", 0.0)) == 1.0 and am.environment == &"interior", "director: inside → interior bed, interior reverb send")
	player.in_house = was_in
	d._poll_t = 0.0
	await s.seconds(1.0)
	var playing := d.beds_playing()
	s.check(playing.size() >= 1 and (d.beds[playing[0]] as AudioStreamPlayer).bus == &"Ambience",
		"ambience beds playing on the Ambience bus: %s (dry run: %s)" % [", ".join(playing), am.dry_run])
	# --- footsteps resolve the surface under the player
	am.play_ex(&"footstep_snow", player.global_position)
	var steps := 0
	for k in am.last_voice:
		if String(k).begins_with("footstep:"):
			steps += 1
	s.check(steps >= 1, "a footstep resolves its surface (%s)" % am.surface_at(player.global_position, player))
	# --- 50 zombies around the player: the voice budget holds and they are heard
	var sys := ZombieSystem.instance
	if sys != null:
		var dir_on := Director.instance != null and Director.instance.enabled
		if Director.instance != null:
			Director.instance.enabled = false
		sys.clear_all()
		var groans0: int = am.zombies.groans
		sys.spawn_ring(player.global_position, 50, 6.0, 26.0, ZombieKinds.Kind.WALKER, ZombieKinds.State.WANDER)
		var peak := 0
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 3500:
			await tree.process_frame
			peak = maxi(peak, am.voices_in_group(&"zombie_voice"))
		var n := ZombieClient.instance.records.size() if ZombieClient.instance != null else 0
		s.check(n >= 40 and peak <= 6 and am.zombies.groans > groans0,
			"50 zombies nearby (%d records): peak %d zombie voices (≤ 6), %d groans started" % [n, peak, am.zombies.groans - groans0])
		sys.clear_all()
		if Director.instance != null:
			Director.instance.enabled = dir_on
	# the earlier M4 / M5 steps swung melee weapons and reloaded guns: their clips scheduled anim-event sounds
	s.check(am.combat.anim_scheduled > 0, "anim-event sounds scheduled from the players' clips (swings, reload steps): %d" % am.combat.anim_scheduled)
	s.check(am.stats["played"] > 0, "audio stats %s" % str(am.stats))


## A point of the valley whose macro biome is forest (spiral search around `from`).
func _forest_point(world: World, from: Vector3) -> Vector3:
	var macro := world.hf.macro if world.hf != null else null
	for r in range(0, 900, 30):
		for k in 12:
			var a := TAU * float(k) / 12.0
			var p := from + Vector3(cos(a) * r, 0, sin(a) * r)
			if macro == null or not macro.ok or AudioManager.family_at(p) == &"forest":
				var ok := true
				for kk in 4:   # the 35 m samples too
					var q := p + Vector3(cos(TAU * kk / 4.0 + 0.4), 0, sin(TAU * kk / 4.0 + 0.4)) * 35.0
					ok = ok and AudioManager.family_at(q) == &"forest"
				if ok:
					p.y = world.get_height(p.x, p.z) + 1.7
					return p
	return from
