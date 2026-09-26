extends SceneTree
## Server CPU under a horde (PLAN M4 acceptance, R1; ARQ v2 §16.6 "tick ≤ 8 ms"): a headless DEDICATED server (real
## ENet listener, no client branch) with 4 bot players walking around the hunter's clearing and 200 zombies around
## them (up to the 150 L0 bodies + L1 records), the director and the residents off so the load is fixed. The bots
## swing at the nearest zombie every second (melee, deaths, respawns) and ZombieNet builds their packets as if they
## were peers (bench mode: counted, not sent). Measures every tick the server's busy time, the ZombieSystem's and
## ZombieNet's own µs, move_and_slide, route queries and the bytes per bot. Writes tests/perf/horde.json,
## checks tests/perf_budgets.json "perf_horde" (median tick ≤ 8 ms; p99 is reported).
## Usage: tests/run_perf_horde.sh [--zombies=200] [--seconds=20] [--nocheck]
## Experiments: HORDE_NOBENCH=1 (no packet building for the bots), HORDE_BODIES=n (cap the L0 body pool).
## The tick is the server's busy time per physics tick (probes from the first physics callback to the last process
## callback); the engine's TIME_*_PROCESS monitors are maxima over one second and are only reported.

var _body: RefCounted


func _initialize() -> void:
	var opts := {"zombies": 200, "seconds": 20.0, "check": true, "out": "tests/perf/horde.json", "port": 7817}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--zombies="):
			opts["zombies"] = int(a.substr(10))
		elif a.begins_with("--seconds="):
			opts["seconds"] = float(a.substr(10))
		elif a.begins_with("--out="):
			opts["out"] = a.substr(6)
		elif a.begins_with("--port="):
			opts["port"] = int(a.substr(7))
		elif a == "--nocheck":
			opts["check"] = false
	var script: GDScript = load("res://tests/perf_horde_steps.gd")
	if script == null or not script.can_instantiate():
		print("FAIL: cannot load perf_horde_steps.gd")
		quit(1)
		return
	_body = script.new()
	_body.run(self, opts)
	var t := create_timer(float(opts["seconds"]) + 240.0)
	t.timeout.connect(func() -> void:
		print("FAIL: perf horde watchdog timeout")
		quit(1))
