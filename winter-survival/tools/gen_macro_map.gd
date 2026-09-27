extends SceneTree
## Paints the macro map v1 (W1, PLAN C25; ARQ v2 §8.4, §8.10) from the 48 × 48 ASCII map (PoiRegistry, doc 09
## §4.2):
##   godot --headless --path . -s tools/gen_macro_map.gd
## writes data/world/macro_map.png (768² px, 8 m/px from −1536 m on both axes: R/A = 16-bit height, G = biome × 16,
## B = scatter density) and data/world/macro_roads.json (road and rail splines, stamped as terrain by
## HeightFunction: the M3 roads + Carretera del Puerto, Gran Vía, rondas, A‑14, N‑140 sur, ski and village roads,
## Ferrocarril del Albo). Deterministic (fixed noise seeds): rerunning it reproduces the committed files byte for
## byte. `--check` compares instead of writing.
##
## The valley stays the M3 valley: every pixel whose centre is < VALLEY_KEEP m on both axes is painted by the M3 v0
## generator (legacy branch: its 24 × 24 map, its ±1536 m border and constants, unchanged code), so every byte a
## valley chunk (|x|, |z| < 1152 m) reads is the M3 byte — except the Carretera del Puerto cutting (PASS_*), the
## closed exception of the W1 card. Between VALLEY_KEEP and the old map edge (1536 m) the old border ring becomes
## the Sierra del Cierzo (east) and the Sierra de Peña Blanca (south): max(legacy, new) blended in; beyond, the new
## generator alone: mountains rise inside the '^' / '%' cells of the map (signed distance to their union, with the
## same domain warp as v0), the world border ring keeps the v0 formula on the new extent, the city, port, polígono
## and air base are flat, the río Albo / dársena / embalse / ibón are carved for PoiRegistry.WATER, and the roads
## get their corridors (the Carretera del Puerto pass, the Peña Roya tunnel approach and gorge, the border tunnels).

const OUT_PNG := "res://data/world/macro_map.png"
const OUT_ROADS := "res://data/world/macro_roads.json"
const NOISE_SEED := 4242
const N := 768
const PX := 8.0
const ORIGIN := -1536.0
## v0 map size (px) and half size (m): the legacy generator's domain.
const LEGACY_N := 384
const LEGACY_HALF := 1536.0
## Pixels with centre x < VALLEY_KEEP and z < VALLEY_KEEP are the v0 bytes. 1224 m keeps every pixel a valley
## chunk reads (B-spline ±16 m + lattice 4 m + scatter berry look-alike 24 m + the N‑140 profile window 40 m).
const VALLEY_KEEP := 1224.0
## The old border ring becomes the sierras between VALLEY_KEEP and BAND_END; the v0 data stops at LEGACY_HALF.
const BAND_END := 1400.0
const LEGACY_FADE := 1450.0

## The M3 (v0) map of PLAN §4.2, 24 × 24: only the legacy branch reads it (PoiRegistry.ASCII is the 48 × 48 map).
const VALLEY_ASCII := [
	"^^^^^^^^^^^^^^^^^^^^^^^^",
	"^^^##############X^^^^^^",
	"^################=#####^",
	"^################M#####^",
	"^################=#####^",
	"^##########f#####=#####^",
	"^#####vS###.....#=#####^",
	"^#####------TTT.-=#####^",
	"^##########.THTP-=#####^",
	"^##########.TTT.#G#####^",
	"^###########|####=##f##^",
	"^##R########|####=#####^",
	"^####D######C####=#####^",
	"^####~~##---#####A#####^",
	"^###~~~~~#|######=#####^",
	"^###~~~~~#|####f#=#####^",
	"^####~~~~v#######=#####^",
	"^#####~~#########G#####^",
	"^################=-v+##^",
	"^#############L##=#####^",
	"^################=#####^",
	"^################=#####^",
	"^^####################^^",
	"^^^^^^^^^^^^^^^^^^^^^^^^",
]

## Terrain classes of the new generator (48 × 48 map characters → class).
enum Cls { FOREST, FIELD, MOUNTAIN, SKI, WATER, OLD_TOWN, ENSANCHE, FINANCIAL, BARRIADA, SUBURB, INDUSTRIAL, PORT, AIRBASE, SETTLEMENT }
const CLS_OF := {
	"#": Cls.FOREST, "Q": Cls.FOREST, ".": Cls.FIELD, "f": Cls.FIELD, "^": Cls.MOUNTAIN, "U": Cls.MOUNTAIN,
	"%": Cls.SKI, "K": Cls.SKI, "~": Cls.WATER, "o": Cls.OLD_TOWN, "+": Cls.OLD_TOWN, "E": Cls.ENSANCHE, "N": Cls.ENSANCHE,
	"P": Cls.ENSANCHE, "m": Cls.ENSANCHE, "O": Cls.ENSANCHE, "B": Cls.FINANCIAL, "b": Cls.BARRIADA, "Y": Cls.BARRIADA,
	"s": Cls.SUBURB, "I": Cls.INDUSTRIAL, "e": Cls.INDUSTRIAL, "q": Cls.INDUSTRIAL, "D": Cls.INDUSTRIAL, "W": Cls.PORT,
	"Z": Cls.AIRBASE, "_": Cls.AIRBASE, "x": Cls.FIELD, "v": Cls.SETTLEMENT, "A": Cls.SETTLEMENT, "G": Cls.SETTLEMENT,
	"T": Cls.SETTLEMENT, "H": Cls.SETTLEMENT, "S": Cls.SETTLEMENT, "C": Cls.FOREST, "X": Cls.FIELD, "R": Cls.FOREST,
	"L": Cls.FOREST,
}
## Characters resolved from their neighbours (roads, rail, POI letters that sit on a road or change meaning).
const RESOLVE := ["=", "-", "|", ":", "j", "M", "F"]
## Per class: [biome, base level m, relief multiplier].
const CLS_DATA := {
	Cls.FOREST: [MacroMap.Biome.FOREST, 7.0, 1.0], Cls.FIELD: [MacroMap.Biome.FIELD, 3.0, 0.35],
	Cls.MOUNTAIN: [MacroMap.Biome.MOUNTAIN, 8.0, 1.0], Cls.SKI: [MacroMap.Biome.SKI, 8.0, 0.8],
	Cls.WATER: [MacroMap.Biome.FIELD, 0.0, 0.2], Cls.OLD_TOWN: [MacroMap.Biome.OLD_TOWN, 3.5, 0.12],
	Cls.ENSANCHE: [MacroMap.Biome.ENSANCHE, 3.0, 0.08], Cls.FINANCIAL: [MacroMap.Biome.FINANCIAL, 3.0, 0.06],
	Cls.BARRIADA: [MacroMap.Biome.BARRIADA, 3.5, 0.12], Cls.SUBURB: [MacroMap.Biome.SUBURB, 5.0, 0.35],
	Cls.INDUSTRIAL: [MacroMap.Biome.INDUSTRIAL, 2.0, 0.06], Cls.PORT: [MacroMap.Biome.PORT, -3.5, 0.03],
	Cls.AIRBASE: [MacroMap.Biome.AIRBASE, 2.0, 0.04], Cls.SETTLEMENT: [MacroMap.Biome.SETTLEMENT, 4.0, 0.3],
}
## New mountains: height = MOUNT_H × ridge factor × smooth(−MOUNT_OUT, MOUNT_IN, signed distance into the cells).
const MOUNT_H := 118.0
const MOUNT_OUT := 80.0
const MOUNT_IN := 150.0
const SKI_H := 64.0

## Carretera del Puerto: the pass over the Sierra del Cierzo (its road bed follows this floor; valley side from
## PASS_X0, the only valley pixels W1 changes). [x, floor height (m over the clearing)]
const PASS_X0 := 960.0
const PASS_PROFILE := [[960.0, 5.0], [1060.0, 10.0], [1150.0, 16.0], [1250.0, 22.0], [1350.0, 28.0], [1450.0, 32.0],
	[1536.0, 34.0], [1620.0, 28.0], [1700.0, 19.0], [1790.0, 10.0], [1830.0, 8.0]]
const PASS_FLAT := 10.0
const PASS_SLOPE := 0.5
## Túnel de Peña Roya: approach to the north portal (the valley's N‑140 ends there) and the desfiladero floor.
const GORGE_PROFILE := [[1640.0, 24.0], [1800.0, 22.0], [2000.0, 18.0], [2300.0, 14.0], [2600.0, 11.0], [2960.0, 8.0]]
## Monte Cierzo (Torre de Telecomunicaciones): a hill at the west edge of the city.
const MONTE_CIERZO := [Vector2(1890, -880), 34.0, 230.0]

## Road polylines (world metres). kind: highway / road / avenue = asphalt, track / rail = packed snow. The first
## nine are the M3 roads (unchanged; the N‑140 now ends at the collapsed north portal of the Peña Roya tunnel).
## Optional: name (banner), smooth (profile half window, samples of 8 m), shoulder (m), max_grade, poles (spacing m),
## guard ([[s0, s1]] metres along the road; filled below for the Carretera del Puerto), pads (set for the W1 roads).
const ROADS := [
	{"id": "n140", "kind": "highway", "width": 8.0, "name": "N-140", "points": [[700, -1600], [668, -1420], [640, -1280], [636, -1150],
		[648, -980], [660, -800], [634, -600], [628, -420], [646, -240], [662, -60], [652, 128], [628, 320], [616, 520],
		[640, 700], [662, 880], [650, 1080], [630, 1280], [632, 1290]]},
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
	# --- W1
	{"id": "carretera_puerto", "kind": "road", "width": 7.0, "name": "CARRETERA DEL PUERTO", "poles": 25.0, "smooth": 7, "max_grade": 0.09, "points": [[632, -392],
		[700, -390], [780, -386], [860, -382], [940, -380], [1010, -384], [1080, -388], [1140, -386], [1200, -378],
		[1260, -370], [1320, -372], [1380, -386], [1440, -398], [1500, -394], [1536, -384], [1580, -378], [1640, -386],
		[1700, -396], [1750, -392], [1792, -384]]},
	{"id": "gran_via", "kind": "avenue", "width": 24.0, "name": "GRAN VÍA", "shoulder": 6.0, "points": [[1792, -384],
		[2200, -384], [2432, -384], [2800, -384], [3300, -384], [3712, -384], [4096, -384]]},
	{"id": "ronda_norte", "kind": "avenue", "width": 18.0, "name": "RONDA NORTE", "shoulder": 6.0, "points": [[1752, -1024],
		[2100, -1024], [2432, -1024], [2800, -1024], [3300, -1024], [3712, -1024], [4096, -1024]]},
	{"id": "ronda_sur", "kind": "avenue", "width": 18.0, "name": "RONDA SUR", "shoulder": 6.0, "points": [[1752, 640],
		[2100, 640], [2432, 640], [2800, 640], [3300, 640], [3712, 640], [4096, 640]]},
	{"id": "a14", "kind": "highway", "width": 22.0, "name": "AUTOVÍA A-14", "smooth": 12, "poles": 50.0, "pole_model": "road_delineator", "points": [[4096, -1600],
		[4100, -1100], [4090, -640], [4096, -384], [4104, 0], [4096, 640], [4092, 1280], [4100, 2000], [4096, 2944],
		[4090, 3600], [4098, 4200], [4096, 4700]]},
	{"id": "n140_sur", "kind": "highway", "width": 8.0, "name": "N-140", "smooth": 8, "poles": 30.0, "pole_model": "road_delineator", "points": [[640, 1678],
		[640, 1800], [632, 2000], [648, 2200], [636, 2432], [644, 2600], [640, 2800], [656, 2910], [720, 2944], [1000, 2944],
		[1500, 2940], [2000, 2948], [2432, 2944], [2800, 2944], [3300, 2940], [3700, 2944], [3968, 2944], [4096, 2944]]},
	{"id": "esqui", "kind": "road", "width": 6.0, "poles": 20.0, "points": [[636, 2432], [500, 2436], [300, 2428], [100, 2432],
		[-128, 2436], [-300, 2432], [-500, 2426], [-600, 2400], [-640, 2330], [-640, 2280]]},
	{"id": "santa_maria", "kind": "road", "width": 5.0, "points": [[-128, 2436], [-120, 2600], [-132, 2800], [-128, 2990]]},
	{"id": "ferrocarril_eo", "kind": "rail", "width": 5.0, "name": "FERROCARRIL DEL ALBO", "smooth": 15, "shoulder": 5.0, "points": [
		[-1600, 2560], [-1000, 2556], [-400, 2564], [200, 2560], [800, 2556], [1400, 2562], [2000, 2560], [2432, 2560],
		[3000, 2556], [3450, 2552], [3600, 2520], [3690, 2440], [3712, 2300]]},
	{"id": "ferrocarril_ns", "kind": "rail", "width": 5.0, "name": "FERROCARRIL DEL ALBO", "smooth": 15, "shoulder": 5.0, "points": [
		[3712, -1600], [3712, -1024], [3712, -384], [3712, 640], [3712, 1152], [3712, 2300]]},
]
## Guardrails of the Carretera del Puerto: where its x is past this (the mountain section).
const GUARD_FROM_X := 1150.0

var _legacy_ascii_cache := {}
var _cls: Array = []          # 48 × 48 resolved classes (row-major)


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var check := OS.get_cmdline_user_args().has("--check")
	var relief := _noise(NOISE_SEED, 1.0 / 650.0, 3)
	var ridge := _noise(NOISE_SEED + 1, 1.0 / 260.0, 2)
	var warp_a := _noise(NOISE_SEED + 2, 1.0 / 180.0, 2)
	var warp_b := _noise(NOISE_SEED + 3, 1.0 / 180.0, 2)
	var dense := _noise(NOISE_SEED + 4, 1.0 / 300.0, 2)
	var glade := _noise(NOISE_SEED + 5, 1.0 / 140.0, 3)
	var peaks := _noise(NOISE_SEED + 6, 1.0 / 140.0, 3)
	_resolve_classes()
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	var counts := {}
	var carved_valley := 0
	for j in N:
		for i in N:
			var x := ORIGIN + (float(i) + 0.5) * PX
			var z := ORIGIN + (float(j) + 0.5) * PX
			var mx := maxf(x, z)
			var legacy: Array = []
			if i < LEGACY_N and j < LEGACY_N:
				legacy = _legacy_pixel(x, z, relief, ridge, warp_a, warp_b, dense, glade)
			var code: int
			var b: int
			var dens: int
			if mx < VALLEY_KEEP:
				code = legacy[0]
				b = legacy[1]
				dens = legacy[2]
			else:
				var nw := _new_pixel(x, z, relief, ridge, warp_a, warp_b, dense, glade, peaks)
				var rel := float(nw[0])
				if not legacy.is_empty():
					var lrel := float(int(legacy[0]) - MacroMap.H0_CODE) * MacroMap.HEIGHT_RANGE / 65535.0
					var w := _smooth(VALLEY_KEEP, BAND_END, mx)
					var both := maxf(lrel, rel)
					rel = lerpf(lrel, both, w)
					rel = lerpf(rel, float(nw[0]), _smooth(LEGACY_FADE, LEGACY_HALF, mx))
				code = _code(rel)
				b = int(nw[1]) if (legacy.is_empty() or mx >= BAND_END) else int(legacy[1])
				dens = int(nw[2]) if (legacy.is_empty() or mx >= BAND_END) else int(legacy[2])
			# corridors: the pass (outside the valley it also fills: the road bed follows PASS_PROFILE), the tunnel
			# approach and the gorge (only lower)
			var rel0 := float(code - MacroMap.H0_CODE) * MacroMap.HEIGHT_RANGE / 65535.0
			var rel1 := rel0
			var cut := _corridor_floor(x, z)
			if cut < rel1:
				rel1 = cut
			var fill := _pass_fill(x, z)
			if fill > rel1:
				rel1 = fill
			if rel1 != rel0:
				code = _code(rel1)
				if mx < VALLEY_KEEP:
					carved_valley += 1
			counts[b] = int(counts.get(b, 0)) + 1
			img.set_pixel(i, j, Color8(code >> 8, b * MacroMap.BIOME_STEP, dens, code & 255))
	var roads := _roads_json()
	var text := JSON.stringify({"version": 2, "doc": "Macro roads v1 (tools/gen_macro_map.gd, W1). Points in world metres (x east, z south). kind: highway | road | avenue (asphalt), track | rail (packed snow). Optional: name (region banner), smooth (profile half window, samples of 8 m), shoulder (m), poles (snow pole spacing m), guard ([[s0, s1]] guardrail stretches, m along the road).",
		"roads": roads}, "\t")
	print("macro map: %d² px, %d valley pixels carved by the Carretera del Puerto pass, biomes %s, %d ms" % [N, carved_valley, counts, Time.get_ticks_msec() - t0])
	if check:
		var ok := _same_png(img) and FileAccess.get_file_as_string(OUT_ROADS) == text
		print("gen_macro_map --check: %s" % ("identical" if ok else "DIFFERENT"))
		quit(0 if ok else 1)
		return
	var err := img.save_png(ProjectSettings.globalize_path(OUT_PNG))
	var f := FileAccess.open(ProjectSettings.globalize_path(OUT_ROADS), FileAccess.WRITE)
	f.store_string(text)
	f.close()
	print("macro map: %s (%s), roads: %d" % [OUT_PNG, error_string(err), roads.size()])
	quit(0 if err == OK else 1)


func _same_png(img: Image) -> bool:
	var old := Image.load_from_file(ProjectSettings.globalize_path(OUT_PNG))
	if old == null or old.get_width() != N:
		return false
	old.convert(Image.FORMAT_RGBA8)
	return old.get_data() == img.get_data()


static func _code(rel: float) -> int:
	return clampi(MacroMap.H0_CODE + int(round(rel * 65535.0 / MacroMap.HEIGHT_RANGE)), 0, 65535)


# ------------------------------------------------------------------ the M3 v0 generator (legacy branch, unchanged)
## [height code, biome, density byte] of the v0 map at a pixel centre (the M3 code, with its 24 × 24 map).
func _legacy_pixel(x: float, z: float, relief: FastNoiseLite, ridge: FastNoiseLite, warp_a: FastNoiseLite, warp_b: FastNoiseLite,
		dense: FastNoiseLite, glade: FastNoiseLite) -> Array:
	var edge := LEGACY_HALF - maxf(absf(x), absf(z))
	var d_clear := Vector2(x, z).length()
	var wx := x + warp_a.get_noise_2d(x, z) * 55.0
	var wz := z + warp_b.get_noise_2d(x, z) * 55.0
	var ch := _legacy_char_at(wx, wz)
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
	if edge < 230.0 and not _legacy_in_pass(x, z):
		b = MacroMap.Biome.MOUNTAIN
	if sdf < 30.0:
		b = MacroMap.Biome.FIELD      # open shore
	if sdf < 0.0:
		b = MacroMap.Biome.LAKE
	if d_clear < 110.0:
		b = MacroMap.Biome.FOREST
	# --- height (relative to the clearing, m)
	var rel := relief.get_noise_2d(x, z) * 9.0
	if b == MacroMap.Biome.SETTLEMENT or ch in [".", "f"]:
		rel *= 0.35
	rel = lerpf(rel, -7.0, _smooth(160.0, 0.0, sdf))
	var mount := 118.0 * _smooth(560.0, 70.0, edge) * (0.72 + 0.55 * (1.0 - absf(ridge.get_noise_2d(x, z))))
	if _legacy_in_pass(x, z):
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
	return [code, b, int(round(dens * 255.0))]


static func _legacy_char_at(x: float, z: float) -> String:
	var col := int(round(x / 128.0)) + 12
	var row := int(round(z / 128.0)) + 12
	if row < 0 or row >= VALLEY_ASCII.size() or col < 0 or col >= 24:
		return "^"
	var line: String = VALLEY_ASCII[row]
	return line[col] if col < line.length() else "#"


## The v0 N‑140 passes through the border ring (north: checkpoint / evacuation bridge; south: tunnel).
static func _legacy_in_pass(x: float, z: float) -> bool:
	return absf(z) > 900.0 and absf(x - 650.0) < 260.0


# ------------------------------------------------------------------ the W1 generator
## 48 × 48 classes: map characters, roads / rail / ambiguous letters resolved to their neighbours (never to a
## mountain or water: a road cell is open ground).
func _resolve_classes() -> void:
	_cls.resize(PoiRegistry.COLS * PoiRegistry.ASCII.size())
	for r in PoiRegistry.ASCII.size():
		var line: String = PoiRegistry.ASCII[r]
		for c in PoiRegistry.COLS:
			var ch := line[c]
			var cl: int = CLS_OF.get(ch, Cls.FOREST)
			if ch in RESOLVE:
				var votes := {}
				for dr in range(-1, 2):
					for dc in range(-1, 2):
						var rr := r + dr
						var cc := c + dc
						if rr < 0 or cc < 0 or rr >= PoiRegistry.ASCII.size() or cc >= PoiRegistry.COLS or (dr == 0 and dc == 0):
							continue
						var nch: String = (PoiRegistry.ASCII[rr] as String)[cc]
						if nch in RESOLVE or not CLS_OF.has(nch):
							continue
						var ncl: int = CLS_OF[nch]
						if ncl == Cls.MOUNTAIN or ncl == Cls.WATER or ncl == Cls.SKI:
							continue
						votes[ncl] = int(votes.get(ncl, 0)) + 1
				cl = Cls.FIELD
				var best := 0
				for k in [Cls.FOREST, Cls.FIELD, Cls.SUBURB, Cls.OLD_TOWN, Cls.ENSANCHE, Cls.FINANCIAL, Cls.BARRIADA, Cls.INDUSTRIAL,
						Cls.PORT, Cls.AIRBASE, Cls.SETTLEMENT]:
					if int(votes.get(k, 0)) > best:
						best = int(votes[k])
						cl = k
			_cls[r * PoiRegistry.COLS + c] = cl


func _cls_at_cell(col: int, row: int) -> int:
	if row < 0 or row >= PoiRegistry.ASCII.size() or col < 0 or col >= PoiRegistry.COLS:
		return Cls.MOUNTAIN
	return _cls[row * PoiRegistry.COLS + col]


## Signed distance (m) from a (warped) point into the union of the cells of class `cl` (> 0 inside), ±256 m.
func _cell_sdf(wx: float, wz: float, cl: int) -> float:
	var col := int(round(wx / 128.0)) + 12
	var row := int(round(wz / 128.0)) + 12
	var inside := _cls_at_cell(col, row) == cl
	var best := 256.0
	for dr in range(-2, 3):
		for dc in range(-2, 3):
			var c := col + dc
			var r := row + dr
			var is_cl := _cls_at_cell(c, r) == cl
			if is_cl == inside:
				continue
			# distance from the point to the cell square
			var cx := float(c - 12) * 128.0
			var cz := float(r - 12) * 128.0
			var qx := maxf(absf(wx - cx) - 64.0, 0.0)
			var qz := maxf(absf(wz - cz) - 64.0, 0.0)
			best = minf(best, sqrt(qx * qx + qz * qz))
	return best if inside else -best


## [rel height (m), biome, density byte] of the W1 generator at a pixel centre.
func _new_pixel(x: float, z: float, relief: FastNoiseLite, ridge: FastNoiseLite, warp_a: FastNoiseLite, warp_b: FastNoiseLite,
		dense: FastNoiseLite, glade: FastNoiseLite, peaks: FastNoiseLite) -> Array:
	var wx := x + warp_a.get_noise_2d(x, z) * 55.0
	var wz := z + warp_b.get_noise_2d(x, z) * 55.0
	var col := int(round(wx / 128.0)) + 12
	var row := int(round(wz / 128.0)) + 12
	var cl := _cls_at_cell(col, row)
	var cd: Array = CLS_DATA[cl]
	var b: int = cd[0]
	var rel := float(cd[1]) + relief.get_noise_2d(x, z) * 9.0 * float(cd[2])
	# mountains: inside the '^' cells (signed distance), the '%' slopes, and the world border ring (v0 formula)
	var rf := 0.72 + 0.55 * (1.0 - absf(ridge.get_noise_2d(x, z)))
	var s_m := _cell_sdf(wx, wz, Cls.MOUNTAIN)
	var s_k := _cell_sdf(wx, wz, Cls.SKI)
	var edge := minf(minf(x - ORIGIN, (ORIGIN + N * PX) - x), minf(z - ORIGIN, (ORIGIN + N * PX) - z))
	var border := MOUNT_H * _smooth(560.0, 70.0, edge) * rf * _border_pass(x, z)
	var inner := MOUNT_H * _smooth(-MOUNT_OUT, MOUNT_IN, s_m) * rf * (0.85 + 0.3 * peaks.get_noise_2d(x, z))
	var ski := SKI_H * _smooth(-60.0, 120.0, s_k) * (0.8 + 0.4 * absf(peaks.get_noise_2d(x * 0.7, z * 0.7)))
	rel += maxf(maxf(border, inner), ski)
	# Monte Cierzo
	var mc: Vector2 = MONTE_CIERZO[0]
	rel += float(MONTE_CIERZO[1]) * exp(-pow(Vector2(x, z).distance_to(mc) / float(MONTE_CIERZO[2]), 2.0))
	# water: carve the banks toward the ice (HeightFunction stamps the exact flat ice)
	var wat := PoiRegistry.water_at(x, z, 160.0)
	if wat.x < 160.0:
		var lvl := wat.y
		var wi := int(wat.z)
		var grp := int(PoiRegistry.WATER[wi]["group"])
		if grp == 1:
			rel = lerpf(rel, lvl + 1.5, _smooth(90.0, 30.0, wat.x))
		else:
			rel = lerpf(rel, lvl + 1.0, _smooth(120.0, 25.0, wat.x))
		if wat.x < 0.0:
			b = MacroMap.Biome.RIVER if grp == 1 else MacroMap.Biome.LAKE
	elif cl == Cls.WATER:
		b = MacroMap.Biome.FIELD
	# biome refinements (as v0): dense forest near the mountains and by noise, mountain rock on the heights
	if b == MacroMap.Biome.FOREST and (dense.get_noise_2d(x, z) > 0.12 or s_m > -140.0 or edge < 430.0):
		b = MacroMap.Biome.DENSE_FOREST
	if (s_m > -8.0 or (edge < 230.0 and border > 40.0)) and b != MacroMap.Biome.RIVER and b != MacroMap.Biome.LAKE:
		b = MacroMap.Biome.MOUNTAIN
	var dens := clampf(0.62 + 0.75 * glade.get_noise_2d(x, z), 0.12, 1.0)
	if b == MacroMap.Biome.MOUNTAIN:
		dens = 0.8
	return [rel, b, int(round(dens * 255.0))]


## Where the roads leave the world through the border ring (A‑14 north / south, railway north / west), v0-style
## pass: the border mountain is lowered around them.
static func _border_pass(x: float, z: float) -> float:
	var f := 1.0
	if z < -900.0:
		f *= 1.0 - 0.85 * exp(-pow((x - 4096.0) / 150.0, 2.0))
		f *= 1.0 - 0.85 * exp(-pow((x - 3712.0) / 120.0, 2.0))
	if z > 3900.0:
		f *= 1.0 - 0.85 * exp(-pow((x - 4096.0) / 150.0, 2.0))
	if x < -900.0 and z > 1600.0:
		f *= 1.0 - 0.85 * exp(-pow((z - 2560.0) / 120.0, 2.0))
	return f


## Floor of the road corridors at a point (INF = none): the Carretera del Puerto pass, the approach to the north
## portal of the Peña Roya tunnel and the Desfiladero de Peña Roya (N‑140 sur). Only ever lowers the terrain.
func _corridor_floor(x: float, z: float) -> float:
	var out := INF
	if x >= PASS_X0 and x <= 1840.0 and absf(z + 384.0) < 200.0:
		var zr := _poly_z(ROADS[9]["points"], x)
		var fl := _profile(PASS_PROFILE, x)
		out = minf(out, fl + PASS_SLOPE * maxf(0.0, absf(z - zr) - PASS_FLAT))
	if z >= 1236.0 and z <= 1300.0 and absf(x - 634.0) < 120.0:
		out = minf(out, 16.0 + 0.6 * maxf(0.0, absf(x - 634.0) - 16.0))
	if z >= 1640.0 and z <= 2960.0 and absf(x - 640.0) < 260.0:
		var xr := _poly_x(ROADS[14]["points"], z)
		out = minf(out, _profile(GORGE_PROFILE, z) + 0.45 * maxf(0.0, absf(x - xr) - 12.0))
	return out


## Lowest ground allowed in the Carretera del Puerto pass outside the valley (−INF elsewhere): the profile minus a
## cone, so the road never dives into a notch of the sierra.
func _pass_fill(x: float, z: float) -> float:
	if x < VALLEY_KEEP or x > 1840.0 or absf(z + 384.0) > 200.0:
		return -INF
	var zr := _poly_z(ROADS[9]["points"], x)
	return _profile(PASS_PROFILE, x) - PASS_SLOPE * maxf(0.0, absf(z - zr) - PASS_FLAT)


static func _profile(prof: Array, v: float) -> float:
	if v <= float(prof[0][0]):
		return float(prof[0][1])
	for k in prof.size() - 1:
		var a: Array = prof[k]
		var b: Array = prof[k + 1]
		if v <= float(b[0]):
			return lerpf(float(a[1]), float(b[1]), (v - float(a[0])) / (float(b[0]) - float(a[0])))
	return float(prof[prof.size() - 1][1])


## z of a polyline at x (the first segment spanning x), or the nearest end.
static func _poly_z(pts: Array, x: float) -> float:
	for k in pts.size() - 1:
		var a: Array = pts[k]
		var b: Array = pts[k + 1]
		if (x >= float(a[0]) and x <= float(b[0])) or (x <= float(a[0]) and x >= float(b[0])):
			var t := (x - float(a[0])) / maxf(absf(float(b[0]) - float(a[0])), 0.001) * signf(float(b[0]) - float(a[0]))
			return lerpf(float(a[1]), float(b[1]), clampf(t, 0.0, 1.0))
	return float(pts[0][1]) if absf(x - float(pts[0][0])) < absf(x - float(pts[pts.size() - 1][0])) else float(pts[pts.size() - 1][1])


## x of a polyline at z (the first segment spanning z), or the nearest end.
static func _poly_x(pts: Array, z: float) -> float:
	for k in pts.size() - 1:
		var a: Array = pts[k]
		var b: Array = pts[k + 1]
		if (z >= float(a[1]) and z <= float(b[1])) or (z <= float(a[1]) and z >= float(b[1])):
			var t := (z - float(a[1])) / maxf(absf(float(b[1]) - float(a[1])), 0.001) * signf(float(b[1]) - float(a[1]))
			return lerpf(float(a[0]), float(b[0]), clampf(t, 0.0, 1.0))
	return float(pts[0][0]) if absf(z - float(pts[0][1])) < absf(z - float(pts[pts.size() - 1][1])) else float(pts[pts.size() - 1][0])


## Roads for macro_roads.json (the Carretera del Puerto gets its guardrail stretch in metres along the road).
func _roads_json() -> Array:
	var out: Array = []
	for r: Dictionary in ROADS:
		var e := r.duplicate(true)
		if out.size() >= 9:
			e["pads"] = true   # W1 roads run level over the W1 pads (HeightFunction)
		if str(r["id"]) == "carretera_puerto":
			var pts: Array = r["points"]
			var s := 0.0
			var s0 := -1.0
			for k in pts.size() - 1:
				var a := Vector2(float(pts[k][0]), float(pts[k][1]))
				var b := Vector2(float(pts[k + 1][0]), float(pts[k + 1][1]))
				if s0 < 0.0 and b.x >= GUARD_FROM_X:
					s0 = s + a.distance_to(b) * clampf((GUARD_FROM_X - a.x) / maxf(b.x - a.x, 0.001), 0.0, 1.0)
				s += a.distance_to(b)
			e["guard"] = [[snappedf(s0, 0.1), snappedf(s - 30.0, 0.1)]]
		out.append(e)
	return out


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
