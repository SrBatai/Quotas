extends SceneTree
## H1 gate: idle HUD coverage ≤ 3 % at 1920 × 1080 (docs/research/10_hud_ux.md §V.5 / §V.8). Run under xvfb:
##   tests/run_hud_coverage.sh [--moments=idle,action,zone,blizzard,info] [--out=dir]
## The typed body lives in hud_coverage_steps.gd (loaded at runtime, after the autoloads exist).

var _body: RefCounted


func _initialize() -> void:
	var moments := "idle"
	var out_dir := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--moments="):
			moments = a.substr(10)
		elif a.begins_with("--out="):
			out_dir = a.substr(6)
	var script: GDScript = load("res://tests/hud_coverage_steps.gd")
	if script == null or not script.can_instantiate():
		print("FAIL: cannot load hud_coverage_steps.gd")
		quit(1)
		return
	_body = script.new()
	_body.run(self, moments.split(","), out_dir)
	var t := create_timer(900.0)
	t.timeout.connect(func() -> void:
		print("FAIL: hud coverage watchdog timeout")
		quit(1))
