extends Node
## Tracks the current day's quest steps; listens to the Events signal named by each step.

var day: int = 1
var title_small: String = ""
var title_big: String = ""
var steps: Array = []
var index: int = 0
var counter: int = 0
var day_completed: bool = false

var _connected_signal: StringName = &""
var _connected_callable: Callable


func _ready() -> void:
	Events.day_started.connect(_on_day_started)


func _on_day_started(new_day: int) -> void:
	# Let the current "survive until dawn" step consume the signal first.
	call_deferred("reset_for_day", new_day)


func reset_for_day(new_day: int) -> void:
	_disconnect_current()
	day = new_day
	var data := Quests.for_day(new_day)
	title_small = data["title_small"]
	title_big = data["title_big"]
	steps = data["steps"]
	index = 0
	counter = 0
	day_completed = false
	_connect_current()
	_emit_state()


func _connect_current() -> void:
	_disconnect_current()
	if index >= steps.size():
		return
	var step: Dictionary = steps[index]
	var sig: StringName = step["trigger"]
	if not Events.has_signal(sig):
		push_warning("Quest trigger signal missing: %s" % sig)
		return
	_connected_signal = sig
	_connected_callable = Callable(self, "_on_trigger_any").bind(index)
	# Godot needs the exact arg count: bind through a variadic-friendly wrapper.
	var argc: int = 0
	for s in Events.get_signal_list():
		if s["name"] == String(sig):
			argc = s["args"].size()
			break
	match argc:
		0: _connected_callable = Callable(self, "_t0").bind(index)
		1: _connected_callable = Callable(self, "_t1").bind(index)
		2: _connected_callable = Callable(self, "_t2").bind(index)
		_: _connected_callable = Callable(self, "_t3").bind(index)
	Events.connect(sig, _connected_callable)


func _disconnect_current() -> void:
	if _connected_signal != &"" and Events.is_connected(_connected_signal, _connected_callable):
		Events.disconnect(_connected_signal, _connected_callable)
	_connected_signal = &""


func _t0(step_i: int) -> void:
	_on_trigger([], step_i)


func _t1(a, step_i: int) -> void:
	_on_trigger([a], step_i)


func _t2(a, b, step_i: int) -> void:
	_on_trigger([a, b], step_i)


func _t3(a, b, c, step_i: int) -> void:
	_on_trigger([a, b, c], step_i)


func _on_trigger(args: Array, step_i: int) -> void:
	if step_i != index or index >= steps.size():
		return
	var step: Dictionary = steps[index]
	var filter = step.get("filter")
	if filter is Callable and not (filter as Callable).call(args):
		return
	var inc := 1
	if step.has("count_arg") and args.size() > int(step["count_arg"]):
		inc = maxi(int(args[int(step["count_arg"])]), 1)
	counter += inc
	if counter >= int(step["count"]):
		_complete_step()
	else:
		_emit_state()


func _complete_step() -> void:
	var done_i := index
	_disconnect_current()
	index += 1
	counter = 0
	Events.quest_step_completed.emit(done_i)
	AudioManager.play(&"quest_done")
	if index >= steps.size():
		day_completed = true
		Events.quest_day_completed.emit(day)
	else:
		_connect_current()
	_emit_state()


func get_state() -> Dictionary:
	var list := []
	for i in steps.size():
		var s: Dictionary = steps[i]
		var title: String = s["title"]
		if i == index and int(s["count"]) > 1:
			title += " (%d/%d)" % [counter, int(s["count"])]
		list.append({"title": title, "hint": s["hint"], "done": i < index})
	return {
		"title_small": title_small, "title_big": title_big,
		"index": index, "total": steps.size(), "steps": list, "day_completed": day_completed,
	}


func _emit_state() -> void:
	Events.quest_updated.emit(get_state())
