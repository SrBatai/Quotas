extends SceneTree
## G2b «Atmósfera» checks, headless (functional, no GPU): the LUTs and their CPU blend (exact, ≤ 0.1 ms of work per
## frame, nothing at rest), the grade weights by hour / cloud / blizzard / city / blackout / fire, the
## presentation-only overcast (deterministic, clear first day), the DayNight hooks (overcast keys, wind, fog layers,
## volumetric fog only on `alto` and only in a blizzard or at night, the compat depth boost), the thaw sources, the
## wind materials, the sprites and the render-side life (beacons, smoke columns, flocks, cables).
## The typed body lives in g2b_steps.gd and is loaded at runtime, after the autoloads exist.
##   godot --headless --path . -s tests/g2b_checks.gd
## Prints "== g2b checks: N checks, M failed" and exits 1 on any failure.

var _body: RefCounted


func _initialize() -> void:
	var script: GDScript = load("res://tests/g2b_steps.gd")
	if script == null or not script.can_instantiate():
		print("FAIL: cannot load g2b_steps.gd")
		quit(1)
		return
	_body = script.new()
	_body.run(self)
	var t := create_timer(240.0)
	t.timeout.connect(func() -> void:
		print("FAIL: g2b checks watchdog timeout")
		quit(1))
