class_name RemoteInterp
extends RefCounted
## Snapshot interpolation for remote players (ARQ v2 §6.7): buffer of server states stamped on arrival,
## rendered NET_INTERP_DELAY (100 ms) in the past, extrapolated at most NET_EXTRAPOLATE_MAX.

var _buf: Array[Dictionary] = []   # {"t": float, "pos": Vector3, "yaw": float, "aim": Vector3}
var last_velocity: Vector3 = Vector3.ZERO


func push(pos: Vector3, yaw: float, aim: Vector3) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	if not _buf.is_empty() and _buf[-1]["pos"] == pos and absf(float(_buf[-1]["yaw"]) - yaw) < 0.0001:
		_buf[-1]["t"] = t   # identical state: only refresh the time stamp (server idle)
		return
	_buf.append({"t": t, "pos": pos, "yaw": yaw, "aim": aim})
	while _buf.size() > 8:
		_buf.pop_front()


func has_data() -> bool:
	return not _buf.is_empty()


## Returns {"pos", "yaw", "aim"} for the render time, or an empty dictionary when nothing was received yet.
func sample() -> Dictionary:
	if _buf.is_empty():
		return {}
	var t := Time.get_ticks_msec() / 1000.0 - Balance.NET_INTERP_DELAY
	if _buf.size() == 1 or t <= float(_buf[0]["t"]):
		var s := _buf[0]
		return {"pos": s["pos"], "yaw": s["yaw"], "aim": s["aim"]}
	for i in range(_buf.size() - 1):
		var a := _buf[i]
		var b := _buf[i + 1]
		if t >= float(a["t"]) and t <= float(b["t"]):
			var span := float(b["t"]) - float(a["t"])
			var f := 0.0 if span <= 0.0001 else (t - float(a["t"])) / span
			last_velocity = ((b["pos"] as Vector3) - (a["pos"] as Vector3)) / maxf(span, 0.001)
			return {"pos": (a["pos"] as Vector3).lerp(b["pos"], f), "yaw": lerp_angle(float(a["yaw"]), float(b["yaw"]), f),
				"aim": (a["aim"] as Vector3).lerp(b["aim"], f)}
	# newer than the last snapshot: extrapolate a little, then hold
	var last := _buf[-1]
	var prev := _buf[-2]
	var dt := float(last["t"]) - float(prev["t"])
	var vel := Vector3.ZERO
	if dt > 0.0001:
		vel = ((last["pos"] as Vector3) - (prev["pos"] as Vector3)) / dt
	var ahead := clampf(t - float(last["t"]), 0.0, Balance.NET_EXTRAPOLATE_MAX)
	last_velocity = vel if ahead < Balance.NET_EXTRAPOLATE_MAX else Vector3.ZERO
	return {"pos": (last["pos"] as Vector3) + vel * ahead, "yaw": last["yaw"], "aim": last["aim"]}
