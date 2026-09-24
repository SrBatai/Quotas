class_name FuelBurner
extends Node
## Fuel in seconds; burns 1 s per second while lit.

signal lit_changed(lit: bool)
signal extinguished()
signal fueled(seconds_added: float)

@export var fuel_max: float = 300.0
@export var per_wood: float = 60.0
var fuel: float = 0.0
var is_lit: bool = false


func _process(delta: float) -> void:
	if not is_lit:
		return
	fuel -= delta
	if fuel <= 0.0:
		fuel = 0.0
		is_lit = false
		lit_changed.emit(false)
		extinguished.emit()


## Takes n wood from the inventory and adds fuel; relights when out. False if no wood.
func add_wood(n: int = 1) -> bool:
	if not Inventory.remove(&"madera", n):
		return false
	add_fuel(per_wood * n)
	return true


func add_fuel(seconds: float) -> void:
	fuel = minf(fuel + seconds, fuel_max)
	fueled.emit(seconds)
	if not is_lit and fuel > 0.0:
		is_lit = true
		lit_changed.emit(true)


func set_lit(value: bool) -> void:
	if value and fuel <= 0.0:
		return
	if value != is_lit:
		is_lit = value
		lit_changed.emit(value)
		if not value:
			extinguished.emit()


func seconds_left() -> float:
	return fuel
