class_name Firearms
## Ranged weapons of M5 (GDD v2 §7.2–§7.6, ARQ v2 §11.3; caminante = 100 PV). Keyed by the inventory item held in
## the HAND slot. Pure data + pure helpers shared by the server (Gunplay: validation, hits, noise) and the owner
## client (FirearmClient: prediction of the spread reticle, recoil, ammo, reload timing).
##   dmg / pellets     damage per hit (per pellet for the shotgun: 8 × 12)
##   crit              base critical chance (×Balance.GUN_CRIT_MULT; +GUN_CRIT_GREEN when the reticle is green)
##   cadence           s between two shots (the bow: its full draw)
##   range / max_range effective range (full damage) and the farthest a shot counts (linear falloff to 50 %)
##   pierce            victims one bullet goes through (revolver / rifle 2, "atraviesa 2 en línea")
##   spread_min        minimum dispersion (degrees, full cone angle / 2), `cone` = fixed pellet cone of the shotgun
##   recoil            degrees added to the spread per shot (recovered at Balance.GUN_RECOIL_RECOVER °/s)
##   noise             SoundEvents radius (m, GDD §6.3): pistol 80 · revolver 90 · rifle 120 · shotgun 150 · bow 5
##   mag / ammo        magazine size and the ammo item; `reload` s (clip = anim, events from data/anim_events.json),
##                     `per_shell` = the shotgun loads one shell per `reload` s and can be interrupted
##   knock / push      zombie knockdown chance and flinch push (m) per hit
##   dur_n             durability N (a point lost with probability 100/N per shot)
##   lean              camera lean toward the cursor (m, GDD §3.1: 3 m, rifle with scope 6 m)
##   jam_cold          extra jam chance per shot when cold (GDD §7.3: < −15 °C without gun oil)
## `class` picks the player's upper-body layer (ASSET_SPEC v2 §6.2: Pistol / LongGun / Bow).

const TABLE := {
	&"pistola": {"name": "Pistola 9 mm", "class": &"Pistol", "kind": DamageResolver.DamageKind.BULLET, "dmg": 25.0, "pellets": 1,
		"crit": 0.15, "cadence": 0.25, "range": 15.0, "max_range": 40.0, "pierce": 1, "spread_min": 1.5, "cone": 0.0,
		"recoil": 2.0, "noise": 80.0, "mag": 15, "ammo": &"municion_9mm", "reload": 1.6, "per_shell": false,
		"knock": 0.05, "push": 0.4, "dur_n": 1500, "lean": 3.0, "jam_cold": 0.05, "model": "pistol",
		"clip_aim": &"Pistol_Aim", "clip_shoot": &"Pistol_Shoot", "clip_reload": &"Pistol_Reload", "sfx": &"gun_pistol"},
	&"revolver": {"name": "Revólver .357", "class": &"Pistol", "kind": DamageResolver.DamageKind.BULLET, "dmg": 45.0, "pellets": 1,
		"crit": 0.20, "cadence": 0.50, "range": 18.0, "max_range": 45.0, "pierce": 2, "spread_min": 1.2, "cone": 0.0,
		"recoil": 4.0, "noise": 90.0, "mag": 6, "ammo": &"municion_357", "reload": 3.0, "per_shell": false,
		"knock": 0.15, "push": 0.6, "dur_n": 2000, "lean": 3.0, "jam_cold": 0.05, "model": "revolver",
		"clip_aim": &"Pistol_Aim", "clip_shoot": &"Pistol_Shoot", "clip_reload": &"Pistol_Reload_Revolver", "sfx": &"gun_revolver"},
	&"escopeta": {"name": "Escopeta de corredera", "class": &"LongGun", "kind": DamageResolver.DamageKind.BUCKSHOT, "dmg": 8.0, "pellets": 12,
		"crit": 0.10, "cadence": 0.90, "range": 10.0, "max_range": 22.0, "pierce": 1, "spread_min": 1.5, "cone": 10.0,
		"recoil": 9.0, "noise": 150.0, "mag": 6, "ammo": &"cartuchos", "reload": 0.7, "per_shell": true, "max_victims": 4,
		"knock": 0.70, "push": 1.0, "dur_n": 1200, "lean": 3.0, "jam_cold": 0.05, "model": "shotgun",
		"clip_aim": &"LongGun_Aim", "clip_shoot": &"LongGun_Shoot_Shotgun", "clip_reload": &"LongGun_Reload_Shell", "sfx": &"gun_shotgun"},
	&"rifle": {"name": "Rifle .308", "class": &"LongGun", "kind": DamageResolver.DamageKind.BULLET, "dmg": 90.0, "pellets": 1,
		"crit": 0.40, "cadence": 1.5, "range": 45.0, "max_range": 60.0, "pierce": 2, "spread_min": 0.5, "cone": 0.0,
		"recoil": 6.0, "noise": 120.0, "mag": 5, "ammo": &"municion_308", "reload": 3.5, "per_shell": false,
		"knock": 0.35, "push": 0.8, "dur_n": 2500, "lean": 6.0, "jam_cold": 0.05, "model": "rifle_hunting",
		"clip_aim": &"LongGun_Aim", "clip_shoot": &"LongGun_Shoot", "clip_reload": &"LongGun_Reload_Bolt", "sfx": &"gun_rifle"},
	&"arco": {"name": "Arco de caza", "class": &"Bow", "kind": DamageResolver.DamageKind.ARROW, "dmg": 40.0, "pellets": 1,
		"crit": 0.25, "cadence": 1.4, "range": 25.0, "max_range": 30.0, "pierce": 1, "spread_min": 1.0, "cone": 0.0,
		"recoil": 1.0, "noise": 5.0, "mag": 1, "ammo": &"flechas", "reload": 0.0, "per_shell": false, "projectile": true,
		"arrow_speed": 42.0, "recover": 0.6, "knock": 0.05, "push": 0.3, "dur_n": 300, "lean": 3.0, "jam_cold": 0.0, "model": "bow",
		"clip_aim": &"Bow_Aim", "clip_shoot": &"Bow_Release", "clip_reload": &"Bow_Draw", "sfx": &"bow_release"},
}

## Reticle bands (GDD §7.1): red > 8°, amber 4–8°, green < 4°; grey = an ally blocks the line (friendly fire off).
enum Band { GREEN, AMBER, RED, GREY }


static func is_firearm(id: StringName) -> bool:
	return id != &"" and TABLE.has(id)


static func is_bow(id: StringName) -> bool:
	return TABLE.has(id) and bool(TABLE[id].get("projectile", false))


static func of(id: StringName) -> Dictionary:
	return TABLE.get(id, {})


static func ammo_of(id: StringName) -> StringName:
	return StringName(of(id).get("ammo", &""))


static func mag_of(id: StringName) -> int:
	return int(of(id).get("mag", 0))


## Seconds of a full reload (per shell for the shotgun). The clip's `mag_in` / `shell_in` / `bolt_close` event from
## data/anim_events.json (ASSET_SPEC v2 §6.1) is the moment the rounds count; without it the GDD §7.4 time.
static func reload_time(id: StringName) -> float:
	var f := of(id)
	if f.is_empty():
		return 0.0
	var clip := String(f["clip_reload"])
	for ev in ["mag_in", "shell_in", "bolt_close", "load"]:
		if AnimEvents.has(clip, ev):
			return maxf(AnimEvents.at(clip, ev, 0.0), 0.2)
	return float(f["reload"])


## Seconds to clear a jam (Act_Unjam, GDD §7.3: 1.5 s).
static func unjam_time() -> float:
	return AnimEvents.at("Act_Unjam", "clear", Balance.GUN_UNJAM_TIME)


## Reticle band of a spread angle (degrees).
static func band(spread_deg: float) -> int:
	if spread_deg > Balance.GUN_BAND_RED:
		return Band.RED
	if spread_deg >= Balance.GUN_BAND_AMBER:
		return Band.AMBER
	return Band.GREEN


static func band_name(b: int) -> StringName:
	return [&"green", &"amber", &"red", &"grey"][clampi(b, 0, 3)]


## Target spread (degrees) for the shooter's posture (GDD §7.4): the weapon minimum (×0.6 with Puntería 10: skills
## arrive in M8) + walking 3 / running 8 / crouched −1, ×1.5 when Calor < 15. The shotgun's pellet cone is fixed.
static func target_spread(id: StringName, speed: float, running: bool, crouching: bool, warmth: float) -> float:
	var f := of(id)
	if f.is_empty():
		return 0.0
	var s := float(f["spread_min"])
	if running and speed > 0.5:
		s += Balance.GUN_SPREAD_RUN
	elif speed > 0.3:
		s += Balance.GUN_SPREAD_WALK
	elif crouching:
		s += Balance.GUN_SPREAD_CROUCH
	s = maxf(s, float(f["spread_min"]) * 0.5)
	if warmth < Balance.FREEZING_SLOW_BELOW:
		s *= Balance.GUN_SPREAD_COLD_MULT
	return s


## One step of the spread model (shared by the server and the owner's prediction): opens fast toward a bigger
## target and closes linearly at GUN_SPREAD_CLOSE_RATE (14 °/s): a running opening (+8°) is gone in ≤ 0.8 s standing
## still (GDD §7.1) and the recoil recovers at ≈ the 12 °/s of GDD §7.4.
static func step_spread(current: float, target: float, dt: float) -> float:
	if current < target:
		return minf(target, current + Balance.GUN_SPREAD_OPEN_RATE * dt)
	return maxf(target, current - Balance.GUN_SPREAD_CLOSE_RATE * dt)


## Damage multiplier by distance: full up to `range`, linear to 50 % at `max_range`, 0 beyond.
static func falloff(id: StringName, dist: float) -> float:
	var f := of(id)
	if f.is_empty() or dist > float(f["max_range"]):
		return 0.0
	var r := float(f["range"])
	if dist <= r:
		return 1.0
	return lerpf(1.0, 0.5, clampf((dist - r) / maxf(float(f["max_range"]) - r, 0.01), 0.0, 1.0))


## Pellet / bullet directions for one shot: `yaw` toward the aim, `spread_deg` (+ the fixed shotgun cone) applied
## with a seeded RNG, so the server's result is reproducible from (seed, seq). Returns yaw angles (radians).
static func shot_yaws(id: StringName, yaw: float, spread_deg: float, seed_v: int) -> PackedFloat32Array:
	var f := of(id)
	var out := PackedFloat32Array()
	if f.is_empty():
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var n := int(f["pellets"])
	var cone := float(f["cone"])
	var dev := deg_to_rad(spread_deg)
	for i in n:
		var y := yaw + rng.randfn(0.0, dev * 0.5)
		if cone > 0.0:
			y += rng.randf_range(-1.0, 1.0) * deg_to_rad(cone)
		out.append(wrapf(y, -PI, PI))
	return out


## Player animation clips (ASSET_SPEC v2 §6.2). `what` = &"aim" | &"shoot" | &"reload".
static func clip(id: StringName, what: StringName) -> StringName:
	var f := of(id)
	if f.is_empty():
		return &""
	return StringName(f.get("clip_" + String(what), &""))
