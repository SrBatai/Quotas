class_name WorldConst
## World grid constants and deterministic integer hashing (ARQ v2 §8.1, M3; W1 / PLAN C25). The world is
## WORLD_CHUNKS × WORLD_CHUNKS chunks of CHUNK_SIZE m = 6 144 m. Chunk CENTER_CHUNK is centred on the origin (M2
## convention kept so the hunter's clearing is exactly chunks 23–25 on both axes): the chunk grid spans
## EXTENT_MIN … EXTENT_MAX (−1568 … +4576 m) on both axes. The M3 valley keeps its coordinates, chunk indices and
## wids in the north-west quadrant; the world grew toward +x (east) and +z (south). The macro map
## (data/world/macro_map.png) covers MACRO_ORIGIN … +4608 m and the playable walls are per axis
## (WALL_MIN … WALL_MAX = −1450 … +4420 m), with the border ring (mountains, fog) inside each wall.
## Everything here is pure (no scene tree, no global RNG): the client and the server compute the same values.
##
## Chunk keys (persistence, net, registries): key(cx, cz) = cx << 16 | cz, cx and cz in 0 … WORLD_CHUNKS − 1.
## The encoding did not change with W1 (it always had 16 + 16 bits): every M3 key keeps its value.

const CHUNK_SIZE := 64.0
const WORLD_CHUNKS := 96
const CENTER_CHUNK := 24
## Chunks in the world (dense tables: chunk_index(cx, cz) in 0 … CHUNK_COUNT − 1).
const CHUNK_COUNT := WORLD_CHUNKS * WORLD_CHUNKS
## World format version (persistence `world_meta.world_version`): 1 = M3 valley 3 × 3 km, 2 = W1 world 6 × 6 km.
const WORLD_VERSION := 2
## Terrain samples per chunk edge (1 m spacing, the last row/column is shared with the neighbour).
const SAMPLES := 65
const SAMPLE_STEP := 1.0
## Chunk grid extent (m, both axes): chunk 0 starts at EXTENT_MIN, chunk WORLD_CHUNKS − 1 ends at EXTENT_MAX.
const EXTENT_MIN := -1568.0
const EXTENT_MAX := 4576.0
## First pixel edge of the macro map (m, both axes): 768 px × 8 m → −1536 … +4608.
const MACRO_ORIGIN := -1536.0
## Legacy (M3): half size of the 384² valley macro map (±1536 m). Only the valley generator (tools/gen_macro_map.gd,
## legacy branch) uses it; world queries use MACRO_ORIGIN.
const HALF := 1536.0
## Hard invisible walls of the playable area, per axis (m). The outer ring up to each is border mountains + fog.
const WALL_MIN := -1450.0
const WALL_MAX := 4420.0
## Legacy (M3): the valley's symmetric wall (= −WALL_MIN). Use WALL_MIN / WALL_MAX / in_playable / clamp_playable.
const WALL := 1450.0
## Width (m) of the border ring inside each wall: the border fog starts BORDER_FOG m before the nearest wall
## (M3: from 1252 m to the ±1450 m wall, same on every side now) and the "LAS CUMBRES" region BORDER_REGION m.
const BORDER_FOG := 198.0
const BORDER_REGION := 202.0
## Legacy (M3): where the valley's border ring started (m, Chebyshev from the origin). Kept for old callers only.
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


## Dense index of a chunk (0 … CHUNK_COUNT − 1, row-major by cz): for packed per-chunk tables in memory. Persist
## `key`, not this (the key does not depend on the grid size).
static func chunk_index(cx: int, cz: int) -> int:
	return cz * WORLD_CHUNKS + cx


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


## Inside the playable walls (strictly).
static func in_playable(x: float, z: float) -> bool:
	return x > WALL_MIN and x < WALL_MAX and z > WALL_MIN and z < WALL_MAX


## A point moved inside the walls, `margin` m from each (teleports, spawns).
static func clamp_playable(x: float, z: float, margin: float = 2.0) -> Vector2:
	return Vector2(clampf(x, WALL_MIN + margin, WALL_MAX - margin), clampf(z, WALL_MIN + margin, WALL_MAX - margin))


## Distance (m) to the nearest wall: > 0 inside the playable area, < 0 outside. The border fog and the border
## region use it (M3 used the Chebyshev distance from the origin, identical on the valley's west and north sides).
static func wall_distance(x: float, z: float) -> float:
	return minf(minf(x - WALL_MIN, WALL_MAX - x), minf(z - WALL_MIN, WALL_MAX - z))


## Quadrant of the world around its centre ((EXTENT_MIN + EXTENT_MAX) / 2 on both axes): 0 NW (the valley),
## 1 NE (Altavega), 2 SW (Peña Blanca), 3 SE (La Vega). Tests and tools.
static func quadrant(x: float, z: float) -> int:
	var c := (EXTENT_MIN + EXTENT_MAX) * 0.5
	return (1 if x >= c else 0) + (2 if z >= c else 0)


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
