class_name ZombieKinds
## Zombie roster, M4 batch (GDD v2 §6.1): walker, runner, crawler, frozen, bloater. One row per kind, indexed by
## the `kind` byte that travels in ZENTER / the SoA (`ZombieSystem.kind`). Speeds in m/s, damage per hit, cadence
## in s, senses in m (vision per light: day / night / blizzard) and the cone in degrees. `share` = weight in a
## mixed population (GDD "% población"); `min_day` = first day it can appear. Models follow ASSET_SPEC v2 §5.2:
## `zombies/zombie_<model>_<nn>.glb`, `variants` files per kind (the frozen use the walker bodies + ice).

enum Kind { WALKER, RUNNER, CRAWLER, FROZEN, BLOATER }

## Replicated brain states (ARQ v2 §6.3 `state` byte).
enum State { IDLE, WANDER, INVESTIGATE, CHASE, ATTACK, HIT, STAGGER, KNOCKED, DEAD, FROZEN, WAKING, GRAB, SCREAM, EAT, SLEEP }

## Flags (3 high bits of the replicated state byte).
const FLAG_TIRED := 1      # runner in its slow phase
const FLAG_GRAB := 2       # holding a player (P1)
const FLAG_BURN := 4       # on fire (M5)

const TABLE := [
	{"id": &"walker", "name": "Caminante", "hp": 100.0, "speed": 1.2, "speed_var": 0.2, "dmg": 12.0, "cadence": 1.2,
		"reach": 1.35, "vision": [25.0, 12.0, 6.0], "cone": 120.0, "hearing": 1.0, "smell": 8.0, "share": 70.0, "min_day": 1,
		"model": "walker", "variants": 24, "authored": 1.2, "radius": 0.32},
	{"id": &"runner", "name": "Corredor", "hp": 70.0, "speed": 5.5, "speed_var": 0.0, "dmg": 10.0, "cadence": 0.9,
		"reach": 1.35, "vision": [30.0, 14.0, 6.0], "cone": 90.0, "hearing": 1.0, "smell": 8.0, "share": 8.0, "min_day": 3,
		"model": "runner", "variants": 6, "authored": 5.5, "radius": 0.3,
		"burst": 4.0, "tired": 3.0, "tired_speed": 3.0},
	{"id": &"crawler", "name": "Reptador", "hp": 50.0, "speed": 1.0, "speed_var": 0.1, "dmg": 8.0, "cadence": 1.0,
		"reach": 1.1, "vision": [8.0, 6.0, 4.0], "cone": 120.0, "hearing": 1.5, "smell": 8.0, "share": 7.0, "min_day": 1,
		"model": "crawler", "variants": 4, "authored": 1.0, "radius": 0.3},
	{"id": &"frozen", "name": "Congelado", "hp": 100.0, "speed": 0.96, "speed_var": 0.1, "dmg": 12.0, "cadence": 1.2,
		"reach": 1.35, "vision": [25.0, 12.0, 6.0], "cone": 120.0, "hearing": 1.0, "smell": 8.0, "share": 10.0, "min_day": 1,
		"model": "walker", "variants": 8, "authored": 1.2, "radius": 0.32,
		"wake_noise": 15.0, "wake_noise_dist": 8.0, "wake_touch": 1.5, "wake_heat": 4.0, "woken_mult": 0.8, "woken_time": 30.0},
	{"id": &"bloater", "name": "Hinchado", "hp": 150.0, "speed": 0.9, "speed_var": 0.05, "dmg": 15.0, "cadence": 1.5,
		"reach": 1.4, "vision": [15.0, 10.0, 5.0], "cone": 120.0, "hearing": 1.0, "smell": 8.0, "share": 3.0, "min_day": 5,
		"model": "bloater", "variants": 4, "authored": 0.9, "radius": 0.45,
		"cloud_radius": 4.0, "cloud_time": 8.0, "cloud_warmth": 5.0},
]


static func row(kind: int) -> Dictionary:
	return TABLE[clampi(kind, 0, TABLE.size() - 1)]


static func count() -> int:
	return TABLE.size()


static func id_of(kind: int) -> StringName:
	return row(kind)["id"]


static func kind_of(id: StringName) -> int:
	for i in TABLE.size():
		if TABLE[i]["id"] == id:
			return i
	return -1


static func max_hp(kind: int) -> float:
	return float(row(kind)["hp"])


## Vision range for the current light (GDD §6.2 / §6.5): day, night or blizzard.
static func vision(kind: int, night: bool, blizzard: bool) -> float:
	var v: Array = row(kind)["vision"]
	if blizzard:
		return float(v[2])
	return float(v[1]) if night else float(v[0])


## Model name for Assets.spawn_model (ASSET_SPEC v2 §5.2): zombies/zombie_<model>_<nn>, nn from 01.
static func model_name(kind: int, variant: int) -> String:
	var r := row(kind)
	var n := int(r["variants"])
	return "zombies/zombie_%s_%02d" % [r["model"], posmod(variant, maxi(n, 1)) + 1]


## Pick a kind for a random population slot (weights = GDD share, kinds gated by the day). `frozen` is never
## picked here: freezing is a state the population puts walkers in (GDD §6.4 "recicla población").
static func pick(u: float, day: int, allow_bloater: bool = true) -> int:
	var total := 0.0
	for i in TABLE.size():
		if _eligible(i, day, allow_bloater):
			total += float(TABLE[i]["share"])
	var x := u * total
	for i in TABLE.size():
		if not _eligible(i, day, allow_bloater):
			continue
		x -= float(TABLE[i]["share"])
		if x <= 0.0:
			return i
	return Kind.WALKER


static func _eligible(i: int, day: int, allow_bloater: bool) -> bool:
	if i == Kind.FROZEN:
		return false
	if i == Kind.BLOATER and not allow_bloater:
		return false
	return day >= int(TABLE[i]["min_day"])
