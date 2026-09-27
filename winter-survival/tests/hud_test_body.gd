extends RefCounted
## Body of tests/hud_test.gd: starts the offline game and runs tests/hud_steps.gd.

var tree: SceneTree
var _failed: bool = false
var _checks: int = 0


func check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("  ok   ", msg)
	else:
		_failed = true
		print("FAIL: ", msg)


func run(p_tree: SceneTree) -> void:
	tree = p_tree
	await tree.process_frame
	print("== VENTISCA HUD test (H1)")
	GameFlow.play_offline()
	var waited := 0
	while GameFlow.local_player() == null and waited < 900:
		await tree.process_frame
		waited += 1
	for i in 10:
		await tree.process_frame
	var game := tree.current_scene
	var player: Player = GameFlow.local_player()
	if player == null:
		check(false, "local player")
		tree.quit(1)
		return
	await (load("res://tests/hud_steps.gd").new()).run(self, tree, game, game.get_node("World"), player)
	print("== %d checks, %s" % [_checks, "FAILED" if _failed else "ALL PASSED"])
	tree.quit(1 if _failed else 0)
