class_name Weapons
## Melee weapon table, M4 rows (GDD v2 §7.1 / §7.6; caminante = 100 PV). Keyed by the inventory item id held in
## the HAND slot; no weapon = fists. Damage per hit, crit chance (×Balance.MELEE_CRIT_MULT), cadence (s between
## swings), reach (m, the server adds Balance.MELEE_REACH_TOLERANCE), targets per swing, noise radius (m) and
## durability N (the weapon loses a point with probability 100/N per hit: it lasts about N hits). `clip` names the
## player animation (ASSET_SPEC v2 §6.2; code-generated stand-ins until humanoid_combat.glb exists). `model` is
## the weapons/<name>.glb of §12 (identity on RightHandSocket).

const FISTS := &""

const TABLE := {
	&"": {"name": "Puños", "kind": DamageResolver.DamageKind.MELEE_BLUNT, "dmg": 6.0, "crit": 0.0, "cadence": 0.6,
		"reach": 1.1, "targets": 1, "noise": 4.0, "dur_n": 0, "class": &"Unarmed", "clip": &"Melee1H_Light_A", "knock": 0.05},
	&"cuchillo": {"name": "Cuchillo de caza", "kind": DamageResolver.DamageKind.MELEE_SHARP, "dmg": 18.0, "crit": 0.10,
		"cadence": 0.40, "reach": 1.2, "targets": 1, "noise": 3.0, "dur_n": 250, "class": &"Melee1H",
		"clip": &"Melee1H_Light_A", "knock": 0.0, "execute": true, "model": "knife"},
	&"palanca": {"name": "Palanca", "kind": DamageResolver.DamageKind.MELEE_BLUNT, "dmg": 28.0, "crit": 0.15,
		"cadence": 0.70, "reach": 1.6, "targets": 1, "noise": 8.0, "dur_n": 800, "class": &"Melee1H",
		"clip": &"Melee1H_Light_B", "knock": 0.15, "model": "crowbar"},
	&"bate": {"name": "Bate", "kind": DamageResolver.DamageKind.MELEE_BLUNT, "dmg": 30.0, "crit": 0.20,
		"cadence": 0.65, "reach": 1.7, "targets": 2, "noise": 10.0, "dur_n": 300, "class": &"Melee2H",
		"clip": &"Melee2H_Swing_A", "knock": 0.35, "model": "bat"},
	&"bate_clavos": {"name": "Bate con clavos", "kind": DamageResolver.DamageKind.MELEE_BLUNT, "dmg": 38.0, "crit": 0.20,
		"cadence": 0.65, "reach": 1.7, "targets": 2, "noise": 10.0, "dur_n": 150, "class": &"Melee2H",
		"clip": &"Melee2H_Swing_B", "knock": 0.35, "model": "bat_nailed"},
	&"hacha": {"name": "Hacha", "kind": DamageResolver.DamageKind.MELEE_SHARP, "dmg": 45.0, "crit": 0.30,
		"cadence": 0.90, "reach": 1.7, "targets": 2, "noise": 10.0, "dur_n": 400, "class": &"Melee2H",
		"clip": &"Melee2H_Swing_A", "knock": 0.1, "model": "stone_axe"},
	&"machete": {"name": "Machete", "kind": DamageResolver.DamageKind.MELEE_SHARP, "dmg": 38.0, "crit": 0.20,
		"cadence": 0.55, "reach": 1.5, "targets": 1, "noise": 8.0, "dur_n": 350, "class": &"Melee1H",
		"clip": &"Melee1H_Light_B", "knock": 0.05, "model": "machete"},
}

## Attack kinds (request_melee `mode`).
enum Mode { LIGHT, CHARGED, SHOVE, STOMP, EXECUTE }


static func is_weapon(id: StringName) -> bool:
	return id != &"" and TABLE.has(id)


## The row for the hand item (fists for anything that is not a weapon, e.g. the torch).
static func of(hand: StringName) -> Dictionary:
	return TABLE.get(hand, TABLE[FISTS])


static func can_execute(hand: StringName) -> bool:
	return bool(of(hand).get("execute", false))


## Seconds the swing locks the attacker (charged adds the wind-up).
static func cadence(hand: StringName, mode: int) -> float:
	var c := float(of(hand)["cadence"])
	match mode:
		Mode.CHARGED:
			return c + Balance.MELEE_CHARGED_EXTRA
		Mode.SHOVE:
			return Balance.SHOVE_TIME
		Mode.STOMP:
			return Balance.STOMP_TIME
		Mode.EXECUTE:
			return Balance.EXECUTE_TIME
	return c


## Player animation for an attack (ASSET_SPEC v2 §6.2 names; the view falls back to generated clips).
static func clip(hand: StringName, mode: int) -> StringName:
	match mode:
		Mode.CHARGED:
			return &"Melee_Charged"
		Mode.SHOVE:
			return &"Act_Shove"
		Mode.STOMP:
			return &"Act_Stomp"
		Mode.EXECUTE:
			return &"Act_Execute"
	return of(hand)["clip"]


## Seconds from the accepted request to the server's damage check = `hit_start` of the clip (data/anim_events.json,
## ASSET_SPEC v2 M4.3): the blow lands when the animation connects. CHARGED: the owner has been holding the wind-up
## pose (Melee_Charged hold_start…hold_end) and the release jumps to hold_end, so the strike lands
## hit_start − hold_end later. EXECUTE: the first stab (`stab`). Without the file: the pre-M4 instant hit (0).
static func hit_delay(hand: StringName, mode: int) -> float:
	var c := String(clip(hand, mode))
	match mode:
		Mode.CHARGED:
			return maxf(AnimEvents.at(c, "hit_start", 0.0) - AnimEvents.at(c, "hold_end", 0.0), 0.0)
		Mode.EXECUTE:
			return AnimEvents.at(c, "stab", 0.0)
	return AnimEvents.at(c, "hit_start", 0.0)
