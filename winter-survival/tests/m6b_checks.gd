extends SceneTree
## M6b checks, headless (functional, no GPU): the settlement generator and the hand-made POIs (Settlements /
## SettlementGen: La Herrería with 15–20 buildings and ≥ 6 enterable, OBB lots of 400–900 m², 1–2 branches, reserved
## uses, the plan hash equal on a rebuild and across three seeds' rules), the terrain stamps (level pads at the street,
## streets pinned to the Valdenieve road, everything inside the sites' bounds, the scatter kept off the buildings),
## the residents by land use (per chunk 3–12, spots inside / outside the buildings, PopulationTable), the zones
## (the sawmill registered, the village / gas station / farm titles), the loot tables by use, and the built chunks
## (SettlementChunk: KitBuildings with locked doors, the shop alarm, loot remaps, car / dumpster containers, props,
## lamps). The typed body lives in m6b_steps.gd and is loaded at runtime, after the autoloads exist.
##   godot --headless --path . -s tests/m6b_checks.gd
## Prints "== m6b checks: N checks, M failed" and exits 1 on any failure.

var _body: RefCounted


func _initialize() -> void:
	var script: GDScript = load("res://tests/m6b_steps.gd")
	if script == null or not script.can_instantiate():
		print("FAIL: cannot load m6b_steps.gd")
		quit(1)
		return
	_body = script.new()
	_body.run(self)
	var t := create_timer(300.0)
	t.timeout.connect(func() -> void:
		print("FAIL: m6b checks watchdog timeout")
		quit(1))
