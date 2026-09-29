extends SceneTree
## W1 gate «el valle no cambia» (PLAN v3.8.2 W1, C25): the height, surface and scatter hashes of every chunk with
## |x|, |z| < 1152 m (chunks 7…41 on both axes, 1 225 chunks) must be identical to the ones taken before W1
## (tests/data/valley_prew1_hashes.json), except the closed list of Carretera del Puerto chunks in the body.
##   godot --headless --path . -s tests/valley_unchanged.gd              check against the baseline
##   godot --headless --path . -s tests/valley_unchanged.gd ++ --write   (re)write the baseline (pre-W1 only!)

var _body: RefCounted


func _initialize() -> void:
	var script: GDScript = load("res://tests/valley_unchanged_steps.gd")
	if script == null or not script.can_instantiate():
		print("FAIL: cannot load valley_unchanged_steps.gd")
		quit(1)
		return
	_body = script.new()
	_body.run(self)
