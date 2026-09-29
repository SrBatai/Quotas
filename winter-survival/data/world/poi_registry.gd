class_name PoiRegistry
## Points of interest, regions, pads and water of the macro map (PLAN §4.2–4.3, ARQ v2 §8.4; W1: PLAN C25/C36,
## docs/research/09_ciudad_mundo_vivo.md §4.2–4.3), in world metres (x → east, z → south; the hunter's clearing at
## the origin). The ASCII map is the source: character (col, row) is centred at ((col − 12) × 128, (row − 12) × 128),
## so C (12, 12) is (0, 0), the N-140 column 17 runs along x ≈ 640 and the río Albo column 31 along x ≈ 2432.
## Pure data + pure queries: tools/gen_macro_map.gd paints the macro map from it, HeightFunction flattens the pads
## and freezes the water, ScatterGen keeps them clear, the region banner names the chunks, PopulationManager reads
## the zombie densities and LocationInfo (H2) reads the region records (see REGIONS).

## The 48 × 48 map of doc 09 §4.2 / appendix A (1 character = 128 m, row 0 = north). Rows 0–21 × columns 0–22
## are the M3 map of PLAN §4.2 except the Carretera del Puerto (row 9, columns 18–22). One fix to appendix A: the
## río Albo is continuous (rows 43–44 of column 31 were painted over by the vega; a frozen river cannot stop).
const ASCII := [
	"^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^~~~^^^^^^^^U^^U^^^",
	"^^^##############X^^^^^^^^####~~~########:##=^^^",
	"^################=#####^^^sssssD#ssssssss:##=^^^",
	"^################M#####^^^sssss~#ssssssss:##=^^^",
	"^################=#####^^#===============:===^^^",
	"^##########f#####=#####^^##Qooo~EEEEEEEEE:ss=^^^",
	"^#####vS###.....#=#####^^##oooo~EEEEENEEE:ss=^^^",
	"^#####------TTT.-=#####^^#ooooo~BBBEEEEEE:ss=^^^",
	"^##########.THTP-=#####^^#ooo+o~BBBEEEEEE:ss=^^^",
	"^##########.TTT.#G------M-===============:===^^^",
	"^###########|####=##f##^^#ooooo~BBBEEEEEEFss=^^^",
	"^##R########|####=#####^^#ooooo~BBBEEEmmE:ss=^^^",
	"^####D######C####=#####^^#.Ybbb~EEEEEEEEE:ss=^^^",
	"^####~~##---#####A#####^^#bbbbb~.EEEPEEEE:ss=^^^",
	"^###~~~~~#|######=#####^^#bbbbb~.EEEEEEEE:ssj^^^",
	"^###~~~~~#|####f#=#####^^#bbbbb~.EEEEEEOE:ssj^^^",
	"^####~~~~v#######=#####^^#bbbbb~EEEEEEEEE:ssj^^^",
	"^#####~~#########G#####^^#===============:==j^^^",
	"^################=-v+##^^#..G..~IIIIIIIII:##j^^^",
	"^#############L##=#####^^#.....~IIeIIIIII:##j^^^",
	"^################=#####^^#...W~~~WIIIIIII:##j^^^",
	"^################=#####^^#...W~~~WIIIIqqIF##j^^^",
	"^^###############U####^^^#...W~~~WIIIIqqI:##j^^^",
	"^^^^^^^^^^^^^^^^^^^^^^^^^#...W~~~WIIIIIII:##j^^^",
	"^^^^^^^^^^^^^^^^^^^^^^^###...##~IIIIIIIII:#Gj^^^",
	"^^^%%%%%%%%%^^^##U#^^^^###...##~IIIIIqIII:##j^^^",
	"^^^%%%%%%%%%^^^%%=#^^^^###...##~IIIIIIIII:##j^^^",
	"^^^%%%%%%%%%^^^%%=%%^^^###ssss#~IIIIIIIII:##j^^^",
	"^^^%%%%%%%%%^^^%%=%%^^^###ssss#~#ssssssss:##j^^^",
	"^^%%%%^K^^^^^^^%%=%%^^^###ssss#~#ssssssss:##j^^^",
	"^^%%%%^|^^^^^^^%%=%%######ssss#~#ssssssss:##j^^^",
	"^######----------=%%###########~#ssssssss:##=^^^",
	"U::::::::::::::::=::::::::::::::::::::::::##=^^^",
	"^^^########|#####=#############~#ssssssss###=^^^",
	"^^^########|#####=#############~#ssssssss###=^^^",
	"^##~~~#####|#####==========================A=^^^",
	"^##~~~#####v############.......~#M##########=^^^",
	"^##~~~##################.......~ZZZZZZZZZZZZ=^^^",
	"^............####..........f...~ZZZZZZZZZZZZ=^^^",
	"^............####...f..........~ZZZZZZZZZZZZ=^^^",
	"^............####..............~____________=^^^",
	"^######.f....####..............~ZZZZZZZZZZZZ=^^^",
	"^######........................~ZZZZZZZZZZZZ=^^^",
	"^######...................f....~..........x.=^^^",
	"^######........................~......f.....=^^^",
	"^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^~^^^^^^^^^^^^=^^^",
	"^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^~^^^^^^^^^^^^=^^^",
	"^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^~^^^^^^^^^^^^U^^^",
]
const COLS := 48
const CELL := 128.0

# ------------------------------------------------------------------ regions
## Named regions for the banner ("REGIÓN — NOMBRE") and the data of LocationInfo (H2, C35). First match wins
## within a tier: tier 0 (places: POIs, districts, towns — small ones first), then the water bodies (WATER), then
## the named roads (macro_roads.json "name"), then tier 1 (broad areas: the city, the sierras, the vega), then the
## border ring (LAS CUMBRES), the valley's high forest (PINOS ALTOS) and BOSQUE PROFUNDO.
## shape: "radius" (circle around center) or "size" (axis-aligned rect around center); "water" = the region is a
## WATER body (exact shape: its signed distance; the rect only bounds it).
## LocationInfo fields (W1 regions; the valley's come from Locations.KNOWN): id, display (display case), kind
## (city | district | town | village | farm | poi | natural | road), parent (id), danger 0–3, power ("off" |
## "generator" | "on" | ""), temp (°C offset), zombies [min, max] per chunk (doc 09 §4.3), milestone (the one
## that builds its content) and reserved (true: only terrain + pad in W1, nothing urban yet).
const REGIONS := [
	# --- M3 valley (unchanged; names, order and shapes)
	{"name": "CLARO DEL CAZADOR", "center": Vector2(0, 0), "radius": 100.0},
	{"name": "PUNTO DE EVACUACIÓN", "center": Vector2(640, -1408), "radius": 110.0},
	{"name": "CONTROL MILITAR KM 12", "center": Vector2(640, -1152), "radius": 100.0},
	{"name": "GASOLINERA NORTE", "center": Vector2(640, -384), "radius": 80.0},
	{"name": "GASOLINERA SUR", "center": Vector2(640, 640), "radius": 80.0},
	{"name": "ÁREA DE DESCANSO", "center": Vector2(640, 128), "radius": 90.0},
	{"name": "GRANJA DEL MOLINO", "center": Vector2(-128, -896), "radius": 100.0},
	{"name": "GRANJA ALTA", "center": Vector2(1024, -256), "radius": 100.0},
	{"name": "GRANJA ROMERO", "center": Vector2(384, 384), "radius": 100.0},
	{"name": "LA HERRERÍA", "center": Vector2(-704, -768), "radius": 170.0},
	{"name": "EL EMBARCADERO", "center": Vector2(-384, 512), "radius": 120.0},
	{"name": "SAN BLAS", "center": Vector2(960, 768), "radius": 150.0},
	{"name": "PRESA", "center": Vector2(-880, 20), "radius": 100.0},
	{"name": "REPETIDOR DEL PICO", "center": Vector2(-1152, -128), "radius": 170.0},
	{"name": "TORRE DE VIGILANCIA", "center": Vector2(256, 896), "radius": 90.0},
	{"name": "VALDENIEVE", "center": Vector2(176, -512), "size": Vector2(560, 420)},
	# --- W1: POIs and small places (tier 0)
	{"id": "control_del_puerto", "name": "CONTROL DEL PUERTO", "display": "Control del Puerto", "kind": "poi", "parent": "",
		"center": Vector2(1536, -384), "size": Vector2(100, 80), "danger": 2, "power": "off", "temp": -3.0, "zombies": [15, 30], "milestone": "C1", "reserved": true},
	{"id": "catedral", "name": "CATEDRAL DE ALTAVEGA", "display": "Catedral de Altavega", "kind": "poi", "parent": "altavega_casco_viejo",
		"center": Vector2(2176, -512), "size": Vector2(110, 80), "danger": 2, "power": "off", "temp": 0.0, "zombies": [20, 35], "milestone": "C2", "reserved": true},
	{"id": "torre_telecomunicaciones", "name": "MONTE CIERZO — TORRE DE TELECOMUNICACIONES", "display": "Torre de Telecomunicaciones", "kind": "poi",
		"parent": "altavega", "center": Vector2(1920, -896), "size": Vector2(80, 80), "danger": 1, "power": "off", "temp": -2.0, "zombies": [5, 15], "milestone": "C2", "reserved": true},
	{"id": "universidad", "name": "UNIVERSIDAD", "display": "Universidad", "kind": "poi", "parent": "altavega",
		"center": Vector2(1920, 0), "size": Vector2(220, 170), "danger": 2, "power": "off", "temp": 0.0, "zombies": [15, 30], "milestone": "C2", "reserved": true},
	{"id": "puente_de_hierro", "name": "PUENTE DE HIERRO", "display": "Puente de Hierro", "kind": "poi", "parent": "altavega",
		"center": Vector2(2432, -384), "size": Vector2(200, 70), "danger": 2, "power": "off", "temp": -2.0, "zombies": [20, 40], "milestone": "C1", "reserved": true},
	{"id": "presa_del_cierzo", "name": "PRESA DEL CIERZO", "display": "Presa del Cierzo", "kind": "poi", "parent": "",
		"center": Vector2(2432, -1280), "size": Vector2(220, 100), "danger": 1, "power": "off", "temp": -3.0, "zombies": [5, 15], "milestone": "C2", "reserved": true},
	{"id": "hospital_provincial", "name": "HOSPITAL PROVINCIAL", "display": "Hospital Provincial", "kind": "poi", "parent": "altavega_ensanche",
		"center": Vector2(3200, -768), "size": Vector2(180, 140), "danger": 3, "power": "off", "temp": 0.0, "zombies": [40, 60], "milestone": "C2", "reserved": true},
	{"id": "jefatura_de_policia", "name": "JEFATURA DE POLICÍA", "display": "Jefatura de Policía", "kind": "poi", "parent": "altavega_ensanche",
		"center": Vector2(3072, 128), "size": Vector2(100, 80), "danger": 2, "power": "off", "temp": 0.0, "zombies": [20, 40], "milestone": "C2", "reserved": true},
	{"id": "centro_comercial", "name": "CENTRO COMERCIAL", "display": "Centro Comercial", "kind": "poi", "parent": "altavega_ensanche",
		"center": Vector2(3392, -128), "size": Vector2(276, 148), "danger": 3, "power": "off", "temp": 0.0, "zombies": [30, 50], "milestone": "C2", "reserved": true},
	{"id": "estacion_central", "name": "ESTACIÓN CENTRAL", "display": "Estación Central", "kind": "poi", "parent": "altavega_ensanche",
		"center": Vector2(3712, -256), "size": Vector2(110, 220), "danger": 3, "power": "off", "temp": 0.0, "zombies": [30, 50], "milestone": "C2", "reserved": true},
	{"id": "estadio", "name": "ESTADIO — CAMPO DE REFUGIADOS", "display": "Estadio", "kind": "poi", "parent": "altavega_ensanche",
		"center": Vector2(3456, 384), "size": Vector2(260, 220), "danger": 3, "power": "off", "temp": 0.0, "zombies": [60, 100], "milestone": "C2", "reserved": true},
	{"id": "central_termica", "name": "CENTRAL TÉRMICA DEL ALBO", "display": "Central Térmica del Albo", "kind": "poi", "parent": "poligono_del_albo",
		"center": Vector2(2816, 896), "size": Vector2(220, 170), "danger": 2, "power": "off", "temp": 0.0, "zombies": [10, 20], "milestone": "C2", "reserved": true},
	{"id": "parque_de_combustibles", "name": "PARQUE DE COMBUSTIBLES", "display": "Parque de Combustibles", "kind": "poi", "parent": "poligono_del_albo",
		"center": Vector2(3392, 1216), "size": Vector2(170, 170), "danger": 2, "power": "off", "temp": 0.0, "zombies": [10, 20], "milestone": "C2", "reserved": true},
	{"id": "quimicas_del_albo", "name": "QUÍMICAS DEL ALBO", "display": "Químicas del Albo", "kind": "poi", "parent": "poligono_del_albo",
		"center": Vector2(3200, 1664), "size": Vector2(170, 170), "danger": 2, "power": "off", "temp": 0.0, "zombies": [10, 20], "milestone": "C2", "reserved": true},
	{"id": "estacion_de_mercancias", "name": "ESTACIÓN DE MERCANCÍAS", "display": "Estación de Mercancías", "kind": "poi", "parent": "poligono_del_albo",
		"center": Vector2(3712, 1152), "size": Vector2(100, 320), "danger": 2, "power": "off", "temp": 0.0, "zombies": [8, 15], "milestone": "C3", "reserved": true},
	{"id": "gasolinera_de_la_ronda", "name": "GASOLINERA DE LA RONDA", "display": "Gasolinera de la Ronda", "kind": "poi", "parent": "altavega",
		"center": Vector2(2048, 768), "radius": 70.0, "danger": 1, "power": "off", "temp": 0.0, "zombies": [4, 10], "milestone": "C1", "reserved": true},
	{"id": "gasolinera_a14", "name": "GASOLINERA DE LA A-14", "display": "Gasolinera de la A-14", "kind": "poi", "parent": "",
		"center": Vector2(3968, 1536), "radius": 70.0, "danger": 1, "power": "off", "temp": 0.0, "zombies": [4, 10], "milestone": "C2", "reserved": true},
	{"id": "area_de_servicio_la_vega", "name": "ÁREA DE SERVICIO LA VEGA", "display": "Área de servicio La Vega", "kind": "poi", "parent": "",
		"center": Vector2(3968, 2944), "size": Vector2(140, 100), "danger": 1, "power": "off", "temp": 0.0, "zombies": [8, 15], "milestone": "C3", "reserved": true},
	{"id": "avion_estrellado", "name": "AVIÓN ESTRELLADO", "display": "Avión estrellado", "kind": "poi", "parent": "la_vega",
		"center": Vector2(3840, 3968), "size": Vector2(220, 80), "danger": 2, "power": "off", "temp": -2.0, "zombies": [15, 25], "milestone": "C3", "reserved": true},
	{"id": "tunel_de_pena_roya", "name": "TÚNEL DE PEÑA ROYA", "display": "Túnel de Peña Roya", "kind": "poi", "parent": "",
		"center": Vector2(640, 1476), "size": Vector2(80, 440), "danger": 2, "power": "off", "temp": -4.0, "zombies": [10, 25], "milestone": "C3", "reserved": true},
	{"id": "estacion_de_esqui", "name": "ESTACIÓN DE ESQUÍ PEÑA BLANCA", "display": "Estación de esquí Peña Blanca", "kind": "poi", "parent": "",
		"center": Vector2(-640, 2176), "size": Vector2(400, 300), "danger": 1, "power": "off", "temp": -6.0, "zombies": [8, 20], "milestone": "C3", "reserved": true},
	{"id": "santa_maria_del_puerto", "name": "SANTA MARÍA DEL PUERTO", "display": "Santa María del Puerto", "kind": "village", "parent": "",
		"center": Vector2(-128, 3072), "size": Vector2(170, 170), "danger": 1, "power": "off", "temp": -3.0, "zombies": [3, 8], "milestone": "C3", "reserved": true},
	{"id": "el_gran_atasco", "name": "EL GRAN ATASCO", "display": "El Gran Atasco", "kind": "road", "parent": "",
		"center": Vector2(4096, 1280), "size": Vector2(90, 2176), "danger": 2, "power": "off", "temp": 0.0, "zombies": [20, 40], "milestone": "C2", "reserved": true},
	{"id": "base_aerea", "name": "BASE AÉREA DE LA VEGA", "display": "Base aérea de La Vega", "kind": "poi", "parent": "",
		"center": Vector2(3264, 3520), "size": Vector2(1536, 768), "danger": 3, "power": "generator", "temp": -2.0, "zombies": [40, 60], "milestone": "C3", "reserved": true},
	{"id": "puerto_fluvial", "name": "PUERTO FLUVIAL DEL ALBO", "display": "Puerto fluvial del Albo", "kind": "district", "parent": "altavega",
		"center": Vector2(2432, 1216), "size": Vector2(640, 512), "danger": 1, "power": "off", "temp": -2.0, "zombies": [6, 12], "milestone": "C2", "reserved": true},
	# --- W1: Altavega's districts (tier 0; the city itself is tier 1)
	{"id": "altavega_las_torres", "name": "ALTAVEGA — LAS TORRES", "display": "Las Torres", "kind": "district", "parent": "altavega",
		"center": Vector2(2688, -384), "size": Vector2(384, 640), "danger": 2, "power": "off", "temp": 0.0, "zombies": [20, 40], "milestone": "C1", "reserved": true},
	{"id": "altavega_casco_viejo", "name": "ALTAVEGA — CASCO VIEJO", "display": "Casco viejo", "kind": "district", "parent": "altavega",
		"center": Vector2(2048, -512), "size": Vector2(640, 896), "danger": 2, "power": "off", "temp": 0.0, "zombies": [10, 20], "milestone": "C1", "reserved": true},
	{"id": "barriada_de_san_lazaro", "name": "BARRIADA DE SAN LÁZARO", "display": "Barriada de San Lázaro", "kind": "district", "parent": "altavega",
		"center": Vector2(2048, 256), "size": Vector2(640, 640), "danger": 2, "power": "off", "temp": 0.0, "zombies": [10, 20], "milestone": "C1", "reserved": true},
	{"id": "altavega_ensanche", "name": "ALTAVEGA — ENSANCHE", "display": "Ensanche", "kind": "district", "parent": "altavega",
		"center": Vector2(3072, -192), "size": Vector2(1152, 1536), "danger": 2, "power": "off", "temp": 0.0, "zombies": [12, 25], "milestone": "C1", "reserved": true},
	{"id": "urbanizaciones_del_norte", "name": "URBANIZACIONES DEL NORTE", "display": "Urbanizaciones del norte", "kind": "district", "parent": "altavega",
		"center": Vector2(2048, -1216), "size": Vector2(640, 256), "danger": 1, "power": "off", "temp": -1.0, "zombies": [3, 8], "milestone": "C3", "reserved": true},
	{"id": "urbanizaciones_del_norte_este", "name": "URBANIZACIONES DEL NORTE", "display": "Urbanizaciones del norte", "kind": "district", "parent": "altavega",
		"center": Vector2(3136, -1216), "size": Vector2(1024, 256), "danger": 1, "power": "off", "temp": -1.0, "zombies": [3, 8], "milestone": "C3", "reserved": true},
	{"id": "urbanizaciones_del_este", "name": "URBANIZACIONES DEL ESTE", "display": "Urbanizaciones del este", "kind": "district", "parent": "altavega",
		"center": Vector2(3904, -192), "size": Vector2(256, 1536), "danger": 1, "power": "off", "temp": -1.0, "zombies": [3, 8], "milestone": "C3", "reserved": true},
	{"id": "poligono_del_albo", "name": "POLÍGONO DEL ALBO", "display": "Polígono del Albo", "kind": "district", "parent": "altavega",
		"center": Vector2(3072, 1344), "size": Vector2(1152, 1280), "danger": 1, "power": "off", "temp": 0.0, "zombies": [4, 10], "milestone": "C2", "reserved": true},
	{"id": "vega_baja", "name": "VEGA BAJA", "display": "Vega Baja", "kind": "town", "parent": "",
		"center": Vector2(1984, 2112), "size": Vector2(512, 512), "danger": 1, "power": "off", "temp": 0.0, "zombies": [3, 8], "milestone": "C3", "reserved": true},
	{"id": "urbanizacion_los_alamos", "name": "URBANIZACIÓN LOS ÁLAMOS", "display": "Urbanización Los Álamos", "kind": "town", "parent": "",
		"center": Vector2(3136, 2432), "size": Vector2(1024, 896), "danger": 1, "power": "off", "temp": 0.0, "zombies": [3, 8], "milestone": "C3", "reserved": true},
	{"id": "desfiladero_de_pena_roya", "name": "DESFILADERO DE PEÑA ROYA", "display": "Desfiladero de Peña Roya", "kind": "natural", "parent": "sierra_de_pena_blanca",
		"center": Vector2(640, 2305), "size": Vector2(384, 1030), "danger": 1, "power": "", "temp": -4.0, "zombies": [1, 4], "milestone": "E1", "reserved": true},
	# --- W1: water bodies (exact shape in WATER; the rect only bounds them)
	{"id": "rio_albo", "name": "RÍO ALBO", "display": "Río Albo", "kind": "natural", "parent": "", "water": "rio_albo",
		"center": Vector2(2432, 1700), "size": Vector2(260, 6000), "danger": 1, "power": "", "temp": -3.0, "zombies": [0, 1], "milestone": "E1", "reserved": false},
	{"id": "embalse_del_cierzo", "name": "EMBALSE DEL CIERZO", "display": "Embalse del Cierzo", "kind": "natural", "parent": "", "water": "embalse_del_cierzo",
		"center": Vector2(2432, -1500), "size": Vector2(300, 360), "danger": 1, "power": "", "temp": -4.0, "zombies": [0, 1], "milestone": "E1", "reserved": false},
	{"id": "ibon_helado", "name": "IBÓN HELADO", "display": "Ibón helado", "kind": "natural", "parent": "", "water": "ibon_helado",
		"center": Vector2(-1024, 3072), "size": Vector2(420, 420), "danger": 1, "power": "", "temp": -5.0, "zombies": [0, 1], "milestone": "E1", "reserved": false},
	# --- W1: broad areas (tier 1, after the water and the named roads)
	{"id": "altavega", "name": "ALTAVEGA", "display": "Altavega", "kind": "city", "parent": "", "tier": 1,
		"center": Vector2(2880, 352), "size": Vector2(2304, 3392), "danger": 2, "power": "off", "temp": 0.0, "zombies": [6, 12], "milestone": "C1", "reserved": true},
	{"id": "sierra_del_cierzo", "name": "SIERRA DEL CIERZO", "display": "Sierra del Cierzo", "kind": "natural", "parent": "", "tier": 1,
		"center": Vector2(1488, 0), "size": Vector2(480, 2944), "danger": 1, "power": "", "temp": -6.0, "zombies": [0, 1], "milestone": "W1", "reserved": false},
	{"id": "sierra_de_pena_blanca", "name": "SIERRA DE PEÑA BLANCA", "display": "Sierra de Peña Blanca", "kind": "natural", "parent": "", "tier": 1,
		"center": Vector2(-32, 1808), "size": Vector2(2880, 1120), "danger": 1, "power": "", "temp": -6.0, "zombies": [0, 1], "milestone": "W1", "reserved": false},
	{"id": "la_vega", "name": "LA VEGA", "display": "La Vega", "kind": "natural", "parent": "", "tier": 1,
		"center": Vector2(1344, 3680), "size": Vector2(5632, 960), "danger": 1, "power": "", "temp": -1.0, "zombies": [1, 4], "milestone": "C3", "reserved": false},
]
## LocationInfo data of the named roads (the banner of a chunk within 32 m of their bed; HeightFunction.named_road_at).
const ROAD_REGIONS := {
	"N-140": {"id": "n140", "display": "N‑140", "kind": "road", "danger": 1, "power": "", "temp": 0.0, "zombies": [1, 4], "milestone": "M3"},
	"CARRETERA DEL PUERTO": {"id": "carretera_del_puerto", "display": "Carretera del Puerto", "kind": "road", "danger": 1, "power": "", "temp": -3.0, "zombies": [1, 4], "milestone": "W1"},
	"GRAN VÍA": {"id": "gran_via", "display": "Gran Vía", "kind": "road", "danger": 2, "power": "off", "temp": 0.0, "zombies": [4, 10], "milestone": "C1"},
	"RONDA NORTE": {"id": "ronda_norte", "display": "Ronda Norte", "kind": "road", "danger": 2, "power": "off", "temp": 0.0, "zombies": [4, 10], "milestone": "C1"},
	"RONDA SUR": {"id": "ronda_sur", "display": "Ronda Sur", "kind": "road", "danger": 2, "power": "off", "temp": 0.0, "zombies": [4, 10], "milestone": "C1"},
	"AUTOVÍA A-14": {"id": "autovia_a14", "display": "Autovía A‑14", "kind": "road", "danger": 1, "power": "", "temp": -1.0, "zombies": [2, 6], "milestone": "C2"},
	"FERROCARRIL DEL ALBO": {"id": "ferrocarril_del_albo", "display": "Ferrocarril del Albo", "kind": "road", "danger": 1, "power": "", "temp": -1.0, "zombies": [2, 6], "milestone": "C3"},
}
const REGION_LAKE := "LAGO DE LAS ÁNIMAS"
const REGION_ROAD := "N-140"
const REGION_BORDER := "LAS CUMBRES"
const REGION_HIGH_FOREST := "PINOS ALTOS"
const REGION_FOREST := "BOSQUE PROFUNDO"
## The M3 valley square (PINOS ALTOS only exists in it: Chebyshev > 900 m from the clearing, inside ±1248 m).
const VALLEY_SQUARE := 1248.0

# ------------------------------------------------------------------ pads
## Terrain pads (flattened; scatter kept clear). Circle: "center" + "radius" (flat inside 0.6 r, blended out to r).
## Rect (W1): "center" + "size" (flat inside, blended over "blend" m outside, default 16). Height: the natural
## ground at the centre, or "h" (absolute metres). `model` = static prop placed on the pad by the chunk that
## contains `center` (Assets.spawn_model → placeholder until the art exists); yaw in degrees (+Z front).
## "reserved" (W1): flat ground kept now for a POI a later milestone builds, so the terrain never changes under it.
const PADS := [
	{"id": "cabin_small_1", "center": Vector2(-512, -300), "radius": 12.0, "model": "cabin_small", "yaw": 160.0},
	{"id": "cabin_small_2", "center": Vector2(400, -160), "radius": 12.0, "model": "cabin_small", "yaw": -110.0},
	{"id": "cabin_small_3", "center": Vector2(-160, 720), "radius": 12.0, "model": "cabin_small", "yaw": 20.0},
	{"id": "cabin_small_4", "center": Vector2(880, 330), "radius": 12.0, "model": "cabin_small", "yaw": 75.0},
	{"id": "lookout_tower", "center": Vector2(256, 896), "radius": 10.0, "model": "lookout_tower", "yaw": 30.0},
	{"id": "camp_1", "center": Vector2(150, 60), "radius": 7.0, "model": "campsite_remains", "yaw": 200.0},
	{"id": "camp_2", "center": Vector2(230, -250), "radius": 7.0, "model": "campsite_remains", "yaw": 40.0},
	{"id": "camp_3", "center": Vector2(-340, -150), "radius": 7.0, "model": "campsite_remains", "yaw": 300.0},
	{"id": "camp_4", "center": Vector2(170, 400), "radius": 7.0, "model": "campsite_remains", "yaw": 120.0},
	{"id": "camp_5", "center": Vector2(-620, -120), "radius": 7.0, "model": "campsite_remains", "yaw": 250.0},
	{"id": "camp_6", "center": Vector2(470, 920), "radius": 7.0, "model": "campsite_remains", "yaw": 10.0},
	# future POIs (M6/M9a/M10): flat ground reserved now so the terrain does not change under them later
	{"id": "dam", "center": Vector2(-880, 20), "radius": 30.0, "model": ""},
	{"id": "repeater", "center": Vector2(-1152, -128), "radius": 22.0, "model": ""},
	{"id": "rest_area", "center": Vector2(610, 128), "radius": 40.0, "model": ""},
	{"id": "gas_north", "center": Vector2(610, -384), "radius": 30.0, "model": ""},
	{"id": "gas_south", "center": Vector2(610, 640), "radius": 30.0, "model": ""},
	{"id": "checkpoint", "center": Vector2(640, -1152), "radius": 45.0, "model": ""},
	# --- W1 (doc 09 §4.3): tunnel portals (art T2: assets/models/world/tunnel_portal[_collapsed].glb; the road enters
	# toward the model's −Z, its `carve` rect x ∈ [−6.5, 6.5], z ∈ [−12.2, 0.3] must stay at road level). The pad is
	# the carve rect grown by 1 m sideways, 1.3 m deep and 4 m of apron in front, level with the ground at the mouth
	# ("h_at"); `model_at` = the mouth (the model's origin). The A‑14 (22 m) gets one 7 m portal per carriageway.
	{"id": "tunel_pena_roya_n", "center": Vector2(632, 1296.75), "size": Vector2(15, 17.5), "h_at": Vector2(632, 1292), "blend": 8.0,
		"model_at": Vector2(632, 1292), "model": "tunnel_portal_collapsed", "yaw": 180.0},
	{"id": "tunel_pena_roya_s", "center": Vector2(640, 1671.25), "size": Vector2(15, 17.5), "h_at": Vector2(640, 1676), "blend": 8.0,
		"model_at": Vector2(640, 1676), "model": "tunnel_portal", "yaw": 0.0},
	{"id": "tunel_a14_n_e", "center": Vector2(4096, -1424.75), "size": Vector2(30, 17.5), "h_at": Vector2(4096, -1420), "blend": 8.0,
		"model_at": Vector2(4103.5, -1420), "model": "tunnel_portal", "yaw": 0.0},
	{"id": "tunel_a14_n_w", "center": Vector2(4088.5, -1420), "radius": 1.0, "h_at": Vector2(4096, -1420), "model_at": Vector2(4088.5, -1420), "model": "tunnel_portal", "yaw": 0.0},
	{"id": "tunel_a14_s_e", "center": Vector2(4096, 4396.75), "size": Vector2(30, 17.5), "h_at": Vector2(4096, 4392), "blend": 8.0,
		"model_at": Vector2(4103.5, 4392), "model": "tunnel_portal", "yaw": 180.0},
	{"id": "tunel_a14_s_w", "center": Vector2(4088.5, 4392), "radius": 1.0, "h_at": Vector2(4096, 4392), "model_at": Vector2(4088.5, 4392), "model": "tunnel_portal", "yaw": 180.0},
	{"id": "tunel_tren_n", "center": Vector2(3712, -1424.75), "size": Vector2(15, 17.5), "h_at": Vector2(3712, -1420), "blend": 8.0,
		"model_at": Vector2(3712, -1420), "model": "tunnel_portal", "yaw": 0.0},
	{"id": "tunel_tren_o", "center": Vector2(-1426.75, 2560), "size": Vector2(17.5, 15), "h_at": Vector2(-1422, 2560), "blend": 8.0,
		"model_at": Vector2(-1422, 2560), "model": "tunnel_portal", "yaw": 90.0},
	# --- W1 reserved pads for the hero POIs and places of C1–C3 (terrain only; nothing is built on them yet)
	{"id": "control_del_puerto", "center": Vector2(1536, -384), "size": Vector2(90, 70), "model": "", "reserved": true, "milestone": "C1"},
	{"id": "presa_del_cierzo", "center": Vector2(2432, -1284), "size": Vector2(210, 70), "h": 16.0, "blend": 10.0, "model": "", "reserved": true, "milestone": "C2"},
	{"id": "catedral", "center": Vector2(2176, -512), "size": Vector2(100, 70), "model": "", "reserved": true, "milestone": "C2"},
	{"id": "torre_telecomunicaciones", "center": Vector2(1920, -896), "size": Vector2(64, 64), "model": "", "reserved": true, "milestone": "C2"},
	{"id": "universidad", "center": Vector2(1920, 0), "size": Vector2(200, 150), "model": "", "reserved": true, "milestone": "C2"},
	{"id": "hospital_provincial", "center": Vector2(3200, -768), "size": Vector2(160, 120), "model": "", "reserved": true, "milestone": "C2"},
	{"id": "jefatura_de_policia", "center": Vector2(3072, 128), "size": Vector2(80, 60), "model": "", "reserved": true, "milestone": "C2"},
	{"id": "centro_comercial", "center": Vector2(3392, -128), "size": Vector2(256, 128), "model": "", "reserved": true, "milestone": "C2"},
	{"id": "estacion_central", "center": Vector2(3712, -256), "size": Vector2(90, 200), "model": "", "reserved": true, "milestone": "C2"},
	{"id": "estadio", "center": Vector2(3456, 384), "size": Vector2(240, 200), "model": "", "reserved": true, "milestone": "C2"},
	{"id": "central_termica", "center": Vector2(2816, 896), "size": Vector2(200, 150), "model": "", "reserved": true, "milestone": "C2"},
	{"id": "parque_de_combustibles", "center": Vector2(3392, 1216), "size": Vector2(150, 150), "model": "", "reserved": true, "milestone": "C2"},
	{"id": "quimicas_del_albo", "center": Vector2(3200, 1664), "size": Vector2(150, 150), "model": "", "reserved": true, "milestone": "C2"},
	{"id": "estacion_de_mercancias", "center": Vector2(3712, 1152), "size": Vector2(80, 300), "model": "", "reserved": true, "milestone": "C3"},
	{"id": "gasolinera_de_la_ronda", "center": Vector2(2048, 768), "radius": 40.0, "model": "", "reserved": true, "milestone": "C1"},
	{"id": "gasolinera_a14", "center": Vector2(4010, 1536), "radius": 40.0, "model": "", "reserved": true, "milestone": "C2"},
	{"id": "area_de_servicio_la_vega", "center": Vector2(3968, 2980), "size": Vector2(120, 80), "model": "", "reserved": true, "milestone": "C3"},
	{"id": "puerta_base_aerea", "center": Vector2(2688, 3072), "size": Vector2(80, 60), "model": "", "reserved": true, "milestone": "C3"},
	{"id": "pista_base_aerea", "center": Vector2(3328, 3584), "size": Vector2(1500, 70), "model": "", "reserved": true, "milestone": "C3"},
	{"id": "avion_estrellado", "center": Vector2(3840, 3968), "size": Vector2(200, 60), "model": "", "reserved": true, "milestone": "C3"},
	{"id": "estacion_de_esqui", "center": Vector2(-640, 2200), "size": Vector2(200, 140), "model": "", "reserved": true, "milestone": "C3"},
	{"id": "santa_maria_del_puerto", "center": Vector2(-128, 3072), "size": Vector2(150, 150), "model": "", "reserved": true, "milestone": "C3"},
	{"id": "granja_vega_1", "center": Vector2(1920, 3328), "radius": 30.0, "model": "", "reserved": true, "milestone": "C3"},
	{"id": "granja_vega_2", "center": Vector2(1024, 3456), "radius": 30.0, "model": "", "reserved": true, "milestone": "C3"},
	{"id": "granja_vega_3", "center": Vector2(-512, 3712), "radius": 30.0, "model": "", "reserved": true, "milestone": "C3"},
	{"id": "granja_vega_4", "center": Vector2(1792, 3968), "radius": 30.0, "model": "", "reserved": true, "milestone": "C3"},
	{"id": "granja_vega_5", "center": Vector2(3328, 4096), "radius": 30.0, "model": "", "reserved": true, "milestone": "C3"},
]
## Default blend margin (m) of a rect pad.
const PAD_BLEND := 16.0
## PADS[0 … M3_PAD_COUNT − 1] are the M3 valley's; the W1 roads flatten their profile over the W1 pads only.
const M3_PAD_COUNT := 17

## Lago de las Ánimas: smooth union of discs (fast signed distance, identical everywhere). Flat, safe ice (M3).
const LAKE_DISCS := [
	[Vector2(-780, 340), 250.0],
	[Vector2(-660, 500), 190.0],
	[Vector2(-910, 460), 160.0],
	[Vector2(-720, 660), 120.0],
]
const LAKE_SMOOTH := 70.0
## Lake ice level (absolute metres; the clearing ground is ≈ 0).
const LAKE_LEVEL := -5.0
const LAKE_BBOX := Rect2(-1090, 80, 640, 720)

# ------------------------------------------------------------------ water (W1)
## Frozen water bodies of W1, flat and safe until E1 (thin ice): the ground inside is exactly `level` with the ice
## surface mask, like the Lago de las Ánimas. Shapes: "points" + "hw" (a river: distance to the polyline − half
## width), "box" (Rect2, rounded by "round"), "discs" (smooth union, like LAKE_DISCS). Bodies with the same `group`
## are merged (min of the signed distances): the Albo and its dársena are one sheet of ice.
const RIVER_LEVEL := -6.0
const WATER := [
	{"id": "rio_albo", "group": 1, "level": RIVER_LEVEL, "hw": 64.0, "points": [
		Vector2(2432, -1228), Vector2(2440, -1100), Vector2(2426, -900), Vector2(2436, -700), Vector2(2432, -480),
		Vector2(2432, -290), Vector2(2440, -80), Vector2(2428, 160), Vector2(2432, 420), Vector2(2434, 640),
		Vector2(2432, 900), Vector2(2432, 1216), Vector2(2432, 1520), Vector2(2422, 1800), Vector2(2440, 2100),
		Vector2(2432, 2400), Vector2(2432, 2720), Vector2(2426, 2944), Vector2(2436, 3200), Vector2(2428, 3500),
		Vector2(2436, 3800), Vector2(2430, 4100), Vector2(2432, 4400), Vector2(2432, 4700)]},
	{"id": "darsena", "group": 1, "level": RIVER_LEVEL, "box": Rect2(2304, 976, 256, 480), "round": 28.0},
	{"id": "embalse_del_cierzo", "group": 2, "level": 14.0, "box": Rect2(2290, -1720, 284, 400), "round": 60.0},
	{"id": "ibon_helado", "group": 3, "level": 7.0, "discs": [[Vector2(-1024, 3072), 150.0], [Vector2(-930, 2990), 95.0],
		[Vector2(-1100, 3160), 105.0]], "smooth": 60.0},
]


## World centre of an ASCII character.
static func char_center(col: int, row: int) -> Vector2:
	return Vector2(float(col - 12) * CELL, float(row - 12) * CELL)


## ASCII character at a world position ("^" outside the map).
static func char_at(x: float, z: float) -> String:
	var col := int(round(x / CELL)) + 12
	var row := int(round(z / CELL)) + 12
	if row < 0 or row >= ASCII.size() or col < 0 or col >= COLS:
		return "^"
	var line: String = ASCII[row]
	return line[col] if col < line.length() else "#"


## Signed distance to the big lake's shore (m): < 0 inside.
static func lake_sdf(x: float, z: float) -> float:
	var d := INF
	for disc in LAKE_DISCS:
		var c: Vector2 = disc[0]
		var r: float = disc[1]
		var di := Vector2(x - c.x, z - c.y).length() - r
		if d == INF:
			d = di
		else:
			# polynomial smooth minimum (organic shore where the discs meet)
			var h := clampf(0.5 + 0.5 * (di - d) / LAKE_SMOOTH, 0.0, 1.0)
			d = lerpf(di, d, h) - LAKE_SMOOTH * h * (1.0 - h)
	return d


# ------------------------------------------------------------------ water queries (W1)
## Bounding rect of a water body (its exact shape is inside).
static func water_bbox(i: int) -> Rect2:
	var w: Dictionary = WATER[i]
	if w.has("box"):
		return w["box"]
	var r := Rect2()
	var first := true
	if w.has("points"):
		for p: Vector2 in w["points"]:
			r = Rect2(p, Vector2.ZERO) if first else r.expand(p)
			first = false
		return r.grow(float(w["hw"]))
	for disc in w["discs"]:
		var dr := Rect2(disc[0], Vector2.ZERO).grow(float(disc[1]))
		r = dr if first else r.merge(dr)
		first = false
	return r


## Signed distance (m) to the shore of water body `i` (< 0 on the ice).
static func water_body_sdf(i: int, x: float, z: float) -> float:
	var w: Dictionary = WATER[i]
	if w.has("points"):
		var pts: Array = w["points"]
		var best := INF
		for k in pts.size() - 1:
			var a: Vector2 = pts[k]
			var b: Vector2 = pts[k + 1]
			var ab := b - a
			var t := clampf(((x - a.x) * ab.x + (z - a.y) * ab.y) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
			var dx := a.x + ab.x * t - x
			var dz := a.y + ab.y * t - z
			best = minf(best, dx * dx + dz * dz)
		return sqrt(best) - float(w["hw"])
	if w.has("box"):
		var box: Rect2 = w["box"]
		var rr := float(w.get("round", 0.0))
		var c := box.get_center()
		var h := box.size * 0.5 - Vector2(rr, rr)
		var qx := absf(x - c.x) - h.x
		var qz := absf(z - c.y) - h.y
		return Vector2(maxf(qx, 0.0), maxf(qz, 0.0)).length() + minf(maxf(qx, qz), 0.0) - rr
	var sm := float(w.get("smooth", 60.0))
	var d := INF
	for disc in w["discs"]:
		var di := Vector2(x, z).distance_to(disc[0]) - float(disc[1])
		if d == INF:
			d = di
		else:
			var hh := clampf(0.5 + 0.5 * (di - d) / sm, 0.0, 1.0)
			d = lerpf(di, d, hh) - sm * hh * (1.0 - hh)
	return d


## Nearest W1 water body at a point: Vector3(signed distance, ice level, body index) (sdf INF when none within
## `reach` m of its bounding rect).
static func water_at(x: float, z: float, reach: float = 80.0) -> Vector3:
	var best := Vector3(INF, 0.0, -1.0)
	for i in WATER.size():
		if not water_bbox(i).grow(reach).has_point(Vector2(x, z)):
			continue
		var d := water_body_sdf(i, x, z)
		if d < best.x:
			best = Vector3(d, float(WATER[i]["level"]), float(i))
	return best


static func water_index(id: String) -> int:
	for i in WATER.size():
		if str(WATER[i]["id"]) == id:
			return i
	return -1


# ------------------------------------------------------------------ pads queries (W1)
## Signed distance (m) to the flat part of pad `i` (< 0 inside; circles: the whole radius) and its blend width.
static func pad_sdf(i: int, x: float, z: float) -> float:
	var pad: Dictionary = PADS[i]
	var c: Vector2 = pad["center"]
	if pad.has("size"):
		var h: Vector2 = (pad["size"] as Vector2) * 0.5
		var qx := absf(x - c.x) - h.x
		var qz := absf(z - c.y) - h.y
		return Vector2(maxf(qx, 0.0), maxf(qz, 0.0)).length() + minf(maxf(qx, qz), 0.0)
	return Vector2(x, z).distance_to(c) - float(pad["radius"])


## Radius (m) around a pad's centre that contains all of its influence (flat part + blend).
static func pad_reach(i: int) -> float:
	var pad: Dictionary = PADS[i]
	if pad.has("size"):
		return (pad["size"] as Vector2).length() * 0.5 + float(pad.get("blend", PAD_BLEND))
	return float(pad["radius"])


# ------------------------------------------------------------------ regions queries
## Region name of a chunk (evaluated at its centre; RegionTracker adds the fine zones inside the clearing).
## `road` = the banner name of the named road within 32 m of the centre ("" none; HeightFunction.named_road_at).
static func region_of_chunk(cx: int, cz: int, road: String = "") -> String:
	var c := WorldConst.chunk_center(cx, cz)
	return region_at(c.x, c.z, road)


## True when region record `r` contains (x, z) (circle or rect; water records by their exact shape).
static func region_has(r: Dictionary, x: float, z: float) -> bool:
	if r.has("water"):
		return water_body_sdf(water_index(str(r["water"])), x, z) < 0.0
	var p := Vector2(x, z)
	if r.has("size"):
		return Rect2((r["center"] as Vector2) - (r["size"] as Vector2) * 0.5, r["size"]).has_point(p)
	return p.distance_to(r["center"]) <= float(r["radius"])


## Region banner name at a point. `road` = name of the named road there (see region_of_chunk).
static func region_at(x: float, z: float, road: String = "") -> String:
	# 1. places (tier 0)
	for r: Dictionary in REGIONS:
		if int(r.get("tier", 0)) != 0 or r.has("water"):
			continue
		if region_has(r, x, z):
			return r["name"]
	# 2. water
	if lake_sdf(x, z) < 40.0:
		return REGION_LAKE
	for r: Dictionary in REGIONS:
		if r.has("water") and Rect2((r["center"] as Vector2) - (r["size"] as Vector2) * 0.5, r["size"]).has_point(Vector2(x, z)) and region_has(r, x, z):
			return r["name"]
	# 3. named roads
	if road != "":
		return road
	# 4. broad areas (tier 1)
	for r: Dictionary in REGIONS:
		if int(r.get("tier", 0)) == 1 and region_has(r, x, z):
			return r["name"]
	# 5. the border ring, the valley's high forest, the forest
	if WorldConst.wall_distance(x, z) < WorldConst.BORDER_REGION:
		return REGION_BORDER
	var cheb := maxf(absf(x), absf(z))
	if cheb > 900.0 and x < VALLEY_SQUARE and z < VALLEY_SQUARE:
		return REGION_HIGH_FOREST
	return REGION_FOREST


## The region record (W1 fields for LocationInfo) of a banner name ({} for the valley's plain names).
static func region_record(region_name: String) -> Dictionary:
	for r: Dictionary in REGIONS:
		if str(r["name"]) == region_name:
			return r
	return {}


## Region record by id ({} when unknown).
static func region_by_id(id: String) -> Dictionary:
	for r: Dictionary in REGIONS:
		if str(r.get("id", "")) == id:
			return r
	return {}


## Region records containing (x, z), deepest first (a POI, its district, the city…): the hierarchy LocationInfo /
## ZoneTracker (H2) walks. Only W1 records carry `parent`; water and broad areas are included when they match.
static func regions_containing(x: float, z: float) -> Array:
	var out: Array = []
	for r: Dictionary in REGIONS:
		if region_has(r, x, z):
			out.append(r)
	return out


## Signed depth (m) inside the natural "fn" areas of LocationInfo (Locations.depth): > 0 inside.
##   border       the ring of WorldConst.BORDER_REGION m inside the nearest wall (LAS CUMBRES)
##   high_forest  the valley's PINOS ALTOS (Chebyshev > 900 m from the clearing, inside the valley square)
##   water:<id>   a W1 water body
static func natural_depth(fn: String, x: float, z: float) -> float:
	if fn == "border":
		return WorldConst.BORDER_REGION - WorldConst.wall_distance(x, z)
	if fn == "high_forest":
		return minf(maxf(absf(x), absf(z)) - 900.0, minf(VALLEY_SQUARE - x, VALLEY_SQUARE - z))
	if fn.begins_with("water:"):
		var i := water_index(fn.substr(6))
		return -water_body_sdf(i, x, z) if i >= 0 else -INF
	return -INF
