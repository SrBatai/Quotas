class_name WoodStove
extends StaticBody3D
## The cabin's iron stove: heats the whole house while lit.

@onready var burner: FuelBurner = $Burner
@onready var interactable: InteractableComponent = $Interactable

var is_lit: bool = false
var light: LightFlicker
var embers: CPUParticles3D
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
	light.base_energy = 1.6
	light.omni_range = 5.0
	light.omni_attenuation = 1.3
	add_child(light)
	embers = CPUParticles3D.new()
	embers.amount = 10
	embers.lifetime = 1.2
	embers.direction = Vector3(0, 1, -1)
	embers.spread = 20.0
	embers.initial_velocity_min = 0.2
	embers.initial_velocity_max = 0.5
	embers.gravity = Vector3(0, 0.4, 0)
	embers.scale_amount_min = 0.3
	embers.scale_amount_max = 0.5
	var g := Gradient.new()
	g.set_color(0, Color("#FFD166"))
	g.set_color(1, Color("#E63B12", 0.0))
	embers.color_ramp = g
	embers.mesh = FireEffect.make_quad(0.12, FireEffect.make_particle_material(true))
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
		Events.notify.emit("La estufa se ha apagado. La casa se enfría.", 4.0)


func get_interact_label(_player: Node) -> String:
	var n := Inventory.count(&"madera")
	if is_lit:
		return "Alimentar estufa (%d)" % n
	return "Estufa apagada · Añadir leña (%d)" % n


func can_interact(_player: Node) -> bool:
	return Inventory.has(&"madera", 1)


func interact(player: Node) -> void:
	add_wood_from_player(player)


func add_wood_from_player(_player: Node) -> bool:
	if not burner.add_wood(1):
		Events.notify.emit("Sin leña", 2.0)
		return false
	Events.stove_fueled.emit()
	Events.notify.emit("Alimentas la estufa", 2.0)
	AudioManager.play(&"fire_add_wood", global_position)
	return true


func seconds_left() -> float:
	return burner.seconds_left()
