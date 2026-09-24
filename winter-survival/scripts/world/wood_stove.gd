class_name WoodStove
extends StaticBody3D
## The cabin's iron stove: heats the whole house while lit. The burner ticks on the server; lit/fuel travel
## as a world delta so every client shows the same fire.

@onready var burner: FuelBurner = $Burner
@onready var interactable: InteractableComponent = $Interactable

var is_lit: bool = false
var light: LightFlicker
var embers: GPUParticles3D
var _model: Node3D
var _door: MeshInstance3D


func _ready() -> void:
	collision_layer = 1 | 64
	collision_mask = 0
	add_to_group("stove")
	_model = Assets.spawn_model("wood_stove")
	$Visual.add_child(_model)
	_door = _model.find_child("Door", true, false) as MeshInstance3D
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 0.9, 0.6)
	var cs := CollisionShape3D.new()
	cs.shape = box
	cs.position = Vector3(0, 0.45, 0)
	add_child(cs)
	var ibox := BoxShape3D.new()
	ibox.size = Vector3(1.0, 1.4, 1.0)
	interactable.set_shape(ibox, Vector3(0, 0.6, 0))
	interactable.ring_radius = 0.6
	interactable.interact_range = Balance.INTERACT_RANGE
	var anchor: Node3D = _model.find_child("StoveAnchor", true, false)
	light = LightFlicker.new()
	light.name = "Light"
	light.light_color = Color("#FF9A3C")
	light.base_energy = 2.5
	light.omni_range = 6.0
	light.omni_attenuation = 1.2
	add_child(light)
	var g := Gradient.new()
	g.set_color(0, Color("#FFD166"))
	g.set_color(1, Color("#E63B12", 0.0))
	# embers drift up and out of the door (+Z, the stove's front)
	embers = FireEffect.make_emitter(10, 1.2, 0.02, Vector3(0, 1, 1), 20.0, 0.2, 0.5, Vector3(0, 0.4, 0), 0.3, 0.5, null, g, 0.12, true)
	embers.name = "Embers"
	add_child(embers)
	if anchor != null:
		light.global_position = anchor.global_position + Vector3(0, 0.15, 0)
		embers.global_position = anchor.global_position
	else:
		light.position = Vector3(0, 0.6, -0.35)
		embers.position = Vector3(0, 0.45, -0.35)
	burner.fuel_max = Balance.STOVE_FUEL_MAX
	burner.per_wood = Balance.STOVE_FUEL_PER_WOOD
	burner.lit_changed.connect(_on_lit_changed)
	burner.add_fuel(Balance.STOVE_FUEL_START)
	if not Net.is_server and NetWorld.instance != null:
		apply_net_delta(NetWorld.instance.delta_of(WorldRegistry.wid_of(self)))


func _on_lit_changed(lit: bool) -> void:
	is_lit = lit
	light.visible = lit
	embers.emitting = lit
	if _door != null:
		Assets.override_named(_door, "ember", Assets.get_ember_material() if lit else null)
	Events.stove_changed.emit(lit)
	if lit:
		AudioManager.start_loop(&"stove_loop", self)
	else:
		AudioManager.stop_loop(&"stove_loop", self)
	if Net.is_server and is_inside_tree() and NetWorld.instance != null:
		NetWorld.instance.set_delta(WorldRegistry.wid_of(self), {"lit": lit, "fuel": burner.fuel})
		if not lit:
			WorldState.instance.notify_all("La estufa se ha apagado. La casa se enfría.", 4.0)


func get_interact_label(player: Node) -> String:
	var n: int = player.state.count(&"madera") if player is Player else 0
	if is_lit:
		return "Alimentar estufa (%d)" % n
	return "Estufa apagada · Añadir leña (%d)" % n


func can_interact(player: Node) -> bool:
	return player is Player and player.state.has(&"madera", 1)


## Server only.
func interact(player: Node) -> void:
	add_wood_from_player(player)


func add_wood_from_player(player: Node) -> bool:
	var p := player as Player
	if p == null or not Net.is_server:
		return false
	if not burner.add_wood(p, 1):
		p.state.notify("Sin leña", 2.0)
		return false
	p.state.emit_sim(&"stove_fueled", [])
	p.state.notify("Alimentas la estufa", 2.0)
	AudioManager.play(&"fire_add_wood", global_position)
	NetWorld.instance.set_delta(WorldRegistry.wid_of(self), {"lit": is_lit, "fuel": burner.fuel})
	return true


func seconds_left() -> float:
	return burner.seconds_left()


func apply_net_delta(f: Dictionary) -> void:
	if f.has("fuel"):
		burner.fuel = float(f["fuel"])
	if f.has("lit"):
		burner.set_lit(bool(f["lit"]))
