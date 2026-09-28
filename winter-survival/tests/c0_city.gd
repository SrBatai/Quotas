extends SceneTree
## C0 «Escaparate de Altavega» gate (headless, no scene): the lot file v0 (format, city_version = WorldConst.CITY_VERSION,
## references, hashes), the tower assembler (Base + floor groups + Roof + ShadowProxy, the city contract), the chunk
## items (layout + seeded jam) where doc 09 / W1 put them, the streaming hook (ChunkJob → WorldChunk steps →
## CityBuilding + CityHlod, colliders, teardown), the provisional bridge, the mirador and the silhouettes v0.
##   godot --headless --path . -s tests/c0_city.gd [++ --digest=path]   (--digest: write the lot / items digest)

var _body: RefCounted


func _initialize() -> void:
	var script: GDScript = load("res://tests/c0_city_steps.gd")
	if script == null or not script.can_instantiate():
		print("FAIL: cannot load c0_city_steps.gd")
		quit(1)
		return
	_body = script.new()
	_body.run(self)
