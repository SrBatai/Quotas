extends SceneTree
## M5 pure-function gate: loot rolls (determinism per seed + container wid, tables, nominal caps, personal bags,
## restock) and firearms (table rows vs GDD §7.6, spread model: closes in 0.8 s / opens when moving / recoil recovery,
## bands, damage falloff, seeded pellet yaws, reload times from data/anim_events.json, the hitscan segment test and the
## player hit history used for lag compensation), weights and encumbrance thresholds.
## Run: godot --headless --path . -s tests/unit/m5_units_test.gd  → "== N checks, ALL PASSED" / exit 1.

var _body: RefCounted


func _initialize() -> void:
	var script: GDScript = load("res://tests/unit/m5_units_steps.gd")
	if script == null or not script.can_instantiate():
		print("FAIL: cannot load m5_units_steps.gd")
		quit(1)
		return
	_body = script.new()
	_body.run(self)
	var t := create_timer(60.0)
	t.timeout.connect(func() -> void:
		print("FAIL: M5 unit test watchdog timeout")
		quit(1))
