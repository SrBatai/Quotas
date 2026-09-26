class_name SoundEvents
## Noise as a loan (GDD v2 §6.3, ARQ v2 §11.4): `SoundEvents.emit(pos, radius, priority, kind)` on the server records a
## SoundEvent the zombies' hearing reads on their next thought (ZombieSystem), feeds the zone heat the director
## watches and sends the visible ring (ZombieNet FX, clients with interest). Modifiers: blizzard ×0.6, indoors ÷2,
## server rule `noise_scale`. Footsteps are not events: the brain derives them from the players' gait
## (SoundEvents.gait_radius) so walking does not flood the network with rings.

enum Kind { STEP, MELEE, MISS, SHOVE, CHOP, DOOR, THROW, GUN, HORN, ALARM, SCREAM, OTHER }

## Seconds a SoundEvent stays audible to thinking zombies (longer than the 2 Hz L1 period: nobody misses it).
const LIFETIME := 0.6
const MAX_EVENTS := 96

## Recent events (server): {pos, radius, priority, kind, t, peer}. Oldest first.
static var recent: Array[Dictionary] = []
## Total events emitted (tests).
static var emitted: int = 0
## Zone heat: chunk key -> accumulated radius-weighted noise (decays 1/min, GDD §6.2). Read by the director.
static var heat: Dictionary = {}


static func reset() -> void:
	recent.clear()
	heat.clear()
	emitted = 0


static func now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Server: a sound of `radius` m at `pos`. Returns the effective radius after the modifiers (0 = silent).
static func emit(pos: Vector3, radius: float, priority: int = 1, kind: int = Kind.OTHER, peer: int = 0, indoors: bool = false) -> float:
	if not Net.is_server or radius <= 0.0:
		return 0.0
	var r := radius * float(WorldState.rules_now().get("noise_scale", 1.0))
	if WorldState.weather_now() == &"blizzard":
		r *= 0.6
	if indoors:
		r *= 0.5
	if r < 0.5:
		return 0.0
	var t := now()
	while not recent.is_empty() and (t - float(recent[0]["t"]) > LIFETIME or recent.size() >= MAX_EVENTS):
		recent.pop_front()
	recent.append({"pos": pos, "radius": r, "priority": priority, "kind": kind, "t": t, "peer": peer})
	emitted += 1
	var k := WorldConst.key_of(pos)
	heat[k] = float(heat.get(k, 0.0)) + r
	if ZombieSystem.instance != null:
		ZombieSystem.instance.on_noise(pos, r)
	if ZombieNet.instance != null:
		ZombieNet.instance.fx_noise(pos, r, kind)
	return r


## Events still audible at time `t` (the caller filters by distance).
static func live(t: float) -> Array[Dictionary]:
	while not recent.is_empty() and t - float(recent[0]["t"]) > LIFETIME:
		recent.pop_front()
	return recent


## Footstep radius of a moving player (GDD §6.3: crouched 2, walking 6, running 14; still = 0).
static func gait_radius(p: Player) -> float:
	var v := Vector2(p.velocity.x, p.velocity.z).length()
	if v < 0.3:
		return 0.0
	var r := 6.0
	if p.crouching:
		r = 2.0
	elif p.running:
		r = 14.0
	if p.in_house:
		r *= 0.5
	return r * float(WorldState.rules_now().get("noise_scale", 1.0)) * (0.6 if WorldState.weather_now() == &"blizzard" else 1.0)


## Decays the zone heat (called once a second by the director): −1 "radius-metre" per minute of every 60.
static func decay_heat(dt: float) -> void:
	for k in heat.keys():
		var v := float(heat[k]) * pow(0.5, dt / 60.0)
		if v < 0.5:
			heat.erase(k)
		else:
			heat[k] = v
