class_name DamageResolver
## The single point that reads `rules.pvp` / `rules.friendly_fire` (PLAN C20, ARQ v2 §11). M2 = v0: player→player
## gating, the animal/world paths (wolves, deer and anything with `take_damage`), kind multipliers, knockback
## and the kill flag. M4: zombie victims (ZombieSystem records by slot: criticals ×Balance.MELEE_CRIT_MULT, frozen
## ones shatter ×Balance.FROZEN_BLUNT_MULT under blunt weapons, knockdown chance, push direction), zombie attackers
## (bites → the player's StatsComponent, which downs it at 0) and the death cause per attacker kind.

enum Kind { PLAYER, ZOMBIE, ANIMAL, VEHICLE, WORLD, FIRE }
enum DamageKind { MELEE_BLUNT, MELEE_SHARP, MELEE_PIERCE, BULLET, BUCKSHOT, ARROW, EXPLOSION, FIRE, VEHICLE, FALL, COLD, BITE }

const FF_MULT := {"off": 0.0, "reduced": 0.25, "full": 1.0}
## v0 multipliers per damage kind against animals (sharp tools hunt; bare hands barely hurt).
const ANIMAL_KIND_MULT := {DamageKind.MELEE_BLUNT: 0.8, DamageKind.MELEE_SHARP: 1.0, DamageKind.MELEE_PIERCE: 1.1,
	DamageKind.BULLET: 1.5, DamageKind.BUCKSHOT: 1.5, DamageKind.ARROW: 1.2, DamageKind.FIRE: 0.5}
## Horizontal push (m/s) an animal receives per hit, by kind.
const KNOCKBACK := {DamageKind.MELEE_BLUNT: 6.0, DamageKind.MELEE_SHARP: 6.0, DamageKind.MELEE_PIERCE: 4.0}
## Death cause recorded on a player per attacker kind (GDD v2 §5 "Causa registrada").
const SOURCE := {Kind.PLAYER: &"jugador", Kind.ZOMBIE: &"zombi", Kind.ANIMAL: &"lobo", Kind.FIRE: &"fuego"}

## Test counters: applications per victim kind and blocked player→player hits.
static var applied_count: Dictionary = {}
static var blocked_pvp: int = 0


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


## Resolves damage; returns {"applied": float, "blocked": bool, "reason": String, "killed": bool, "knockback": Vector3,
## "crit": bool}. The victim node must expose `take_damage(amount, source_name[, attacker_name])` (players) or
## `take_damage(amount, from_node)` (animals via HealthComponent) and, optionally, `is_dead()`. Zombies have no node:
## `ctx.slot` names the ZombieSystem record (+ `crit`, `knock` chance, `dir` push).
static func apply(attacker: Dictionary, victim: Dictionary, victim_node: Node, dmg: float, dmg_kind: DamageKind, rules: Dictionary, attacker_node: Node = null, ctx: Dictionary = {}) -> Dictionary:
	var result := {"applied": 0.0, "blocked": true, "reason": "", "killed": false, "knockback": Vector3.ZERO, "crit": false}
	var mult := 1.0
	var victim_kind := int(victim.get("kind", -1))
	var attacker_kind := int(attacker.get("kind", -1))
	if victim_kind == Kind.PLAYER and attacker_kind == Kind.PLAYER:
		mult = player_vs_player_mult(rules, attacker, victim, dmg_kind)
		if mult <= 0.0:
			result["reason"] = "friendly_fire"
			blocked_pvp += 1
			return result
	elif victim_kind == Kind.ANIMAL:
		mult = float(ANIMAL_KIND_MULT.get(dmg_kind, 1.0))
	if victim_kind == Kind.ZOMBIE:
		return _apply_zombie(attacker, dmg, dmg_kind, ctx, result)
	if victim_node == null or not is_instance_valid(victim_node):
		result["reason"] = "no_victim"
		return result
	var amount := maxf(dmg, 0.0) * mult
	var was_dead := victim_node.has_method("is_dead") and bool(victim_node.call("is_dead"))
	if victim_kind == Kind.PLAYER:
		var source: StringName = SOURCE.get(attacker_kind, &"jugador")
		var who := ""
		if attacker_kind == Kind.PLAYER and attacker_node is Player:
			who = (attacker_node as Player).display_name
		if victim_node is Player:
			(victim_node as Player).take_damage(amount, source, who)
		else:
			victim_node.call("take_damage", amount, source)
	else:
		if attacker_node is Node3D and victim_node is Node3D and KNOCKBACK.has(dmg_kind):
			var away: Vector3 = (victim_node as Node3D).global_position - (attacker_node as Node3D).global_position
			away.y = 0.0
			if away.length() > 0.01:
				result["knockback"] = away.normalized() * float(KNOCKBACK[dmg_kind])
		victim_node.call("take_damage", amount, attacker_node)
	applied_count[victim_kind] = int(applied_count.get(victim_kind, 0)) + 1
	result["applied"] = amount
	result["blocked"] = false
	result["killed"] = not was_dead and victim_node.has_method("is_dead") and bool(victim_node.call("is_dead"))
	return result


static func _apply_zombie(attacker: Dictionary, dmg: float, dmg_kind: DamageKind, ctx: Dictionary, result: Dictionary) -> Dictionary:
	var sys := ZombieSystem.instance
	var slot := int(ctx.get("slot", -1))
	if sys == null or not sys.is_alive(slot):
		result["reason"] = "no_victim"
		return result
	var amount := maxf(dmg, 0.0)
	var crit := bool(ctx.get("crit", false))
	if crit:
		amount *= Balance.MELEE_CRIT_MULT
	if sys.kind[slot] == ZombieKinds.Kind.FROZEN and dmg_kind == DamageKind.MELEE_BLUNT:
		amount *= Balance.FROZEN_BLUNT_MULT
	var knock := float(ctx.get("knock", 0.0)) if dmg_kind == DamageKind.MELEE_BLUNT else 0.0
	var peer := int(attacker.get("id", 0)) if int(attacker.get("kind", -1)) == Kind.PLAYER else 0
	# a critical kill bursts the head (gore-lite, ASSET_SPEC v2 M4.1) unless the blade is the knife (`gore` false)
	var killed := sys.apply_damage(slot, amount, peer, ctx.get("dir", Vector3.FORWARD), crit, knock, false, crit and bool(ctx.get("gore", true)))
	applied_count[Kind.ZOMBIE] = int(applied_count.get(Kind.ZOMBIE, 0)) + 1
	result["applied"] = amount
	result["blocked"] = false
	result["killed"] = killed
	result["crit"] = crit
	return result
