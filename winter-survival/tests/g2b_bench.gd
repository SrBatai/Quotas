extends SceneTree
## G2b bench (xvfb; tests/run_g2b_bench.sh). The typed body lives in g2b_bench_steps.gd, loaded after the autoloads:
##   --mode=ratio   the C0 city scene (the survivor on the Gran Vía in front of LT-01, like perf_probe --scene=altavega_c0)
##                  day 11:00 clear vs the same view in a blizzard (volumetric fog on `alto`, heavy snow, snow snakes,
##                  overcast, LUT) in interleaved rounds: frame-time ratio (PLAN G2b: ≤ +25 % on lavapipe), plus the
##                  night city and a night blizzard for information; and the LUT blend's CPU per frame in the real loop
##   --mode=depth   the same city view at night, at dusk and in a blizzard, rendered as the game does, without fog and
##                  with the fog saturated: how far the fog moves the far third of the frame toward its colour against
##                  the near third (depth); written to --json so the Compatibility and Forward+ runs can be compared
##                  (`compat`, without volumetrics, keeps the depth)
## Options: --json=path --rounds=n --shots=dir (depth mode saves its captures there)

var _body: RefCounted


func _initialize() -> void:
	var opts := {"mode": "ratio", "json": "/tmp/ventisca_g2b_bench.json", "rounds": 3, "shots": ""}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mode="):
			opts["mode"] = a.substr(7)
		elif a.begins_with("--json="):
			opts["json"] = a.substr(7)
		elif a.begins_with("--rounds="):
			opts["rounds"] = int(a.substr(9))
		elif a.begins_with("--shots="):
			opts["shots"] = a.substr(8)
	Engine.max_fps = 0
	var script: GDScript = load("res://tests/g2b_bench_steps.gd")
	if script == null or not script.can_instantiate():
		print("FAIL: cannot load g2b_bench_steps.gd")
		quit(1)
		return
	_body = script.new()
	_body.run(self, opts)
	var t := create_timer(1500.0)
	t.timeout.connect(func() -> void:
		print("FAIL: g2b bench watchdog timeout")
		quit(1))
