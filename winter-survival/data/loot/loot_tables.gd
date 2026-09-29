class_name LootTables
## Loot tables (GDD v2 §9.1–§9.2, ARQ v2 §9.6; M5). A container rolls its table once, the first time somebody opens
## it (Loot.roll: deterministic from the world seed, the container's wid and the day it is rolled). Each table:
##   chance   probability that the container holds anything (GDD §9.2: 65 %)
##   count    [min, max] entries rolled (GDD §9.2: 1–3)
##   entries  [{id, w (weight), n: [min, max]}] picked with replacement (same ids merge)
## The named tables of the POI models (`Spawn_Container_n` extras `table`, ASSET_SPEC v2 M3.5): cabin_forest, lookout,
## campsite, house_kitchen; `loose` for `Spawn_Loot_n` (an item lying on a shelf / in a box) and building tables for
## M6+ (house, gas_station, pharmacy, police, military) so the town can use them as it arrives. Weights follow the
## rarity bands of §9.1 (common 60 / uncommon 30 / rare 9 / unique 1).

const TABLES := {
	&"cabin_forest": {"chance": 0.75, "count": [1, 3], "entries": [
		{"id": &"carne_seca", "w": 26, "n": [1, 3]}, {"id": &"cuerda", "w": 12, "n": [1, 2]}, {"id": &"piel", "w": 10, "n": [1, 1]},
		{"id": &"lata_judias", "w": 10, "n": [1, 2]}, {"id": &"vendas", "w": 8, "n": [1, 2]}, {"id": &"flechas", "w": 12, "n": [3, 8]},
		{"id": &"arco", "w": 6, "n": [1, 1]}, {"id": &"municion_308", "w": 6, "n": [2, 5]}, {"id": &"cartuchos", "w": 4, "n": [2, 4]},
		{"id": &"guantes", "w": 5, "n": [1, 1]}, {"id": &"rifle", "w": 2, "n": [1, 1]}]},
	&"lookout": {"chance": 0.85, "count": [1, 3], "entries": [
		{"id": &"vendas", "w": 16, "n": [1, 3]}, {"id": &"bengala", "w": 14, "n": [1, 2]}, {"id": &"chocolate", "w": 16, "n": [1, 2]},
		{"id": &"municion_9mm", "w": 12, "n": [3, 9]}, {"id": &"municion_308", "w": 6, "n": [2, 4]}, {"id": &"cuerda", "w": 8, "n": [1, 1]},
		{"id": &"gorro", "w": 6, "n": [1, 1]}, {"id": &"pistola", "w": 4, "n": [1, 1]}, {"id": &"aceite_arma", "w": 4, "n": [1, 1]},
		{"id": &"rifle", "w": 1, "n": [1, 1]}]},
	&"campsite": {"chance": 0.65, "count": [1, 3], "entries": [
		{"id": &"lata_sopa", "w": 20, "n": [1, 2]}, {"id": &"lata_judias", "w": 18, "n": [1, 2]}, {"id": &"chocolate", "w": 12, "n": [1, 2]},
		{"id": &"vendas", "w": 10, "n": [1, 2]}, {"id": &"cuerda", "w": 8, "n": [1, 1]}, {"id": &"cinta", "w": 8, "n": [1, 1]},
		{"id": &"lata_vacia", "w": 8, "n": [1, 3]}, {"id": &"municion_9mm", "w": 8, "n": [2, 6]}, {"id": &"cartuchos", "w": 5, "n": [1, 3]},
		{"id": &"bengala", "w": 4, "n": [1, 1]}, {"id": &"guantes", "w": 3, "n": [1, 1]}, {"id": &"revolver", "w": 1, "n": [1, 1]}]},
	&"house_kitchen": {"chance": 0.65, "count": [1, 3], "entries": [
		{"id": &"lata_judias", "w": 20, "n": [1, 3]}, {"id": &"lata_sopa", "w": 15, "n": [1, 3]}, {"id": &"chocolate", "w": 10, "n": [1, 2]},
		{"id": &"vendas", "w": 10, "n": [1, 2]}, {"id": &"cinta", "w": 6, "n": [1, 1]}, {"id": &"lata_vacia", "w": 10, "n": [1, 3]},
		{"id": &"cuchillo", "w": 5, "n": [1, 1]}, {"id": &"analgesicos", "w": 5, "n": [1, 2]}, {"id": &"municion_9mm", "w": 3, "n": [2, 5]},
		{"id": &"pistola", "w": 1, "n": [1, 1]}]},
	&"loose": {"chance": 0.5, "count": [1, 1], "entries": [
		{"id": &"lata_sopa", "w": 16, "n": [1, 1]}, {"id": &"chocolate", "w": 14, "n": [1, 1]}, {"id": &"vendas", "w": 12, "n": [1, 1]},
		{"id": &"lata_vacia", "w": 12, "n": [1, 2]}, {"id": &"cinta", "w": 8, "n": [1, 1]}, {"id": &"municion_9mm", "w": 8, "n": [1, 4]},
		{"id": &"flechas", "w": 6, "n": [1, 3]}, {"id": &"cartuchos", "w": 4, "n": [1, 2]}, {"id": &"bengala", "w": 4, "n": [1, 1]}]},
	# hunter's gear (the clearing / hunting cabins; GDD §9.2 "Cabaña / cazador")
	&"hunter": {"chance": 1.0, "count": [2, 3], "entries": [
		{"id": &"carne_seca", "w": 20, "n": [1, 3]}, {"id": &"cuerda", "w": 10, "n": [1, 2]}, {"id": &"flechas", "w": 20, "n": [4, 10]},
		{"id": &"arco", "w": 12, "n": [1, 1]}, {"id": &"municion_308", "w": 10, "n": [3, 6]}, {"id": &"guantes", "w": 8, "n": [1, 1]},
		{"id": &"rifle", "w": 5, "n": [1, 1]}]},
	# M6+ building tables (GDD §9.2)
	&"house": {"chance": 0.65, "count": [1, 3], "entries": [
		{"id": &"lata_judias", "w": 18, "n": [1, 2]}, {"id": &"lata_sopa", "w": 17, "n": [1, 2]}, {"id": &"abrigo", "w": 8, "n": [1, 1]},
		{"id": &"gorro", "w": 8, "n": [1, 1]}, {"id": &"guantes", "w": 9, "n": [1, 1]}, {"id": &"vendas", "w": 10, "n": [1, 2]},
		{"id": &"cinta", "w": 5, "n": [1, 1]}, {"id": &"cuchillo", "w": 5, "n": [1, 1]}, {"id": &"pistola", "w": 3, "n": [1, 1]},
		{"id": &"municion_9mm", "w": 6, "n": [1, 6]}, {"id": &"rifle", "w": 1, "n": [1, 1]}]},
	&"gas_station": {"chance": 0.65, "count": [1, 3], "entries": [
		{"id": &"lata_judias", "w": 18, "n": [1, 2]}, {"id": &"chocolate", "w": 20, "n": [1, 3]}, {"id": &"cinta", "w": 12, "n": [1, 2]},
		{"id": &"aceite_arma", "w": 8, "n": [1, 1]}, {"id": &"lata_vacia", "w": 10, "n": [1, 3]}, {"id": &"bengala", "w": 8, "n": [1, 2]},
		{"id": &"cartuchos", "w": 4, "n": [1, 3]}]},
	&"pharmacy": {"chance": 0.7, "count": [1, 3], "entries": [
		{"id": &"vendas", "w": 40, "n": [1, 3]}, {"id": &"analgesicos", "w": 30, "n": [1, 3]}, {"id": &"botiquin", "w": 10, "n": [1, 1]}]},
	&"police": {"chance": 0.7, "count": [1, 3], "entries": [
		{"id": &"municion_9mm", "w": 30, "n": [4, 12]}, {"id": &"pistola", "w": 20, "n": [1, 1]}, {"id": &"cartuchos", "w": 15, "n": [2, 6]},
		{"id": &"escopeta", "w": 8, "n": [1, 1]}, {"id": &"vendas", "w": 10, "n": [1, 2]}, {"id": &"municion_357", "w": 8, "n": [2, 6]},
		{"id": &"revolver", "w": 4, "n": [1, 1]}]},
	# M6b village / POI tables by building use (GDD §9.2: tienda, bar, taller, aserradero, granja; cars and dumpsters
	# outside). Items of the current Items.DB: nails, fuel, parts, chains and blueprints arrive with M7 / M8.
	&"shop": {"chance": 0.7, "count": [1, 3], "entries": [
		{"id": &"lata_judias", "w": 22, "n": [1, 3]}, {"id": &"lata_sopa", "w": 20, "n": [1, 3]}, {"id": &"chocolate", "w": 18, "n": [1, 3]},
		{"id": &"carne_seca", "w": 10, "n": [1, 2]}, {"id": &"cinta", "w": 8, "n": [1, 1]}, {"id": &"vendas", "w": 8, "n": [1, 2]},
		{"id": &"analgesicos", "w": 5, "n": [1, 2]}, {"id": &"bengala", "w": 5, "n": [1, 1]}, {"id": &"lata_vacia", "w": 4, "n": [1, 2]}]},
	&"bar": {"chance": 0.65, "count": [1, 3], "entries": [
		{"id": &"lata_judias", "w": 12, "n": [1, 2]}, {"id": &"lata_sopa", "w": 10, "n": [1, 2]}, {"id": &"chocolate", "w": 20, "n": [1, 3]},
		{"id": &"carne_seca", "w": 16, "n": [1, 3]}, {"id": &"analgesicos", "w": 6, "n": [1, 2]}, {"id": &"cuchillo", "w": 5, "n": [1, 1]},
		{"id": &"bate", "w": 4, "n": [1, 1]}, {"id": &"bengala", "w": 4, "n": [1, 1]}, {"id": &"municion_9mm", "w": 4, "n": [2, 6]},
		{"id": &"revolver", "w": 1, "n": [1, 1]}]},
	&"garage": {"chance": 0.7, "count": [1, 3], "entries": [
		{"id": &"cinta", "w": 20, "n": [1, 2]}, {"id": &"palanca", "w": 12, "n": [1, 1]}, {"id": &"aceite_arma", "w": 10, "n": [1, 1]},
		{"id": &"cuerda", "w": 10, "n": [1, 2]}, {"id": &"bengala", "w": 8, "n": [1, 2]}, {"id": &"lata_vacia", "w": 10, "n": [1, 3]},
		{"id": &"machete", "w": 3, "n": [1, 1]}, {"id": &"hacha", "w": 4, "n": [1, 1]}, {"id": &"bate", "w": 4, "n": [1, 1]},
		{"id": &"guantes", "w": 6, "n": [1, 1]}]},
	&"sawmill": {"chance": 0.75, "count": [1, 3], "entries": [
		{"id": &"madera", "w": 35, "n": [2, 6]}, {"id": &"cuerda", "w": 20, "n": [1, 2]}, {"id": &"cinta", "w": 10, "n": [1, 1]},
		{"id": &"hacha", "w": 10, "n": [1, 1]}, {"id": &"machete", "w": 4, "n": [1, 1]}, {"id": &"palanca", "w": 6, "n": [1, 1]},
		{"id": &"guantes", "w": 8, "n": [1, 1]}, {"id": &"bengala", "w": 4, "n": [1, 1]}, {"id": &"carne_seca", "w": 3, "n": [1, 2]}]},
	&"farm": {"chance": 0.7, "count": [1, 3], "entries": [
		{"id": &"carne_seca", "w": 18, "n": [1, 3]}, {"id": &"lata_judias", "w": 15, "n": [1, 2]}, {"id": &"cuerda", "w": 12, "n": [1, 2]},
		{"id": &"madera", "w": 10, "n": [1, 4]}, {"id": &"hacha", "w": 6, "n": [1, 1]}, {"id": &"guantes", "w": 8, "n": [1, 1]},
		{"id": &"gorro", "w": 6, "n": [1, 1]}, {"id": &"abrigo", "w": 5, "n": [1, 1]}, {"id": &"cartuchos", "w": 5, "n": [2, 5]},
		{"id": &"escopeta", "w": 2, "n": [1, 1]}]},
	&"car": {"chance": 0.5, "count": [1, 2], "entries": [
		{"id": &"chocolate", "w": 20, "n": [1, 2]}, {"id": &"cinta", "w": 12, "n": [1, 1]}, {"id": &"bengala", "w": 12, "n": [1, 2]},
		{"id": &"analgesicos", "w": 8, "n": [1, 2]}, {"id": &"vendas", "w": 10, "n": [1, 2]}, {"id": &"lata_vacia", "w": 10, "n": [1, 2]},
		{"id": &"guantes", "w": 6, "n": [1, 1]}, {"id": &"gorro", "w": 6, "n": [1, 1]}, {"id": &"municion_9mm", "w": 5, "n": [2, 6]},
		{"id": &"pistola", "w": 1, "n": [1, 1]}]},
	&"dumpster": {"chance": 0.4, "count": [1, 2], "entries": [
		{"id": &"lata_vacia", "w": 30, "n": [1, 3]}, {"id": &"cinta", "w": 10, "n": [1, 1]}, {"id": &"cuerda", "w": 8, "n": [1, 1]},
		{"id": &"madera", "w": 12, "n": [1, 3]}, {"id": &"lata_sopa", "w": 8, "n": [1, 1]}, {"id": &"guantes", "w": 4, "n": [1, 1]}]},
	&"military": {"chance": 0.8, "count": [1, 3], "entries": [
		{"id": &"racion", "w": 30, "n": [1, 3]}, {"id": &"cartuchos", "w": 15, "n": [3, 8]}, {"id": &"municion_308", "w": 12, "n": [3, 8]},
		{"id": &"botiquin", "w": 8, "n": [1, 1]}, {"id": &"abrigo", "w": 8, "n": [1, 1]}, {"id": &"rifle", "w": 4, "n": [1, 1]},
		{"id": &"escopeta", "w": 4, "n": [1, 1]}]},
}

## Nominal caps per region for 4 players (GDD §9.3 / C22: ammo and weapons are the scarce ones). Scaled by the
## number of players (×1 / 1.25 / 1.5 / 1.75, PLAN §3.2 "Escalado por jugadores"). Items without a cap are free.
const NOMINAL := {&"municion_9mm": 150, &"cartuchos": 40, &"municion_308": 25, &"municion_357": 40, &"flechas": 60,
	&"pistola": 6, &"revolver": 3, &"escopeta": 3, &"rifle": 2, &"arco": 3}


static func has(id: StringName) -> bool:
	return TABLES.has(id)


static func table(id: StringName) -> Dictionary:
	return TABLES.get(id, {})


## Container model per table (art T2: `props/loot/<name>.glb`; placeholders until the art lands).
static func model_for(id: StringName, loose: bool) -> String:
	if loose:
		return "can_beans"
	match id:
		&"campsite":
			return "backpack"
		&"lookout", &"hunter", &"cabin_forest", &"military", &"police":
			return "footlocker"
		&"house_kitchen":
			return "kitchen_cabinet"
		&"bar":
			return "fridge"
		&"garage", &"sawmill":
			return "locker"
		&"farm":
			return "footlocker"
	return "crate"
