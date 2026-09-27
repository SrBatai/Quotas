extends SceneTree
## Network condition simulator for the net tests (ARQ v2 §18 `--net-sim`, M5): a UDP relay between the clients and
## the dedicated server that delays every datagram by `latency`/2 ± `jitter`/2 ms in each direction (a round trip of
## `latency` ± `jitter` ms: the ping a player would see) and drops `loss` % of them in each direction (ENet retransmits the reliable ones; the unreliable poses / zombie snapshots are simply lost).
##   godot --headless -s tests/net/net_sim.gd ++ --listen 7900 --to 7890 --latency 150 --jitter 20 --loss 2
## One upstream socket per client address, so the server sees N distinct peers. Prints "[SIM] relay …" lines and a
## summary at exit. Runs until killed.

var listen_port: int = 7900
var to_port: int = 7777
var latency_ms: float = 150.0
var jitter_ms: float = 20.0
var loss_pct: float = 2.0
var _server := UDPServer.new()
var _pairs: Array[Dictionary] = []   # {client: PacketPeerUDP, up: PacketPeerUDP, key}
var _queue: Array = []               # [deliver_at_usec, PacketPeerUDP target, PackedByteArray]
var _rng := RandomNumberGenerator.new()
var stats := {"up": 0, "down": 0, "dropped": 0}
var _t_report: int = 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		match args[i]:
			"--listen": i += 1; listen_port = int(args[i])
			"--to": i += 1; to_port = int(args[i])
			"--latency": i += 1; latency_ms = float(args[i])
			"--jitter": i += 1; jitter_ms = float(args[i])
			"--loss": i += 1; loss_pct = float(args[i])
		i += 1
	_rng.seed = 12345
	var err := _server.listen(listen_port, "127.0.0.1")
	if err != OK:
		print("[SIM] cannot listen on %d (%s)" % [listen_port, error_string(err)])
		quit(2)
		return
	print("[SIM] relay 127.0.0.1:%d -> 127.0.0.1:%d rtt=%.0f ms jitter=%.0f ms loss=%.1f %% per direction" % [listen_port, to_port, latency_ms, jitter_ms, loss_pct])
	_t_report = Time.get_ticks_msec()


## One-way delay: half the round trip (the `latency` is the ping a player would see) ± half the jitter.
func _delay_usec() -> int:
	return int((latency_ms * 0.5 + _rng.randf_range(-jitter_ms, jitter_ms) * 0.5) * 1000.0)


func _schedule(target: PacketPeerUDP, bytes: PackedByteArray, dir: String) -> void:
	if _rng.randf() * 100.0 < loss_pct:
		stats["dropped"] = int(stats["dropped"]) + 1
		return
	stats[dir] = int(stats[dir]) + 1
	_queue.append([Time.get_ticks_usec() + _delay_usec(), target, bytes])


func _process(_delta: float) -> bool:
	_server.poll()
	while _server.is_connection_available():
		var c := _server.take_connection()
		var up := PacketPeerUDP.new()
		up.bind(0, "127.0.0.1")
		up.connect_to_host("127.0.0.1", to_port)
		_pairs.append({"client": c, "up": up})
		print("[SIM] new client %s:%d" % [c.get_packet_ip(), c.get_packet_port()])
	for p in _pairs:
		var c: PacketPeerUDP = p["client"]
		var up: PacketPeerUDP = p["up"]
		while c.get_available_packet_count() > 0:
			_schedule(up, c.get_packet(), "up")
		while up.get_available_packet_count() > 0:
			_schedule(c, up.get_packet(), "down")
	var now := Time.get_ticks_usec()
	var k := 0
	while k < _queue.size():
		var e: Array = _queue[k]
		if now >= int(e[0]):
			(e[1] as PacketPeerUDP).put_packet(e[2])
			_queue.remove_at(k)
		else:
			k += 1
	if Time.get_ticks_msec() - _t_report > 10000:
		_t_report = Time.get_ticks_msec()
		print("[SIM] up=%d down=%d dropped=%d queued=%d clients=%d" % [stats["up"], stats["down"], stats["dropped"], _queue.size(), _pairs.size()])
	OS.delay_msec(1)   # ~1 kHz: latency precision ±1 ms without spinning a whole core
	return false
