class_name LootContainer
extends StaticBody3D
## A lootable container of the world (ARQ v2 §9.1 step 7, §9.6; M5): built by LootSpawns on both sides from a POI
## model's `Spawn_Container_<n>` / `Spawn_Loot_<n>` empty, with a deterministic wid (hash64 of the seed, the POI and
## the spawn), so nothing about it is replicated but its delta. Opening is exclusive (NetWorld.open_storage: the other
## clients see "en uso"). The contents are rolled on the server the first time anybody opens it (Loot.roll, shared
## or one bag per player with `personal_loot_bags`), cut by the nominal caps, and persisted in the chunk's delta
## (`containers`: items, rolled_day, table, opened_day, bags); a chunk that reloads gets them back.

const SLOTS := 6
const SLOTS_LOOSE := 2
## Art T2 contract: collision box, loot point and the hinged parts (lid / flap / doors) of every container model.
const MANIFEST_PATH := "res://assets/models/props/loot/manifest.json"
const OPEN_SECONDS := 0.35

static var _manifest: Dictionary = {}
static var _manifest_loaded: bool = false

var table_id: StringName = &"campsite"
var loose: bool = false
var model_name: String = "crate"
var storage: Storage
var interactable: InteractableComponent
var rolled: bool = false
var _bag_owner: String = ""
var _hinges: Array = []    # [Node3D part, Transform3D closed, Vector3 hinge, Vector3 axis, float open_rad]
var _open_t: float = 0.0


## Called before the node enters the tree.
func setup(p_wid: int, p_table: StringName, p_loose: bool) -> void:
	set_meta("wid", p_wid)
	table_id = p_table if LootTables.has(p_table) else &"campsite"
	loose = p_loose
	model_name = LootTables.model_for(table_id, loose)
	name = "loot_%x" % p_wid


func _ready() -> void:
	add_to_group("loot_container")
	collision_layer = 1 | 64
	collision_mask = 0
	var visual := Assets.spawn_model(model_name)
	add_child(visual)
	var m: Dictionary = manifest().get(model_name, {})
	var box := BoxShape3D.new()
	box.size = Vector3(0.5, 0.35, 0.4) if loose else Vector3(0.9, 0.7, 0.6)
	var cs := CollisionShape3D.new()
	cs.shape = box
	cs.position = Vector3(0, box.size.y * 0.5, 0)
	if not loose and m.has("col_size"):
		box.size = _v3(m["col_size"], box.size)
		cs.position = _v3(m.get("col_center", []), cs.position)
	add_child(cs)
	if not loose and Net.has_client:
		var parts: Dictionary = m.get("parts", {})
		for part_name in parts:
			var part := visual.find_child(str(part_name), true, false) as Node3D
			var pe: Dictionary = parts[part_name]
			if part != null:
				_hinges.append([part, part.transform, _v3(pe.get("hinge", []), Vector3.ZERO),
					_v3(pe.get("hinge_axis", []), Vector3.RIGHT).normalized(), deg_to_rad(float(pe.get("open_deg", -100.0)))])
	set_process(not _hinges.is_empty())
	storage = Storage.new()
	storage.name = "Storage"
	storage.slot_count = SLOTS_LOOSE if loose else SLOTS
	add_child(storage)
	interactable = InteractableComponent.new()
	interactable.name = "Interactable"
	add_child(interactable)
	var ibox := BoxShape3D.new()
	ibox.size = Vector3(1.0, 1.0, 1.0)
	interactable.set_shape(ibox, Vector3(0, 0.5, 0))
	interactable.ring_radius = 0.55 if loose else 0.75
	interactable.interact_range = Balance.INTERACT_RANGE
	interactable.default_action = &"open"
	storage.title = _title()
	if Net.is_server and NetWorld.instance != null:
		# a chunk that comes back (or a restarted server) finds what was left in it
		var e := NetWorld.instance.container_entry(WorldRegistry.wid_of(self), self)
		if e.has("rolled_day"):
			rolled = true
			if e.has("items") and not bool(WorldState.rules_now().get("personal_loot_bags", false)):
				storage.set_slots_from(e["items"])
		storage.changed.connect(_on_storage_changed)
	elif NetWorld.instance != null:
		apply_net_delta(NetWorld.instance.delta_of(WorldRegistry.wid_of(self)))


static func manifest() -> Dictionary:
	if not _manifest_loaded:
		_manifest_loaded = true
		if FileAccess.file_exists(MANIFEST_PATH):
			var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
			if v is Dictionary:
				_manifest = v
	return _manifest


static func _v3(a: Variant, fallback: Vector3) -> Vector3:
	if a is Array and (a as Array).size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return fallback


## Clients: the lid / doors swing open while somebody has it open (art manifest hinge, axis and angle).
func _process(delta: float) -> void:
	var want := 1.0 if storage != null and (storage.open_by != 0 or storage.is_open) else 0.0
	if is_equal_approx(_open_t, want):
		return
	_open_t = move_toward(_open_t, want, delta / OPEN_SECONDS)
	var k := ease(_open_t, -2.0)
	for h in _hinges:
		var part := h[0] as Node3D
		if not is_instance_valid(part):
			continue
		var pivot: Vector3 = h[2]
		var rot := Transform3D(Basis(h[3], float(h[4]) * k), Vector3.ZERO)
		part.transform = Transform3D(Basis.IDENTITY, pivot) * rot * Transform3D(Basis.IDENTITY, -pivot) * (h[1] as Transform3D)


func _title() -> String:
	if loose:
		return "OBJETOS"
	match table_id:
		&"campsite":
			return "MOCHILA"
		&"lookout":
			return "CAJA DE MUNICIÓN"
		&"cabin_forest", &"hunter":
			return "BAÚL"
	return "CAJA"


func interact_actions() -> Array:
	return [&"open"]


func get_interact_label(player: Node) -> String:
	if storage.in_use_by_other(player):
		return "%s en uso" % storage.title.capitalize()
	return "Registrar %s" % storage.title.to_lower() if not storage.is_open else "%s abierto" % storage.title.capitalize()


func can_interact(player: Node) -> bool:
	return not storage.is_open and not storage.in_use_by_other(player)


func apply_net_delta(f: Dictionary) -> void:
	if f.has("open_by"):
		storage.open_by = int(f["open_by"])


## Server only: roll (first opening, a personal bag, a restock), then open for `player`.
func server_interact(player: Node, action: StringName, _arg: int) -> bool:
	if action != &"open" or not (player is Player) or not Net.is_server or NetWorld.instance == null:
		return false
	var p := player as Player
	if storage.open_by != 0 and storage.open_by != p.peer_id:
		return NetWorld.instance.open_storage(p, storage)   # "en uso"
	_prepare_for(p)
	var ok := NetWorld.instance.open_storage(p, storage)
	if ok:
		NetWorld.instance.set_container(WorldRegistry.wid_of(self), {"opened_day": WorldState.day_now()})
		Net.rpc_to(NetWorld.instance, &"_loot_opened", p.peer_id, [WorldRegistry.wid_of(self), table_id, _count_items()])
	return ok


func _count_items() -> int:
	var n := 0
	for s in storage.slots:
		if not s.is_empty():
			n += 1
	return n


func _prepare_for(p: Player) -> void:
	var nw := NetWorld.instance
	var wid := WorldRegistry.wid_of(self)
	var e := nw.container_entry(wid, self)
	var day := WorldState.day_now()
	var seed_v := WorldState.instance.world_seed if WorldState.instance != null else 0
	var rules := WorldState.rules_now()
	var region := _region()
	var players := maxi(PlayerManager.instance.players().size() if PlayerManager.instance != null else 1, 1)
	if bool(rules.get("personal_loot_bags", false)):
		var bags: Dictionary = e.get("bags", {})
		var key := p.token_hash if p.token_hash != "" else str(p.peer_id)
		if not bags.has(key):
			var items := Loot.apply_nominal(Loot.roll(seed_v, wid, table_id, int(e.get("rolled_day", day)), Loot.bag_salt(key)), region, players)
			bags[key] = items
			print("[EVT] loot bag %x (%s) for %s: %s" % [wid, table_id, p.display_name, Loot.describe(items)])
		_bag_owner = key
		storage.set_slots_from(bags[key])
		nw.set_container(wid, {"bags": bags, "rolled_day": int(e.get("rolled_day", day)), "table": String(table_id)})
		rolled = true
		return
	if not e.has("rolled_day"):
		var items := Loot.apply_nominal(Loot.roll(seed_v, wid, table_id, day), region, players)
		storage.set_slots_from(items)
		nw.set_container(wid, {"items": storage.slots.duplicate(true), "rolled_day": day, "table": String(table_id), "opened_day": day})
		rolled = true
		print("[EVT] loot roll %x (%s, day %d) at %s: %s" % [wid, table_id, day, global_position.snapped(Vector3(0.1, 0.1, 0.1)), Loot.describe(items)])
		return
	if Loot.restock_due(seed_v, wid, day, int(e.get("opened_day", e.get("rolled_day", day))), float(rules.get("loot_respawn", 0.6))):
		var extra := Loot.apply_nominal(Loot.roll(seed_v, wid, table_id, day, 1, Balance.LOOT_RESTOCK_FRACTION, true), region, players)
		for it in extra:
			storage.add(it["id"], int(it["count"]), int(it.get("dur", -1)), int(it.get("ammo", -1)))
		nw.set_container(wid, {"items": storage.slots.duplicate(true), "rolled_day": day})
		print("[EVT] loot restock %x (%s, day %d): %s" % [wid, table_id, day, Loot.describe(extra)])


func _region() -> String:
	var w := get_tree().get_first_node_in_group("world") as World
	return w.region_at(global_position.x, global_position.z) if w != null else "?"


## Personal bags: what the player leaves in his bag stays his bag.
func _on_storage_changed() -> void:
	if _bag_owner == "" or NetWorld.instance == null or not bool(WorldState.rules_now().get("personal_loot_bags", false)):
		return
	var wid := WorldRegistry.wid_of(self)
	var e := NetWorld.instance.container_entry(wid, self)
	var bags: Dictionary = e.get("bags", {})
	bags[_bag_owner] = storage.slots.duplicate(true)
	NetWorld.instance.set_container(wid, {"bags": bags})
