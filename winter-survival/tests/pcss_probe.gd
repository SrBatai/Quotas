extends SceneTree
## R23 (PLAN v3.11) PCSS precision far from the origin, measured in C0: the same tower (A1 tower_a assembled like
## Las Torres' T21, its ShadowProxy the only caster) on a flat ground with the game's sun at 11:00 (`alto`: PCSS
## 1.2°, soft shadows high, 4096 atlas) and the same camera relative to it, once at the origin and once at
## (2 688, −384) (Las Torres, 2.7 km). Metric on the ground around the shadow edge of the tower: penumbra pixels
## (luma between 10 % and 90 % of the lit → umbra range) and their mean luma; the mean penumbra difference is the
## relative difference of the penumbra width (penumbra area / edge length, same edge in both) + the mean absolute
## luma difference inside the penumbra (in units of the lit − umbra contrast). Gate: ≤ 3 % (else the R23
## mitigation applies). Forward+ only (Compatibility has no PCSS: the probe reports and passes).
##   RENDER=forward tests/run_pcss_probe.sh [--shots=dir] [--x=2688 --z=-384]

var _body: RefCounted


func _initialize() -> void:
	var opts := {"shots": "", "x": 2688.0, "z": -384.0, "json": "", "limit": 0.03}
	for a in OS.get_cmdline_user_args():
		for k in opts.keys():
			if a.begins_with("--%s=" % k):
				var v := a.substr(str(k).length() + 3)
				opts[k] = float(v) if opts[k] is float else v
	Engine.max_fps = 0
	var script: GDScript = load("res://tests/pcss_probe_steps.gd")
	if script == null or not script.can_instantiate():
		print("FAIL: cannot load pcss_probe_steps.gd")
		quit(1)
		return
	_body = script.new()
	_body.run(self, opts)
	var t := create_timer(900.0)
	t.timeout.connect(func() -> void:
		print("FAIL: pcss probe watchdog timeout")
		quit(1))
