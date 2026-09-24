extends Node3D
## Two-board signpost pointing at the fisher's cabin and the frozen lake.

var _model: Node3D


func _ready() -> void:
	_model = Assets.spawn_model("signpost")
	$Visual.add_child(_model)
	_add_label("TextTop", "CABAÑA DEL PESCADOR")
	_add_label("TextBottom", "LAGO HELADO")


func _add_label(anchor_name: String, text: String) -> void:
	var anchor: Node3D = _model.find_child(anchor_name, true, false)
	if anchor == null:
		return
	var l := Label3D.new()
	l.text = text
	l.font_size = 48
	l.pixel_size = 0.0017
	l.modulate = Color("#F1E9D8")
	l.outline_modulate = Color("#3A2A20")
	l.outline_size = 10
	l.double_sided = false
	l.no_depth_test = false
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.uppercase = true
	anchor.add_child(l)


## Yaw the post so BoardTop's +X points to the A-frame; yaw BoardBottom toward the lake.
func setup(aframe_pos: Vector3, lake_pos: Vector3) -> void:
	var to_a := aframe_pos - global_position
	var yaw_a := atan2(-to_a.z, to_a.x)
	rotation.y = yaw_a
	var board: Node3D = _model.find_child("BoardBottom", true, false)
	if board != null:
		var to_l := lake_pos - global_position
		var yaw_l := atan2(-to_l.z, to_l.x)
		board.rotation.y = yaw_l - yaw_a
