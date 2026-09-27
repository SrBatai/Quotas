class_name HudVisibility
extends Node
## Visibility state machine of the HUD v2 (docs/research/10_hud_ux.md §V.3, §V.8 "HudVisibility"): every element
## is hidden → appearing → shown → fading. Components `poke()` their element when their `Events` signal arrives
## (shown for the read time, then it fades by itself), or `set_hold()` it while a condition lasts (a low vital, a
## downed teammate). Holding Info (`hud_info`: Tab / D‑pad ↑) shows every element registered with `on_info`.
## The HUD preset / per-element override (UiSettings) turns an element into `always` or `hidden`.

signal info_changed(active: bool)

enum Phase { HIDDEN, APPEARING, SHOWN, FADING }


class Element:
	var id: StringName
	var node: CanvasItem
	var t_in: float = 0.2
	var read: float = 3.0
	var t_out: float = 0.6
	var on_info: bool = false
	var group: StringName = &""
	var until: float = -1.0
	var hold: bool = false
	var progress: float = 0.0     # 0..1 linear
	var alpha: float = 0.0        # eased
	var phase: int = Phase.HIDDEN
	var want: bool = false
	var pokes: int = 0
	var mode: StringName = &"dynamic"


var info_active: bool = false
## Seconds of HUD clock (process time of the HUD).
var now: float = 0.0
var _els: Dictionary = {}
var _settings: UiSettings


var _reduced: bool = false


func _ready() -> void:
	_settings = UiSettings.get_instance()
	_settings.changed.connect(_refresh_modes)
	_refresh_modes()


## Modes (preset / overrides) and reduced motion are cached until the settings change.
func _refresh_modes() -> void:
	_reduced = UiMotion.reduced()
	for id: StringName in _els:
		var e: Element = _els[id]
		e.mode = _settings.mode_of(e.group) if e.group != &"" else &"dynamic"


## Registers an element. `timing` = [in, read, out] seconds (UiTokens.T_*). `group` = the settings key of the
## element (UiSettings.mode_of: vitals, hotbar, tracker, clock, …; empty = always dynamic).
func register(id: StringName, node: CanvasItem, timing: Array, on_info: bool = false, group: StringName = &"") -> void:
	var e := Element.new()
	e.id = id
	e.node = node
	e.t_in = float(timing[0])
	e.read = float(timing[1])
	e.t_out = float(timing[2])
	e.on_info = on_info
	e.group = group
	e.mode = _settings.mode_of(group) if group != &"" and _settings != null else &"dynamic"
	_els[id] = e
	if node != null:
		node.modulate.a = 0.0
		node.visible = false


func has(id: StringName) -> bool:
	return _els.has(id)


## Shows the element now and (re)starts its read time (`read` < 0: the registered one).
func poke(id: StringName, read: float = -1.0) -> void:
	var e: Element = _els.get(id)
	if e == null:
		return
	e.until = maxf(e.until, now + (e.read if read < 0.0 else read)) if e.want else now + (e.read if read < 0.0 else read)
	e.pokes += 1


## Keeps the element visible while `on` (conditions such as "Salud < 50").
func set_hold(id: StringName, on: bool) -> void:
	var e: Element = _els.get(id)
	if e != null:
		e.hold = on


## Ends the read time at once (the element starts fading).
func release(id: StringName) -> void:
	var e: Element = _els.get(id)
	if e != null:
		e.until = -1.0
		e.hold = false


func alpha_of(id: StringName) -> float:
	var e: Element = _els.get(id)
	return e.alpha if e != null else 0.0


## Linear 0..1 progress (for slides that follow the fade).
func progress_of(id: StringName) -> float:
	var e: Element = _els.get(id)
	return e.progress if e != null else 0.0


func phase_of(id: StringName) -> int:
	var e: Element = _els.get(id)
	return e.phase if e != null else Phase.HIDDEN


## True while the element wants to be visible (it may still be fading in).
func is_on(id: StringName) -> bool:
	var e: Element = _els.get(id)
	return e != null and e.want


func mode_of(id: StringName) -> StringName:
	var e: Element = _els.get(id)
	if e == null or e.group == &"":
		return &"dynamic"
	return _settings.mode_of(e.group)


func set_info(active: bool) -> void:
	if active == info_active:
		return
	info_active = active
	info_changed.emit(active)


## Tests / screenshots: every element jumps to its current target.
func settle() -> void:
	for id: StringName in _els:
		var e: Element = _els[id]
		_eval_want(e)
		e.progress = 1.0 if e.want else 0.0
		_apply(e)


## Tests: clears every read timer (the HUD returns to rest after the fades).
func clear_all() -> void:
	for id: StringName in _els:
		var e: Element = _els[id]
		e.until = -1.0
		e.hold = false


func ids() -> Array:
	return _els.keys()


func _eval_want(e: Element) -> void:
	var mode := e.mode
	if mode == &"hidden":
		e.want = false
	elif mode == &"always":
		e.want = true
	else:
		e.want = e.hold or now < e.until or (info_active and e.on_info)


func _process(delta: float) -> void:
	now += delta
	var reduced := _reduced
	for e: Element in _els.values():
		_eval_want(e)
		if not e.want and e.progress <= 0.0 and e.phase == Phase.HIDDEN:
			continue   # at rest: nothing to do
		if e.want and e.progress < 1.0:
			e.progress = minf(e.progress + delta / maxf(UiTokens.T_REDUCED if reduced else e.t_in, 0.001), 1.0)
		elif not e.want and e.progress > 0.0:
			e.progress = maxf(e.progress - delta / maxf(UiTokens.T_REDUCED if reduced else e.t_out, 0.001), 0.0)
		_apply(e)


func _apply(e: Element) -> void:
	if e.want:
		e.alpha = UiMotion.ease_in_curve(e.progress)
		e.phase = Phase.SHOWN if e.progress >= 1.0 else Phase.APPEARING
	else:
		e.alpha = UiMotion.ease_out_curve(e.progress)
		e.phase = Phase.HIDDEN if e.progress <= 0.0 else Phase.FADING
	if e.node != null:
		e.node.modulate.a = e.alpha
		var vis := e.alpha > 0.002
		if e.node.visible != vis:
			e.node.visible = vis
