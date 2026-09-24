class_name Packets
## Custom binary packets (ARQ v2 §6.3): input commands and the owner state ack. StreamPeerBuffer, no Variants.

const CMD_SIZE := 18
## Raw packet types (SceneMultiplayer.send_bytes, first byte).
const PKT_STATE := 1
const STATE_SIZE := 1 + 4 + 12 + 6

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


## Owner state ack (raw packet, no Variant headers): u8 PKT_STATE | u32 ack_seq | 3 × f32 pos | 3 × i16 vel cm/s (23 B).
static func pack_state(ack: int, pos: Vector3, vel: Vector3) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u8(PKT_STATE)
	b.put_u32(ack)
	b.put_float(pos.x)
	b.put_float(pos.y)
	b.put_float(pos.z)
	b.put_16(clampi(int(round(vel.x * 100.0)), -32767, 32767))
	b.put_16(clampi(int(round(vel.y * 100.0)), -32767, 32767))
	b.put_16(clampi(int(round(vel.z * 100.0)), -32767, 32767))
	return b.data_array


static func unpack_state(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < STATE_SIZE or bytes[0] != PKT_STATE:
		return {}
	var b := StreamPeerBuffer.new()
	b.data_array = bytes
	b.get_u8()
	var ack := b.get_u32()
	var pos := Vector3(b.get_float(), b.get_float(), b.get_float())
	var vel := Vector3(float(b.get_16()), float(b.get_16()), float(b.get_16())) / 100.0
	return {"ack": ack, "pos": pos, "vel": vel}


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
