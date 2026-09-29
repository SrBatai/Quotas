extends Node
## Boot scene (project main scene): routes to the dedicated server's game scene or to the main menu.
## Needed because an autoload's _ready cannot change scene (the root is still adding children).


func _ready() -> void:
	if Net.is_dedicated:
		Net.load_game_scene()
	else:
		get_tree().change_scene_to_file.call_deferred(GameFlow.MENU_SCENE)
