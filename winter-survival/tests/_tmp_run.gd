extends SceneTree
var _body: RefCounted
func _initialize() -> void:
	Engine.max_fps = 60
	var script: GDScript = load("res://tests/_tmp_run_body.gd")
	_body = script.new()
	_body.run(self)
	create_timer(120.0).timeout.connect(func() -> void: quit(1))
