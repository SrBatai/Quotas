class_name Cabin
extends Node3D
## The hunter's house: shelter volume, cutaway, stove/cabinet/furniture, lantern, window glow, smoke.

@onready var visual: Node3D = $Visual
@onready var shelter: Area3D = $Shelter
@onready var stove: WoodStove = $Stove
@onready var cutaway: Cutaway = $Cutaway
@onready var smoke: SmokeEffect = $ChimneySmoke
@onready var interior_light: OmniLight3D = $InteriorLight

var model: Node3D
var player_inside: bool = false
var stove_on: bool = false
var lantern: Lantern
var _glow_on: bool = false


func _ready() -> void:
	add_to_group("cutaway_cabin")
	model = Assets.spawn_model("cabin")
	visual.add_child(model)
	if not Assets.is_placeholder(model) and model.find_child("ColFoundation", true, false) == null:
		# v2 frame: porch and door at +Z, chimney at +X (ASSET_SPEC v2 §17)
		push_warning("cabin.glb has no embedded collision; adding spec boxes")
		Placeholders._col_box(model, "ColFoundation", Vector3(-3.0, 0, -2.5), Vector3(3.0, 0.30, 2.5))
		Placeholders._col_box(model, "ColPorch", Vector3(-3.0, 0, 2.5), Vector3(3.0, 0.30, 4.5))
		Placeholders._col_box(model, "ColWallBack", Vector3(-3.0, 0.30, -2.5), Vector3(3.0, 3.0, -2.32))
		Placeholders._col_box(model, "ColWallLeft", Vector3(2.82, 0.30, -2.5), Vector3(3.0, 3.0, 2.5))
		Placeholders._col_box(model, "ColWallRight", Vector3(-3.0, 0.30, -2.5), Vector3(-2.82, 3.0, 2.5))
		Placeholders._col_box(model, "ColWallFrontL", Vector3(1.4, 0.30, 2.32), Vector3(3.0, 3.0, 2.5))
		Placeholders._col_box(model, "ColWallFrontR", Vector3(-3.0, 0.30, 2.32), Vector3(0.4, 3.0, 2.5))
	# shelter volume
	shelter.collision_layer = 32
	shelter.collision_mask = 2
	shelter.add_to_group("shelter")
	var box := BoxShape3D.new()
	box.size = Vector3(5.6, 2.6, 4.6)
	var cs := CollisionShape3D.new()
	cs.shape = box
	cs.position = Vector3(0, 1.6, 0)
	shelter.add_child(cs)
	shelter.body_entered.connect(_on_body_entered)
	shelter.body_exited.connect(_on_body_exited)
	cutaway.setup(self, model)
	# lantern
	var socket: Node3D = model.find_child("LanternSocket", true, false)
	lantern = Lantern.new()
	lantern.name = "Lantern"
	add_child(lantern)
	if socket != null:
		lantern.global_position = socket.global_position
	else:
		lantern.position = Vector3(1.6, 2.35, 4.3)
	# interior light
	interior_light.light_color = Color("#FFB454")
	interior_light.omni_range = 7.0
	interior_light.shadow_enabled = false
	interior_light.position = Vector3(0, 2.2, 0)
	# smoke at the chimney top (+X wall, in front of the ridge)
	smoke.position = Vector3(3.35, 5.3, 0.6)
	stove_on = stove.is_lit
	Events.stove_changed.connect(_on_stove_changed)
	Events.time_changed.connect(_on_time)
	_update_lighting()


func _on_body_entered(body: Node) -> void:
	if body is Player:
		if Net.is_server:
			body.in_house = true   # authoritative (stats)
		if body.is_local:
			player_inside = true
			cutaway.set_active(true)
			if lantern != null:
				lantern.visible = false  # hangs from the porch roof, which is part of Roof in the glb
			smoke.visible = false  # would float over the opened room
			Events.shelter_changed.emit(true)


func _on_body_exited(body: Node) -> void:
	if body is Player:
		if Net.is_server:
			body.in_house = false
		if body.is_local:
			player_inside = false
			cutaway.set_active(false)
			if lantern != null:
				lantern.visible = true
			smoke.visible = true
			Events.shelter_changed.emit(false)


func _on_stove_changed(lit: bool) -> void:
	stove_on = lit
	_update_lighting()


func _on_time(_day: int, _hour: float, _night: bool) -> void:
	_update_lighting()


func _update_lighting() -> void:
	var hour := WorldState.hour_now()
	var dark := hour >= 17.5 or hour < 6.5
	var glow := stove_on and dark
	if glow != _glow_on:
		_glow_on = glow
		for n in ["WindowsFront", "WindowsLeft"]:
			var w := model.find_child(n, true, false)
			if w != null:
				Assets.override_named(w, "window", Assets.get_glow_material() if glow else null)
	smoke.set_active(stove_on)
	if dark:
		interior_light.visible = true
		interior_light.light_energy = 1.8 if stove_on else 0.3
	else:
		interior_light.visible = stove_on
		interior_light.light_energy = 0.6


func get_door_anchor() -> Node3D:
	return model.find_child("DoorAnchor", true, false)


## 2.5 m in front of the door (the door anchor's +Z = Vector3.MODEL_FRONT, out of the house).
func get_spawn_point() -> Vector3:
	var door := get_door_anchor()
	if door == null:
		return global_position + global_transform.basis * Vector3(0.9, 0.3, 5.7)
	return door.global_position + door.global_basis.z * 2.5


## Yaw so the player's front (+Z) looks at the door, i.e. against the door anchor's +Z.
func get_spawn_yaw() -> float:
	var door := get_door_anchor()
	var facing := -global_transform.basis.z
	if door != null:
		facing = -door.global_basis.z
	return atan2(facing.x, facing.z)
