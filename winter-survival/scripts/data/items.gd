class_name Items
## Item database (GDD §9). Kinds: material | food | tool.

const DB := {
	&"madera": {"name": "Madera", "icon": "wood", "stack": 20, "kind": "material", "tint": Color("#C7A16B")},
	&"piedra": {"name": "Piedra", "icon": "stone", "stack": 20, "kind": "material", "tint": Color("#7C8592")},
	&"bayas": {"name": "Bayas", "icon": "berry", "stack": 20, "kind": "food", "hunger": 12, "tint": Color("#D9403D")},
	&"carne_cruda": {"name": "Carne cruda", "icon": "meat_raw", "stack": 20, "kind": "food", "hunger": 8, "health": -5, "tint": Color("#C25A5A")},
	&"carne_asada": {"name": "Carne asada", "icon": "meat_cooked", "stack": 20, "kind": "food", "hunger": 40, "warmth": 10, "tint": Color("#8B5A3C")},
	&"bayas_calientes": {"name": "Bayas calientes", "icon": "berries_hot", "stack": 20, "kind": "food", "hunger": 25, "warmth": 10, "tint": Color("#E06B4A")},
	&"lata_judias": {"name": "Lata de judías", "icon": "can_beans", "stack": 20, "kind": "food", "hunger": 40, "tint": Color("#C23B3B")},
	&"lata_sopa": {"name": "Lata de sopa", "icon": "can_soup", "stack": 20, "kind": "food", "hunger": 35, "tint": Color("#3B6BC2")},
	&"piel": {"name": "Piel de lobo", "icon": "pelt", "stack": 20, "kind": "material", "tint": Color("#8A7A6A")},
	&"hacha": {"name": "Hacha de piedra", "icon": "axe", "stack": 1, "kind": "tool", "model": "stone_axe", "tint": Color("#DDE6F0")},
	&"antorcha": {"name": "Antorcha", "icon": "torch", "stack": 20, "kind": "tool", "model": "torch", "tint": Color("#DDE6F0")},
}

const FOOD_PRIORITY: Array[StringName] = [&"carne_asada", &"lata_judias", &"lata_sopa", &"bayas_calientes", &"bayas", &"carne_cruda"]


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


static func is_tool(id: StringName) -> bool:
	return DB.has(id) and DB[id]["kind"] == "tool"


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
	elif is_tool(id):
		text += " · Herramienta"
	return text
