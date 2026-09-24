class_name Campfire
extends StaticBody3D
## Placeable fire: heat zone, light, flames; fuel via FuelBurner; scares wolves.

@export var start_lit: bool = true

@onready var burner: FuelBurner = $Burner
@onready var interactable: InteractableComponent = $Interactable

var is_lit: bool = false
var heat: HeatZone
var fire: FireEffect
var _model: Node3D


func _ready() -> void:
	collision_layer = 1 | 64
	collision_mask = 0
	add_to_group("campfire")
	add_to_group("placed")
	_model = Assets.spawn_model("campfire")
	$Visual.add_child(_model)
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.55
	cyl.height = 0.35
	var cs := CollisionShape3D.new()
	cs.shape = cyl
	cs.position = Vector3(0, 0.175, 0)
	add_child(cs)
	var icyl := CylinderShape3D.new()
	icyl.radius = 0.8
	icyl.height = 1.0
	interactable.set_shape(icyl, Vector3(0, 0.4, 0))
	interactable.ring_radius = 0.8
	interactable.interact_range = Balance.INTERACT_RANGE
	heat = HeatZone.new()
	heat.name = "Heat"
	heat.gain = Balance.CAMPFIRE_WARMTH
	heat.radius = Balance.CAMPFIRE_HEAT_RADIUS
	add_child(heat)
	fire = FireEffect.new()
	fire.name = "Fire"
	var anchor: Node3D = _model.find_child("FlameAnchor", true, false)
	add_child(fire)
	if anchor != null:
		fire.global_position = anchor.global_position
	else:
		fire.position = Vector3(0, 0.18, 0)
	burner.fuel_max = Balance.CAMPFIRE_FUEL_MAX
	burner.per_wood = Balance.CAMPFIRE_FUEL_PER_WOOD
	burner.lit_changed.connect(_on_lit_changed)
	if start_lit:
		burner.add_fuel(Balance.CAMPFIRE_FUEL_START)
	else:
		_on_lit_changed(false)


func _on_lit_changed(lit: bool) -> void:
	is_lit = lit
	heat.set_active(lit)
	fire.set_active(lit)
	if lit:
		add_to_group("heat_source")
		Events.campfire_lit.emit(self)
		AudioManager.start_loop(&"fire_loop", self)
	else:
		remove_from_group("heat_source")
		Events.campfire_extinguished.emit(self)
		Events.notify.emit("La fogata se ha apagado", 3.0)
		AudioManager.stop_loop(&"fire_loop", self)
		AudioManager.play(&"fire_out", global_position)


func get_interact_label(_player: Node) -> String:
	var n := Inventory.count(&"madera")
	if n <= 0:
		return "Sin leña"
	return "Añadir leña (%d)" % n


func can_interact(_player: Node) -> bool:
	return Inventory.has(&"madera", 1)


func interact(_player: Node) -> void:
	if burner.add_wood(1):
		Events.notify.emit("Añades leña a la fogata", 2.0)
		AudioManager.play(&"fire_add_wood", global_position)


func seconds_left() -> float:
	return burner.seconds_left()
