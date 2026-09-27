extends SceneTree
## Writes the HUD v2 «Susurro» Theme (tokens of docs/research/10_hud_ux.md §V.2) to assets/ui/susurro_theme.tres
## from `UiStyle.build_theme()` / `UiTokens`. Run after changing a token:
##   godot --headless --path . -s tools/gen_hud_theme.gd
## tests/hud_steps.gd checks that the saved resource matches the tokens.

const OUT := "res://assets/ui/susurro_theme.tres"


func _initialize() -> void:
	var t := UiStyle.build_theme()
	var err := ResourceSaver.save(t, OUT)
	print("gen_hud_theme: %s -> %s" % [OUT, "ok" if err == OK else "error %d" % err])
	quit(0 if err == OK else 1)
