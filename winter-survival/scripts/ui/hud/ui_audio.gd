class_name UiAudio
extends Node
## UI audio of the HUD that is not tied to one notice (H3; docs/research/10_hud_ux.md appendix §5.6, docs/AUDIO.md
## §10 "H3: conectar heartbeat()"): with a HUD that hides, the critical states are HEARD.
##   heartbeat   AudioManager.heartbeat(intensity): own health < 25 → 0.35 … 1 (lower = faster, louder), downed
##               0.8, a teammate bleeding out 0.22 (a soft pulse under the rest); 0 otherwise. Sent on change only.
##   radio       while a teammate stays down, a soft `ui_radio_static` every 10 s after the `ui_mate_down` cue
##               (appendix §5.6 "se repite suave cada 10 s mientras dure"), with its caption toward the teammate.
## (`ui_objective_update` is MissionLine's; `ui_mate_down` is the P0 of the NotifyRouter.)

var team: TeamTracker
var captions: Node
var intensity: float = 0.0
var statics: int = 0
var _static_t: float = -1.0


func _process(delta: float) -> void:
	var p := GameFlow.local_player() as Player
	var want := 0.0
	if p != null and p.state != null and not p.dead and GameFlow.in_game:
		if p.downed:
			want = 0.8
		elif p.state.health < Balance.LOW_HEALTH:
			want = lerpf(0.35, 1.0, clampf((Balance.LOW_HEALTH - p.state.health) / Balance.LOW_HEALTH, 0.0, 1.0))
	var down := team.nearest_downed() if team != null else {}
	if not down.is_empty() and p != null and not p.dead:
		want = maxf(want, UiTokens.HEARTBEAT_MATE)
		if _static_t < 0.0:
			_static_t = UiTokens.MATE_DOWN_REPEAT
		_static_t -= delta
		if _static_t <= 0.0:
			_static_t = UiTokens.MATE_DOWN_REPEAT
			var o := TeamTracker.player_of(down)
			if captions != null and o != null:
				captions.call("expect", &"ui_radio_static", o.global_position, str(down["name"]), o.peer_id)
			AudioManager.play(&"ui_radio_static")
			statics += 1
	else:
		_static_t = -1.0
	if absf(want - intensity) > 0.02 or (want == 0.0 and intensity != 0.0):
		intensity = want
		AudioManager.heartbeat(want)


func _exit_tree() -> void:
	if intensity > 0.0:
		AudioManager.heartbeat(0.0)
