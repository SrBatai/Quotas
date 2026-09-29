extends SceneTree
## H1 HUD checks alone (the same tests/hud_steps.gd the smoke test runs at its end), for quick iteration:
##   godot --headless --path . -s tests/hud_test.gd
## The body is loaded at runtime (autoloads first), like the smoke test.

var _body: RefCounted


func _initialize() -> void:
	Engine.max_fps = 60
	var script: GDScript = load("res://tests/hud_test_body.gd")
	if script == null or not script.can_instantiate():
		print("FAIL: cannot load hud_test_body.gd")
		quit(1)
		return
	_body = script.new()
	_body.run(self)
	var t := create_timer(180.0)
	t.timeout.connect(func() -> void:
		print("FAIL: hud test watchdog timeout")
		quit(1))
