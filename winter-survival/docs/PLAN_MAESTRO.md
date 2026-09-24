# VENTISCA — PLAN MAESTRO (v2: mundo abierto, zombis, co‑op 1–4)

> **Punto de entrada** de la documentación v2. De aquí cuelgan `docs/v2/GDD_MUNDO_ABIERTO.md` (diseño), `docs/v2/ARQUITECTURA_V2.md` (técnica) y `docs/v2/ASSET_SPEC_V2.md` (contrato de arte). Los cuatro documentos son coherentes entre sí: **si algo cambia en uno, cambia en los otros**.
>
> Los documentos del slice (`docs/GDD.md`, `ARCHITECTURE.md`, `ASSET_SPEC.md`) siguen describiendo el código que existe hoy; quedan como referencia de "estado inicial" y se retiran cuando el hito M2 los deje obsoletos.
>
> Fecha: 24‑sep‑2026. Motor **Godot 4.7.2** (GDScript tipado). Arte **Blender 5.0.1 (bpy)**. Equipo: planificación y código = agentes **Fable**; modelado, rigs, animación y kits = agentes **Opus**.

---

## 0. Resumen en una página

- **Qué hacemos**: convertir el slice VENTISCA (claro nevado de 160 × 160 m, un jugador, lobos) en un **juego de supervivencia post‑apocalíptico invernal de mundo abierto** (3 × 3 km) con **pueblos, aldeas, coches, armas y zombis**, jugable **solo o en cooperativo PvE de 1–4** en **servidores dedicados autoalojados**, con PvP y fuego amigo como opciones del servidor.
- **Cómo se ve**: la misma cámara alta tipo isométrica de la referencia (apuntado con ratón, interiores en corte), el mismo low‑poly de colores planos sobre nieve azulada.
- **Decisiones fijadas por el usuario (vinculantes)**: cámara A (alta, seguimiento, corte de interiores); co‑op PvE 1–4 con PvP/fuego amigo por configuración; servidores dedicados propios; Godot 4.7.2; Blender 5.0.1; Fable = código, Opus = arte.
- **Las cuatro decisiones técnicas que ordenan todo lo demás** (detalle en §3): (1) servidor dedicado autoritativo siempre, incluso en solitario; (2) mundo determinista por semilla en chunks de 64 m + solo *deltas* persistidos en SQLite; (3) IA de zombis por niveles (LOD) en el servidor con replicación propia comprimida; (4) arte con esqueleto humanoide único + color de vértice + kit modular fusionado por grupos de corte.
- **Camino**: 13 pases (M0…M10, con M6 y M9 partidos), cada uno entregable por **1 agente Fable + 1 agente Opus** y cada uno **jugable y probado automáticamente**. Lo arriesgado va primero: red (M1–M2) y mundo por chunks (M3) antes que contenido.

---

## 1. Visión

### 1.1 Nombre: se mantiene **VENTISCA**

Se conserva porque (a) ya es la identidad del proyecto, el repo y los tests; (b) es una sola palabra en español, sin traducción necesaria; (c) en v2 la **Gran Ventisca** pasa a ser el evento periódico que estructura la partida (la "luna de sangre" del juego), así que el título nombra literalmente el momento más importante del diseño. Cambia el lema:

> **VENTISCA** — *El frío no perdona. Los muertos tampoco.*

### 1.2 Pitch

Despiertas en la casa de un cazador, en un claro rodeado de pinos. La estufa aún está tibia. A un kilómetro y medio, por la carretera nacional, están Valdenieve y sus aldeas: casas con armarios llenos de ropa, gasolineras con bidones, una comisaría con armas… y calles llenas de muertos que el frío ha dejado dormidos bajo la nieve. Cada expedición es la misma pregunta: **¿me queda calor para llegar, saquear en silencio y volver antes de la noche?** Cada disparo es un préstamo que se paga en zombis. Cada siete días llega la Gran Ventisca y con ella la horda. Solo o con tres amigos, en vuestro propio servidor: reclamad una casa, arreglad un coche, reparad la torre de radio y llegad a la evacuación… o quedaos.

### 1.3 Pilares (en este orden de prioridad)

1. **Legible desde arriba.** Siluetas, anillos, huellas, humo, luz y sonido posicionado son información. Todo peligro se lee a 20 m con la cámara a 22 m.
2. **El frío decide el ritmo; los zombis son el obstáculo.** Cada bucle empieza y termina en una fuente de calor. Los zombis son lo que hay entre dos fuentes de calor. El frío también congela a los zombis: el mundo es un campo de minas dormido.
3. **Ruido = préstamo.** Toda acción tiene un radio de ruido visible (anillo). Las armas de fuego resuelven el presente y compran problemas futuros.
4. **Nunca separes al grupo, pero permite separarse.** Los especiales castigan al lobo solitario; el mundo abierto y los *pings* permiten dividirse para saquear.
5. **Persistencia honesta.** Lo que matas no vuelve pronto; lo que rompes queda roto; el cadáver guarda tu mochila; la base se enfría si nadie alimenta la estufa. Un mundo, un servidor, sin "invitados".
6. **Un director, no un guion.** Un algoritmo reparte la presión entre frío y zombis con 30–45 s de alivio garantizado tras cada pico.

---

## 2. Referencias que mandan

- **Visual**: las cuatro capturas de referencia (casa azul‑gris con porche en corte, camioneta, señal, cabaña en A, pinos en niveles con nieve, HUD de tres anillos + reloj + panel de misiones + barra de 10 huecos + categorías a la izquierda). v2 **extiende** ese HUD, no lo sustituye (GDD v2 §13).
- **Diseño**: Project Zomboid (ruido/visión, habilidades por uso), Left 4 Dead (director, especiales, derribado), The Long Dark / DayZ Sakhal (frío legible, ropa por capas, humedad, hielo), 7 Days to Die (evento periódico anunciado, escalado por jugadores), State of Decay 2 (especiales legibles, reclamar edificios), Days Gone (horda migratoria con rutina y rastro), Valheim (mojado anula abrigo, *corpse run*, servidor dedicado entre amigos), Deep Rock Galactic (fuego amigo escalado).
- **Técnica**: pruebas de concepto **superadas** en `prototypes/netpoc/` (servidor headless ENet + 4 clientes: auth, spawn, sync 30 Hz, interest management, RPC validado, chat, PvP bloqueado por config, soak 75 s, ≈ 3.5 kB/s por cliente) y `prototypes/animpoc/` (humanoide esquelético bpy 23 huesos, retarget, BlendSpace + capa de torso, ragdoll, 40 personajes: 960 → 120 draw calls con color de vértice).

---

## 3. Decisiones finales (tabla maestra)

La columna **Fuente** apunta a la sección de investigación (`docs/research/0N_*.md`) o al PoC de donde sale la cifra. Donde dos documentos discrepaban, la columna **Por qué** explica la elección. Estas decisiones son vinculantes para todos los pases; cambiarlas exige actualizar esta tabla.

### 3.1 Conflictos resueltos explícitamente

| # | Tema | Decisión | Por qué (conflicto resuelto) | Fuente |
|---|---|---|---|---|
| C1 | **Eje "frente" de los modelos** | **Frente = −Y Blender = +Z Godot (`Vector3.MODEL_FRONT`)** para *todo* asset con frente en v2 (personajes, zombis, vehículos, armas, edificios, muebles). El slice usaba +Y Blender → −Z Godot. **Migración**: como los 33 assets son 100 % generados por script, se regeneran en M0 con `lib.FRONT = -Y` (rotación de 180° en `to_object`) y el código pasa a usar `basis.z` / `look_at(target, UP, true)`. No se mantienen dos convenciones. | glTF 2.0 define el frente en +Z; `SkeletonProfileHumanoid` mira a +Z; el *Rest Fixer* del retarget y las librerías CC0 asumen +Z; `VehicleBody3D` usa `MODEL_FRONT`. Mezclar convenciones en personajes rompe el retarget. El coste de regenerar 33 assets por script es una tarde; el coste de arrastrar dos convenciones es permanente. | 04 §0, §3, §4.1; PoC anim |
| C2 | **Materiales** | **Color de vértice `COLOR_0` (paleta horneada) + 1 material `palette_vcol` por malla**. Excepciones con nombre (materiales aparte): `window`, `glass`, `ember`, `ice_clear`, `emissive_*`. En Godot, `Assets.spawn_model` sustituye `palette_vcol` por **un único `ShaderMaterial` compartido** (`world_vcol.gdshader`: albedo = COLOR, nieve por normal mundial, escarcha, tinte de corte). Los 33 assets existentes se regeneran así en M0 (la cabaña pasa de 34 superficies a ≈ 10). | Medido: 40 personajes = 960 draw calls con 8 materiales vs 120 con color de vértice (×8). Godot activa *albedo from vertex color* automáticamente si la primitiva trae `COLOR_0`. Un material compartido permite al renderer ordenar por material. El código que busca materiales por nombre (`window`, `ember`) sigue funcionando porque esos siguen siendo materiales aparte. | 04 §0, §3, §5.8, PoC |
| C3 | **Motor de física** | **Jolt Physics**, activado explícitamente en `project.godot` (`physics/3d/physics_engine="Jolt Physics"`) en M0. 60 Hz. | El slice corre hoy en GodotPhysics porque la clave no existe (Jolt solo es defecto en proyectos *nuevos* desde 4.6). Jolt soporta ≈ 800 `CharacterBody3D` antes de degradar frente a 10–40 (issue #78761), y `HeightMapShape3D` con menos "ghost collisions". | 01 §1.1, §10.1; 03 §2.2 |
| C4 | **Partículas** | **`GPUParticles3D` por defecto** (nieve, ventisca, fuego, vapor). `CPUParticles3D` solo para efectos de un disparo con lógica CPU (astillas, vaho) y en el preset `compat` si una iGPU falla. El servidor headless no instancia partículas. | El slice exigía CPU "para Compatibility": innecesario, `GPUParticles3D` funciona en Compatibility (sin *trails*/SDF/`emit_particle`). 12 000 copos en ventisca solo son viables en GPU. | 01 §3.4, §4.5, §7.1 |
| C5 | **Renderer** | **Forward+ por defecto**; preset **`compat`** (Compatibility/OpenGL) seleccionable y autodetectado en iGPU antiguas; **sin Mobile**. Misma escena; los efectos exclusivos (niebla volumétrica, PCSS, SSAO, > 8 luces por malla) se activan por preset. | Pueblos de noche con farolas, ventanas y fogatas necesitan luces *clustered*; Compatibility limita a 8 omni + 8 spot por malla. La cámara alta hace el coste GPU pequeño en ambos. | 01 §7.1 |
| C6 | **Tamaño del mundo** | **3 072 × 3 072 m (48 × 48 chunks de 64 m)**, coordenadas centradas (±1 536 m), **precisión simple, sin origin shifting**. El anillo exterior de ≈ 384 m es "borde" (bosque denso, acantilados, hielo, niebla) casi sin POIs: el contenido vive en los 2.3 × 2.3 km centrales. | 9.4 km² ≈ 12–17 min andando de lado a lado, 3 min en coche: suficiente para que separarse "duela" y el coche importe. Concentrar contenido en el centro mantiene realista la producción de arte. Godot tolera 32k unidades en top‑down; nuestro máximo es 1.5k. | 01 §0, §2.2, §4.3 |
| C7 | **Chunk** | **64 m**, capas independientes por chunk (terreno+colisión r2, estáticos r2, edificios r1+prefetch r2, dinámicos r1, navmesh r1 solo servidor). Cliente: anillo 1 (3 × 3) completo, anillo 2 (5 × 5) precargado. Servidor: chunks "calientes" (unión de anillos 1 de todos los jugadores), "tibios" (anillo 2), "hibernados" (delta serializado, liberado tras 60 s sin jugador a < 3 chunks). | Consistente en los tres documentos técnicos (01 §4.1, 03 §4.1, 04 §9.1: 64 m = 32 celdas de kit). | 01 §4.1; 03 §4.1 |
| C8 | **Rejilla del kit de edificios** | **2 m con medio módulo de 1 m**; planta 3.0 m; muro exterior 0.2 m; cimiento 0.3 m; rejilla interior de mobiliario 1 m. Los edificios se **ensamblan en Blender a partir de plantillas (`data/buildings/*.json`) y se exportan fusionados por grupos de corte** (`Floor0`, `Walls0_N/S/E/W` + `Stub`, `Interior0`, `Roof`, `Door_n`, `Spawn_*`, `Col*`): **una `.glb` por variante de edificio**. El generador de asentamientos elige *qué* edificio va en *qué* parcela; no ensambla módulos en runtime. | 01 proponía rejilla 1 m y ensamblado en runtime (GridMap/MultiMesh); 04 mide 34 superficies en la cabaña actual (≈ 100 draw calls con sombras) y propone rejilla 2 m + fusión. La fusión offline da 12–16 superficies por edificio frente a 1 draw call por *tipo de módulo* por edificio; además funciona con *Strip Visuals* en el servidor (los `Col*` sobreviven). La variedad sale de 3 estilos × N plantillas × sets de interior, no de recombinar módulos en vivo. | 04 §0, §9; 01 §5.1.5 |
| C9 | **LOD de IA (cifras)** | Cuatro niveles, todos en servidor: **L0 Activo** (< 40 m de un jugador; `CharacterBody3D` de un pool; piensa 10 Hz, sentidos 5 Hz, ruta 0.5–1 s; ≤ 60 por zona, **≤ 150 en total**); **L1 Cercano** (40–120 m; registro SoA sin cuerpo, avanza por ruta cada 2 s a 2 Hz; ≤ 100 por zona, ≤ 400 total); **L2 Grupo** (120–400 m; una entidad "grupo" con cuenta y destino sobre el grafo de carreteras); **L3 Celda/durmiente** (> 400 m o chunk tibio: solo cuenta y semilla por chunk; los congelados son registros). Cliente: **≤ 60 esqueletos activos** (4 jugadores + 56 zombis/animales), animación a 10–15 Hz fuera de pantalla o > 30 m. Director: 12 × (1 + 0.5·(n−1)) activos por zona (12/18/24/30). | 01 (150/500/2000), 02 (L0–L3, 40/80 por zona, 500 por servidor) y 03 (10 Hz/2 Hz/dormido) coinciden en la forma; se unifican los números a los más conservadores y se elimina la contradicción "NavigationAgent3D con evasión" (02) → `NavigationServer3D` directo sin nodos agente, RVO solo a < 20 m del jugador (01). VAT/MultiMesh para hordas queda **fuera de v2.0** (ver no objetivos). | 01 §5.3; 02 §3.4, §3.6; 03 §3.8; 04 §5.8 |
| C10 | **Tick rates** | Física **60 Hz** en cliente y servidor (sin subir a 90 Hz por los vehículos). Inputs del jugador 60 Hz, empaquetados 2 por paquete a **30 Hz con redundancia** de los 2 últimos. Estado de jugadores y vehículos conducidos **30 Hz**; vehículos aparcados `ON_CHANGE` (nada cuando duermen). Zombis por banda de distancia: **15 Hz (< 30 m), 10 Hz (30–60), 4 Hz (60–120)** + keyframe por chunk cada 1 s. Mundo `ON_CHANGE`; reloj/clima cada 5 s + extrapolación local. Red poleada en `_physics_process`. | 01 decía 20–30 Hz y 10 Hz para aparcados; 03 fija 30 Hz y bandas para zombis con medidas. Se toman los de 03. 60 Hz de física: 01 §6.1 acepta 90 Hz solo si aparece *jitter* de suspensión — se decidirá con `perf_drive`, no antes. | 03 §0, §3.1, §3.8; 01 §7.3 |
| C11 | **Ancho de banda** | Bajada por cliente: **típico ≤ 15 kB/s (120 kbit/s), pico ≤ 30 kB/s (240 kbit/s)**; subida ≤ 3 kB/s. Paquetes propios ≤ 1 200 B; `max_sync_packet_size` 1 350. | 01 pedía ≤ 40 kbit/s (5 kB/s): irreal frente a la medida del PoC (3.5 kB/s solo con 4 jugadores, sin zombis) y a 60 zombis × 8 B × 8 Hz ≈ 4 kB/s. Se adopta el presupuesto medido de 03. | 03 §3.9, §12 |
| C12 | **Persistencia** | **SQLite** (`godot-sqlite` v4.9, MIT, WAL) en el servidor, **solo deltas** sobre el mundo procedural. Autoguardado de "sucios" cada **60 s** + al cerrar contenedor, al desconectar jugador, al hibernar chunk, por comando de admin y al apagar. Interfaz `PersistenceBackend` con `SqliteBackend` (producción), `MemoryBackend` (tests) y `FileBackend` JSON (respaldo si la GDExtension no carga). **Los zombis no se persisten individualmente**: por chunk se guardan contadores de población y "limpiado hasta"; la horda migratoria se guarda como una fila. Esquema en ARQ v2 §15. | 01 (30 s) y 03 (120 s): 60 s acota la pérdida ante *crash* a un minuto con coste despreciable (transacción única). 01 guardaba `actors`; 03 no: guardar 2 000 zombis no aporta nada que la regla de densidad no regenere. | 01 §8; 03 §4.2–4.3 |
| C13 | **API de red** | **Híbrida**: `MultiplayerSpawner` + `MultiplayerSynchronizer` (con filtros de visibilidad por chunk) para **jugadores, vehículos, estructuras colocadas y `WorldState`**; **paquetes propios** (`PackedByteArray`, `StreamPeerBuffer`) para **inputs con secuencia, snapshots de zombis (8 B/zombi), drops, snapshot de delta de chunk (ZSTD) y eventos de mundo**. Canales ENet: 0 movimiento/estado (no fiable ordenado), 1 fiable (interacción, inventario, chat, eventos), 2 zombis, 3 voz (futuro). | 01 sugería Spawner/Synchronizer también para zombis; 03 mide ≈ 1 kB/s por entidad a 30 Hz con el sincronizador (200 zombis ⇒ 200 kB/s): inviable. Los sincronizadores se quedan donde son cómodos y baratos. | 03 §2.1, §2.4, §3.8; 01 §9 |
| C14 | **Topología** | **Servidor dedicado autoritativo siempre**, exportado como "dedicated server" headless. "Crear partida" = lanzar el propio ejecutable como proceso hijo (`--headless -- --server`) y conectarse a `127.0.0.1`. **Un solo `game.tscn` con dos sabores** (`game.gd` añade ramas solo‑cliente en runtime). Sin *listen server*. | 01 proponía `game_client.tscn` y `game_server.tscn`; 03 demuestra que los RPC exigen `NodePath` idénticos y que un solo camino de código evita `call_local` y dobles roles. El PoC ya funciona así. | 03 §1, §10.1 |
| C15 | **Vehículos** | **`RigidBody3D` + suspensión por 4 raycasts + modelo de neumático simple** (implementación propia inspirada en *Godot Easy Vehicle Physics*, MIT), tracción por superficie desde la máscara del terreno (asfalto 0.9 / nieve pisada 0.55 / nieve profunda 0.35 / hielo 0.12). **Autoridad del conductor con validación del servidor**; pasajeros por referencia (nunca reparentar bajo el vehículo). Sin `VehicleBody3D`, sin sufijos `-vehicle/-wheel` en los `.glb`. | 01 y 03 coinciden; 04 prueba que los sufijos de import crean nodos mal configurados. Se implementa propio (el addon no es descargable desde el entorno y hay que ajustarlo a 60 Hz). | 01 §6; 03 §3.7; 04 §10 |
| C16 | **Navegación** | Navmesh **solo en el servidor**, horneado **asíncrono por chunk** desde **colisionadores estáticos** (nunca mallas visuales), `cell_size` 0.25, `agent_radius` 0.4, rehorneado con *cooldown* 2 s cuando cambia geometría; puertas = `NavigationLink3D` conmutables. Cliente sin navmesh: el *auto‑walk* del clic es línea recta + `ShapeCast3D`. | 01 §5.2 (verificado con la API 4.7); evita duplicar horneados en cliente. | 01 §5.2 |
| C17 | **Huellas y nieve** | Huellas/rodadas por **`SubViewport` cenital** (1024² sobre 64 × 64 m alrededor del jugador local, re‑proyección cada 8 m, decaimiento 0.5 %/s) detrás de la interfaz `SnowTrailMap`; migración a `DrawableTexture2D` cuando salga del estado experimental. Acumulación: `snow_amount` como *global shader parameter* que el clima sube en ventisca. Cosmético y local: el servidor no lo conoce. | `DrawableTexture2D` (4.7) tiene un bug abierto en D3D12 (#123507). | 01 §3.4 |
| C18 | **Duración del día** | **30 min reales** (día 20 / noche 10), configurable en `server.cfg` (`day_length_sec=1800`). **Gran Ventisca cada 7 días** de juego, anunciada 1 día antes. | El slice usaba 7 min para una sesión de 40 min; con expediciones de 600–1 200 m hace falta que quepan en un día. | 02 §2.5 |
| C19 | **Velocidades** | Jugador: andar **3.0 m/s**, correr **6.0 m/s** (gasta aguante), agachado **1.5 m/s**. Caminante 1.2, corredor 5.5 (ráfagas), reptador 1.0. | El slice tenía `WALK_SPEED = 4.0`; 02 y 04 (animaciones autoradas) usan 3.0. Andar más despacio que el corredor y más rápido que el caminante es el núcleo del combate zombi. | 02 §3.1; 04 §4.5 |
| C20 | **Fuego amigo y PvP** | `friendly_fire = off \| reduced \| full` = multiplicador de daño jugador→jugador **para toda fuente** (0 / 0.25 / 1.0; explosivos ×0.5 adicional en `reduced`). `pvp = false \| true`: con `true`, el daño entre jugadores de **distinta facción** es siempre ×1.0, los jugadores **colisionan** entre sí y se activan sistema de seguridad (30 s), facciones, casas seguras, candados y robo de vehículos; dentro de la misma facción sigue mandando `friendly_fire`. Ambos se consultan en **un único punto**: `DamageResolver.apply(...)`. | 02 definía FF en tres niveles y PvP con zonas seguras; 03 definía `pvp` = armas y `friendly_fire` = colateral. La definición fusionada no tiene huecos (una bala "accidental" y una "deliberada" son indistinguibles para el servidor). | 02 §4.7, §10.4; 03 §3.4, §7 |
| C21 | **Población de zombis** | Densidad objetivo **por chunk (64 m)**: bosque 0–1, aldea 3–8, pueblo 10–25, comisaría/hospital 16–33, control militar 40+. Sin reaparición hasta 72 h de juego sin jugador a < 150 m y solo hasta el 60 %. | 01 daba densidades por 100 m² y 02 por celda de 100 × 100 m; se convierten a la unidad real del motor (chunk). | 01 §5.1.9; 02 §3.3 |
| C22 | **Tirada de botín** | **Determinista en el servidor la primera vez que un jugador abre el contenedor** (`rng.seed = hash(world_seed, container_wid, rolled_day)`), persistida como delta. Reabastecimiento = borrar la fila cuando el chunk lleva 72 h sin visitas → se vuelve a tirar al 60 % (`loot_respawn`). Topes `nominal` por categoría (munición/armas) por región. | Une el modelo "tirar al abrir" (01) con la economía nominal/mínimo de DayZ (02) sin guardar botín que nadie vio. | 01 §5.1.8, §8.2; 02 §6.3 |
| C23 | **Animación** | **Esqueleto humanoide único** (22 huesos con nombres exactos de `SkeletonProfileHumanoid` + 5 sockets), **skin rígido por pieza**, animaciones **generadas por script** (locomoción por generador cíclico con IK analítica; acciones por poses clave), exportadas como `AnimationLibrary`, **in‑place sin root motion**, `AnimationTree` con capa de torso filtrada. Lobo y ciervo siguen con piezas rígidas (`quadruped_animator.gd`) hasta M9b. Librerías externas CC0 (Quaternius UAL) **solo si se pueden descargar**; no son un requisito de ningún hito. | Verificado en el PoC (pies sin deslizamiento, retarget, ragdoll). Mixamo/Synty prohibidos por licencia. | 04 §0–§7; PoC |
| C24 | **Wolves/fauna** | Se mantienen (lobos de noche, ciervos, caza con arco en M5) y pasan por el mismo `DamageResolver`, `SoundEvent` y LOD que los zombis. | Ya existen y encajan con el frío como enemigo. | GDD slice §12; 02 §2.4 |

### 3.2 Resto de decisiones (sin conflicto, fijadas para no reabrir)

| Tema | Decisión | Fuente |
|---|---|---|
| Estructura del mundo | Híbrido **macro autorado / micro procedural**: plano macro (biomas, alturas base, carreteras, asentamientos, POIs) dibujado a mano en `data/world/macro_map.png` (384 × 384, 1 px = 8 m) + `macro_roads.json`; terreno, bosque, aldeas, pueblo y rellenos generados por función pura `f(seed, chunk)`; ≈ 15 POIs a mano como escenas. | 01 §2.3–2.4 |
| Terreno | Malla propia por chunk (65 × 65 muestras a 1 m, indexada, flat shading por derivadas en el shader) + `HeightMapShape3D` por chunk. **Terrain3D no se usa.** | 01 §3 |
| Cámara | Perspectiva, FOV 35°, pitch −52°, yaw en pasos de 45°, distancia 14–30 m (defecto 22), `far = 70`, adelanto 1.5 m en movimiento, **inclinación hacia el cursor hasta 3 m con arma (6 m con mira)**, sombra direccional 60 m, 2 *splits*, 4096. | GDD slice §4; 02 §4.1, §8 |
| Corte de interiores | `CutawayManager` por jugador local: oculta `Roof` y plantas superiores; sustituye por `Stub` (0.6 m) las fachadas cuya normal mira a cámara; solo edificios a < 30 m. Stencil (4.5+) como mejora opcional en M10. | 01 §5.1.7; 04 §9.3 |
| Interest management | 3 × 3 chunks alrededor de cada jugador, recalculado cada 0.5 s; objetos estáticos generados por semilla **no se replican**, solo sus deltas por `wid`. | 03 §4.1 |
| Identidad de objetos | `wid` (64 bits) = `hash64(world_seed, cx, cz, generator_id, index)` para lo procedural; aleatorio de 64 bits con bit alto para lo creado por jugadores. Los RPC viajan por `wid`, no por `NodePath`. | 03 §4.1; 01 §8.1 |
| Predicción | Solo movimiento y apuntado del propio jugador (inputs con `seq`, reconciliación con *replay*, umbral 5 cm). Todo lo demás: UI optimista + confirmación. Interpolación remota 100 ms. *Lag compensation* acotada a 200 ms para hitscan; melee validado por cono/alcance con rebobinado 100–150 ms. | 03 §3.2–3.5 |
| Autenticación | `SceneMultiplayer.auth_callback`: versión + protocolo + nombre + token de identidad (32 B aleatorios en `user://identity.cfg`, el servidor guarda `sha256`) + `HMAC‑SHA256(password, nonce)`. `server_relay = false`, `allow_object_decoding = false`. | 03 §6–7 |
| Hosting | Linux x86_64 (y arm64) headless, `systemd` + Docker opcionales, **UDP 7777** abierto, admin por **socket TCP local 7778** (el headless no procesa `SIGTERM` limpiamente: `ExecStop` guarda por socket). Windows soportado con `--headless`. | 03 §5 |
| Descubrimiento | v2.0: IP:puerto + contraseña + lista de recientes + **LAN por broadcast UDP 7776**. Lista de servidores HTTP, UPnP/relé y Steam: **fuera de v2.0**. | 03 §6 |
| Chat | Texto siempre (canal 1, saneado, *rate limit*); *pings* contextuales; voz **fuera de v2.0** (TwoVoIP como candidato). | 02 §10.3; 03 §8 |
| Escalado por jugadores | Zombis × (1 + 0.5·(n−1)); PV de zombi sin cambios; especiales +1 por cada 2 jugadores; botín nominal ×1 / 1.25 / 1.5 / 1.75; el frío no escala. | 02 §2.5, §10.5 |
| Derribado / muerte | Derribado 60 s (40 s con Calor < 30), reanimar 4 s (2 s con "Camillero"), máx. 2 derribos entre descansos, muerte → reaparecer en cama de base tras 20 s sin mochila, cadáver 48 h de juego (*corpse run*), −10 % XP hacia el siguiente nivel. Solo: auto‑levantarse una vez al día (20 s). `permadeath` como opción de servidor. | 02 §10.2 |
| Progresión | 9 habilidades 0–10 por uso (solo acciones significativas, rendimiento decreciente diario), 1 ventaja de 2 cada 2 niveles, planos desbloqueados para todo el servidor, base por niveles (reclamar edificio + ranuras), meta‑objetivos: torre de radio → quitanieves → evacuación (o "Nos quedamos"). | 02 §7 |
| Armas | 13 armas + arrojadizas + 7 modificaciones (tabla en GDD v2 §7.6). Crítico = cabeza, sin apuntado por partes. | 02 §4.6 |
| Tests | `SceneTree` headless propios (sin framework externo): humo, red con N clientes headless, determinismo, rendimiento con presupuestos en `tests/perf_budgets.json`, capturas xvfb, `verify_*.py` de arte. Cada hito añade sus tests y son **puertas de aceptación**. | 01 §7.4; 03 §9 |
| Addons de terceros | Solo `godot-sqlite`. Ningún otro en v2.0 (netfox, Terrain3D, road‑generator, GodotSteam, TwoVoIP: no). | 01 §10.1; 03 §0 |

---

## 4. El mundo

### 4.1 Concepto

Un valle de montaña del norte, cortado del resto del país por la nieve: la carretera nacional **N‑140** lo cruza de norte a sur; el pueblo **Valdenieve** (cabecera, ≈ 130 edificios) está al noreste del claro inicial; tres aldeas con oficio (aserradero, iglesia, embarcadero), tres granjas, un gran lago helado, una presa, un repetidor de radio en un pico, un control militar que corta la carretera al norte (hacia la evacuación) y las gasolineras/área de descanso de la nacional. El **claro del cazador** (el slice) es el punto de inicio, en el centro del mapa. El borde del mundo es un anillo de montaña, bosque impenetrable y niebla.

### 4.2 Mapa macro (ASCII; 1 carácter = 128 m; 24 × 24 = 3 072 m; norte arriba, x → este, z → sur)

```
        0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3     x: -1536 … +1536
      +-------------------------------------------------+
 z  0 | ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ |  borde: montaña
    1 | ^ ^ ^ # # # # # # # # # # # # # # X ^ ^ ^ ^ ^ ^ |  X = PUNTO DE EVACUACIÓN (puente norte, tras el control)
    2 | ^ # # # # # # # # # # # # # # # # = # # # # # ^ |
    3 | ^ # # # # # # # # # # # # # # # # M # # # # # ^ |  M = CONTROL MILITAR KM 12 (corta la N-140)
    4 | ^ # # # # # # # # # # # # # # # # = # # # # # ^ |
    5 | ^ # # # # # # # # # # f # # # # # = # # # # # ^ |  f = GRANJA DEL MOLINO
    6 | ^ # # # # # v S # # # . . . . . # = # # # # # ^ |  v S = LA HERRERÍA (aldea) + ASERRADERO
    7 | ^ # # # # # - - - - - - T T T . - = # # # # # ^ |  T = VALDENIEVE (pueblo, 500 x 600 m)
    8 | ^ # # # # # # # # # # . T H T P - = # # # # # ^ |      H = hospital, P = comisaría, iglesia y escuela dentro
    9 | ^ # # # # # # # # # # . T T T . # G # # # # # ^ |  G = GASOLINERA NORTE
   10 | ^ # # # # # # # # # # # | # # # # = # # f # # ^ |  f = GRANJA ALTA
   11 | ^ # # R # # # # # # # # | # # # # = # # # # # ^ |  R = REPETIDOR DEL PICO (torre de radio, colina)
   12 | ^ # # # # D # # # # # # C # # # # = # # # # # ^ |  C = CLARO DEL CAZADOR (inicio, = slice)   D = PRESA
   13 | ^ # # # # ~ ~ # # - - - # # # # # A # # # # # ^ |  A = ÁREA DE DESCANSO (atasco, coches saqueables)
   14 | ^ # # # ~ ~ ~ ~ ~ # | # # # # # # = # # # # # ^ |  ~ = LAGO DE LAS ÁNIMAS (hielo; grueso/fino)
   15 | ^ # # # ~ ~ ~ ~ ~ # | # # # # f # = # # # # # ^ |  f = GRANJA ROMERO
   16 | ^ # # # # ~ ~ ~ ~ v # # # # # # # = # # # # # ^ |  v = EL EMBARCADERO (aldea de pescadores)
   17 | ^ # # # # # ~ ~ # # # # # # # # # G # # # # # ^ |  G = GASOLINERA SUR
   18 | ^ # # # # # # # # # # # # # # # # = - v + # # ^ |  v + = SAN BLAS (aldea) + IGLESIA
   19 | ^ # # # # # # # # # # # # # L # # = # # # # # ^ |  L = TORRE DE VIGILANCIA (bosque profundo)
   20 | ^ # # # # # # # # # # # # # # # # = # # # # # ^ |
   21 | ^ # # # # # # # # # # # # # # # # = # # # # # ^ |  la N-140 sigue hacia el sur (borde: túnel derrumbado)
   22 | ^ ^ # # # # # # # # # # # # # # # # # # # # ^ ^ |
   23 | ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ |
      +-------------------------------------------------+
   =  N-140 (asfalto 8 m)     - | caminos secundarios (4-7 m)     # bosque (pinos)     . campos abiertos     ^ montaña / borde
```

Distancias útiles (desde el claro C, en (0, 0)): Valdenieve ≈ 1.2 km (6–7 min andando, 1.5 min en coche); N‑140 ≈ 640 m al este; lago ≈ 700 m al suroeste; La Herrería ≈ 1.1 km; San Blas ≈ 1.3 km; control militar ≈ 1.6 km; evacuación ≈ 1.9 km. Coordenadas exactas de cada POI en `data/world/poi_registry.gd` (ARQ v2 §8.4).

### 4.3 Regiones (banner `REGIÓN — NOMBRE`) y contenido

| Región | Tipo | Extensión | Contenido | Densidad zombi (por chunk) | Hito |
|---|---|---|---|---|---|
| CLARO DEL CAZADOR | POI a mano (el slice, sello de altura) | 3 × 3 chunks | Casa del cazador, cabaña del pescador, camioneta, señal, lago pequeño | 0–1 (congelados en el porche desde M4) | M0–M3 |
| BOSQUE PROFUNDO / PINOS ALTOS | Bosque procedural | ≈ 45 % del mapa | Lobos, ciervos, cabañas aisladas (4), torre de vigilancia, claros con restos de acampada | 0–1 | M3 |
| LA HERRERÍA | Aldea procedural + POI aserradero | 160 × 200 m, 15–20 edificios | Calle principal + 2 ramales, taller mecánico, aserradero (planos, cadenas), bar | 3–8 | M6 |
| N‑140 | Autovía autorada N–S | 3 km × 8 m | Atascos con coches (1 de cada 8 funcional), 2 gasolineras, área de descanso, puente norte | 2–6 en atascos | M6–M7 |
| VALDENIEVE | Pueblo procedural (cuadrícula con *jitter*) + 5 POIs a mano | 500 × 600 m, 120–140 edificios, 50–70 enterables | Casas, tiendas (ropa/deportes, ultramarinos, farmacia), clínica/hospital, comisaría, iglesia, escuela, depósito municipal (quitanieves) | 10–25 (comisaría/hospital 16–33) | M9a |
| EL EMBARCADERO | Aldea procedural en la orilla | 120 × 160 m, 12–15 edificios | Casetas de pesca, embarcadero, motonieve (rara), agujeros de pesca | 3–6 | M9a |
| SAN BLAS | Aldea procedural + iglesia (hito) | 150 × 180 m, 15–18 edificios | Iglesia con campanario (refugio de la horda de día), cementerio, escuela rural | 3–8 | M9a |
| GRANJAS ×3 | POI semiprocedural | 80 × 80 m | Casa, granero, silo, tractor, vallas; comida, gasolina, herramientas | 2–5 | M6 (1), M9a (2) |
| LAGO DE LAS ÁNIMAS | Lago | ≈ 0.45 km² | Hielo grueso/fino/agujeros, casetas, presa al norte | — | M3 (superficie), M8 (hielo fino) |
| CONTROL MILITAR KM 12 | POI a mano | 100 × 60 m | Barreras Jersey, sacos terreros, garita, contenedores; carabinas, munición, piezas del quitanieves; Coloso en la Gran Ventisca | 40+ | M9b |
| REPETIDOR DEL PICO | POI a mano | 40 × 40 m | Sala de control, componente único, custodiada por la horda 1 de cada 3 días | evento | M10 |
| PRESA / ASERRADERO / TORRE DE VIGILANCIA | POIs a mano (hitos de navegación) | 40–120 m | Loot temático, notas de historia | 2–6 | M9a |
| PUNTO DE EVACUACIÓN | POI a mano (final) | puente norte | Convoy, bengalas, defensa de 8 min | evento | M10 |

Regla de densidad: ≈ 1 POI con nombre por 0.25 km² en la zona central (≈ 24) y ≈ 1 edificio enterable por 2 000 m² de asentamiento.

---

## 5. Sistemas (visión de conjunto)

| Sistema | Qué hace | Diseño | Técnica | Arte |
|---|---|---|---|---|
| Red y servidor | Servidor dedicado autoritativo, predicción del jugador, interés por chunk, chat, auth | GDD §12 | ARQ §2, §6–7, §16 | — |
| Mundo por chunks | Terreno determinista, streaming, scatter en MultiMesh, nieve y huellas, borde | GDD §17 | ARQ §8, §14 | ASSET §13 |
| Asentamientos y edificios | Grafo viario, parcelas, plantillas, interiores, corte, botín, puertas | GDD §17 | ARQ §9 | ASSET §8–10 |
| Frío | Temperatura sentida, ropa, humedad, refugios, ventiscas, hielo, objetos con temperatura | GDD §4–5 | ARQ §13 | ASSET §5.4 (ropa) |
| Zombis e IA | Roster, sentidos, ruido, población, hordas, director, LOD | GDD §6 | ARQ §10 | ASSET §5–6 |
| Combate | Apuntado desde arriba, melee, hitscan, proyectiles, daño con política PvP/FF, *game feel* | GDD §7, §15 | ARQ §11 | ASSET §12 |
| Vehículos | Física raycast, superficies, llaves/batería/gasolina, daño, asientos, red | GDD §8 | ARQ §12 | ASSET §11 |
| Botín y economía | Rarezas, tablas por edificio, tirada determinista, reaparición, peso | GDD §9 | ARQ §9.6, §15 | ASSET §13 |
| Fabricación, base, progresión | Recetas, estaciones, reclamar + ranuras, habilidades, ventajas, planos, meta‑objetivos | GDD §10–11 | ARQ §3 (`scripts/systems/`), §7 | ASSET §9 |
| Co‑op | Derribado/reanimar/muerte, *pings*, chat, opciones de servidor, escalado | GDD §12 | ARQ §6.9, §11.2 | ASSET §6 (emotes) |
| UI/HUD | Extensión del estilo de referencia: termómetro, aguante, anillo de ruido, compañeros, mapa, chat, tablón | GDD §13 | ARQ §17 | — (SVG por Fable) |
| Persistencia | SQLite, deltas, perfiles, migraciones, copias | GDD §12.1 | ARQ §15 | — |
| Operación | Export, `server.cfg`, Docker, systemd, admin, logs, métricas | — | ARQ §16 | — |
| Tests | Humo, red, determinismo, rendimiento, capturas, verificación de arte | — | ARQ §18 | ASSET §16 |

---

## 6. Equipo y forma de trabajo

- **Pases**: cada hito lo entrega **un agente Fable (código) + un agente Opus (arte)** trabajando en paralelo sobre contratos escritos (ASSET_SPEC v2 + la sección del hito). El arte de un hito se produce **durante el hito anterior** siempre que sea posible (la columna "Arte necesario" indica para cuándo).
- **Contrato**: el código **nunca depende de que exista un `.glb`** (`Assets.spawn_model` + `Placeholders`, como en el slice). El arte **nunca depende de leer código**: solo del contrato. Los verificadores (`blender/verify_*.py`, `tests/inspect_models.gd`) son el contrato ejecutable.
- **Definición de hecho** (por pase): (1) todos los tests del hito y de los anteriores en verde (`tests/run_all.sh`); (2) presupuestos de rendimiento cumplidos donde el hito los introduce; (3) capturas actualizadas en el informe; (4) documentación tocada si cambió una decisión (esta tabla, GDD v2, ARQ v2, ASSET v2); (5) informe final ≤ 40 líneas con lo hecho, lo que quedó fuera y las cifras medidas.
- **Ramas y commits**: se trabaja en la rama de desarrollo asignada (hoy `claude/winter-survival-game-txs1nx`), con al menos un commit por hito (`M<N>: …`); nunca se hace *merge* a `main` sin que el usuario lo pida.
- **Idioma**: documentos y textos del juego en español; identificadores de código y nombres de assets en inglés ASCII.

---

## 7. Roadmap por hitos

Tamaños: **S** ≈ medio pase, **M** ≈ un pase holgado, **L** ≈ un pase completo con alcance ajustado (si un L se desborda se recorta alcance, nunca tests). Cada hito termina **jugable** y con **tests automáticos como criterio de aceptación**.

Orden y razón: **M0** paga la deuda de convenciones (barato ahora, carísimo después). **M1–M2** hacen el refactor más arriesgado (autoloads de un jugador → servidor autoritativo con estado por jugador) mientras el juego sigue siendo el slice. **M3** abre el mundo (streaming, determinismo). **M4–M5** convierten el slice en juego zombi (IA a escala, combate, armas, botín, persistencia real, servidor operable). **M6–M7** añaden aldeas, carreteras y coches. **M8** profundiza el frío, la base y la progresión. **M9** trae el pueblo y el director completo. **M10** cierra la meta y el lanzamiento.

### M0 — Cimientos técnicos y contrato de arte v2 · **S (código) + M (arte)**

- **Objetivo**: el slice idéntico en jugabilidad, corriendo sobre Jolt y con todas las convenciones v2 ya aplicadas (frente −Y, color de vértice, partículas GPU), para no producir ni una sola pieza de contenido nuevo con las convenciones viejas.
- **Fable**: `physics/3d/physics_engine="Jolt Physics"`; `Camera3D.far = 70`; sombras 2 *splits* / 4096; revisar `floor_max_angle`, márgenes de cápsula y `HeightMapShape3D` bajo Jolt; `Assets.spawn_model` sustituye `palette_vcol` por el `ShaderMaterial` compartido `assets/materials/world_vcol.tres` (`world_vcol.gdshader` con `snow_amount` global); código a `MODEL_FRONT` (`cabin` rotación 0, `signpost`, muebles, `Visual.look_at(..., true)`, spawn del jugador con `+basis.z`); `snowfall` a `GPUParticles3D` (CPU solo en `hit_puff`/vaho); autoload `Quality` (presets `alto/medio/compat`, detección de iGPU); `tests/perf_probe.gd` (draw calls, objetos, ms en una escena fija, escribe JSON) y `tests/perf_budgets.json`; `tests/run_all.sh`.
- **Opus**: `lib/palette.py` → color de vértice (`COLOR_0`) + material único `palette_vcol` + excepciones; `lib/export.py` con las opciones de ASSET v2 §2.8; `lib/lowpoly.py` con `FRONT = -Y`; **regenerar los 33 assets**; `verify_assets.py` v2 (frente −Y, ≤ 2 superficies por malla salvo excepciones, sin `.001`); extraer `lib/rig.py` y `lib/anim.py` del PoC (sin usarlos aún en assets).
- **Aceptación**: `verify_assets.py` → `ALL OK`; `run_smoke.sh` OK bajo Jolt; capturas `day/night/blizzard/interior/menu` sin regresión visual; `perf_probe`: draw calls de la escena del claro **≤ 60 %** de la medida previa (registrar antes/después); `inspect_models.gd`: todos los anclajes con frente en `+Z` local.
- **Dependencias**: ninguna. **Arte necesario para M1**: rig + locomoción (empieza aquí si sobra tiempo).

### M1 — Servidor dedicado y red base · **L (código) + M (arte)**

- **Objetivo**: 4 jugadores en el claro en un servidor headless; el modo "un jugador" pasa a ser un servidor local. El estado del jugador deja de ser global.
- **Fable**: autoload `Net` (roles, `server.cfg`, auth nonce/HMAC, versión/protocolo, host desde el juego como proceso hijo, `Identity`); `game.tscn` de doble sabor; `PlayerSpawner` (precarga, nombre = peer id); `player.tscn` partido en `PlayerSim` (función pura compartida), `PlayerInput`, `PlayerNet` (inputs 60 Hz empaquetados, predicción + reconciliación con *replay*), `PlayerView`, `PlayerState` (servidor: `InventoryComponent`, `Stats`, `QuestState`) con espejos `ON_CHANGE` solo para el dueño; `Inventory`, `GameState`, `QuestManager` **dejan de ser autoloads** (`WorldState` replicado + `GameFlow` cliente); interpolación de remotos 100 ms; chat de texto; HUD de depuración de red (RTT, pérdida, kB/s, correcciones/s); `tests/net/run_net_test.sh` (servidor + N clientes headless, escenarios) y `tests/net/net_smoke.gd`; el `run_smoke.sh` pasa a arrancar el servidor local.
- **Opus**: `lib/rig.py`, `lib/anim.py` (del PoC); `chars/build_survivor.py` esquelético con **4 variantes de paleta** (chaqueta roja/azul/verde/mostaza) y sockets; `anims/build_loco.py` (`Loco_Idle`, `Loco_Walk`, `Loco_Run`, `Crouch_Idle`, `Crouch_Walk`, `Loco_Idle_Cold`); `humanoid_bonemap.tres` + plantillas `.import`; `verify_chars.py` (huesos, bucles, duraciones, tobillo mínimo, velocidad de apoyo).
- **Aceptación**: `run_net_test.sh --clients 4 --duration 60`: los 4 se ven moverse, chat relayado, reconexión dentro de la gracia (60 s) recupera posición, `request_hit_player` bloqueado con `friendly_fire=off`, 0 `ERROR`; *soak* del servidor 90 s con escena principal; bajada ≤ 5 kB/s por cliente (sin zombis); `run_smoke.sh` OK (offline = servidor local); `verify_chars.py` OK.
- **Dependencias**: M0. **Riesgo principal**: R2 (refactor de autoloads).

### M2 — Mundo compartido e interacción autoritativa · **M–L (código) + M (arte)**

- **Objetivo**: todo lo que hace el slice (talar, recoger, estufa, armario, fabricar, colocar, comer, lobos) funciona con 4 jugadores, validado en el servidor, y el jugador ya es esquelético.
- **Fable**: `WorldRegistry` + `wid`; cada objeto del mundo expone `server_interact(player, action, arg)` y `client_preview`; `NetWorld.request_interact/craft/place/take/deposit` con validación (distancia + tolerancia, herramienta, *rate limit*, infracciones); `ChunkDelta` en memoria + `chunk_delta_snapshot` al entrar (el claro son los chunks 23–25); `Storage` con exclusión mutua ("en uso"); drops replicados (`DropSpawner`); `Respawner` solo servidor; corte por jugador local; huellas para todos los personajes; `PersistenceBackend` + `MemoryBackend` + guardado de perfiles en JSON temporal; **integración del jugador esquelético**: `character_visual.tscn` (modelo + `AnimationPlayer` con librerías + `AnimationTree` + `BoneAttachment3D` en `RightHandSocket` + `LookAtModifier3D`), retirada de `player_animator.gd`; lobos/ciervos pasan por `DamageResolver` v0.
- **Opus**: `chars/build_zombie.py` **caminante** (3 cuerpos × 4 atuendos × 2 paletas; entregar ≥ 8 variantes); `anims/build_zombie.py` (`Zom_Idle_A/B`, `Zom_Shamble_A/B/C/D`, `Zom_Attack_A/B`, `Zom_Hit`, `Zom_Death_A/B`, `Zom_Frozen_Idle`, `Zom_Wake`); armas cuerpo a cuerpo lote 1 (`bat`, `crowbar`, `knife`, `fire_axe`, `machete`, `stone_axe` migrada) con anclas; parches de sangre (quads).
- **Aceptación**: escenario de red `shared_world`: A tala → B ve tocón, solo A recibe madera; A y B abren el armario → B ve "en uso"; C entra tarde y recibe los deltas; fabricar y colocar fogata replicados; `run_smoke.sh` con el jugador esquelético: métrica de pies (tobillo ≥ 0.08 m, deslizamiento < 5 %); `perf_probe` sin regresión.
- **Dependencias**: M1.

### M3 — Mundo por chunks (3 km) y nieve nueva · **L (código) + M (arte)**

- **Objetivo**: caminar (y, con teletransporte, "conducir") 3 km sin tirones; el claro es un POI en el centro de un bosque determinista compartido por cliente y servidor.
- **Fable**: `WorldConst` (48 × 48 × 64 m); `height_function.gd` puro (fBm + altura macro + sellos: claro, lago pequeño, lago grande, pads de POI, carreteras del macro); `terrain_chunk.gd` (malla indexada, flat shading por derivadas, `HeightMapShape3D`, máscara de superficie en `CUSTOM0`); `macro_map` (PNG 384² + JSON de carreteras; v0 dibujado por Fable con el mapa de §4.2); `world_streamer.gd` (anillos, prioridad por velocidad, `WorkerThreadPool`, presupuesto 2 ms/frame); `scatter_gen` + `multimesh_chunk` + `scatter_index` (talar árboles por índice, instancia real solo al golpear); `Bounds` → borde del mundo; `RegionTracker` por chunk; servidor: chunks caliente/tibio/hibernado, `ChunkDelta` por chunk, interés 3 × 3; `SnowTrailMap` (`SubViewport`) sustituye `footprints.tscn`; `snow_amount` global; lago grande (superficie plana, hielo seguro por ahora); `tests/determinism.gd` (hash de N chunks en dos procesos) y `tests/perf_walk.gd` (ruta fija a 25 m/s: 0 frames > 33 ms por streaming, coste de streaming ≤ 2 ms/frame).
- **Opus**: vegetación y rocas para MultiMesh (pinos ×3 nuevos, árboles secos ×2, abeto joven, arbustos ×2, rocas ×3, montones de nieve ×3, troncos ×2, carámbanos), cabaña aislada (`cabin_small`, a mano, con la estructura de corte v2), torre de vigilancia, restos de acampada; **empieza el kit de edificios (M6)**.
- **Aceptación**: `determinism.gd` OK (hashes iguales cliente/servidor para 50 chunks); `perf_walk` dentro de presupuesto; net: 2 clientes a 1 km entre sí solo reciben su anillo; memoria cliente ≤ 2.5 GB; `run_smoke.sh` y capturas OK.
- **Dependencias**: M2 (deltas por chunk). **Riesgo**: R3 (determinismo), R4 (tirones).

### M4 — Zombis, navegación y combate cuerpo a cuerpo · **L (código) + M (arte)**

- **Objetivo**: 100 zombis alrededor del claro a 60 FPS con 4 jugadores; matar, ser derribado y reanimado; fuego amigo/PvP funcionando como reglas de servidor.
- **Fable**: `nav_baker` (async por chunk, colisionadores estáticos), `nav_query_queue` (≤ 40 consultas/tick, rutas compartidas por grupo); `ZombieSystem` SoA (L1–L3) + pool de `CharacterBody3D` (L0); `ZombieBrain` (idle/wander/investigate/chase/attack/hit/dead/frozen), sentidos (cono 120°, oído por `SoundEvent`, olfato mínimo), memoria; `population_manager` (densidad por chunk, durmientes, congelado por frío); `Director` v0 (intensidad, acumulación/pico/alivio, hordas errantes); replicación propia de zombis (enter/leave, snapshots 8 B, bandas); `ZombieView` pool + `AnimationTree` + LOD de animación + ragdoll a < 25 m; `DamageResolver` completo con `pvp`/`friendly_fire`; melee validado (cono, alcance + 0.5 m, rebobinado); *hitstop*, sacudida, sangre en nieve; anillo de ruido en el mundo; empujón/pisotón/ejecución a congelados; **derribado/reanimar/muerte/reaparición/cadáver**; aguante; `tests/perf_horde.gd` (200 zombis en el claro, servidor headless: tick ≤ 8 ms) y escenario de red `zombies` (bandwidth ≤ 15 kB/s típico).
- **Opus**: especiales lote 1 (corredor, reptador, congelado con esquirlas, hinchado); `anims`: `Zom_Run`, `Zom_Run_Tired`, `Zom_Crawl`, `Zom_Grab`, `Zom_Knock_Door`, `Zom_Stagger`, `Zom_Knockdown`, `Zom_GetUp`; jugador: `Melee1H_Light_A/B`, `Melee2H_Swing_A/B`, `Melee_Charged`, `Act_Shove`, `Act_Stomp`, `Act_Execute`, `Hit_Front`, `Hit_Back`, `Down_Crawl`, `Down_Idle`, `Act_Revive`, `Act_GetUp`, `Death_A` (+ configuración de ragdoll); props gore‑lite (muñones, cabeza fragmentada).
- **Aceptación**: `perf_horde` en presupuesto; escenario `zombies` con 4 clientes: mismos zombis mueren en todos, derribado → reanimado → muerto → reaparece en la cama; `friendly_fire=off` sin daño y `full` con daño; `pvp=true` → colisión entre jugadores; `run_smoke.sh` ampliado (spawn de 20 zombis, matar 1, congelado despierta por ruido).
- **Dependencias**: M3 (navmesh por chunk). **Riesgo**: R1 (CPU de IA).

### M5 — Armas de fuego, ruido, botín, persistencia SQLite y servidor operable · **L (código) + M (arte)**

- **Objetivo**: disparar con retícula que se cierra, munición escasa, ruido que trae zombis, contenedores con tablas de botín, y un servidor que se reinicia sin perder nada y se administra por socket/Docker/systemd.
- **Fable**: hitscan con *lag compensation* ≤ 200 ms (historial 1 s), cono de precisión (colores), retroceso, cadencia/cargador/recarga cancelable, encasquillamiento por frío, magnetismo del cursor, inclinación de cámara hacia el cursor; tabla completa de ruido; `LootTables` + tirada determinista por `wid` + `nominal`; `Items` ampliado (armas, munición, medicinas, ropa v0, herramientas); peso y umbrales; arco (proyectil) y arrojadizas básicas (lata, bengala); caza (ciervo → carne/piel); `SqliteBackend` + esquema + migraciones (`PRAGMA user_version`) + autoguardado 60 s + `VACUUM INTO` diario + `FileBackend` de respaldo; reconexión con gracia; preset de export "Dedicated Server" + `server/Dockerfile` + `server/ventisca.service` + `server/admin.sh` + socket admin + comandos de chat (`/kick /ban /save /time /weather /give /tp /pvp /ff`); `server.cfg` completo; logs `[EVT]`.
- **Opus**: `pistol_9mm`, `revolver_357`, `shotgun_pump`, `rifle_308` (+ mira), `bow`, `crossbow` (P2), `carbine_556` (P2), arrojadizas (`molotov`, `flare`, `pipe_bomb`, `can`); anims `Pistol_Aim/Shoot/Reload`, `LongGun_Aim/Shoot/Reload_Bolt/Reload_Shell`, `Bow_Draw/Hold/Release`, `Throw`, `Act_Unjam`; props de botín (latas ×4, vendas, botiquín, cajas de munición, mochilas ×3, bidón, batería, cadenas) y contenedores (caja, taquilla, estantería, nevera, cómoda, mostrador); fogonazo (malla).
- **Aceptación**: escenario `restart`: colocar fogata, talar, saquear, desconectar; reiniciar servidor; todo persiste; `admin.sh save-and-quit` apaga limpio; `docker build` + arranque headless en `debian:bookworm-slim`; escenario `hitscan` con `--net-sim 150,20,2`: acierta a objetivo en movimiento, rechaza disparos sin munición; determinismo de tiradas de botín (misma semilla → mismo contenido); `run_smoke.sh` con disparo → anillo de ruido → zombi investiga.
- **Dependencias**: M4. **Riesgo**: R6 (godot‑sqlite).

### M6a — Kit modular, carreteras y calle de prueba · **M (código) + L (arte)**

- **Objetivo**: una calle generada por semilla con 6 casas enterables de 1–2 plantas, puertas, ventanas, mobiliario, botín y corte de plantas; carretera con cinta y sello en el terreno.
- **Fable**: `road_graph` (splines macro + calles), `road_mesh` (cinta 8 m/4 m, sello de altura, bermas, máscara `asphalt`); `building_assembler` (instancia `.glb` por plantilla, lee `Door_n`, `Spawn_*`, `Col*`, capas de corte); puertas interactivas (abrir/cerrar/forzar/romper, `NavigationLink3D`); ventanas rompibles; `CutawayManager` (plantas, stubs, ≤ 30 m, por jugador local); interiores: mobiliario y contenedores desde `Spawn_*`; zombis dormidos en interiores; superficies `interior` (sin nieve); `perf_drive` v0 (ruta por la calle).
- **Opus**: **kit** (muros/esquinas/suelos/escaleras/tejados/aberturas ×3 estilos: madera‑azul, ladrillo, hormigón/chapa) y **plantillas**: `house_small_A/B/C` (1 planta), `house_two_story_A/B` (2 plantas), `shop_general`, `garage`, `barn`, `sawmill_shed`, `gas_station` (marquesina + tienda); baldosas de carretera (recta, X, T, curva, fin, paso de cebra, aparcamiento) y aceras; `verify_kits.py` (grupos de corte, `Stub`, anclas, colisiones, presupuestos).
- **Aceptación**: `verify_kits.py` OK; calle determinista (hash); corte correcto en 2 plantas (captura); navmesh entra por las puertas (zombi persigue dentro de casa en test); `perf_probe` en la calle ≤ 800 draw calls / ≤ 12 ms (Forward+).
- **Dependencias**: M3, M5 (botín). **Arte necesario en M5**: kit.

### M6b — Aldea LA HERRERÍA, aserradero, gasolinera norte y granja · **L (código) + M (arte)**

- **Objetivo**: primera región "civilizada" completa a 1.1 km del claro: aldea procedural + 3 POIs a mano, con población zombi, botín por tipo de edificio y farolas de noche.
- **Fable**: `settlement_gen` (aldea: calle principal + 1–2 ramales, parcelas OBB 400–900 m², asignación de uso, plantillas por estilo); POIs a mano (`poi/sawmill.tscn`, `poi/gas_station_north.tscn`, `poi/farm_molino.tscn`) con sellos; `population_manager` por uso de suelo; alarmas (tienda 5 %); luces de pueblo (Forward+; `compat`: emisivos + halo); coches abandonados como props con contenedor; `perf_drive` por la aldea; señales/carteles (`Label3D`).
- **Opus**: props urbanos (farola, poste + cables, señales, parada, banco, papelera, contenedor, vallas ×3, barricadas ×4, hidrante, buzón, neumáticos, palés, cajas, carrito), restos de coche estáticos ×3 (sedán, furgoneta, camioneta: variantes), surtidor, cartel de gasolinera, silo, tractor (prop), sierra/maquinaria del aserradero, heno.
- **Aceptación**: aldea determinista (hash) con 15–20 edificios y ≥ 6 enterables; `perf_drive` (aldea) ≤ 800 draw calls típicos, p99 frame ≤ 16 ms, 0 tirones > 33 ms; escenario de red `village`: 2 jugadores en casas distintas ven estados de puertas y contenedores coherentes; densidad zombi de aldea y alarma probadas en `run_smoke.sh`.
- **Dependencias**: M6a.

### M7 — Vehículos · **M (código) + M (arte)**

- **Objetivo**: conducir la camioneta y un sedán con 4 ocupantes por la N‑140 hasta la aldea; gasolina, batería, llaves, atropellos, daño, maletero compartido.
- **Fable**: `raycast_vehicle.gd` (RigidBody3D, 4 raycasts/ShapeCast, neumático, cambio automático simple), `vehicle_builder.gd` (anclas), `surface.gd` (μ por máscara), asientos por referencia, entrar/salir (0.8 s), autoridad del conductor + validación (v_max × 1.2, desplazamiento por tick, altura), pasajeros y disparo desde la ventanilla/caja, maletero `Storage`, llaves/guantera/puentear (canal 8 s, alarma 15 %), batería con frío, gasolina y sifón, 4 piezas de daño, atropello (`contact_monitor`), faros, calefacción, ruido, hielo del lago con μ 0.12, `vehicles` en SQLite, autovía N‑140 con atascos (1 de 8 funcional), área de descanso, `perf_drive` en coche.
- **Opus**: `sedan` (+ patrulla), `pickup` (migrada con anclas v2), `van`, `snowmobile` (esquís + oruga), variantes *wreck* del generador; anims `Veh_Enter`, `Veh_Exit`, `Veh_Drive` (IK volante), `Veh_Passenger`, `Veh_Shoot_Window`, `Veh_Snowmobile`; `verify_vehicles.py` (anclas, ruedas simétricas, colisiones sin sufijo).
- **Aceptación**: escenario `vehicle`: A conduce, B pasajero, C observa interpolado (error < 0.5 m a 150 ms simulados), servidor rechaza teletransporte (snap + infracción), coche persiste tras reinicio, atropello mata caminante a ≥ 30 km/h; `perf_drive` en coche a 25 m/s: 0 tirones por streaming.
- **Dependencias**: M3, M5 (persistencia), M6b (carretera).

### M8 — Frío v2, ropa, base y progresión · **L (código) + M (arte)**

- **Objetivo**: el frío como sistema completo y legible; una base reclamada con ranuras; habilidades y planos; un día de 30 min con la primera Gran Ventisca.
- **Fable**: temperatura sentida (`T_ambiente + aislamiento − viento − humedad + fuente`), ropa por 3 capas + cabeza/manos/pies (aislamiento, cortaviento, impermeable, peso, estado), humedad y secado, correr suda, congelación (−10 % salud máx.), aislamiento de edificios (ventanas rotas), hielo grueso/fino/agujero y caída al agua, objetos con temperatura (latas, pilas, cantimplora), fiebre por mordisco, aguante completo; **base**: reclamar edificio, ranuras (estufa, camas, almacén, taller, radio, generador, cargador, barricadas) por niveles N1–N4, colocables (valla, barricada, fogata, tienda, caja), "calor de ruido" de la base; **progresión**: 9 habilidades por uso con rendimiento decreciente, ventajas, planos leídos junto al fuego, XP compartida de planos; dormir por votación; día 30 min; **Gran Ventisca v0** (−20 °C, visibilidad 6 m, congelados despiertan por oleadas); HUD: termómetro sentido, iconos de causa, panel de ropa, panel de habilidades, panel de base.
- **Opus**: ropa como piezas rígidas sobre el esqueleto (abrigo, parka, abrigo militar, sudadera, chaleco policial, gorros ×3, guantes ×2, botas ×3), mochilas ×3 (socket `BackSocket`); props de base (banco de trabajo, generador, radio, cargador, barricadas de ventana/puerta, cama de campaña, estufa de aceite); hielo (grietas como mallas, agujero de pesca); anims `Loco_Idle_Cold` (mejorada), `Act_Warm_Hands`, `Act_Sit_Fire`, `Act_Sleep`, `Act_Eat`, `Act_Drink`, `Act_Bandage`, `Act_Inject`, `Act_Read`, `Act_Fall_Ice`.
- **Aceptación**: tests unitarios de las fórmulas (`tests/unit/thermal_test.gd`, `skills_test.gd`) con los valores del GDD; escenario `base`: reclamar, mejorar N1→N2, dormir por votación, base persiste; `run_smoke.sh` con hielo fino y humedad; Gran Ventisca forzada (`/weather great_blizzard`) despierta congelados en oleadas.
- **Dependencias**: M5, M6b.

### M9a — VALDENIEVE, El Embarcadero, San Blas, granjas y POIs de hito · **L (código) + L (arte)**

- **Objetivo**: el pueblo cabecera (120–140 edificios, 50–70 enterables) con comisaría, hospital, iglesia, escuela, farmacia, tiendas y depósito municipal; dos aldeas más; presa, aserradero terminado, torre de vigilancia; el mapa macro definitivo.
- **Fable**: `settlement_gen` pueblo (cuadrícula con *jitter* 60–90 m, recorte por pendiente/agua, manzanas → parcelas OBB, uso 65/15/8/12, POIs reservados en las mejores parcelas), enterables 45 % casas / 100 % servicios, edificios grandes en sub‑escenas (fachada/interior/mobiliario/contenedores) para el presupuesto de instanciación, armería cerrada (llave/Mecánica 4), alarmas, escuela/iglesia como refugios de horda, mapa macro final (`macro_map.png` + POIs), `perf_drive` pueblo, `perf_horde` en pueblo.
- **Opus**: kit comercial/servicios (escaparates, toldos, marquesinas, petos, escaleras exteriores), plantillas: `shop_clothes`, `shop_pharmacy`, `clinic`, `hospital` (2–3 plantas), `police_station`, `church` (+ campanario), `school`, `municipal_depot`, `apartment_small`, `bar`, `fishing_hut`, `dam_control`, `lookout_tower`; interiores nuevos (celdas, taquillas, camas de hospital, camillas, bancos de iglesia, altar, pupitres, estanterías de tienda, probadores); ambulancia y autobús como restos.
- **Aceptación**: pueblo determinista; `perf_drive` (pueblo) ≤ 800 draw calls típicos / ≤ 1 500 máx. con sombras, p99 ≤ 16 ms; `perf_horde` en pueblo (150 L0) tick ≤ 8 ms; sesión de 4 en el hospital (escenario `hospital`: 40 zombis, 4 jugadores, 0 desincronizaciones de puertas/contenedores).
- **Dependencias**: M6b, M8. **Riesgo**: R5 (volumen de contenido) — se mide la velocidad de producción en M6a/M6b antes de fijar el número final de plantillas.

### M9b — Director completo, especiales lote 2, hordas y eventos · **L (código) + M (arte)**

- **Objetivo**: gritón, acechador de ventisca, acorazado, coloso; horda migratoria con rutina y rastro; asalto a la base; meta‑eventos; Gran Ventisca completa; control militar.
- **Fable**: `Director` completo (presupuestos por zona, reglas de cortesía, eventos ponderados por clima, *gamestage* de grupo), gritón (grito 60 m), acechador (solo en ventisca, huele a 20 m), acorazado (chaleco/casco), coloso (rompe puertas y hielo), horda migratoria L2 (rutina día/noche, rastro con `SnowTrailMap` + cadáveres, persistente), hordas errantes por carreteras, asalto a la base por "calor", meta‑eventos (helicóptero, disparos, alarma remota), deshielo (raro), control militar (POI + Coloso), zombis con botín temático, desmembramiento ligero, lobos y ciervos migrados al `ZombieSystem`/navmesh (misma IA por niveles).
- **Opus**: gritón (sin brazos), acechador (blanco, agazapado), acorazado (casco `RigidBody3D` + chaleco), coloso (×1.6), anims `Zom_Scream`, `Zom_Stalk`, `Zom_Pounce`, `Zom_Charge`, `Zom_Smash`, `Zom_Eat`, `Zom_Sleep_Group`, `Zom_Helmet_Off`; **esqueleto cuadrúpedo** + lobo/ciervo esqueléticos con sus ciclos (idle, andar, trote, galope, acecho, mordisco, huida, muerte); control militar (barreras, sacos, garita, tienda, contenedores, torre); helicóptero estrellado (prop).
- **Aceptación**: tests del director (`tests/unit/director_test.gd`: nunca ventisca + horda salvo Gran Ventisca; alivio 30–45 s; presupuesto por n jugadores); `perf_horde` con horda migratoria de 120 (30 L0 + 90 L1) en San Blas; escenario `great_blizzard` con 4 clientes: acechador aparece solo con jugador separado > 10 m; captura de la horda de noche por la carretera.
- **Dependencias**: M9a.

### M10 — Meta‑objetivos, co‑op pulido y lanzamiento · **L (código) + M (arte)**

- **Objetivo**: partida completa de principio a fin (torre de radio → quitanieves → evacuación), *pings*, mapa de papel, navegador de servidores, preset `compat` afinado, audio, onboarding de 3 días, builds de cliente y servidor.
- **Fable**: torre de radio (3 componentes), quitanieves (batería de camión + 3 piezas), evacuación (defensa 8 min + final + "Nos quedamos"), tablón de objetivos (1 principal + 3 secundarios generados), *pings* contextuales + emotes + rueda, mapa de papel con marcas, navegador (directo/recientes/LAN), `Voice=off` reservado, `Quality` afinado (`compat`: ≤ 3 sombras, luces limitadas, niebla exponencial), audio: `AudioManager` con eventos v2 + viento/ambiente procedural + SFX CC0 si están disponibles, pantalla de muerte (causa + consejo), onboarding días 1–3 (misiones del slice + ruido/congelados/primer disparo), accesibilidad (chat, remapeo), grabador de *replay* de red, `export_presets.cfg` (cliente Linux/Windows; servidor Linux x86_64/arm64/Windows), `server/README.md` de hosting, stencil de corte (opcional).
- **Opus**: `snowplow`, `heavy_truck`, convoy de evacuación (autobús, camión militar, barreras, bengalas), anims de emotes (`Emote_Point`, `Emote_Come`, `Emote_Wait`, `Emote_Quiet`), `Act_Repair`, `Act_Siphon`, `Act_Chains`, `Act_Jump_Start`, iconos SVG de UI restantes (por Fable si Opus no llega), radio portátil, walkie, componentes de la torre.
- **Aceptación**: escenario `campaign` (headless, acelerado): reparar torre → emisión → quitanieves → evacuación con 4 clientes; `run_all.sh` completo en verde; capturas de las 12 regiones día/noche/ventisca; `perf_*` en `compat` dentro de presupuesto reducido; export de cliente y servidor sin errores y *soak* de 30 min del servidor exportado.
- **Dependencias**: M9b.

### Después de v2.0 (no comprometido)

Voz por proximidad (TwoVoIP), lista de servidores HTTP + UPnP/relé, VAT + MultiMesh para hordas de 500, stencil de corte por defecto, `DrawableTexture2D` para huellas, esqueletos para más fauna (conejo), `flow fields` para hordas, Steam.

### Resumen

| Hito | Nombre | Fable | Opus | Puertas de aceptación (tests) |
|---|---|---|---|---|
| M0 | Cimientos y convenciones v2 | S | M | verify_assets v2, smoke (Jolt), perf_probe −40 % draw calls |
| M1 | Servidor dedicado y red base | L | M | net_test 4 clientes, soak 90 s, smoke offline, verify_chars |
| M2 | Mundo compartido | M–L | M | net `shared_world`, métrica de pies, smoke |
| M3 | Mundo por chunks 3 km | L | M | determinism, perf_walk, net 2 clientes lejanos |
| M4 | Zombis y melee | L | M | perf_horde 200, net `zombies`, smoke ampliado |
| M5 | Armas de fuego, botín, SQLite, operación | L | M | net `restart`, `hitscan` con net‑sim, docker, admin |
| M6a | Kit, carreteras, calle | M | L | verify_kits, hash de calle, corte 2 plantas, perf_probe |
| M6b | Aldea + POIs | L | M | hash de aldea, perf_drive, net `village` |
| M7 | Vehículos | M | M | net `vehicle`, perf_drive en coche, persistencia |
| M8 | Frío v2, base, progresión | L | M | unit thermal/skills, net `base`, Gran Ventisca v0 |
| M9a | Pueblo y regiones | L | L | perf_drive/horde pueblo, net `hospital` |
| M9b | Director, especiales, hordas | L | M | unit director, perf_horde migratoria, net `great_blizzard` |
| M10 | Meta, co‑op, lanzamiento | L | M | net `campaign`, run_all, exports, soak 30 min |

---

## 8. Migración desde el slice (resumen)

El detalle fichero a fichero está en ARQ v2 §20 y el de assets en ASSET v2 §17. En una frase por sistema:

| Slice (hoy) | v2 | Cuándo |
|---|---|---|
| `project.godot` sin Jolt, CPUParticles, +Y frente | Jolt, GPUParticles, `MODEL_FRONT`, presets de calidad | M0 |
| Autoloads `Inventory`, `GameState`, `QuestManager` (un jugador) | `PlayerState` por jugador en servidor + espejos; `WorldState` replicado; `GameFlow` cliente | M1 |
| `player.gd` monolítico, animador procedural de piezas | `PlayerSim/Input/Net/View/State`; `character_visual.tscn` esquelético | M1–M2 |
| `interact(player)` local | `server_interact` + `NetWorld.request_*` por `wid` | M2 |
| `terrain.gd` 160 m, `scatter.gd` con 330 nodos árbol, `footprints.tscn` | `height_function` + `terrain_chunk` + `world_streamer`; MultiMesh + `scatter_index`; `SnowTrailMap` | M3 |
| `wolf.gd`/`steering.gd` con *whiskers* | `ZombieSystem` + navmesh; lobos migrados en M9b | M4, M9b |
| `cabin.tscn` + `cutaway.gd` a mano | Plantilla del kit (`house_hunter`) + `CutawayManager` | M6a |
| `pickup_truck.tscn` (contenedor estático) | `vehicle_base.tscn` + `raycast_vehicle` (y restos estáticos del mismo generador) | M7 |
| `user://best.cfg` | SQLite en servidor; identidad por token en cliente | M5 |
| `tests/smoke_test.gd` | Se mantiene (offline = servidor local) + `tests/net/*`, `perf_*`, `determinism`, `unit/*` | M0–M10 |

Deuda del slice que se paga en el camino: textos de UI acoplados (sin cambio), `RegionTracker` por *polling* (→ eventos de chunk, M3), lobos que "no entran en la casa" por caja mágica (→ navmesh y puertas, M6a/M9b), fin de partida al día 6 (desaparece en M1: mundo persistente).

---

## 9. Registro de riesgos

| # | Riesgo | Prob. | Impacto | Señal de alarma | Mitigación / plan B | Hito |
|---|---|---|---|---|---|---|
| R1 | CPU de la IA de zombis en GDScript (150 L0 + 400 L1) en un VPS de 2 vCPU | Media | Alto | `perf_horde` tick > 8 ms | LOD desde el diseño (SoA para L1–L3, pool de cuerpos L0, *round‑robin*, ≤ 40 rutas/tick); plan B: `ZombieBrain` en C# o GDExtension, o cuerpos por `PhysicsServer3D` sin nodos | M4 |
| R2 | El refactor de autoloads a estado por jugador rompe el slice y se alarga | Alta | Alto | M1 sin `run_smoke.sh` en verde a mitad de pase | Modo offline = servidor local desde el primer día; paridad de smoke test como criterio; el PoC cubre ~60 % del esqueleto de red | M1 |
| R3 | Divergencia cliente/servidor de los generadores (coma flotante, orden de `Dictionary`, x86 vs arm64) | Media | Alto | `determinism.gd` falla; *snaps* de predicción > 1/s | Generadores con enteros/RNG sembrado, arrays ordenados, nunca `Dictionary.keys()`; test de hashes en CI; recomendar servidor x86_64; la altura solo necesita coincidir a < 5 cm | M3 |
| R4 | Tirones de streaming en coche (25 m/s cruza un chunk en 2.5 s) | Media | Alto | `perf_drive` con frames > 33 ms | Presupuesto de 2 ms/frame, anillo 2 precargado, prioridad por velocidad, edificios grandes en sub‑escenas, *shader baker* en export | M3, M7 |
| R5 | Volumen de contenido del pueblo (kit + 30 plantillas + interiores) supera la capacidad de un pase de Opus | Alta | Alto | M6a/M6b entregan < 70 % de las plantillas | Medir ritmo real en M6a; familias parametrizadas (una plantilla = JSON, no un script); recortar Valdenieve a 80–100 edificios antes que recortar interiores enterables | M6a–M9a |
| R6 | `godot-sqlite` (compilado contra 4.7.1) no carga en 4.7.2 o en arm64/Windows | Baja | Medio | Error al cargar la GDExtension en el servidor | `FileBackend` JSON detrás de la misma interfaz; misma suite de tests para ambos | M5 |
| R7 | Límite de 8 luces por malla en Compatibility arruina el pueblo de noche | Alta | Medio | Capturas en `compat` con farolas apagadas | Preset `compat`: farolas emisivas + halo sin luz real, fogatas/faros priorizados, `distance_fade` | M6b, M10 |
| R8 | Atasco del headless (GH‑122707) en Windows | Baja | Alto | *Soak* en Windows se detiene a los 25–55 s | No reproducido en Linux 4.7.2; *soak* en CI; recomendar Linux para hosting | M5 |
| R9 | Calidad de las animaciones generadas en acciones complejas (entrar al coche, trepar) y UAL CC0 no descargable desde el entorno | Media | Medio | Capturas a 22 m poco legibles | Poses exageradas 20–30 %, anticipación ≥ 0.25 s; a 22 m la tolerancia es alta; trepar/saltar vallas fuera de v2.0 | M4+ |
| R10 | Trampas del conductor (autoridad de cliente) con PvP activado | Media | Bajo | — | Validación de velocidad/desplazamiento/altura + infracciones; documentado como "PvP entre amigos"; netfox como opción futura | M7 |
| R11 | Bug del importador #123782 (*Except Bone Transform*) u otros de retarget | Media | Medio | Animaciones con 1 pista | Opción desactivada en las plantillas `.import`; `verify_chars.py` cuenta pistas (≥ 10) | M1 |
| R12 | Deriva entre contrato de arte y código entre pases | Media | Medio | `inspect_models.gd` y `verify_*.py` discrepan | Los verificadores son el contrato; cada hito actualiza ASSET v2 antes de producir | todos |
| R13 | Bandwidth en hordas (200 zombis en interés) supera 30 kB/s | Baja | Medio | HUD de red > 30 kB/s | Bandas de frecuencia, presupuesto por paquete (recorte a 12 kB/s), keyframes cada 1 s | M4 |

---

## 10. No objetivos (v2.0)

1. **Cámara al hombro / tercera persona.** Todo el diseño técnico (streaming, LOD, presupuestos) asume que nunca se ve más allá de ~45 m.
2. **NPC supervivientes con moral, comercio o diálogos.** La historia se cuenta con notas, radios, cadáveres y escenografía.
3. **Construcción libre por vóxeles o piezas ilimitadas.** Base = reclamar edificio + ranuras + 6 piezas colocables.
4. **Hordas de 500 individuales, VAT/MultiMesh de zombis, flow fields.** Hordas de 100–120 con L2.
5. **Infección mortal con permadeath por defecto.** Fiebre curable; `permadeath` solo como opción.
6. **Zombis que excavan/construyen.**
7. **Botín instanciado por jugador por defecto.** (`personal_loot_bags` como opción.)
8. **Cientos de armas.** 13 + arrojadizas + 7 modificaciones.
9. **Voz, lista de servidores pública, relé/UPnP, Steam, plataformas móviles/Web, doble precisión, Terrain3D, netfox.**
10. **Texturas/UVs.** La paleta vive en el color de vértice.

---

## 11. Índice de documentos

- `docs/PLAN_MAESTRO.md` — este documento (visión, decisiones, mundo, roadmap, riesgos).
- `docs/v2/GDD_MUNDO_ABIERTO.md` — diseño completo v2 (números, tablas, textos).
- `docs/v2/ARQUITECTURA_V2.md` — arquitectura técnica v2 (red, mundo, IA, persistencia, servidor, tests, migración fichero a fichero).
- `docs/v2/ASSET_SPEC_V2.md` — contrato de arte v2 (convenciones, esqueleto, animaciones, kits, vehículos, armas, presupuestos, verificación, migración de los 33 assets).
- `docs/research/01..04` — investigación (fuentes de las cifras).
- `prototypes/netpoc`, `prototypes/animpoc` — pruebas de concepto superadas (base de M1 y del rig).
