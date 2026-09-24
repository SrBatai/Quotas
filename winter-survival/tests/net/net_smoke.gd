extends SceneTree
## Headless multiplayer test runner (ARQ v2 §18, PLAN M1 acceptance). One process per role:
##   server:  godot --headless --path . -s tests/net/net_smoke.gd ++ --server --config <cfg> [--duration S]
##   client:  godot --headless --path . -s tests/net/net_smoke.gd ++ --client --name=A --scenario basic --port 7777 --duration 60
## The `Net` autoload already started the server when it saw --server; the typed body (net_steps.gd) is loaded
## at runtime so the autoloads exist when it compiles. Every process prints "RESULT OK/FAIL" (clients) or
## "SERVER RESULT OK/FAIL" (server, at quit) and exits with 0/1.

var _body: RefCounted


func _initialize() -> void:
	Engine.max_fps = 60
	var opts := {"server": false, "name": "?", "scenario": "basic", "duration": 60.0, "port": Net.DEFAULT_PORT,
		"password": "", "host": "127.0.0.1", "clients": 4}
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
			_:
				if a.begins_with("--name="):
					opts["name"] = a.substr(7)
		i += 1
	var script: GDScript = load("res://tests/net/net_steps.gd")
	if script == null or not script.can_instantiate():
		print("FAIL: cannot load net_steps.gd")
		quit(1)
		return
	_body = script.new()
	_body.run(self, opts)
	var limit := float(opts["duration"]) + 60.0 if float(opts["duration"]) > 0.0 else 600.0
	var t := create_timer(limit)
	t.timeout.connect(func() -> void:
		print("FAIL: net test watchdog timeout")
		quit(1))


func _finalize() -> void:
	if _body != null and _body.has_method("on_finalize"):
		_body.on_finalize()
