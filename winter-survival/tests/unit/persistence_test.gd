extends SceneTree
## Persistence backends (ARQ v2 §15, M2): the same suite over MemoryBackend and FileBackend (SqliteBackend joins
## in M5). Run: godot --headless --path . -s tests/unit/persistence_test.gd  → "== N checks, ALL PASSED" / exit 1.
## The typed body is loaded after the autoloads exist (Net.GAME_VERSION is read by the document format).

var _body: RefCounted


func _initialize() -> void:
	var script: GDScript = load("res://tests/unit/persistence_steps.gd")
	if script == null or not script.can_instantiate():
		print("FAIL: cannot load persistence_steps.gd")
		quit(1)
		return
	_body = script.new()
	_body.run(self)
	var t := create_timer(60.0)
	t.timeout.connect(func() -> void:
		print("FAIL: persistence test watchdog timeout")
		quit(1))
