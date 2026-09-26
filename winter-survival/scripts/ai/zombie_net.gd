class_name ZombieNet
extends Node
## Zombie replication (ARQ v2 §6.3, §10.4; PLAN C10–C13, M4). Own binary packets through
## `SceneMultiplayer.send_bytes` (no nodes, no synchronizers):
##   ZSNAP (unreliable ordered, channel 2): u8 type | u32 tick | u8 n_chunks | per chunk { u8 cx | u8 cz | u8 n |
##     n × { u16 id | 3 B x,z (12 bits each, 1.56 cm over the 64 m chunk) | i16 y cm | u8 yaw | u8 state|flags<<5 } }
##     = 9 B per zombie. Per peer, a zombie is sent when its quantized pose/state changed since the last send to that
##     peer and its distance band is due (15 Hz < 30 m, 10 Hz < 60 m, 4 Hz beyond), and in any case once a second
##     (keyframe). A packet never exceeds MAX_PACKET bytes: the farthest zombies wait for the next tick.
##   ZREL (reliable, channel 1): u8 type | u8 n | n records: ENTER {u16 id, u8 kind, u8 variant, 3 × f32 pos, u8 yaw,
##     u8 hp %, u8 state}, LEAVE {u16 id}, EVENT {u16 id, u8 event, u8 arg, u8 dir}, FX {u8 fx, 3 × f32 pos, u8 a,
##     u8 b} (noise ring, blood on the snow, bloater cloud).
## Interest (2 Hz): the living and dead records in the 3 × 3 chunks around the peer's player, within
## Balance.ZOMBIE_L1_RADIUS, at most MAX_INTEREST (nearest first). Offline (web, tests) the local client gets the
## very same bytes by a direct call, so one code path is exercised everywhere.

const PKT_ZSNAP := 10
const PKT_ZREL := 11
const REC_ENTER := 1
const REC_LEAVE := 2
const REC_EVENT := 3
const REC_FX := 4
const FX_NOISE := 1
const FX_BLOOD := 2
const FX_CLOUD := 3
const FX_PLAYER_HIT := 4

const MAX_PACKET := 1200
const MAX_INTEREST := 200
const ENTRY_SIZE := 9
const INTEREST_PERIOD := 0.5
const KEYFRAME := 1.0
const BANDS := [[30.0, 4], [60.0, 6], [INF, 15]]   # [max distance, physics ticks between two sends]
const Q_XZ := 4095.0

static var instance: ZombieNet

var sys: ZombieSystem
## Test / bench hook: bot players (not network peers) for which packets are built and counted but not sent.
var bench_players: Array = []
## Stats: bytes sent per peer (running), packets, entries; bytes/s per peer over the last second.
var stats: Dictionary = {"bytes": 0, "snap_packets": 0, "entries": 0, "rel_packets": 0, "usec": 0}
var kbps: Dictionary = {}          # peer -> kB/s of zombie data (last second)

var _peers: Dictionary = {}        # peer -> PeerState
var _tick: int = 0
var _interest_t: float = 0.0
var _rate_t: float = 0.0
# per-slot quantization cache (shared by every peer in a tick)
var _q_tick := PackedInt32Array()
var _q_key := PackedInt64Array()
var _q_bytes: Array = []


class PeerState:
	extends RefCounted
	var peer: int
	var player: Player
	var bench: bool = false
	var known: Dictionary = {}       # slot -> id
	var order := PackedInt32Array()  # known slots, nearest first
	var sent_key: Dictionary = {}    # slot -> last quantized key sent
	var sent_tick: Dictionary = {}   # slot -> physics tick of the last send
	var sent_t: Dictionary = {}      # slot -> time of the last send (keyframes)
	var rel := StreamPeerBuffer.new()
	var rel_n: int = 0
	var bytes: int = 0


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func setup(p_sys: ZombieSystem) -> void:
	sys = p_sys
	Net.peer_left.connect(func(peer: int) -> void: _peers.erase(peer))


# ------------------------------------------------------------------ server → peers
func _physics_process(delta: float) -> void:
	if sys == null or not Net.is_server:
		return
	var t0 := Time.get_ticks_usec()
	_run(delta)
	stats["usec"] = Time.get_ticks_usec() - t0


func _run(delta: float) -> void:
	_tick += 1
	_interest_t -= delta
	if _interest_t <= 0.0:
		# one peer per call, the whole set every INTEREST_PERIOD (spreads the scan over the ticks)
		_interest_t = INTEREST_PERIOD / float(maxi(_peers.size(), 1))
		_update_interest()
	_rate_t += delta
	if _rate_t >= 1.0:
		for peer in _peers:
			var ps: PeerState = _peers[peer]
			kbps[peer] = float(ps.bytes) / _rate_t / 1000.0
			ps.bytes = 0
		_rate_t = 0.0
	# reliable records every tick; snapshots at 30 Hz per peer, half of the peers on each tick (spreads the cost)
	var k := 0
	for peer in _peers.keys():
		var ps: PeerState = _peers[peer]
		if not is_instance_valid(ps.player):
			_peers.erase(peer)
			continue
		_flush_rel(ps)
		if (_tick + k) % 2 == 0:
			_send_snapshot(ps)
		k += 1


## The peers that receive zombies: every connected client with a player, the local player offline, bench bots.
func _targets() -> Array:
	var out: Array = []
	var world := sys.world
	if world == null:
		return out
	var players := world.get_node_or_null("Players")
	if players == null:
		return out
	var peers := multiplayer.get_peers() if multiplayer.multiplayer_peer != null else PackedInt32Array()
	for c in players.get_children():
		var p := c as Player
		if p == null or p.disconnected:
			continue
		if p.is_local and Net.has_client:
			out.append([p.peer_id, p, false])
		elif peers.has(p.peer_id) and Net.peer_ready(p.peer_id):
			out.append([p.peer_id, p, false])
	for b in bench_players:
		if is_instance_valid(b):
			out.append([(b as Player).peer_id, b, true])
	return out


var _interest_rr: int = 0


func _update_interest() -> void:
	var seen := {}
	var targets := _targets()
	for t in targets:
		seen[int(t[0])] = true
	for peer in _peers.keys():
		if not seen.has(peer):
			_peers.erase(peer)
	if targets.is_empty():
		return
	# new peers first, else round robin
	var pick: Array = []
	for t in targets:
		if not _peers.has(int(t[0])):
			pick = t
			break
	if pick.is_empty():
		_interest_rr = (_interest_rr + 1) % targets.size()
		pick = targets[_interest_rr]
	for t in [pick]:
		var peer := int(t[0])
		var ps: PeerState = _peers.get(peer)
		if ps == null:
			ps = PeerState.new()
			ps.peer = peer
			ps.bench = bool(t[2])
			_peers[peer] = ps
		ps.player = t[1]
		var pp := ps.player.global_position
		var pcx := WorldConst.chunk_of(pp.x)
		var pcz := WorldConst.chunk_of(pp.z)
		var cand: Array = []
		for i in sys.used.size():
			if sys.used[i] == 0:
				continue
			var q := sys.pos[i]
			if WorldConst.ring_dist(WorldConst.chunk_of(q.x), WorldConst.chunk_of(q.z), pcx, pcz) > WorldConst.INTEREST_RADIUS:
				continue
			var d := Vector2(q.x - pp.x, q.z - pp.z).length()
			if d <= Balance.ZOMBIE_L1_RADIUS:
				cand.append([d, i])
		cand.sort_custom(func(a, b) -> bool: return float(a[0]) < float(b[0]))
		if cand.size() > MAX_INTEREST:
			cand.resize(MAX_INTEREST)
		var now_set := {}
		ps.order.clear()
		for c in cand:
			var i := int(c[1])
			now_set[i] = true
			ps.order.append(i)
			if not ps.known.has(i) or int(ps.known[i]) != sys.net_id[i]:
				if ps.known.has(i):
					_rec_leave(ps, int(ps.known[i]))
				ps.known[i] = sys.net_id[i]
				_rec_enter(ps, i)
		for i in ps.known.keys():
			if not now_set.has(i):
				_rec_leave(ps, int(ps.known[i]))
				ps.known.erase(i)
				ps.sent_key.erase(i)
				ps.sent_tick.erase(i)
				ps.sent_t.erase(i)


## A record is going away (despawn / corpse expired): every peer that knew it gets a LEAVE now.
func on_release(i: int) -> void:
	for peer in _peers:
		var ps: PeerState = _peers[peer]
		if ps.known.has(i):
			_rec_leave(ps, int(ps.known[i]))
			ps.known.erase(i)
			ps.sent_key.erase(i)
			ps.sent_tick.erase(i)
			ps.sent_t.erase(i)


## A tick with more than 250 reliable records is split in several packets (the count is a byte).
func _room(ps: PeerState) -> void:
	if ps.rel_n >= 250:
		_flush_rel(ps)


func _rec_enter(ps: PeerState, i: int) -> void:
	_room(ps)
	var b := ps.rel
	b.put_u8(REC_ENTER)
	b.put_u16(sys.net_id[i])
	b.put_u8(sys.kind[i])
	b.put_u8(sys.variant[i])
	var p := sys.pos[i]
	b.put_float(p.x)
	b.put_float(p.y)
	b.put_float(p.z)
	b.put_u8(_yaw8(sys.yaw[i]))
	b.put_u8(clampi(int(sys.hp[i] / ZombieKinds.max_hp(sys.kind[i]) * 100.0), 0, 100))
	b.put_u8(sys.state[i] | (sys.flags[i] << 5))
	ps.rel_n += 1


func _rec_leave(ps: PeerState, id: int) -> void:
	_room(ps)
	ps.rel.put_u8(REC_LEAVE)
	ps.rel.put_u16(id)
	ps.rel_n += 1


## Server: a zombie event (hit, crit, die, wake, attack, stagger, knock, cloud, execute) for every peer that knows it.
func zevent(i: int, ev: int, arg: int, dir: int) -> void:
	for peer in _peers:
		var ps: PeerState = _peers[peer]
		if ps.known.has(i) and int(ps.known[i]) == sys.net_id[i]:
			_room(ps)
			ps.rel.put_u8(REC_EVENT)
			ps.rel.put_u16(sys.net_id[i])
			ps.rel.put_u8(ev)
			ps.rel.put_u8(arg & 0xFF)
			ps.rel.put_u8(dir & 0xFF)
			ps.rel_n += 1


## Server: a visible effect at `pos` for the peers whose player is within `reach` m.
func fx(kind: int, pos: Vector3, a: int, b: int = 0, reach: float = 70.0) -> void:
	for peer in _peers:
		var ps: PeerState = _peers[peer]
		if not is_instance_valid(ps.player):
			continue
		var pp := ps.player.global_position
		if Vector2(pp.x - pos.x, pp.z - pos.z).length() > reach:
			continue
		_room(ps)
		ps.rel.put_u8(REC_FX)
		ps.rel.put_u8(kind)
		ps.rel.put_float(pos.x)
		ps.rel.put_float(pos.y)
		ps.rel.put_float(pos.z)
		ps.rel.put_u8(clampi(a, 0, 255))
		ps.rel.put_u8(clampi(b, 0, 255))
		ps.rel_n += 1


## SoundEvents → the white ring on every client that can see it (GDD §6.3 "Feedback").
func fx_noise(pos: Vector3, radius: float, kind: int) -> void:
	fx(FX_NOISE, pos, int(round(radius * 2.0)), kind, maxf(radius + 50.0, 70.0))


func _flush_rel(ps: PeerState) -> void:
	if ps.rel_n == 0:
		return
	var out := PackedByteArray([PKT_ZREL, ps.rel_n])
	out.append_array(ps.rel.data_array)
	ps.rel = StreamPeerBuffer.new()
	ps.rel_n = 0
	_deliver(ps, out, true)
	stats["rel_packets"] = int(stats["rel_packets"]) + 1


func _deliver(ps: PeerState, bytes: PackedByteArray, reliable: bool) -> void:
	ps.bytes += bytes.size() + 8   # + ENet/SceneMultiplayer header estimate
	stats["bytes"] = int(stats["bytes"]) + bytes.size()
	if ps.bench:
		return
	if ps.player.is_local and Net.has_client:
		if ZombieClient.instance != null:
			ZombieClient.instance.on_packet(bytes)
		return
	if reliable:
		multiplayer.send_bytes(bytes, ps.peer, MultiplayerPeer.TRANSFER_MODE_RELIABLE, 1)
	else:
		multiplayer.send_bytes(bytes, ps.peer, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED, 2)


static func _yaw8(y: float) -> int:
	return int(round(fposmod(y, TAU) / TAU * 256.0)) & 0xFF


## Quantized snapshot entry of slot `i` (cached for this tick): [key (int), bytes (9), cx, cz].
func _quant(i: int) -> Array:
	if _q_tick.size() < sys.used.size():
		_q_tick.resize(sys.used.size())
		_q_key.resize(sys.used.size())
		_q_bytes.resize(sys.used.size())
	if _q_tick[i] == _tick:
		return _q_bytes[i]
	var p := sys.pos[i]
	var cx := WorldConst.chunk_of(p.x)
	var cz := WorldConst.chunk_of(p.z)
	var o := WorldConst.chunk_origin(cx, cz)
	var qx := clampi(int(round((p.x - o.x) / WorldConst.CHUNK_SIZE * Q_XZ)), 0, 4095)
	var qz := clampi(int(round((p.z - o.y) / WorldConst.CHUNK_SIZE * Q_XZ)), 0, 4095)
	var qy := clampi(int(round(p.y * 100.0)), -32768, 32767)
	var qa := _yaw8(sys.yaw[i])
	var qs := (sys.state[i] & 0x1F) | ((sys.flags[i] & 7) << 5)
	var id := sys.net_id[i]
	var bytes := PackedByteArray()
	bytes.resize(ENTRY_SIZE)
	bytes.encode_u16(0, id)
	bytes[2] = qx & 0xFF
	bytes[3] = ((qx >> 8) & 0x0F) | ((qz & 0x0F) << 4)
	bytes[4] = (qz >> 4) & 0xFF
	bytes.encode_s16(5, qy)
	bytes[7] = qa
	bytes[8] = qs
	var key := (qx << 44) | (qz << 32) | ((qy & 0xFFFF) << 16) | (qa << 8) | qs
	var out := [key, bytes, cx, cz]
	_q_tick[i] = _tick
	_q_key[i] = key
	_q_bytes[i] = out
	return out


func _send_snapshot(ps: PeerState) -> void:
	if ps.order.is_empty():
		return
	var pp := ps.player.global_position
	var now := Time.get_ticks_msec() / 1000.0
	var tick := Engine.get_physics_frames()
	var by_chunk: Dictionary = {}     # cx * 256 + cz -> PackedByteArray of entries
	var counts: Dictionary = {}
	var size := 6
	var n := 0
	for i in ps.order:
		if not ps.known.has(i) or sys.used[i] == 0:
			continue
		var q := sys.pos[i]
		var d := Vector2(q.x - pp.x, q.z - pp.z).length()
		var period := 15
		for band in BANDS:
			if d <= float(band[0]):
				period = int(band[1])
				break
		var last_tick := int(ps.sent_tick.get(i, -1000))
		if tick - last_tick < period:
			continue
		var e := _quant(i)
		var key: int = e[0]
		var keyframe := now - float(ps.sent_t.get(i, -10.0)) >= KEYFRAME
		if not keyframe and int(ps.sent_key.get(i, -1)) == key:
			continue
		var ck := int(e[2]) * 256 + int(e[3])
		var add := ENTRY_SIZE + (0 if by_chunk.has(ck) else 3)
		if size + add > MAX_PACKET:
			break
		size += add
		# packed arrays held in a Dictionary are values: read, append, write back
		var buf: PackedByteArray = by_chunk.get(ck, PackedByteArray())
		buf.append_array(e[1])
		by_chunk[ck] = buf
		counts[ck] = int(counts.get(ck, 0)) + 1
		ps.sent_key[i] = key
		ps.sent_tick[i] = tick
		ps.sent_t[i] = now
		n += 1
	if n == 0:
		return
	var out := PackedByteArray()
	out.resize(6)
	out[0] = PKT_ZSNAP
	out.encode_u32(1, tick & 0xFFFFFFFF)
	out[5] = by_chunk.size()
	for ck in by_chunk:
		var c := int(ck)
		var cnt := int(counts[ck])
		var hdr := PackedByteArray([c / 256, c % 256, cnt])
		out.append_array(hdr)
		out.append_array(by_chunk[ck])
	stats["snap_packets"] = int(stats["snap_packets"]) + 1
	stats["entries"] = int(stats["entries"]) + n
	_deliver(ps, out, false)


## Peers currently following slot `i` (tests).
func peers_knowing(i: int) -> Array:
	var out: Array = []
	for peer in _peers:
		if (_peers[peer] as PeerState).known.has(i):
			out.append(peer)
	return out


func known_count(peer: int) -> int:
	var ps: PeerState = _peers.get(peer)
	return ps.known.size() if ps != null else 0


# ------------------------------------------------------------------ decoding (client side, pure)
## Decodes a ZSNAP packet into entries {id, pos, yaw, state, flags} (the tick is returned under "tick").
static func decode_snapshot(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 6 or bytes[0] != PKT_ZSNAP:
		return {}
	var tick := bytes.decode_u32(1)
	var nch := bytes[5]
	var off := 6
	var out: Array = []
	for c in nch:
		if off + 3 > bytes.size():
			break
		var cx := bytes[off]
		var cz := bytes[off + 1]
		var cnt := bytes[off + 2]
		off += 3
		var o := WorldConst.chunk_origin(cx, cz)
		for k in cnt:
			if off + ENTRY_SIZE > bytes.size():
				break
			var id := bytes.decode_u16(off)
			var qx := bytes[off + 2] | ((bytes[off + 3] & 0x0F) << 8)
			var qz := ((bytes[off + 3] >> 4) & 0x0F) | (bytes[off + 4] << 4)
			var y := float(bytes.decode_s16(off + 5)) / 100.0
			var yaw := float(bytes[off + 7]) / 256.0 * TAU
			var st := bytes[off + 8]
			out.append({"id": id, "pos": Vector3(o.x + float(qx) / Q_XZ * WorldConst.CHUNK_SIZE, y, o.y + float(qz) / Q_XZ * WorldConst.CHUNK_SIZE),
				"yaw": wrapf(yaw, -PI, PI), "state": st & 0x1F, "flags": (st >> 5) & 7})
			off += ENTRY_SIZE
	return {"tick": tick, "entries": out}


## Decodes a ZREL packet into records (dictionaries with "r" = REC_*).
static func decode_rel(bytes: PackedByteArray) -> Array:
	var out: Array = []
	if bytes.size() < 2 or bytes[0] != PKT_ZREL:
		return out
	var b := StreamPeerBuffer.new()
	b.data_array = bytes
	b.seek(2)
	var n := bytes[1]
	for k in n:
		if b.get_position() >= bytes.size():
			break
		var r := b.get_u8()
		match r:
			REC_ENTER:
				var id := b.get_u16()
				var kd := b.get_u8()
				var vr := b.get_u8()
				var p := Vector3(b.get_float(), b.get_float(), b.get_float())
				var y := float(b.get_u8()) / 256.0 * TAU
				var hpp := b.get_u8()
				var st := b.get_u8()
				out.append({"r": REC_ENTER, "id": id, "kind": kd, "variant": vr, "pos": p, "yaw": wrapf(y, -PI, PI), "hp": hpp,
					"state": st & 0x1F, "flags": (st >> 5) & 7})
			REC_LEAVE:
				out.append({"r": REC_LEAVE, "id": b.get_u16()})
			REC_EVENT:
				out.append({"r": REC_EVENT, "id": b.get_u16(), "ev": b.get_u8(), "arg": b.get_u8(), "dir": float(b.get_u8()) / 255.0 * TAU})
			REC_FX:
				out.append({"r": REC_FX, "fx": b.get_u8(), "pos": Vector3(b.get_float(), b.get_float(), b.get_float()), "a": b.get_u8(), "b": b.get_u8()})
			_:
				break
	return out
