class_name MapFog
extends Node
## Fog of war of the paper map (docs/research/10_hud_ux.md appendix §6.11): a bitmap of the 3 × 3 km world in
## cells of 8 m (the macro map grid, 384 × 384), revealed within 40 m of the local player on foot (120 m from
## heights more than 15 m above the terrain around), sampled every 0.5 s. Client side, kept per world seed in
## user://hud_map_fog.cfg (the server-side, group-shared bitmap of §6.11 is deferred: `shared_map`).

const PATH := "user://hud_map_fog.cfg"
const SIZE := MacroMap.SIZE
const CELL := MacroMap.PX
const HALF := float(MacroMap.SIZE) * MacroMap.PX * 0.5
## W1: the macro grid starts at WorldConst.MACRO_ORIGIN (−1536 m) and spans SPAN m (the 6 km world is not centred
## on the origin any more: cells are counted from ORIGIN, not from −HALF).
const ORIGIN := WorldConst.MACRO_ORIGIN
const SPAN := float(MacroMap.SIZE) * MacroMap.PX
const REVEAL := 40.0
const REVEAL_HIGH := 120.0
const PERIOD := 0.5

var bits := PackedByteArray()
var image: Image
var texture: ImageTexture
var revealed: int = 0
var dirty: bool = false
var _acc: float = 0.0
var _save_acc: float = 0.0
var _seed_key: String = ""


func _ready() -> void:
	bits.resize(SIZE * SIZE)
	image = Image.create_empty(SIZE, SIZE, false, Image.FORMAT_L8)
	texture = ImageTexture.create_from_image(image)


func _process(delta: float) -> void:
	_acc += delta
	_save_acc += delta
	if _acc < PERIOD:
		return
	_acc = 0.0
	_check_seed()
	var p := GameFlow.local_player() as Node3D
	if p != null and p.is_inside_tree():
		var r := REVEAL
		var w := World.instance
		if w != null and w.is_configured and p.global_position.y - w.get_height(p.global_position.x, p.global_position.z) > 15.0:
			r = REVEAL_HIGH
		reveal(p.global_position.x, p.global_position.z, r)
	if dirty:
		dirty = false
		texture.update(image)
	if _save_acc > 10.0:
		_save_acc = 0.0
		save()


## World position → cell (x, y).
static func cell_of(x: float, z: float) -> Vector2i:
	return Vector2i(int(floor((x - ORIGIN) / CELL)), int(floor((z - ORIGIN) / CELL)))


func reveal(x: float, z: float, radius: float) -> void:
	var c := cell_of(x, z)
	var rc := int(ceil(radius / CELL))
	for j in range(c.y - rc, c.y + rc + 1):
		if j < 0 or j >= SIZE:
			continue
		for i in range(c.x - rc, c.x + rc + 1):
			if i < 0 or i >= SIZE:
				continue
			var d := Vector2(float(i - c.x), float(j - c.y)).length() * CELL
			if d > radius:
				continue
			var k := j * SIZE + i
			# soft edge: full inside, half on the rim (the charcoal edge of the map)
			var v := 255 if d < radius - CELL else 150
			if bits[k] < v:
				if bits[k] == 0:
					revealed += 1
				bits[k] = v
				image.set_pixel(i, j, Color(float(v) / 255.0, 0, 0))
				dirty = true


func is_revealed(x: float, z: float) -> bool:
	var c := cell_of(x, z)
	if c.x < 0 or c.y < 0 or c.x >= SIZE or c.y >= SIZE:
		return false
	return bits[c.y * SIZE + c.x] > 0


func explored_fraction() -> float:
	return float(revealed) / float(SIZE * SIZE)


func _check_seed() -> void:
	var key := "seed_%d" % (WorldState.instance.world_seed if WorldState.instance != null else 0)
	if key == _seed_key:
		return
	if _seed_key != "":
		save()
	_seed_key = key
	_load()


func _load() -> void:
	bits.fill(0)
	revealed = 0
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK and cfg.has_section_key(_seed_key, "bits"):
		var packed: PackedByteArray = Marshalls.base64_to_raw(str(cfg.get_value(_seed_key, "bits")))
		var raw := packed.decompress(SIZE * SIZE, FileAccess.COMPRESSION_DEFLATE)
		if raw.size() == SIZE * SIZE:
			bits = raw
	for k in bits.size():
		if bits[k] > 0:
			revealed += 1
	image = Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_L8, bits.duplicate())
	texture.set_image(image)


func save() -> void:
	if _seed_key == "":
		return
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value(_seed_key, "bits", Marshalls.raw_to_base64(bits.compress(FileAccess.COMPRESSION_DEFLATE)))
	cfg.save(PATH)


## Tests: put back a bitmap taken with `bits.duplicate()` (the checks run on a blank map, then restore it).
func restore(b: PackedByteArray) -> void:
	if b.size() != SIZE * SIZE:
		return
	bits = b
	revealed = 0
	for k in bits.size():
		if bits[k] > 0:
			revealed += 1
	image = Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_L8, bits.duplicate())
	texture.set_image(image)


## Tests: forget everything.
func clear_all() -> void:
	bits.fill(0)
	revealed = 0
	image.fill(Color(0, 0, 0))
	texture.update(image)
