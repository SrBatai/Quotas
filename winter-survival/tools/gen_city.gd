extends SceneTree
## Altavega city generator (C1; doc 09 §4.5; PLAN v3.8.2 C1): data/world/city/districts.json (hand-authored rules and
## fixed content) → data/world/city/altavega_lots.json (city_version 1), read by CityLots at run time.
##   godot --headless --path . -s tools/gen_city.gd                 # writes the lot file, prints the stats
##   godot --headless --path . -s tools/gen_city.gd ++ --check      # rebuilds in memory, compares the bytes (CI)
##   godot --headless --path . -s tools/gen_city.gd ++ --out=/tmp/x.json
## The logic lives in scripts/world/city/city_gen.gd (CityGen), loaded at run time (after the autoloads exist).

const IN_PATH := "res://data/world/city/districts.json"
const OUT_PATH := "res://data/world/city/altavega_lots.json"
## The height function the generator checks slopes and water with (the layout never depends on the world seed:
## the city relief is ±1 m, far below the families' skirts).
const CHECK_SEED := 1337

var _started := false


func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	_run()
	return false


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	var args := OS.get_cmdline_user_args()
	var check := args.has("--check")
	var out_path := OUT_PATH
	for a in args:
		if a.begins_with("--out="):
			out_path = a.substr(6)
	var src: Variant = JSON.parse_string(FileAccess.get_file_as_string(IN_PATH))
	if not (src is Dictionary):
		print("gen_city: cannot read %s" % IN_PATH)
		quit(1)
		return
	var macro_script: GDScript = load("res://scripts/world/terrain/macro_map.gd")
	var hf_script: GDScript = load("res://scripts/world/terrain/height_function.gd")
	var macro: Variant = macro_script.call("load_default")
	var hf: Variant = hf_script.call("create", CHECK_SEED, macro)
	var gen_script: GDScript = load("res://scripts/world/city/city_gen.gd")
	var gen: Variant = gen_script.new()
	var out: Dictionary = gen.call("run", src, hf)
	var text: String = gen_script.call("serialize", out)
	var probs: PackedStringArray = gen.get("problems")
	for p in probs:
		print("gen_city problem: %s" % p)
	print("gen_city: %s" % JSON.stringify(out.get("stats", {})))
	print("gen_city: %d bytes, sha256 %s (%d ms)" % [text.length(), text.sha256_text(), Time.get_ticks_msec() - t0])
	if check:
		var cur := FileAccess.get_file_as_string(OUT_PATH)
		var ok := cur == text
		print("gen_city --check: %s" % ("identical" if ok else "DIFFERENT (run tools/gen_city.gd and commit the lot file)"))
		quit(0 if ok and probs.is_empty() else 1)
		return
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		print("gen_city: cannot write %s" % out_path)
		quit(1)
		return
	f.store_string(text)
	f.close()
	print("gen_city: wrote %s" % out_path)
	quit(0 if probs.is_empty() else 1)
