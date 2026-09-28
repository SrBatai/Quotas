extends RefCounted
## Body of tests/unit/audio_test.gd (loaded at runtime so the autoloads exist when it compiles).

const CODE_DIRS := ["res://scripts"]
## Events the code builds at run time (not literal &"…" names): Gunplay's reload_<class>, CombatAudio's impacts and
## casings, and the door events M6a calls (PLAN M6a: door_open / door_close / door_locked).
const DYNAMIC := [&"reload_pistol", &"reload_longgun", &"reload_bow", &"impact_snow", &"impact_wood", &"impact_metal",
	&"impact_concrete", &"impact_flesh", &"casing_brass_snow", &"casing_brass_hard", &"casing_hull_snow", &"casing_hull_hard",
	&"door_open", &"door_close", &"door_locked", &"heartbeat", &"stinger_night", &"stinger_danger"]
const MIN_VARIATIONS := {"gun_pistol": 3, "gun_revolver": 3, "gun_shotgun": 3, "gun_rifle": 3, "zombie_groan": 4,
	"zombie_alert": 4, "zombie_attack": 4, "zombie_die": 4, "chop_hit": 4, "impact_snow": 3, "impact_flesh": 3}
const BUDGET_BYTES := 10_500_000

var tree: SceneTree
var _checks: int = 0
var _failed: bool = false
var _played: Dictionary = {}


func check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("  ok   ", msg)
	else:
		_failed = true
		print("FAIL: ", msg)


func run(p_tree: SceneTree) -> void:
	tree = p_tree
	print("== VENTISCA audio test (S1)")
	await tree.process_frame
	var t := AudioTable.load_default()
	check(t.ok and not t.events.is_empty(), "data/audio_events.json + assets/audio/manifest.json load (%d events, %d files)" % [t.events.size(), (t.manifest.get("files", {}) as Dictionary).size()])
	var errs := t.validate()
	check(errs.is_empty(), "the event table validates (%d problems%s)" % [errs.size(), (": " + "; ".join(errs.slice(0, 6))) if not errs.is_empty() else ""])
	_code_events(t)
	_files(t)
	_variations(t)
	await _manager(t)
	print("== %d checks, %s" % [_checks, "FAILED" if _failed else "ALL PASSED"])
	tree.quit(1 if _failed else 0)


# ------------------------------------------------------------------ code ↔ table
func _code_events(t: AudioTable) -> void:
	var used := {}
	var re := RegEx.new()
	re.compile("AudioManager\\.(?:play|play_ex|start_loop|stop_loop|schedule)\\(\\s*&\"([A-Za-z0-9_]+)\"")
	var re_local := RegEx.new()   # the audio lane's own calls (play(&"…") inside scripts/audio and the manager)
	re_local.compile("(?:^|[^.\\w])(?:play|play_ex|schedule)\\(\\s*&\"([A-Za-z0-9_]+)\"")
	var files := _collect("res://scripts")
	for path in files:
		var src := _strip_comments(FileAccess.get_file_as_string(path))
		for m in re.search_all(src):
			used[StringName(m.get_string(1))] = path
		if path.begins_with("res://scripts/audio/") or path.ends_with("audio_manager.gd"):
			for m in re_local.search_all(src):
				used[StringName(m.get_string(1))] = path
	for id in Firearms.TABLE:
		used[StringName(str(Firearms.TABLE[id].get("sfx", "")))] = "Firearms.TABLE[%s].sfx" % id
		used[StringName("reload_%s" % String(Firearms.TABLE[id]["class"]).to_lower())] = "Gunplay.reload (reload_<class>)"
	for d in DYNAMIC:
		used[d] = used.get(d, "dynamic")
	var missing: Array = []
	var silent := 0
	for ev in used:
		if t.silent.has(ev):
			silent += 1
			continue
		if AudioManager.STREAM_FILES.has(ev) and not t.events.has(ev):
			continue
		if not t.events.has(ev):
			missing.append("%s (%s)" % [ev, used[ev]])
			continue
		var ty := str((t.events[ev] as Dictionary).get("type", "simple"))
		if ty != "layer" and ty != "hit" and t.paths_of(ev).is_empty():
			missing.append("%s (no file)" % ev)
	check(used.size() >= 60, "event names found in the code: %d (literal calls + Firearms sfx + reload classes + dynamic)" % used.size())
	check(missing.is_empty(), "every event the code plays has a stream or is in the documented silent list (%d silent)%s" % [silent, (": missing " + ", ".join(missing)) if not missing.is_empty() else ""])
	for s in t.silent:
		check(str(t.silent[s]).length() > 20, "silent event %s documents why (%s…)" % [s, str(t.silent[s]).left(40)])
	check(t.events.has(&"door_open") and t.events.has(&"door_close") and t.events.has(&"door_locked"), "door events for M6a: door_open / door_close / door_locked")


# ------------------------------------------------------------------ files
func _files(t: AudioTable) -> void:
	var man: Dictionary = t.manifest.get("files", {})
	var total := 0
	var bad_load: Array = []
	var bad_ch: Array = []
	var bad_len: Array = []
	var bad_peak: Array = []
	for f: String in man:
		var info: Dictionary = man[f]
		var path := AudioTable.ROOT + f
		total += FileAccess.get_file_as_bytes(path).size() if FileAccess.file_exists(path) else 0
		var s := load(path) as AudioStream if ResourceLoader.exists(path) else null
		if s == null:
			bad_load.append(f)
			continue
		var ch := _channels(path)
		if ch != int(info.get("ch", 0)):
			bad_ch.append("%s (%d ch, manifest %s)" % [f, ch, info.get("ch")])
		var dur := float(info.get("dur", 0.0))
		if dur < 0.02 or dur > 40.0 or absf(s.get_length() - dur) > maxf(0.05, dur * 0.05):
			bad_len.append("%s (%.2f s, manifest %.2f)" % [f, s.get_length(), dur])
		if not info.has("owner") and float(info.get("peak", 0.0)) > -0.9:
			bad_peak.append("%s (%.1f dBFS)" % [f, float(info.get("peak", 0.0))])
	check(bad_load.is_empty(), "every manifest file loads as an AudioStream (%d files)%s" % [man.size(), (": " + ", ".join(bad_load.slice(0, 5))) if not bad_load.is_empty() else ""])
	check(bad_ch.is_empty(), "channels match the manifest (read from the OGG / WAV headers)%s" % ((": " + ", ".join(bad_ch.slice(0, 5))) if not bad_ch.is_empty() else ""))
	check(bad_len.is_empty(), "lengths sane (0.02–40 s) and equal to the manifest%s" % ((": " + ", ".join(bad_len.slice(0, 5))) if not bad_len.is_empty() else ""))
	check(bad_peak.is_empty(), "peaks ≤ −1 dBFS (build output)%s" % ((": " + ", ".join(bad_peak.slice(0, 5))) if not bad_peak.is_empty() else ""))
	check(total <= BUDGET_BYTES and int(t.manifest.get("total_bytes", 0)) <= BUDGET_BYTES, "size budget: %.2f MB ≤ %.1f MB" % [total / 1e6, BUDGET_BYTES / 1e6])
	# 3D point sources mono, beds / stingers stereo
	var wrong: Array = []
	for ev in t.events:
		var d: Dictionary = t.events[ev]
		var want := 2 if str(d.get("bus", "")) == "Music" else (1 if str(d.get("mode", "3d")) == "3d" else 0)
		if want == 0:
			continue
		for p in t.paths_of(ev):
			if int(t.file_info(p).get("ch", want)) != want:
				wrong.append("%s → %s" % [ev, p.get_file()])
	for kind in ["beds", "layers"]:
		for b in (t.ambience.get(kind, {}) as Dictionary):
			for p in t.resolve(t.ambience[kind][b]):
				if int(t.file_info(p).get("ch", 0)) != 2:
					wrong.append("bed %s" % b)
				if not bool(t.file_info(p).get("loop", false)):
					wrong.append("bed %s is not a loop" % b)
	check(wrong.is_empty(), "3D events are mono, beds and stingers stereo loops / cues%s" % ((": " + ", ".join(wrong.slice(0, 6))) if not wrong.is_empty() else ""))
	var lic := FileAccess.get_file_as_string("res://assets/audio/LICENSES.md")
	var unlisted: Array = []
	for f: String in man:
		if not lic.contains("`%s`" % f):
			unlisted.append(f)
	check(not lic.is_empty() and unlisted.is_empty() and lic.contains("CC0"), "assets/audio/LICENSES.md lists every file (CC0 / original)%s" % ((": missing " + ", ".join(unlisted.slice(0, 5))) if not unlisted.is_empty() else ""))
	var layout := FileAccess.get_file_as_string("res://default_bus_layout.tres")
	var buses_ok := true
	for b in ["Music", "SFX", "Weapons", "Creatures", "Foley", "World", "Ambience", "UI", "RevOutdoor", "RevInterior", "RevCity"]:
		buses_ok = buses_ok and layout.contains("\"%s\"" % b) and AudioServer.get_bus_index(b) >= 0
	check(buses_ok, "default_bus_layout.tres: Master → Music, SFX (Weapons, Creatures, Foley, World), Ambience, UI, reverb returns")


## Channels from the file header: Vorbis identification packet ("\x01vorbis", channels at +11) or WAV fmt chunk.
func _channels(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0
	var head := f.get_buffer(256)
	if path.ends_with(".wav"):
		return head.decode_u16(22) if head.size() > 24 else 0
	for i in head.size() - 12:
		if head[i] == 1 and head[i + 1] == 0x76 and head[i + 2] == 0x6f and head[i + 3] == 0x72 and head[i + 4] == 0x62:
			return head[i + 11]
	return 0


func _variations(t: AudioTable) -> void:
	var low: Array = []
	for ev: String in MIN_VARIATIONS:
		var d: Dictionary = t.events.get(StringName(ev), {})
		var n := (d.get("close_paths", d.get("files_paths", PackedStringArray())) as PackedStringArray).size()
		if n < int(MIN_VARIATIONS[ev]):
			low.append("%s %d < %d" % [ev, n, MIN_VARIATIONS[ev]])
	var steps: Dictionary = (t.events.get(&"footstep_snow", {}) as Dictionary).get("surface_paths", {})
	for s in ["snow", "packed", "ice", "wood", "concrete", "metal"]:
		if (steps.get(s, PackedStringArray()) as PackedStringArray).size() < 6:
			low.append("footsteps on %s < 6" % s)
	for w in t.tails:
		for env in t.tails[w]:
			if (t.tails[w][env] as PackedStringArray).size() < 3:
				low.append("tail %s/%s < 3" % [w, env])
	check(low.is_empty(), "variations: ≥ 3 per shot type (+ 3 far, 3 tails × 4 environments), ≥ 6 per footstep surface (6 surfaces), ≥ 4 zombie groans%s" % ((": " + ", ".join(low)) if not low.is_empty() else ""))
	check(int((t.groups.get(&"zombie_voice", {}) as Dictionary).get("max", 99)) <= 6, "zombie voice budget ≤ 6 concurrent vocalisations")


# ------------------------------------------------------------------ AudioManager (headless client, no world)
func _manager(_t: AudioTable) -> void:
	var am := AudioManager
	check(am.enabled and am.table != null and am.table.ok and am.dry_run, "AudioManager enabled on a headless non-server process (dry run: no real playback), table loaded")
	check(am.has_stream(&"ui_zone_discover") and am.has_stream(&"gun_pistol") and not am.has_stream(&"no_such_event"), "has_stream: H2's registered ui_zone_discover, table events, unknown → false")
	am.event_played.connect(func(ev: StringName, _v: Node, _a: Vector3) -> void: _played[ev] = int(_played.get(ev, 0)) + 1)
	var id := am.play_ex(&"ui_click")
	var v := instance_from_id(id) as AudioStreamPlayer if id >= 0 else null
	check(v != null and am.voice_active(id) and v.bus == &"UI", "ui_click: a 2D voice on the UI bus")
	id = am.play_ex(&"chop_hit", Vector3(3, 0, 0))
	var v3 := instance_from_id(id) as AudioStreamPlayer3D if id >= 0 else null
	check(v3 != null and am.voice_active(id) and v3.bus == &"World" and v3.global_position.distance_to(Vector3(3, 0, 0)) < 0.01, "chop_hit: a 3D voice at the given point on the World bus")
	check(am.play_ex(&"chop_hit", Vector3(900, 0, 0)) < 0, "a 3D event beyond its max_distance is not played (culled)")
	check(am.play_ex(&"no_such_event") < 0 and am.play_ex(&"reload_pistol") < 0, "unknown and silent events play nothing")
	# zombie voice budget: 30 groans in random order at 1..30 m → 6 voices, the nearest
	var ds: Array = []
	for i in 30:
		ds.append(float(i + 1))
	ds.shuffle()
	for d in ds:
		am.play_ex(&"zombie_groan", Vector3(d, 0, 0))
	var kept: Array = []
	for p in am.voices_of(&"zombie_groan"):
		kept.append((p as Node3D).global_position.x)
	kept.sort()
	check(am.voices_in_group(&"zombie_voice") == 6 and kept.size() == 6 and float(kept[-1]) <= 12.0,
		"zombie voice budget: 30 requests → %d voices, nearest first (farthest kept %.0f m)" % [kept.size(), float(kept[-1]) if not kept.is_empty() else -1.0])
	var aid := am.play_ex(&"zombie_alert", Vector3(20, 0, 0))
	check(aid >= 0 and am.voices_in_group(&"zombie_voice") == 6 and am.voices_of(&"zombie_groan").size() == 5,
		"a «te he visto» 20 m away takes the place of the weakest groan (priority before distance), the budget stays 6")
	# per-event cap
	for i in 12:
		am.play_ex(&"impact_wood", Vector3(2, 0, 1))
	check(am.voices_of(&"impact_wood").size() == 8, "max_instances: 12 wood impacts at once → 8 voices")
	# gunshot layering
	am.play_ex(&"gun_shotgun", Vector3(2, 0, 0))
	check(am.voices_of(&"gun_shotgun:close").size() >= 1 and am.voices_of(&"gun_shotgun:tail").size() >= 1 and am.voices_of(&"gun_shotgun:far").is_empty(),
		"a shotgun 2 m away: close layer + environment tail, no distant layer")
	am.play_ex(&"gun_rifle", Vector3(95, 0, 0))
	check(am.voices_of(&"gun_rifle:far").size() >= 1 and am.voices_of(&"gun_rifle:close").is_empty(), "a rifle 95 m away: distant layer (+ tail), no close layer")
	await tree.create_timer(1.2).timeout
	check(int(_played.get(&"gun_pump_back", 0)) >= 1 and int(_played.get(&"gun_pump_fwd", 0)) >= 1, "the shotgun's pump follows the shot (back + forward)")
	# loops
	var n := Node3D.new()
	tree.root.add_child(n)
	am.start_loop(&"fire_loop", n)
	am.start_loop(&"fire_loop", n)
	await tree.process_frame
	check(am.is_loop_playing(&"fire_loop", n) and am.loop_count() == 1, "start_loop: one looping 3D voice attached to its owner (a second start is ignored)")
	var lp := am._loops.get("fire_loop:%d" % n.get_instance_id()) as AudioStreamPlayer3D
	check(lp != null and lp.get_parent() == n and (lp.stream as AudioStreamOggVorbis).loop, "the loop follows the owner (child of it) and its stream loops")
	am.stop_loop(&"fire_loop", n)
	await tree.create_timer(0.5).timeout
	check(not am.is_loop_playing(&"fire_loop", n) and am.loop_count() == 0, "stop_loop fades it out and frees it")
	am.start_loop(&"stove_loop", n)
	n.queue_free()
	await tree.process_frame
	await tree.process_frame
	check(am.loop_count() == 0, "an owner leaving the tree takes its loop with it")
	var w := Node.new()
	tree.root.add_child(w)
	am.start_loop(&"wind_loop", w)
	var bz_on := bool(am.director.layer_on.get(&"blizzard", false))
	am.stop_loop(&"wind_loop", w)
	check(bz_on and not bool(am.director.layer_on.get(&"blizzard", true)), "wind_loop (Weather, blizzard) raises / drops the director's blizzard layer")
	w.queue_free()
	# heartbeat hook (H3)
	am.heartbeat(0.8)
	await tree.create_timer(1.2).timeout
	var beats := int(_played.get(&"heartbeat", 0))
	am.heartbeat(0.0)
	check(beats >= 1, "heartbeat(0.8) beats (%d in 1.2 s); heartbeat(0) stops it" % beats)
	# settings → bus volumes
	var st := AudioSettings.get_instance()
	var keep := st.get_value("effects")
	st.set_value("effects", 0.5, false)
	var sfx_db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"SFX"))
	st.set_value("effects", 0.0, false)
	var muted := AudioServer.is_bus_mute(AudioServer.get_bus_index(&"SFX"))
	st.set_value("effects", keep, false)
	check(absf(sfx_db - linear_to_db(0.5)) < 0.1 and muted, "AudioSettings: Efectos 50 %% → SFX bus %.1f dB, 0 mutes it" % sfx_db)
	check(am.stats["played"] > 30 and am.stats["rejected"] > 0, "stats: %s" % str(am.stats))


## Code without its comment lines (doc comments mention event names as examples).
func _strip_comments(src: String) -> String:
	var out := PackedStringArray()
	for line in src.split("\n"):
		if not line.strip_edges().begins_with("#"):
			out.append(line)
	return "\n".join(out)


func _collect(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if dir.current_is_dir():
			if not f.begins_with("."):
				out.append_array(_collect(dir_path + "/" + f))
		elif f.ends_with(".gd"):
			out.append(dir_path + "/" + f)
		f = dir.get_next()
	dir.list_dir_end()
	return out
