extends Node
## AudioManager v2 (S1; docs/AUDIO.md). Plays sounds by event name (GDD §14 / §18): the gameplay code keeps calling
## `play(&"event", pos)` / `start_loop` / `stop_loop` / `set_wind`, and the data-driven table data/audio_events.json
## (AudioTable, resolved against assets/audio/manifest.json) decides files, bus, level, randomisation, 2D / 3D,
## distance, priority, voice budget and layering.
##   voices    pooled AudioStreamPlayer3D / AudioStreamPlayer; a full pool steals its least important voice (event
##             priority minus distance); `max_instances` per event, `cooldown`, and voice budgets per group
##             (`zombie_voice` ≤ 6, the nearest win); a 3D event beyond its `max_distance` is not played at all.
##   variety   a shuffled bag per event (never the same file twice in a row), random pitch / volume.
##   types     simple, shot (close + distant layer by listener distance + a tail per firing environment + the
##             action's follow-ups + the casing on snow / hard ground), footstep (the surface under the foot, the
##             walker's speed and posture), surface, hit (weapon impact + flesh + reaction), melee_swing (by weapon
##             weight), stinger, layer (the ambience director's blizzard layer).
##   loops     start_loop / stop_loop: a dedicated player attached to the owner (3D follows it), faded in and out.
##   buses     Master → Music, SFX (Weapons, Creatures, Foley, World), Ambience, UI, + three reverb returns
##             (RevOutdoor, RevInterior, RevCity) fed by an Area3D send that follows the listener
##             (default_bus_layout.tres; `ensure_buses()` builds the same layout when the file is missing).
##   listener  an AudioListener3D at the local player's head, turned with the camera's yaw (not its pitch): distance
##             is measured from the character — the same distances as the zombies' hearing — and left / right follow
##             the screen (GDD §14: pan by screen position, not by where the character faces).
##   children  AmbienceDirector (beds, one-shots, stingers), ZombieVoices (groans / steps / breaths within budget),
##             CombatAudio (anim-event reload steps and swings, impacts, whiz, loot, downed, breath).
## Dedicated server (Net.is_dedicated, feature `dedicated_server`, `--server`) and `--no-audio`: nothing is loaded
## and every call returns at once (the «Dedicated Server» export also leaves assets/audio/ out).
## Dry run: headless processes and the Dummy audio driver (tests, xvfb benches, headless net clients) resolve every
## event exactly as a real run (voice, bus, position, budgets, loops, beds) but never start a real playback — a voice
## counts as playing for its stream's length — so no AudioServer playback can outlive the process at quit (a leaked
## playback prints «ERROR: resources still in use at exit», which every test gate greps).
## H2: STREAM_FILES / register() / has_stream() are kept: registered streams play as plain events.

## Event -> stream file loaded at start (missing files are skipped: the event stays silent).
const STREAM_FILES := {
	&"ui_zone_discover": "res://assets/audio/ui/ui_zone_discover.wav",
}

const POOL_3D := 40
const POOL_3D_WEB := 24
const POOL_2D := 16
const LISTENER_HEIGHT := 1.7
## Physics layer 20: only the audio reverb send area lives there (AudioStreamPlayer3D.area_mask).
const REVERB_LAYER := 1 << 19
## Bus layout: [name, send, base volume dB]. Sends go to an earlier bus (Godot's rule).
const BUS_LAYOUT := [
	["Master", "", 0.0], ["Music", "Master", -4.0], ["SFX", "Master", 0.0], ["Weapons", "SFX", 0.0],
	["Creatures", "SFX", 0.0], ["Foley", "SFX", 0.0], ["World", "SFX", 0.0], ["Ambience", "Master", -2.0],
	["UI", "Master", -3.0], ["RevOutdoor", "Master", 0.0], ["RevInterior", "Master", 0.0], ["RevCity", "Master", 0.0],
]
const BUS_BASE_DB := {"Music": -4.0, "Ambience": -2.0, "UI": -3.0}
## Reverb send per environment: [return bus, send amount].
const ENV_SEND := {&"forest": [&"RevOutdoor", 0.18], &"open": [&"RevOutdoor", 0.1], &"city": [&"RevCity", 0.3],
	&"interior": [&"RevInterior", 0.35]}
## Casing kind → shots: surfaces that sound hard.
const HARD_SURFACES := [&"packed", &"concrete", &"wood", &"metal", &"ice"]

signal event_played(event: StringName, voice: Node, at: Vector3)

var enabled: bool = true
## No real playback (headless / Dummy driver): see the header.
var dry_run: bool = false
var table: AudioTable
var wind: float = 0.0
var environment: StringName = &"forest"
var listener: AudioListener3D
var director: AmbienceDirector
var zombies: ZombieVoices
var combat: CombatAudio
## Tests / debug counters.
var stats := {"played": 0, "stolen": 0, "rejected": 0, "culled": 0, "loops": 0}
## Tests: the last voice started per event.
var last_voice: Dictionary = {}

var _streams: Dictionary = {}
var _loops: Dictionary = {}
var _pool_2d: Array[AudioStreamPlayer] = []
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _meta: Dictionary = {}          # player instance id -> {event, prio, group, dist, t0, key}
var _cache: Dictionary = {}         # res path -> AudioStream
var _bags: Dictionary = {}          # key -> Array of indices left
var _last_idx: Dictionary = {}
var _last_play: Dictionary = {}     # event -> time
var _pending: Array = []            # scheduled plays: {t, event, node, at, opts}
var _rng := RandomNumberGenerator.new()
var _reverb_area: Area3D
var _hb_intensity: float = 0.0
var _hb_next: float = 0.0
var _duck: Dictionary = {}          # bus -> [db, until]
var _lpf: AudioEffectLowPassFilter
var _prewarm: PackedStringArray = PackedStringArray()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	var args := OS.get_cmdline_user_args()
	if Net.is_dedicated or OS.has_feature("dedicated_server") or args.has("--server") or args.has("--no-audio"):
		enabled = false
		return
	dry_run = DisplayServer.get_name() == "headless" or AudioServer.get_driver_name() == "Dummy" or args.has("--audio-dry-run")
	ensure_buses()
	AudioSettings.get_instance().apply()
	table = AudioTable.load_default()
	var n3 := POOL_3D_WEB if OS.has_feature("web") else POOL_3D
	for i in n3:
		var p3 := AudioStreamPlayer3D.new()
		p3.name = "V3_%d" % i
		p3.process_mode = Node.PROCESS_MODE_PAUSABLE
		p3.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p3.area_mask = REVERB_LAYER
		add_child(p3)
		_pool_3d.append(p3)
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		p.name = "V2_%d" % i
		add_child(p)
		_pool_2d.append(p)
	for ev: StringName in STREAM_FILES:
		if ResourceLoader.exists(STREAM_FILES[ev]):
			register(ev, load(STREAM_FILES[ev]) as AudioStream)
	listener = AudioListener3D.new()
	listener.name = "Listener"
	listener.top_level = true
	add_child(listener)
	_reverb_area = Area3D.new()
	_reverb_area.name = "ReverbSend"
	_reverb_area.top_level = true
	_reverb_area.monitoring = false
	_reverb_area.monitorable = true
	_reverb_area.collision_layer = REVERB_LAYER
	_reverb_area.collision_mask = 0
	_reverb_area.reverb_bus_enabled = true
	_reverb_area.reverb_bus_uniformity = 0.35
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 600.0
	cs.shape = sph
	_reverb_area.add_child(cs)
	add_child(_reverb_area)
	set_environment(&"forest")
	director = AmbienceDirector.new()
	director.setup(table.ambience)
	add_child(director)
	zombies = ZombieVoices.new()
	add_child(zombies)
	combat = CombatAudio.new()
	add_child(combat)
	Events.world_ready.connect(_start_prewarm)


## Plugs (or replaces) the stream of an event (H2): it plays as a plain 2D / 3D event when the table has no entry.
func register(event: StringName, stream: AudioStream) -> void:
	if stream != null:
		_streams[event] = stream


func has_stream(event: StringName) -> bool:
	if _streams.has(event):
		return true
	return table != null and table.has_event(event) and not table.paths_of(event).is_empty()


# ------------------------------------------------------------------ buses
## Creates the S1 bus layout when default_bus_layout.tres is missing (and tools/audio/gen_bus_layout.gd saves it).
func ensure_buses() -> void:
	if AudioServer.get_bus_index(&"Weapons") >= 0 and AudioServer.get_bus_index(&"RevCity") >= 0:
		_lpf = _find_effect(&"Ambience", "AudioEffectLowPassFilter") as AudioEffectLowPassFilter
		return
	while AudioServer.bus_count > 1:
		AudioServer.remove_bus(AudioServer.bus_count - 1)
	for i in BUS_LAYOUT.size():
		var b: Array = BUS_LAYOUT[i]
		if i > 0:
			AudioServer.add_bus()
		AudioServer.set_bus_name(i, b[0])
		AudioServer.set_bus_volume_db(i, b[2])
		if str(b[1]) != "":
			AudioServer.set_bus_send(i, b[1])
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -0.3
	AudioServer.add_bus_effect(0, lim)
	var glue := AudioEffectCompressor.new()
	glue.threshold = -14.0
	glue.ratio = 3.0
	glue.attack_us = 2000.0
	glue.release_ms = 180.0
	AudioServer.add_bus_effect(AudioServer.get_bus_index(&"SFX"), glue)
	var amb := AudioServer.get_bus_index(&"Ambience")
	_lpf = AudioEffectLowPassFilter.new()
	_lpf.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(amb, _lpf)
	var duck := AudioEffectCompressor.new()   # gunfire ducks the ambience (sidechain on Weapons)
	duck.threshold = -30.0
	duck.ratio = 4.0
	duck.attack_us = 1000.0
	duck.release_ms = 900.0
	duck.sidechain = &"Weapons"
	AudioServer.add_bus_effect(amb, duck)
	for r in [[&"RevOutdoor", 0.45, 0.85, 50.0, 0.25], [&"RevInterior", 0.3, 0.45, 8.0, 0.1], [&"RevCity", 0.8, 0.35, 80.0, 0.2]]:
		var rv := AudioEffectReverb.new()
		rv.room_size = r[1]
		rv.damping = r[2]
		rv.predelay_msec = r[3]
		rv.hipass = r[4]
		rv.dry = 0.0
		rv.wet = 1.0
		rv.spread = 1.0
		AudioServer.add_bus_effect(AudioServer.get_bus_index(r[0]), rv)


func _find_effect(bus: StringName, cls: String) -> AudioEffect:
	var i := AudioServer.get_bus_index(bus)
	if i < 0:
		return null
	for k in AudioServer.get_bus_effect_count(i):
		var e := AudioServer.get_bus_effect(i, k)
		if e.get_class() == cls:
			return e
	return null


## The Ambience bus low-pass (AmbienceDirector: 700 Hz indoors, open outside).
func set_ambience_lowpass(hz: float) -> void:
	if _lpf != null:
		_lpf.cutoff_hz = hz


## Firing / reverb environment of the listener: switches the reverb return the send area feeds.
func set_environment(env: StringName) -> void:
	environment = env
	if _reverb_area != null and ENV_SEND.has(env):
		_reverb_area.reverb_bus_name = ENV_SEND[env][0]
		_reverb_area.reverb_bus_amount = ENV_SEND[env][1]


# ------------------------------------------------------------------ public API
func play(event: StringName, at: Vector3 = Vector3.INF) -> void:
	play_ex(event, at)


## Plays an event; returns the voice's instance id (-1 = silent: unknown, culled, budget, cooldown).
func play_ex(event: StringName, at: Vector3 = Vector3.INF, opts: Dictionary = {}) -> int:
	if not enabled:
		return -1
	var def: Dictionary = table.events.get(event, {}) if table != null else {}
	if def.is_empty():
		var s: AudioStream = _streams.get(event)
		if s == null:
			return -1
		return _start(event, s, {"bus": "UI" if at == Vector3.INF else "World", "mode": "2d" if at == Vector3.INF else "3d"}, at, 0.0, 1.0)
	match str(def.get("type", "simple")):
		"shot":
			return _play_shot(event, def, at)
		"footstep":
			return _play_footstep(event, def, at, opts)
		"surface":
			var surf := surface_at(at) if at != Vector3.INF else &"snow"
			var key := "snow" if surf == &"snow" else "hard"
			return _play_set(event, def, (def.get("surface_paths", {}) as Dictionary).get(key, PackedStringArray()), at, opts)
		"hit":
			return _play_hit(event, def, at)
		"melee_swing":
			var w := StringName(str(opts.get("weight", table.weights.get(str(opts.get("hand", "")), "light"))))
			return _play_set(event, def, (def.get("weight_paths", {}) as Dictionary).get(String(w), PackedStringArray()), at, opts)
		"layer":
			if director != null:
				director.set_layer(StringName(str(def.get("layer", ""))), true)
			return -1
	return _play_set(event, def, def.get("files_paths", PackedStringArray()), at, opts)


## Plays `event` after `delay` s at `node`'s position then (it follows the node until it starts) or at `at`.
func schedule(event: StringName, delay: float, node: Node3D, at: Vector3, opts: Dictionary = {}) -> void:
	if not enabled:
		return
	if delay <= 0.0:
		play_ex(event, node.global_position if node != null and node.is_inside_tree() else at, opts)
		return
	_pending.append({"t": _now() + delay, "event": event, "node": node, "at": at, "opts": opts})


func start_loop(event: StringName, owner_node: Node) -> void:
	if not enabled or owner_node == null:
		return
	var key := _loop_key(event, owner_node)
	if _loops.has(key) and is_instance_valid(_loops[key]):
		return
	var def: Dictionary = table.events.get(event, {})
	if str(def.get("type", "")) == "layer":
		if director != null:
			director.set_layer(StringName(str(def.get("layer", ""))), true)
		_loops[key] = null
		return
	var paths: PackedStringArray = def.get("files_paths", PackedStringArray())
	if paths.is_empty():
		return
	var s := stream(paths[_rng.randi() % paths.size()])
	if s == null:
		return
	set_stream_loop(s)
	var p: Node
	var vol := float(def.get("volume_db", 0.0))
	if owner_node is Node3D and str(def.get("mode", "3d")) == "3d":
		var p3 := AudioStreamPlayer3D.new()
		p3.stream = s
		p3.bus = StringName(str(def.get("bus", "World")))
		p3.max_distance = float(def.get("max_distance", 20.0))
		p3.unit_size = float(def.get("unit_size", 3.0))
		p3.attenuation_filter_cutoff_hz = float(def.get("lpf_hz", 5000.0))
		p3.area_mask = REVERB_LAYER
		p3.volume_db = -40.0
		p = p3
	else:
		var p2 := AudioStreamPlayer.new()
		p2.stream = s
		p2.bus = StringName(str(def.get("bus", "World")))
		p2.volume_db = -40.0
		p = p2
	p.name = "Loop_" + String(event)
	if p is AudioStreamPlayer3D:
		owner_node.add_child(p)
	else:
		add_child(p)
	player_play(p, _rng.randf() * maxf(s.get_length() - 0.5, 0.0))
	create_tween().tween_property(p, "volume_db", vol, 0.4)
	_loops[key] = p
	stats["loops"] += 1
	var cb := _on_owner_exit.bind(owner_node.get_instance_id())
	if not owner_node.tree_exiting.is_connected(cb):
		owner_node.tree_exiting.connect(cb)


func stop_loop(event: StringName, owner_node: Node) -> void:
	if not enabled or owner_node == null:
		return
	var key := _loop_key(event, owner_node)
	if not _loops.has(key):
		return
	var p: Node = _loops[key]
	_loops.erase(key)
	var def: Dictionary = table.events.get(event, {})
	if str(def.get("type", "")) == "layer":
		if director != null:
			director.set_layer(StringName(str(def.get("layer", ""))), false)
		return
	if p != null and is_instance_valid(p):
		var tw := create_tween()
		tw.tween_property(p, "volume_db", -50.0, 0.3)
		tw.tween_callback(p.queue_free)


func is_loop_playing(event: StringName, owner_node: Node) -> bool:
	var p: Variant = _loops.get(_loop_key(event, owner_node))
	return p != null and is_instance_valid(p) and player_active(p)


func loop_count() -> int:
	var n := 0
	for k in _loops:
		if _loops[k] != null and is_instance_valid(_loops[k]):
			n += 1
	return n


func _loop_key(event: StringName, owner_node: Node) -> String:
	return "%s:%d" % [event, owner_node.get_instance_id()]


func _on_owner_exit(id: int) -> void:
	for k in _loops.keys():
		if str(k).ends_with(":%d" % id):
			_loops.erase(k)


func set_wind(intensity: float) -> void:
	wind = clampf(intensity, 0.0, 1.0)


## H3 hook: heartbeat by intensity (0 = off; 1 = 140 bpm, loud). Low health, a teammate bleeding out…
func heartbeat(intensity: float) -> void:
	_hb_intensity = clampf(intensity, 0.0, 1.0)


func heartbeat_intensity() -> float:
	return _hb_intensity


## PlayerView.on_swing: a clip started on a player (owner or remote) → its anim-event sounds (CombatAudio).
## `from` = where the clip starts (s; a remote charged swing starts at its strike).
func clip_started(clip: StringName, source: Node, from: float = 0.0) -> void:
	if enabled and combat != null:
		combat.clip_started(clip, source, from)


## Where the listener is (the local player's head; the camera in menus).
func listener_position() -> Vector3:
	return listener.global_position if listener != null and listener.is_inside_tree() else Vector3.ZERO


## Voices playing now in a group / of an event (tests, debug).
func voices_in_group(group: StringName) -> int:
	var n := 0
	for p in _all_voices():
		if _voice_active(p) and StringName(str((_meta.get(p.get_instance_id(), {}) as Dictionary).get("group", ""))) == group:
			n += 1
	return n


func voices_of(event: StringName) -> Array:
	var out: Array = []
	for p in _all_voices():
		if _voice_active(p) and StringName(str((_meta.get(p.get_instance_id(), {}) as Dictionary).get("event", ""))) == event:
			out.append(p)
	return out


func active_voices() -> int:
	var n := 0
	for p in _all_voices():
		if _voice_active(p):
			n += 1
	return n


## Starts a player (AudioStreamPlayer / 3D) — or, in a dry run, only marks it as playing.
func player_play(p: Node, from: float = 0.0) -> void:
	if p == null:
		return
	if dry_run:
		p.set_meta("dry_playing", true)
		p.set_meta("dry_t0", _now())
		return
	p.call("play", from)


func player_stop(p: Node) -> void:
	if p == null:
		return
	p.set_meta("dry_playing", false)
	if not dry_run:
		p.call("stop")


## Playing, or (dry run) started and not stopped — loops and beds.
func player_active(p: Node) -> bool:
	if p == null or not is_instance_valid(p):
		return false
	if dry_run:
		return bool(p.get_meta("dry_playing", false))
	return bool(p.get("playing"))


## A pooled voice is busy: playing (real) or within its stream's length since it started (dry run).
func _voice_active(p: Node) -> bool:
	if not dry_run:
		return bool(p.get("playing"))
	var m: Dictionary = _meta.get(p.get_instance_id(), {})
	return not m.is_empty() and bool(p.get_meta("dry_playing", false)) and _now() < float(m.get("until", 0.0))


## Tests: is the voice `id` (from play_ex) busy?
func voice_active(id: int) -> bool:
	var o := instance_from_id(id) if id >= 0 else null
	return o is Node and _voice_active(o as Node)


## Quitting: stop every real playback first (a playback still in the AudioServer at exit is reported as a leak).
func stop_all() -> void:
	for p in _all_voices():
		player_stop(p)
	_meta.clear()
	for k in _loops:
		var l: Variant = _loops[k]
		if l != null and is_instance_valid(l):
			player_stop(l)
	if director != null:
		director.stop_all()
	_pending.clear()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if enabled and not dry_run:
			stop_all()


func stream(path: String) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	if not ResourceLoader.exists(path):
		_cache[path] = null
		return null
	var s := load(path) as AudioStream
	_cache[path] = s
	return s


func set_stream_loop(s: AudioStream) -> void:
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	elif s is AudioStreamWAV:
		(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		(s as AudioStreamWAV).loop_end = int((s as AudioStreamWAV).get_length() * (s as AudioStreamWAV).mix_rate)


# ------------------------------------------------------------------ world queries
## Macro-map family (forest, open, pass, ice, city, port) at a point.
func family_at(pos: Vector3) -> StringName:
	var w := World.instance
	if table == null or w == null or w.hf == null or w.hf.macro == null or not w.hf.macro.ok:
		return &"forest"
	var names: Array = MacroMap.Biome.keys()
	var b := w.hf.macro.biome_at(pos.x, pos.z)
	return StringName(str((table.ambience.get("biome_family", {}) as Dictionary).get(names[clampi(b, 0, names.size() - 1)], "forest")))


## Firing environment of a shot at `pos` heard by the listener: interior when the local player is inside and close,
## else the family (forest → forest; city / port → city; the rest → open).
func env_at(pos: Vector3) -> StringName:
	var lp := GameFlow.local_player() as Player
	if lp != null and lp.in_house and lp.global_position.distance_to(pos) < 25.0:
		return &"interior"
	var f := family_at(pos)
	if f == &"forest":
		return &"forest"
	if f == &"city" or f == &"port":
		return &"city"
	return &"open"


## Surface under a foot / a landing object: snow, packed (roads, tracks), ice, wood, concrete, metal.
func surface_at(pos: Vector3, walker: Node3D = null) -> StringName:
	var pl := walker as Player
	var w := World.instance
	if pl != null and pl.in_house:
		return &"concrete" if family_at(pos) == &"city" else &"wood"
	if w == null or not w.is_configured:
		return &"snow"
	var ground := w.get_height(pos.x, pos.z)
	if pos.y - ground > 0.25:   # a porch, a floor, a roof, a vehicle
		var f := family_at(pos)
		return &"concrete" if f == &"city" or f == &"port" else &"wood"
	var s: Color = w.terrain.surface_at(pos.x, pos.z) if w.terrain != null else Color(0, 0, 0, 0)
	if s.g > 0.5 or w.hf.is_w1_water(pos.x, pos.z):
		return &"ice"
	if s.r > 0.5 or s.b > 0.5:
		return &"packed"
	return &"snow"


## Material a bullet end hit: ground (by surface), else what stands there (city → concrete / metal, else wood).
func impact_material(p: Vector3) -> StringName:
	var w := World.instance
	var f := family_at(p)
	if w != null and w.is_configured:
		var ground := w.get_height(p.x, p.z)
		if p.y - ground < 0.4:
			var s := surface_at(Vector3(p.x, ground, p.z))
			return &"concrete" if s == &"packed" and (f == &"city" or f == &"port") else &"snow"
	if f == &"city" or f == &"port":
		return &"metal" if _rng.randf() < 0.3 else &"concrete"
	return &"wood"


# ------------------------------------------------------------------ event types
func _play_set(event: StringName, def: Dictionary, paths: PackedStringArray, at: Vector3, opts: Dictionary) -> int:
	if paths.is_empty():
		return -1
	var now := _now()
	var cd := float(def.get("cooldown", 0.0))
	if cd > 0.0 and now - float(_last_play.get(event, -100.0)) < cd:
		stats["rejected"] += 1
		return -1
	var idx := _bag_pick(String(event) + str(paths.size()), paths.size())
	var s := stream(paths[idx])
	if s == null:
		return -1
	var vol := float(def.get("volume_db", 0.0)) + float(opts.get("volume_db", 0.0)) + _rng.randf_range(-1.0, 1.0) * float(def.get("vol_rand_db", 1.5))
	var pr := float(def.get("pitch_rand", 0.04))
	var pitch := float(opts.get("pitch", 1.0)) * (1.0 + _rng.randf_range(-pr, pr))
	var id := _start(event, s, def, at, vol, pitch, opts)
	if id >= 0:
		_last_play[event] = now
		for f in (def.get("follow", []) as Array):
			schedule(StringName(str(f["event"])), float(f.get("delay", 0.0)), null, at, {})
		if def.has("duck"):
			var dk: Dictionary = def["duck"]
			_duck[str(dk.get("bus", "Ambience"))] = [float(dk.get("db", -4.0)), now + float(dk.get("seconds", 1.0))]
	return id


## The gunshot: close layer (fades out from 20 to 60 m), distant layer (fades in from 15 to 45 m), the environment's
## tail (always, wider and louder with distance), then the action's follow-ups and the casing within reach.
func _play_shot(event: StringName, def: Dictionary, at: Vector3) -> int:
	var lpos := listener_position()
	if at == Vector3.INF:
		at = lpos
	var d := lpos.distance_to(at)
	var hear := float(def.get("hear", 80.0))
	var force_far := bool(def.get("force_far", false))
	if d > hear * 1.3 and not force_far:
		stats["culled"] += 1
		return -1
	var env := StringName(str(def["tail_env"])) if def.has("tail_env") else env_at(at)
	var base := float(def.get("volume_db", 0.0))
	var close_g := 0.0 if force_far else 1.0 - smoothstep(20.0, 60.0, d)
	var far_g := 1.0 if force_far else smoothstep(15.0, 45.0, d)
	var main := -1
	var reach := maxf(hear * 1.3, d + 10.0)
	if close_g > 0.02:
		main = _play_set(StringName(String(event) + ":close"), {"bus": def.get("bus", "Weapons"), "priority": def.get("priority", 90),
			"max_instances": def.get("max_instances", 6), "max_distance": reach, "unit_size": 6.0, "lpf_hz": 9000.0,
			"volume_db": base + linear_to_db(close_g), "pitch_rand": 0.035, "vol_rand_db": 1.0}, def.get("close_paths", PackedStringArray()), at, {})
	if far_g > 0.02:
		var f := _play_set(StringName(String(event) + ":far"), {"bus": def.get("bus", "Weapons"), "priority": int(def.get("priority", 90)) - 5,
			"max_instances": 4, "max_distance": reach, "unit_size": 22.0 if not force_far else 40.0, "lpf_hz": 2500.0,
			"volume_db": base + linear_to_db(far_g) - 2.0, "pitch_rand": 0.05, "vol_rand_db": 1.5}, def.get("far_paths", PackedStringArray()), at, {})
		main = f if main < 0 else main
	var tails: Dictionary = table.tails.get(str(def.get("tail", "light")), {})
	var tp: PackedStringArray = tails.get(String(env), tails.get("open", PackedStringArray()))
	if not tp.is_empty():
		_play_set(StringName(String(event) + ":tail"), {"bus": def.get("bus", "Weapons"), "priority": int(def.get("priority", 90)) - 10,
			"max_instances": 4, "max_distance": reach * 1.15, "unit_size": 14.0, "lpf_hz": 4000.0, "panning": 0.4,
			"volume_db": base - 5.0 + 5.0 * smoothstep(5.0, 60.0, d), "pitch_rand": 0.03, "vol_rand_db": 1.0}, tp, at, {})
	if d < 25.0 and not force_far:
		for fo in (def.get("follow", []) as Array):
			schedule(StringName(str(fo["event"])), float(fo.get("delay", 0.0)), null, at, {})
		if d < 12.0 and def.has("casing"):
			var c: Dictionary = def["casing"]
			var ground := at + Vector3(_rng.randf_range(-0.8, 0.8), -1.2, _rng.randf_range(-0.8, 0.8))
			var hard := HARD_SURFACES.has(surface_at(ground))
			schedule(StringName("casing_%s_%s" % [c.get("kind", "brass"), "hard" if hard else "snow"]), float(c.get("delay", 0.4)) + _rng.randf_range(0.0, 0.12), null, ground, {})
	if main >= 0:
		_last_play[event] = _now()
		last_voice[event] = main
	return main


## A footstep: the set of the surface under the foot; the walker's speed / posture set level and pitch (players);
## other walkers (wolves, deer) are lighter and quieter.
func _play_footstep(event: StringName, def: Dictionary, at: Vector3, opts: Dictionary) -> int:
	if at == Vector3.INF:
		at = listener_position()
	var walker := _player_at(at)
	var surf := StringName(str(opts.get("surface", ""))) if opts.has("surface") else surface_at(at, walker)
	var o := opts.duplicate()
	if walker != null:
		var sp := Vector2(walker.velocity.x, walker.velocity.z).length()
		if walker.crouching:
			o["volume_db"] = float(o.get("volume_db", 0.0)) - 8.0
		elif walker.running and sp > 3.0:
			o["volume_db"] = float(o.get("volume_db", 0.0)) + 3.0
			o["pitch"] = 1.05
	else:
		o["volume_db"] = float(o.get("volume_db", 0.0)) - 9.0
		o["pitch"] = 1.15
	var sets: Dictionary = def.get("surface_paths", {})
	var paths: PackedStringArray = sets.get(String(surf), sets.get("snow", PackedStringArray()))
	var id := _play_set(event, def, paths, at, o)
	if id >= 0:
		last_voice[StringName("footstep:" + String(surf))] = id
	return id


## A hit on a zombie: the weapon's impact (a melee swing of a player within 3.5 m in the last 0.7 s → blunt / sharp /
## fist, else a bullet into flesh), and the reaction (voice budget). Beyond 25 m only the impact (GDD §7.5).
func _play_hit(_event: StringName, def: Dictionary, at: Vector3) -> int:
	var hand: Variant = combat.recent_melee(at) if combat != null else null
	var ev := &"impact_flesh"
	if hand != null:
		var w := Weapons.of(StringName(str(hand)))
		if StringName(str(hand)) == Weapons.FISTS:
			ev = &"melee_hit_fist"
		elif int(w.get("kind", -1)) == DamageResolver.DamageKind.MELEE_SHARP:
			ev = &"melee_hit_sharp"
		else:
			ev = &"melee_hit_blunt"
	var id := play_ex(ev, at)
	if listener_position().distance_to(at) < 25.0 and _rng.randf() < float(def.get("reaction_chance", 0.7)):
		play_ex(StringName(str(def.get("reaction", "zombie_hurt"))), at)
	return id


# ------------------------------------------------------------------ voices
func _start(event: StringName, s: AudioStream, def: Dictionary, at: Vector3, vol: float, pitch: float, opts: Dictionary = {}) -> int:
	var mode_3d := str(def.get("mode", "3d")) == "3d" and at != Vector3.INF
	var prio := float(def.get("priority", 50))
	var group := StringName(str(def.get("group", "")))
	var dist := 0.0
	if mode_3d:
		dist = listener_position().distance_to(at)
		var maxd := float(def.get("max_distance", 40.0))
		if dist > maxd:
			stats["culled"] += 1
			return -1
		prio -= 25.0 * dist / maxd
	# voice budget of the group: the least important voice (priority − distance) makes room — among equals the
	# nearest win, and a «te he visto» (75) takes the place of a far groan (30)
	if group != &"" and table.groups.has(group):
		var gmax := int((table.groups[group] as Dictionary).get("max", 6))
		if voices_in_group(group) >= gmax:
			var weak: Node = null
			var wp := INF
			for p in _all_voices():
				var m: Dictionary = _meta.get(p.get_instance_id(), {})
				if _voice_active(p) and StringName(str(m.get("group", ""))) == group and float(m.get("prio", 0.0)) < wp:
					wp = float(m.get("prio", 0.0))
					weak = p
			if weak == null or wp >= prio:
				stats["rejected"] += 1
				return -1
			_stop_voice(weak)
	# per-event instances: the least important of the same event makes room (the oldest on a tie), never a more
	# important one
	var maxi := int(def.get("max_instances", 4))
	var same := voices_of(event)
	if same.size() >= maxi:
		var victim: Node = null
		var vp := INF
		var vt := INF
		for p in same:
			var m: Dictionary = _meta.get(p.get_instance_id(), {})
			var pp := float(m.get("prio", 0.0))
			if pp < vp - 0.5 or (absf(pp - vp) <= 0.5 and float(m.get("t0", 0.0)) < vt):
				vp = pp
				vt = float(m.get("t0", 0.0))
				victim = p
		if victim == null or vp > prio + 0.5:
			stats["rejected"] += 1
			return -1
		_stop_voice(victim)
	var v: Node = _free_voice(mode_3d, prio)
	if v == null:
		stats["rejected"] += 1
		return -1
	if mode_3d:
		var p3 := v as AudioStreamPlayer3D
		p3.stream = s
		p3.bus = StringName(str(def.get("bus", "World")))
		p3.global_position = at
		p3.max_distance = float(def.get("max_distance", 40.0))
		p3.unit_size = float(def.get("unit_size", 5.0))
		p3.attenuation_filter_cutoff_hz = float(def.get("lpf_hz", 5000.0))
		p3.attenuation_filter_db = -24.0
		p3.panning_strength = float(def.get("panning", 1.0))
		p3.volume_db = vol
		p3.pitch_scale = maxf(pitch, 0.05)
	else:
		var p2 := v as AudioStreamPlayer
		p2.stream = s
		p2.bus = StringName(str(def.get("bus", "UI")))
		p2.volume_db = vol
		p2.pitch_scale = maxf(pitch, 0.05)
	_meta[v.get_instance_id()] = {"event": event, "prio": prio, "group": group, "dist": dist, "t0": _now(),
		"until": _now() + s.get_length() / maxf(pitch, 0.05) if s.get_length() > 0.0 else INF}
	player_play(v)
	stats["played"] += 1
	last_voice[event] = v.get_instance_id()
	event_played.emit(event, v, at)
	return v.get_instance_id()


func _free_voice(mode_3d: bool, prio: float) -> Node:
	var pool: Array = _pool_3d if mode_3d else _pool_2d
	var worst: Node = null
	var wp := INF
	for p in pool:
		if not _voice_active(p):
			return p
		var m: Dictionary = _meta.get(p.get_instance_id(), {})
		var pp := float(m.get("prio", 0.0))
		if pp < wp:
			wp = pp
			worst = p
	if worst != null and wp < prio:
		_stop_voice(worst)
		stats["stolen"] += 1
		return worst
	return null


func _stop_voice(p: Node) -> void:
	if p != null:
		player_stop(p)
		_meta.erase(p.get_instance_id())


func _all_voices() -> Array:
	var out: Array = []
	out.append_array(_pool_3d)
	out.append_array(_pool_2d)
	return out


func _bag_pick(key: String, n: int) -> int:
	if n <= 1:
		return 0
	var bag: Array = _bags.get(key, [])
	if bag.is_empty():
		for i in n:
			bag.append(i)
		bag.shuffle()
		if int(bag[0]) == int(_last_idx.get(key, -1)):
			bag.push_back(bag.pop_front())
	var i := int(bag.pop_front())
	_bags[key] = bag
	_last_idx[key] = i
	return i


func _player_at(p: Vector3) -> Player:
	for n in get_tree().get_nodes_in_group("player"):
		var pl := n as Player
		if pl != null and Vector2(pl.global_position.x - p.x, pl.global_position.z - p.z).length() < 0.8:
			return pl
	return null


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# ------------------------------------------------------------------ per frame
func _process(delta: float) -> void:
	if not enabled:
		return
	_update_listener()
	var now := _now()
	if not _pending.is_empty():
		var keep: Array = []
		for e in _pending:
			if now >= float(e["t"]):
				var node: Node3D = e["node"]
				var at: Vector3 = node.global_position if node != null and is_instance_valid(node) and node.is_inside_tree() else e["at"]
				play_ex(e["event"], at, e["opts"])
			else:
				keep.append(e)
		_pending = keep
	if _hb_intensity > 0.01 and now >= _hb_next:
		play_ex(&"heartbeat", Vector3.INF, {"volume_db": lerpf(-16.0, -4.0, _hb_intensity)})
		_hb_next = now + 60.0 / lerpf(68.0, 140.0, _hb_intensity)
	# ducks (ui_zone_discover −4 dB 1.5 s, the P0 cues)
	for bus in _duck.keys():
		var dk: Array = _duck[bus]
		var idx := AudioServer.get_bus_index(bus)
		if idx < 0:
			_duck.erase(bus)
			continue
		var base := float(BUS_BASE_DB.get(bus, 0.0)) + linear_to_db(maxf(AudioSettings.get_instance().get_value("ambience") if bus == "Ambience" else 1.0, 0.001))
		if now >= float(dk[1]):
			AudioServer.set_bus_volume_db(idx, base)
			_duck.erase(bus)
		else:
			AudioServer.set_bus_volume_db(idx, base + float(dk[0]) * clampf((float(dk[1]) - now) / 0.4, 0.0, 1.0))
	if not _prewarm.is_empty():   # a few small files per frame after world_ready (≈ 3 s for the whole set)
		for i in mini(3, _prewarm.size()):
			stream(_prewarm[_prewarm.size() - 1])
			_prewarm.remove_at(_prewarm.size() - 1)


func _update_listener() -> void:
	var lp := GameFlow.local_player() as Node3D
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp != null else null
	if lp != null and lp.is_inside_tree():
		var pos := lp.global_position + Vector3(0.0, LISTENER_HEIGHT, 0.0)
		var fwd := Vector3.FORWARD
		if cam != null:
			fwd = -cam.global_basis.z
			fwd.y = 0.0
			if fwd.length() < 0.01:
				fwd = cam.global_basis.y
				fwd.y = 0.0
		fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
		listener.global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), pos)
		if not listener.is_current():
			listener.make_current()
	elif cam != null:
		listener.global_transform = cam.global_transform
		if listener.is_current():
			listener.clear_current()
	if _reverb_area != null:
		_reverb_area.global_position = listener.global_position


func _start_prewarm() -> void:
	if table == null:
		return
	var seen := {}
	for ev in table.events:
		for p in table.paths_of(ev):
			# one-shots only: loops and beds load when they start (they are the big files)
			if not seen.has(p) and not _cache.has(p) and not bool(table.file_info(p).get("loop", false)):
				seen[p] = true
				_prewarm.append(p)
