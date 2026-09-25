class_name WorldConst
## World grid constants (ARQ v2 §8.1, M2 subset). The open world of M3 is WORLD_CHUNKS × WORLD_CHUNKS chunks of
## CHUNK_SIZE m; the slice clearing (±BOUNDS m around the origin) sits at the centre of chunk CENTER_CHUNK, so
## world (0, 0) is the centre of that chunk and the clearing spans chunks 23–25 on both axes (PLAN M2).

const CHUNK_SIZE := 64.0
const WORLD_CHUNKS := 48
const CENTER_CHUNK := 24


## Chunk index along one axis for a world coordinate.
static func chunk_of(v: float) -> int:
	return int(floor((v + CHUNK_SIZE * 0.5) / CHUNK_SIZE)) + CENTER_CHUNK


## Packed chunk key (cx in the high 16 bits, cz in the low 16 bits) for a world position.
static func key_of(pos: Vector3) -> int:
	return key(chunk_of(pos.x), chunk_of(pos.z))


static func key(cx: int, cz: int) -> int:
	return ((cx & 0xFFFF) << 16) | (cz & 0xFFFF)


static func key_cx(k: int) -> int:
	return (k >> 16) & 0xFFFF


static func key_cz(k: int) -> int:
	return k & 0xFFFF


## World-space centre of a chunk.
static func chunk_center(cx: int, cz: int) -> Vector3:
	return Vector3(float(cx - CENTER_CHUNK) * CHUNK_SIZE, 0.0, float(cz - CENTER_CHUNK) * CHUNK_SIZE)
