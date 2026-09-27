extends SceneTree
## City bench runner (W0 + G2a). The typed body lives in city_bench_steps.gd and is loaded at runtime, after the
## autoloads exist. Needs a real renderer (xvfb + Compatibility/llvmpipe or Forward+/lavapipe):
##   tests/run_city_bench.sh gate            visibility gate (blocking) + draw-call budgets (blocking) + timings (info)
##   tests/run_city_bench.sh shots [dir]     presets city_day, city_night, city_cut, city_inside, city_rooftop,
##                                           city_hlod, profile_compare
## Args after "++": --mode=gate|perf|shots --preset=name --out=path --json=path --budgets=res://tests/city_bench_budgets.json
## --frames=24 (per perf sample) --rounds=1 (interleaved perf rounds; the report takes the median)
## Exit code 0 = pass.

var _body: RefCounted


func _initialize() -> void:
	var opts := {"mode": "gate", "preset": "city_day", "out": "/tmp/ventisca_city.png", "json": "",
		"budgets": "res://tests/city_bench_budgets.json", "frames": 24, "rounds": 1}
	for a in OS.get_cmdline_user_args():
		for k in ["mode", "preset", "out", "json", "budgets", "frames", "rounds"]:
			if a.begins_with("--%s=" % k):
				opts[k] = a.substr(k.length() + 3)
	Engine.max_fps = 0
	var script: GDScript = load("res://tests/city_bench_steps.gd")
	if script == null or not script.can_instantiate():
		print("FAIL: cannot load city_bench_steps.gd")
		quit(1)
		return
	_body = script.new()
	_body.run(self, opts)
	var t := create_timer(1500.0)
	t.timeout.connect(func() -> void:
		print("FAIL: city bench watchdog timeout")
		quit(1))
