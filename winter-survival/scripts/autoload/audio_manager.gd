extends Node
## Audio hooks by event name (GDD §18). v1 has no audio files: every call is a silent no-op
## that keeps the player pool ready, so real streams can be plugged in via _streams later.

var _streams: Dictionary = {}
var _loops: Dictionary = {}
var _pool_2d: Array[AudioStreamPlayer] = []
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _wind: float = 0.0
var _generator_player: AudioStreamPlayer


func _ready() -> void:
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool_2d.append(p)
		var p3 := AudioStreamPlayer3D.new()
		add_child(p3)
		_pool_3d.append(p3)


func play(event: StringName, at: Vector3 = Vector3.INF) -> void:
	var stream: AudioStream = _streams.get(event)
	if stream == null:
		return
	if at == Vector3.INF:
		for p in _pool_2d:
			if not p.playing:
				p.stream = stream
				p.play()
				return
	else:
		for p in _pool_3d:
			if not p.playing:
				p.global_position = at
				p.stream = stream
				p.play()
				return


func start_loop(event: StringName, owner_node: Node) -> void:
	_loops[[event, owner_node.get_instance_id()]] = true


func stop_loop(event: StringName, owner_node: Node) -> void:
	_loops.erase([event, owner_node.get_instance_id()])


func set_wind(intensity: float) -> void:
	_wind = clampf(intensity, 0.0, 1.0)
	if Balance.PROCEDURAL_AUDIO:
		_ensure_generator()


func _ensure_generator() -> void:
	if _generator_player != null:
		return
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 44100.0
	gen.buffer_length = 0.2
	_generator_player = AudioStreamPlayer.new()
	_generator_player.stream = gen
	add_child(_generator_player)
	_generator_player.play()


func _process(_delta: float) -> void:
	if _generator_player == null:
		return
	var playback := _generator_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return
	var frames := playback.get_frames_available()
	var lp := 0.0
	for i in frames:
		var noise := randf() * 2.0 - 1.0
		lp += (noise - lp) * 0.05
		var v := lp * 0.08 * _wind
		playback.push_frame(Vector2(v, v))
