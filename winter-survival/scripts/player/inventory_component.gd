class_name InventoryComponent
extends Node
## Server-side inventory of one player (the old `Inventory` autoload, ARQ v2 §7): 10 slots stored in
## PlayerState.slots, slot 0 = HAND (tools only). Every change marks the owner mirror dirty and emits the
## per-player simulation events the quests listen to.

var state: PlayerState
## M5 (GDD §9.4): carried weight / capacity, refreshed on every change (StatsComponent slows the player with it).
var carry_ratio: float = 0.0


func setup(s: PlayerState) -> void:
	state = s
	after_load()


func _slots() -> Array[Dictionary]:
	return state.slots


func _changed() -> void:
	state.mark(&"slots")
	state.mark(&"gun")   # reserve ammo / weight shown with the weapon data
	carry_ratio = carried_weight() / Balance.CARRY_CAPACITY
	_sync_hand()


func _sync_hand() -> void:
	var tool := state.hand_tool()
	if state.player.hand_tool != tool:
		state.player.hand_tool = tool
		state.player.torch_lit = tool == &"antorcha"
		state.emit_sim(&"tool_changed", [tool])


## After a profile restore: republish the public hand tool.
func after_load() -> void:
	_sync_hand()
	state.mark(&"slots")


func clear() -> void:
	for i in _slots().size():
		_slots()[i] = {}
	state.has_coat = false
	state.worn.clear()
	_changed()


static func _new_slot(id: StringName, count: int, dur: int, ammo: int = -1) -> Dictionary:
	var d := {"id": id, "count": count}
	if Items.has_durability(id):
		d["dur"] = dur if dur >= 0 else 100
	if Firearms.is_firearm(id) and not Firearms.is_bow(id):
		d["ammo"] = maxi(ammo, 0)
	return d


## Weight carried (kg, GDD §9.4): the weapon in hand counts half.
func carried_weight() -> float:
	var w := 0.0
	var slots := _slots()
	for i in slots.size():
		var s := slots[i]
		if s.is_empty():
			continue
		var k := Items.weight(s["id"]) * float(s["count"])
		if i == 0 and (Weapons.is_weapon(s["id"]) or Firearms.is_firearm(s["id"])):
			k *= Balance.CARRY_HAND_FACTOR
		w += k
	return w


## Adds n of id; returns the leftover that did not fit. Emits item_picked_up for the amount added. `dur` = the
## durability carried by a weapon moved from a container / corpse (-1 = new, 100); `ammo` = the rounds loaded in a
## firearm (M5: they travel with the gun).
func add(id: StringName, n: int, silent: bool = false, dur: int = -1, ammo: int = -1) -> int:
	if n <= 0 or not Items.exists(id):
		return n
	var slots := _slots()
	var left := n
	var stack := Items.stack_max(id)
	if Items.is_tool_item(id):
		if slots[0].is_empty():
			var put := mini(left, stack)
			slots[0] = _new_slot(id, put, dur, ammo)
			left -= put
		elif slots[0]["id"] == id and int(slots[0]["count"]) < stack:
			var put := mini(left, stack - int(slots[0]["count"]))
			slots[0]["count"] = int(slots[0]["count"]) + put
			left -= put
	for i in range(1, slots.size()):
		if left <= 0:
			break
		var s := slots[i]
		if not s.is_empty() and s["id"] == id and int(s["count"]) < stack:
			var put := mini(left, stack - int(s["count"]))
			s["count"] = int(s["count"]) + put
			left -= put
	for i in range(1, slots.size()):
		if left <= 0:
			break
		if slots[i].is_empty():
			var put := mini(left, stack)
			slots[i] = _new_slot(id, put, dur, ammo)
			left -= put
	var added := n - left
	if added > 0:
		_changed()
		if not silent:
			state.emit_sim(&"item_picked_up", [id, added])
	return left


func remove(id: StringName, n: int) -> bool:
	if state.count(id) < n:
		return false
	var slots := _slots()
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
	_changed()
	return true


## Swap slot i with the hand (slot 0). Only tools may go to the hand.
func equip_from_slot(i: int) -> void:
	var slots := _slots()
	if i <= 0 or i >= slots.size():
		return
	var s := slots[i]
	if not s.is_empty() and not Items.is_tool_item(s["id"]):
		return
	var hand := slots[0]
	slots[0] = s
	slots[i] = hand
	_changed()


## Puts the hand tool back into a free slot.
func unequip_hand() -> void:
	var slots := _slots()
	if slots[0].is_empty():
		return
	for i in range(1, slots.size()):
		if slots[i].is_empty():
			slots[i] = slots[0]
			slots[0] = {}
			_changed()
			return
	state.notify("Inventario lleno", 2.0)


## Hotbar click: tool → equip, food → eat one, medicine → use one, clothing → wear / take off (M5).
func use_slot(i: int) -> void:
	var slots := _slots()
	if i < 0 or i >= slots.size() or slots[i].is_empty():
		return
	var id: StringName = slots[i]["id"]
	if Items.is_tool_item(id):
		if i == 0:
			unequip_hand()
		else:
			equip_from_slot(i)
	elif Items.is_food(id):
		eat(id)
	elif Items.is_medicine(id):
		use_medicine(id)
	elif Items.is_clothing(id):
		toggle_wear(id)


## M5 medicine (vendas, analgésicos, botiquín) and gun oil (GDD §7.3: no cold jams for a day).
func use_medicine(id: StringName) -> bool:
	if not Items.is_medicine(id) or not state.has(id, 1):
		return false
	if bool(Items.DB[id].get("gun_oil", false)):
		remove(id, 1)
		state.gun.oil_until = Time.get_ticks_msec() / 1000.0 + Balance.GUN_OIL_SECONDS
		state.notify("Arma engrasada: no se encasquillará con el frío", 2.5)
		return true
	if state.health >= Balance.HEALTH_MAX - 0.5:
		state.notify("No estás herido", 1.5)
		return false
	remove(id, 1)
	state.health = minf(state.health + Items.food_delta(id, "health"), Balance.HEALTH_MAX)
	state.mark(&"stats")
	state.emit_sim(&"item_consumed", [id])
	state.notify("%s (%+d salud)" % [Items.display_name(id), int(Items.food_delta(id, "health"))], 2.0)
	AudioManager.play(&"bandage")
	return true


## M5 clothing v0: the coat keeps the slice's has_coat (warmth drain ×0.6); gloves let the bow be drawn when cold.
func toggle_wear(id: StringName) -> void:
	var slot := str(Items.DB[id].get("slot", ""))
	if slot == "":
		return
	if state.worn.get(slot, &"") == id:
		state.worn.erase(slot)
	else:
		state.worn[slot] = id
	if slot == "coat":
		state.has_coat = state.worn.has("coat") or state.worn.has("fur")   # "fur" = the crafted coat (slice recipe flag)
	state.notify("%s %s" % ["Te pones" if state.worn.get(slot, &"") == id else "Te quitas", Items.display_name(id).to_lower()], 1.5)
	_changed()


## Swap the torch with the hand tool (T key).
func toggle_torch() -> void:
	var slots := _slots()
	if state.hand_tool() == &"antorcha":
		unequip_hand()
		return
	for i in range(1, slots.size()):
		if not slots[i].is_empty() and slots[i]["id"] == &"antorcha":
			equip_from_slot(i)
			return


func eat(id: StringName) -> bool:
	if not Items.is_food(id) or not state.has(id, 1):
		return false
	remove(id, 1)
	state.stats.on_item_consumed(id)
	state.emit_sim(&"item_consumed", [id])
	state.notify("Comes %s (%+d)" % [Items.display_name(id).to_lower(), int(Items.food_delta(id, "hunger"))], 2.5)
	AudioManager.play(&"eat")
	return true


func eat_best() -> bool:
	for id in Items.food_priority():
		if state.has(id, 1):
			return eat(id)
	state.notify("No tienes comida", 2.0)
	return false


## Takes one unit (or the stack) from a Storage slot into the inventory.
func take_from_container(storage: Storage, slot: int, all: bool) -> bool:
	if storage == null or slot < 0 or slot >= storage.slots.size() or storage.slots[slot].is_empty():
		return false
	var entry: Dictionary = storage.slots[slot]
	var id: StringName = entry["id"]
	var want: int = int(entry["count"]) if all else 1
	var left := add(id, want, false, int(entry.get("dur", -1)), int(entry.get("ammo", -1)))
	var moved := want - left
	if moved <= 0:
		state.notify("Inventario lleno", 2.0)
		return false
	storage.remove_from_slot(slot, moved)
	return true


## Deposits the inventory slot (one unit, or all with shift) into the storage.
func deposit_to_container(storage: Storage, slot: int, all: bool) -> bool:
	var slots := _slots()
	if storage == null or slot < 0 or slot >= slots.size() or slots[slot].is_empty():
		return false
	var id: StringName = slots[slot]["id"]
	var want: int = int(slots[slot]["count"]) if all else 1
	var left: int = storage.add(id, want, int(slots[slot].get("dur", -1)), int(slots[slot].get("ammo", -1)))
	var moved := want - left
	if moved <= 0:
		state.notify("Contenedor lleno", 2.0)
		return false
	remove(id, moved)
	return true


func set_flag(flag: String, value: bool) -> void:
	if flag == "has_coat":
		state.has_coat = value
		if value:
			state.worn["fur"] = &"piel"
		else:
			state.worn.erase("fur")
		_changed()


## Server: one use of the hand weapon (a hit, a chop): loses a point with probability 100/N (GDD §7.3) and
## breaks at 0 ("se ha roto"). Returns false when it broke.
func wear_hand(rng: RandomNumberGenerator) -> bool:
	var slots := _slots()
	if slots[0].is_empty() or not Items.has_durability(slots[0]["id"]):
		return true
	var n := int(Firearms.of(slots[0]["id"]).get("dur_n", 0)) if Firearms.is_firearm(slots[0]["id"]) else int(Weapons.of(slots[0]["id"]).get("dur_n", 0))
	if n <= 0 or rng.randf() >= 100.0 / float(n):
		return true
	var d := int(slots[0].get("dur", 100)) - 1
	slots[0]["dur"] = d
	state.mark(&"slots")
	if d > 0:
		return true
	var id: StringName = slots[0]["id"]
	slots[0] = {}
	_changed()
	state.notify("%s se ha roto" % Items.display_name(id), 3.0)
	AudioManager.play(&"tool_break")
	return false


## Server: everything the player carries (death → corpse), leaving the inventory empty.
func take_all() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in _slots().size():
		if not _slots()[i].is_empty():
			out.append(_slots()[i].duplicate())
		_slots()[i] = {}
	state.has_coat = false
	state.worn.clear()
	_changed()
	return out


## The torch in hand burnt out (server StatsComponent timer).
func torch_burnt() -> void:
	state.notify("La antorcha se ha consumido", 3.0)
	var had := state.hand_count()
	remove(&"antorcha", 1)
	if had <= 1 and state.hand_tool() == &"":
		toggle_torch()
