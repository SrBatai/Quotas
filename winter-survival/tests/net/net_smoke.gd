extends SceneTree
## Headless multiplayer test runner (ARQ v2 §18, PLAN M1 acceptance). One process per role:
##   server:  godot --headless --path . -s tests/net/net_smoke.gd ++ --server --config <cfg> [--duration S]
##   client:  godot --headless --path . -s tests/net/net_smoke.gd ++ --client --name=A --scenario basic --port 7777 --duration 60 [--late 22]
## The `Net` autoload already started the server when it saw --server; the typed body (net_steps.gd) is loaded
## at runtime so the autoloads exist when it compiles. Every process prints "RESULT OK/FAIL" (clients) or
## "SERVER RESULT OK/FAIL" (server, at quit) and exits with 0/1.

var _body: RefCounted


func _initialize() -> void:
	Engine.max_fps = 60
	# no autoload references here: this script compiles before the autoloads exist (-s mode)
	var opts := {"server": false, "name": "?", "scenario": "basic", "duration": 60.0, "port": 7777,
		"password": "", "host": "127.0.0.1", "clients": 4, "late": 0.0, "phase": 1}
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var a := args[i]
		match a:
			"--server": opts["server"] = true
			"--client": opts["server"] = false
			"--scenario": i += 1; opts["scenario"] = args[i]
			"--duration": i += 1; opts["duration"] = float(args[i])
			"--port": i += 1; opts["port"] = int(args[i])
			"--password": i += 1; opts["password"] = args[i]
			"--host": i += 1; opts["host"] = args[i]
			"--clients": i += 1; opts["clients"] = int(args[i])
			"--late": i += 1; opts["late"] = float(args[i])
			"--phase": i += 1; opts["phase"] = int(args[i])
			_:
				if a.begins_with("--name="):
					opts["name"] = a.substr(7)
		i += 1
	# M5 scenarios (hitscan, restart) and H2's (discovery) live in their own bodies, extensions of net_steps.gd
	var body_path := "res://tests/net/net_steps_m5.gd" if str(opts["scenario"]) in ["hitscan", "restart"] else "res://tests/net/net_steps.gd"
	if str(opts["scenario"]) == "discovery":
		body_path = "res://tests/net/net_steps_h2.gd"
	if str(opts["scenario"]) == "street":
		body_path = "res://tests/net/net_steps_m6a.gd"   # M6a: kit doors replicated (C joins late)
	if str(opts["scenario"]) == "village":
		body_path = "res://tests/net/net_steps_m6b.gd"   # M6b: 2 players in 2 La Herrería houses: doors + containers
	if str(opts["scenario"]) == "interest":
		body_path = "res://tests/net/net_steps_interest.gd"   # spawns / teleports outside a peer's chunk interest
	if str(opts["scenario"]) == "team":
		body_path = "res://tests/net/net_steps_h3.gd"   # H3: a danger ping on every client, B's down → A ≤ 0.2 s, the blizzard countdown
	if str(opts["scenario"]) == "tower":
		body_path = "res://tests/net/net_steps_c1.gd"   # C1: 4 clients on 3 floors of a hero tower (doors, loot, vertical filter)
	var script: GDScript = load(body_path)
	if script == null or not script.can_instantiate():
		print("FAIL: cannot load %s" % body_path)
		quit(1)
		return
	_body = script.new()
	_body.run(self, opts)
	var limit := float(opts["duration"]) + float(opts["late"]) + 60.0 if float(opts["duration"]) > 0.0 else 600.0
	var t := create_timer(limit)
	t.timeout.connect(func() -> void:
		print("FAIL: net test watchdog timeout")
		quit(1))


func _finalize() -> void:
	if _body != null and _body.has_method("on_finalize"):
		_body.on_finalize()
