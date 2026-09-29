class_name PickupStack
extends Control
## Side stack for pickups and crafting (appendix §6.5 channel "feed", restyled for §V): right-aligned whisper lines
## bottom right, the newest at the bottom, 4 at most. The same key within 2.5 s MERGES: "Leña +2 (4)" becomes
## "Leña +3 (5)" and its time grows by 1 s (5 s at most). Lines enter in 200 ms, stay 2.5 s, leave in 600 ms.

const LINE_H := 28.0

var lines: Array = []   # [{key, label, delta, total, born, until, a}]
var clock: float = 0.0
var merges: int = 0
var _scrim: Scrim


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrim = Scrim.new()
	_scrim.name = "Scrim"
	_scrim.show_behind_parent = true
	_scrim.strength = 0.9
	add_child(_scrim)


## Adds or merges a line. `delta` 0 = a plain message; `total` 0 = no "(n)".
func add(key: String, label: String, delta: int, total: int) -> void:
	var read := float(UiTokens.T_PICKUP[1])
	for l: Dictionary in lines:
		if str(l["key"]) == key and clock - float(l["born"]) < UiTokens.T_PICKUP_MAX and clock < float(l["until"]):
			l["delta"] = int(l["delta"]) + delta
			l["total"] = total
			l["label"] = label
			l["until"] = minf(float(l["until"]) + UiTokens.T_PICKUP_MERGE, float(l["born"]) + UiTokens.T_PICKUP_MAX)
			merges += 1
			queue_redraw()
			return
	lines.append({"key": key, "label": label, "delta": delta, "total": total, "born": clock, "until": clock + read, "a": 0.0})
	while lines.size() > UiTokens.PICKUP_LINES:
		lines.pop_front()
	AudioManager.play(&"ui_pickup")
	queue_redraw()


## A crafted item: the pickup line of that item (if it came first) becomes "Fabricado · X".
func replace_item_line(item_name: String, key: String, label: String) -> void:
	for l: Dictionary in lines:
		if str(l["label"]) == item_name and clock - float(l["born"]) < 1.5:
			l["key"] = key
			l["label"] = label
			l["delta"] = 0
			l["total"] = 0
			queue_redraw()
			return
	add(key, label, 0, 0)


func text_of(l: Dictionary) -> String:
	var s := str(l["label"])
	if int(l["delta"]) > 0:
		s += " +%d" % int(l["delta"])
	if int(l["total"]) > 0 and int(l["total"]) != int(l["delta"]):
		s += " (%d)" % int(l["total"])
	return s


func _process(delta: float) -> void:
	clock += delta
	if lines.is_empty():
		_scrim.visible = false
		return
	var tin := UiMotion.dur(float(UiTokens.T_PICKUP[0]))
	var tout := UiMotion.dur(float(UiTokens.T_PICKUP[2]))
	var i := 0
	var maxa := 0.0
	while i < lines.size():
		var l: Dictionary = lines[i]
		if clock < float(l["until"]):
			l["a"] = minf(float(l["a"]) + delta / tin, 1.0)
		else:
			l["a"] = float(l["a"]) - delta / tout
		if float(l["a"]) <= 0.0 and clock >= float(l["until"]):
			lines.remove_at(i)
			continue
		maxa = maxf(maxa, float(l["a"]))
		i += 1
	_scrim.visible = maxa > 0.002
	_scrim.modulate.a = maxa
	_scrim.position = Vector2(size.x - 380.0, size.y - LINE_H * lines.size() - 70.0)
	_scrim.size = Vector2(520.0, LINE_H * lines.size() + 130.0)
	queue_redraw()


func _draw() -> void:
	var y := size.y
	for i in range(lines.size() - 1, -1, -1):
		var l: Dictionary = lines[i]
		var a := float(l["a"])
		if a <= 0.002:
			y -= LINE_H
			continue
		var ease := UiMotion.ease_in_curve(a) if clock < float(l["until"]) else UiMotion.ease_out_curve(a)
		var label := str(l["label"])
		var extra := ""
		if int(l["delta"]) > 0:
			extra = " +%d" % int(l["delta"])
		var tot := ""
		if int(l["total"]) > 0 and int(l["total"]) != int(l["delta"]):
			tot = " (%d)" % int(l["total"])
		var w_tot := UiStyle.text_width(&"text_num", tot)
		var w_extra := UiStyle.text_width(&"text_num", extra)
		var w_label := UiStyle.text_width(&"whisper", label)
		var x := size.x - w_tot - w_extra - w_label + UiMotion.slide(UiTokens.MOVE_MAX) * (1.0 - ease)
		UiStyle.draw_text(self, &"whisper", Vector2(x, y - 8.0), label, UiTokens.INK, HORIZONTAL_ALIGNMENT_LEFT, -1.0, ease)
		UiStyle.draw_text(self, &"text_num", Vector2(x + w_label, y - 8.0), extra, UiTokens.INK_RGB, HORIZONTAL_ALIGNMENT_LEFT, -1.0, ease)
		UiStyle.draw_text(self, &"text_num", Vector2(x + w_label + w_extra, y - 8.0), tot, UiTokens.INK_50, HORIZONTAL_ALIGNMENT_LEFT, -1.0, ease)
		y -= LINE_H
