extends Node
## 10-slot inventory. Slot 0 = HAND (tools only). Slots hold {"id": StringName, "count": int} or {}.

var slots: Array[Dictionary] = []
var has_coat: bool = false


func _ready() -> void:
	clear()


func clear() -> void:
	slots.clear()
	for i in Balance.HOTBAR_SLOTS:
		slots.append({})
	has_coat = false
	Events.inventory_changed.emit()
	Events.tool_changed.emit(&"")


func slot_empty(i: int) -> bool:
	return slots[i].is_empty()


func hand_tool() -> StringName:
	if slots[0].is_empty():
		return &""
	return slots[0]["id"]


func hand_count() -> int:
	if slots[0].is_empty():
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


## Adds n of id; returns the leftover that did not fit. Emits item_picked_up for the amount added.
func add(id: StringName, n: int, silent: bool = false) -> int:
	if n <= 0 or not Items.exists(id):
		return n
	var left := n
	var stack := Items.stack_max(id)
	if Items.is_tool(id):
		# Tools: stack in the hand if it holds the same tool, else take the hand if free.
		if slots[0].is_empty():
			var put := mini(left, stack)
			slots[0] = {"id": id, "count": put}
			left -= put
			Events.tool_changed.emit(id)
		elif slots[0]["id"] == id and int(slots[0]["count"]) < stack:
			var put := mini(left, stack - int(slots[0]["count"]))
			slots[0]["count"] = int(slots[0]["count"]) + put
			left -= put
	# existing stacks
	for i in range(1, slots.size()):
		if left <= 0:
			break
		var s := slots[i]
		if not s.is_empty() and s["id"] == id and int(s["count"]) < stack:
			var put := mini(left, stack - int(s["count"]))
			s["count"] = int(s["count"]) + put
			left -= put
	# empty slots
	for i in range(1, slots.size()):
		if left <= 0:
			break
		if slots[i].is_empty():
			var put := mini(left, stack)
			slots[i] = {"id": id, "count": put}
			left -= put
	var added := n - left
	if added > 0:
		Events.inventory_changed.emit()
		if not silent:
			Events.item_picked_up.emit(id, added)
	return left


func remove(id: StringName, n: int) -> bool:
	if count(id) < n:
		return false
	var left := n
	for i in range(slots.size() - 1, -1, -1):
		if left <= 0:
			break
		var s := slots[i]
		if not s.is_empty() and s["id"] == id:
			var take := mini(left, int(s["count"]))
			s["count"] = int(s["count"]) - take
			left -= take
			if int(s["count"]) <= 0:
				slots[i] = {}
				if i == 0:
					Events.tool_changed.emit(&"")
	Events.inventory_changed.emit()
	return true


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
		if Items.is_tool(id) and (sim[0].is_empty() or (sim[0]["id"] == id and int(sim[0]["count"]) < stack)):
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


func free_slots() -> int:
	var n := 0
	for i in range(1, slots.size()):
		if slots[i].is_empty():
			n += 1
	return n


## Swap slot i with the hand (slot 0). Only tools may go to the hand.
func equip_from_slot(i: int) -> void:
	if i <= 0 or i >= slots.size():
		return
	var s := slots[i]
	if not s.is_empty() and not Items.is_tool(s["id"]):
		return
	var hand := slots[0]
	slots[0] = s
	slots[i] = hand
	Events.inventory_changed.emit()
	Events.tool_changed.emit(hand_tool())


## Puts the hand tool back into a free slot.
func unequip_hand() -> void:
	if slots[0].is_empty():
		return
	for i in range(1, slots.size()):
		if slots[i].is_empty():
			slots[i] = slots[0]
			slots[0] = {}
			Events.inventory_changed.emit()
			Events.tool_changed.emit(&"")
			return
	Events.notify.emit("Inventario lleno", 2.0)


## Hotbar click: tool → equip, food → eat one.
func use_slot(i: int) -> void:
	if i < 0 or i >= slots.size() or slots[i].is_empty():
		return
	var id: StringName = slots[i]["id"]
	if Items.is_tool(id):
		if i == 0:
			unequip_hand()
		else:
			equip_from_slot(i)
	elif Items.is_food(id):
		eat(id)


## Swap the torch with the hand tool (T key).
func toggle_torch() -> void:
	if hand_tool() == &"antorcha":
		unequip_hand()
		return
	for i in range(1, slots.size()):
		if not slots[i].is_empty() and slots[i]["id"] == &"antorcha":
			equip_from_slot(i)
			return


func eat(id: StringName) -> bool:
	if not Items.is_food(id) or not has(id, 1):
		return false
	remove(id, 1)
	Events.item_consumed.emit(id)
	Events.notify.emit("Comes %s (%+d)" % [Items.display_name(id).to_lower(), int(Items.food_delta(id, "hunger"))], 2.5)
	AudioManager.play(&"eat")
	return true


func eat_best() -> bool:
	for id in Items.food_priority():
		if has(id, 1):
			return eat(id)
	Events.notify.emit("No tienes comida", 2.0)
	return false


## Takes one unit (or the stack) from a Storage slot into the inventory.
func take_from_container(storage: Node, slot: int, all: bool) -> bool:
	if storage == null or slot < 0 or slot >= storage.slots.size() or storage.slots[slot].is_empty():
		return false
	var entry: Dictionary = storage.slots[slot]
	var id: StringName = entry["id"]
	var want: int = int(entry["count"]) if all else 1
	var left := add(id, want)
	var moved := want - left
	if moved <= 0:
		Events.notify.emit("Inventario lleno", 2.0)
		return false
	storage.remove_from_slot(slot, moved)
	return true


## Deposits the inventory slot (one unit, or all with shift) into the storage.
func deposit_to_container(storage: Node, slot: int, all: bool) -> bool:
	if storage == null or slot < 0 or slot >= slots.size() or slots[slot].is_empty():
		return false
	var id: StringName = slots[slot]["id"]
	var want: int = int(slots[slot]["count"]) if all else 1
	var left: int = storage.add(id, want)
	var moved := want - left
	if moved <= 0:
		Events.notify.emit("Contenedor lleno", 2.0)
		return false
	remove(id, moved)
	return true
