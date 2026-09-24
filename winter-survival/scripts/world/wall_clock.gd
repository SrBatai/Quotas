extends "res://scripts/world/furniture.gd"
## Wall clock whose hands follow the game hour.

var _hour_hand: Node3D
var _minute_hand: Node3D


func _ready() -> void:
	model = "clock"
	super()
	_hour_hand = find_child("HourHand", true, false)
	_minute_hand = find_child("MinuteHand", true, false)
	Events.time_changed.connect(_on_time)
	_on_time(GameState.day, GameState.hour, GameState.is_night)


func _on_time(_day: int, hour: float, _night: bool) -> void:
	# Hands extend along +Y and the face looks toward +Z (v2 front): a negative rotation about Z reads clockwise from the room.
	if _hour_hand != null:
		_hour_hand.rotation.z = -TAU * fmod(hour, 12.0) / 12.0
	if _minute_hand != null:
		_minute_hand.rotation.z = -TAU * (hour - floor(hour))
