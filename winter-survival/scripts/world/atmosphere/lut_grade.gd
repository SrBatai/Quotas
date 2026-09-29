class_name LutGrade
extends RefCounted
## G2b colour grading (PLAN v3.8.2 G2b, doc 08 §3.7): the 32³ LUTs of tools/make_luts.py blended on the CPU into the
## Environment's `adjustment_color_correction` (one Texture3D: works in Forward+, Compatibility and the Web build;
## the tonemapper samples it for free). Client only; Atmosphere owns one and feeds it the weights of the moment.
##
## The blend, per 32 × 32 slice (blue = slice): a fresh opaque black RGBAF slice, then for every weighted LUT a copy
## of its RGBAF slice (alpha 128/255 from the file) pre-scaled with Image.adjust_bcs and Image.blend_rect onto it.
## blend_rect keeps the destination opaque and computes dst·(1 − s) + src·s, so after N sources the slice is
## Σ s(1 − s)^(N−i) · src_i; the pre-scale w_i / (s(1 − s)^(N−i)) makes it Σ w_i · LUT_i exactly (float, no clamp);
## the slice is then converted to RGBA8. All native Image work: ≈ 0.05 ms per slice for 2 LUTs, 0.075 for 3.
## The 32 slices of an update are cut in quarter-slice units (20–35 µs) spread over frames within `budget_usec`
## (0.075 ms; the first unit of a frame always runs, no unit starts that the running average says would overrun) into
## a back buffer and uploaded at once (Texture3D.update, ~2 µs), so the grade never shows two weights at a time.
## At rest (weights within EPS of what is shown) nothing runs; a single LUT at weight 1 is its own texture (no blend).

const NAMES: Array[StringName] = [&"dia_claro", &"nublado", &"ventisca", &"atardecer", &"noche", &"noche_ciudad",
	&"apagon", &"calor"]
const DIR := "res://assets/luts/"
const SIZE := 32
const MAX_SOURCES := 3
## Weight change that starts a new update (also the smallest weight kept).
const EPS := 1.0 / 128.0
const MIN_WEIGHT := 0.02
## Work unit: a quarter slice (32 × 8 texels: ~20 µs for 2 LUTs, ~35 µs for 3): a frame runs as many as fit the budget.
const PARTS := 4
const ROWS := SIZE / PARTS
const UNITS := SIZE * PARTS
const PART_RECT := Rect2i(0, 0, SIZE, ROWS)

## CPU time allowed per frame for slices (the frame's first slice always runs).
var budget_usec: int = 75
## The texture to put in Environment.adjustment_color_correction (changes when a pure LUT is shown).
var texture: Texture3D
## Stats (tests / bench): last frame's step cost, the worst step, full updates finished, slices blended.
var last_step_usec: int = 0
var max_step_usec: int = 0
var updates_done: int = 0
var slices_done: int = 0
var busy_frames: int = 0

var _strips: Dictionary = {}       # id -> Image (the 1024 × 32 RGBA8 strip as imported)
var _src_f: Dictionary = {}        # id -> Array (32 RGBAF slices, alpha 128/255, converted lazily slice by slice)
var _pure: Dictionary = {}         # id -> ImageTexture3D (the LUT on its own)
var _blend_tex: ImageTexture3D
var _back: Array[Image] = []
var _shown_slices: Array[Image] = []   # what the texture holds (CPU copy: lookup() works headless too)
var _shown := PackedFloat32Array()     # weights on screen
var _target := PackedFloat32Array()    # weights wanted
var _job_ids := PackedInt32Array()     # the running update: sources, their pre-scales, next slice
var _job_scales := PackedFloat32Array()
var _job_w := PackedFloat32Array()
var _job_z: int = -1              # next work unit (slice z = unit / PARTS), -1 = idle
var _cur: Image                    # the float slice being blended
var _unit_ema: float = 30.0        # µs per unit (budget control)
var _alpha: float = 128.0 / 255.0
var _ok: bool = false


func _init() -> void:
	_shown.resize(NAMES.size())
	_target.resize(NAMES.size())
	_shown.fill(-1.0)
	_target.fill(0.0)
	_ok = ResourceLoader.exists(DIR + String(NAMES[0]) + ".png")


func available() -> bool:
	return _ok


static func index_of(name: StringName) -> int:
	return NAMES.find(name)


## The weights wanted now (any size ≤ NAMES; normalised here; the MAX_SOURCES largest are kept).
func set_target(weights: PackedFloat32Array) -> void:
	var w := PackedFloat32Array()
	w.resize(NAMES.size())
	for i in mini(weights.size(), NAMES.size()):
		w[i] = maxf(weights[i], 0.0)
	# keep the MAX_SOURCES largest above MIN_WEIGHT, renormalise
	var order: Array = []
	for i in w.size():
		if w[i] >= MIN_WEIGHT:
			order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return w[a] > w[b] or (w[a] == w[b] and a < b))
	var keep := {}
	for k in mini(order.size(), MAX_SOURCES):
		keep[order[k]] = true
	var total := 0.0
	for i in w.size():
		if not keep.has(i):
			w[i] = 0.0
		total += w[i]
	if total <= 0.0:
		w[0] = 1.0
		total = 1.0
	for i in w.size():
		w[i] /= total
	_target = w


func target() -> PackedFloat32Array:
	return _target


func shown() -> PackedFloat32Array:
	return _shown


## True while the texture does not show the target yet (an update pending or running).
func is_busy() -> bool:
	return _job_z >= 0 or _differs(_target, _shown)


## Per frame (Atmosphere): advances the running update within the budget, or starts one when the target moved.
## Returns true when the texture changed this frame.
func step() -> bool:
	last_step_usec = 0
	if not _ok:
		return false
	if _job_z < 0:
		if not _differs(_target, _shown):
			return false   # at rest: nothing at all
		if _start_job():
			return true    # a pure LUT: swapped, no blend
	var t0 := Time.get_ticks_usec()
	var changed := false
	busy_frames += 1
	if _job_z >= UNITS:
		# the upload gets a frame of its own (32 slices to the texture)
		_finish_job()
		last_step_usec = Time.get_ticks_usec() - t0
		max_step_usec = maxi(max_step_usec, last_step_usec)
		return true
	while _job_z < UNITS:
		var u0 := Time.get_ticks_usec()
		_blend_unit(_job_z)
		_job_z += 1
		var now := Time.get_ticks_usec()
		_unit_ema = lerpf(_unit_ema, float(now - u0), 0.2)
		# stop before a unit that would overrun the budget (the first unit of a frame always runs)
		if float(now - t0) + _unit_ema > float(budget_usec):
			break
	last_step_usec = Time.get_ticks_usec() - t0
	max_step_usec = maxi(max_step_usec, last_step_usec)
	return changed


## Tests / screenshots: finish everything now (no budget).
func flush() -> void:
	if not _ok:
		return
	for guard in 4:
		if _job_z < 0 and not _differs(_target, _shown):
			return
		if _job_z < 0 and _start_job():
			continue
		while _job_z < UNITS:
			_blend_unit(_job_z)
			_job_z += 1
		_finish_job()


## Colour the current texture maps `c` (display sRGB) to, sampled like the tonemapper (trilinear, texel i at
## (i + 0.5) / 32): tests compare it with a CPU reference.
func lookup(c: Color) -> Color:
	if _shown_slices.size() != SIZE:
		return c
	return sample(_shown_slices, c)


static func sample(imgs: Array, c: Color) -> Color:
	var p := Vector3(c.r, c.g, c.b) * float(SIZE) - Vector3(0.5, 0.5, 0.5)
	p = p.clamp(Vector3.ZERO, Vector3.ONE * float(SIZE - 1))
	var i0 := Vector3i(int(floor(p.x)), int(floor(p.y)), int(floor(p.z)))
	var i1 := Vector3i(mini(i0.x + 1, SIZE - 1), mini(i0.y + 1, SIZE - 1), mini(i0.z + 1, SIZE - 1))
	var f := p - Vector3(i0)
	var c00 := (imgs[i0.z] as Image).get_pixel(i0.x, i0.y).lerp((imgs[i0.z] as Image).get_pixel(i1.x, i0.y), f.x)
	var c01 := (imgs[i0.z] as Image).get_pixel(i0.x, i1.y).lerp((imgs[i0.z] as Image).get_pixel(i1.x, i1.y), f.x)
	var c10 := (imgs[i1.z] as Image).get_pixel(i0.x, i0.y).lerp((imgs[i1.z] as Image).get_pixel(i1.x, i0.y), f.x)
	var c11 := (imgs[i1.z] as Image).get_pixel(i0.x, i1.y).lerp((imgs[i1.z] as Image).get_pixel(i1.x, i1.y), f.x)
	var out := c00.lerp(c01, f.y).lerp(c10.lerp(c11, f.y), f.z)
	out.a = 1.0
	return out


## The RGBA8 slices of one LUT as the file has them (tests' reference).
func slices_of(id: int) -> Array[Image]:
	var out: Array[Image] = []
	var strip := _load_strip(id)
	if strip == null:
		return out
	for z in SIZE:
		out.append(strip.get_region(Rect2i(z * SIZE, 0, SIZE, SIZE)))
	return out


# ------------------------------------------------------------------ internals
func _differs(a: PackedFloat32Array, b: PackedFloat32Array) -> bool:
	for i in a.size():
		if absf(a[i] - b[i]) > EPS:
			return true
	return false


## Starts an update toward the target. A single LUT is swapped in at once (returns true: done).
func _start_job() -> bool:
	var ids := PackedInt32Array()
	var ws := PackedFloat32Array()
	for i in _target.size():
		if _target[i] > 0.0:
			ids.append(i)
			ws.append(_target[i])
	if ids.size() == 1:
		texture = _pure_texture(ids[0])
		_shown_slices = slices_of(ids[0])
		_shown = _target.duplicate()
		_job_z = -1
		updates_done += 1
		return true
	var n := ids.size()
	_job_ids = ids
	_job_w = _target.duplicate()
	_job_scales.resize(n)
	for i in n:
		# source i (0-based) is blended i-th of n: its share after the later blends is s(1 − s)^(n − 1 − i)
		_job_scales[i] = ws[i] / (_alpha * pow(1.0 - _alpha, float(n - 1 - i)))
	if _back.size() != SIZE:
		_back.resize(SIZE)
	_job_z = 0
	return false


func _blend_unit(u: int) -> void:
	var z := u / PARTS
	var q := u % PARTS
	if q == 0:
		_cur = Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBAF)
		_cur.fill(Color(0.0, 0.0, 0.0, 1.0))
	for i in _job_ids.size():
		var s := Image.new()
		s.copy_from(_src_part(_job_ids[i], z, q))
		s.adjust_bcs(_job_scales[i], 1.0, 1.0)
		_cur.blend_rect(s, PART_RECT, Vector2i(0, q * ROWS))
	if q == PARTS - 1:
		_cur.convert(Image.FORMAT_RGBA8)
		_back[z] = _cur
		slices_done += 1


func _finish_job() -> void:
	if _blend_tex == null:
		_blend_tex = ImageTexture3D.new()
		_blend_tex.create(Image.FORMAT_RGBA8, SIZE, SIZE, SIZE, false, _back)
	else:
		_blend_tex.update(_back)
	texture = _blend_tex
	_shown_slices = _back.duplicate()
	_shown = _job_w
	_job_z = -1
	updates_done += 1


## Loads every LUT strip now (world setup, outside the frame budget); the float slices follow lazily.
func preload_all() -> void:
	for id in NAMES.size():
		_load_strip(id)


func _load_strip(id: int) -> Image:
	if _strips.has(id):
		return _strips[id]
	var path := DIR + String(NAMES[id]) + ".png"
	var res: Resource = load(path) if ResourceLoader.exists(path) else null
	var img: Image = res as Image
	if img == null and res is Texture2D:
		img = (res as Texture2D).get_image()
	if img == null or img.get_width() != SIZE * SIZE or img.get_height() != SIZE:
		push_warning("LutGrade: bad LUT %s" % path)
		return null
	if img.get_format() != Image.FORMAT_RGBA8:
		img = img.duplicate() as Image
		img.convert(Image.FORMAT_RGBA8)
	_strips[id] = img
	return img


func _pure_texture(id: int) -> ImageTexture3D:
	if _pure.has(id):
		return _pure[id]
	var tex := ImageTexture3D.new()
	var slices := slices_of(id)
	if slices.size() == SIZE:
		tex.create(Image.FORMAT_RGBA8, SIZE, SIZE, SIZE, false, slices)
	_pure[id] = tex
	return tex


## One quarter slice of a LUT as RGBAF (converted on first use, inside the frame budget: a few µs).
func _src_part(id: int, z: int, q: int) -> Image:
	var arr: Array = _src_f.get(id, [])
	if arr.size() != UNITS:
		arr = []
		arr.resize(UNITS)
		_src_f[id] = arr
	var img: Image = arr[z * PARTS + q]
	if img != null:
		return img
	var strip := _load_strip(id)
	if strip != null:
		img = strip.get_region(Rect2i(z * SIZE, q * ROWS, SIZE, ROWS))
		img.convert(Image.FORMAT_RGBAF)
		_alpha = img.get_pixel(0, 0).a
	else:
		# a broken file: blend as neutral grey rather than crash
		img = Image.create_empty(SIZE, ROWS, false, Image.FORMAT_RGBAF)
		img.fill(Color(0.5, 0.5, 0.5, _alpha))
	arr[z * PARTS + q] = img
	return img
