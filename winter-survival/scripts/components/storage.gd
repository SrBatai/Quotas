class_name Storage
extends Node
## Container model (cabinet, truck, box): 6 slots of {"id", "count"} or {}.

signal changed()

@export var title: String = "ARMARIO"
@export var open_label: String = "Abrir armario"
@export var opened_label: String = "Armario abierto"
var slots: Array[Dictionary] = []
var is_open: bool = false


func _ready() -> void:
	if slots.is_empty():
		for i in Balance.CONTAINER_SLOTS:
			slots.append({})
	add_to_group("storage")


## Initial contents, e.g. {&"lata_judias": 2, &"lata_sopa": 2}.
func setup(initial: Dictionary) -> void:
	slots.clear()
	for i in Balance.CONTAINER_SLOTS:
		slots.append({})
	for id in initial:
		add(id, int(initial[id]))


func add(id: StringName, n: int) -> int:
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
	remove_from_slot(slot, n)
	return out


func is_empty() -> bool:
	for s in slots:
		if not s.is_empty():
			return false
	return true


func anchor_position() -> Vector3:
	var p := get_parent()
	if p is Node3D:
		return (p as Node3D).global_position
	return Vector3.ZERO
