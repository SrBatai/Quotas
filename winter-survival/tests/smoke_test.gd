extends SceneTree
## Headless smoke test runner (ARCHITECTURE §21.1). Run: godot --headless --path . -s tests/smoke_test.gd
## The typed test body lives in smoke_steps.gd and is loaded here at runtime, after the autoloads exist.

var _body: RefCounted


func _initialize() -> void:
	Engine.max_fps = 60
	var script: GDScript = load("res://tests/smoke_steps.gd")
	if script == null or not script.can_instantiate():
		print("FAIL: cannot load smoke_steps.gd")
		quit(1)
		return
	_body = script.new()
	_body.run(self)
	# watchdog: a crashed coroutine must not hang the runner
	var t := create_timer(240.0)
	t.timeout.connect(func() -> void:
		print("FAIL: smoke test watchdog timeout")
		quit(1))
