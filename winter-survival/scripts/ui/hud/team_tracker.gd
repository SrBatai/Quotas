class_name TeamTracker
extends Node
## Teammates seen by the local client (HUD v2 §V.3 "Compañeros", appendix §6.4.4 / §6.8), refreshed at 5 Hz:
## name, colour (their jacket / outfit slot), distance, downed + bleed-out seconds, and the replicated hints of
## trouble — `cold` (warmth < 30), `speed_mult` < 1 ("Malherido" after a revive). Remote health is not replicated
## yet (ARQ §8.7 `teammate_state` is deferred), so "herido (< 25 %)" uses those two hints. `talking` = a chat
## line from them in the last 6 s.

const PERIOD := 0.2

var mates: Array = []            # [{player, name, color, dist, downed, bleed, hurt, talking, text}]
var _talk: Dictionary = {}       # name -> [until, text]
var _acc: float = 0.0
var _clock: float = 0.0


func _ready() -> void:
	Events.chat_message.connect(_on_chat)


func _on_chat(who: String, text: String) -> void:
	_talk[who] = [_clock + UiTokens.T_CHAT, text]


func _process(delta: float) -> void:
	_clock += delta
	_acc += delta
	if _acc < PERIOD:
		return
	_acc = 0.0
	refresh()


func refresh() -> void:
	mates.clear()
	var me := GameFlow.local_player() as Player
	if me == null or not me.is_inside_tree():
		return
	for n in me.get_parent().get_children():
		var o := n as Player
		if o == null or o == me or o.dead or not o.is_inside_tree():
			continue
		var d := Vector2(o.global_position.x - me.global_position.x, o.global_position.z - me.global_position.z).length()
		var talk: Array = _talk.get(o.display_name, [])
		var talking := not talk.is_empty() and _clock < float(talk[0])
		mates.append({
			"player": o, "name": o.display_name, "color": o.outfit, "dist": d, "downed": o.downed,
			"bleed": o.bleed, "hurt": o.cold or o.speed_mult < 0.99, "talking": talking,
			"text": str(talk[1]) if talking else "",
		})
	mates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a["downed"]) != bool(b["downed"]):
			return bool(a["downed"])
		return float(a["dist"]) < float(b["dist"]))


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
