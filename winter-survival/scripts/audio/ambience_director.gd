class_name AmbienceDirector
extends Node
## Ambience director (S1, docs/AUDIO.md §3): crossfades the stereo beds by where the listener is, the time of day,
## the weather and inside / outside, and scatters the sparse one-shots around it.
##   where     every POLL s the macro-map biome is sampled at the listener and 4 points 35 m around it; each biome
##             maps to a family (data/audio_events.json ambience.biome_family: forest, open, pass, ice, city, port),
##             the 5 samples give the family weights. H2's zone tracker (Events.zone_entered) wins when present: a
##             zone of Altavega (its `chain`) pins the city family; a zone with power «generator» gets a generator
##             hum at its centre while the listener is within 120 m.
##   when      forest / city have day and night beds (WorldState.is_night_now()).
##   weather   the wind layer follows AudioManager.set_wind() (0.2 day, 0.5 night, 0.6 warning, 1 blizzard); the
##             blizzard layer comes up with Weather's wind_loop (start_loop / stop_loop) or WorldState's weather.
##   inside    the local player's in_house: the interior bed (room tone + the storm through the walls) fades in, the
##             outdoor beds drop 14 dB and the Ambience bus low-pass closes to 700 Hz; the reverb send switches to
##             the interior room (AudioManager.set_environment).
##   one-shots per family, from the table (every [min, max] s, day / night, distance), placed in 3D at a random
##             bearing around the listener (AudioManager.play at that point: the listener hears it from there).
## Beds are 2D AudioStreamPlayers on the Ambience bus, created on first use, stopped when silent for 3 s.

const POLL := 0.5
const FADE_RATE := 0.35          # weight units per second (a full crossfade ≈ 3 s)
const INSIDE_OUTDOOR_DB := -14.0
const LPF_OUT := 20000.0
const LPF_IN := 700.0
const SAMPLE_R := 35.0
const GEN_RANGE := 120.0

var table: Dictionary = {}
var beds: Dictionary = {}         # bed name -> AudioStreamPlayer
var weights: Dictionary = {}      # bed name -> current weight 0..1 (smoothed)
var targets: Dictionary = {}      # bed name -> target weight
var family: StringName = &""      # dominant family (tests / debug)
var family_weights: Dictionary = {}
var inside: bool = false
var blizzard: bool = false
var layer_on: Dictionary = {}     # layer name -> requested by start_loop
var _poll_t: float = 0.0
var _timers: Dictionary = {}      # "family:index" -> seconds left
var _zone_city: bool = false
var _gen_player: AudioStreamPlayer3D
var _gen_pos: Vector3 = Vector3.INF
var _lpf_hz: float = LPF_OUT
var _rng := RandomNumberGenerator.new()
var _gen_proc: AudioStreamPlayer   # Balance.PROCEDURAL_AUDIO fallback wind (beds missing from the build)
## Tests.
var oneshots: int = 0
var forced_pos: Vector3 = Vector3.INF


func setup(p_table: Dictionary) -> void:
	table = p_table
	_rng.randomize()
	Events.zone_entered.connect(_on_zone)
	Events.weather_changed.connect(func(w: StringName) -> void: blizzard = w == &"blizzard")
	Events.night_started.connect(func(_d: int) -> void: AudioManager.play(&"stinger_night"))
	# WorldState._roll_day plays day_start where the day rolls; clients get Events.day_started (the cooldown dedups)
	Events.day_started.connect(func(_d: int) -> void: AudioManager.play(&"day_start"))


func _ready() -> void:
	name = "AmbienceDirector"
	process_mode = Node.PROCESS_MODE_ALWAYS


## Weather's wind_loop (the `layer` events): the blizzard layer on / off.
func set_layer(layer: StringName, on: bool) -> void:
	layer_on[layer] = on


func _on_zone(info: Dictionary) -> void:
	var chain: Array = info.get("chain", [])
	_zone_city = chain.has(Locations.CITY_ID) or str(info.get("id", "")) == Locations.CITY_ID
	var e := Locations.by_id(str(info.get("id", "")))
	if not e.is_empty() and str(e.get("power", "")) == "generator":
		var c := Locations.center(e)
		var w := World.instance
		_gen_pos = Vector3(c.x, (w.get_height(c.x, c.y) if w != null and w.is_configured else 0.0) + 1.0, c.y)


func listener_pos() -> Vector3:
	return forced_pos if forced_pos != Vector3.INF else AudioManager.listener_position()


## Family weights at a point (tests call it directly): the biome under 5 samples, mapped by the table.
func families_at(pos: Vector3) -> Dictionary:
	var out := {}
	var w := World.instance
	var macro: MacroMap = w.hf.macro if w != null and w.hf != null else null
	var bf: Dictionary = table.get("biome_family", {})
	var names: Array = MacroMap.Biome.keys()
	var pts := [Vector2(pos.x, pos.z)]
	for k in 4:
		var a := TAU * float(k) / 4.0 + 0.4
		pts.append(Vector2(pos.x + cos(a) * SAMPLE_R, pos.z + sin(a) * SAMPLE_R))
	for i in pts.size():
		var p: Vector2 = pts[i]
		var fam := "forest"
		if macro != null and macro.ok:
			var b := macro.biome_at(p.x, p.y)
			fam = str(bf.get(names[clampi(b, 0, names.size() - 1)], "forest"))
		elif p.length() > 1500.0:
			fam = "open"
		out[fam] = float(out.get(fam, 0.0)) + (2.0 if i == 0 else 1.0) / 6.0
	return out


func _process(delta: float) -> void:
	if not AudioManager.enabled or table.is_empty():
		return
	var lp := GameFlow.local_player() as Player
	var in_game := lp != null or forced_pos != Vector3.INF
	_poll_t -= delta
	if _poll_t <= 0.0:
		_poll_t = POLL
		if in_game:
			_poll(lp)
		else:
			targets.clear()
	_fade(delta)
	if in_game:
		_oneshots(delta)


func _poll(lp: Player) -> void:
	var pos := listener_pos()
	inside = lp != null and lp.in_house and forced_pos == Vector3.INF
	family_weights = families_at(pos)
	if _zone_city and not family_weights.has("port"):
		family_weights["city"] = maxf(float(family_weights.get("city", 0.0)), 0.7)
	var best := 0.0
	for f in family_weights:
		if float(family_weights[f]) > best:
			best = family_weights[f]
			family = StringName(f)
	var night := WorldState.is_night_now()
	targets.clear()
	var out_mul := db_to_linear(INSIDE_OUTDOOR_DB) if inside else 1.0
	for f in family_weights:
		var bed := str(f)
		if f == "forest" or f == "city":
			bed = "%s_%s" % [f, "night" if night else "day"]
		targets[bed] = float(targets.get(bed, 0.0)) + float(family_weights[f]) * out_mul
	targets["interior"] = 1.0 if inside else 0.0
	var wind := AudioManager.wind
	targets["@wind"] = clampf(wind, 0.0, 1.0) * (0.35 if inside else 1.0)
	var bz := blizzard or bool(layer_on.get(&"blizzard", false)) or WorldState.weather_now() == &"blizzard"
	targets["@blizzard"] = (0.3 if inside else 1.0) if bz else 0.0
	AudioManager.set_environment(&"interior" if inside else (&"city" if family == &"city" or family == &"port" else (&"forest" if family == &"forest" else &"open")))
	_update_generator(pos)


func _bed_path(name: String) -> String:
	if name.begins_with("@"):
		var l: Dictionary = table.get("layers", {})
		var p := str(l.get(name.substr(1), ""))
		return AudioTable.ROOT + p if p != "" else ""
	var b: Dictionary = table.get("beds", {})
	return AudioTable.ROOT + str(b[name]) if b.has(name) else ""


func _bed_db(name: String) -> float:
	var t: Dictionary = table.get("bed_db", {})
	if name == "@wind":
		return -10.0
	if name == "@blizzard":
		return -2.0
	return float(t.get(name, -6.0))


func _fade(delta: float) -> void:
	var names := {}
	for k in targets:
		names[k] = true
	for k in weights:
		names[k] = true
	for name in names:
		var cur := float(weights.get(name, 0.0))
		var tgt := float(targets.get(name, 0.0))
		cur = move_toward(cur, tgt, FADE_RATE * delta * (2.0 if name == "@blizzard" or name == "interior" else 1.0))
		weights[name] = cur
		var p: AudioStreamPlayer = beds.get(name)
		if cur > 0.001:
			if p == null:
				p = _make_bed(name)
				if p == null:
					continue
			p.volume_db = _bed_db(name) + linear_to_db(cur)
			if not AudioManager.player_active(p):
				AudioManager.player_play(p, _rng.randf() * maxf(p.stream.get_length() - 1.0, 0.0))
			p.set_meta("silent_t", 0.0)
		elif p != null and AudioManager.player_active(p):
			p.volume_db = -80.0
			var s := float(p.get_meta("silent_t", 0.0)) + delta
			p.set_meta("silent_t", s)
			if s > 3.0:
				AudioManager.player_stop(p)
	# the Ambience bus low-pass: closed indoors (muffled storm), open outside
	var want := LPF_IN if inside else LPF_OUT
	_lpf_hz = lerpf(_lpf_hz, want, 1.0 - exp(-3.0 * delta))
	AudioManager.set_ambience_lowpass(_lpf_hz)
	_procedural_wind(delta)


## Beds playing now (tests / debug).
func beds_playing() -> PackedStringArray:
	var out := PackedStringArray()
	for b in beds:
		if AudioManager.player_active(beds[b]):
			out.append(b)
	return out


## Quitting: every bed, the generator and the procedural wind stop.
func stop_all() -> void:
	for b in beds:
		AudioManager.player_stop(beds[b])
	if _gen_player != null:
		AudioManager.player_stop(_gen_player)
	if _gen_proc != null:
		_gen_proc.stop()


func _make_bed(name: String) -> AudioStreamPlayer:
	var path := _bed_path(name)
	if path == "" or not ResourceLoader.exists(path):
		return null
	var s := AudioManager.stream(path)
	if s == null:
		return null
	AudioManager.set_stream_loop(s)
	var p := AudioStreamPlayer.new()
	p.name = "Bed_" + name.replace("@", "")
	p.stream = s
	p.bus = &"Ambience"
	p.volume_db = -80.0
	add_child(p)
	beds[name] = p
	return p


## Sparse one-shots of the families present (weight ≥ 0.25), each on its own random timer.
func _oneshots(delta: float) -> void:
	var os: Dictionary = table.get("oneshots", {})
	var night := WorldState.is_night_now()
	var fams: Array = []
	if inside:
		fams = ["interior"]
	else:
		for f in family_weights:
			if float(family_weights[f]) >= 0.25:
				fams.append(f)
	for f in fams:
		var list: Array = os.get(f, [])
		for i in list.size():
			var o: Dictionary = list[i]
			if bool(o.get("day", false)) and night:
				continue
			if bool(o.get("night", false)) and not night:
				continue
			if o.has("wind_min") and AudioManager.wind < float(o["wind_min"]):
				continue
			var key := "%s:%d" % [f, i]
			var every: Array = o.get("every", [30, 60])
			var mul := float(o.get("night_mult", 1.0)) if night else 1.0
			if not _timers.has(key):
				_timers[key] = _rng.randf_range(float(every[0]), float(every[1])) * mul * _rng.randf_range(0.3, 1.0)
				continue
			_timers[key] = float(_timers[key]) - delta
			if float(_timers[key]) > 0.0:
				continue
			_timers[key] = _rng.randf_range(float(every[0]), float(every[1])) * mul
			fire_oneshot(o)


func fire_oneshot(o: Dictionary) -> int:
	var ev := StringName(str(o.get("event", "")))
	var def: Dictionary = AudioManager.table.events.get(ev, {})
	oneshots += 1
	if str(def.get("mode", "3d")) == "2d":
		return AudioManager.play_ex(ev)
	var dist: Array = o.get("dist", [25, 80])
	var a := _rng.randf() * TAU
	var r := _rng.randf_range(float(dist[0]), float(dist[1]))
	var p := listener_pos() + Vector3(cos(a) * r, _rng.randf_range(2.0, 12.0), sin(a) * r)
	return AudioManager.play_ex(ev, p)


func _update_generator(pos: Vector3) -> void:
	var near := _gen_pos != Vector3.INF and pos.distance_to(_gen_pos) < GEN_RANGE
	if near and _gen_player == null:
		var paths: PackedStringArray = (AudioManager.table.events.get(&"generator_loop", {}) as Dictionary).get("files_paths", PackedStringArray())
		if paths.is_empty():
			return
		var s := AudioManager.stream(paths[0])
		if s == null:
			return
		AudioManager.set_stream_loop(s)
		_gen_player = AudioStreamPlayer3D.new()
		_gen_player.name = "Generator"
		_gen_player.stream = s
		_gen_player.bus = &"World"
		_gen_player.max_distance = 45.0
		_gen_player.unit_size = 4.0
		_gen_player.volume_db = -4.0
		add_child(_gen_player)
		_gen_player.global_position = _gen_pos
		AudioManager.player_play(_gen_player)
	elif not near and _gen_player != null:
		_gen_player.queue_free()
		_gen_player = null


## Balance.PROCEDURAL_AUDIO: when the wind beds are not in the build (a trimmed web export), a generated filtered
## noise stands in for the wind layer (the pre-S1 behaviour).
func _procedural_wind(_delta: float) -> void:
	if AudioManager.dry_run or not Balance.PROCEDURAL_AUDIO or _bed_path("@wind") != "" and ResourceLoader.exists(_bed_path("@wind")):
		return
	if _gen_proc == null:
		var gen := AudioStreamGenerator.new()
		gen.mix_rate = 22050.0
		gen.buffer_length = 0.25
		_gen_proc = AudioStreamPlayer.new()
		_gen_proc.stream = gen
		_gen_proc.bus = &"Ambience"
		add_child(_gen_proc)
		_gen_proc.play()
	var pb := _gen_proc.get_stream_playback() as AudioStreamGeneratorPlayback
	if pb == null:
		return
	var w := float(weights.get("@wind", 0.0)) + float(weights.get("@blizzard", 0.0))
	var lp := float(_gen_proc.get_meta("lp", 0.0))
	for i in pb.get_frames_available():
		lp += (randf() * 2.0 - 1.0 - lp) * 0.06
		var v := lp * 0.25 * w
		pb.push_frame(Vector2(v, v))
	_gen_proc.set_meta("lp", lp)
