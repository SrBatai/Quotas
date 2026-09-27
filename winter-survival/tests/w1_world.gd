extends SceneTree
## W1 world gate (PLAN v3.8.2 W1, C25): the 6 × 6 km grid and walls, the 768² macro map, the region banner at 20
## test points (+ LocationInfo data), the río Albo / dársena / embalse / ibón as flat safe ice, the reserved pads,
## the road and rail splines as terrain stamps (Carretera del Puerto grade, no road bed on the ice), the W1 art
## placements (tunnel portals, crest props, snow poles, guardrails), the 96² population table and the chunk cost
## in the four quadrants. Headless, no scene:
##   godot --headless --path . -s tests/w1_world.gd

var _body: RefCounted


func _initialize() -> void:
	var script: GDScript = load("res://tests/w1_world_steps.gd")
	if script == null or not script.can_instantiate():
		print("FAIL: cannot load w1_world_steps.gd")
		quit(1)
		return
	_body = script.new()
	_body.run(self)
