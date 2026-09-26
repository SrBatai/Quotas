extends SceneTree
## Determinism gate (PLAN M3 / R3, ARQ v2 §18): generates 50 chunks and prints one hash per chunk (heights
## quantized to cm, surface mask, scatter entries with their wids, node entries, POI props) plus a total. Run it in
## two separate processes with the two code paths the game uses and compare (tests/run_determinism.sh):
##   --role=server   the dedicated server's path: ChunkJob without visuals, synchronous on the main thread
##   --role=client   the client's path: ChunkJob with mesh arrays / MultiMesh buffers, on WorkerThreadPool tasks
## Both must print identical hashes (and HeightFunction.height_at at 200 fixed points must agree too).
##   godot --headless --path . -s tests/determinism.gd ++ --role=client --out=/tmp/a.txt

var _body: RefCounted


func _initialize() -> void:
	var script: GDScript = load("res://tests/determinism_steps.gd")
	if script == null or not script.can_instantiate():
		print("FAIL: cannot load determinism_steps.gd")
		quit(1)
		return
	_body = script.new()
	_body.run(self)
