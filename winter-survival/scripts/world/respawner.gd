class_name Respawner
extends Node
## Server only (PLAN M2): every dawn up to RESPAWN_FIREWOOD_PER_DAY firewood and RESPAWN_STONE_PER_DAY stones
## reappear as replicated drops (DropSpawner), capped at MAX_FIREWOOD / MAX_STONES on the ground.

var enabled: bool = false


func _ready() -> void:
	Events.day_started.connect(_on_day_started)


func _on_day_started(_day: int) -> void:
	if not enabled or not Net.is_server:
		return
	var scatter := get_parent().get_node_or_null("Scatter")
	if scatter == null:
		return
	var wood_now: int = scatter.count_pickups(&"madera")
	var stone_now: int = scatter.count_pickups(&"piedra")
	var wood_n := mini(Balance.RESPAWN_FIREWOOD_PER_DAY, Balance.MAX_FIREWOOD - wood_now)
	var stone_n := mini(Balance.RESPAWN_STONE_PER_DAY, Balance.MAX_STONES - stone_now)
	for i in maxi(wood_n, 0):
		scatter.spawn_random_pickup(&"madera", "firewood")
	for i in maxi(stone_n, 0):
		scatter.spawn_random_pickup(&"piedra", "stone")
	print("[EVT] dawn respawn: +%d firewood, +%d stones" % [maxi(wood_n, 0), maxi(stone_n, 0)])
