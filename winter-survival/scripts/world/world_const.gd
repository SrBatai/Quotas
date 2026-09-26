class_name WorldConst
## World grid constants and deterministic integer hashing (ARQ v2 §8.1, M3). The world is WORLD_CHUNKS ×
## WORLD_CHUNKS chunks of CHUNK_SIZE m. Chunk CENTER_CHUNK is centred on the origin (M2 convention kept so the
## hunter's clearing is exactly chunks 23–25 on both axes): the chunk grid spans −1568 … +1504 m, the macro map
## (data/world/macro_map.png) ±1536 m and the playable wall ±WALL m sits inside both (PLAN C6).
## Everything here is pure (no scene tree, no global RNG): the client and the server compute the same values.

const CHUNK_SIZE := 64.0
const WORLD_CHUNKS := 48
const CENTER_CHUNK := 24
## Terrain samples per chunk edge (1 m spacing, the last row/column is shared with the neighbour).
const SAMPLES := 65
const SAMPLE_STEP := 1.0
## Half size of the macro map (m): 384 px × 8 m.
const HALF := 1536.0
## Hard invisible wall of the playable area (m, both axes). The outer ring up to it is border forest / cliffs.
const WALL := 1450.0
## Where the border ring (dense forest, cliffs, fog) starts (m from the centre, Chebyshev).
const BORDER_START := 1152.0
## Client rings (Chebyshev radius in chunks): 1 = full (3 × 3), 2 = prefetched (5 × 5). Server: hot / warm.
const RING_FULL := 1
const RING_PREFETCH := 2
## Server: a chunk with no player within this many chunks hibernates after HIBERNATE_SECONDS.
const HIBERNATE_RADIUS := 3
const HIBERNATE_SECONDS := 60.0
## Interest management (ARQ v2 §6.5): 3 × 3 chunks around each player, recomputed every INTEREST_PERIOD s.
const INTEREST_RADIUS := 1
const INTEREST_PERIOD := 0.5
## Streaming budget: main-thread instantiation per frame (ARQ v2 §8.5, PLAN M3).
const STREAM_BUDGET_USEC := 2000


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


static func in_grid(cx: int, cz: int) -> bool:
	return cx >= 0 and cz >= 0 and cx < WORLD_CHUNKS and cz < WORLD_CHUNKS


## World-space centre of a chunk.
static func chunk_center(cx: int, cz: int) -> Vector3:
	return Vector3(float(cx - CENTER_CHUNK) * CHUNK_SIZE, 0.0, float(cz - CENTER_CHUNK) * CHUNK_SIZE)


## World-space minimum corner (x, z) of a chunk: its first terrain sample.
static func chunk_origin(cx: int, cz: int) -> Vector2:
	return Vector2(float(cx - CENTER_CHUNK) * CHUNK_SIZE - CHUNK_SIZE * 0.5, float(cz - CENTER_CHUNK) * CHUNK_SIZE - CHUNK_SIZE * 0.5)


## Integer world coordinate (m) of a chunk's first sample (sample (i, j) is at origin_i + i, origin_j + j).
static func chunk_origin_i(c: int) -> int:
	return (c - CENTER_CHUNK) * int(CHUNK_SIZE) - int(CHUNK_SIZE) / 2


static func chunk_rect(cx: int, cz: int) -> Rect2:
	return Rect2(chunk_origin(cx, cz), Vector2(CHUNK_SIZE, CHUNK_SIZE))


## Chebyshev distance between two chunks.
static func ring_dist(ax: int, az: int, bx: int, bz: int) -> int:
	return maxi(absi(ax - bx), absi(az - bz))


## Keys of the (2r+1)² chunks around (cx, cz) that exist in the grid, ordered by ring then row.
static func ring_keys(cx: int, cz: int, r: int) -> Array[int]:
	var out: Array[int] = []
	for d in r + 1:
		for dz in range(-d, d + 1):
			for dx in range(-d, d + 1):
				if maxi(absi(dx), absi(dz)) != d:
					continue
				if in_grid(cx + dx, cz + dz):
					out.append(key(cx + dx, cz + dz))
	return out


static func in_playable(x: float, z: float) -> bool:
	return absf(x) < WALL and absf(z) < WALL


# ------------------------------------------------------------------ deterministic hashing (R3: integers only)
## SplitMix64 finaliser. GDScript ints are int64 with wrapping multiplication; `>>` is arithmetic, so the
## shifted value is masked to make it a logical shift.
static func mix64(v: int) -> int:
	var x := v
	x = (x ^ ((x >> 30) & 0x3FFFFFFFF)) * -4658895280553007687
	x = (x ^ ((x >> 27) & 0x1FFFFFFFFF)) * -7723592293110705685
	return x ^ ((x >> 31) & 0x1FFFFFFFF)


## 63-bit non-negative hash of up to five integers (world seed, generator, cell / chunk coordinates, index).
## Procedural `wid`s use it (ARQ v2 §8.7); player-made objects keep other id spaces.
static func hash64(a: int, b: int = 0, c: int = 0, d: int = 0, e: int = 0) -> int:
	var h := mix64(a - 7046029254386353131)   # + 0x9E3779B97F4A7C15 (golden ratio, as int64)
	h = mix64(h ^ (b + 0x632BE59BD9B4E019))
	h = mix64(h ^ (c + 0x3C6EF372FE94F82A))
	h = mix64(h ^ (d + 0x1B873593A5A5A5A5))
	h = mix64(h ^ (e + 0x2545F4914F6CDD1D))
	return h & 0x7FFFFFFFFFFFFFFF


## Uniform float in [0, 1) from a hash (24 bits of entropy: exact in float32 and identical on every platform).
static func unit(h: int) -> float:
	return float(h & 0xFFFFFF) / 16777216.0


## Uniform float in [0, 1) for (seed, generator, x, z, k): stateless, so any chunk can evaluate any cell.
static func rand01(seed_v: int, gen: int, x: int, z: int, k: int) -> float:
	return unit(hash64(seed_v, gen, x, z, k))
