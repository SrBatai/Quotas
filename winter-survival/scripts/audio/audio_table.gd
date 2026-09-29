class_name AudioTable
extends RefCounted
## S1 audio event table (data/audio_events.json, docs/AUDIO.md §4) resolved against the build manifest
## (assets/audio/manifest.json, written by tools/audio/build_audio.py): every event's `files` / `close` / `far` /
## `surfaces` / `weights` globs become lists of res:// paths. Pure data: AudioManager plays from it, the unit test
## (tests/unit/audio_test.gd) validates it, the dedicated server never loads it.

const TABLE_PATH := "res://data/audio_events.json"
const MANIFEST_PATH := "res://assets/audio/manifest.json"
const ROOT := "res://assets/audio/"
const TYPES := ["simple", "shot", "footstep", "surface", "hit", "melee_swing", "stinger", "layer"]
const MODES := ["2d", "3d"]
const BUSES := ["Master", "Music", "SFX", "Weapons", "Creatures", "Foley", "World", "Ambience", "UI"]

var ok: bool = false
var data: Dictionary = {}
var manifest: Dictionary = {}
var defaults: Dictionary = {}
var events: Dictionary = {}       # StringName -> Dictionary (defaults merged, `type` set)
var groups: Dictionary = {}       # StringName -> {max}
var silent: Dictionary = {}       # StringName -> reason
var anim: Dictionary = {}         # clip -> {anim event -> audio event}
var ambience: Dictionary = {}
var tails: Dictionary = {}        # weight -> env -> Array[String]
var weights: Dictionary = {}      # hand item -> light | medium | heavy
var _files: PackedStringArray = PackedStringArray()   # manifest keys (relative to ROOT)
var _glob_cache: Dictionary = {}


static func load_default() -> AudioTable:
	var t := AudioTable.new()
	t.load_from(TABLE_PATH, MANIFEST_PATH)
	return t


func load_from(table_path: String, manifest_path: String) -> void:
	ok = false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(table_path)) if FileAccess.file_exists(table_path) else null
	if not parsed is Dictionary:
		push_warning("AudioTable: cannot read %s" % table_path)
		return
	data = parsed
	var man: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path)) if FileAccess.file_exists(manifest_path) else null
	manifest = man if man is Dictionary else {}
	_files = PackedStringArray((manifest.get("files", {}) as Dictionary).keys())
	defaults = data.get("defaults", {})
	for g in (data.get("groups", {}) as Dictionary):
		groups[StringName(g)] = data["groups"][g]
	for s in (data.get("silent", {}) as Dictionary):
		silent[StringName(s)] = str(data["silent"][s])
	anim = data.get("anim", {})
	ambience = data.get("ambience", {})
	weights = data.get("weights", {})
	var raw: Dictionary = data.get("events", {})
	for name in raw:
		var d: Dictionary = defaults.duplicate()
		d.merge(raw[name], true)
		if not d.has("type"):
			d["type"] = "simple"
		for key in ["files", "close", "far"]:
			if d.has(key):
				d[key + "_paths"] = resolve(d[key])
		if d.has("surfaces"):
			var sp := {}
			for s in (d["surfaces"] as Dictionary):
				sp[s] = resolve(d["surfaces"][s])
			d["surface_paths"] = sp
		if d.has("weights"):
			var wp := {}
			for w in (d["weights"] as Dictionary):
				wp[w] = resolve(d["weights"][w])
			d["weight_paths"] = wp
		events[StringName(name)] = d
	for w in (data.get("tails", {}) as Dictionary):
		tails[w] = {}
		for env in (data["tails"][w] as Dictionary):
			tails[w][env] = resolve(data["tails"][w][env])
	ok = true


## A `files` value (a path, a glob with `*`, or an Array of them, relative to assets/audio/) → res:// paths that the
## manifest lists, sorted. Literal paths that are not in the manifest are kept only when the file exists.
func resolve(spec: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	var specs: Array = spec if spec is Array else [spec]
	for s in specs:
		var p := str(s)
		if _glob_cache.has(p):
			out.append_array(_glob_cache[p])
			continue
		var found := PackedStringArray()
		if p.contains("*"):
			for f in _files:
				# a trimmed export (the Web subset, docs/AUDIO.md §9) lists files it does not carry: skip them
				if f.match(p) and ResourceLoader.exists(ROOT + f):
					found.append(ROOT + f)
			found.sort()
		elif _files.has(p) or ResourceLoader.exists(ROOT + p):
			found.append(ROOT + p)
		_glob_cache[p] = found
		out.append_array(found)
	return out


func has_event(ev: StringName) -> bool:
	return events.has(ev)


## Every path an event can play (for the tests and the prewarm).
func paths_of(ev: StringName) -> PackedStringArray:
	var d: Dictionary = events.get(ev, {})
	var out := PackedStringArray()
	for key in ["files_paths", "close_paths", "far_paths"]:
		if d.has(key):
			out.append_array(d[key])
	for key in ["surface_paths", "weight_paths"]:
		if d.has(key):
			for k in (d[key] as Dictionary):
				out.append_array(d[key][k])
	if d.get("type", "") == "shot":
		var t: Dictionary = tails.get(str(d.get("tail", "light")), {})
		for env in t:
			out.append_array(t[env])
	return out


func file_info(path: String) -> Dictionary:
	return (manifest.get("files", {}) as Dictionary).get(path.trim_prefix(ROOT), {})


## Validation errors of the table (empty = valid): unknown types / modes / buses / groups, events with nothing to
## play, anim entries pointing at unknown events, beds / layers / one-shots of the ambience that do not resolve.
func validate() -> PackedStringArray:
	var errs := PackedStringArray()
	if not ok:
		errs.append("table not loaded")
		return errs
	for ev in events:
		var d: Dictionary = events[ev]
		var ty := str(d.get("type", "simple"))
		if not TYPES.has(ty):
			errs.append("%s: unknown type %s" % [ev, ty])
		if not MODES.has(str(d.get("mode", "3d"))):
			errs.append("%s: unknown mode %s" % [ev, d.get("mode")])
		if not BUSES.has(str(d.get("bus", "World"))):
			errs.append("%s: unknown bus %s" % [ev, d.get("bus")])
		if d.has("group") and not groups.has(StringName(str(d["group"]))):
			errs.append("%s: unknown group %s" % [ev, d["group"]])
		if int(d.get("priority", 50)) < 0 or int(d.get("priority", 50)) > 100:
			errs.append("%s: priority out of 0..100" % ev)
		if float(d.get("max_distance", 1.0)) <= 0.0 or float(d.get("unit_size", 1.0)) <= 0.0:
			errs.append("%s: max_distance / unit_size must be > 0" % ev)
		match ty:
			"simple", "stinger":
				if (d.get("files_paths", PackedStringArray()) as PackedStringArray).is_empty():
					errs.append("%s: no file matches %s" % [ev, d.get("files")])
			"shot":
				if (d.get("close_paths", PackedStringArray()) as PackedStringArray).is_empty() or (d.get("far_paths", PackedStringArray()) as PackedStringArray).is_empty():
					errs.append("%s: close / far layers do not resolve" % ev)
				var t: Dictionary = tails.get(str(d.get("tail", "")), {})
				for env in ["forest", "open", "city", "interior"]:
					if (t.get(env, PackedStringArray()) as PackedStringArray).is_empty():
						errs.append("%s: no %s tail for weight %s" % [ev, env, d.get("tail")])
			"footstep", "surface":
				var sp: Dictionary = d.get("surface_paths", {})
				if sp.is_empty():
					errs.append("%s: no surfaces" % ev)
				for s in sp:
					if (sp[s] as PackedStringArray).is_empty():
						errs.append("%s: surface %s does not resolve" % [ev, s])
			"melee_swing":
				for w in ["light", "medium", "heavy"]:
					if ((d.get("weight_paths", {}) as Dictionary).get(w, PackedStringArray()) as PackedStringArray).is_empty():
						errs.append("%s: weight %s does not resolve" % [ev, w])
			"hit":
				if not events.has(StringName(str(d.get("reaction", "")))):
					errs.append("%s: reaction event %s missing" % [ev, d.get("reaction")])
		for f in (d.get("follow", []) as Array):
			if not events.has(StringName(str(f.get("event", "")))):
				errs.append("%s: follow event %s missing" % [ev, f.get("event")])
	for clip in anim:
		for k in (anim[clip] as Dictionary):
			if not events.has(StringName(str(anim[clip][k]))):
				errs.append("anim %s.%s: event %s missing" % [clip, k, anim[clip][k]])
	for kind in ["beds", "layers"]:
		for b in (ambience.get(kind, {}) as Dictionary):
			if resolve(ambience[kind][b]).is_empty():
				errs.append("ambience %s %s: %s missing" % [kind, b, ambience[kind][b]])
	for fam in (ambience.get("oneshots", {}) as Dictionary):
		for o in (ambience["oneshots"][fam] as Array):
			if not events.has(StringName(str(o.get("event", "")))):
				errs.append("ambience %s one-shot: event %s missing" % [fam, o.get("event")])
	for s in silent:
		if events.has(s):
			errs.append("%s: both silent and in the table" % s)
	return errs
