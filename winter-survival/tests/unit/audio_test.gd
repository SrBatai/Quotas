extends SceneTree
## S1 audio gate (docs/AUDIO.md §8): the event table validates; every event name the code plays has a stream or is in
## the documented silent list; every shipped file loads with the channels its use needs (3D = mono, beds / stingers =
## stereo), a sane length and level (peaks ≤ −1 dBFS), the licences cover every file, the variation minimums and the
## size budget hold; the AudioManager (headless, not a dedicated server) plays, loops, keeps the zombie voice budget
## (nearest first) and the per-event instance cap.
## Run: godot --headless --path . -s tests/unit/audio_test.gd  → "== N checks, ALL PASSED" / exit 1.

var _body: RefCounted


func _initialize() -> void:
	var script: GDScript = load("res://tests/unit/audio_test_steps.gd")
	if script == null or not script.can_instantiate():
		print("FAIL: cannot load audio_test_steps.gd")
		quit(1)
		return
	_body = script.new()
	_body.run(self)
	var t := create_timer(120.0)
	t.timeout.connect(func() -> void:
		print("FAIL: audio test watchdog timeout")
		quit(1))
