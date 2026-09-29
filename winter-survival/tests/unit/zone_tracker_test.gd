extends SceneTree
## H2 zone gate (PLAN v3.8.1 H2, C35 / C36; docs/research/10_hud_ux.md appendix §6.1 and §8.9): LocationInfo data
## migrated from PoiRegistry (W1 regions incl. the reserved ones), ZoneTracker hysteresis (a zigzag over a border = 0
## changes, ≥ 12 m inside for 1.5 s = 1 change), hierarchy (district over city), cooldowns (90 s per zone, 20 s
## between cards, a queue of 1), combat and P0 deferral, the P3 exit line, the highway sign for a scripted fast mover
## (> 40 km/h on a road), zone_entered and the camera profile, the titles at W1's 20 test points, the title / sign
## timelines, the discovery store (schema 3 on the memory / file / SQLite backends, migration from schema 2), the
## placeholder sound and the names test (C36: no «Albarr» / «Albar» word in data/, scripts/, scenes/).
## Run: godot --headless --path . -s tests/unit/zone_tracker_test.gd  → "== N checks, ALL PASSED" / exit 1.

var _body: RefCounted


func _initialize() -> void:
	var script: GDScript = load("res://tests/unit/zone_tracker_steps.gd")
	if script == null or not script.can_instantiate():
		print("FAIL: cannot load zone_tracker_steps.gd")
		quit(1)
		return
	_body = script.new()
	_body.run(self)
	var t := create_timer(120.0)
	t.timeout.connect(func() -> void:
		print("FAIL: zone tracker test watchdog timeout")
		quit(1))
