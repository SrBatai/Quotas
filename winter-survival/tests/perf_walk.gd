extends SceneTree
## Streaming perf walk (PLAN M3 acceptance, ARQ v2 §18): the local player is moved along a fixed route at
## 25 m/s (car speed, R4; 2.26 km) through forest, the N‑140 and back while the world streams around it. Measures every
## frame: frame time, the streamer's main-thread cost (budget 2 ms/frame), frames over 33 ms and whether streaming
## caused them, missing ground under the player, generation time in the workers, loaded chunks, memory (RSS).
## Two modes (tests/run_perf_walk.sh):
##   render: xvfb + a real renderer (Compatibility on llvmpipe by default): frame times, GPU-side upload cost, memory.
##   --cpu:  headless (dummy renderer) with the client's visual streaming path forced on: the streaming CPU cost per
##           frame without a software GPU preempting the main thread — the gate for the 2 ms/frame budget.
##   --nothreads: generation on the main thread, one chunk per refresh (the web nothreads build; informative).
## Exit 0 = within tests/perf_budgets.json "perf_walk" (render) / "perf_walk_cpu" (--cpu).

var _body: RefCounted


func _initialize() -> void:
	var opts := {"out": "tests/perf/walk.json", "budgets": "res://tests/perf_budgets.json", "speed": 25.0, "check": true, "cpu": false}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			opts["out"] = a.substr(6)
		elif a.begins_with("--speed="):
			opts["speed"] = float(a.substr(8))
		elif a == "--nocheck":
			opts["check"] = false
		elif a == "--cpu":
			opts["cpu"] = true
		elif a == "--nothreads":
			opts["nothreads"] = true
	Engine.max_fps = 0
	var script: GDScript = load("res://tests/perf_walk_steps.gd")
	if script == null or not script.can_instantiate():
		print("FAIL: cannot load perf_walk_steps.gd")
		quit(1)
		return
	_body = script.new()
	_body.run(self, opts)
	var t := create_timer(900.0)
	t.timeout.connect(func() -> void:
		print("FAIL: perf walk watchdog timeout")
		quit(1))
