class_name DownedOverlay
extends Control
## The local player downed (M4; docs/research/10_hud_ux.md appendix §6.13 restyled for §V): centred, no box —
## a 64 px ring that drains with the bleed-out around a line skull, "DESANGRÁNDOTE · 47 s" in Barlow Condensed
## Light, "arrástrate hacia un compañero · mantén X para rendirte" with the hold ring of the give-up, and the
## nearest teammate's distance. Being revived: "TE ESTÁN REANIMANDO · 62 %" and the ring fills.
## `title` is the Label the smoke test reads (Hud.down_title).

const RING := 64.0

var title: Label
var team: TeamTracker
var _t: float = 0.0
var _scrim: Scrim


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrim = Scrim.new()
	_scrim.name = "Scrim"
	_scrim.show_behind_parent = true
	_scrim.strength = 1.3
	add_child(_scrim)
	title = UiStyle.label(&"down_title", "DESANGRÁNDOTE")
	title.name = "Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	visible = false


func _process(delta: float) -> void:
	var lp := GameFlow.local_player() as Player
	var downed := lp != null and lp.downed and not lp.dead
	visible = downed
	if not downed:
		return
	_t += delta
	var revived := lp.revive_by != 0
	title.text = "DESANGRÁNDOTE · %d s" % lp.bleed if not revived else "TE ESTÁN REANIMANDO · %d %%" % lp.revive_pct
	title.position = Vector2(size.x * 0.5 - 400.0, size.y * 0.5 - 150.0)
	title.size = Vector2(800.0, 50.0)
	_scrim.position = Vector2(size.x * 0.5 - 520.0, size.y * 0.5 - 330.0)
	_scrim.size = Vector2(1040.0, 360.0)
	queue_redraw()


func _draw() -> void:
	var lp := GameFlow.local_player() as Player
	if lp == null or not lp.downed:
		return
	var c := Vector2(size.x * 0.5, size.y * 0.5 - 200.0)
	var revived := lp.revive_by != 0
	var v := float(lp.revive_pct) / 100.0 if revived else clampf(float(lp.bleed) / Balance.DOWNED_BLEED, 0.0, 1.0)
	var pl := UiMotion.pulse(_t, 1.0)
	Whisper.ring(self, c, RING, v, UiTokens.ACCENT if revived else UiTokens.BLOOD, 2.0, 0.75 + 0.25 * pl)
	Whisper.draw_icon(self, "skull", c, 28.0, UiTokens.BLOOD_TEXT)
	if revived:
		return
	# hint + give-up hold ring
	var pad := HudInput.gamepad
	var y := size.y * 0.5 - 70.0
	var t1 := "arrástrate hacia un compañero · mantén"
	var t2 := "para rendirte"
	var w1 := UiStyle.text_width(&"whisper", t1)
	var w2 := UiStyle.text_width(&"whisper", t2)
	var gw := 26.0 if pad else 28.0
	var x := size.x * 0.5 - (w1 + gw + w2 + 20.0) * 0.5
	UiStyle.draw_text(self, &"whisper", Vector2(x, y), t1, UiTokens.INK)
	x += w1 + 10.0
	var gc := Vector2(x + gw * 0.5, y - 6.0)
	Whisper.glyph(self, gc, "Y" if pad else "X", pad)
	var give := float(lp.interactor.get("_give_up_t")) if lp.interactor != null else -1.0
	if give >= 0.0:
		Whisper.hold_ring(self, gc, give / Balance.GIVE_UP_HOLD, 1.0, 36.0)
	x += gw + 10.0
	UiStyle.draw_text(self, &"whisper", Vector2(x, y), t2, UiTokens.INK)
	# nearest teammate
	if team != null and not team.mates.is_empty():
		var m: Dictionary = team.mates[0]
		var t := "%s · %s" % [str(m["name"]), UiTokens.distance(float(m["dist"]))]
		var tw := UiStyle.text_width(&"text_num", t)
		UiStyle.draw_text(self, &"text_num", Vector2(size.x * 0.5 - tw * 0.5, y + 32.0), t, UiTokens.INK_70)
