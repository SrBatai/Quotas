# VENTISCA — PLAN MAESTRO (v2: mundo abierto, zombis, co‑op 1–4)

> **Punto de entrada** de la documentación v2. De aquí cuelgan `docs/v2/GDD_MUNDO_ABIERTO.md` (diseño), `docs/v2/ARQUITECTURA_V2.md` (técnica) y `docs/v2/ASSET_SPEC_V2.md` (contrato de arte). Los cuatro documentos son coherentes entre sí: **si algo cambia en uno, cambia en los otros**.
>
> Los documentos del slice (`docs/GDD.md`, `ARCHITECTURE.md`, `ASSET_SPEC.md`) siguen describiendo el código que existe hoy; quedan como referencia de "estado inicial" y se retiran cuando el hito M2 los deje obsoletos.
>
> Fecha: 24‑sep‑2026. Motor **Godot 4.7.2** (GDScript tipado). Arte **Blender 5.0.1 (bpy)**. Equipo: planificación y código = agentes **Fable**; modelado, rigs, animación y kits = agentes **Opus**.
>
> **Actualización v3 (26‑sep‑2026).** Tras M4 manda la **Parte II — Roadmap v3** (al final de este documento): gráficos G2, ciudad de **Altavega** en un mundo de 6 × 6 km, mundo vivo, peligros invernales y HUD «Susurro». El texto de esta Parte I (§0–§11) se conserva como historial; donde algo queda sustituido o enmendado lo indica una **Nota v3**. Resumen en lenguaje llano para el propietario: `docs/PLAN_V3_RESUMEN.md`.

---

## 0. Resumen en una página

- **Qué hacemos**: convertir el slice VENTISCA (claro nevado de 160 × 160 m, un jugador, lobos) en un **juego de supervivencia post‑apocalíptico invernal de mundo abierto** (3 × 3 km) con **pueblos, aldeas, coches, armas y zombis**, jugable **solo o en cooperativo PvE de 1–4** en **servidores dedicados autoalojados**, con PvP y fuego amigo como opciones del servidor.
- **Cómo se ve**: la misma cámara alta tipo isométrica de la referencia (apuntado con ratón, interiores en corte), el mismo low‑poly de colores planos sobre nieve azulada.
- **Decisiones fijadas por el usuario (vinculantes)**: cámara A (alta, seguimiento, corte de interiores); co‑op PvE 1–4 con PvP/fuego amigo por configuración; servidores dedicados propios; Godot 4.7.2; Blender 5.0.1; Fable = código, Opus = arte.
- **Las cuatro decisiones técnicas que ordenan todo lo demás** (detalle en §3): (1) servidor dedicado autoritativo siempre, incluso en solitario; (2) mundo determinista por semilla en chunks de 64 m + solo *deltas* persistidos en SQLite; (3) IA de zombis por niveles (LOD) en el servidor con replicación propia comprimida; (4) arte con esqueleto humanoide único + color de vértice + kit modular fusionado por grupos de corte.
- **Camino**: 13 pases (M0…M10, con M6 y M9 partidos), cada uno entregable por **1 agente Fable + 1 agente Opus** y cada uno **jugable y probado automáticamente**. Lo arriesgado va primero: red (M1–M2) y mundo por chunks (M3) antes que contenido.

> **Nota v3:** el mundo pasa a 6 × 6 km con la ciudad de Altavega (C25–C26), el post‑apocalipsis es habitado (C32), el invierno trae 13 peligros (C33) y el HUD sigue la dirección «Susurro» (C34). El camino tras M4 es el de la Parte II §v3.7: M5–M10 intercalados con los hitos W, C, V, E, G2 y H, en carriles paralelos.

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
| C19 | **Velocidades** | Jugador: andar **2.2 m/s**, correr **6.0 m/s** (gasta aguante), agachado **1.3 m/s** (**decisión M1, vinculante**: `Balance.WALK_SPEED/RUN_SPEED/CROUCH_SPEED`; las animaciones esqueléticas `Loco_Walk/Run` y `Crouch_Walk` se autoran a estas velocidades de apoyo). Caminante 1.2, corredor 5.5 (ráfagas), reptador 1.0. | El slice tenía `WALK_SPEED = 4.0`; 02 y 04 proponían 3.0. En M1 se fija 2.2 para que el ciclo de andar (cadencia y zancada legibles desde 22 m) coincida con la locomoción generada por Opus y para que andar siga siendo más rápido que el caminante (1.2) pero claramente más lento que correr; la diferencia andar/correr (×2.7) hace que correr sea una decisión (aguante, ruido). | 02 §3.1; 04 §4.5; M1 |
| C20 | **Fuego amigo y PvP** | `friendly_fire = off \| reduced \| full` = multiplicador de daño jugador→jugador **para toda fuente** (0 / 0.25 / 1.0; explosivos ×0.5 adicional en `reduced`). `pvp = false \| true`: con `true`, el daño entre jugadores de **distinta facción** es siempre ×1.0, los jugadores **colisionan** entre sí y se activan sistema de seguridad (30 s), facciones, casas seguras, candados y robo de vehículos; dentro de la misma facción sigue mandando `friendly_fire`. Ambos se consultan en **un único punto**: `DamageResolver.apply(...)`. | 02 definía FF en tres niveles y PvP con zonas seguras; 03 definía `pvp` = armas y `friendly_fire` = colateral. La definición fusionada no tiene huecos (una bala "accidental" y una "deliberada" son indistinguibles para el servidor). | 02 §4.7, §10.4; 03 §3.4, §7 |
| C21 | **Población de zombis** | Densidad objetivo **por chunk (64 m)**: bosque 0–1, aldea 3–8, pueblo 10–25, comisaría/hospital 16–33, control militar 40+. Sin reaparición hasta 72 h de juego sin jugador a < 150 m y solo hasta el 60 %. | 01 daba densidades por 100 m² y 02 por celda de 100 × 100 m; se convierten a la unidad real del motor (chunk). | 01 §5.1.9; 02 §3.3 |
| C22 | **Tirada de botín** | **Determinista en el servidor la primera vez que un jugador abre el contenedor** (`rng.seed = hash(world_seed, container_wid, rolled_day)`), persistida como delta. Reabastecimiento = borrar la fila cuando el chunk lleva 72 h sin visitas → se vuelve a tirar al 60 % (`loot_respawn`). Topes `nominal` por categoría (munición/armas) por región. | Une el modelo "tirar al abrir" (01) con la economía nominal/mínimo de DayZ (02) sin guardar botín que nadie vio. | 01 §5.1.8, §8.2; 02 §6.3 |
| C23 | **Animación** | **Esqueleto humanoide único** (22 huesos con nombres exactos de `SkeletonProfileHumanoid` + 5 sockets), **skin rígido por pieza**, animaciones **generadas por script** (locomoción por generador cíclico con IK analítica; acciones por poses clave), exportadas como `AnimationLibrary`, **in‑place sin root motion**, `AnimationTree` con capa de torso filtrada. Lobo y ciervo siguen con piezas rígidas (`quadruped_animator.gd`) hasta M9b. Librerías externas CC0 (Quaternius UAL) **solo si se pueden descargar**; no son un requisito de ningún hito. | Verificado en el PoC (pies sin deslizamiento, retarget, ragdoll). Mixamo/Synty prohibidos por licencia. | 04 §0–§7; PoC |
| C24 | **Wolves/fauna** | Se mantienen (lobos de noche, ciervos, caza con arco en M5) y pasan por el mismo `DamageResolver`, `SoundEvent` y LOD que los zombis. | Ya existen y encajan con el frío como enemigo. | GDD slice §12; 02 §2.4 |

> **Nota v3:** C6 queda **sustituida** por C25 (6 144 m, 96 × 96 chunks, el valle intacto en el cuadrante noroeste). Quedan **enmendadas**: C2 por C29 (dos materiales compartidos, `window_city`, atlas `signage` y de calcomanías), C8 por C26 (las torres apilan grupos de plantas ya fusionados), C9 y C21 por C32 (humanos, estatuas congeladas, población por planta, densidades urbanas) y C23 por C30 (fauna CC0). Decisiones nuevas C25–C37 en la Parte II §v3.2.

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

> **Nota v3:** la fila «Cámara» tiene las cifras previas a G1; las vigentes son las del código (`balance.gd`): −48°, FOV 36°, 24 m, zoom 16–38 m, más el perfil de cámara urbano de C28. En «Corte de interiores», la mejora «Stencil (4.5+) como mejora opcional en M10» queda **sustituida** por el corte urbano (C27). La regla de addons no cambia: `winterize` es una herramienta de Blender y no entra en el proyecto de Godot (C30).

---

## 4. El mundo

> **Nota v3:** este valle (mapa de §4.2 y regiones de §4.3) se conserva **sin cambios** como cuadrante noroeste del mundo de 6 × 6 km (C25). El mapa de 48 × 48 caracteres y las regiones nuevas están en `docs/research/09_ciudad_mundo_vivo.md` §4.2–4.3; resumen por áreas e hitos en la Parte II §v3.5.

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

> **Nota v3:** desde el 26‑sep‑2026 se trabaja en **carriles paralelos** (U código UI, R código mundo/render, J código juego, A‑ciudad y A‑juego arte) con propiedad de ficheros (C37, Parte II §v3.6). La unidad sigue siendo «1 Fable + 1 Opus por hito» con esta misma definición de hecho.

---

## 7. Roadmap por hitos

Tamaños: **S** ≈ medio pase, **M** ≈ un pase holgado, **L** ≈ un pase completo con alcance ajustado (si un L se desborda se recorta alcance, nunca tests). Cada hito termina **jugable** y con **tests automáticos como criterio de aceptación**.

Orden y razón: **M0** paga la deuda de convenciones (barato ahora, carísimo después). **M1–M2** hacen el refactor más arriesgado (autoloads de un jugador → servidor autoritativo con estado por jugador) mientras el juego sigue siendo el slice. **M3** abre el mundo (streaming, determinismo). **M4–M5** convierten el slice en juego zombi (IA a escala, combate, armas, botín, persistencia real, servidor operable). **M6–M7** añaden aldeas, carreteras y coches. **M8** profundiza el frío, la base y la progresión. **M9** trae el pueblo y el director completo. **M10** cierra la meta y el lanzamiento.

> **Nota v3:** M0–M4 están hechos. El **orden** de esta sección queda sustituido por el roadmap v3 (Parte II §v3.7). El **contenido** de M5–M10 sigue vigente con los cambios de la Parte II §v3.8.4; en particular, el tablón, los *pings* y el mapa de papel de M10 pasan a H3–H5, y el stencil de corte de M10 desaparece (C27).

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
- **Estado M3 (código)**: hecho; detalles en ARQ v2 §8.9. Desviaciones:
  - la rejilla conserva la convención de M2 (el chunk 24 centrado en el origen, el claro = chunks 23–25);
  - las huellas siguen en el mapa de rastro de G1 (`Footprints`, espacio mundo) en vez de un `SubViewport` nuevo;
  - el lago grande es de hielo plano y seguro (el hielo fino llega en M8);
  - `cabin_small` y `lookout_tower` usan un corte v2 provisional (`PoiCutaway`) hasta el `CutawayManager` de M6a;
  - no se integra el kit de casas.

  Puertas nuevas en `tests/run_all.sh`:
  - `run_determinism.sh`;
  - `run_perf_walk.sh --cpu` (2 ms/frame) y `run_perf_walk.sh` (xvfb/llvmpipe: suelo y memoria);
  - `run_net_test.sh --scenario far` (2 clientes a ~1 km).

### M4 — Zombis, navegación y combate cuerpo a cuerpo · **L (código) + M (arte)**

- **Objetivo**: 100 zombis alrededor del claro a 60 FPS con 4 jugadores; matar, ser derribado y reanimado; fuego amigo/PvP funcionando como reglas de servidor.
- **Fable**: `nav_baker` (async por chunk, colisionadores estáticos), `nav_query_queue` (≤ 40 consultas/tick, rutas compartidas por grupo); `ZombieSystem` SoA (L1–L3) + pool de `CharacterBody3D` (L0); `ZombieBrain` (idle/wander/investigate/chase/attack/hit/dead/frozen), sentidos (cono 120°, oído por `SoundEvent`, olfato mínimo), memoria; `population_manager` (densidad por chunk, durmientes, congelado por frío); `Director` v0 (intensidad, acumulación/pico/alivio, hordas errantes); replicación propia de zombis (enter/leave, snapshots 8 B, bandas); `ZombieView` pool + `AnimationTree` + LOD de animación + ragdoll a < 25 m; `DamageResolver` completo con `pvp`/`friendly_fire`; melee validado (cono, alcance + 0.5 m, rebobinado); *hitstop*, sacudida, sangre en nieve; anillo de ruido en el mundo; empujón/pisotón/ejecución a congelados; **derribado/reanimar/muerte/reaparición/cadáver**; aguante; `tests/perf_horde.gd` (200 zombis en el claro, servidor headless: tick ≤ 8 ms) y escenario de red `zombies` (bandwidth ≤ 15 kB/s típico).
- **Opus**: especiales lote 1 (corredor, reptador, congelado con esquirlas, hinchado); `anims`: `Zom_Run`, `Zom_Run_Tired`, `Zom_Crawl`, `Zom_Grab`, `Zom_Knock_Door`, `Zom_Stagger`, `Zom_Knockdown`, `Zom_GetUp`; jugador: `Melee1H_Light_A/B`, `Melee2H_Swing_A/B`, `Melee_Charged`, `Act_Shove`, `Act_Stomp`, `Act_Execute`, `Hit_Front`, `Hit_Back`, `Down_Crawl`, `Down_Idle`, `Act_Revive`, `Act_GetUp`, `Death_A` (+ configuración de ragdoll); props gore‑lite (muñones, cabeza fragmentada).
- **Aceptación**: `perf_horde` en presupuesto; escenario `zombies` con 4 clientes: mismos zombis mueren en todos, derribado → reanimado → muerto → reaparece en la cama; `friendly_fire=off` sin daño y `full` con daño; `pvp=true` → colisión entre jugadores; `run_smoke.sh` ampliado (spawn de 20 zombis, matar 1, congelado despierta por ruido).
- **Dependencias**: M3 (navmesh por chunk). **Riesgo**: R1 (CPU de IA).
- **Estado M4 (código)**: hecho; los detalles vinculantes están en ARQ v2 §10.7. Desviaciones:
  - **Rutas**: la mayoría de los zombis no piden ruta. Una consulta de `NavigationServer3D` cuesta 1–2 ms en un mapa
    de 25 chunks, así que un zombi con el camino despejado (rayo a la altura de la rodilla, ≤ 14 m) va en línea
    recta. Solo pide ruta cuando algo se interpone. Las consultas van acotadas (1 200 polígonos, 90 m) con un
    máximo de 1.5 ms por tick, además del tope de 40.
  - **Navmesh**: la geometría fuente se construye en código y se hornea en `WorkerThreadPool` (de uno en uno, sin
    competir con el streaming), en lugar de usar `parse_source_geometry_data` más el horneado asíncrono. Solo se
    hornea el anillo de cada jugador (≤ 96 m), y no mientras va a más de 8 m/s. Las costuras se cosen con vértices
    exactos en lugar de `edge_connection_margin`, porque esa búsqueda es O(aristas libres²): 150–230 ms por
    reconstrucción del mapa, que rompía el p99.9 de perf walk.
  - **Instantáneas**: ocupan 9 B por zombi, no 8, porque llevan la altura en un i16.
  - **Colisión**: los jugadores no chocan con los zombis (la predicción del cliente sigue siendo exacta). Entre
    zombis, separación por *spatial hash*, sin RVO.
  - **Director**: v0 simplificado. Tiene presupuesto, fases y eventos (horda, despertar congelados), pero no tiene
    hordas L2 persistentes ni zonas fusionadas.
  - **Muerte del zombi**: se usa el clip de muerte y se mantiene la pose final; no hay ragdoll.
  - **Animación del jugador**: los golpes usan un OneShot de torso, salvo los de cuerpo entero (pisotón, ejecución,
    derribo, levantarse). El golpe cargado sostiene la pose `hold_start` mientras se carga; los demás jugadores solo
    ven el golpe desde `hold_end`.
  - **Derribo**: solo el daño de combate derriba; el frío y el hambre matan directamente. El cadáver es una
    estructura `corpse` que se guarda en el `ChunkDelta`.
  - **Golpe**: el daño se evalúa en el `hit_start` del clip (`data/anim_events.json`). La ejecución mata en el
    primer `stab`, a los 0.7 s, con la víctima sujeta.
  - **Gore‑lite**: un crítico que mata o un pisotón revientan la cabeza (hueso `Head` a escala 0 +
    `gore/head_fragments`). No hay miembros cortados.
  - **P1 aplazado**: agarre (`Zom_Grab`), golpear puertas (`Zom_Knock_Door`), pulido del corredor cansado,
    desmembramiento de brazos y sincronizar la animación de ejecución en la víctima.

  Puertas nuevas en `tests/run_all.sh` y en CI:
  - `run_net_test.sh --scenario zombies` (4 clientes, bloqueante);
  - `run_perf_horde.sh` (200 zombis + 4 bots, tick mediano ≤ 8 ms; en CI con `continue-on-error`);
  - smoke ampliado (194 comprobaciones);
  - captura `RENDER=forward tests/run_screenshots.sh <dir> zombies`.

  Cifras de `taskset -c 0,1 tests/run_all.sh` (2 núcleos de una VM compartida), **ALL PASSED**:

  | Puerta | Resultado |
  |---|---|
  | `perf_horde` | tick ocupado p50 5.5 ms (4.9–6.2 entre ejecuciones; presupuesto 8), p99 9.6 ms. `ZombieSystem` p50 2.4 ms, `ZombieNet` 1.3 ms. 10 kB/s de datos de zombis por bot. Rutas: 7.8/s a ≈ 1 ms cada una |
  | Escenario `zombies` | 4.9 kB/s de bajada por cliente (máx. 6.7) con ~94 zombis; el límite es 15 |
  | `perf_walk --cpu` | streaming p99 1.86, p99.9 2.03 y máx. 3.2 ms (como en M3) |
  | Resto (`basic`, `shared_world`, `far`, determinismo, perf probe, `inspect_models`, persistencia) | en verde |

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

> **Nota v3:** riesgos nuevos R14–R30 (ciudad, CC0, precisión lejos del origen, tamaño del repo, carriles paralelos, HUD mínimo) en la Parte II §v3.11.

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

> **Nota v3:** el no objetivo 2 queda **enmendado** (supervivientes humanos limitados: ≤ 12 activos, sin diálogos, trueque por menú) y el 10 admite excepciones cerradas (atlas `signage`, calcomanías, LUT, humo). La Parte II §v3.12 añade no objetivos nuevos (tráfico civil vivo, *skyline* en la cámara de juego, *occlusion culling* en ciudad…).

---

## 11. Índice de documentos

- `docs/PLAN_MAESTRO.md` — este documento (visión, decisiones, mundo, roadmap, riesgos).
- `docs/v2/GDD_MUNDO_ABIERTO.md` — diseño completo v2 (números, tablas, textos).
- `docs/v2/ARQUITECTURA_V2.md` — arquitectura técnica v2 (red, mundo, IA, persistencia, servidor, tests, migración fichero a fichero).
- `docs/v2/ASSET_SPEC_V2.md` — contrato de arte v2 (convenciones, esqueleto, animaciones, kits, vehículos, armas, presupuestos, verificación, migración de los 33 assets).
- `docs/research/01..04` — investigación (fuentes de las cifras).
- `docs/research/05..10` — investigación de G1/G2 y v3: arte y render (05, 06, 08), librerías CC0 y `winterize` (07), ciudad, mundo vivo y peligros (09), HUD «Susurro» (10).
- `docs/PLAN_V3_RESUMEN.md` — resumen del roadmap v3 (Parte II) para el propietario.
- `prototypes/netpoc`, `prototypes/animpoc` — pruebas de concepto superadas (base de M1 y del rig).

---

# Parte II — Roadmap v3 (tras M4): gráficos G2, ciudad de Altavega, mundo vivo, riesgos invernales y HUD «Susurro»

> Fecha: 26‑sep‑2026. Punto de partida: M0–M4 hechos (Parte I §7) y G1 integrado (`docs/research/06_graficos_render.md` §9).
> Fuentes de esta parte: `docs/research/07_assets_cc0.md` (librerías CC0, pase `winterize`, manifiesto de licencias,
> dominios), `08_graficos_g2.md` (prioridades y presupuestos de render G2), `09_ciudad_mundo_vivo.md` (cámara, corte
> urbano, mapa de 6 km, distritos de Altavega, mundo vivo, 13 peligros, hitos W/C/V/E) y `10_hud_ux.md` §V (HUD v2
> «Susurro»). Esta parte **no copia** esos documentos: fija decisiones, orden, tamaños, carriles y puertas de
> aceptación. Si una cifra discrepa, manda esta parte y se corrige la fuente. Resumen en lenguaje llano para el
> propietario: `docs/PLAN_V3_RESUMEN.md`.

## v3.0 Resumen en una página (para el propietario)

- **Qué pediste.** Mejores gráficos usando librerías de assets; una ciudad con rascacielos en un mundo más grande y
  «vivido» (coches, animales, supervivientes, convoyes) que siga nevado y con problemas del invierno; y un HUD, unas
  misiones y unos avisos de entrada y salida de zona de nivel AAA.
- **Lo ya decidido contigo (vinculante).** Post‑apocalipsis **habitado**; mapa de **≈ 6 × 6 km con una ciudad**;
  librerías **CC0 reestilizadas al invierno**; HUD **v2 «Susurro»** (la v1 era demasiado pesada).
- **La ciudad se llama Altavega y su río, Albo.** Está al noreste del valle actual, que no cambia ni un metro. El mundo
  crece hacia el este y el sur hasta 6 144 m de lado (cuatro veces la superficie actual). La ciudad queda a medio día a
  pie del claro: el coche pasa a ser imprescindible.
- **El hallazgo que manda.** Con nuestra cámara alta, nada más alto que la cámara (≈ 18 m) entra jamás en pantalla. Un
  rascacielos se ve como su base y su sombra de 200 m, tapa al jugador y a menudo «se traga» la cámara. La respuesta
  (§v3.4): **corte urbano** (se recorta con un tramado lo que tapa, y el edificio cortado se lee como un plano de
  arquitecto), un **perfil de cámara urbano** algo más tendido y alejado en los distritos altos (más fachada, hasta
  ≈ 17 m por encima del jugador), **miradores** en azoteas donde la cámara se levanta y se ve el *skyline*, y el
  *skyline* en el **mapa de papel y el menú principal**.
- **Cómo se verá (G2).** Una sola nieve, luz y niebla para todo. La ciudad y el tráfico salen de librerías CC0 pasadas por
  nuestro filtro invernal (`winterize`); la gente, la nieve y la luz siguen siendo nuestras. De noche, ventanas
  encendidas por celdas y barrios apagados.
- **Mundo vivo.** Rastros por todas partes (atascos, grafitis, humo, campamentos), animales que delatan (los cuervos
  levantan el vuelo si algo pasa) y pocos actores humanos con consecuencias (convoyes, helicópteros, comerciantes; los
  saqueadores armados en v2.1). Como mucho 12 humanos activos y sin diálogos.
- **El invierno como sistema.** 13 peligros sobre un `HazardSystem` común (ventisca blanca, tormenta de hielo, ola de
  frío, aludes, hielo fino, red eléctrica, incendios…); 8 entran en v2.0.
- **HUD «Susurro».** En reposo solo una tira de 10 trazos (0,05 % de la pantalla en maqueta; puerta automática ≤ 3 %).
  Todo lo demás aparece al cambiar o al mantener Info. Títulos de zona tipográficos al entrar; un único acento ámbar.
- **Cómo trabajamos.** Por carriles en paralelo (§v3.6). **En curso**: H1 (HUD), W0+G2a (corte urbano y render de
  ciudad) y A1 (pipeline CC0 y primer set urbano). **Siguiente**: W1 (mundo de 6 km). En el tramo 2 se abren el carril de
  juego (M5…) y un segundo carril de arte.
- **Coste.** El trabajo que queda se duplica (doc 09 lo mide en ×2,1 sin contar HUD ni G2). Con 3 carriles de código y 2
  de arte, v2.0 cabe en **≈ 10–11 tramos** (un tramo ≈ un pase de agente); con solo los 3 carriles de hoy, ≈ 19.
- **Qué necesitamos de ti** (§v3.13): (1) abrir unos dominios de red para descargar las librerías oficiales; (2) sí o no
  a dar experiencia por descubrir zonas; (3) confirmar que quieres ver una primera manzana de Altavega pronto (C0);
  (4) confirmar la línea de corte v2.0 / v2.1; (5) aprobar los valores por defecto de «Susurro».

## v3.1 Qué sustituye esta parte

| Parte I / GDD / investigación | Estado en v3 | Dónde |
|---|---|---|
| C6 (3 072 m, 48 × 48 chunks) | **Sustituida** | C25 |
| C2 (un material compartido) | Enmendada: dos materiales compartidos, `window_city`, atlas `signage` y de calcomanías | C29 |
| C8 (una `.glb` por variante, sin ensamblar en vivo) | Enmendada: las torres apilan grupos de plantas ya fusionados | C26 |
| C9 (LOD de IA) y C21 (densidades) | Enmendadas: humanos, estatuas congeladas, población por planta, densidades urbanas | C32 |
| C23 (animación propia; CC0 solo si se puede descargar) | Enmendada: fauna CC0 permitida vía `winterize` | C30 |
| §3.2 «Cámara» (−52°, FOV 35°, 22 m, 14–30 m) | **Sustituida** por las cifras del código (G1) y el perfil urbano | C28, §v3.4 |
| §3.2 «Corte de interiores»: stencil opcional en M10 | **Sustituida** por el corte urbano | C27 |
| §4 El mundo | Se conserva entero como **cuadrante noroeste** | C25, §v3.5 |
| §7 orden de hitos | **Sustituido** (el contenido de M5–M10 sigue vigente con cambios) | §v3.7, §v3.8.4 |
| §7 M10: tablón, *pings*, mapa de papel, stencil | Tablón → H4; *pings* → H3/H4; mapa → H5; stencil eliminado | §v3.8 |
| §9 riesgos | Ampliado con R14–R30 | §v3.11 |
| §10 no objetivos 2 y 10 | Enmendados; se añaden no objetivos v3 | §v3.12 |
| GDD §1, §3.1, §4.5, §6.4, §6.6, §11.3, §11.4, §12.4, §13, §17, §18 | Enmendados | GDD «Addendum v3» |
| Doc 05 (CC0 descartado como base) | Revisado por el doc 07 | C30 |
| Doc 08 P0 «fundido de edificios altos» | Absorbido como capa B del corte urbano (W0 = G2a en lo que se solapan) | C27 |
| Doc 09 «*pitch* urbano −55°» (descartado) | Se mantiene descartado; el perfil urbano va en sentido contrario (más tendido) | C28 |
| Doc 10: «Albarrán», «Río Albar», Info en Tab | Sustituidos | C36, C34 |

## v3.2 Decisiones nuevas (C25–C37)

Continúan la tabla maestra de §3.1 y son igual de vinculantes.

| # | Tema | Decisión | Por qué | Fuente |
|---|---|---|---|---|
| C25 | **Mundo v3** (sustituye C6) | **6 144 × 6 144 m = 96 × 96 chunks de 64 m** (C7 sin cambios). El valle de la Parte I queda en el **cuadrante noroeste con sus coordenadas, índices de chunk (`CENTER_CHUNK = 24`) y `wid` intactos**; el mundo crece hacia +x (este) y +z (sur): extensión −1 568 … +4 576 m, muro jugable x, z ∈ [−1 450, +4 420] (`WALL_MIN`/`WALL_MAX` por eje), niebla del borde por distancia al muro más cercano. Macro **768² a 8 m/px** con biomas 6–15 nuevos + *splines* (A‑14, rondas, Gran Vía, N‑140 sur, Carretera del Puerto, ferrocarril). Precisión simple; **el servidor trabaja siempre en coordenadas absolutas**; desplazamiento de origen solo en el cliente y solo como plan B de R23. SQLite (M5) nace con claves de 96², `world_version = 2` y `city_version` en `world_meta`. | No cambia ni un hash del valle (determinismo, *perf walk* y deltas siguen valiendo). El trabajo por frame depende de los anillos, no del tamaño del mundo. Hacerlo antes de M5 evita migrar partidas. Chunks de 128 m descartados (generación y navmesh ×4, hibernación gruesa). | 09 §4.1, §4.4, §8.1 |
| C26 | **Ciudad de Altavega** (enmienda C8) | **Híbrido**: trazado **horneado offline** (`tools/gen_city.gd` → `data/world/city/altavega_*.json`: distritos, calles, manzanas, parcelas, arquetipos, alturas, grafo de calles y siluetas de distrito, en cm enteros, con `city_version` congelada por hito); **≈ 14 bloques héroe** a mano como escenas; **familias por gramática** (zócalo + planta tipo + coronación, bpy) para lo enterable; **torres CC0 winterizadas «listas para corte»** para las no enterables; vestido (coches, daños, cadáveres, botín) por semilla `hash64(seed, GEN_CITY, lot_id, …)`. Enmienda a C8: el generador sigue sin ensamblar módulos en vivo, pero **apila grupos de plantas ya fusionados**: `Podium` + N × `FloorGroup` (4 plantas) + `Crown` + `ShadowProxy` (`SHADOWS_ONLY`). Enterables: casco viejo 25 %, ensanche 12 %, Las Torres vestíbulo + 2 plantas en el 30 % y **2 torres héroe** completas, barriada 10 %, polígono y puerto 50 %. | La ciudad es la misma en todos los servidores (se aprende: «nos vemos en la catedral») y el determinismo es trivial (se leen datos). Los héroes dan hitos. Las familias cumplen el contrato de corte que ningún paquete CC0 trae. Hacer a mano 1 500–2 500 edificios es inviable (R5, R15). | 09 §4.5; 07 §3.5 |
| C27 | **Oclusión en ciudad: corte urbano** (sustituye el stencil de §3.2 y el P0 «fundido de torres» del doc 08) | Capas, todas en los materiales compartidos: **(A)** corte por forjado de lo que está en el lado de la cámara y dentro del pasillo cámara → jugador o tapa el suelo a menos de R del jugador (o del punto de mira); **(B)** cápsula tramada cámara → pecho para árboles, farolas, pasos elevados y grúas; **(C)** **tapas de sección** (caras traseras en `cap_color`: el edificio cortado se lee como una planta de arquitecto); **(D)** **siluetas** con `depth_test_inverted` para los jugadores siempre y para zombis/NPC **percibidos**; **(E)** edificio propio con `CutawayManager` (tejado y plantas altas en `SHADOWS_ONLY`, nunca `visible = false`); **(F)** `CityCut.is_cut`, idéntica en GDScript, para el rayo del cursor. Nunca se corta en `IN_SHADOW_PASS`. **Sin stencil y sin *occlusion culling* en la ciudad.** Valores iniciales: muñón 0.4 m, pasillo W 10 m, zona R 16 m (20 m con zoom ≥ 32 m), cápsula Rc 3.5 m (4.5 m), tramado Bayer 4 × 4, transición de planta 0.25 s; el perfil urbano los escala (§v3.4). | Es la única combinación que resiste la **cámara dentro de una torre**: en el prototipo, **100 %** de jugador y zombis legibles a 16/24/38 m, frente a 0–15 % sin corte y 28–59 % solo con la cápsula. Funciona igual en Forward+ y Compatibility. El *occlusion culling* haría desaparecer lo que el corte deja ver. | 09 §3; 08 §3.1 |
| C28 | **Cámara v3, perfil urbano y *skyline*** (sustituye la fila «Cámara» de §3.2) | Cifras vigentes = código (`balance.gd`, G1): *pitch* **−48°**, FOV **36°**, **24 m** (zoom 16–38 m), `far` 70 m, pivote 3 m por delante. **Perfil de cámara por distrito** (§v3.4): *Urbano bajo* −46° y zoom 16–42 m; *Torres* −44° y zoom 18–46 m; transición de 1.5 s al confirmar la zona (misma histéresis que los títulos de zona), **nunca en combate**, conserva el zoom relativo del jugador, desactivable en Opciones; `far` dinámico (≥ 85 m en *Torres*; más la altura del jugador en azoteas). El *skyline* **no** se busca en la cámara de juego: **miradores** (mantener V 1 s: −20°, `far` 1 500 m, siluetas de distrito; 6 en v2.0), **mapa de papel y menú principal** con el *skyline*, **cinemática** corta de llegada al Puente de Hierro. La cámara sigue sin colisionar ni girar sola (guiñada en pasos de 45°); las cuadrículas urbanas van alineadas con los ejes del mundo. | El borde superior del encuadre baja 30° bajo el horizonte: sobre el jugador solo caben 10.3 m a 24 m (15.3 m a 38 m). El perfil gana fachada (17.3 m) y perspectiva vertical sin romper la lectura; el *pitch* más vertical (−55°) del doc 09 mueve la cámara sin enseñar más ciudad. | 08 §1.1; 09 §1, §3.7 |
| C29 | **Materiales v3** (enmienda C2) | **Dos materiales compartidos**: `world_vcol` (props, mobiliario, vegetación: `cull_back`, solo cápsula, `cut_class = 2`) y `world_vcol_struct` (estructura: `cull_disabled`, corte + tapas, `cut_class = 1`); lo variable va por `instance uniform`, sin duplicar materiales. Excepciones con nombre: `window` (con `window_city`: ventanas por celdas, ocupación 20–35 % por *hash*, `city_power` por distrito, `power`/`occupied` por instancia), `glass`, `ember`, `ice_clear`, `emissive_*`, `lamp_red`. **Primeras texturas del proyecto**, cerradas y con verificador: atlas **`signage`** (2048², paleta cerrada, carteles y rótulos; V1) y atlas de **calcomanías** (G2c). Assets de terceros: RGB **graduado en OKLab dentro de gama** (no paleta exacta), AO en `COLOR_0.a`. **Nieve v2 única** (`snow_include`: borde roto, abrigo por AO, barlovento, edad por instancia, deshielo junto a fuentes de calor, escarcha en cristal). | El corte necesita caras traseras solo en la estructura; un material por familia mantiene el orden por material; los carteles pequeños no se leen con color de vértice. | 09 §3.3, §5.2; 08 §3.2, §3.4; 07 §4 |
| C30 | **Assets de terceros CC0** (revisa doc 05; enmienda C23) | Solo **CC0** (MIT/BSD con su aviso copiado); nunca CC‑BY‑NC/ND, EULAs de tienda ni «uso personal». Todo pasa por **`winterize`** (`blender/third_party/`) y por el **manifiesto** `assets/third_party/manifest.json` (repo, commit, ruta, SHA‑256, `License.txt` literal, modificaciones); `verify_third_party.py` falla sin licencia o con otro hash. **Las fuentes no se versionan** (`fetch.py` a una caché fuera del proyecto): solo el `.glb` resultante. Créditos voluntarios a Kenney, Quaternius y Kay Lousberg (`CREDITS.md` generado). Uso: torres Kenney *City Kit Commercial* (+ `low_*`); coches Quaternius (*Cars*, *Zombie Apocalypse Kit*) en primer plano; mobiliario urbano Quaternius/Kenney; industria y puerto Kenney; fauna Quaternius *Ultimate Animated Animals* (M9b). **Siguen siendo propios**: personajes, zombis, vegetación, casas enterables y vehículos conducibles. **No**: KayKit, coches Kenney en primer plano, *Public Transport* del espejo. | Lo eligió el propietario. La prueba convirtió 30 modelos en 48 s con 0 errores de import; con color de vértice ocupan 10 MB frente a 66 MB texturizados. «La ciudad y el tráfico pueden salir de librerías; la gente, la nieve y la luz son nuestras». | 07 §0, §3.5, §4, §5 |
| C31 | **Render G2** | **P0 (G2a)**: corte urbano, nieve v2, ciudad de noche (ventanas por celdas, ≤ 12–16 farolas reales a < 40 m, charcos de luz falsos, balizas), torres por grupos de plantas + proxy de sombra + `visibility_range`, `cast_shadow = OFF` en props < 1 m. **P1 (G2b)**: niebla en capas (exponencial + altura; `FogVolume` y volumétrica solo Forward+), viento y serpientes de nieve, LUT 3D por clima y hora mezclada en CPU, humo, fuego, balizas y bandadas, deshielo visible. **P2 (G2c)**: rodadas persistentes por chunk, calcomanías (mallas en `compat`), SSR por región, SMAA en `alto`, FSR2 opcional, AO de cielo de las torres. **No**: TAA por defecto, DoF, `AreaLight3D`, SDFGI/VoxelGI, HLOD o impostores en la cámara de juego (solo miradores y menú), *occlusion culling* en ciudad. **Presupuestos**: `alto` ≤ 12 ms de día / ≤ 14 ms de noche en ciudad o en ventisca (GPU media, medido en la máquina del propietario), `medio` ≤ 10 ms, `compat` ≤ 16.6 ms; ciudad **≤ 1 000 draw calls típicos / ≤ 1 500 máx.** (`compat` ≤ 700); ≤ 1.5 M tris; ≤ 64 luces visibles (≤ 6 con sombra). El preset `web` del doc 08 queda como presupuesto de referencia, no como plataforma (no objetivo 9). | Medido en 4.7.2: en la escena de ciudad las sombras son el 54 % del frame, no los draw calls (152); la noche con luces reales solo cerca cuesta +10 %. | 08 §0, §3, §5; 09 §4.6, §7.1 |
| C32 | **Población urbana y mundo vivo** (enmienda C9 y C21) | Tres capas: **estática por semilla** (atascos, controles, campamentos, grafitis, ventanas con generador, humo: 0 B/s), **ambiental en cliente** (cuervos que delatan movimiento, ratas, restos al viento, neón) y **dinámica en servidor** (convoyes, helicópteros, quitanieves, radio, lanzamientos, director del mundo, comerciantes; saqueadores en v2.1). **Sin tráfico civil vivo.** C9 sin cambios (≤ 150 L0 por servidor, ≤ 60 por zona); **≤ 12 humanos L0 por servidor**, y con humanos el tope de zombis L0 baja a 130. La ciudad parece llena sin CPU: **estatuas congeladas** en MultiMesh (≤ 300 visibles, 6–12 DC, 0 B/s, no cuentan como esqueletos), **atrapados en coches**, **población por planta** (L3 por planta, se materializa al hornear su tesela), hordas L2 por el grafo de calles. Filtro de interés **vertical** en torres (\|Δy\| ≤ 9 m). Densidades urbanas por chunk: doc 09 §4.3. Red ≤ 15 kB/s típico (C11 sin cambios). | La historia se cuenta con rastros baratos; lo caro (IA humana) se limita y va detrás del director completo (M9b). | 09 §4.4, §5 |
| C33 | **Peligros invernales** (`HazardSystem`) | Un **`HazardSystem`** de servidor con tres escalas: global (`WorldState`: clima, viento, `ice_glaze`, inversión), regional (sectores eléctricos, hielo por masa de agua, carga de laderas, nieve por tramo de carretera) y local (`ChunkDelta`: tuberías, gas, fuego, carga de tejado, vertidos, depósitos de alud). Lo que depende del tiempo se evalúa **perezosamente** al despertar un chunk (nunca con un *tick* global); ≤ 0.5 ms por *tick*. Reglas: todo peligro **se anuncia o se telegrafía** (≥ 3 s, por radio o sonido), **se lee desde arriba**, tiene **contrajuego** e **interactúa con los zombis**. 13 sistemas: 8 en v2.0 (E1: *whiteout*, tormenta de hielo, ola de frío, aludes, hielo fino, congelación por partes; E2a: red eléctrica, incendios) y 5 en v2.1 (E2b). Opciones de servidor nuevas: `fire_spread = off \| buildings \| full` (defecto `buildings` desde E2a) y `military_attitude = neutral \| hostile` (V2a). | Cada sistema da juego legible desde arriba y conecta frío, zombis, vehículos y co‑op. | 09 §6 |
| C34 | **HUD «Susurro»** (sustituye la estética de GDD §13 y la v1 «Escarcha») | En reposo **< 3 % de la pantalla** (puerta automática `ui_idle_coverage`; maqueta: 0,05 %): solo la tira de la barra (10 trazos de 2 px). Todo aparece **al cambiar** (3–5 s y se funde) o **a petición** (mantener Info). **Sin cajas**: texto con sombra, velo radial adaptativo, filetes de 1 px, iconos de línea. Barlow Light/Regular de 16–26 px con versalitas reales; Barlow Condensed ExtraLight **solo** en títulos de zona (76 px); ningún peso por encima de 400. **Un solo acento ámbar** `#FFB454` (prioridad: compañero derribado > fuente de calor con Calor < 30 > objetivo seguido) y **un solo indicador de borde**. Sin minimapa ni brújula: mapa de papel. Base 1920 × 1080; mínimo 16 px (≥ 12 px en Steam Deck). Preajustes *Mínimo* (defecto), *Estándar* y *Completo*. **Info**: el doc 10 lo pone en Tab, que hoy es Fabricación (GDD §3.2); propuesta, que H1 fija: **Alt mantenido** en teclado y **D‑pad ↑ mantenido** en mando (el toque corto sigue siendo zoom), remapeable. Todo lo funcional de GDD §13 (termómetro sentido con desglose, estados con causa, compañeros, *pings*, chat, vehículo, derribado, muerte) se conserva con estas reglas de visibilidad. | El propietario vio la v1 y dijo «muy toscas» y «demasiado en pantalla». Referentes: *The Last of Us Part II*, *Ghost of Tsushima*, *Death Stranding*. | 10 §V |
| C35 | **Zonas (entrar y salir) y misiones** | **Entrar**: `ZoneTracker` por posición del jugador con **histéresis de 12 m y 1.5 s**; jerarquía ciudad → distrito → PDI (se muestra la más profunda); enfriamiento de 90 s por zona y 20 s entre títulos; se aplaza en combate y con un P0. Primera visita: título de 5.6 s (antetítulo «zona descubierta», nombre y una línea de datos: ciudad · electricidad · temperatura · peligro). Re‑entrada: solo el nombre, al 60 %, 2.5 s. En vehículo a más de 40 km/h y en carreteras: **cartel de autovía** 3 s. **Salir**: sin título; una línea P3 solo si la situación mejora («Has salido de la zona militar»). Las zonas especiales (apagón, militar, hielo fino) son **peligros**, no títulos. **Misiones**: tres tipos (principal ◆, secundaria ◇, dinámica ⬡ con caducidad), una sola seguida; línea «objetivo actualizado» de 5 s + lista a petición; rombo de 10 px en el mundo. El **tablón de GDD §11.4 queda absorbido** y se adelanta de M10 a H4. Descubrimiento de zonas y niebla del mapa **compartidos por el grupo** por defecto (`shared_discovery`, `shared_map`); mapa con posición exacta (opción de servidor: aproximada). XP por descubrir: pendiente (D2). | Es lo que el propietario pidió («como en un juego AAA») con la disciplina de «Susurro». | 10 §V.3–V.4; apéndice §6.1–6.4, §6.11 |
| C36 | **Nombres** | Ciudad **Altavega** y río **Albo** (y sus derivados: Torre Albo, Polígono del Albo, Químicas del Albo, Ferrocarril del Albo…). Sustituyen a los nombres de trabajo **«Albarrán»**, **«Río Albar»/«Albar»** del doc 10 y de sus maquetas, que se conservan como historial pero **no** son texto de referencia. Regiones y banners: doc 09 §4.3 (reconciliación en §v3.3). | El doc 09 fija el mapa y todos los nombres; el doc 10 se escribió en paralelo con un nombre de trabajo. | 09 §4.2–4.3; 10 §10.6 |
| C37 | **Carriles paralelos y propiedad de ficheros** | El trabajo se reparte en **carriles** (§v3.6): U (código UI), R (código mundo/render), J (código juego), A‑ciudad y A‑juego (arte). Cada hito sigue siendo «1 Fable + 1 Opus» con contrato escrito y tests como puerta (§6). Cada carril **posee** sus directorios; los ficheros compartidos (`project.godot`, `scripts/autoload/events.gd`, `scripts/data/balance.gd`, `assets/shaders/world_vcol.gdshader` y sus *includes*, `tests/run_all.sh`, `tests/perf_budgets.json`, `docs/`) se tocan con cambios pequeños, anunciados en el informe del hito y con `tests/run_all.sh` en verde antes de fusionar. La UI de los hitos de juego (retícula, vehículo, ropa, base, trueque, menús) la hace el carril U contra señales de `Events` («enganches de UI»). | H1, W0+G2a y A1 ya corren a la vez; sin propietarios, los ficheros compartidos se pisan (R28). | — |

## v3.3 Reconciliación de nombres

| Doc 10 y sus maquetas (nombre de trabajo) | Definitivo | Dónde se aplica |
|---|---|---|
| Albarrán · «Ciudad de Albarrán» | **Altavega** · «Ciudad de Altavega» | Títulos de zona (H2), `LocationInfo`, mapa (H5), carteles (V1), radio (V2a) |
| Río Albar · «Albar» | **Río Albo** | Región `RÍO ALBO` (W1), hielo (E1), mapa |
| «DISTRITO FINANCIERO · Ciudad de Albarrán» | «**LAS TORRES** · Distrito financiero · Altavega» (banner `ALTAVEGA — LAS TORRES`) | H2, C1 |
| Cartel «Albarrán 4 km / SALIDA 12 Distrito Financiero →» | «**Altavega** 4 km / SALIDA 12 **Las Torres** →» | Cartel de autovía (H2), señalización diegética (V1) |
| `map_albarran.svg` (mapa ilustrativo) | Mapa de papel generado del macro real de W1 y de `altavega_lots.json` | H5 |

Regla: las maquetas del doc 10 **no se editan** (son historial); todo texto de juego, dato, captura y maqueta nueva usa
los nombres definitivos. H2 añade un test que falla si aparece «Albarr» o «Albar» como palabra en `data/`, `scripts/` o
`scenes/`. Si el propietario prefiere otros nombres, cambiarlos cuesta una búsqueda y reemplazo mientras no se haya
cerrado H2.

## v3.4 La cámara y el *skyline*: hallazgo y respuesta

**Hallazgo** (docs 08 §1.1 y 09 §1). Con la cámara del código (*pitch* −48°, FOV 36°, 24 m) la cámara está a 17.8 m de
altura y 13.1 m por detrás del jugador, y el borde superior del encuadre baja 30° bajo el horizonte. Consecuencias:

1. Nada más alto que la cámara entra en pantalla salvo muy cerca de ella: sobre el jugador se ven **10.3 m** (≈ 3
   plantas) a 24 m de zoom y 15.3 m a 38 m. **El *skyline* no existe en juego.**
2. Un edificio de 2 plantas en el lado de la cámara tapa al jugador a menos de 3 m; uno de 4–5 plantas, a 10 m. En una
   calle de 12 m eso pasa siempre.
3. Cualquier edificio de 6 o más plantas cuya planta cubra el punto de la cámara **contiene la cámara**: imagen negra o
   una jaula de forjados.
4. Las torres se leen por su base, su azotea baja y su **sombra de más de 200 m** con el sol de invierno.

**Respuesta elegida** (C27 + C28), en cinco piezas:

1. **Corte urbano** como base de la legibilidad (W0+G2a, en curso): capas A–F de C27. Es lo que hace jugable la ciudad.
2. **Perfil de cámara urbano por distrito** (W0+G2a, en curso), para que las torres se lean como torres a pie de calle:

   | Perfil | Distritos | *Pitch* | Zoom (mín.–máx., defecto) | `far` | Altura visible sobre el jugador (zoom máx.) | Suelo visible por delante (zoom máx.) | Corte W / R / Rc |
   |---|---|---|---|---|---|---|---|
   | Valle (hoy) | valle, bosque, aldeas, carreteras | −48° | 16–38 m (24) | 70 m | 15.3 m (10.3 m a 24 m) | 26.5 m | 10 / 16–20 / 3.5–4.5 m |
   | Urbano bajo | casco viejo, ensanche, barriada, puerto, polígono | −46° | 16–42 m (26) | 80 m | 16.3 m | 30.6 m | 10 / 20 / 4.5 m |
   | Torres | Las Torres, Torre Albo, hospital provincial | −44° | 18–46 m (28) | 85 m | **17.3 m** (12.4 m en una fachada 10 m más allá) | 35.4 m | 12 / 22 / 5 m |

   Reglas: se aplica con una transición de 1.5 s cuando el `ZoneTracker` confirma el distrito (histéresis de C35; en
   W0 un disparador por región de prueba); **nunca durante un combate** (pico del director o persecución en los últimos
   5 s: se aplaza); conserva la posición relativa del zoom del jugador dentro del rango; la guiñada no se toca; la
   cámara sigue sin colisionar; opción «Perfil de cámara urbano: sí/no» (H6). Lo que gana es honesto y medido: más
   fachada (hasta 17.3 m, ≈ 4–5 plantas), aristas verticales en perspectiva y más calle por delante; **no** enseña el
   *skyline* (con −44° el borde superior sigue 26° por debajo del horizonte). W0 valida los valores con
   `citycut_probe` y `perf_probe` a zoom máximo; si el zoom de 46 m pasa de 1 000 DC típicos, el máximo baja a 42 m.
3. **Miradores** (C1–C2; el primero, provisional, en C0): mantener V 1 s en un punto marcado inclina la cámara a −20°,
   sube `far` a 1 500 m y dibuja las **siluetas de distrito** (una malla por distrito, 1 DC cada una, con ventanas según
   la red eléctrica). Revelan ≈ 600 m del mapa, columnas de humo y barrios con luz. 3–6 s sin control; cualquier tecla
   cancela. En v2.0: Puente de Hierro y Torre Albo (C1), Torre de Telecomunicaciones y Presa del Cierzo (C2), y en el
   valle la torre de vigilancia (ya tiene `ViewAnchor`) y el Repetidor del Pico (C1). En v2.1: telesilla de Peña Blanca y
   torre de control de la base aérea (C3).
4. **Mapa y menú**: el menú principal usa como fondo el *skyline* de Altavega de noche visto desde un mirador (C0); el
   mapa de papel lleva la ciudad impresa y una cartela con el perfil del *skyline* (H5).
5. **Cinemática** de 6–8 s, saltable, la primera vez que se cruza el Puente de Hierro (C1); nunca en combate.

Y el detalle de las torres se invierte donde la cámara lo ve: **base** (vestíbulo, marquesinas, ventisqueros),
**azoteas bajas** (el tejado es el lienzo: nieve fundida donde hay calor, carámbanos, vapor), **tapas de sección** y
**sombras**.

## v3.5 El mundo de 6 × 6 km: áreas y hitos

Mapa de 48 × 48 caracteres y tabla completa de regiones en `docs/research/09_ciudad_mundo_vivo.md` §4.2–4.3 (y apéndice
A, en formato `PoiRegistry.ASCII`). Distancias desde el claro: Control del Puerto 1.6 km (12 min a pie), catedral 2.2 km,
Las Torres y el puerto 2.7 km (≈ 21 min, medio día de juego), Gran Atasco 4.3 km, base aérea 4.8 km.

| Área | Qué hay | Hitos | Versión |
|---|---|---|---|
| Valle de Valdenieve (cuadrante NO) | Todo lo de la Parte I §4, sin cambios | M5–M10 | v2.0 |
| Sierra del Cierzo y Carretera del Puerto | Divisoria valle/ciudad; puerto de montaña de 1.1 km; Control del Puerto a la entrada | W1, C1 | v2.0 |
| Altavega: casco viejo, ensanche, barriada de San Lázaro, Las Torres | Ciudad procedural + 2 torres héroe (Torre Albo, 45 plantas) | C0 (una manzana), C1 | v2.0 |
| Hitos de Altavega | Catedral, Torre de Telecomunicaciones, Universidad, Presa del Cierzo, Hospital Provincial, Jefatura de Policía, Centro Comercial, Estación Central, Estadio (campo de refugiados) | C2 | v2.0 |
| Río Albo y Puente de Hierro | Río helado de 5.5 km (plano y seguro en W1, hielo fino en E1), puente con control militar | W1, C1, E1 | v2.0 |
| Puerto fluvial y Polígono del Albo | Dársena, grúas, gabarras, naves, central térmica, parque de combustibles, químicas | C2 | v2.0 |
| A‑14 y el Gran Atasco | Autovía N–S de 6 km; 2.2 km de éxodo bloqueado (1 500–2 500 coches) | W1 (trazado), C2 | v2.0 |
| Desfiladero de Peña Roya e ibón | N‑140 sur entre laderas de aludes; lago de montaña con hielo fino | W1 (terreno), E1 | v2.0 |
| Periferia sur y Sierra de Peña Blanca | Base aérea y avión estrellado, Vega Baja, Los Álamos, urbanizaciones del norte y del este, estación de mercancías, área de servicio, estación de esquí, Santa María del Puerto, túnel de Peña Roya (galería a pie), ferrocarril | W1 (terreno y carreteras), C3 | **v2.1** (en v2.0 existen el terreno, las carreteras, el bosque y los campos) |

## v3.6 Carriles de trabajo

| Carril | Agente | Qué lleva | Posee (directorios) | Estado |
|---|---|---|---|---|
| **U** — código UI | Fable | H1–H6 y los enganches de UI de cada hito de juego | `scripts/ui/`, `scenes/ui/`, `assets/fonts/`, `assets/icons/`, `assets/themes/` | **en curso: H1** |
| **R** — código mundo/render | Fable | W0+G2a, W1, C0, G2b, C1, V1, G2c, E1, C2, E2a (v2.1: C3, E2b) y la parte Godot de A1 | `scripts/world/`, `assets/shaders/`, `assets/materials/`, `data/world/`, `tools/`, `prototypes/citycut/` | **en curso: W0+G2a**; **siguiente: W1** |
| **J** — código juego | Fable (el carril original de M0–M4) | M5–M10 y V2a (v2.1: V2b) | `scripts/{ai,combat,net,persistence,player,components,actors}/`, `server/` | se abre en T2 con M5 |
| **A‑ciudad** — arte | Opus | A1, arte de W0/W1/C0, kit de M6a, props de M6b, C1, V1, plantillas de M9a, C2, E2a (v2.1: C3) | `blender/third_party/`, `blender/kits/`, `blender/props/`, `blender/poi/`, `assets/models/city/`, `assets/third_party/` | **en curso: A1** |
| **A‑juego** — arte | Opus | Armas y botín (M5), vehículos (M7), ropa (M8), especiales y cuadrúpedos (M9b), E1 (hielo, alud, animaciones), NPC y vehículos militares (V2a), M10 | `blender/{chars,anims,weapons,zombies}/`, `assets/models/{chars,anims}/` | se abre en T2 con M5 |

Reglas: la de C37 (ficheros compartidos); el arte va **un tramo por delante** del código cuando puede; **el código nunca
depende de un `.glb`** (§6) y el arte nunca lee código. Si no se abren J y A‑juego, J se ejecuta dentro de R y A‑juego
dentro de A‑ciudad, en el orden global de §v3.7 (≈ 19 tramos en vez de ≈ 11).

## v3.7 Roadmap v3: orden global, calendario y dependencias

Tamaños como en §7: **S** ≈ medio pase, **M** ≈ un pase holgado, **L** ≈ un pase completo con alcance ajustado (si un L
se desborda se recorta alcance, nunca tests). Un **tramo** ≈ un pase en todos los carriles a la vez.

### v3.7.1 Orden global

| # | Hito | Carril | Código | Arte | Depende de | Versión | Estado |
|---|---|---|---|---|---|---|---|
| 1 | **H1** Cimientos del HUD «Susurro» | U | M | — | — | v2.0 | **en curso** |
| 2 | **W0+G2a** Corte urbano y ciudad jugable en render | R | M–L | S | — | v2.0 | **en curso** |
| 3 | **A1** Pipeline CC0 y primer set urbano | A‑ciudad (+ R) | S | L | — | v2.0 | **en curso** |
| 4 | **W1** Mundo de 6 × 6 km | R | M | S | M4, W0+G2a (suave) | v2.0 | **siguiente** |
| 5 | **H2** Zonas: entrar y salir | U | M | — | H1, W1 | v2.0 | pendiente |
| 6 | **M5** Armas, ruido, botín, SQLite, operación | J | L | M | M4, W1 (solo el esquema SQLite) | v2.0 | pendiente |
| 7 | **C0** Escaparate de Altavega | R | S | S | W0+G2a, W1, A1 | v2.0 (D3) | pendiente |
| 8 | **H3** Avisos, peligros y grupo | U | M | — | H2 | v2.0 | pendiente |
| 9 | **M6a** Kit listo para corte, carreteras, calle | J | M | L | M5, W0+G2a | v2.0 | pendiente |
| 10 | **G2b** Atmósfera | R | M | S | W0+G2a | v2.0 | pendiente |
| 11 | **H4** Misiones y marcadores | U | L | S | H3, M5 (suave) | v2.0 | pendiente |
| 12 | **M6b** La Herrería y POIs | J | L | M | M6a | v2.0 | pendiente |
| 13 | **C1** Altavega: núcleo urbano | R | L | L | W0+G2a, W1, C0, M6a; M7 (suave) | v2.0 | pendiente |
| 14 | **H5** Mapa de papel y diario | U | L | S | H4, W1, M5; C1 (miradores, suave) | v2.0 | pendiente |
| 15 | **M7** Vehículos | J | M | M | M5, M6b | v2.0 | pendiente |
| 16 | **V1** Rastros y vida ambiental | R | M | M | C1, G2b | v2.0 | pendiente |
| 17 | **H6** Accesibilidad y pulido | U | S–M | — | H5 | v2.0 | pendiente |
| 18 | **M8** Frío v2, ropa, base, progresión | J | L | M | M5, M6b | v2.0 | pendiente |
| 19 | **G2c** Detalle | R | M | S | M7, C1 | v2.0 (recortable) | pendiente |
| 20 | **M9a** Valdenieve, aldeas, granjas, POIs | J | L | L | M6b, M8 | v2.0 | pendiente |
| 21 | **E1** Clima extremo | R | L | M | M8, W1 | v2.0 | pendiente |
| 22 | **M9b** Director, especiales, hordas | J | L | M | M9a; C1 (grafo de calles, suave) | v2.0 | pendiente |
| 23 | **C2** Hitos de Altavega, puerto, industria, Gran Atasco | R | L | L | C1, M9a | v2.0 | pendiente |
| 24 | **V2a** Supervivientes, convoyes y radio | J | L | M | M9b, M7, C1; C2 (suave) | v2.0 | pendiente |
| 25 | **E2a** Red eléctrica e incendios | R | M–L | M | C2, E1 | v2.0 | pendiente |
| 26 | **M10** Meta, co‑op pulido, lanzamiento | J | L | M | M9b, V2a, H6; E2a (suave) | v2.0 | pendiente |
| 27 | **C3** Periferia sur | R | M | L | C2, E1 | **v2.1** | — |
| 28 | **E2b** Peligros urbanos (resto) | R | M | S | E2a | **v2.1** | — |
| 29 | **V2b** Saqueadores y perros | J | M–L | S | V2a, M9b | **v2.1** | — |

### v3.7.2 Calendario por tramos (indicativo)

| Tramo | U · código UI | R · mundo/render | J · juego | A‑ciudad | A‑juego | Qué verá el propietario al cerrar el tramo |
|---|---|---|---|---|---|---|
| **T1** | **H1** (en curso) | **W0+G2a** (en curso) | — | **A1** (en curso) | — | HUD «Susurro» en el valle, casi vacío en reposo; escena de prueba de ciudad con torres CC0 nevadas, corte urbano, siluetas y ventanas de noche; nieve v2 en todo el valle |
| T2 | H2 | **W1** (siguiente) | M5 (armas y botín primero; SQLite al cerrar W1) | props de W1 · kit de M6a | M5 | Mundo de 6 km caminable (sierras, río Albo helado, A‑14, carretera del puerto), aún sin ciudad; títulos de zona al entrar; armas de fuego y guardado real |
| T3 | H3 | C0 · G2b | M6a | kit de M6a · manzana de C0 | M7 | Primera manzana de Altavega en su sitio y *skyline* en el menú; calle con casas enterables cortadas por plantas; avisos y peligros sin banners |
| T4 | H4 | G2b · C1 (herramienta de ciudad) | M6b | props de M6b · kit urbano de C1 | M8 | Niebla por capas y color por hora y clima; La Herrería; misiones con «objetivo actualizado» y marcadores |
| T5 | H5 | C1 | M7 | familias e interiores de C1 | M8 · E1 | **Altavega jugable** (casco viejo, ensanche, barriada, Las Torres con 2 torres héroe y miradores); coches; mapa de papel con el *skyline* |
| T6 | H6 · enganches de M8 | V1 | M8 | V1 | M9b | Ciudad con rastros de vida (atascos, humo, grafitis, cuervos); frío v2, ropa, base y habilidades; opciones de accesibilidad |
| T7 | enganches | G2c | M9a | plantillas de M9a | M9b · E1 | Rodadas que se quedan y detalle a pie de calle; Valdenieve completo |
| T8 | enganches | E1 | M9b | POI héroe de C2 | V2a | Tormenta de hielo, ola de frío, aludes y hielo fino en el río; director completo y especiales |
| T9 | enganches (trueque) | C2 | V2a | POI héroe de C2 · E2a | M10 | Catedral, hospital, estación, estadio, puerto, polígono y el Gran Atasco; convoyes, helicópteros, radio y comerciantes |
| T10 | pulido | E2a | M10 | — | M10 | Barrios que recuperan la luz (y sus alarmas) e incendios; la partida completa de principio a fin |
| T11 | estabilización | estabilización | lanzamiento v2.0 | — | — | **v2.0**: builds de cliente y servidor, *soak* de 30 min |

A‑ciudad es el carril más cargado (≈ 10 pases): si se retrasa, se recorta por la línea de corte (§v3.10), nunca se
para el código.

### v3.7.3 Dependencias

```
U   H1 ──► H2 ──► H3 ──► H4 ──► H5 ──► H6 ──► enganches de UI (M8, V2a, M10)
           ▲ W1                 ▲ C1 (miradores)
R   W0+G2a ──► W1 ──► C0 ──► G2b ──► C1 ──► V1 ──► G2c ──► E1 ──► C2 ──► E2a     ··· v2.1: C3, E2b
               │                     ▲ M6a         ▲ M7    ▲ M8   ▲ M9a
J              └──► M5 ──► M6a ──► M6b ──► M7 ──► M8 ──► M9a ──► M9b ──► V2a ──► M10   ··· v2.1: V2b
A‑ciudad  A1 ──► W1 · kit M6a ──► C0 · M6b ──► C1 ──► V1 ──► M9a ──► C2 ──► E2a     ··· v2.1: C3
A‑juego         M5 ──► M7 ──► M8 ──► E1 · M9b ──► V2a ──► M10
```

## v3.8 Fichas de hitos

Formato de §7: objetivo, alcance de código (Fable) y de arte (Opus), aceptación (tests como puerta) y dependencias. Todos
los hitos mantienen en verde `tests/run_all.sh` y las puertas anteriores.

### v3.8.1 Carril U — interfaz («Susurro»)

#### H1 — Cimientos del HUD «Susurro» · **M (código) + — (arte)** · **en curso**

- **Objetivo**: el HUD actual pasa a v2 mínimo sin perder nada del slice: en reposo solo la tira de la barra; lo demás
  aparece al cambiar o con Info.
- **Código**: fuentes Barlow (Light, Regular) y Barlow Condensed (ExtraLight, Thin) con licencia OFL en `assets/fonts/`;
  `UiTokens` v2 (doc 10 §V.2); `Theme` v2 **sin StyleBox de panel**, `LabelSettings` compartidos (sombra) y variaciones
  `LabelWhisper`, `LabelSmallCaps` (`smcp`/`c2sc`), `LabelZoneTitle`, `LabelNum` (`tnum`); base 1920 × 1080
  (`canvas_items`, `expand`), `SafeArea` y escala de UI; **`HudVisibility`** (máquina de estados por elemento con los
  tiempos de §V.2.4 y §V.3; acción `hud_info`); **`AccentArbiter`** (quién lleva el ámbar y el único indicador de
  borde); barra rápida en tira ↔ iconos; constante única dinámica (anillo de 40 px + número + versalita de estado); arco
  de aguante junto al personaje; viñeta de escarcha de pantalla (`frost_screen`, intensidad 1 − Calor/40) y de daño;
  línea de recogidas; chat que se funde; derribado con indicador único; arreglos del doc 10 §1.3 (selección de la barra
  con mando, números con Info, aviso de ventisca a 60 s, legibilidad del `signpost`); decisión de la tecla Info (C34).
- **Aceptación**: `tests/ui_idle_coverage.gd` (30 s en reposo: área de `Control` visibles con `modulate.a ≥ 0.1`
  **≤ 3 %**); `tests/ui_legibility.gd` (1280 × 800 con la escala de Steam Deck: todo texto ≥ 12 px);
  `tests/unit/hud_visibility_test.gd` (aparece al cambiar, se funde en 3–5 s, Info muestra y oculta) y
  `tests/unit/accent_arbiter_test.gd` (derribado > calor < 30 > objetivo; nunca dos indicadores de borde); capturas
  `hud_day`, `hud_action` y `hud_blizzard_night` comparables a las maquetas v2 a/b/d; CPU del HUD
  ≤ 0.5 ms/frame y ≤ 60 draw calls; `run_smoke.sh` y escenario `zombies` en verde; ningún `StyleBox` de panel en el
  `Theme`.
- **Dependencias**: ninguna (se engancha a `Events`).

#### H2 — Zonas: entrar y salir · **M + —**

- **Objetivo**: avisos de entrada y salida de zona de nivel AAA (C35) con los nombres definitivos (C36).
- **Código**: `LocationInfo` (tipo, zona padre, polígono o radio, peligro, temperatura, electricidad) migrado desde
  `PoiRegistry.REGIONS` y ampliado con las regiones de W1 (incluidas las reservadas de doc 09 §4.3); `ZoneTracker`
  (histéresis 12 m / 1.5 s por posición del jugador, jerarquía, enfriamientos, cola de 1, aplazado en combate y con P0);
  `ZoneTitle` (primera visita 5.6 s con espaciado animado por `FontVariation.spacing_glyph`; re‑entrada 2.5 s; línea de
  datos); cartel de autovía (vehículo a > 40 km/h y carreteras); línea P3 al salir solo si mejora; descubrimiento
  persistente y compartido (`shared_discovery`) con *feed* «Ana descubrió: …»; sonido `ui_zone_discover`; retirada del
  banner permanente del slice; señal `zone_entered` que usa también el perfil de cámara (C28).
- **Aceptación**: `tests/unit/zone_tracker_test.gd` (zigzag sobre un borde: 0 cambios; ≥ 12 m durante 1.5 s: 1 cambio;
  distrito sobre ciudad; enfriamientos; el combate aplaza); capturas `zone_card` (como la maqueta v2 c) y
  `zone_sign_vehicle`; escenario de red `discovery` (A descubre, B llega después y ve el título compacto y el *feed*; el
  descubrimiento sobrevive a reiniciar el servidor); títulos correctos en los 20 puntos de prueba de W1; `run_smoke.sh`
  entra en 2 zonas sin `SCRIPT ERROR`; test de nombres (C36).
- **Dependencias**: H1; W1 (regiones de 6 km).

#### H3 — Avisos, peligros y grupo · **M + —**

- **Objetivo**: que nada crítico se pierda con un HUD que se oculta.
- **Código**: `NotifyRouter` (P0–P3, prelación, cola, fusión, enfriamiento); P0 en el mundo o en la constante afectada
  (sin banner central), P1–P2 una línea de 3 s, P3 línea de recogida; línea de peligro arriba a la derecha que a los 5 s
  queda en icono + tiempo; `HazardStack` con estados previsto → inminente → activo para ventisca y Gran Ventisca, y API
  para E1/E2 (hielo fino, tormenta de hielo, ola de frío, alud, apagón, incendio); arco de daño direccional
  (`player_hit_from`); compañeros (punto y nombre a > 25 m, herido, derribado = indicador único, línea de grupo con
  Info); *pings* básicos (lugar, peligro) replicados; audio de UI (latido, estática de radio, `ui_objective_update`) y
  rótulos de sonido con dirección para los P0 (imprescindibles con un HUD mínimo); enganches de M5 (retícula de
  dispersión rojo/ámbar/verde, munición en la línea de la barra).
- **Aceptación**: `tests/unit/notify_router_test.gd`; captura `downed_coop` (maqueta v2 e) con cobertura ≤ 3 %;
  escenario `zombies` con 2 clientes: el derribo de B llega a A (indicador + audio) en ≤ 0.2 s; ventisca forzada:
  aviso 60 s antes, línea y cuenta atrás; un *ping* de peligro visible en los 4 clientes; `run_smoke.sh` con un P0
  simulado.
- **Dependencias**: H2 (M5 para la retícula, suave).

#### H4 — Misiones y marcadores · **L + S**

- **Objetivo**: misiones que se leen como en un AAA sin panel fijo; adelanta el tablón de M10.
- **Código**: `MissionComponent` (principal, secundaria y dinámica con caducidad; varios lugares; una seguida);
  adaptador del `quest_state` del slice y del onboarding de los días 1–3 (GDD §16); tablón v0 (secundarias generadas por
  el mundo: alarma, Gran Ventisca, rastro de horda; GDD §11.4); línea «objetivo actualizado» (5 s, filete ámbar) y ✓ en
  el mundo; lista a petición (velo lateral: misiones, encargos, en la radio); `WorldMarkers` (pool de 24 rombos,
  distancia solo con foco o Info, 30 Hz); `EdgeRail` (un solo indicador fuera de Info; agrupación); «calor cercano»
  (Calor < 30: el ámbar pasa al refugio o la fogata conocida más cercana); rueda de *pings*; «Orientarse» (estela de
  20 m durante 4 s).
- **Arte**: iconos renderizados de los objetos nuevos que falten; glifos de teclado y mando (SVG, Fable).
- **Aceptación**: `tests/unit/edge_rail_test.gd` (360 direcciones: siempre en el carril, fuera de las exclusiones,
  agrupación); `tests/unit/mission_adapter_test.gd` (el slice produce la misma lista de pasos); onboarding del día 1
  completo en `run_smoke.sh`; escenario `missions` (un paso completado por C aparece en A y B con su avatar); captura
  `missions_open` (maqueta v2 f) con cobertura ≤ 7 %; `ui_idle_coverage` sigue ≤ 3 %; CPU del HUD ≤ 0.5 ms con 24
  marcadores.
- **Dependencias**: H3; M5 (eventos del mundo para el tablón, suave).

#### H5 — Mapa de papel y diario · **L + S**

- **Objetivo**: navegar 6 km sin minimapa; el *skyline* de Altavega en el mapa.
- **Código**: pantalla de papel (`SubViewport` 2D por capas) generada del `macro_map` 768² y de `altavega_lots.json`
  (manzanas impresas, siluetas de distrito, cartela del *skyline*); niebla por grupo persistente (`shared_map`);
  posición exacta (opción de servidor: aproximada); marcas, *pings* y notas a lápiz; cursor con magnetismo; 3 niveles
  de zoom; capas desbloqueables (pronóstico de ventisca, sectores con luz de E2a, rastro de horda de M9b); miradores y
  «Otear» revelan ≈ 600 m; diario con pestañas (misiones, lugares, notas, radio); barra de pestañas v2 sin caja.
- **Arte**: sello del *skyline* renderizado desde un mirador (A‑ciudad, S); el resto del mapa es SVG de Fable.
- **Aceptación**: captura `map` (niebla, ciudad, marcas); escenario `map_fog` (A descubre y B ve la niebla levantada;
  persiste tras reiniciar el servidor); un mirador de C0/C1 revela ≥ 600 m; abrir y cerrar el mapa en `run_smoke.sh`;
  abrir el mapa ≤ 2 ms de CPU (no por frame).
- **Dependencias**: H4, W1, M5 (persistencia); C1 (miradores, suave).

#### H6 — Accesibilidad y pulido · **S–M + —**

- **Código**: preajustes *Mínimo*/*Estándar*/*Completo* y ajuste por elemento (dinámico, siempre, oculto); grosor de
  texto; fondo de texto automático u opaco; Info como alternancia; daltonismo en los acentos; movimiento reducido; TTS
  de P0; rótulos de sonido con dirección; escala «Sofá/TV» (150 %); preajuste de Deck; remapeo; todas las cadenas con
  `tr()`; opciones del perfil de cámara urbano y del radio del corte.
- **Aceptación**: recorrido completo solo con mando (`run_smoke.sh --gamepad`); `ui_legibility` ≥ 12 px en Deck con
  todos los preajustes; ninguna animación de UI por encima de 2 Hz (test sobre las curvas de `UiMotion`);
  `ui_idle_coverage` ≤ 3 % en *Mínimo*; capturas por preajuste.
- **Dependencias**: H5; antes de M10.

### v3.8.2 Carril R — mundo y render

#### W0+G2a — Corte urbano y ciudad jugable en render · **M–L (código) + S (arte)** · **en curso**

- **Objetivo**: decidir con medidas la oclusión, congelar el contrato del kit urbano antes de producirlo y dejar listo
  el render P0 de la ciudad (doc 09 W0 + doc 08 G2a, que se solapan).
- **Código**: `shaders/include/city_cut.gdshaderinc` (capas A, B, C y F de C27); material compartido
  `world_vcol_struct`; `CutManager` (*globals* por frame, uniformes por instancia, transición de planta,
  `SHADOWS_ONLY`); siluetas como `next_pass` (capa D); `CityCut.is_cut` y el rayo del cursor; **nieve v2** en
  `snow_include`; **ventanas por celdas** (`window_city`, `city_power`); farolas reales cerca + `light_pool` (charco y
  halo); **LOD de torres**: grupos de plantas + `ShadowProxy` + `visibility_range` + `cast_shadow = OFF` en props
  < 1 m; **perfil de cámara urbano** (`CameraProfile` por región, transición, bloqueo en combate, `far` dinámico, opción);
  `prototypes/citycut/` (calle‑cañón, cruce en diagonal, azotea); `tests/citycut_probe.gd`; escena «ciudad» de
  `perf_probe` con los assets de A1.
- **Arte**: los dos edificios de prueba listos para corte (torre de 20 plantas: zócalo + 4 grupos + coronación + proxy;
  ensanche de 6 plantas) y `cap_color` en la paleta (los entrega A1); propuesta de ASSET_SPEC_V2 para el kit urbano.
- **Aceptación**: `citycut_probe` en Compatibility y Forward+: jugador ≥ 99 % y zombis ≥ 95 % legibles en las 3 vistas
  a 16/24/38 m y con el perfil *Torres* a 46 m; la sombra de la torre cortada sigue en la calle (píxeles en sombra ±5 %
  frente a sin corte); el cursor selecciona un contenedor a través de un edificio cortado; `perf_probe` «ciudad»: corte
  ≤ 10 % del frame (lavapipe, informativo), ≤ 1 000 DC típicos, primitivas de sombra ≥ 25 % menos que con torres
  completas; de noche, 20–35 % de ventanas encendidas y con `city_power = 0` solo las de generador; capturas del claro
  (día, noche, ventisca, interior) sin regresión con la nieve v2; el perfil urbano entra en 1.5 s al cruzar la región de
  prueba y no cambia durante un combate forzado; `run_smoke.sh` sin cambios; en la GPU del propietario `alto` ≤ 12 ms
  de día (se informa, no bloquea).
- **Dependencias**: ninguna (usa los assets de A1 cuando llegan; placeholders mientras tanto).

#### W1 — Mundo de 6 × 6 km · **M + S** · **siguiente**

- **Objetivo**: caminar (y teletransportarse) por 6 km con el valle idéntico; carreteras, río y sierras nuevas como
  terreno; nada urbano aún.
- **Código**: C25 completo: `WorldConst` 96², muros por eje, macro 768² con biomas nuevos, `gen_macro_map` 48 × 48 con
  las *splines* de A‑14, rondas, Gran Vía, N‑140 sur, Carretera del Puerto y ferrocarril como sellos de terreno; río Albo
  y dársena como hielo plano seguro hasta E1; `PoiRegistry` 48 × 48 con regiones, nombres definitivos y *pads*
  reservados; `Bounds` y niebla por lado; `/tp` con los muros nuevos; tablas de población de 96² en el servidor;
  `perf_walk` con una ruta de 6.5 km por los cuatro cuadrantes; datos de región listos para `LocationInfo` (H2).
- **Arte**: props de cresta y montaña, jalones de carretera, bocas de túnel (abierta y derrumbada), guardarraíles.
- **Aceptación**: **«el valle no cambia»**: hashes de altura, superficie y *scatter* de los chunks con \|x\|, \|z\| <
  1 152 m idénticos a los previos a W1, salvo los de la Carretera del Puerto (lista cerrada en el test);
  `determinism.gd` en 60 chunks de los cuatro cuadrantes; `perf_walk --cpu` de 6.5 km a 25 m/s: p99 ≤ 2 ms y 0 tirones;
  memoria del cliente ≤ 2.5 GB; `run_net_test.sh --scenario far` con 4 clientes en 4 cuadrantes (hasta 5 km entre sí):
  cada uno recibe solo su anillo y el RSS del servidor ≤ 400 MB; banner/región correctos en 20 puntos de prueba.
- **Dependencias**: M4 (hecho); W0+G2a (suave: comparten `world_vcol` y el terreno). **Va antes del esquema SQLite de
  M5.**

#### C0 — Escaparate de Altavega · **S + S** (sujeto a D3)

- **Objetivo**: ver la ciudad pronto y medir sus riesgos (R14, R18, R23) en su sitio real antes de producir el contenido
  de C1.
- **Código**: `data/world/city/altavega_lots.json` v0 (a mano, `city_version = 0`) con una supermanzana de Las Torres
  (4–6 torres CC0 listas para corte y zócalos no enterables) y un tramo de Gran Vía con atasco estático (coches de A1),
  farolas y barreras; ensamblador mínimo de torres (`Podium` + grupos + `Crown` + proxy) leído por el `ChunkJob`; un
  mirador provisional en una azotea de zócalo; siluetas de distrito v0; fondo del menú principal con el *skyline* de
  noche; medida de PCSS a 2.7 km del origen.
- **Arte**: montaje con piezas de A1; Puente de Hierro provisional (bloque); malla de silueta de distrito.
- **Aceptación**: `perf_walk --cpu` Carretera del Puerto → Las Torres a 25 m/s: streaming p99 ≤ 2 ms y 0 tirones;
  `perf_probe` «altavega_c0» de día y de noche ≤ 1 000 DC típicos (Forward+) y ≤ 700 (`compat`); `citycut_probe` en 5
  puntos fijos de la manzana ≥ 95 % (jugador ≥ 99 %); PCSS: la misma torre en el origen y a 2.7 km, diferencia media
  ≤ 3 % en la penumbra (si no, se aplica la mitigación de R23 aquí); hash del fichero de lotes igual en cliente y
  servidor; captura `menu_skyline`; `run_smoke.sh` sin cambios.
- **Dependencias**: W0+G2a, W1, A1.

#### G2b — Atmósfera · **M + S**

- **Objetivo**: *The Long Dark* en cada hora: profundidad entre torres, viento que se ve, vida que humea.
- **Código**: niebla en capas (exponencial + altura; `FogVolume` locales y volumétrica solo en `alto` y en ventisca o
  noche); serpientes de nieve a ras de suelo y arrastre en el terreno; viento por vértice (pinos, cables, lonas);
  `tools/make_luts.py` y 6–8 LUT 32³ (`dia_claro`, `nublado`, `ventisca`, `atardecer`, `noche`, `noche_ciudad`,
  `apagon`, `calor`) con mezcla en CPU; humo (partículas + sprites CC0), fuego, balizas y rotativos, bandadas (render);
  deshielo visible (oscurecer y mojar junto a fuentes de calor).
- **Arte**: sprites de humo (Kenney *Particle Pack*, CC0, por el manifiesto); ajustes de LUT.
- **Aceptación**: hoja de contacto de 8 horas × 3 climas (`run_screenshots.sh … g2b_sheet`); ventisca en la escena
  «ciudad» ≤ +25 % sobre el día en lavapipe (proporción) y ≤ 14 ms en la GPU del propietario (se informa); mezcla de LUT
  ≤ 0.1 ms de CPU por actualización y 0 en reposo; `compat` sin volumétrica conserva la profundidad (captura);
  `perf_walk` sin regresión.
- **Dependencias**: W0+G2a.

#### C1 — Altavega: núcleo urbano · **L + L**

- **Objetivo**: entrar por el Control del Puerto, cruzar el Puente de Hierro y recorrer casco viejo, ensanche, barriada y
  un bloque de Las Torres (hasta 40 plantas; 2 torres héroe con escalera y azotea) a 60 FPS con 4 jugadores.
- **Código**: `tools/gen_city.gd` y `data/world/city/*` (distritos, lotes, grafo de calles, siluetas); `BuildingAssembler`
  de familias; `NavFloorTile` y enlaces de escalera; filtro vertical de interés; población urbana (estatuas en
  MultiMesh, atrapados en coches, población por planta); miradores (Puente de Hierro, Torre Albo, torre de vigilancia,
  Repetidor del Pico); perfiles de cámara por distrito definitivos; cinemática de llegada; `far` dinámico;
  `perf_horde_city`.
- **Arte**: kit urbano (≈ 120 piezas), 4 familias × 5 variantes, 20 sets de interior, set de azotea, props de calle, poses
  congeladas horneadas, Control del Puerto y Puente de Hierro.
- **Aceptación**: hash de ciudad (fichero + vestido de 50 parcelas) igual en cliente y servidor; `citycut_probe` en 10
  puntos aleatorios ≥ 95 %; `perf_walk` urbano (Carretera del Puerto → Gran Vía → ensanche) a 15 m/s: ≤ 1 000 DC
  típicos, p99 ≤ 16 ms, 0 tirones > 33 ms (y `perf_drive` en coche en cuanto M7 esté); `perf_horde_city` (150 L0 + 300
  estatuas + 4 bots en Las Torres): *tick* p50 ≤ 8 ms; escenario de red `tower` (4 clientes en 3 plantas de una torre
  héroe: puertas y contenedores coherentes; el filtro vertical reduce la bajada ≥ 30 %); los miradores revelan el mapa;
  títulos de zona de los 4 distritos; captura desde una azotea con la calle visible.
- **Dependencias**: W0+G2a, W1, C0, M6a; M7 (suave). **Riesgos**: R15, R17, R18.

#### V1 — Rastros y vida ambiental · **M + M**

- **Código**: atascos (rondas y primer tramo de la A‑14), 40 escenas de rastro, grafitis y carteles (letras de malla +
  atlas `signage`), generadores sueltos con ventanas encendidas, humo, tendederos; bandadas (registro en el servidor +
  *boids* en el cliente) que despegan y delatan; ratas; restos al viento; neón y semáforos con generador; paisaje sonoro
  urbano.
- **Arte**: ≈ 12 restos de vehículo, props de campamento y rastro, letras, atlas `signage` (2048², paleta cerrada),
  cuervos, palomas y ratas.
- **Aceptación**: `perf_probe` en un cruce con todo activo: ≤ +0.5 ms de CPU del cliente y ≤ +60 DC; test `flocks` (20
  pasadas de un zombi a 10 m de una bandada: despega 20/20; dos clientes ven el despegue con ≤ 0.2 s de diferencia); el
  escenario `zombies` no sube la bajada más de un 5 %; capturas de día, noche y ventisca en 3 distritos;
  `verify_third_party.py`/verificador de `signage` en verde.
- **Dependencias**: C1, G2b.

#### G2c — Detalle · **M + S** (recortable)

- **Código**: mapa de rodadas persistente por chunk (vehículos, arado, rastro de horda) en `Texture2DArray`; carreteras
  que se cubren en ventisca y se reabren al pasar coches; calcomanías (Forward+) y mallas‑calcomanía (`compat`); SSR solo
  en regiones con hielo o cristal; SMAA en `alto` y FSR2 en el menú de calidad; AO de cielo de las torres en el terreno.
- **Arte**: atlas de calcomanías (aceite, sangre, hollín, escarcha).
- **Aceptación**: `tests/unit/trail_map_test.gd` (sellar, salir y volver a un chunk: mismo hash); carretera cubierta y
  reabierta (capturas); SSR solo activo donde `RegionTracker` lo pide; capturas de calcomanías en Forward+ y `compat`;
  `perf_walk` y `perf_probe` sin regresión > 5 %.
- **Dependencias**: M7, C1.

#### E1 — Clima extremo · **L + M**

- **Código**: `HazardSystem` (global y regional); *whiteout*; tormenta de hielo (`ice_glaze`, resbalones, líneas
  cortadas); ola de frío (gasóleo, baterías, congelación en 60 s → ciudad de estatuas); aludes (cargas, disparadores,
  depósitos, sepultados, excavar); mapa de hielo por masa de agua (río, dársena, ibón y el lago de M8); congelación por
  partes; parte meteorológico de la radio de emergencia; líneas de peligro de H3 para cada uno.
- **Arte**: carámbanos, grietas y agujeros de hielo de río, 3 depósitos de alud, pala; animaciones `Act_Dig`,
  `Buried_Struggle`, `Slip_Fall`, `Act_Pull_From_Ice`.
- **Aceptación**: `tests/unit/hazards_test.gd` (carga y disparo de aludes, grosor de hielo, gelificación, resbalones:
  valores del doc 09 §6); escenario `avalanche` (A dispara un alud con una bomba de tubo en el desfiladero, B queda
  sepultado y A lo desentierra en ≤ 5 s; el depósito corta la N‑140 y persiste tras reiniciar); `run_smoke.sh`:
  `/weather ice_storm` → μ del asfalto 0.15 y un zombi que resbala; cruzar el río a pie sobre hielo medio y romperlo con
  un coche; cada peligro se anuncia ≥ 3 s antes en el HUD.
- **Dependencias**: M8 (modelo térmico), W1 (río y laderas).

#### C2 — Hitos de Altavega, puerto, industria y Gran Atasco · **L + L**

- **Código**: los POI héroe de la ciudad como escenas; ascensores (enlaces con corriente; provisionales hasta E2a);
  generador del Gran Atasco (2.2 km, 1 500–2 500 coches en MultiMesh con índice espacial; zombis atrapados); poblaciones
  por POI; `perf_drive` por la A‑14; miradores de la Torre de Telecomunicaciones y la presa.
- **Arte**: 10 POI héroe (Catedral, Torre de Telecomunicaciones, Universidad, Presa del Cierzo, Hospital Provincial,
  Jefatura de Policía, Centro Comercial, Estación Central, Estadio, Torre Albo completa), sets portuario e industrial.
- **Aceptación**: `perf_drive` por la A‑14 a 30 m/s por el carril libre: 0 tirones; tramo más denso del atasco ≤ 1 000 DC
  típicos; escenario `hospital_provincial` (40–60 zombis, 4 jugadores): 0 desincronizaciones de puertas y contenedores;
  PCSS en el Gran Atasco (4.3 km) con diferencia de penumbra ≤ 3 % frente al origen (R23); capturas de los POI de día y
  de noche.
- **Dependencias**: C1, M9a (plantillas de servicios).

#### E2a — Red eléctrica e incendios · **M–L + M** (v2.0)

- **Código**: `PowerGrid` (≈ 10 sectores; presa y central térmica como fuentes; subestaciones; el grupo elige qué
  sectores reciben corriente; generadores por edificio; ascensores; alarmas; calefacción eléctrica); `FireSystem` (por
  edificio y planta, adosados, ruina; `fire_spread = buildings`); meta «Devolver la luz a Altavega» (para M10).
- **Arte**: variantes quemadas de las familias; chispas y cables caídos; extintor.
- **Aceptación**: `tests/unit/urban_hazards_test.gd` (propagación del fuego, reparto de capacidad de la red); escenario
  `power` (2 jugadores reparan la presa y activan 3 sectores: las ventanas se encienden en ambos clientes, suena al menos
  una alarma y los congelados de un interior calentado despiertan); escenario `fire` (un molotov en el ensanche pasa al
  edificio adosado en 3–5 min y despierta congelados a ≤ 30 m); todo persiste tras reiniciar; `perf_probe` de noche con 4
  sectores encendidos ≤ 16 ms en la GPU del propietario (se informa).
- **Dependencias**: C2, E1.

#### v2.1 — C3 (periferia sur, **M + L**), E2b (resto de peligros urbanos, **M + S**)

- **C3**: base aérea (con Coloso) y avión estrellado; suburbios (Vega Baja, Los Álamos, urbanizaciones del norte y del
  este, con las plantillas de M6b); estación de esquí y Santa María del Puerto; túnel de Peña Roya (galería a pie) y
  desfiladero; ferrocarril con tren nevado; estación de mercancías; área de servicio. Aceptación del doc 09 §8.2 (hashes
  de suburbios, `perf_drive` N‑140 sur → A‑14 → base aérea, escenario `airbase`, túnel a pie en `run_smoke.sh`).
  Dependencias: C2, E1.
- **E2b**: tuberías → inundación → placas de hielo, fugas de gas y explosiones, vertidos, inversión térmica y *smog*,
  carga de nieve y colapso de tejados. Aceptación: `urban_hazards_test` ampliado (ignición de gas, `T(y)` de la
  inversión, carga de tejado); un hangar o nave colapsa tras forzar Gran Ventisca + deshielo; tuberías que revientan al
  calentar un edificio; todo persiste. Dependencias: E2a.

### v3.8.3 Carril A — arte de base

#### A1 — Pipeline CC0 en el repo y primer set urbano · **S (código) + L (arte)** · **en curso**

- **Objetivo**: meter las librerías CC0 en el repo de forma reproducible y con licencias trazables (C30), y entregar el
  primer set de ciudad ya invernal y listo para corte.
- **Arte (Opus)**: `blender/third_party/winterize.py` (import, ajuste por altura de planta, color por esquina,
  clasificación, gradación OKLab, intemperie, nieve con losas y ventisqueros, AO, export) + etapa **«listo para corte»**
  (volumen cerrado, una losa por planta, grupos de 4 plantas, `ShadowProxy`, `Col*`); `packs/<pack>.json`; `fetch.py`
  (URL + SHA‑256, caché fuera del repo); `verify_third_party.py`; `assets/third_party/manifest.json`, un `License.txt`
  por pack y `CREDITS.md` generado. Primer set: 5 torres Kenney × 2–3 variantes (63–104 m) con `low_*`,
  `Tower_Base/Shaft/Top`, `Light_Beacon` y `Smoke_*`; 10 coches de atasco (Quaternius *Cars* y *Zombie Apocalypse Kit*)
  con `Body`/`Glass`/`Snow` separados y anclas `Loot`, `FuelCap`, `Headlight_L/R`; ≈ 30 props urbanos (farolas,
  barreras, pórtico, contenedores, depósito de agua, chimenea); los 2 edificios de prueba de W0 y `cap_color`.
- **Código (carril R)**: plantillas `.import` para `assets/models/city/`; `inspect_models.gd` ampliado a la familia de
  terceros (frente, superficies, `COLOR_0`, anclas).
- **Aceptación**: `verify_third_party.py` → `ALL OK` (formato, gama OKLab, presupuesto de tris por familia, AO, licencia
  y SHA‑256 en el manifiesto); `fetch.py` reproduce las fuentes desde los espejos con los hashes fijados; import en
  Godot 4.7.2 con 0 errores e `inspect_models.gd` en verde; `verify_assets.py` sigue en `ALL OK`; `assets/` crece
  ≤ 25 MB; `CREDITS.md` generado.
- **Dependencias**: ninguna. Alimenta W0+G2a (escena «ciudad»), C0 y M7 (restos de coche).

### v3.8.4 Carril J — juego: cambios v3 en M5–M10 y vida dinámica

El objetivo, el alcance y la aceptación de M5–M10 son los de §7; aquí solo cambia lo que se indica.

| Hito | Tamaño | Tramo | Cambios v3 (código / arte) | Aceptación añadida | Dependencias v3 |
|---|---|---|---|---|---|
| **M5** | L + M | T2 | Esquema SQLite sobre claves de 96², `world_meta.world_version = 2` y `city_version`; armas, ruido y botín pueden empezar antes de W1 (solo el esquema espera). La retícula y la munición las pinta U (H3). Arte en A‑juego. | Escenario `restart` con un jugador en el cuadrante SE (x, z > 3 000): todo persiste; `world_meta` con `world_version = 2`. | M4, W1 (esquema) |
| **M6a** | M + L | T3 | Kit **listo para corte** (contrato de W0: volúmenes cerrados, una losa por planta, tabiques con grosor, `cap_color`); `CutawayManager` con `inside` y tejado/plantas en `SHADOWS_ONLY` (sustituye a `PoiCutaway`); carteles diegéticos legibles a 24 m (doc 10 §7.4). | `citycut_probe` en la calle de prueba ≥ 95 %; el interior de una casa cortada sigue en sombra (±5 %). | M5, W0+G2a |
| **M6b** | L + M | T4 | Plantillas reutilizables como suburbio en C3; señalización de carretera y de Protección Civil (doc 10 §7); farolas con charcos de luz de G2a; títulos de zona (H2) de La Herrería y sus POIs. | Títulos correctos al entrar en la aldea y en los 3 POIs. | M6a |
| **M7** | M + M | T5 | `perf_drive` por la A‑14 a 30 m/s (tramo de W1 con atasco provisional de coches de A1); los restos de coche son CC0 winterizados; el HUD de vehículo y el cartel de autovía los pinta U. | `perf_drive` A‑14 a 30 m/s: 0 tirones. | M5, M6b |
| **M8** | L + M | T6 | Congelación diseñada ya con las fases del doc 09 §6.13 (E1 la completa); hielo fino del lago con el mapa de grosor que E1 extiende al río; paneles de ropa, habilidades y base y el desglose térmico (en Info) los pinta U; el tablón ya no está aquí (H4). | `thermal_test` cubre las fases de congelación. | M5, M6b |
| **M9a** | L + L | T7 | Plantillas de servicios (hospital, comisaría, iglesia, escuela) con variantes urbanas para C2; topes de C32. | — | M6b, M8 |
| **M9b** | L + M | T8 | Densidades urbanas y hordas L2 por el grafo de calles de Altavega; esqueleto cuadrúpedo y fauna CC0 (lobo, ciervo, zorro, husky) que habilita los perros de V2b; acechador con *whiteout* (E1). | `perf_horde` con horda migratoria por una calle de Altavega. | M9a; C1 (suave) |
| **V2a** | L + M | T9 | **Nuevo**: director del mundo, `RadioSchedule`, lanzamientos de suministros, helicópteros, convoyes militares cinemáticos (`military_attitude`), quitanieves de los supervivientes, 3–4 campamentos con comerciante y guardias **estáticos**, trueque y frases cortas (sin diálogo), NPC visibles en ventanas y azoteas. Arte: atuendos de NPC sobre el superviviente, 3 vehículos militares, helicóptero, paracaídas y cajas, animaciones `Trade_Idle` y de guardia. | `tests/unit/world_director_test.gd` (nunca en Gran Ventisca, ≤ 1 evento grande por zona y hora, enfriamientos); escenario `convoy` (2 km de A‑14, se para en el atasco, abre un carril y el carril persiste); escenario `trade` (2 clientes con el mismo comerciante sin duplicar objetos); `perf_horde` con 12 humanos L0 + 130 zombis L0: *tick* p50 ≤ 8 ms; bajada típica ≤ 15 kB/s. | M9b, M7, C1; C2 (suave) |
| **M10** | L + M | T10 | Tablón, *pings* y mapa salen de M10 (H3–H5); el stencil de corte desaparece (C27); meta nueva «Devolver la luz a Altavega» (con E2a); evacuación por el puente norte (base aérea como alternativa en v2.1); el convoy de evacuación es el sistema de V2a; menú con *skyline* (C0) y navegador; onboarding de 3 días con títulos de zona y misiones de H4; `compat` afinado para ciudad (≤ 700 DC). | Escenario `campaign` incluye devolver la luz a 2 sectores; capturas de todas las regiones de v2.0 de día, de noche y en ventisca. | M9b, V2a, H6; E2a (suave) |
| **V2b** (v2.1) | M–L + S | — | Saqueadores (IA de combate humano con coberturas precalculadas, emboscadas, asaltos a bases, retirada al 50 %), perros callejeros, caravanas entre campamentos. | Escenario `raid` del doc 09 §8.2; `perf_horde` con saqueadores activos ≤ 8 ms. | V2a, M9b |

## v3.9 Resumen

| Hito | Nombre | Carril | Fable | Opus | Puertas de aceptación | Versión |
|---|---|---|---|---|---|---|
| H1 | HUD «Susurro»: cimientos | U | M | — | `ui_idle_coverage` ≤ 3 %, `ui_legibility` Deck, `hud_visibility`/`accent_arbiter`, capturas v2 | v2.0 · en curso |
| W0+G2a | Corte urbano y render de ciudad | R | M–L | S | `citycut_probe` ≥ 99/95 %, sombra ±5 %, `perf_probe` ciudad, capturas del claro | v2.0 · en curso |
| A1 | Pipeline CC0 y primer set | A‑ciudad | S | L | `verify_third_party`, manifiesto, import 0 errores, `inspect_models` | v2.0 · en curso |
| W1 | Mundo de 6 km | R | M | S | «el valle no cambia», determinismo 60 chunks, `perf_walk` 6.5 km, `far` 4 clientes | v2.0 · siguiente |
| H2 | Zonas: entrar y salir | U | M | — | `zone_tracker_test`, net `discovery`, test de nombres | v2.0 |
| M5 | Armas, botín, SQLite, operación | J | L | M | §7 + `restart` en el cuadrante SE | v2.0 |
| C0 | Escaparate de Altavega | R | S | S | `perf_walk` al distrito, `perf_probe` ≤ 1 000 DC, PCSS a 2.7 km, `menu_skyline` | v2.0 (D3) |
| H3 | Avisos, peligros y grupo | U | M | — | `notify_router_test`, derribo en ≤ 0.2 s, aviso de ventisca 60 s | v2.0 |
| M6a | Kit listo para corte, calle | J | M | L | §7 + `citycut_probe` en la calle | v2.0 |
| G2b | Atmósfera | R | M | S | hoja 8 h × 3 climas, ventisca ≤ +25 %, LUT ≤ 0.1 ms | v2.0 |
| H4 | Misiones y marcadores | U | L | S | `edge_rail_test`, `mission_adapter_test`, net `missions` | v2.0 |
| M6b | La Herrería y POIs | J | L | M | §7 + títulos de zona | v2.0 |
| C1 | Altavega núcleo | R | L | L | hash de ciudad, `citycut_probe` 10 puntos, `perf_horde_city`, net `tower` | v2.0 |
| H5 | Mapa de papel y diario | U | L | S | net `map_fog`, persistencia, mirador revela 600 m | v2.0 |
| M7 | Vehículos | J | M | M | §7 + `perf_drive` A‑14 30 m/s | v2.0 |
| V1 | Rastros y vida ambiental | R | M | M | `flocks`, ≤ +0.5 ms / +60 DC, bajada +≤ 5 % | v2.0 |
| H6 | Accesibilidad y pulido | U | S–M | — | recorrido con mando, Deck ≥ 12 px, ≤ 2 Hz | v2.0 |
| M8 | Frío v2, base, progresión | J | L | M | §7 + fases de congelación | v2.0 |
| G2c | Detalle | R | M | S | `trail_map_test`, SSR por región, sin regresión | v2.0 (recortable) |
| M9a | Valdenieve y regiones | J | L | L | §7 | v2.0 |
| E1 | Clima extremo | R | L | M | `hazards_test`, net `avalanche`, `ice_storm` | v2.0 |
| M9b | Director, especiales, hordas | J | L | M | §7 + horda por Altavega | v2.0 |
| C2 | Hitos, puerto, industria, Gran Atasco | R | L | L | `perf_drive` A‑14, net `hospital_provincial` | v2.0 |
| V2a | Supervivientes, convoyes, radio | J | L | M | `world_director_test`, net `convoy`/`trade`, 12 humanos + 130 zombis ≤ 8 ms | v2.0 |
| E2a | Red eléctrica e incendios | R | M–L | M | `urban_hazards_test`, net `power`/`fire` | v2.0 |
| M10 | Meta, co‑op, lanzamiento | J | L | M | §7 + `campaign` con la luz | v2.0 |
| C3 | Periferia sur | R | M | L | net `airbase`, túnel a pie | v2.1 |
| E2b | Tuberías, gas, vertidos, *smog*, colapsos | R | M | S | `urban_hazards_test` ampliado | v2.1 |
| V2b | Saqueadores y perros | J | M–L | S | net `raid` | v2.1 |

## v3.10 Línea de corte v2.0 / v2.1

- **v2.0 (lanzamiento)**: H1–H6; W0+G2a, W1, C0, G2b, G2c, C1, V1, E1, C2, E2a; A1; M5–M10 y V2a. Es decir: el valle
  completo, **Altavega** (núcleo + hitos + puerto + polígono + Gran Atasco), el mundo de 6 km con la periferia sur como
  terreno, **8 de los 13 peligros**, vida estática y ambiental, convoyes, helicópteros, radio y **comerciantes
  estáticos** (≤ 12 humanos, sin combate humano) y el HUD «Susurro» completo.
- **v2.1**: C3 (periferia sur: base aérea, avión, esquí, Santa María, suburbios del sur, túnel a pie, tren), V2b
  (saqueadores armados, perros, caravanas), E2b (tuberías, gas, vertidos, *smog*, colapsos), evacuación alternativa por
  la base aérea, set «héroe» texturizado de *Downtown* (si se aprueba) y lo que ya estaba en «Después de v2.0» (§7).
- **Orden de recorte dentro de v2.0 si hay retraso** (de lo primero a lo último): (1) SSR, calcomanías y FSR2 de G2c;
  (2) C2 reducido a 6 POI héroe (hospital, jefatura, estación, estadio, dársena, central térmica) + Gran Atasco;
  (3) incendios de E2a (se queda la red eléctrica); (4) comerciantes de V2a (se quedan radio, convoyes, helicópteros y
  lanzamientos); (5) C0 se funde en C1. **No se recortan nunca**: tests y puertas, corte urbano, H1–H5, W1, C1, M5–M10.
- **Puntos de decisión**: al cerrar **C1** (T5), con el ritmo real de familias e interiores (R15, R27), y al cerrar
  **E1** (T8), con el presupuesto de servidor medido.

## v3.11 Riesgos nuevos

Continúan §9 (R1–R13). R14–R22 vienen del doc 09 §8.5; R23 se precisa; R24–R30 son nuevos.

| # | Riesgo | Prob. | Impacto | Señal de alarma | Mitigación / plan B | Hito |
|---|---|---|---|---|---|---|
| R14 | Legibilidad insuficiente en la ciudad pese al corte | Media | Alto | `citycut_probe` < 95 % o *playtest* confuso | Prototipo al 100 % en calle‑cañón; siluetas más fuertes, R mayor, perfil *Torres* desactivable; plan B: *pitch* urbano más vertical como opción | W0, C0, C1 |
| R15 | Volumen de contenido urbano (kit, familias, interiores, 14 héroes) | Alta | Alto | C1 entrega < 70 % de familias o interiores | Bajar el % enterable; familias parametrizadas (JSON); héroes priorizados; línea de corte §v3.10 | C1–C3 |
| R16 | CPU de la IA humana | Media | Alto | `perf_horde` con humanos > 8 ms | V2a solo con humanos estáticos; ≤ 12 L0; coberturas precalculadas; tope de zombis 130; combates lejanos resueltos en abstracto (L2); combate humano en v2.1 | V2a, V2b |
| R17 | Navmesh multiplanta | Media | Medio | Cola de horneado > 2 s | Teselas por planta perezosas, escaleras como enlaces, ≤ 12 teselas/s | C1 |
| R18 | Tirones de *streaming* en ciudad | Media | Alto | `perf_walk`/`perf_drive` urbano con frames > 33 ms | `PackedScene` por variante, grupos de plantas, precarga, velocidad limitada por el tráfico muerto; se mide ya en C0 | C0, C1 |
| R19 | El generador de ciudad cambia después de publicar | Media | Medio | Hash de ciudad distinto entre versiones | `city_version` + migración explícita; datos congelados por hito | C1+ |
| R20 | Las texturas `signage` y de calcomanías rompen el estilo | Baja | Bajo | Capturas | Paleta cerrada, solo carteles y rótulos, verificador | V1, G2c |
| R21 | El alcance nuevo desborda el plan (×2 de trabajo) | Alta | Alto | Retrasos acumulados tras C1 | Carriles paralelos; orden de recorte y puntos de decisión de §v3.10 | todos |
| R22 | Coste de `discard` + `cull_disabled` en iGPU (`compat`) | Media | Medio | `perf_probe` `compat` fuera de presupuesto | `cut_class = 0` por CPU lejos de la zona; tapas solo cerca; tramado más simple | W0, C1 |
| R23 | **Precisión y PCSS lejos del origen**: el desenfoque PCSS depende de la distancia al origen (#86536) y Altavega está a 2–4.6 km; *jitter* de sombras o de vértices en zoom máximo | Media | Medio | Sombras borrosas o que tiemblan en Altavega; diferencia de penumbra > 3 % entre el origen y 2.7 km (C0) | PCSS solo en `alto` con ángulo ≤ 1.2°; se mide en C0 (2.7 km) y se repite en C2 (Gran Atasco, 4.3 km); plan B: desplazamiento de origen **solo en el cliente** (el servidor, los chunks y los `wid` siguen en absoluto) | W1, C0, C1 |
| R24 | **Disponibilidad y procedencia de los espejos CC0**: `series-ai/jam-ready-assets` o `chibifire-stages/quaternius-stage` desaparecen, cambian o contienen algo no CC0; USD con colores perdidos; *Downtown* incompleto | Media | Medio | `fetch.py` falla por hash o 404; `verify_third_party.py` en rojo | Manifiesto con repo, commit, ruta y SHA‑256; los `.glb` resultantes están en el repo (el juego no depende de la fuente); abrir los dominios oficiales (D1) y reverificar contra el pack oficial; plan B: bpy propio para lo que falte | A1, C1 |
| R25 | **Tamaño del repositorio**: 200–400 `.glb` de ciudad (media 330 kB, torres 0.5–1.5 MB) y sus regeneraciones inflan el historial de git (hoy `.git` 78 MB, `assets/` 15 MB) | Alta | Medio | `assets/models/` > 150 MB o un commit > 50 MB | Fuentes nunca en el repo; exportación determinista y no volver a subir `.glb` sin cambios (comparar hash); presupuesto por familia en `verify_third_party.py` y total en un test; maquetas y capturas en JPG ≤ 400 kB; plan B: Git LFS para `assets/models/city/` (se pedirá al propietario si salta la señal) | A1 y todos |
| R26 | Coherencia de estilo entre CC0 y lo propio | Media | Medio | Capturas que parecen «dos juegos» | Gradación OKLab única, nieve v2 y AO para todo; personajes, zombis, vegetación y casas enterables propios; revisión de capturas por hito | A1, C1 |
| R27 | **El arte es el cuello de botella** (≈ 17–18 pases de Opus frente a ≈ 10 del carril de código más cargado) | Alta | Alto | Hitos que cierran con *placeholders* | Dos carriles de arte; CC0 para relleno; el código no depende de `.glb`; orden de recorte | C1–C2 |
| R28 | **Conflictos entre carriles paralelos** en ficheros compartidos | Media | Medio | Fusiones rotas; tests en rojo tras fusionar | Propiedad de ficheros (C37); cambios pequeños y anunciados; `run_all.sh` antes de cada fusión; integración frecuente | todos |
| R29 | HUD mínimo: los avisos críticos dependen del audio de UI y de los rótulos de sonido | Media | Medio | *Playtest*: «no me enteré de que Ana estaba derribada» | Audio de UI y rótulos en la aceptación de H3; preajuste *Estándar* a un clic; TTS en H6; plan B: banner P0 mínimo opcional | H3, H6 |
| R30 | Perfil de cámara urbano: desorientación, más draw calls a 46 m, más veces la cámara dentro de una torre | Media | Bajo | `perf_probe` a zoom máximo > 1 000 DC; quejas en *playtest* | Transición solo al confirmar el distrito y nunca en combate; desactivable; zoom máximo recortable a 42 m; corte escalado con el zoom | W0, C1 |

## v3.12 No objetivos: enmiendas y nuevos

- **No objetivo 2 (enmendado)**: «**NPC con moral, diálogos o compañeros reclutables.**» Desde V2a hay supervivientes
  humanos **limitados: como mucho 12 activos (L0) por servidor**, **sin diálogos** (ni árboles ni conversaciones; solo
  frases cortas ambientales) y con **trueque por menú**. La historia se sigue contando con notas, radio, rastros y
  escenografía. El combate contra humanos (saqueadores) es de v2.1.
- **No objetivo 10 (enmendado)**: «Texturas/UVs» sigue siendo la regla; excepciones cerradas y con verificador: atlas
  `signage` (V1), atlas de calcomanías (G2c), LUT 3D (G2b) y sprites de humo (G2b). El set «héroe» texturizado de
  *Downtown* queda aplazado (v2.1, si se aprueba).
- **No objetivo 9 (precisión)**: sigue sin doble precisión; el desplazamiento de origen en el cliente solo como plan B
  de R23.
- **Nuevos (v3)**: tráfico civil vivo; *skyline* en la cámara de juego (solo miradores, mapa, menú y cinemáticas);
  *occlusion culling* en la ciudad; HLOD o impostores en la cámara de juego; interiores en todas las torres (solo
  vestíbulos del 30 % y 2 torres héroe); minimapa y brújula; banner central de avisos por defecto.

## v3.13 Decisiones pendientes del propietario

Cinco, con recomendación. Todo lo demás lo decide el plan.

| # | Decisión | Opciones | Recomendación | Si no se decide |
|---|---|---|---|---|
| D1 | **Dominios de red** para descargar las librerías oficiales (doc 07 §6). Se cambia en la configuración del entorno de nube: menú del entorno en la barra de título de la sesión → Editar → acceso a red → añadir dominios permitidos. | (a) Ninguno; (b) prioridad 1 y 2; (c) 1, 2 y 3 | **(b) ya**: `kenney.nl`; `quaternius.com`, `drive.google.com`, `drive.usercontent.google.com`, `www.googleapis.com`. **Grupo 3** (`itch.io`, `api.itch.io` y el CDN de descargas, más una API key gratuita de itch) **en T4**, cuando empiece el kit urbano de C1 (*Downtown City MegaKit* completo). Poly Haven y ambientCG no hacen falta. | Seguimos con los espejos de GitHub (funciona hoy; riesgo R24) |
| D2 | **XP por descubrir zonas** | (a) +10 de Supervivencia al descubrir distritos y pueblos; (b) sin XP: solo revela el mapa y añade una entrada al diario | **(b)**: fiel al GDD §11.1 (XP solo por acciones significativas); el mapa y los miradores ya premian explorar | (b) |
| D3 | **¿Ver Altavega pronto?** (orden M5 frente a ciudad) | (a) **C0** (una manzana de Las Torres en su sitio + *skyline* en el menú) en T3, en paralelo con M6a; ciudad jugable (C1) en T5; (b) sin C0: la ciudad se ve por primera vez en T5; (c) ciudad jugable antes de M5 | **(a)**: cuesta medio pase, adelanta dos tramos lo que el propietario ve y mide los riesgos de C1 (R14, R18, R23). **(c) no**: sin kit, coches ni guardado la ciudad sería una maqueta a medio día a pie y habría que rehacerla. Si solo quedara un carril de código para mundo y juego, C0 iría justo antes de M5. | (a) |
| D4 | **Línea de corte v2.0 / v2.1** | La de §v3.10 u otra | **Confirmar §v3.10**, con revisión al cerrar C1 (T5) | Se aplica §v3.10 |
| D5 | **Valores por defecto de «Susurro»** (doc 10 §V.9 y §10) | Sí / cambiar alguno | **Sí a los seis**: preajuste *Mínimo*; acento ámbar que se mueve por prioridad; sin banner central; sin rastreador fijo (misiones con Info); descubrimiento y niebla del mapa compartidos por el grupo; mapa con posición exacta (opción de servidor: aproximada) | Se aplican los seis |

## v3.14 Documentos

- `docs/PLAN_V3_RESUMEN.md` — resumen de esta parte en lenguaje llano para el propietario.
- `docs/v2/GDD_MUNDO_ABIERTO.md` — «Addendum v3»: mundo y regiones, pilares del mundo vivo, peligros y HUD.
- `docs/v2/ARQUITECTURA_V2.md` y `docs/v2/ASSET_SPEC_V2.md` — cada carril actualiza las secciones que su hito toca
  (lista en doc 09 §8.6: `WorldConst`, generador de ciudad, corte urbano, `NavFloorTile`, `HazardSystem`, interés
  vertical; kit urbano listo para corte, familias, grupos de plantas, poses congeladas, `signage`, familia de terceros).
- `docs/research/07`–`10` — fuentes de esta parte. El doc 10 conserva los nombres de trabajo (C36) y el doc 08 su P0 de
  fundido como historial (C27).
