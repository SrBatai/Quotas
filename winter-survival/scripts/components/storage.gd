class_name Storage
extends Node
## Container model (cabinet, truck, box): 6 slots of {"id", "count"} or {}. Authoritative on the server;
## the peer that has it open receives a mirror through NetWorld (`open_by` is replicated as a world delta).

signal changed()

@export var title: String = "ARMARIO"
@export var open_label: String = "Abrir armario"
@export var opened_label: String = "Armario abierto"
## Slots (containers 6; a corpse holds a whole inventory).
@export var slot_count: int = Balance.CONTAINER_SLOTS
var slots: Array[Dictionary] = []
## Local UI flag (the opener's panel is showing it).
var is_open: bool = false
## Peer id of the player using it (0 = nobody). Server authoritative, replicated.
var open_by: int = 0


func _ready() -> void:
	if slots.is_empty():
		for i in slot_count:
			slots.append({})
	add_to_group("storage")
	changed.connect(func() -> void:
		if Net.is_server and NetWorld.instance != null:
			NetWorld.instance.push_storage(self))


## Initial contents, e.g. {&"lata_judias": 2, &"lata_sopa": 2}.
func setup(initial: Dictionary) -> void:
	slots.clear()
	for i in slot_count:
		slots.append({})
	for id in initial:
		add(id, int(initial[id]))


## Client mirror from the server.
func set_slots_from(arr: Array) -> void:
	slots.clear()
	for e in arr:
		var d: Dictionary = e
		if d.is_empty():
			slots.append({})
		else:
			var s := {"id": StringName(str(d["id"])), "count": int(d["count"])}
			if d.has("dur"):
				s["dur"] = int(d["dur"])
			slots.append(s)
	while slots.size() < slot_count:
		slots.append({})
	changed.emit()


func add(id: StringName, n: int, dur: int = -1) -> int:
	var left := n
	var stack := Items.stack_max(id)
	for s in slots:
		if left <= 0:
			break
		if not s.is_empty() and s["id"] == id and int(s["count"]) < stack:
			var put := mini(left, stack - int(s["count"]))
			s["count"] = int(s["count"]) + put
			left -= put
	for i in slots.size():
		if left <= 0:
			break
		if slots[i].is_empty():
			var put := mini(left, stack)
			slots[i] = {"id": id, "count": put}
			if Items.has_durability(id):
				slots[i]["dur"] = dur if dur >= 0 else 100
			left -= put
	if left != n:
		changed.emit()
	return left


func remove_from_slot(slot: int, n: int) -> void:
	if slot < 0 or slot >= slots.size() or slots[slot].is_empty():
		return
	slots[slot]["count"] = int(slots[slot]["count"]) - n
	if int(slots[slot]["count"]) <= 0:
		slots[slot] = {}
	changed.emit()


func take(slot: int, all: bool) -> Dictionary:
	if slot < 0 or slot >= slots.size() or slots[slot].is_empty():
		return {}
	var s := slots[slot]
	var n: int = int(s["count"]) if all else 1
	var out := {"id": s["id"], "count": n}
	if s.has("dur"):
		out["dur"] = s["dur"]
	remove_from_slot(slot, n)
	return out


func is_empty() -> bool:
	for s in slots:
		if not s.is_empty():
			return false
	return true


## True when another player has it open (the replicated `open_by`): the UI shows "en uso".
func in_use_by_other(player: Node) -> bool:
	if open_by == 0:
		return false
	if player is Player:
		return open_by != (player as Player).peer_id
	return true


func anchor_position() -> Vector3:
	var p := get_parent()
	if p is Node3D:
		return (p as Node3D).global_position
	return Vector3.ZERO


func wid() -> int:
	return WorldRegistry.wid_of(get_parent())
