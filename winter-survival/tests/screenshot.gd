extends SceneTree
## Screenshot runner (xvfb + Compatibility). Args after "++": --preset=day|dusk|night|blizzard|interior|menu --out=path.png
## The typed body lives in screenshot_steps.gd and is loaded at runtime, after the autoloads exist.

var _body: RefCounted


func _initialize() -> void:
	var preset := "day"
	var out_path := "/tmp/ventisca_shot.png"
	var flags: Array[String] = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--preset="):
			preset = a.substr(9)
		elif a.begins_with("--out="):
			out_path = a.substr(6)
		elif a.begins_with("--"):
			flags.append(a.substr(2))
	Engine.max_fps = 60
	var script: GDScript = load("res://tests/screenshot_steps.gd")
	if script == null or not script.can_instantiate():
		print("FAIL: cannot load screenshot_steps.gd")
		quit(1)
		return
	_body = script.new()
	_body.flags = flags
	_body.run(self, preset, out_path)
	var t := create_timer(600.0)
	t.timeout.connect(func() -> void:
		print("FAIL: screenshot watchdog timeout")
		quit(1))
