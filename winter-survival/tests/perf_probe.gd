extends SceneTree
## Performance probe runner (ARQ v2 §18). The typed body lives in perf_probe_steps.gd and is loaded at
## runtime, after the autoloads exist. Needs a real renderer (draw calls are 0 under --headless):
##   xvfb-run -a godot --path . --rendering-method gl_compatibility -s tests/perf_probe.gd ++ \
##       --out=tests/perf/last.json [--budgets=tests/perf_budgets.json] [--label=after] [--placeholders] [--nocheck]
## Exit code 0 = within budget (or --nocheck), 1 = over budget / error.

var _body: RefCounted


func _initialize() -> void:
	var opts := {"out": "tests/perf/last.json", "budgets": "res://tests/perf_budgets.json", "label": "",
		"placeholders": false, "check": true}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			opts["out"] = a.substr(6)
		elif a.begins_with("--budgets="):
			opts["budgets"] = a.substr(10)
		elif a.begins_with("--label="):
			opts["label"] = a.substr(8)
		elif a == "--placeholders":
			opts["placeholders"] = true
		elif a == "--nocheck":
			opts["check"] = false
	Engine.max_fps = 0  # uncapped: frame time measures the real cost
	var script: GDScript = load("res://tests/perf_probe_steps.gd")
	if script == null or not script.can_instantiate():
		print("FAIL: cannot load perf_probe_steps.gd")
		quit(1)
		return
	_body = script.new()
	_body.run(self, opts)
	var t := create_timer(300.0)
	t.timeout.connect(func() -> void:
		print("FAIL: perf probe watchdog timeout")
		quit(1))
