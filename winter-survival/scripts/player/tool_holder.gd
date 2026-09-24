class_name ToolHolder
extends Node
## Spawns the equipped tool model into ToolSocket; runs the torch burn timer.

var socket: Node3D
var tool_model: Node3D
var torch_fire: FireEffect
var torch_seconds_left: float = Balance.TORCH_DURATION
var _player: Node
var _current: StringName = &""


func _ready() -> void:
	_player = get_parent()
	Events.tool_changed.connect(_on_tool_changed)


func setup(model: Node3D) -> void:
	socket = model.find_child("ToolSocket", true, false)
	_on_tool_changed(Inventory.hand_tool())


func _on_tool_changed(id: StringName) -> void:
	if socket == null:
		return
	if tool_model != null:
		tool_model.queue_free()
		tool_model = null
		torch_fire = null
	var was_torch := _current == &"antorcha"
	_current = id
	if id != &"":
		var model_name: String = Items.DB[id].get("model", String(id))
		tool_model = Assets.spawn_model(model_name)
		socket.add_child(tool_model)
		tool_model.transform = Transform3D.IDENTITY
		# Tools: handle along +Y, useful end (blade, flame) toward +Z (ASSET_SPEC v2 §12). The socket must point the
		# handle forward; if its roll leaves the blade hanging down, half a turn about the handle fixes it.
		if (socket.global_basis * Vector3(0, 0, 1)).y < -0.5:
			tool_model.rotation.y = PI
	var is_torch := id == &"antorcha"
	if is_torch:
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
		if not was_torch:
			torch_seconds_left = Balance.TORCH_DURATION
	_player.set("torch_lit", is_torch)
	if _player.get("animator") != null:
		_player.animator.torch_pose = is_torch
	if is_torch != was_torch:
		Events.torch_toggled.emit(is_torch)


func _process(delta: float) -> void:
	if _current != &"antorcha" or GameState.is_game_over or not GameState.is_running:
		return
	torch_seconds_left -= delta
	if torch_seconds_left <= 0.0:
		torch_seconds_left = Balance.TORCH_DURATION
		Events.notify.emit("La antorcha se ha consumido", 3.0)
		var had := Inventory.hand_count()
		Inventory.remove(&"antorcha", 1)
		if had > 1:
			# still holding the stack: refresh the model
			_on_tool_changed(&"antorcha")
		elif Inventory.hand_tool() == &"":
			# equip the next stack if any
			Inventory.toggle_torch()
