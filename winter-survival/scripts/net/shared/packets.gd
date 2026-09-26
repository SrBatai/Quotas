class_name Packets
## Custom binary packets (ARQ v2 §6.3): input commands and the owner state ack. StreamPeerBuffer, no Variants.

const CMD_SIZE := 18
## Raw packet types (SceneMultiplayer.send_bytes, first byte).
const PKT_POSES := 2
const POSES_HEADER := 1 + 4 + 6 + 10 + 1
const POSE_SIZE := 4 + 8

# button bits (u16)
const BTN_RUN := 1
const BTN_CROUCH := 2
const BTN_ATTACK := 4
const BTN_INTERACT := 32


## Packs up to 255 commands (oldest first, newest last): u8 n | n × { u32 seq | i8 mx | i8 my | i16 aim_yaw |
## 3 × i16 aim_rel_cm | u16 buttons | u8 slot | u8 flags }. `aim_rel` is relative to cmd["pos"], the predicted
## position when the command was generated.
static func pack_cmds(cmds: Array) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u8(mini(cmds.size(), 255))
	for c in cmds:
		var cmd: Dictionary = c
		var move: Vector2 = (cmd.get("move", Vector2.ZERO) as Vector2).limit_length(1.0)
		var pos: Vector3 = cmd.get("pos", Vector3.ZERO)
		var rel: Vector3 = ((cmd.get("aim", pos) as Vector3) - pos) * 100.0
		b.put_u32(int(cmd.get("seq", 0)))
		b.put_8(int(round(move.x * 127.0)))
		b.put_8(int(round(move.y * 127.0)))
		b.put_16(int(round(clampf(float(cmd.get("aim_yaw", 0.0)) / PI, -1.0, 1.0) * 32767.0)))
		b.put_16(clampi(int(rel.x), -32767, 32767))
		b.put_16(clampi(int(rel.y), -32767, 32767))
		b.put_16(clampi(int(rel.z), -32767, 32767))
		b.put_u16(int(cmd.get("btn", 0)) & 0xFFFF)
		b.put_u8(int(cmd.get("slot", 0)) & 0xFF)
		b.put_u8(int(cmd.get("flags", 0)) & 0xFF)
	return b.data_array


## Unpacks a packet into command dictionaries; `aim` is rebuilt relative to `pos` (the server's own position).
static func unpack_cmds(bytes: PackedByteArray, pos: Vector3) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if bytes.size() < 1:
		return out
	var b := StreamPeerBuffer.new()
	b.data_array = bytes
	var n := b.get_u8()
	if bytes.size() < 1 + n * CMD_SIZE:
		return out
	for i in n:
		var seq := b.get_u32()
		var mv := Vector2(float(b.get_8()) / 127.0, float(b.get_8()) / 127.0)
		var yaw := float(b.get_16()) / 32767.0 * PI
		var rel := Vector3(float(b.get_16()), float(b.get_16()), float(b.get_16())) / 100.0
		var btn := b.get_u16()
		var slot := b.get_u8()
		var flags := b.get_u8()
		out.append({"seq": seq, "move": mv.limit_length(1.0), "aim_yaw": wrapf(yaw, -PI, PI),
			"aim": pos + rel.limit_length(Balance.NET_MAX_AIM_DIST), "btn": btn, "slot": slot, "flags": flags})
	return out


## Player poses, one raw packet per client per tick (replaces a 30 Hz MultiplayerSynchronizer stream per player
## and the separate ack): u8 PKT_POSES | u32 ack_seq (owner's last applied command) | 3 × i16 owner vel cm/s |
## base (i32 x_cm | i16 y_cm | i32 z_cm) | u8 n | n × { u32 peer | 3 × i16 cm relative to base | i16 yaw }.
## M3: the base (the recipient's own position) makes the entries valid anywhere in the 3 km world while keeping
## i16 offsets: interest management only sends players within the recipient's 3 × 3 chunks (< 200 m away).
## = 22 + 12 n bytes (70 B with 4 players).
static func pack_poses(ack: int, vel: Vector3, entries: Array, base: Vector3 = Vector3.ZERO) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u8(PKT_POSES)
	b.put_u32(ack)
	b.put_16(_cm(vel.x))
	b.put_16(_cm(vel.y))
	b.put_16(_cm(vel.z))
	var bx := int(round(base.x * 100.0))
	var by := clampi(int(round(base.y * 100.0)), -32768, 32767)
	var bz := int(round(base.z * 100.0))
	b.put_32(bx)
	b.put_16(by)
	b.put_32(bz)
	var basef := Vector3(float(bx), float(by), float(bz)) / 100.0
	b.put_u8(mini(entries.size(), 255))
	for e in entries:
		var d: Dictionary = e
		var rel: Vector3 = (d["pos"] as Vector3) - basef
		b.put_u32(int(d["peer"]) & 0xFFFFFFFF)
		b.put_16(_cm(rel.x))
		b.put_16(_cm(rel.y))
		b.put_16(_cm(rel.z))
		b.put_16(_yaw16(float(d["yaw"])))
	return b.data_array


static func unpack_poses(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < POSES_HEADER or bytes[0] != PKT_POSES:
		return {}
	var b := StreamPeerBuffer.new()
	b.data_array = bytes
	b.get_u8()
	var ack := b.get_u32()
	var vel := Vector3(float(b.get_16()), float(b.get_16()), float(b.get_16())) / 100.0
	var base := Vector3(float(b.get_32()), float(b.get_16()), float(b.get_32())) / 100.0
	var n := b.get_u8()
	if bytes.size() < POSES_HEADER + n * POSE_SIZE:
		return {}
	var poses := []
	for i in n:
		var peer := b.get_u32()
		var pos := base + Vector3(float(b.get_16()), float(b.get_16()), float(b.get_16())) / 100.0
		poses.append({"peer": peer, "pos": pos, "yaw": float(b.get_16()) / 32767.0 * PI})
	return {"ack": ack, "vel": vel, "poses": poses}


## Actor pose (wolves, deer) in ONE int for the synchronizer (12 B on the wire instead of 24 B for Vector3 +
## float). M3 layout (whole 3 km world): x_cm 19 bits | z_cm 19 bits (±2.6 km) | y_cm 16 bits (±327 m) | yaw 10 bits.
static func pack_pose(pos: Vector3, yaw: float) -> int:
	var x := clampi(int(round(pos.x * 100.0)), -262144, 262143) + 262144
	var z := clampi(int(round(pos.z * 100.0)), -262144, 262143) + 262144
	var y := clampi(int(round(pos.y * 100.0)), -32768, 32767) + 32768
	var a := int(round(fposmod(yaw, TAU) / TAU * 1024.0)) & 1023
	return (x << 45) | (z << 26) | (y << 10) | a


static func unpack_pose(v: int) -> Dictionary:
	var x := ((v >> 45) & 0x7FFFF) - 262144
	var z := ((v >> 26) & 0x7FFFF) - 262144
	var y := ((v >> 10) & 0xFFFF) - 32768
	return {"pos": Vector3(float(x), float(y), float(z)) / 100.0, "yaw": wrapf(float(v & 1023) / 1024.0 * TAU, -PI, PI)}


static func _cm(v: float) -> int:
	return clampi(int(round(v * 100.0)), -32768, 32767)


static func _yaw16(yaw: float) -> int:
	return clampi(int(round(wrapf(yaw, -PI, PI) / PI * 32767.0)), -32768, 32767)


static func _s16(u: int) -> float:
	return float(u - 65536 if u >= 32768 else u)


## Inventory mirror: u16 id_index | u8 count per slot (ids indexed in Items.DB order).
static func pack_slots(slots: Array) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	var ids := Items.DB.keys()
	for s in slots:
		var d: Dictionary = s
		if d.is_empty():
			b.put_u16(0xFFFF)
			b.put_u8(0)
		else:
			b.put_u16(ids.find(d["id"]))
			b.put_u8(clampi(int(d["count"]), 0, 255))
	return b.data_array


static func unpack_slots(bytes: PackedByteArray) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var b := StreamPeerBuffer.new()
	b.data_array = bytes
	var ids := Items.DB.keys()
	var n := bytes.size() / 3
	for i in n:
		var idx := b.get_u16()
		var count := b.get_u8()
		if idx == 0xFFFF or idx >= ids.size() or count <= 0:
			out.append({})
		else:
			out.append({"id": ids[idx], "count": count})
	return out
