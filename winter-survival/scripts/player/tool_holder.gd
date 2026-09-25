class_name ToolHolder
extends Node
## Client visual: spawns the equipped tool model on the character's hand socket (BoneAttachment3D on
## RightHandSocket; the rigid placeholder's ToolSocket as fallback), torch flame included. The torch burn timer
## lives on the server (StatsComponent); this node only mirrors `Player.hand_tool`.

## RightHandSocket (ASSET_SPEC v2 §4.2): Y = handle axis toward the thumb, Z = along the forearm toward the
## knuckles. Tools: handle along +Y, useful end toward +Z (§12). Identity keeps the blade leading the swing.
const HAND_TOOL_TRANSFORM := Transform3D(Basis.IDENTITY, Vector3(0, -0.06, 0))

var socket: Node3D
var tool_model: Node3D
var torch_fire: FireEffect
var _player: Player
var _visual: CharacterVisual
var _current: StringName = &""


func setup(player: Player, visual: CharacterVisual) -> void:
	_player = player
	_visual = visual
	socket = visual.tool_parent()
	if tool_model != null and is_instance_valid(tool_model):
		tool_model.queue_free()
	tool_model = null
	torch_fire = null
	_current = &""


func apply(id: StringName, force: bool = false) -> void:
	if socket == null or (id == _current and tool_model != null and not force):
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
		if _visual != null and _visual.is_skeletal:
			tool_model.transform = HAND_TOOL_TRANSFORM
		else:
			tool_model.transform = Transform3D.IDENTITY
			# rigid placeholder: the socket must point the handle forward; half a turn fixes a hanging blade
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
	if is_torch != was_torch and _player != null and _player.is_local:
		Events.torch_toggled.emit(is_torch)
