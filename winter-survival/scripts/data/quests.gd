class_name Quests
## Quest definitions (GDD §13). Each step: title, hint, trigger (Events signal name), filter, count.
## "count_arg" = index of the signal argument that carries the amount (item_picked_up → amount).


static func _wood_filter() -> Callable:
	return func(args: Array) -> bool: return args.size() > 0 and args[0] == &"madera"


static func _recipe_filter(id: StringName) -> Callable:
	return func(args: Array) -> bool: return args.size() > 0 and args[0] == id


static func for_day(day: int) -> Dictionary:
	if day <= 1:
		return {
			"title_small": "PRIMER DÍA",
			"title_big": "SOBREVIVE",
			"steps": [
				{"title": "Recoge leña", "hint": "Haz clic en la leña del suelo",
					"trigger": &"item_picked_up", "filter": _wood_filter(), "count": 2, "count_arg": 1},
				{"title": "Entra en casa y alimenta la estufa", "hint": "Si la estufa se apaga, la casa se enfría",
					"trigger": &"stove_fueled", "filter": null, "count": 1},
				{"title": "Fabrica un hacha", "hint": "Herramientas → Hacha de piedra",
					"trigger": &"crafted", "filter": _recipe_filter(&"hacha"), "count": 1},
				{"title": "Tala un árbol", "hint": "Haz clic en un árbol con el hacha",
					"trigger": &"tree_felled", "filter": null, "count": 1},
				{"title": "Come algo", "hint": "Busca latas en el armario",
					"trigger": &"item_consumed", "filter": null, "count": 1},
				{"title": "Fabrica una fogata", "hint": "Fuego → Fogata, colócala cerca de casa",
					"trigger": &"campfire_placed", "filter": null, "count": 1},
				{"title": "Fabrica una antorcha", "hint": "Los lobos temen al fuego",
					"trigger": &"crafted", "filter": _recipe_filter(&"antorcha"), "count": 1},
				{"title": "Sobrevive hasta el amanecer", "hint": "Quédate cerca del fuego",
					"trigger": &"day_started", "filter": null, "count": 1},
			],
		}
	var last_title := "Sobrevive hasta el amanecer final" if day >= 5 else "Sobrevive hasta el amanecer"
	return {
		"title_small": "DÍA %d" % day,
		"title_big": "SOBREVIVE",
		"steps": [
			{"title": "Mantén la estufa encendida", "hint": "Añade leña a la estufa",
				"trigger": &"stove_fueled", "filter": null, "count": 1},
			{"title": "Consigue 6 de madera", "hint": "Tala árboles o recoge leña",
				"trigger": &"item_picked_up", "filter": _wood_filter(), "count": 6, "count_arg": 1},
			{"title": "Come algo", "hint": "Cocina o abre una lata",
				"trigger": &"item_consumed", "filter": null, "count": 1},
			{"title": last_title, "hint": "Quédate cerca del fuego",
				"trigger": &"day_started", "filter": null, "count": 1},
		],
	}
