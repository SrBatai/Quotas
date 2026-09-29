class_name WeaponState
extends RefCounted
## Firearm state of one player (ARQ v2 §11.3, M5). Server: authoritative (Gunplay). Owner client: the same model
## predicted from its own inputs for the reticle (FirearmClient), corrected by the `gun` mirror. The rounds in the
## magazine live in the HAND slot (`"ammo"`: they travel with the gun into a container or a corpse); this holds
## what belongs to the shooter's hands: spread, cadence, reload / unjam timers, jam and gun oil.

var weapon: StringName = &""
## Current dispersion (degrees): posture target + recoil (Firearms.step_spread).
var spread: float = 0.0
var last_shot: float = -100.0
## Reload in progress: ends at `reload_until` (s, Time ticks); the shotgun re-arms per shell.
var reload_until: float = -1.0
var reload_total: float = 0.0
var jammed: bool = false
var unjam_until: float = -1.0
## Gun oil (GDD §7.3): no cold jams until this time (s, Time ticks).
var oil_until: float = -1.0
var shots: int = 0
## Bow: the draw started at (s); -1 = not drawing.
var draw_start: float = -1.0


func reset(id: StringName) -> void:
	weapon = id
	spread = float(Firearms.of(id).get("spread_min", 0.0)) + Balance.GUN_SPREAD_WALK
	reload_until = -1.0
	reload_total = 0.0
	unjam_until = -1.0
	draw_start = -1.0


func reloading(now: float) -> bool:
	return reload_until >= 0.0 and now < reload_until + 5.0


func unjamming() -> bool:
	return unjam_until >= 0.0


## Mirror for the owner (reticle / ammo HUD data): {ammo, mag, reserve, jammed, reload_left, reload_total, spread}.
func to_mirror(ammo_in: int, reserve: int, now: float) -> Dictionary:
	return {"w": String(weapon), "ammo": ammo_in, "mag": Firearms.mag_of(weapon), "reserve": reserve, "jammed": jammed,
		"reload_left": maxf(reload_until - now, 0.0) if reload_until >= 0.0 else -1.0, "reload_total": reload_total,
		"unjam_left": maxf(unjam_until - now, 0.0) if unjam_until >= 0.0 else -1.0, "spread": spread}
