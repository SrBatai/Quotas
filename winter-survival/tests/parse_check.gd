extends SceneTree
## Loads every .gd under res://scripts and res://tests and reports scripts that fail to compile.


func _initialize() -> void:
	var failed := 0
	var total := 0
	for path in _collect("res://scripts") + _collect("res://tests"):
		total += 1
		var s := load(path)
		if s == null or not (s as Script).can_instantiate() and not (s as Script).is_tool():
			# Scripts with class_name-only static usage still instantiate fine; null means a parse error.
			if s == null:
				print("PARSE FAIL: ", path)
				failed += 1
	print("Parse check: %d scripts, %d failed" % [total, failed])
	quit(1 if failed > 0 else 0)


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
