class_name HudInput
extends Node
## Input of the HUD v2: the Info key and the last input device (glyphs).
## `hud_info` = Tab / D‑pad ↑ (docs/research/10_hud_ux.md §V.1 rule 3). Both keys already had a job, so a TAP keeps
## it and a HOLD is Info: Tab tapped (< 0.22 s) still opens crafting (`toggle_craft`), D‑pad ↑ tapped still zooms
## in (`zoom_in`) — the tap is re-sent as an `InputEventAction` on release; held ≥ 0.22 s, Info shows missions,
## time, temperature and the group while held ("Pedir en lugar de mantener": a hold toggles it instead).
## Y on the gamepad keeps crafting; Q / E, the wheel and D‑pad ↓ are untouched.

signal device_changed(gamepad: bool)

## Last device used: true = gamepad (glyphs ⓧ), false = keyboard / mouse (key caps).
static var gamepad: bool = false

var vis: HudVisibility
## "Seguir otra" (MissionLog.track_next), set by the HUD.
var track_next: Callable
var taps: int = 0
var _down: bool = false
var _t: float = 0.0
var _from_joy: bool = false
var _holding: bool = false


func _input(event: InputEvent) -> void:
	_track_device(event)
	if MapScreen.any_open:
		return   # the map screen takes Tab / D-pad (tabs, zoom)
	# while Info is open: R / Y tracks the next mission ("seguir otra")
	if vis != null and vis.info_active and not event.is_echo() and not event is InputEventAction \
			and (event.is_action_pressed("interact") or event.is_action_pressed("toggle_craft")):
		if track_next.is_valid():
			track_next.call()
		get_viewport().set_input_as_handled()
		return
	if not event.is_action("hud_info") or event.is_echo():
		return
	if _typing() or not GameFlow.in_game or GameFlow.is_paused:
		return
	if event.is_pressed():
		if not _down:
			_down = true
			_t = 0.0
			_holding = false
			_from_joy = event is InputEventJoypadButton
	else:
		if _down and not _holding:
			_tap()
		elif _down and _holding and not bool(UiSettings.get_value("info_toggle")):
			_set_info(false)
		_down = false
		_holding = false
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not _down:
		return
	_t += delta
	if _t >= UiTokens.HOLD_INFO and not _holding:
		_holding = true
		if bool(UiSettings.get_value("info_toggle")):
			_set_info(not (vis != null and vis.info_active))
		else:
			_set_info(true)


func _tap() -> void:
	taps += 1
	var action := &"zoom_in" if _from_joy else &"toggle_craft"
	for pressed in [true, false]:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = pressed
		Input.parse_input_event(ev)


func _set_info(on: bool) -> void:
	if vis != null:
		vis.set_info(on)
	Events.hud_info.emit(on)
	AudioManager.play(&"ui_info_open" if on else &"ui_info_close")


## Public for tests: hold / release Info without the keyboard.
func set_info(on: bool) -> void:
	_set_info(on)


func _typing() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit


func _track_device(event: InputEvent) -> void:
	var pad := gamepad
	if event is InputEventJoypadButton:
		pad = true
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5:
		pad = true
	elif event is InputEventKey or event is InputEventMouseButton:
		pad = false
	elif event is InputEventMouseMotion and (event as InputEventMouseMotion).relative.length() > 3.0:
		pad = false
	if pad != gamepad:
		gamepad = pad
		device_changed.emit(pad)


## Glyph text of an action for the current device ("R" / "X", "Tab" / "↑"…).
static func glyph_of(action: StringName) -> String:
	if gamepad:
		match action:
			&"interact": return "X"
			&"give_up": return "Y"
			&"toggle_craft": return "Y"
			&"hud_info": return "↑"
			&"cancel": return "B"
		return "A"
	match action:
		&"interact": return "R"
		&"give_up": return "X"
		&"toggle_craft": return "Tab"
		&"hud_info": return "Tab"
		&"cancel": return "Esc"
		&"map": return "M"
	return "?"
