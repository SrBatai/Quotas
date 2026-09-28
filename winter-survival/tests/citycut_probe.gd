extends SceneTree
## C0 «corte urbano» probe in the real world (PLAN C0 acceptance, R14): the game streamed as usual (offline server),
## the local player at 5 fixed points of the superblock LT-01 of Las Torres (Gran Vía sidewalk, west street, back
## street, inner plaza, the mirador roof) with key-colour stand-ins for the player and a few zombies (the city bench
## method, doc 09 §3.8): pixels with the city (cut on, silhouettes) against a reference frame without it. Gate:
## player visible ≥ 99 % (or ≤ 6 edge pixels lost) at every point and zoom, player + zombies readable ≥ 95 % overall.
## Deterministic: fixed clock, no weather / snowfall particles, physics of the player off, the camera placed on its
## follow target (no easing), static stand-ins.
##   xvfb-run -a godot --path . --rendering-method gl_compatibility -s tests/citycut_probe.gd ++ [--json=path] [--shots=dir]
## (tests/run_citycut_probe.sh). Exit code 0 = pass.

var _body: RefCounted


func _initialize() -> void:
	var opts := {"json": "", "shots": ""}
	for a in OS.get_cmdline_user_args():
		for k in opts.keys():
			if a.begins_with("--%s=" % k):
				opts[k] = a.substr(k.length() + 3)
	Engine.max_fps = 0
	var script: GDScript = load("res://tests/citycut_probe_steps.gd")
	if script == null or not script.can_instantiate():
		print("FAIL: cannot load citycut_probe_steps.gd")
		quit(1)
		return
	_body = script.new()
	_body.run(self, opts)
	var t := create_timer(1200.0)
	t.timeout.connect(func() -> void:
		print("FAIL: citycut probe watchdog timeout")
		quit(1))
