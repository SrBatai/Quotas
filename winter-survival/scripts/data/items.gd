class_name Items
## Item database (GDD §9). Kinds: material | food | tool (goes to the HAND slot: tools, melee weapons, firearms,
## throwables) | ammo | medicine | clothing. M5: every item has a weight `w` (kg, GDD §9.4) and a loot category
## `cat` (LootTables / nominal caps). Firearm stats live in Firearms.TABLE, melee ones in Weapons.TABLE.

const DB := {
	&"madera": {"name": "Madera", "icon": "wood", "stack": 20, "kind": "material", "w": 0.4, "cat": "material", "tint": Color("#C7A16B")},
	&"piedra": {"name": "Piedra", "icon": "stone", "stack": 20, "kind": "material", "w": 0.4, "cat": "material", "tint": Color("#7C8592")},
	&"bayas": {"name": "Bayas", "icon": "berry", "stack": 20, "kind": "food", "hunger": 12, "w": 0.05, "cat": "food", "tint": Color("#D9403D")},
	&"carne_cruda": {"name": "Carne cruda", "icon": "meat_raw", "stack": 20, "kind": "food", "hunger": 8, "health": -5, "w": 0.5, "cat": "food", "tint": Color("#C25A5A")},
	&"carne_asada": {"name": "Carne asada", "icon": "meat_cooked", "stack": 20, "kind": "food", "hunger": 40, "warmth": 10, "w": 0.4, "cat": "food", "tint": Color("#8B5A3C")},
	&"bayas_calientes": {"name": "Bayas calientes", "icon": "berries_hot", "stack": 20, "kind": "food", "hunger": 25, "warmth": 10, "w": 0.1, "cat": "food", "tint": Color("#E06B4A")},
	&"lata_judias": {"name": "Lata de judías", "icon": "can_beans", "stack": 20, "kind": "food", "hunger": 40, "w": 0.4, "cat": "food", "tint": Color("#C23B3B")},
	&"lata_sopa": {"name": "Lata de sopa", "icon": "can_soup", "stack": 20, "kind": "food", "hunger": 35, "w": 0.4, "cat": "food", "tint": Color("#3B6BC2")},
	&"piel": {"name": "Piel de lobo", "icon": "pelt", "stack": 20, "kind": "material", "w": 1.0, "cat": "material", "tint": Color("#8A7A6A")},
	&"hacha": {"name": "Hacha de piedra", "icon": "axe", "stack": 1, "kind": "tool", "model": "stone_axe", "w": 1.5, "cat": "tool", "tint": Color("#DDE6F0")},
	&"antorcha": {"name": "Antorcha", "icon": "torch", "stack": 20, "kind": "tool", "model": "torch", "w": 0.4, "cat": "tool", "tint": Color("#DDE6F0")},
	# M4 melee weapons (GDD v2 §7.6; stats in Weapons.TABLE, models weapons/<model>.glb, ASSET_SPEC v2 §12)
	&"cuchillo": {"name": "Cuchillo de caza", "icon": "knife", "stack": 1, "kind": "tool", "weapon": true, "model": "knife", "w": 0.4, "cat": "tool", "tint": Color("#C9D3DD")},
	&"palanca": {"name": "Palanca", "icon": "crowbar", "stack": 1, "kind": "tool", "weapon": true, "model": "crowbar", "w": 2.0, "cat": "tool", "tint": Color("#B8453A")},
	&"bate": {"name": "Bate", "icon": "bat", "stack": 1, "kind": "tool", "weapon": true, "model": "bat", "w": 1.2, "cat": "tool", "tint": Color("#C7A16B")},
	&"bate_clavos": {"name": "Bate con clavos", "icon": "bat_nailed", "stack": 1, "kind": "tool", "weapon": true, "model": "bat_nailed", "w": 1.4, "cat": "tool", "tint": Color("#A8845A")},
	&"machete": {"name": "Machete", "icon": "machete", "stack": 1, "kind": "tool", "weapon": true, "model": "machete", "w": 0.9, "cat": "tool", "tint": Color("#9FB0BF")},
	# M5 firearms + bow (GDD v2 §7.6 rows 7, 9–12; stats in Firearms.TABLE; models weapons/<model>.glb, ASSET_SPEC v2 §12)
	&"pistola": {"name": "Pistola 9 mm", "icon": "pistol", "stack": 1, "kind": "tool", "weapon": true, "firearm": true, "model": "pistol", "w": 0.9, "cat": "weapon", "tint": Color("#3E434A")},
	&"revolver": {"name": "Revólver .357", "icon": "revolver", "stack": 1, "kind": "tool", "weapon": true, "firearm": true, "model": "revolver", "w": 1.1, "cat": "weapon", "tint": Color("#5A5F66")},
	&"escopeta": {"name": "Escopeta de corredera", "icon": "shotgun", "stack": 1, "kind": "tool", "weapon": true, "firearm": true, "model": "shotgun", "w": 3.5, "cat": "weapon", "tint": Color("#6B4A33")},
	&"rifle": {"name": "Rifle .308 de cerrojo", "icon": "rifle_hunting", "stack": 1, "kind": "tool", "weapon": true, "firearm": true, "model": "rifle_hunting", "w": 3.8, "cat": "weapon", "tint": Color("#5B4632")},
	&"arco": {"name": "Arco de caza", "icon": "bow", "stack": 1, "kind": "tool", "weapon": true, "firearm": true, "model": "bow", "w": 1.0, "cat": "weapon", "tint": Color("#8A6A45")},
	# ammunition (GDD v2 §7.2: scarce, never restocked in opened containers)
	&"municion_9mm": {"name": "Munición 9 mm", "icon": "ammo_9mm", "stack": 30, "kind": "ammo", "w": 0.012, "cat": "ammo", "tint": Color("#C9A24A")},
	&"municion_357": {"name": "Munición .357", "icon": "ammo_357", "stack": 24, "kind": "ammo", "w": 0.016, "cat": "ammo", "tint": Color("#B98C3A")},
	&"cartuchos": {"name": "Cartuchos del 12", "icon": "ammo_shells", "stack": 20, "kind": "ammo", "w": 0.04, "cat": "ammo", "tint": Color("#B8453A")},
	&"municion_308": {"name": "Munición .308", "icon": "ammo_308", "stack": 20, "kind": "ammo", "w": 0.025, "cat": "ammo", "tint": Color("#A8844A")},
	&"flechas": {"name": "Flechas", "icon": "arrows", "stack": 20, "kind": "ammo", "w": 0.04, "cat": "ammo", "model": "arrow", "tint": Color("#9C7A52")},
	# throwables (GDD v2 §7.6 row 14, M5: can and flare)
	&"lata_vacia": {"name": "Lata vacía", "icon": "can_soup", "stack": 10, "kind": "tool", "throwable": true, "model": "can_soup", "w": 0.1, "cat": "misc", "tint": Color("#AAB4BE")},
	&"bengala": {"name": "Bengala", "icon": "flare", "stack": 10, "kind": "tool", "throwable": true, "model": "flare", "w": 0.2, "cat": "tool", "tint": Color("#E0483A")},
	# medicine, clothing v0, tools, food (GDD v2 §9.2 tables)
	&"vendas": {"name": "Vendas", "icon": "bandage", "stack": 10, "kind": "medicine", "health": 15, "w": 0.05, "cat": "medicine", "tint": Color("#E8E2D6")},
	&"analgesicos": {"name": "Analgésicos", "icon": "pills", "stack": 10, "kind": "medicine", "health": 8, "w": 0.05, "cat": "medicine", "tint": Color("#D8D8E8")},
	&"botiquin": {"name": "Botiquín", "icon": "medkit", "stack": 3, "kind": "medicine", "health": 50, "w": 0.6, "cat": "medicine", "tint": Color("#D84A3A")},
	&"abrigo": {"name": "Abrigo de invierno", "icon": "coat", "stack": 1, "kind": "clothing", "slot": "coat", "w": 1.8, "cat": "clothing", "tint": Color("#5C6E86")},
	&"guantes": {"name": "Guantes", "icon": "gloves", "stack": 1, "kind": "clothing", "slot": "hands", "w": 0.2, "cat": "clothing", "tint": Color("#6B5A48")},
	&"gorro": {"name": "Gorro de lana", "icon": "hat", "stack": 1, "kind": "clothing", "slot": "head", "w": 0.15, "cat": "clothing", "tint": Color("#A83A3A")},
	&"cuerda": {"name": "Cuerda", "icon": "rope", "stack": 10, "kind": "material", "w": 0.3, "cat": "material", "tint": Color("#B89A6A")},
	&"cinta": {"name": "Cinta americana", "icon": "duct_tape", "stack": 10, "kind": "material", "w": 0.2, "cat": "material", "tint": Color("#9AA4AE")},
	&"aceite_arma": {"name": "Aceite de arma", "icon": "gun_oil", "stack": 5, "kind": "medicine", "gun_oil": true, "w": 0.2, "cat": "tool", "tint": Color("#8A7A3A")},
	&"chocolate": {"name": "Chocolate", "icon": "chocolate", "stack": 20, "kind": "food", "hunger": 15, "warmth": 5, "w": 0.1, "cat": "food", "tint": Color("#6B3F2A")},
	&"carne_seca": {"name": "Carne seca", "icon": "jerky", "stack": 20, "kind": "food", "hunger": 20, "w": 0.1, "cat": "food", "tint": Color("#7A4A32")},
	&"racion": {"name": "Ración militar", "icon": "ration", "stack": 10, "kind": "food", "hunger": 45, "warmth": 5, "w": 0.5, "cat": "food", "tint": Color("#5F6B3F")},
}

const FOOD_PRIORITY: Array[StringName] = [&"carne_asada", &"racion", &"lata_judias", &"lata_sopa", &"bayas_calientes", &"carne_seca", &"chocolate", &"bayas", &"carne_cruda"]


static func exists(id: StringName) -> bool:
	return DB.has(id)


static func display_name(id: StringName) -> String:
	if DB.has(id):
		return DB[id]["name"]
	return String(id)


static func icon_name(id: StringName) -> String:
	if DB.has(id):
		return DB[id]["icon"]
	return ""


static func tint(id: StringName) -> Color:
	if DB.has(id) and DB[id].has("tint"):
		return DB[id]["tint"]
	return Color.WHITE


static func stack_max(id: StringName) -> int:
	if DB.has(id):
		return int(DB[id].get("stack", Balance.STACK_MAX))
	return Balance.STACK_MAX


static func is_food(id: StringName) -> bool:
	return DB.has(id) and DB[id]["kind"] == "food"


static func is_tool_item(id: StringName) -> bool:
	return DB.has(id) and DB[id]["kind"] == "tool"


## Hand items with a durability value per slot (melee weapons + the axe, which is a tool and a weapon; firearms).
static func has_durability(id: StringName) -> bool:
	return Weapons.is_weapon(id) or Firearms.is_firearm(id)


static func is_firearm(id: StringName) -> bool:
	return DB.has(id) and bool(DB[id].get("firearm", false))


static func is_throwable(id: StringName) -> bool:
	return DB.has(id) and bool(DB[id].get("throwable", false))


static func is_medicine(id: StringName) -> bool:
	return DB.has(id) and DB[id]["kind"] == "medicine"


static func is_clothing(id: StringName) -> bool:
	return DB.has(id) and DB[id]["kind"] == "clothing"


static func is_ammo(id: StringName) -> bool:
	return DB.has(id) and DB[id]["kind"] == "ammo"


## Weight of one unit (kg, GDD §9.4).
static func weight(id: StringName) -> float:
	return float(DB[id].get("w", 0.2)) if DB.has(id) else 0.0


## Loot / nominal category: food, medicine, clothing, tool, weapon, ammo, material, misc.
static func category(id: StringName) -> String:
	return str(DB[id].get("cat", "misc")) if DB.has(id) else "misc"


static func food_priority() -> Array[StringName]:
	return FOOD_PRIORITY


static func food_delta(id: StringName, stat: String) -> float:
	if DB.has(id):
		return float(DB[id].get(stat, 0))
	return 0.0


## Tooltip text, e.g. "Lata de judías · Hambre +40".
static func describe(id: StringName) -> String:
	var text := display_name(id)
	if is_food(id):
		var parts: Array[String] = []
		var h := food_delta(id, "hunger")
		var w := food_delta(id, "warmth")
		var hp := food_delta(id, "health")
		if h != 0.0:
			parts.append("Hambre %+d" % int(h))
		if w != 0.0:
			parts.append("Calor %+d" % int(w))
		if hp != 0.0:
			parts.append("Salud %+d" % int(hp))
		if not parts.is_empty():
			text += " · " + " · ".join(parts)
	elif Firearms.is_firearm(id):
		var f: Dictionary = Firearms.of(id)
		text += " · %s · daño %d · %d balas · %s" % ["Arco" if Firearms.is_bow(id) else "Arma de fuego", int(f["dmg"]), int(f["mag"]),
			display_name(StringName(f["ammo"])).to_lower()]
	elif Weapons.is_weapon(id):
		var w: Dictionary = Weapons.of(id)
		text += " · Arma · daño %d · alcance %.1f m" % [int(w["dmg"]), float(w["reach"])]
	elif is_medicine(id):
		text += " · Salud %+d" % int(food_delta(id, "health")) if food_delta(id, "health") != 0.0 else " · Cuidado del arma (1 día)"
	elif is_ammo(id):
		text += " · Munición"
	elif is_clothing(id):
		text += " · Ropa"
	elif is_tool_item(id):
		text += " · Herramienta"
	return text
