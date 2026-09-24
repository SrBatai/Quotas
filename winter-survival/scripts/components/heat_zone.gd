class_name HeatZone
extends Area3D
## Warmth source area (layer 5, mask 2 = player). Registers itself on the player's stats.

@export var gain: float = 5.0
@export var radius: float = 4.5
var active: bool = true


func _ready() -> void:
	collision_layer = 16
	collision_mask = 2
	monitorable = false
	if get_child_count() == 0:
		var cs := CollisionShape3D.new()
		var sh := SphereShape3D.new()
		sh.radius = radius
		cs.shape = sh
		add_child(cs)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node) -> void:
	if body is Player and (body as Player).state.stats != null:
		(body as Player).state.stats.add_heat_source(self)


func _on_body_exited(body: Node) -> void:
	if body is Player and (body as Player).state.stats != null:
		(body as Player).state.stats.remove_heat_source(self)


func set_active(value: bool) -> void:
	active = value
	if not value:
		for b in get_overlapping_bodies():
			_on_body_exited(b)
	set_deferred("monitoring", value)
