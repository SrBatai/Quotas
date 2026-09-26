class_name QuestComponent
extends Node
## Server-side quest tracker of one player (the old `QuestManager` autoload): listens to the player's own
## simulation events plus the world's day roll; the state dictionary is mirrored to the owner.

var state: PlayerState
var day: int = 1
var title_small: String = ""
var title_big: String = ""
var steps: Array = []
var index: int = 0
var counter: int = 0
var day_completed: bool = false


func setup(s: PlayerState) -> void:
	state = s
	state.sim_event.connect(_on_sim_event)
	Events.day_started.connect(_on_day_started)
	reset_for_day(WorldState.day_now())


func _on_day_started(new_day: int) -> void:
	# let the current "survive until dawn" step consume the roll first
	_on_trigger(&"day_started", [new_day])
	call_deferred("reset_for_day", new_day)


func reset_for_day(new_day: int) -> void:
	day = new_day
	var data := Quests.for_day(new_day)
	title_small = data["title_small"]
	title_big = data["title_big"]
	steps = data["steps"]
	index = 0
	counter = 0
	day_completed = false
	_emit_state()


func _on_sim_event(kind: StringName, args: Array) -> void:
	_on_trigger(kind, args)


func _on_trigger(kind: StringName, args: Array) -> void:
	if index >= steps.size():
		return
	var step: Dictionary = steps[index]
	if step["trigger"] != kind:
		return
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
	index += 1
	counter = 0
	state.steps_done += 1
	AudioManager.play(&"quest_done")
	if index >= steps.size():
		day_completed = true
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
		"title_small": title_small, "title_big": title_big, "day": day,
		"index": index, "total": steps.size(), "steps": list, "day_completed": day_completed,
	}


func _emit_state() -> void:
	state.quest_state = get_state()
	state.mark(&"quest")


func to_profile() -> Dictionary:
	return {"day": day, "index": index, "counter": counter, "steps_done": state.steps_done}


func from_profile(p: Dictionary) -> void:
	if p.is_empty() or int(p.get("day", -1)) != WorldState.day_now():
		return
	index = clampi(int(p.get("index", 0)), 0, steps.size())
	counter = int(p.get("counter", 0))
	state.steps_done = int(p.get("steps_done", 0))
	day_completed = index >= steps.size()
	_emit_state()
