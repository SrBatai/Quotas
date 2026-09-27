extends SceneTree
## W0 + G2a rendering checks, headless (functional, no GPU): the «corte urbano» maths and globals, the city
## building contract and its shadow-preserving cutaway, the legacy POI cutaway (unchanged behaviour), camera
## profiles, city lights, silhouettes, HLOD, snow / wind globals, Quality keys and the cursor ray through a cut.
## The typed body lives in render_steps.gd and is loaded at runtime, after the autoloads exist.
##   godot --headless --path . -s tests/render_checks.gd
## Prints "== render checks: N checks, M failed" and exits 1 on any failure.

var _body: RefCounted


func _initialize() -> void:
	var script: GDScript = load("res://tests/render_steps.gd")
	if script == null or not script.can_instantiate():
		print("FAIL: cannot load render_steps.gd")
		quit(1)
		return
	_body = script.new()
	_body.run(self)
	var t := create_timer(240.0)
	t.timeout.connect(func() -> void:
		print("FAIL: render checks watchdog timeout")
		quit(1))
