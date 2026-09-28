extends SceneTree
## M6a street bench runner (tests/street_bench, the test street of Santa María del Puerto). The typed body lives in
## street_bench_steps.gd, loaded at runtime after the autoloads exist. Needs a real renderer (xvfb + Compatibility /
## llvmpipe, or Forward+ / lavapipe with RENDER=forward):
##   tests/run_street_bench.sh gate     citycut probe on the street (player >= 99 %, zombies >= 95 % readable) +
##                                      interior shadow of a cut house and of the cabin_small POI (+-5 %) (blocking)
##   tests/run_street_bench.sh shots    street_day, street_night, house_inside (bench versions)
## Args after "++": --mode=gate|shots --preset=name --out=path --json=path
## Exit code 0 = pass.

var _body: RefCounted


func _initialize() -> void:
	var opts := {"mode": "gate", "preset": "street_day", "out": "/tmp/ventisca_street.png", "json": ""}
	for a in OS.get_cmdline_user_args():
		for k in ["mode", "preset", "out", "json"]:
			if a.begins_with("--%s=" % k):
				opts[k] = a.substr(k.length() + 3)
	Engine.max_fps = 0
	var script: GDScript = load("res://tests/street_bench_steps.gd")
	if script == null or not script.can_instantiate():
		print("FAIL: cannot load street_bench_steps.gd")
		quit(1)
		return
	_body = script.new()
	_body.run(self, opts)
	var t := create_timer(1500.0)
	t.timeout.connect(func() -> void:
		print("FAIL: street bench watchdog timeout")
		quit(1))
