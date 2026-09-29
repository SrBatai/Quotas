extends SceneTree
## Helper of tests/unit/persistence_m5_test.gd (crash safety): opens the SQLite store given as the first user
## argument, commits one autosave batch (player "committed"), opens a second batch (player "uncommitted" + a chunk
## delta), writes the marker file (second argument) and waits to be killed with the transaction still open.

var _backend: RefCounted


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		quit(2)
		return
	# typed backend classes resolve after the autoloads exist
	await process_frame
	var b: RefCounted = load("res://scripts/persistence/sqlite_backend.gd").new()
	_backend = b
	if b.call("open", args[0]) != OK:
		quit(3)
		return
	b.call("begin_batch")
	b.call("save_player", "committed", {"name": "A"})
	b.call("flush")
	b.call("begin_batch")
	b.call("save_player", "uncommitted", {"name": "B"})
	var d: ChunkDelta = ChunkDelta.make(30, 30)
	d.merge(&"objects", 1, {"felled": true})
	b.call("save_chunk_delta", d)
	var f := FileAccess.open(args[1], FileAccess.WRITE)
	f.store_string("batch B open")
	f.close()
	while true:
		OS.delay_msec(50)
