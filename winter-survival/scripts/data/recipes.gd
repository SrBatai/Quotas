class_name Recipes
## Crafting recipes (GDD §10) and the status/craft helpers.

const CATEGORIES: Array[StringName] = [&"herramientas", &"fuego", &"refugio", &"almacenaje", &"cocina", &"ropa"]
const TITLES := {
	&"herramientas": "HERRAMIENTAS", &"fuego": "FUEGO", &"refugio": "REFUGIO",
	&"almacenaje": "ALMACENAJE", &"cocina": "COCINA", &"ropa": "ROPA",
}
const CATEGORY_ICONS := {
	&"herramientas": "tools", &"fuego": "fire", &"refugio": "tent",
	&"almacenaje": "box", &"cocina": "bowl", &"ropa": "shirt",
}

const DB := [
	{"id": &"hacha", "category": &"herramientas", "name": "Hacha de piedra", "icon": "axe",
		"cost": {&"madera": 2, &"piedra": 3}, "result": {&"hacha": 1}, "unique": true},
	{"id": &"antorcha", "category": &"fuego", "name": "Antorcha", "icon": "torch",
		"cost": {&"madera": 2, &"piedra": 1}, "result": {&"antorcha": 1}},
	{"id": &"fogata", "category": &"fuego", "name": "Fogata", "icon": "campfire",
		"cost": {&"madera": 3, &"piedra": 4}, "place": "campfire"},
	{"id": &"carne_asada", "category": &"cocina", "name": "Carne asada", "icon": "meat_cooked",
		"cost": {&"carne_cruda": 1}, "result": {&"carne_asada": 1}, "needs_fire": true},
	{"id": &"bayas_calientes", "category": &"cocina", "name": "Bayas calientes", "icon": "berries_hot",
		"cost": {&"bayas": 3}, "result": {&"bayas_calientes": 1}, "needs_fire": true},
	{"id": &"abrigo", "category": &"ropa", "name": "Abrigo de piel", "icon": "coat",
		"cost": {&"piel": 2}, "flag": "has_coat", "unique": true},
	{"id": &"tienda", "category": &"refugio", "name": "Tienda", "icon": "tent",
		"cost": {&"madera": 6, &"piedra": 2}, "place": "tent", "priority": 2},
	{"id": &"caja", "category": &"almacenaje", "name": "Caja de madera", "icon": "box",
		"cost": {&"madera": 4}, "place": "storage_box", "priority": 2},
]

const STATUS_READY := "Materiales listos"
const STATUS_MISSING := "Faltan materiales"
const STATUS_FIRE := "Requiere fuego cerca"
const STATUS_DONE := "Ya fabricado"
const STATUS_FULL := "Sin hueco en el inventario"
const EMPTY_CATEGORY := "Nada que fabricar aquí todavía"


static func by_id(id: StringName) -> Dictionary:
	for r in DB:
		if r["id"] == id:
			return r
	return {}


static func for_category(category: StringName) -> Array:
	var out := []
	for r in DB:
		if r["category"] == category and int(r.get("priority", 0)) < 2:
			out.append(r)
	return out


static func is_already_made(recipe: Dictionary) -> bool:
	if not recipe.get("unique", false):
		return false
	if recipe.has("flag"):
		return bool(Inventory.get(recipe["flag"]))
	if recipe.has("result"):
		for id in recipe["result"]:
			if Inventory.has(id, 1):
				return true
	return false


static func has_materials(recipe: Dictionary) -> bool:
	for id in recipe["cost"]:
		if not Inventory.has(id, int(recipe["cost"][id])):
			return false
	return true


## Returns {ok: bool, text: String} following GDD §10.
static func status(recipe: Dictionary, player: Node) -> Dictionary:
	if is_already_made(recipe):
		return {"ok": false, "text": STATUS_DONE}
	if not has_materials(recipe):
		return {"ok": false, "text": STATUS_MISSING}
	if recipe.get("needs_fire", false):
		var near_fire := false
		if player != null and player.has_method("is_near_fire"):
			near_fire = player.is_near_fire() or player.is_in_house_with_stove_on()
		if not near_fire:
			return {"ok": false, "text": STATUS_FIRE}
	if recipe.has("result") and not Inventory.can_add_result(recipe["result"], recipe["cost"]):
		return {"ok": false, "text": STATUS_FULL}
	return {"ok": true, "text": STATUS_READY}


## Consumes costs and gives the result (non-placeable recipes). Returns true on success.
static func craft(recipe: Dictionary, player: Node) -> bool:
	var st := status(recipe, player)
	if not st["ok"]:
		Events.craft_failed.emit(st["text"])
		return false
	if recipe.has("place"):
		return false
	for id in recipe["cost"]:
		Inventory.remove(id, int(recipe["cost"][id]))
	if recipe.has("result"):
		for id in recipe["result"]:
			var left: int = Inventory.add(id, int(recipe["result"][id]))
			if left > 0 and player != null and player.has_method("drop_item"):
				player.drop_item(id, left)
	if recipe.has("flag"):
		Inventory.set(recipe["flag"], true)
		Events.inventory_changed.emit()
	Events.crafted.emit(recipe["id"])
	Events.notify.emit("Fabricado: %s" % recipe["name"], 3.0)
	AudioManager.play(&"craft_done")
	return true
