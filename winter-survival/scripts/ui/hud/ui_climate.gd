class_name UiClimate
## Temperatures shown by the HUD (zone facts, Info block, thermal breakdown). The simulation has no air
## temperature yet (M8 thermal): this is the GDD v2 §4.1 table used as a presentation model — air −8 °C by day and
## −18 °C at night (blended over dusk 18–21 h and dawn 5–8 h), −10 °C more in a blizzard, plus the place's offset;
## "sentida" adds clothing, wind, shelter and heat sources. Numbers are rounded, the trend comes from the real
## warmth value (`Vitals` measures its rate).

const DAY_C := -8.0
const NIGHT_C := -18.0
const BLIZZARD_C := -10.0
const CLOTHES_C := 10.0
const COAT_C := 12.0
const WIND_C := 4.0
const WIND_NIGHT_C := 6.0
const WIND_BLIZZARD_C := 14.0
const SHELTER_C := 8.0
const HEAT_C := 30.0


## Air temperature (°C) at a clock hour and weather.
static func air(hour: float, blizzard: bool) -> float:
	var t := NIGHT_C
	if hour >= 8.0 and hour < 18.0:
		t = DAY_C
	elif hour >= 18.0 and hour < 21.0:
		t = lerpf(DAY_C, NIGHT_C, (hour - 18.0) / 3.0)
	elif hour >= 5.0 and hour < 8.0:
		t = lerpf(NIGHT_C, DAY_C, (hour - 5.0) / 3.0)
	return t + (BLIZZARD_C if blizzard else 0.0)


static func air_now() -> float:
	return air(WorldState.hour_now(), WorldState.weather_now() == &"blizzard")


## Feels-like breakdown for the local player: [[label, °C], …] and the total (GDD §4.1 rows).
static func breakdown(p: Player) -> Dictionary:
	var blizzard := WorldState.weather_now() == &"blizzard"
	var rows: Array = [["ambiente", air_now()]]
	var st: PlayerState = p.state if p != null else null
	var clothes := CLOTHES_C + (COAT_C if st != null and st.has_coat else 0.0)
	rows.append(["ropa", clothes])
	var inside := p != null and p.in_house
	if not inside:
		var w := WIND_BLIZZARD_C if blizzard else (WIND_NIGHT_C if WorldState.is_night_now() else WIND_C)
		rows.append(["viento", -w])
	else:
		rows.append(["refugio", SHELTER_C])
	if p != null and p.is_near_fire():
		rows.append(["fuego", HEAT_C])
	elif inside and stove_lit_near(p, 12.0):
		rows.append(["estufa", HEAT_C])
	var total := 0.0
	for r: Array in rows:
		total += float(r[1])
	return {"rows": rows, "feels": total}


## A lit stove within `r` metres (client side: the stove's replicated `is_lit`).
static func stove_lit_near(p: Node3D, r: float) -> bool:
	for s in p.get_tree().get_nodes_in_group("stove"):
		if s is Node3D and bool(s.get("is_lit")) and (s as Node3D).global_position.distance_to(p.global_position) <= r:
			return true
	return false
