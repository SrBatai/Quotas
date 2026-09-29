class_name TeamTracker
extends Node
## Teammates seen by the local client (HUD v2 §V.3 "Compañeros", appendix §6.4.4 / §6.8), refreshed at 5 Hz:
## name, colour (their jacket / outfit slot), distance, downed + bleed-out seconds, hurt, cold, talking (a chat line
## from them in the last 6 s).
## H3: the health / warmth of the others come from the server (HudNet team block, 2 Hz), so «herido» is the real
## < 25 % (before, the `cold` / `speed_mult` hints — still the fallback). A teammate going down is noticed THE FRAME
## it happens — the server's push (HudNet `_mate`, ahead of the synchronizer's 0.2 s delta) or the replicated flag,
## checked every frame — and `mate_downed(m)` fires once (the HUD turns it into the P0: the one world indicator, the
## accent / edge marker, `ui_mate_down` with its caption); `mate_up(m)` when revived or dead.

signal mate_downed(m: Dictionary)
signal mate_up(m: Dictionary)

const PERIOD := 0.2

var mates: Array = []            # [{player, peer, name, color, dist, downed, bleed, hurt, cold, health, warmth, talking, text}]
## Tests: peer -> Time.get_ticks_msec() when mate_downed fired.
var downed_at: Dictionary = {}
var _down: Dictionary = {}       # peer -> bool (what mate_downed / mate_up last said)
var _talk: Dictionary = {}       # name -> [until, text]
var _acc: float = 0.0
var _clock: float = 0.0


func _ready() -> void:
	Events.chat_message.connect(_on_chat)
	_hook_net.call_deferred()


func _hook_net() -> void:
	var hn := HudNet.instance
	if hn != null and not hn.mate_changed.is_connected(_on_mate_changed):
		hn.mate_changed.connect(_on_mate_changed)


func _on_chat(who: String, text: String) -> void:
	_talk[who] = [_clock + UiTokens.T_CHAT, text]


func _on_mate_changed(_peer: int, _downed: bool, _t_ms: int) -> void:
	refresh()


func _process(delta: float) -> void:
	_clock += delta
	_acc += delta
	if _acc >= PERIOD:
		_acc = 0.0
		if HudNet.instance != null and not HudNet.instance.mate_changed.is_connected(_on_mate_changed):
			_hook_net()
		refresh()
		return
	# every frame: a replicated downed flag that flipped since the last refresh (cheap: a few players)
	for m: Dictionary in mates:
		var o := player_of(m)
		if o != null and _is_downed(o) != bool(m["downed"]):
			refresh()
			return


static func _hint(o: Player) -> Dictionary:
	return HudNet.instance.hint_of(o.peer_id) if HudNet.instance != null else {}


## Downed as the client knows it now: the server's push while fresh (1 s), else the replicated flag.
static func _is_downed(o: Player) -> bool:
	var h := _hint(o)
	if not h.is_empty():
		return bool(h["downed"]) and not o.dead
	return o.downed and not o.dead


func refresh() -> void:
	mates.clear()
	var me := GameFlow.local_player() as Player
	if me == null or not me.is_inside_tree():
		return
	var team: Dictionary = HudNet.instance.team if HudNet.instance != null else {}
	for n in me.get_parent().get_children():
		var o := n as Player
		if o == null or o == me or o.dead or not o.is_inside_tree():
			continue
		var d := Vector2(o.global_position.x - me.global_position.x, o.global_position.z - me.global_position.z).length()
		var talk: Array = _talk.get(o.display_name, [])
		var talking := not talk.is_empty() and _clock < float(talk[0])
		var st: Dictionary = team.get(o.peer_id, {})
		var health := float(st.get("health", -1.0))
		var warmth := float(st.get("warmth", -1.0))
		var down := _is_downed(o)
		var h := _hint(o)
		var bleed := o.bleed
		if not h.is_empty() and bool(h["downed"]) and bleed <= 0:
			bleed = int(h["bleed"])
		var cold := o.cold or (warmth >= 0.0 and warmth < UiTokens.HEAT_ACCENT_BELOW)
		var hurt := cold or o.speed_mult < 0.99
		if health >= 0.0:
			hurt = cold or health < Balance.HEALTH_MAX * UiTokens.TEAM_HURT
		mates.append({
			"player": o, "peer": o.peer_id, "name": o.display_name, "color": o.outfit, "dist": d, "downed": down,
			"bleed": bleed, "hurt": hurt and not down, "cold": cold, "health": health, "warmth": warmth,
			"talking": talking, "text": str(talk[1]) if talking else "",
		})
	mates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a["downed"]) != bool(b["downed"]):
			return bool(a["downed"])
		return float(a["dist"]) < float(b["dist"]))
	# transitions (once per change)
	var seen := {}
	for m: Dictionary in mates:
		var peer := int(m["peer"])
		seen[peer] = true
		var was := bool(_down.get(peer, false))
		if bool(m["downed"]) and not was:
			_down[peer] = true
			downed_at[peer] = Time.get_ticks_msec()
			mate_downed.emit(m)
		elif not bool(m["downed"]) and was:
			_down[peer] = false
			downed_at.erase(peer)
			mate_up.emit(m)
	for peer: int in _down.keys():
		if not seen.has(peer):
			var gone := {"peer": peer, "name": "", "downed": false}
			_down.erase(peer)
			downed_at.erase(peer)
			mate_up.emit(gone)


## The entry's Player, or null when it left or was freed since the last refresh (entries live up to 0.2 s).
static func player_of(m: Dictionary) -> Player:
	var v: Variant = m.get("player")
	if v == null or not is_instance_valid(v):
		return null
	return v as Player


## The nearest downed teammate still in the world, or {}.
func nearest_downed() -> Dictionary:
	for m: Dictionary in mates:
		if bool(m["downed"]) and player_of(m) != null:
			return m
	return {}


func any_downed() -> bool:
	return not nearest_downed().is_empty()
