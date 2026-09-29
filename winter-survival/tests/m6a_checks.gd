extends SceneTree
## M6a checks, headless (functional, no GPU): the test street (KitStreet / KitBuilding: root metadata, doors, window
## boxes, containers per storey, signs), the CutawayManager (inside detection per storey, roof and upper storeys
## hidden shadow-preserving, camera-facing facades -> stubs, back to whole on leaving, the M3 forest POIs through
## CutawayManager.attach), KitDoor (server toggle, swing inward, collision follows the leaf, delta fields, snap from
## a delta) and SignText (glyph coverage of the street texts, width fits the boards).
## The typed body lives in m6a_steps.gd and is loaded at runtime, after the autoloads exist.
##   godot --headless --path . -s tests/m6a_checks.gd
## Prints "== m6a checks: N checks, M failed" and exits 1 on any failure.

var _body: RefCounted


func _initialize() -> void:
	var script: GDScript = load("res://tests/m6a_steps.gd")
	if script == null or not script.can_instantiate():
		print("FAIL: cannot load m6a_steps.gd")
		quit(1)
		return
	_body = script.new()
	_body.run(self)
	var t := create_timer(240.0)
	t.timeout.connect(func() -> void:
		print("FAIL: m6a checks watchdog timeout")
		quit(1))
