extends SceneTree
## C1 «Altavega: núcleo urbano» gate (headless, no game scene): the generated lot file (city_version 1, hashes, the
## generator reproducible byte for byte), the districts (lots, zone titles, no overlaps, the street graph), the
## families (city contract, budgets), streaming of sample chunks of the four districts, the Control del Puerto and a
## hero tower (buildings, CityCut, doors, loot, painted streets, scatter cleared; server and no-art paths), the hero
## tower's stairs / doors / roof by physics rays, NavFloorTile + stair links (a path from floor 1 to floor 3), the
## vertical interest filter, the floor population, the lot dressing digest, the real-lot silhouettes and the frozen
## statues bake.
##   godot --headless --path . -s tests/c1_city.gd [++ --digest=path] [++ --no-gen]

var _body: RefCounted


func _initialize() -> void:
	var script: GDScript = load("res://tests/c1_city_steps.gd")
	if script == null or not script.can_instantiate():
		print("FAIL: cannot load c1_city_steps.gd")
		quit(1)
		return
	_body = script.new()
	_body.run(self)
