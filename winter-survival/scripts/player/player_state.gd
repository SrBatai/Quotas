class_name PlayerState
extends Node
## Per-player state (ARQ v2 §7). Server: authoritative storage + the Inventory / Stats / Quests components
## (children, freed on a pure client). Owner: read-only mirror filled by PlayerNet._mirror. The read API
## (count/has/hand_tool/...) works on both sides so UI and recipes use one code path. Replaces the
## `Inventory` / `QuestManager` autoloads and the stats half of `player_stats.gd`.

signal sim_event(kind: StringName, args: Array)

var player: Player
var slots: Array[Dictionary] = []
var has_coat: bool = false
var health: float = Balance.HEALTH_MAX
var warmth: float = Balance.WARMTH_START
var hunger: float = Balance.HUNGER_START
var dead: bool = false
var death_cause: StringName = &""
var quest_state: Dictionary = {}
var steps_done: int = 0
var torch_seconds_left: float = Balance.TORCH_DURATION
var inventory: InventoryComponent
var stats: StatsComponent
var quests: QuestComponent

var _dirty: Dictionary = {}
var _steps_done_seen: int = 0
var _quest_day_seen: int = -1
var _dead_seen: bool = false


func _ready() -> void:
	player = get_parent()
	if slots.is_empty():
		for i in Balance.HOTBAR_SLOTS:
			slots.append({})
	inventory = get_node_or_null("Inventory")
	stats = get_node_or_null("Stats")
	quests = get_node_or_null("Quests")
	if not Net.is_server:
		for c in [inventory, stats, quests]:
			if c != null:
				remove_child(c)
				c.queue_free()
		inventory = null
		stats = null
		quests = null


## Server: wire the components and restore a saved profile (called from Player._ready).
func server_setup() -> void:
	inventory.setup(self)
	stats.setup(self)
	quests.setup(self)
	if not player.pending_profile.is_empty():
		player.apply_profile(player.pending_profile)
		player.pending_profile = {}
	mark_all()


func is_local() -> bool:
	return player != null and player.is_local


# ------------------------------------------------------------------ read API (server storage or owner mirror)
func slot_empty(i: int) -> bool:
	return slots[i].is_empty()


func hand_tool() -> StringName:
	if slots.is_empty() or slots[0].is_empty():
		return &""
	return slots[0]["id"]


func hand_count() -> int:
	if slots.is_empty() or slots[0].is_empty():
		return 0
	return int(slots[0]["count"])


func count(id: StringName) -> int:
	var n := 0
	for s in slots:
		if not s.is_empty() and s["id"] == id:
			n += int(s["count"])
	return n


func has(id: StringName, n: int = 1) -> bool:
	return count(id) >= n


func free_slots() -> int:
	var n := 0
	for i in range(1, slots.size()):
		if slots[i].is_empty():
			n += 1
	return n


## Can the result of a recipe fit once the costs are gone?
func can_add_result(result: Dictionary, cost: Dictionary) -> bool:
	var sim: Array[Dictionary] = []
	for s in slots:
		sim.append(s.duplicate())
	for id in cost:
		var left: int = int(cost[id])
		for i in range(sim.size() - 1, -1, -1):
			if left <= 0:
				break
			if not sim[i].is_empty() and sim[i]["id"] == id:
				var take := mini(left, int(sim[i]["count"]))
				sim[i]["count"] = int(sim[i]["count"]) - take
				left -= take
				if int(sim[i]["count"]) <= 0:
					sim[i] = {}
	for id in result:
		var need: int = int(result[id])
		var stack := Items.stack_max(id)
		if Items.is_tool_item(id) and (sim[0].is_empty() or (sim[0]["id"] == id and int(sim[0]["count"]) < stack)):
			need -= 1
		for i in range(1, sim.size()):
			if need <= 0:
				break
			if sim[i].is_empty():
				need -= stack
			elif sim[i]["id"] == id:
				need -= stack - int(sim[i]["count"])
		if need > 0:
			return false
	return true


# ------------------------------------------------------------------ server API
func mark(key: StringName) -> void:
	_dirty[key] = true


func mark_all() -> void:
	for k in [&"slots", &"stats", &"quest", &"dead", &"torch"]:
		_dirty[k] = true


## Emits a simulation event for this player (quests) and the global presentation signal of the same name.
func emit_sim(kind: StringName, args: Array) -> void:
	sim_event.emit(kind, args)
	if Events.has_signal(kind):
		Events.callv("emit_signal", [kind] + args)


## Toast for the owner (local: direct; remote: RPC).
func notify(text: String, seconds: float) -> void:
	if is_local():
		Events.notify.emit(text, seconds)
	elif player != null:
		Net.rpc_to(player.net, &"_notify", player.peer_id, [text, seconds])


## Server: packs the dirty parts of the mirror and delivers them to the owner (called by PlayerNet each tick).
func flush_mirror() -> void:
	if _dirty.is_empty():
		return
	var d := {}
	if _dirty.has(&"slots"):
		d["slots"] = Packets.pack_slots(slots)
		d["coat"] = has_coat
	if _dirty.has(&"stats"):
		d["stats"] = PackedFloat32Array([health, warmth, hunger])
	if _dirty.has(&"quest"):
		d["quest"] = quest_state
		d["steps_done"] = steps_done
	if _dirty.has(&"dead"):
		d["dead"] = dead
		d["cause"] = String(death_cause)
		d["days"] = WorldState.instance.days_survived() if WorldState.instance != null else 0
		d["hours"] = WorldState.instance.hours_into_day() if WorldState.instance != null else 0
	if _dirty.has(&"torch"):
		d["torch"] = torch_seconds_left
	_dirty.clear()
	if is_local():
		apply_mirror(d)
	else:
		Net.rpc_to(player.net, &"_mirror", player.peer_id, [d])


# ------------------------------------------------------------------ owner mirror
func apply_mirror(d: Dictionary) -> void:
	var local := is_local()
	if d.has("slots"):
		var old_hand := hand_tool()
		if not Net.is_server:
			slots = Packets.unpack_slots(d["slots"])
			while slots.size() < Balance.HOTBAR_SLOTS:
				slots.append({})
			has_coat = bool(d.get("coat", false))
		if local:
			Events.inventory_changed.emit()
			if hand_tool() != old_hand or not Net.is_server:
				Events.tool_changed.emit(hand_tool())
	if d.has("stats"):
		var s: PackedFloat32Array = d["stats"]
		if not Net.is_server and s.size() >= 3:
			health = s[0]
			warmth = s[1]
			hunger = s[2]
		if local:
			Events.stat_changed.emit(&"health", health, Balance.HEALTH_MAX)
			Events.stat_changed.emit(&"warmth", warmth, Balance.WARMTH_MAX)
			Events.stat_changed.emit(&"hunger", hunger, Balance.HUNGER_MAX)
	if d.has("quest"):
		if not Net.is_server:
			quest_state = d["quest"]
			steps_done = int(d.get("steps_done", 0))
		if local:
			Events.quest_updated.emit(quest_state)
			if steps_done > _steps_done_seen:
				_steps_done_seen = steps_done
				Events.quest_step_completed.emit(int(quest_state.get("index", 1)) - 1)
			var qday := int(quest_state.get("day", 0))
			if bool(quest_state.get("day_completed", false)) and qday != _quest_day_seen:
				_quest_day_seen = qday
				Events.quest_day_completed.emit(qday)
	if d.has("dead"):
		if not Net.is_server:
			dead = bool(d["dead"])
			death_cause = StringName(str(d.get("cause", "")))
		if local and dead and not _dead_seen:
			Events.player_died.emit(death_cause)
			GameFlow.on_local_death(death_cause, int(d.get("days", 0)), int(d.get("hours", 0)))
		elif local and _dead_seen and not dead:
			Events.player_respawned.emit()
		_dead_seen = dead
	if d.has("torch") and not Net.is_server:
		torch_seconds_left = float(d["torch"])
