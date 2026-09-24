class_name ToolHolder
extends Node
## Client visual: spawns the equipped tool model into ToolSocket (torch flame included). The torch burn timer
## lives on the server (StatsComponent); this node only mirrors `Player.hand_tool`.

var socket: Node3D
var tool_model: Node3D
var torch_fire: FireEffect
var _player: Player
var _current: StringName = &""


func setup(player: Player, model: Node3D) -> void:
	_player = player
	socket = model.find_child("ToolSocket", true, false)


func apply(id: StringName) -> void:
	if socket == null or id == _current and tool_model != null:
		return
	if tool_model != null:
		tool_model.queue_free()
		tool_model = null
		torch_fire = null
	var was_torch := _current == &"antorcha"
	_current = id
	if id != &"" and Items.DB.has(id):
		var model_name: String = Items.DB[id].get("model", String(id))
		tool_model = Assets.spawn_model(model_name)
		socket.add_child(tool_model)
		tool_model.transform = Transform3D.IDENTITY
		# Tools: handle along +Y, useful end (blade, flame) toward +Z (ASSET_SPEC v2 §12). The socket must point the
		# handle forward; if its roll leaves the blade hanging down, half a turn about the handle fixes it.
		if (socket.global_basis * Vector3(0, 0, 1)).y < -0.5:
			tool_model.rotation.y = PI
	var is_torch := id == &"antorcha"
	if is_torch and tool_model != null:
		torch_fire = FireEffect.new()
		torch_fire.scale_factor = 0.35
		torch_fire.light_range = 7.0
		torch_fire.light_energy = 2.5
		var anchor: Node3D = tool_model.find_child("FlameAnchor", true, false)
		if anchor != null:
			anchor.add_child(torch_fire)
		else:
			tool_model.add_child(torch_fire)
			torch_fire.position = Vector3(0, 0.54, 0)
	var animator: PlayerAnimator = get_parent().get_node_or_null("Animator")
	if animator != null:
		animator.torch_pose = is_torch
	if is_torch != was_torch and _player != null and _player.is_local:
		Events.torch_toggled.emit(is_torch)
