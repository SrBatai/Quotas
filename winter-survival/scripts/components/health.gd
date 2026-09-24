class_name HealthComponent
extends Node

signal died(killer: Node)
signal damaged(amount: float, from: Node)

@export var max_health: float = 60.0
var health: float = 60.0
var dead: bool = false


func _ready() -> void:
	health = max_health


func take_damage(amount: float, from: Node = null) -> void:
	if dead:
		return
	health = maxf(health - amount, 0.0)
	damaged.emit(amount, from)
	if health <= 0.0:
		dead = true
		died.emit(from)


func ratio() -> float:
	return health / max_health if max_health > 0.0 else 0.0
