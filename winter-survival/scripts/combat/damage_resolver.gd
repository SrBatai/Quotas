class_name DamageResolver
## The single point that reads `rules.pvp` / `rules.friendly_fire` (PLAN C20, ARQ v2 §11). M1 stub: player→player
## gating and the animal/world paths; M4 adds zones, criticals, armour, downed state and dismemberment.

enum Kind { PLAYER, ZOMBIE, ANIMAL, VEHICLE, WORLD, FIRE }
enum DamageKind { MELEE_BLUNT, MELEE_SHARP, MELEE_PIERCE, BULLET, BUCKSHOT, ARROW, EXPLOSION, FIRE, VEHICLE, FALL, COLD, BITE }

const FF_MULT := {"off": 0.0, "reduced": 0.25, "full": 1.0}


static func ref(kind: Kind, id: int = 0, faction: String = "") -> Dictionary:
	return {"kind": kind, "id": id, "faction": faction}


## Player→player multiplier for the current server rules (0.0 = blocked).
static func player_vs_player_mult(rules: Dictionary, attacker: Dictionary, victim: Dictionary, dmg_kind: DamageKind) -> float:
	var pvp := bool(rules.get("pvp", false))
	if pvp and String(attacker.get("faction", "")) != String(victim.get("faction", "")):
		return 1.0
	var ff := String(rules.get("friendly_fire", "off")).to_lower()
	var mult := float(FF_MULT.get(ff, 0.0))
	if ff == "reduced" and dmg_kind == DamageKind.EXPLOSION:
		mult *= 0.5
	return mult


## Resolves damage; returns {"applied": float, "blocked": bool, "reason": String}. The victim node must expose
## `take_damage(amount, source_name)` (players) or `take_damage(amount, from_node)` (animals via HealthComponent).
static func apply(attacker: Dictionary, victim: Dictionary, victim_node: Node, dmg: float, dmg_kind: DamageKind, rules: Dictionary, attacker_node: Node = null) -> Dictionary:
	var mult := 1.0
	if int(victim.get("kind", -1)) == Kind.PLAYER and int(attacker.get("kind", -1)) == Kind.PLAYER:
		mult = player_vs_player_mult(rules, attacker, victim, dmg_kind)
		if mult <= 0.0:
			return {"applied": 0.0, "blocked": true, "reason": "friendly_fire"}
	var amount := maxf(dmg, 0.0) * mult
	if victim_node == null or not is_instance_valid(victim_node):
		return {"applied": 0.0, "blocked": true, "reason": "no_victim"}
	if int(victim.get("kind", -1)) == Kind.PLAYER:
		var source: StringName = &"lobo" if int(attacker.get("kind", -1)) == Kind.ANIMAL else &"jugador"
		victim_node.call("take_damage", amount, source)
	else:
		victim_node.call("take_damage", amount, attacker_node)
	return {"applied": amount, "blocked": false, "reason": ""}
