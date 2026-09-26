class_name LookdevTrailMap
extends RefCounted
## Footprint trail map (look-dev G1). R = depression, G = raised rim, over `rect` (world XZ metres).
## Two back-ends with the same stamp(pos, yaw, left) interface:
##  * "cpu": Image + ImageTexture.update() (works everywhere, ~0.1 ms per stamp at 1024²; the upload is the cost).
##  * "drawable": DrawableTexture2D.blit_rect with the additive trail_stamp shader (Godot 4.7, GPU, no readback).
## The terrain shader only needs a Texture2D, so the game can pick the back-end per renderer.

var rect := Rect2(-24.0, -20.0, 48.0, 48.0)
var resolution: int = 1024
var backend: String = "cpu"
var texture: Texture2D
var _image: Image
var _stamp_textures: Array[Texture2D] = []
var _stamp_mat: Material
var _dirty: bool = false


func setup(preferred: String = "cpu") -> void:
	backend = preferred
	if backend == "drawable" and ClassDB.class_exists("DrawableTexture2D"):
		var dt = ClassDB.instantiate("DrawableTexture2D")
		# DrawableFormat RGBA8 = 0 (4.7). Black = no trail.
		dt.setup(resolution, resolution, 0, Color(0, 0, 0, 1), false)
		texture = dt
		# blit_rect has no rotation: 16 pre-rotated stamps (22.5 deg steps) rendered once on the CPU, blended ADD
		# through the official BlitMaterial (falls back to a ShaderMaterial with a `texture_blit` shader).
		for i in 16:
			_stamp_textures.append(_make_stamp_image(64, float(i) * TAU / 16.0))
		if ClassDB.class_exists("BlitMaterial"):
			_stamp_mat = ClassDB.instantiate("BlitMaterial")
			_stamp_mat.set("blend_mode", ClassDB.class_get_integer_constant("BlitMaterial", "BLEND_MODE_ADD"))
		else:
			var sm := ShaderMaterial.new()
			sm.shader = load("res://shaders/trail_stamp_blit.gdshader")
			_stamp_mat = sm
	else:
		backend = "cpu"
		_image = Image.create(resolution, resolution, false, Image.FORMAT_RGBA8)
		_image.fill(Color(0, 0, 0, 1))
		texture = ImageTexture.create_from_image(_image)


## Foot profile: R = depression (1 inside), G = raised rim ring. `yaw` rotates the foot (forward = +y of the image).
static func _foot(fx: float, fy: float, length: float, width: float) -> Vector2:
	var w := width * 0.5 * (1.0 + 0.10 * fy / (length * 0.5))
	var rr := Vector2(fx / w, fy / (length * 0.5)).length()
	var inner := 1.0 - smoothstep(0.62, 0.92, rr)
	var ring := smoothstep(0.70, 0.95, rr) * (1.0 - smoothstep(0.98, 1.22, rr))
	return Vector2(inner, ring)


func _make_stamp_image(size: int, yaw: float) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var cs := cos(yaw)
	var sn := sin(yaw)
	var length := 1.0
	var width := 0.62
	for py in size:
		for px in size:
			var d := (Vector2(px, py) + Vector2(0.5, 0.5)) / float(size) * 2.6 - Vector2(1.3, 1.3)
			var fx := d.x * cs - d.y * sn
			var fy := d.x * sn + d.y * cs
			var f := _foot(fx, fy, length, width)
			img.set_pixel(px, py, Color(f.x, f.y * (1.0 - f.x), 0.0, 1.0))
	return ImageTexture.create_from_image(img)


func _to_px(p: Vector2) -> Vector2:
	return (p - rect.position) / rect.size * float(resolution)


## One footprint. `pos` world XZ of the foot centre, `yaw` walking direction (radians, +Z forward = yaw 0),
## `length`/`width` in metres. Repeated stamps accumulate (deeper trench, taller rims).
func stamp(pos: Vector2, yaw: float, length: float = 0.42, width: float = 0.26, strength: float = 1.0) -> void:
	if backend == "drawable":
		var c := _to_px(pos)
		var half := Vector2(length, length) / rect.size * float(resolution) * 0.5 * 1.3
		var idx := int(round(fposmod(yaw, TAU) / TAU * 16.0)) % 16
		texture.blit_rect(Rect2i(Vector2i(c - half), Vector2i(half * 2.0)), _stamp_textures[idx], Color(strength, strength, 1.0, 1.0), 0, _stamp_mat)
		return
	var px_per_m := float(resolution) / rect.size.x
	var c := _to_px(pos)
	var r := length * 0.5 * px_per_m + 2.0
	var x0 := maxi(int(c.x - r), 0)
	var x1 := mini(int(c.x + r) + 1, resolution - 1)
	var y0 := maxi(int(c.y - r), 0)
	var y1 := mini(int(c.y + r) + 1, resolution - 1)
	var cs := cos(yaw)
	var sn := sin(yaw)
	for py in range(y0, y1 + 1):
		for px in range(x0, x1 + 1):
			var d := (Vector2(px, py) + Vector2(0.5, 0.5) - c) / px_per_m  # metres
			# rotate into foot space: foot forward = walking direction
			var fx := d.x * cs - d.y * sn
			var fy := d.x * sn + d.y * cs
			var w := width * 0.5 * (1.0 + 0.10 * fy / (length * 0.5))
			var rr := Vector2(fx / w, fy / (length * 0.5)).length()
			var inner := 1.0 - smoothstep(0.62, 0.92, rr)
			var ring := smoothstep(0.70, 0.95, rr) * (1.0 - smoothstep(0.98, 1.22, rr))
			if inner <= 0.0 and ring <= 0.0:
				continue
			var old := _image.get_pixel(px, py)
			var nr := minf(old.r + inner * strength, 1.0)
			var ng := minf(maxf(old.g, ring * strength * (1.0 - nr)), 1.0)
			_image.set_pixel(px, py, Color(nr, ng, 0.0, 1.0))
	_dirty = true


## Walks a polyline dropping alternating left/right prints every `step` metres.
func stamp_path(points: PackedVector2Array, step: float = 0.62, stride_side: float = 0.13) -> void:
	var left := true
	var acc := 0.0
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var seg := b - a
		var len := seg.length()
		var dir := seg / maxf(len, 0.0001)
		var yaw := atan2(dir.x, dir.y)
		var t := 0.0
		while t < len:
			if acc <= 0.0:
				var side := Vector2(dir.y, -dir.x) * (stride_side if left else -stride_side)
				stamp(a + dir * t + side, yaw)
				left = not left
				acc = step
			var adv := minf(acc, len - t)
			t += adv
			acc -= adv
			if adv <= 0.0:
				break


func flush() -> void:
	if backend == "cpu" and _dirty:
		(texture as ImageTexture).update(_image)
		_dirty = false
