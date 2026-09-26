extends SceneTree
## Paints the macro map v0 (PLAN §3.2 / M3, ARQ v2 §8.4) from the ASCII map of PLAN §4.2 (PoiRegistry):
##   godot --headless --path . -s tools/gen_macro_map.gd
## writes data/world/macro_map.png (384² px, 8 m/px: R/A = 16-bit height, G = biome × 40, B = scatter density)
## and data/world/macro_roads.json (road polylines: N‑140 + secondary roads + tracks). Deterministic (fixed
## noise seeds): rerunning it reproduces the committed files byte for byte. M9a replaces v0 by a hand-tuned map.

const OUT_PNG := "res://data/world/macro_map.png"
const OUT_ROADS := "res://data/world/macro_roads.json"
const NOISE_SEED := 4242

## Road polylines (world metres). kind: highway (asphalt 8 m), road (asphalt 5–6 m), track (packed snow 4 m).
const ROADS := [
	{"id": "n140", "kind": "highway", "width": 8.0, "points": [[700, -1600], [668, -1420], [640, -1280], [636, -1150],
		[648, -980], [660, -800], [634, -600], [628, -420], [646, -240], [662, -60], [652, 128], [628, 320], [616, 520],
		[640, 700], [662, 880], [650, 1080], [630, 1280], [640, 1600]]},
	{"id": "valdenieve", "kind": "road", "width": 6.0, "points": [[-840, -700], [-700, -662], [-520, -642], [-330, -650],
		[-160, -630], [-20, -602], [160, -590], [380, -570], [520, -590], [632, -600]]},
	{"id": "san_blas", "kind": "road", "width": 6.0, "points": [[646, 760], [760, 772], [880, 768], [1000, 760]]},
	{"id": "embarcadero", "kind": "road", "width": 5.0, "points": [[-100, 128], [-256, 132], [-296, 240], [-290, 380],
		[-340, 470], [-384, 520]]},
	{"id": "clearing_north", "kind": "track", "width": 4.0, "points": [[40, -420], [10, -300], [-8, -200], [-20, -110]]},
	{"id": "lake_north", "kind": "track", "width": 4.0, "points": [[-256, 132], [-420, 82], [-560, 44], [-700, 20], [-860, 8]]},
	{"id": "granja_alta", "kind": "track", "width": 4.0, "points": [[652, -240], [800, -250], [960, -256]]},
	{"id": "granja_romero", "kind": "track", "width": 4.0, "points": [[628, 330], [500, 360], [400, 384]]},
	{"id": "granja_molino", "kind": "track", "width": 4.0, "points": [[-20, -700], [-80, -800], [-128, -880]]},
]


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var relief := _noise(NOISE_SEED, 1.0 / 650.0, 3)
	var ridge := _noise(NOISE_SEED + 1, 1.0 / 260.0, 2)
	var warp_a := _noise(NOISE_SEED + 2, 1.0 / 180.0, 2)
	var warp_b := _noise(NOISE_SEED + 3, 1.0 / 180.0, 2)
	var dense := _noise(NOISE_SEED + 4, 1.0 / 300.0, 2)
	var glade := _noise(NOISE_SEED + 5, 1.0 / 140.0, 3)
	var n := MacroMap.SIZE
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var counts := {}
	for j in n:
		for i in n:
			var x := -WorldConst.HALF + (float(i) + 0.5) * MacroMap.PX
			var z := -WorldConst.HALF + (float(j) + 0.5) * MacroMap.PX
			var edge := WorldConst.HALF - maxf(absf(x), absf(z))
			var d_clear := Vector2(x, z).length()
			var wx := x + warp_a.get_noise_2d(x, z) * 55.0
			var wz := z + warp_b.get_noise_2d(x, z) * 55.0
			var ch := PoiRegistry.char_at(wx, wz)
			var sdf := PoiRegistry.lake_sdf(x, z)
			# --- biome
			var b := MacroMap.Biome.FOREST
			if ch in [".", "f"]:
				b = MacroMap.Biome.FIELD
			elif ch in ["T", "H", "P", "v", "S", "+"]:
				b = MacroMap.Biome.SETTLEMENT
			elif dense.get_noise_2d(x, z) > 0.12:
				b = MacroMap.Biome.DENSE_FOREST
			if edge < 430.0:
				b = MacroMap.Biome.DENSE_FOREST
			if edge < 230.0 and not _in_pass(x, z):
				b = MacroMap.Biome.MOUNTAIN
			if sdf < 30.0:
				b = MacroMap.Biome.FIELD      # open shore
			if sdf < 0.0:
				b = MacroMap.Biome.LAKE
			if d_clear < 110.0:
				b = MacroMap.Biome.FOREST
			counts[b] = int(counts.get(b, 0)) + 1
			# --- height (relative to the clearing, m)
			var rel := relief.get_noise_2d(x, z) * 9.0
			if b == MacroMap.Biome.SETTLEMENT or ch in [".", "f"]:
				rel *= 0.35
			rel = lerpf(rel, -7.0, _smooth(160.0, 0.0, sdf))
			var mount := 118.0 * _smooth(560.0, 70.0, edge) * (0.72 + 0.55 * (1.0 - absf(ridge.get_noise_2d(x, z))))
			if _in_pass(x, z):
				mount *= 1.0 - 0.85 * exp(-pow((x - 650.0) / 150.0, 2.0))
			rel += mount
			rel += 78.0 * exp(-pow(Vector2(x, z).distance_to(Vector2(-1152, -128)) / 240.0, 2.0))
			var code := MacroMap.H0_CODE
			if d_clear > 180.0:
				rel *= _smooth(180.0, 360.0, d_clear)
				code = clampi(MacroMap.H0_CODE + int(round(rel * 65535.0 / MacroMap.HEIGHT_RANGE)), 0, 65535)
			# --- scatter density
			var dens := clampf(0.62 + 0.75 * glade.get_noise_2d(x, z), 0.12, 1.0)
			if b == MacroMap.Biome.MOUNTAIN:
				dens = 0.8
			img.set_pixel(i, j, Color8(code >> 8, b * MacroMap.BIOME_STEP, int(round(dens * 255.0)), code & 255))
	var err := img.save_png(ProjectSettings.globalize_path(OUT_PNG))
	var f := FileAccess.open(ProjectSettings.globalize_path(OUT_ROADS), FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "doc": "Macro roads v0 (tools/gen_macro_map.gd). Points in world metres (x east, z south).", "roads": ROADS}, "\t"))
	f.close()
	print("macro map: %s (%s), roads: %d, biomes %s, %d ms" % [OUT_PNG, error_string(err), ROADS.size(), counts, Time.get_ticks_msec() - t0])
	quit(0 if err == OK else 1)


## The N‑140 crosses the border ring through a pass (north: checkpoint / evacuation bridge; south: tunnel).
static func _in_pass(x: float, z: float) -> bool:
	return absf(z) > 900.0 and absf(x - 650.0) < 260.0


## 0 at `outer`, 1 at `inner` (either order), smooth in between.
static func _smooth(outer: float, inner: float, d: float) -> float:
	var t := clampf((d - outer) / (inner - outer), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func _noise(s: int, freq: float, octaves: int) -> FastNoiseLite:
	var nz := FastNoiseLite.new()
	nz.seed = s
	nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nz.fractal_type = FastNoiseLite.FRACTAL_FBM
	nz.fractal_octaves = octaves
	nz.frequency = freq
	return nz
