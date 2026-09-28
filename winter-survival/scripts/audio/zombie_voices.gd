class_name ZombieVoices
extends Node
## Zombie audio that no replicated event carries (S1): idle / wander groans, chase breaths, shambling steps, the
## stagger and knockdown reactions, read from ZombieClient's records at 8 Hz. The one-shots the server sends as events
## (hit, death, «te he visto», attack, frozen wake, bloater pop) are played by ZombieClient itself.
## Budget: every vocalisation goes through AudioManager's `zombie_voice` group (≤ 6 at once, the nearest win), steps
## through `zombie_step` (≤ 8); only records within HEAR m of the listener are looked at, and each zombie has its own
## cooldown, so 200 zombies in interest cost one pass over the records per tick and a handful of voices.

const TICK := 0.125
const HEAR := 35.0
const STEP_HEAR := 16.0
## Mean seconds between two groans of one idle / wandering zombie (± 50 %), and while chasing.
const GROAN_EVERY := 9.0
const CHASE_GROAN_EVERY := 4.5
const BREATH_EVERY := 1.6
const STRIDE := 0.75

var _t: float = 0.0
var _next: Dictionary = {}        # id -> time of its next vocalisation
var _step_acc: Dictionary = {}    # id -> metres since its last step
var _last_pos: Dictionary = {}    # id -> Vector3
var _state: Dictionary = {}       # id -> last state seen
var _rng := RandomNumberGenerator.new()
## Tests.
var groans: int = 0
var steps: int = 0


func _ready() -> void:
	name = "ZombieVoices"
	_rng.randomize()


func _process(delta: float) -> void:
	_t += delta
	if _t < TICK:
		return
	_t = 0.0
	var zc := ZombieClient.instance
	if zc == null or zc.records.is_empty():
		return
	var lpos := AudioManager.listener_position()
	var now := Time.get_ticks_msec() / 1000.0
	var seen := {}
	for id in zc.records:
		var r: ZombieClient.ZRec = zc.records[id]
		var d := lpos.distance_to(r.render_pos)
		if d > HEAR:
			continue
		seen[id] = true
		var st := r.state
		var was := int(_state.get(id, st))
		_state[id] = st
		if st == ZombieKinds.State.DEAD or st == ZombieKinds.State.FROZEN or st == ZombieKinds.State.SLEEP:
			continue
		# reactions the server only shows as a state (no event carries them)
		if st != was:
			if st == ZombieKinds.State.STAGGER:
				AudioManager.play(&"zombie_stagger", r.render_pos)
			elif st == ZombieKinds.State.KNOCKED:
				AudioManager.play(&"zombie_knock", r.render_pos)
		# steps: a shambling foot every STRIDE m of ground covered
		var lp: Vector3 = _last_pos.get(id, r.render_pos)
		_last_pos[id] = r.render_pos
		if d < STEP_HEAR and r.kind != ZombieKinds.Kind.CRAWLER:
			var acc := float(_step_acc.get(id, 0.0)) + Vector2(r.render_pos.x - lp.x, r.render_pos.z - lp.z).length()
			if acc >= STRIDE * (1.4 if r.kind == ZombieKinds.Kind.RUNNER else 1.0):
				acc = 0.0
				steps += 1
				AudioManager.play(&"zombie_step", r.render_pos)
			_step_acc[id] = minf(acc, 3.0)
		# vocalisations
		var due := float(_next.get(id, now + _rng.randf_range(0.5, GROAN_EVERY)))
		if not _next.has(id):
			_next[id] = due
			continue
		if now < due:
			continue
		var chasing := st == ZombieKinds.State.CHASE or st == ZombieKinds.State.ATTACK
		var ev := &"zombie_groan"
		var every := GROAN_EVERY
		if chasing:
			if r.kind == ZombieKinds.Kind.RUNNER and (r.flags & ZombieKinds.FLAG_TIRED) == 0:
				ev = &"zombie_breath"
				every = BREATH_EVERY
			else:
				every = CHASE_GROAN_EVERY
		_next[id] = now + every * _rng.randf_range(0.5, 1.5)
		if AudioManager.play_ex(ev, r.render_pos) >= 0:
			groans += 1
	# forget the records that left
	if _next.size() > seen.size() + 64:
		for id in _next.keys():
			if not seen.has(id):
				_next.erase(id)
				_step_acc.erase(id)
				_last_pos.erase(id)
				_state.erase(id)
