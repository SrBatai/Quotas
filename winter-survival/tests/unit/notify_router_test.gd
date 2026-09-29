extends SceneTree
## H3 notice gate (PLAN v3.8.1 H3; docs/research/10_hud_ux.md §V.3 / §V.8 "UI‑3", appendix §6.5 and §8.9): the
## NotifyRouter's priorities (P0 in the world / on the vital, never on the line; P1–P2 the 3 s line; P3 the pickup
## line), precedence (a P0 takes the line after 1.2 s and the interrupted notice goes back to the queue), the
## attention window, the queue of 6 (full: the oldest of the lowest priority goes), merge / refresh by key, the
## 8 s cooldown keys, the co-op filter, the zone-title crossing, the legacy text classification, the optional P0
## banner, the P0 sound with its direction caption (AudioManager.event_played), and the HazardStack (forecast →
## imminent → active → end for blizzard and Gran Ventisca, the E1 / E2 kinds, ordering, "+1 previsto").
## Run: godot --headless --path . -s tests/unit/notify_router_test.gd  → "== N checks, ALL PASSED" / exit 1.

var _body: RefCounted


func _initialize() -> void:
	var script: GDScript = load("res://tests/unit/notify_router_steps.gd")
	if script == null or not script.can_instantiate():
		print("FAIL: cannot load notify_router_steps.gd")
		quit(1)
		return
	_body = script.new()
	_body.run(self)
	var t := create_timer(60.0)
	t.timeout.connect(func() -> void:
		print("FAIL: notify router test watchdog timeout")
		quit(1))
