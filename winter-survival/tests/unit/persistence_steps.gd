extends RefCounted
## Body of tests/unit/persistence_test.gd: world meta, players, chunk deltas (dirty-only saves), hordes, events,
## reload from disk, atomic write (no .tmp left behind), M1 save-format compatibility.

var tree: SceneTree
var _checks := 0
var _failed := false


func check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("  ok   ", msg)
	else:
		_failed = true
		print("FAIL: ", msg)


func run(p_tree: SceneTree) -> void:
	tree = p_tree
	await tree.process_frame
	print("== VENTISCA persistence test (MemoryBackend + FileBackend)")
	var path := "user://persistence_test.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_suite(MemoryBackend.new(), "memory", "")
	_suite(FileBackend.new(), "file", path)
	# reload from disk
	var fb := FileBackend.new()
	check(fb.open(path) == OK, "[file] reopen")
	check(fb.player_count() == 2 and fb.load_player("tok_a").get("name", "") == "Ana", "[file] players survive the reload")
	check(int(fb.load_world_meta().get("day", 0)) == 3, "[file] world meta survives the reload")
	var d := fb.load_chunk_delta(24, 24)
	check(d != null and int(d.objects.get(101, {}).get("hits", 0)) == 3 and bool(d.objects.get(101, {}).get("felled", false)), "[file] chunk delta objects survive the reload (int wids)")
	check(d != null and str(d.structures.get(202, {}).get("kind", "")) == "campfire", "[file] chunk delta structures survive the reload")
	check(fb.chunk_keys() == [WorldConst.key(24, 24), WorldConst.key(25, 23)], "[file] chunk keys sorted (%s)" % str(fb.chunk_keys()))
	check(fb.load_hordes().size() == 1 and fb.events().size() == 2, "[file] hordes and events survive the reload")
	check(not FileAccess.file_exists(path + ".tmp"), "[file] no .tmp left after the atomic write")
	var bak := "user://persistence_test_backup.json"
	check(fb.backup(bak) == OK and FileAccess.file_exists(bak), "[file] backup copies the document")
	# M1 save format (players + world clock only) loads
	var legacy := FileAccess.open(path, FileAccess.WRITE)
	legacy.store_string(JSON.stringify({"version": "0.4.0-m1", "world": {"day": 2, "hour": 9.5}, "players": {"tok_z": {"name": "Zoe", "x": 1.0}}}))
	legacy.close()
	var lb := FileBackend.new()
	check(lb.open(path) == OK and lb.player_count() == 1 and lb.chunk_keys().is_empty() and int(lb.load_world_meta().get("day", 0)) == 2, "[file] M1 save format (players + clock) loads")
	# corrupt file: starts empty, no crash
	var bad := FileAccess.open(path, FileAccess.WRITE)
	bad.store_string("not json")
	bad.close()
	var cb := FileBackend.new()
	check(cb.open(path) == ERR_FILE_CORRUPT and cb.player_count() == 0, "[file] corrupt document -> empty store")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(bak))
	# WorldConst chunk mapping: the clearing (±78 m) spans chunks 23–25
	check(WorldConst.chunk_of(0.0) == 24 and WorldConst.chunk_of(-78.0) == 23 and WorldConst.chunk_of(78.0) == 25
		and WorldConst.chunk_of(-31.9) == 24 and WorldConst.chunk_of(32.1) == 25, "WorldConst: clearing = chunks 23–25, chunk 24 centred on the origin")
	var k := WorldConst.key_of(Vector3(70.0, 0.0, -70.0))
	check(WorldConst.key_cx(k) == 25 and WorldConst.key_cz(k) == 23, "WorldConst: key pack/unpack")
	print("== %d checks, %s" % [_checks, "FAILED" if _failed else "ALL PASSED"])
	tree.quit(1 if _failed else 0)


func _suite(b: PersistenceBackend, tag: String, path: String) -> void:
	check(b.open(path) == OK, "[%s] open" % tag)
	b.save_world_meta({"day": 3, "hour": 12.5, "weather": "clear"})
	check(int(b.load_world_meta().get("day", 0)) == 3, "[%s] world meta round trip" % tag)
	b.save_player("tok_a", {"name": "Ana", "x": 1.5, "slots": [{"id": "madera", "count": 2}, {}]})
	b.save_player("tok_b", {"name": "Bea"})
	b.save_player("", {"name": "nobody"})
	check(b.player_count() == 2 and b.load_player("tok_a").get("name", "") == "Ana" and b.load_player("missing").is_empty(), "[%s] players: save/load, empty token ignored" % tag)
	var p := b.load_player("tok_a")
	p["name"] = "mutated"
	check(b.load_player("tok_a").get("name", "") == "Ana", "[%s] load_player returns a copy" % tag)
	# chunk deltas: only dirty tables are written
	var d := ChunkDelta.make(24, 24)
	d.merge(&"objects", 101, {"hits": 2})
	d.merge(&"objects", 101, {"hits": 3, "felled": true, "ax": 0.5, "az": -0.5})
	d.merge(&"containers", 150, {"items": [{"id": "lata_sopa", "count": 1}], "open_by": 0})
	d.merge(&"structures", 202, {"kind": "campfire", "name": "campfire_1", "x": 1.0, "y": 0.5, "z": 9.0, "yaw": 0.0})
	check(d.is_dirty() and d.dirty.has(&"objects") and d.dirty.has(&"structures") and not d.dirty.has(&"drops"), "[%s] ChunkDelta dirty flags per table" % tag)
	b.save_chunk_delta(d)
	check(not d.is_dirty(), "[%s] save_chunk_delta clears the dirty flags" % tag)
	var clean := ChunkDelta.make(25, 23)
	b.save_chunk_delta(clean)
	check(b.chunk_keys() == [WorldConst.key(24, 24)], "[%s] a clean delta is not stored" % tag)
	clean.merge(&"drops", 303, {"item": "madera", "name": "drop_1", "x": 60.0, "y": 0.0, "z": -60.0, "amount": 1})
	b.save_chunk_delta(clean)
	var back := b.load_chunk_delta(24, 24)
	check(back != null and back.cx == 24 and int(back.objects[101]["hits"]) == 3 and bool(back.objects[101]["felled"]) and back.containers.has(150) and not back.is_dirty(), "[%s] chunk delta round trip (objects + containers)" % tag)
	check(b.load_chunk_delta(1, 1) == null, "[%s] missing chunk -> null" % tag)
	# a later save with only the drops table dirty keeps the other tables
	d.merge(&"drops", 304, {"item": "piedra", "name": "drop_2", "x": 0.0, "y": 0.0, "z": 0.0, "amount": 1})
	b.save_chunk_delta(d)
	var again := b.load_chunk_delta(24, 24)
	check(again.objects.has(101) and again.drops.has(304) and again.structures.has(202), "[%s] dirty-only save keeps the stored tables" % tag)
	# pack/unpack (wire form) of the loaded delta
	var pk := again.pack()
	var un := ChunkDelta.unpack(int(pk["size"]), pk["bytes"])
	check((un["objects"] as Dictionary).has(101) and not un.has("containers"), "[%s] wire form carries objects/structures/drops, not containers" % tag)
	check(ChunkDelta.unpack(10, PackedByteArray([1, 2, 3])).is_empty() and ChunkDelta.unpack(0, PackedByteArray()).is_empty(), "[%s] unpack rejects garbage" % tag)
	b.save_hordes([{"id": 1, "kind": "wander"}])
	b.log_event("join", {"peer": 2})
	b.log_event("leave", {"peer": 2})
	check(b.load_hordes().size() == 1 and b.events().size() == 2, "[%s] hordes + events" % tag)
	check(b.flush() == OK, "[%s] flush" % tag)
	if path != "":
		check(FileAccess.file_exists(path), "[%s] document written to %s" % [tag, path])
	b.close()
