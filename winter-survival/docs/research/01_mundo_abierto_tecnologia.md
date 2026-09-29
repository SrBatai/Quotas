# 01 — Mundo abierto y tecnología de motor (Godot 4.7.2)

> Investigación técnica para convertir VENTISCA (vertical slice: claro nevado de 160 × 160 m, un jugador) en un juego de **supervivencia zombi, invernal, post‑apocalíptico, de mundo abierto**, con **cooperativo PvE de 1–4 jugadores** en **servidores dedicados autoalojados** (fuego amigo / PvP como opción de configuración del servidor). Motor: **Godot 4.7.2** (estable, 18‑ago‑2026), GDScript. Arte: low‑poly flat‑shaded generado con Blender 5.0.1 (bpy).
>
> Decisiones fijadas por el equipo antes de este documento: **cámara A** (cámara alta de seguimiento, estilo isométrico, como en las capturas de referencia) y **co‑op PvE 1–4**. La cámara al hombro (opción B) se trata solo como *no objetivo* (§1.3).
>
> Documentos hermanos: `docs/GDD.md`, `docs/ARCHITECTURE.md`, `docs/ASSET_SPEC.md`. Fecha: 24‑sep‑2026.

---

## 0. Resumen ejecutivo — decisiones

| Tema | Decisión | Por qué (resumen) |
|---|---|---|
| Tamaño del mundo | **3 072 × 3 072 m (≈ 9.4 km²)**, cuadrícula de **48 × 48 chunks de 64 m**. Arquitectura preparada para 4 096 m (16.8 km²) sin cambiar de sistema de coordenadas. | Con cámara isométrica se ve ≈ 20 × 35 m de suelo; 9 km² ya son 12 min andando de lado a lado, 3 min en coche. SoD2 (co‑op de 4) usa ≈ 5 km² por mapa; Unturned "grande" 16 km². Más mundo = más contenido que llenar, no más diversión. |
| Estructura | **Híbrido "macro autorado, micro procedural"**: mapa macro (biomas, carreteras, posición de pueblos/POIs) dibujado a mano en un plano 2D; terreno, bosque, aldeas y rellenos generados de forma determinista por semilla; POIs clave (cabaña inicial, checkpoint militar, gasolineras, iglesia…) hechos a mano como escenas. | PZ, DayZ y TLD deben su "sentido de lugar" a mapas hechos a mano; 7DTD/Unturned demuestran que el relleno procedural funciona si el macro es legible. Co‑op necesita hitos compartidos ("nos vemos en la gasolinera del norte"). |
| Terreno | **Malla propia por chunk (heightmap 1 m, 65 × 65 muestras) + `HeightMapShape3D` por chunk**, evolución de `terrain.gd`. Terrain3D queda como plan B documentado. | Estilo flat‑color sin texturas, servidor headless que necesita el mismo terreno sin cámara, y una cámara que nunca ve más allá de ~45 m: no necesitamos clipmap de 65 km ni 32 texturas PBR. Terrain3D 1.0.2 soporta 4.4–4.7 oficialmente solo en builds de precisión simple, y su colisión dinámica sigue a la cámara (mal encaje con un servidor sin cámara). |
| Streaming | Chunks de 64 m; cliente carga **anillo 1 (3 × 3) visible + anillo 2 (5 × 5) precargado**; servidor mantiene unión de anillos 1 de cada jugador "calientes" (simulación completa) y anillo 2 "tibios". `ResourceLoader.load_threaded_request` + instanciación en hilo principal con presupuesto de **≤ 2 ms/frame**. | La cámara acota el dibujado, pero los coches (25 m/s) cruzan un chunk en 2.5 s: hace falta prefetch, no distancia de dibujado. |
| Coordenadas | **Precisión simple, sin origin shifting, sin build `precision=double`.** Mundo centrado en el origen (±1 536 m; ±2 048 m si crece). | Godot documenta que juegos top‑down toleran hasta 32k–65k unidades; nuestro máximo es 2k. Doble precisión exige compilar motor y GDExtensions y complica el multijugador. |
| Física | **Jolt Physics** (default en proyectos nuevos desde 4.6; nuestro `project.godot` NO lo activa: hay que añadir `physics/3d/physics_engine="Jolt Physics"`). 60 Hz. | 20× más `CharacterBody3D` antes de degradarse que GodotPhysics (issue #78761). |
| Zombis y navegación | `NavigationServer3D` directo (sin nodos `NavigationAgent3D`), navmesh **horneado por chunk en hilo** a partir de formas de colisión, consultas de ruta escalonadas; RVO solo a < 20 m de un jugador. **Presupuesto: ≤ 150 zombis con cuerpo físico activos en el servidor, ≤ 60 visibles por cliente, hasta ~2 000 "durmientes" sin física.** Flow fields reservados para eventos de horda (v2). | Cifras de rendimiento §5.5 y §7. |
| Vehículos | **RigidBody3D + suspensión por raycast propia** (base: *Godot Easy Vehicle Physics*, MIT, compatible con Jolt), no `VehicleBody3D`. Autoridad del **conductor** con validación del servidor. | Los docs de `VehicleBody3D` lo desaconsejan para simulación seria; necesitamos tracción por superficie (nieve/hielo/asfalto) por rueda. |
| Render | **Forward+** como objetivo (PC medio, 1080p, 60 FPS) con **preset "Compatibility"** de respaldo (misma escena, menos efectos). Sin renderer Mobile. GPUParticles3D para nieve, `SubViewport`/`DrawableTexture2D` para huellas y rodadas, sombra direccional a 60 m, sin occlusion culling. | Con cámara isométrica el coste GPU es pequeño; Forward+ da luces ilimitadas por malla (clave para pueblos de noche) y niebla volumétrica para ventiscas; Compatibility limita a 8 luces por malla y no tiene decals ni HDR. |
| Persistencia | **SQLite en el servidor** (`godot-sqlite`, MIT, funciona en binarios headless) guardando **solo deltas** frente al mundo procedural: contenedores saqueados, puertas rotas, estructuras de base, entidades vivas, jugadores. Escritura diferida por chunk. | Modelo probado (Minecraft/7DTD/PZ guardan solo chunks modificados). |
| Red | Alto nivel de Godot: `ENetMultiplayerPeer`, `MultiplayerSpawner` + `MultiplayerSynchronizer` con **filtros de visibilidad por chunk** (interest management). Servidor autoritativo para mundo, loot, zombis, clima; jugador y coche con autoridad del cliente + validación. PvP/fuego amigo = un flag en la resolución de daño del servidor. | Co‑op entre amigos: prioriza simplicidad y latencia percibida sobre anti‑cheat perfecto. |

---

## 1. Contexto y restricciones

### 1.1 Estado del motor (verificado)

- **Godot 4.7** estable el 18‑jun‑2026; **4.7.2** el 18‑ago‑2026 (57 correcciones; endurecimiento del modelo de hilo principal único; sin cambios incompatibles frente a 4.7.1).
- Novedades 4.4 → 4.7 relevantes para nosotros:
  - **4.4**: Jolt Physics integrado en el motor (opt‑in), interpolación física 3D.
  - **4.5**: **stencil buffer** (efectos de corte/rayos‑X), *shader baker* (menos stutter de compilación de shaders al exportar), SMAA, `NavigationServer.map_force_update()` obsoleto.
  - **4.6**: **Jolt es el motor 3D por defecto en proyectos nuevos** (PR #105737: escribe `physics/3d/physics_engine="Jolt Physics"` en el `project.godot` de proyectos creados desde el gestor o con `touch project.godot`; los proyectos anteriores no cambian). Se retira la etiqueta "experimental" de Jolt (GH‑111115). D3D12 por defecto en Windows. SSR renovado. IDs únicos de nodo.
  - **4.7**: salida HDR (Forward+/Mobile), `DrawableTexture2D` (textura modificable por *blits* desde código, API marcada experimental), ray tracing Vulkan (experimental), suavizado automático de CSG, `Path3D` con ajuste a colisionadores, correcciones de *deadlocks* en `ResourceLoader.load_threaded_get()` (GH‑119757, GH‑120077), `NoiseTexture2D/3D` sobre `WorkerThreadPool`.
- **Importante para VENTISCA**: `winter-survival/project.godot` **no contiene** `physics/3d/physics_engine`. Como el valor interno `DEFAULT` sigue siendo GodotPhysics3D en proyectos ya existentes, **el slice corre hoy en GodotPhysics**. Primer paso de la migración: añadir la clave (§11).

### 1.2 Lo que la cámara A fija para todo lo demás

Con los parámetros del GDD (perspectiva, FOV vertical 35°, inclinación −52°, distancia 14–30 m, 16:9) el trapecio de suelo visible es:

| Zoom (distancia) | Altura cámara | Profundidad visible | Ancho cerca → lejos | Área | Borde lejano desde el jugador | Rayo más largo |
|---|---|---|---|---|---|---|
| 14 m | 11.0 m | 11.9 m | 13 → 22 m | ≈ 210 m² | 7.4 m | 19.5 m |
| **22 m (defecto)** | 17.3 m | 18.7 m | 21 → 34 m | ≈ 520 m² | 11.7 m | 30.6 m |
| 30 m (máx.) | 23.6 m | 25.6 m | 28 → 47 m | ≈ 960 m² | 15.9 m | 41.7 m |

Consecuencias (todas favorables):

1. **Nada más allá de ~45 m del jugador es visible jamás** (ni siquiera la copa de un pino de 12 m más allá del borde lejano: el borde superior de pantalla lo recorta). El *frustum* recorta el resto gratis. `Camera3D.far` puede ser **60 m** (margen para el *shake* y objetos altos cercanos).
2. **No hay horizonte**: cielo, niebla de distancia, impostores, HLOD y *occlusion culling* no aportan nada. La niebla exponencial sigue siendo útil como *tinte* de ventisca, no como ocultación.
3. **Presupuesto GPU pequeño y estable**: lo que cabe en ~1 000 m² de suelo (un cruce de pueblo denso: 3–6 edificios, 40 props, 30 árboles, 20 zombis, 4 jugadores). El cuello de botella será la **CPU de gameplay/IA/red**, no el dibujado.
4. **La distancia de streaming la dicta la velocidad de movimiento**, no la de dibujado: a 25 m/s un coche cruza un chunk de 64 m en 2.5 s; hay que tener el anillo 2 ya instanciado.
5. **Interiores** se resuelven con el corte (roof/paredes ocultas) como en el slice; no hay que renderizar interiores lejanos.
6. **Sombras**: `directional_shadow_max_distance = 60` (ya en el slice) con 2 *splits* PSSM y mapa de 4096 da sombras nítidas low‑poly a coste fijo.

### 1.3 No objetivo: cámara al hombro (opción B), para que quede escrito

Una cámara en tercera persona vería 400–1 000 m de terreno: exigiría clipmap/LOD de terreno (Terrain3D encaja ahí), cadenas de LOD e impostores de árboles, HLOD de pueblos, niebla de distancia, *occlusion culling* en interiores, presupuestos de 3–5× más triángulos y draw calls, y streaming por distancia de dibujado además de por movimiento. Todo el diseño de este documento asume que **no** ocurrirá; si cambiara, cambiarían §3, §4 y §7 casi enteros.

---

## 2. Tamaño y estructura del mundo

### 2.1 Qué hacen los referentes

| Juego | Tamaño | Construcción | Lección para nosotros |
|---|---|---|---|
| Project Zomboid (B42) | Celdas de 256 × 256 tiles (≈ 1 m) compuestas por 32 × 32 chunks de **8 × 8 tiles**; ~4 065 celdas dibujadas (x 0–77, y 0–62) ≈ 20 × 16 km ≈ 320 km². B41: celdas 300 × 300, chunks 10 × 10. | 100 % a mano (descartaron el mapa procedural al principio del desarrollo). Streaming de chunks en el hilo del juego: tirada de loot, "bakes" y datos de corte al cargar cada chunk. | Chunks pequeños + celdas grandes; loot que se decide al cargar el chunk por primera vez; el corte de techos se precalcula por chunk. |
| DayZ | Chernarus+ 225 km² (15.36 km de lado), Livonia 163 km², 60 jugadores/servidor. | A mano. | Un mundo así solo tiene sentido con 60 jugadores y tercera persona. |
| 7 Days to Die | Navezgane ≈ 32 km² jugables (6 × 6 km con borde); RWG 6k/8k/10k (36–100 km²). | Terreno + biomas procedurales, **POIs prefabricados a mano** insertados por el generador. | Exactamente el híbrido que proponemos. |
| Unturned | Clases de mapa: PEI/Washington "medium" 2 × 2 km (4 km²), Russia "large" ×4 (≈ 16 km²). | A mano, low‑poly, con vehículos. | 4–16 km² es el rango del low‑poly con coches. |
| State of Decay 2 | 3 mapas iniciales de ≈ 5 km² cada uno; co‑op de 4. | A mano; población zombi y loot por *managers* procedurales. | **5 km² bastan para 4 jugadores con vehículos**; densidad > tamaño. |
| The Long Dark | ~21 regiones separadas por "zonas de transición" con carga; ~10 min correr una región. | A mano. | Regiones con identidad y nombre (ya lo hacemos con el banner de REGIÓN). |

### 2.2 Decisión: 3 072 × 3 072 m (≈ 9.4 km²)

- Tiempos de travesía de borde a borde: andar 12.5 min, correr 8.3 min, coche a 54 km/h 3.3 min, a 90 km/h 2 min. Suficiente para que separarse "duela" y para que el coche sea deseable, sin que el mundo sea vacío.
- Cuadrícula de **48 × 48 = 2 304 chunks de 64 m**. Heightmap global de 3 073 × 3 073 muestras a 1 m (37 MB en float32 si se materializara; **no se materializa**: cada chunk se genera de semilla + sellos).
- Coordenadas centradas: x, z ∈ [−1 536, 1 536]. Reserva: el mismo sistema soporta 64 × 64 chunks (4 096 m) sin tocar precisión.
- Límite del mundo: anillo de bosque denso + acantilado/agua + niebla (como el slice, a escala).

### 2.3 Regiones y biomas (macro autorado)

Plano macro en `data/world/macro_map.png` (1 px = 8 m, 384 × 384) con capas: bioma, altura base, carreteras (splines en `macro_roads.json`), asentamientos y POIs con orientación. Propuesta inicial de contenido (a validar en `GDD`):

| Región (banner) | Tipo | Extensión aprox. | Contenido |
|---|---|---|---|
| CLARO DEL CAZADOR | POI a mano (= slice VENTISCA) | 160 × 160 m | Punto de inicio; casa, lago pequeño, cabaña del pescador |
| PINOS ALTOS / BOSQUE PROFUNDO | Bosque | ≈ 45 % del mapa | Lobos, ciervos, cabañas aisladas, torre de vigilancia |
| LAGO HELADO GRANDE | Lago | ≈ 0.4 km² | Hielo (superficie plana, riesgo de rotura v2), embarcaderos, casetas de pesca |
| CARRETERA NACIONAL | Autovía N–S con 2 enlaces | 3 km | Atascos con coches saqueables, gasolineras ×2, área de descanso |
| PUEBLO (cabecera) | Asentamiento procedural grande | ≈ 500 × 600 m | 120–160 edificios, 50–70 enterables (casas, tienda, clínica, comisaría, iglesia, escuela), calles en cuadrícula con jitter |
| ALDEAS ×3 | Asentamientos procedurales pequeños | 120–200 m | 12–25 edificios cada una, un camino principal, granero/serrería/taller |
| GRANJAS ×3 | POI semiprocedural | 80 × 80 m | Silos, establo, casa |
| CHECKPOINT MILITAR | POI a mano | 100 × 60 m | Loot militar, alta densidad zombi, barreras de hormigón |
| ANTENA / SERRERÍA / PRESA | POIs a mano | 40–120 m | Hitos de navegación visibles desde la carretera |

Regla de densidad (derivada de SoD2 y PZ): **≈ 1 POI "con nombre" por cada 0.25 km²** (36–40 en el mapa) y **≈ 1 edificio enterable por cada 2 000 m² de asentamiento**.

### 2.4 Hecho a mano vs procedural vs híbrido — decisión razonada

- *Todo a mano* (PZ, DayZ): máxima calidad y legibilidad, pero 9 km² a mano con un equipo pequeño es inviable y no cabe en el pipeline bpy.
- *Todo procedural*: rápido, pero mundos sin memoria; malo para co‑op (nadie sabe dónde queda nada) y para diseño de dificultad.
- **Híbrido (elegido)**: el plano macro y ~15 POIs son de autor; terreno, bosque, carreteras secundarias, aldeas y el interior del pueblo se generan con **semilla fija por servidor**. Todo generador es una función pura `f(seed, chunk_xz) -> contenido` para que **cliente y servidor generen lo mismo sin transferir el mundo**; solo viajan los deltas (§8).

---

## 3. Terreno en Godot 4.7

### 3.1 Terrain3D — estado verificado (sept‑2026)

- Repo `TokisanGames/Terrain3D`, **MIT**, GDExtension en C++. Última versión estable **v1.0.2 (19‑may‑2026)**: "Supports Godot 4.4‑4.6+"; `main` está en **1.1.0‑dev**. La ficha del Asset Library lista 4.4–4.7 y el issue #1043 confirma que 1.0.2 **funciona en la build oficial 4.7.2 de precisión simple** y **falla con `precision=double`** (`body_add_shape` sin *fallback* de compatibilidad: la colisión no se adjunta).
- Capacidades: hasta 65.5 × 65.5 km en regiones no contiguas, 32 texturas, 10 niveles de LOD (clipmap), instanciador de follaje con LOD y sombra impostora, agujeros, pintado de color/humedad, importación de heightmaps. Renderers: Forward+ (Vulkan; D3D12 "fully supported as of Godot 4.6"), Mobile y **Compatibility "fully supported since Terrain3D 1.0 and Godot 4.4"**.
- Colisión: modos *Dynamic/Game* (por defecto: genera `HeightMapShape3D` **alrededor de la cámara**, sin nodos), *Dynamic/Editor*, *Full/Game* (todo el terreno al arrancar, mucha memoria), *Full/Editor*, *Disabled*. Solo hay colisión donde hay regiones definidas. Recomiendan Jolt si hay problemas de raycast.
- Navegación: pintado de áreas navegables, horneado desde el menú de Terrain3D (el botón estándar de `NavigationRegion3D` no funciona con él), demo de rehorneado periódico alrededor del jugador en tiempo de ejecución.
- Runtime: API para editar altura y regiones desde GDScript (`Terrain3DData`), documentada en el repo.
- **Riesgos para nosotros**: (a) servidor dedicado headless sin cámara ⇒ el modo *Dynamic* no tiene ancla natural; habría que usar *Full/Game* o generar nuestras propias `HeightMapShape3D` desde `Terrain3DData`; (b) dependencia binaria por versión del motor (cada 4.x nuevo exige esperar release); (c) su shader es de texturas PBR con *detiling*; para flat‑color habría que sustituir el shader entero; (d) 4.7 aún no aparece en el texto oficial de release.

### 3.2 Alternativas evaluadas

- **HTerrain (Zylann)**: GDScript, master para Godot 4.6+, "no en desarrollo activo" (solo corrección de errores). Descartado.
- **Malla propia por chunk + `HeightMapShape3D`** (lo que ya hace `terrain.gd` a 160 m): `HeightMapShape3D` es "más rápida que `ConcavePolygonShape3D` pero notablemente más lenta que primitivas"; con Jolt soporta escalado y tiene eliminación mejorada de aristas internas (menos "ghost collisions" al rodar un coche).
- **Clipmap propio**: innecesario, no hay distancia de dibujado.

### 3.3 Decisión: terreno propio por chunk

Especificación:

- `TerrainChunk` (64 × 64 m, 65 × 65 muestras, 1 m). Altura `h(x,z) = base_noise(seed) + macro_map_height + Σ stamps_POI` (sellos = imágenes de altura pintadas o exportadas de Blender, con *flatten pads* como los del slice). Función pura, compartida por cliente y servidor (`scripts/world/terrain/height_function.gd`).
- Malla **indexada** (4 225 vértices, 8 192 triángulos) con **flat shading en el shader** (`NORMAL = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)))` en fragment) en vez de triángulos no indexados: 6× menos vértices que hoy y colores de vértice compartidos. Funciona en Forward+ y Compatibility (derivadas disponibles en GLES3).
- Colores de vértice: nieve/nieve‑sombra por pendiente y ruido (igual que el slice) + **máscara de bioma/carretera/hielo** en el canal alfa o en un segundo `CUSTOM0` para que el shader mezcle asfalto, tierra, hielo.
- Colisión: 1 `StaticBody3D` + `HeightMapShape3D` por chunk (capa `world`). En el servidor se crea igual (headless ejecuta física).
- Bordes: chunks vecinos comparten la fila/columna de muestras ⇒ sin costuras; sin LOD de terreno (nunca se ve un chunk a > 45 m).
- Coste: generar un chunk ≈ 4 225 evaluaciones de ruido + `SurfaceTool` → < 3 ms en hilo secundario (GDScript) — se hace en `WorkerThreadPool` y solo `add_child` en el hilo principal.

### 3.4 Nieve

**Acumulación (estática y dinámica)**

- Los modelos de Blender ya traen "gorros" de nieve como geometría (ASSET_SPEC). Para la nieve que **crece durante ventiscas** y sobre objetos nuevos (coches, cadáveres, estructuras del jugador) se usa un *shader include* común a todos los materiales del mundo:
  `albedo = mix(base, snow_color, smoothstep(0.55, 0.85, world_normal.y) * snow_amount)`, con `snow_amount` como **parámetro global de shader** (`RenderingServer.global_shader_parameter_set("snow_amount", v)`) que el clima sube en ventisca y baja lentamente. Coste: una mezcla por píxel; idéntico en ambos renderers. Sin triplanar (no hay texturas): flat‑color lo hace trivial.
- No usar `Decal` para nieve: no existe en Compatibility.

**Huellas, rodadas y senderos (deformación)**

- Técnica estándar en Godot (godotshaders "Car tracks on snow or sand", goeshard 2025): `SubViewport` con cámara ortográfica cenital que solo ve una capa de render donde se dibujan "sellos" (quads/partículas) bajo pies y ruedas; la `ViewportTexture` resultante entra al shader del terreno y de la nieve de los props como **desplazamiento de vértice negativo + oscurecimiento**.
- Parámetros recomendados: viewport **1024 × 1024 cubriendo 64 × 64 m** (6.25 cm/texel) centrado en el jugador local, sin borrar entre frames (`render_target_clear_mode = NEVER`), con **re‑proyección por desplazamiento** cuando el jugador cruza 8 m (se copia la textura desplazada; lo que sale del área se olvida). Decaimiento lento (0.5 %/s) para que la nevada borre huellas.
- Godot 4.7 permite lo mismo sin cámara ni viewport con **`DrawableTexture2D.blit_rect`** (proyecto MIT `Flynsarmy/gd-snow-project`, portado a 4.7). API marcada *experimental* y con un bug abierto en D3D12/Forward+ (`setup()` deja la textura vacía, issue #123507) ⇒ **implementar primero con `SubViewport`** (estable en los tres renderers) y encapsular detrás de `SnowTrailMap` para migrar a `DrawableTexture2D` cuando se estabilice.
- Multijugador: las huellas son **cosméticas y locales**: cada cliente sella para todos los personajes/vehículos que ve; el servidor no las conoce. Las huellas de VENTISCA (mallas cilíndricas) se sustituyen por este sistema (cubre también coches y zombis).
- Coste: 1 viewport pequeño + decenas de quads por frame ≈ 0.1–0.3 ms en cualquier renderer.

**Precipitación**

- `GPUParticles3D` (soportado en Compatibility; solo `emit_particle()`, *trails* y colisión SDF no lo están). Caja de 40 × 20 × 40 m siguiendo a la cámara (como hoy), 2 000 copos normales / 6 000 en ventisca; con la cámara isométrica es imposible "mirar al horizonte", así que no hace falta más. Mantener `CPUParticles3D` solo como respaldo si la GPU integrada da problemas.

---

## 4. Streaming del mundo

### 4.1 Sistema de chunks

- **Chunk = 64 m** (PZ usa 8 m sobre celdas de 256; nosotros no tenemos tiles). 64 m equilibra: número de nodos por chunk (terreno + 1 MultiMesh por tipo de vegetación + 5–40 props/edificios), coste de horneado de navmesh, y granularidad de persistencia.
- Cada chunk tiene **capas independientes** con su propio radio (idea tomada de OWDB): terreno+colisión (radio 2), vegetación/props estáticos (radio 2), edificios/interiores/contenedores (radio 1 + prefetch 2), entidades dinámicas (zombis, vehículos: solo radio 1, gestionadas por el servidor), navmesh (radio 1).
- Cliente: anillo 1 (3 × 3 = 9 chunks) visible y **completo**; anillo 2 (5 × 5 = 25) con terreno + estáticos instanciados y edificios cargados en memoria pero no añadidos al árbol.
- Servidor: para cada jugador, anillo 1 "caliente" (física, IA, navmesh, contenedores abiertos) y anillo 2 "tibio" (estado en memoria, sin física); con 4 jugadores dispersos ⇒ ≤ 36 chunks calientes, 100 tibios. Un chunk sin jugador a < 3 chunks durante 60 s se **hiberna** (se serializa su delta y se libera).
- Determinismo: cada chunk se genera con `rng = RandomNumberGenerator(); rng.seed = hash(world_seed, cx, cz)`. Nunca se usa el RNG global para contenido del mundo.

### 4.2 Carga en hilos y presupuesto por frame

- Escenas de edificios/POIs: `ResourceLoader.load_threaded_request(path, "", use_sub_threads=true)`, sondeo con `load_threaded_get_status()` (0.0–1.0 de progreso), y `load_threaded_get()` **solo cuando el estado es LOADED** (si no, bloquea). 4.7 corrigió *deadlocks* en esta ruta (GH‑119757/120077) — usar 4.7.2, no 4.7.0.
- La instanciación (`instantiate()` + `add_child`) es de hilo principal: el `SceneTree` no es *thread‑safe*. Cola de instanciación con **presupuesto de 2 ms/frame** medido con `Time.get_ticks_usec()`; edificios grandes se dividen en sub‑escenas (fachada, interior, mobiliario, contenedores) para repartirlos en varios frames.
- Generación de mallas de terreno y de MultiMesh en `WorkerThreadPool.add_task()`; el resultado (`ArrayMesh`, `PackedFloat32Array`) se recoge en el hilo principal.
- Orden de prioridad en la cola: chunk delante del movimiento > laterales > detrás. Con coches, el `WorldStreamer` usa `player.velocity` para desplazar el centro del anillo 1 chunk hacia adelante.
- Objetivo medible: **0 frames > 16 ms por streaming** conduciendo a 25 m/s por el pueblo. Prueba automatizable en `tests/` (recorrido fijo, recogida de `Performance.TIME_PROCESS`).

### 4.3 Coordenadas grandes y precisión

- Los binarios oficiales son de precisión simple; la doble precisión requiere compilar motor y plantillas con `precision=double` y recompilar toda GDExtension con `REAL_T_IS_DOUBLE`; cliente y servidor deben coincidir; penaliza CPU/memoria. La documentación sitúa el umbral cómodo de precisión simple para juegos top‑down en 32k–65k unidades; el demo oficial ve artefactos "a unos pocos miles de unidades" en malla vista de cerca.
- Nuestro peor caso: 1 536 m del origen (2 048 si crecemos). Paso de precisión a 2 048 m ≈ 0.0002 m (docs): invisible con cámara a 22 m. **Decisión: sin origin shifting ni doble precisión.** Si algún día el mundo superase ~8 km de lado, la opción sería origin shifting solo en el cliente (el servidor sigue en coordenadas absolutas), nunca `precision=double`.

### 4.4 Culling, LOD, HLOD, instancing

- **Frustum culling** del motor hace el 95 % del trabajo (§1.2). **Occlusion culling: desactivado** (los docs lo señalan como poco eficaz en vistas cenitales y campos abiertos, y cuesta CPU en el rasterizador Embree).
- **Mesh LOD automático** (importación glTF, meshoptimizer) activado con `lod_bias` 1.0: ayuda en props pequeños a 30–45 m. **Visibility ranges**: ocultar escombros/detalles < 0.3 m a partir de 35 m con `fade_mode = SELF`. **HLOD (visibility parent)**: no necesario.
- **MultiMesh por chunk y por tipo** (pinos a/b/c, árboles secos, rocas, arbustos, hierba seca, escombros): un `MultiMeshInstance3D` se recorta como una sola unidad, por eso se hace **por chunk** (64 m) y no global. Instancias con `custom_data` para tinte/nieve. Árboles talables: la instancia visual vive en el MultiMesh y la **interacción se resuelve por índice espacial** (`scripts/world/scatter/scatter_index.gd`: hash de celdas de 8 m → id de instancia); al golpear, se oculta la instancia (transform a escala 0) y se instancia un `tree.tscn` real solo para ese árbol (animación de caída, tocón). Elimina los 330 nodos de árbol del slice.
- Draw calls típicos por frame en un cruce de pueblo (estimación con esta arquitectura): terreno 9–25, MultiMesh 20–40, edificios 20–60 superficies, props 50–150, personajes 30–80, UI/partículas 10 ⇒ **200–400 draw calls**, muy por debajo del punto donde la submisión pesa (~5 000 draw calls ≈ 8–10 ms de CPU según mediciones de la comunidad; los docs de Godot solo piden "minimizar draw calls y cambios de material").

### 4.5 Partículas y clima

- `GPUParticles3D` en Forward+ y Compatibility; `CPUParticles3D` reservado a efectos pequeños con lógica CPU (astillas) o al preset de respaldo.
- Ventisca: niebla exponencial + `FogVolume`/niebla volumétrica **solo en Forward+** (no existe en Compatibility; el preset de respaldo usa solo la exponencial, como hoy).
- Viento y ventisca son estado de servidor replicado (`weather_state`), las partículas se emiten localmente.

---

## 5. Pueblos, aldeas, interiores y navegación

### 5.1 Pipeline de asentamiento (determinista por semilla)

1. **Semilla y huella**: del plano macro salen centro, radio, tipo (pueblo/aldea/granja), orientación de la calle principal y carretera de acceso.
2. **Red viaria**: no usar L‑systems (Parish & Müller 2001: potentes pero de parametrización pesada) ni campos tensoriales (Chen et al. 2008: bonitos pero excesivos para aldeas). Para pueblos americanos pequeños basta **cuadrícula con jitter**: eje principal = carretera macro; calles secundarias cada 60–90 m con desplazamiento ±10 m y rotación ±8°; se recortan contra pendientes > 12° y agua; las aldeas usan una sola calle con 1–2 ramales (grafo de 3–6 aristas). Salida: grafo de segmentos con ancho (asfalto 7 m / camino 4 m). Malla de carretera: **cinta propia** a lo largo de la spline, aplanando el heightmap (sello de carretera en la función de altura) y con banquetas de nieve. `godot-road-generator` (MIT, 0.9.1 para 4.4+, con API de runtime, intersecciones procedurales y `RoadLaneAgent`) es útil para la **autovía** (carriles, enlaces) pero su estética PBR no encaja en las calles low‑poly; se evalúa solo para la nacional.
3. **Manzanas y parcelas**: polígonos entre calles → **subdivisión recursiva OBB** (Vanegas et al. 2012): cortar por la mediana de la caja orientada hasta parcelas de 400–900 m² (casas) o 1 200–2 500 m² (comercios/servicios); descartar parcelas sin frente a calle. El *straight skeleton* del mismo paper no compensa su complejidad aquí.
4. **Asignación de uso**: tabla por tipo de asentamiento (pueblo: 65 % casas, 15 % comercio, 8 % servicios públicos, 12 % vacías/parques; aldea: 80/10/5/5) + POIs de autor "reservados" (iglesia, comisaría) colocados primero en las parcelas mejores.
5. **Kit modular de edificios** (Blender/bpy): rejilla de **1 m**, módulos de pared exterior‑interior en una pieza (como el "Medieval Village MegaKit" pero con nuestro estilo), esquinas, puertas, ventanas, tejados a 2 aguas por tramos de 1 m, porches, garajes. Cada edificio = **plantilla de planta** (`data/buildings/*.json`: rejilla de habitaciones 1 m, puertas, ventanas, ancla de mobiliario, ancla de loot, `roof_type`) ensamblada en runtime con un `MeshLibrary`/`GridMap` **o** con instancias por módulo agrupadas en un `MultiMesh` por edificio (menos draw calls que GridMap por edificio: 1 draw call por tipo de módulo). Interiores con 2–8 habitaciones por plantilla y **variaciones**: 40 plantillas × mobiliario aleatorio dan miles de casas distintas.
6. **Enterables**: en el pueblo el 45 % de las casas y el 100 % de comercios/servicios son enterables; el resto tiene puerta cerrada tapiada (coste cero de interior). Objetivo: 50–70 interiores en el pueblo, 6–10 por aldea.
7. **Corte (cutaway) para cámara A**: generalizar `cutaway.gd`: cada edificio expone `Roof`, `Walls[N]` con normal exterior; un `CutawayManager` procesa solo edificios a < 30 m de cada jugador local y oculta techo + paredes cuya normal mira a cámara cuando un jugador está dentro (o el cursor apunta dentro). **Plantas superiores**: ocultar plantas por encima de la del jugador. Mejora opcional con **stencil (4.5+)**: en vez de ocultar paredes, un cilindro invisible alrededor del jugador escribe en el stencil y el shader de pared descarta píxeles cubiertos — funciona en los tres renderers y evita "popping" en paredes compartidas.
8. **Loot**: cada contenedor tiene `loot_table_id` + `container_guid` (hash determinista de chunk + índice). La tirada se hace **en el servidor la primera vez que un jugador abre el contenedor** (no al cargar el chunk, como hace PZ, para no guardar loot que nadie vio), con `rng.seed = hash(world_seed, container_guid, world_day)` y se persiste como delta (§8). Rareza por región (militar > comisaría > casa).
9. **Zombis en asentamientos**: `population_manager` por chunk (idea de SoD2): densidad base por uso de suelo (pueblo 0.6/100 m², aldea 0.3, bosque 0.03, checkpoint 1.5), "durmientes" hasta que un jugador entra en el anillo 1; se convierten en cuerpos activos solo a < 80 m de un jugador.

### 5.2 Navmesh en tiempo de ejecución (por chunk)

- **Horneado asíncrono** con la API del servidor: `NavigationServer3D.parse_source_geometry_data()` (obligatoriamente en hilo principal) → `bake_from_source_geometry_data_async()` (hilo secundario, callback al terminar). No usar `NavigationRegion3D.bake_navigation_mesh()` en cliente (no hace falta navmesh en cliente; ver abajo).
- **Fuente = formas de colisión** (`geometry_parsed_geometry_type = STATIC_COLLIDERS`), nunca las mallas visuales: parsear mallas exige bloquear datos de GPU y "afecta negativamente al framerate" (docs). Como el terreno tiene `HeightMapShape3D` y los edificios `Col*` convexos, el parseo es barato.
- **Alineación entre chunks**: mismo `cell_size` (0.25) y `cell_height` (0.2) en todos; `filter_baking_aabb` = AABB del chunk ampliada con `border_size` = `agent_radius` (0.4) para que los bordes casen sin huecos; el servidor de navegación conecta aristas por proximidad de vértices (`edge_connection_margin`).
- Coste estimado: chunk de 64 m con un pueblo denso ≈ 20–60 ms de horneado en hilo secundario, invisible para el frame. Rehorneado solo cuando cambia geometría relevante (puerta rota, barricada) y con *cooldown* de 2 s.
- `map_set_use_async_iterations(map, true)` para que la sincronización de regiones no bloquee el frame de física cuando entran/salen chunks.
- **Solo el servidor hornea y consulta rutas** (los zombis son autoritativos en el servidor). El cliente no tiene navmesh, salvo para el *auto‑walk* del clic (se sustituye por línea recta + evitación local con `ShapeCast3D`, o por una consulta al servidor si el destino está lejos).

### 5.3 Navegación para cientos de zombis — cifras y plan

Datos de rendimiento que condicionan el diseño:

- `CharacterBody3D`: con GodotPhysics la comunidad reporta degradación con **10–40** instancias (issue #78761) y "sub‑15 FPS" con 50–60 en niveles complejos (issue #93184, ambos motores en la versión probada); con **Jolt ≈ 800** instancias antes de notar degradación en la prueba de #78761. El coste real está en `move_and_slide` contra geometría del suelo.
- Evitación RVO: es una simulación aparte (agentes = círculos en el plano XZ) que **ignora el navmesh y la física**; su coste crece con `neighbor_distance`, `max_neighbors` y el número de agentes activos (un bug corregido en 4.7.x, PR #120249, mostraba 2 000 agentes disparando la CPU del 5 % al 40 % al ser añadidos indebidamente a la simulación de evitación: esa es la escala de coste de RVO con miles de agentes).
- Los docs piden: no consultar rutas cada frame, **escalonar** consultas entre agentes, no comprobar alcanzabilidad por separado, y evitar destinos inalcanzables (búsqueda exhaustiva).

Plan (**"LOD de IA"** en tres niveles, todo en el servidor):

| Nivel | Distancia a jugador más cercano | Representación | Coste |
|---|---|---|---|
| **Activo** | < 40 m | `CharacterBody3D` (cápsula, capa `zombies` que no colisiona entre sí salvo con jugadores/vehículos), animación replicada por estado | ≤ 150 en total en el servidor; ≤ 60 por cliente |
| **Cercano** | 40–120 m | Sin cuerpo: posición + `NavigationServer3D.map_get_path` cada 1–2 s, avance por interpolación sobre la ruta, altura por `height_function` | 500 |
| **Durmiente** | > 120 m o chunk tibio | Registro `{guid, chunk, pos, type, hp}` en memoria; no piensa | 2 000+ |

- Consultas de ruta: cola global con **≤ 40 consultas por tick** de servidor; agentes activos repiten ruta cada 0.5–1 s solo si el objetivo se movió > 2 m; ruta compartida por "grupo" (zombis a < 6 m con el mismo objetivo usan la ruta del líder).
- RVO solo para agentes **activos a < 20 m de un jugador** (`agent_set_avoidance_enabled`), `neighbor_distance` 4 m, `max_neighbors` 6, `time_horizon_agents` 0.5 s. El resto usa separación simple por *spatial hash*.
- Cuerpo físico compartido con animación procedural (como `quadruped_animator.gd`), no `AnimationTree` por zombi: ahorra CPU en cliente con 60 zombis en pantalla.
- **Flow fields (v2, eventos de horda)**: cuando > 100 zombis persiguen al mismo jugador en un asentamiento, calcular un campo de flujo por chunk (rejilla de 1 m: campo de coste ← navmesh/colisión, campo de integración Dijkstra desde el objetivo, campo vectorial) y que todos lo sigan sin rutas individuales; es la técnica de Supreme Commander 2 (Continuum Crowds / flow field tiles). Coste: 4 096 celdas por chunk, recalculado cada 0.5 s cuando el objetivo cambia de celda. No se implementa en v1.

### 5.4 Vehículos abandonados y ciudad muerta

- Coches en atascos/aparcamientos son **props estáticos** con contenedor (como la camioneta del slice); solo un subconjunto (1 de cada 8, marcado por semilla) es un **vehículo funcional** (§6). Los estáticos van a MultiMesh por modelo con variación de color por `custom_data`.

---

## 6. Vehículos

### 6.1 `VehicleBody3D` vs suspensión por raycast propia (con Jolt)

- `VehicleBody3D`/`VehicleWheel3D` implementan la suspensión con **raycasts a nivel de escena** (`PhysicsDirectSpaceState3D.intersect_ray` en `vehicle_body_3d.cpp`), así que **funciona con Jolt**; pero la documentación del propio nodo dice que "tiene problemas conocidos y no está diseñado para una física de vehículos realista" y sugiere `RigidBody3D` con física propia para simulación avanzada. No expone modelo de neumático ni fricción por superficie más allá de `friction_slip` por rueda.
- **Decisión**: `RigidBody3D` + 4 raycasts (o `ShapeCast3D` esférico por rueda para no engancharse en bordillos) + modelo de neumático simple (fuerza lateral proporcional al ángulo de deriva, saturada; fuerza longitudinal por deslizamiento). Base de partida: **Godot Easy Vehicle Physics** (MIT, Godot 4.2+, "funciona bien en Godot y Jolt", calcula rigidez/amortiguación a partir de masa y reparto de peso, incluye caja automática, diferenciales y asistencias). Su recomendación de **≥ 120 Hz de física** entra en conflicto con los zombis; plan: mantener **60 Hz** con Jolt y amortiguación calculada; solo si aparece *jitter* de suspensión se sube a 90 Hz (coste ≈ +50 % de física de zombis) — decidirlo con la prueba de la autovía.
- **Tracción por superficie**: cada raycast devuelve el colisionador; el terreno expone `get_surface(x,z)` (asfalto μ 0.9 / nieve compacta 0.55 / nieve profunda 0.35 con resistencia al avance / hielo 0.12) desde la máscara de bioma del heightmap; los edificios y puentes llevan `surface` en metadatos. Hielo del lago: μ muy bajo + sin resistencia ⇒ derrapes legibles desde la cámara alta.
- **Daño y combustible**: `hp` por vehículo (colisiones con `body_entered` e impulso de contacto — Jolt lo estima, solo exacto con un contacto a la vez, suficiente), ruedas pinchables (rueda con μ ×0.3 y radio −10 %), motor (`engine_hp` reduce potencia), depósito con consumo por rpm; loot de bidones en gasolineras. Todo es estado replicado ON_CHANGE.
- **Entrar/salir**: asientos como `Marker3D` (conductor + 3 pasajeros: coche de 4 = co‑op de 4), jugador se reparenta al asiento y se desactiva su `CharacterBody3D`; salida a un punto libre comprobado con `ShapeCast3D`.
- **Zombis vs coche**: atropello = daño por velocidad relativa del `RigidBody3D` contra la cápsula (Jolt: activar `contact_monitor`, `max_contacts_reported` 8).

### 6.2 Red: quién simula el coche

- **Autoridad del conductor** (`set_multiplayer_authority(driver_peer)` al entrar): el cliente que conduce simula localmente (respuesta inmediata, imprescindible para conducir bien con 60–120 ms de ping); el servidor recibe transform/velocidad (ALWAYS, unreliable, 20 Hz), **valida** (velocidad ≤ v_max·1.2, no atraviesa colisión estática, no teletransporte > 10 m/tick) y re‑emite a los demás, que interpolan. El servidor sigue siendo autoridad de daño, combustible, atropellos y de quién ocupa cada asiento.
- Al bajarse el conductor, la autoridad vuelve al servidor (el coche queda como `RigidBody3D` dormido).
- Pasajeros: reparentados a asientos, sin simulación propia.
- Con PvP activado esto es un vector de trampas (cliente conductor); se acepta explícitamente por ser servidores privados entre amigos y se anota en el `GDD`. Netfox (MIT, Godot 4.x) ofrece predicción/rollback si algún día se quiere autoridad de servidor con predicción; no para v1.

---

## 7. Presupuestos de rendimiento y renderer

Objetivo: **PC medio 2022–2026** (p. ej. GTX 1660 / RX 6600 / RTX 3060, 4–6 núcleos, 16 GB) a **1080p 60 FPS**; mínimo aceptable: iGPU moderna (Iris Xe / Radeon 780M) a 1080p 40 FPS con preset Compatibility.

### 7.1 Elección del renderer

| Criterio | Forward+ | Compatibility | Decisión |
|---|---|---|---|
| Luces por malla | Clustered (miles) | **8 omni + 8 spot por malla** (`max_lights_per_object`) | Pueblos de noche con farolas, fogatas y ventanas: Forward+ |
| Niebla volumétrica (ventisca) | Sí | No | Forward+ (Compat usa niebla exponencial) |
| Decals | Sí | **No** | No dependemos de decals (huellas por viewport) |
| GPUParticles | Sí (trails, SDF) | Sí (sin trails/SDF/`emit_particle`) | Ambos OK |
| SSAO | Sí | Sí | Útil para "pegar" props low‑poly al suelo |
| MSAA 3D | Sí | Sí | 2× en ambos (bordes low‑poly lo agradecen) |
| HDR output | Sí (4.7) | No | Opcional |
| Stencil (corte) | Sí | Sí | OK |
| Sombras direccionales PCSS | Sí | No | Forward+; Compat usa filtro PCF |
| Hardware | Vulkan/D3D12/Metal | OpenGL 3.3 / GLES 3 | Compat cubre iGPUs viejas y Linux sin Vulkan |

**Decisión**: Forward+ por defecto (Windows con D3D12 desde 4.6, Linux Vulkan), preset Compatibility seleccionable en opciones (detección automática si `RenderingServer.get_video_adapter_type()` es integrada y antigua). El shader de terreno/nieve/corte se escribe **una vez** con `#if` mínimos; los efectos exclusivos (niebla volumétrica, PCSS) se activan por preset. Mobile no se soporta.

### 7.2 Presupuestos por frame (cliente, Forward+, 1080p)

| Recurso | Presupuesto | Nota |
|---|---|---|
| Frame total | 16.6 ms; objetivo interno **12 ms** (margen para picos de streaming) | |
| Draw calls | **≤ 800** (típico 200–400) | Medir con `Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME` |
| Triángulos | **≤ 1.5 M** (típico 300–600 k) | Low‑poly: casa 1–3 k, coche 1.5 k, pino 150–300, zombi 800–1 500 |
| Objetos visibles | ≤ 2 500 (`RENDER_TOTAL_OBJECTS_IN_FRAME`) | MultiMesh cuenta como 1 |
| Luces con sombra | 1 direccional (2 splits, 4096) + **≤ 6 omni/spot con sombra** (fogatas, faros); resto sin sombra | Compat: ≤ 3 con sombra |
| Personajes animados | ≤ 64 (4 jugadores + 60 zombis) | Animación procedural o `Skeleton3D` con ≤ 20 huesos |
| Partículas | ≤ 12 000 GPU (ventisca) / ≤ 2 000 CPU | |
| GDScript `_process`/`_physics_process` | **≤ 3 ms** | Zombis remotos solo interpolan; sin lógica de IA en cliente |
| Streaming | ≤ 2 ms/frame de instanciación | §4.2 |
| Memoria | ≤ 2.5 GB RAM, ≤ 1.5 GB VRAM | 25 chunks residentes ≈ 60–120 MB |

### 7.3 Presupuestos del servidor dedicado (headless, 4 jugadores)

| Recurso | Presupuesto |
|---|---|
| Tick | 60 Hz física, **30 Hz replicación** de entidades activas, 10 Hz para vehículos aparcados/estado ambiental |
| Cuerpos físicos activos | ≤ 150 zombis + 4 jugadores + ≤ 8 vehículos + estáticos de ≤ 36 chunks calientes |
| IA | 150 activos + 500 cercanos + 2 000 durmientes (§5.3); ≤ 40 consultas de ruta por tick |
| Navmesh | ≤ 36 regiones activas; horneado en hilo |
| CPU objetivo | 1 núcleo moderno al ≤ 60 % (permite alojar en un VPS de 2 vCPU/4 GB) |
| Ancho de banda | ≤ 40 kbit/s por jugador de bajada (interest management por chunk: solo entidades del anillo 1 del jugador) |
| Persistencia | Escritura SQLite en transacciones cada 30 s + al hibernar chunk; ≤ 5 ms por lote |

### 7.4 Qué medir desde el día 1

`tests/perf_drive.gd` (recorrido fijo en coche por pueblo → autovía → bosque; registra ms de frame, draw calls, objetos, `Performance.PHYSICS_3D_ACTIVE_OBJECTS`, `NAVIGATION_*`) y `tests/perf_horde.gd` (200 zombis en un pueblo, servidor headless, mide ms de tick). Los presupuestos anteriores son criterios de aceptación de esos tests.

---

## 8. Persistencia de un mundo que cambia (modelo para servidor dedicado)

### 8.1 Principios

1. **Baseline procedural + deltas**: nada del mundo generado se guarda; solo lo que difiere. Igual que 7DTD/Minecraft (regiones tocadas) y PZ (chunks modificados).
2. **Identidad estable**: todo objeto del mundo tiene `guid` determinista = `hash(world_seed, chunk, generator, index)`; los objetos creados por jugadores reciben `guid` aleatorio de 64 bits y `origin = player`.
3. **El servidor es el único que escribe.** Los clientes no tienen guardado (salvo opciones locales).
4. **Escritura diferida y transaccional**: cambios en memoria por chunk (`ChunkDelta`), volcados en una transacción cada 30 s, al hibernar el chunk y al apagar; SQLite garantiza atomicidad y es un solo fichero copiable para backups.

### 8.2 Esquema (SQLite vía `godot-sqlite`, MIT, compatible con binarios headless)

```
world_meta(key TEXT PK, value TEXT)                     -- seed, version, day, hour, weather, rules (pvp, friendly_fire)
players(id TEXT PK, name, pos_x, pos_y, pos_z, stats_json, inventory_json, last_seen)
chunks(cx INT, cz INT, first_visit, last_visit, loot_rolled INT, PRIMARY KEY(cx,cz))
containers(guid TEXT PK, cx, cz, items_json, rolled_day, opened_by)
world_objects(guid TEXT PK, cx, cz, kind TEXT, state INT, hp REAL, data_json)   -- puertas rotas, ventanas tapiadas, árboles talados (state=removed)
structures(guid TEXT PK, cx, cz, kind, pos_x,pos_y,pos_z, yaw, owner, hp, data_json)  -- base building, fogatas, cajas, barricadas
vehicles(guid TEXT PK, cx, cz, model, transform_json, fuel, hp, wheels_json, inventory_json)
actors(guid TEXT PK, cx, cz, kind, pos_x,pos_y,pos_z, hp, ai_state)   -- zombis/animales solo cuando el chunk hiberna
events(id INT PK, ts, type, data_json)                 -- log ligero para depuración y "historia del servidor"
CREATE INDEX ON containers(cx,cz); ... (idx por chunk en todas las tablas)
```

- `items_json` usa el formato de `Inventory` (id, count, durabilidad); versión de esquema en `world_meta.version` con migraciones en `scripts/persistence/migrations/`.
- Carga de chunk en el servidor: `SELECT` por `(cx,cz)` en las 5 tablas (índices) → aplicar deltas sobre el baseline recién generado (`world_objects.state = removed` oculta el árbol del MultiMesh, etc.).
- Loot: `containers` solo tiene filas de contenedores ya tirados; los no visitados se regeneran deterministamente (§5.1.8). Reabastecimiento (opcional, regla de servidor): el día `rolled_day + N` se borra la fila y se vuelve a tirar.
- Alternativa descartada: ficheros binarios por chunk con `store_var` (guía "Saving games" de Godot): más simple pero sin transacciones ni consultas; solo se usaría para el **cliente** si algún día hubiera partida local sin servidor (el mismo `PersistenceBackend` tendría dos implementaciones: `SqliteBackend` y `FileBackend`).

### 8.3 Interacción con la red

- Cuando un cliente entra en un chunk, el servidor le envía un **snapshot del delta** del chunk (contenedores abiertos con inventario, objetos con `state`, estructuras) en un RPC fiable único (`chunk_delta_snapshot`), y después solo cambios (`MultiplayerSynchronizer` ON_CHANGE para objetos con nodo; RPC para objetos sin nodo, p. ej. instancias de MultiMesh).
- Los contenedores abiertos por dos jugadores a la vez se resuelven en el servidor (una sola `Storage` autoritativa; el panel del cliente pide `take(slot)` por RPC y recibe el resultado).

---

## 9. Multijugador: lo que afecta al mundo

- **Transporte**: `ENetMultiplayerPeer` (UDP fiable/no fiable, IPv6). Exportación "dedicated server" (`OS.has_feature("dedicated_server")`, recursos visuales eliminados del PCK) ejecutada con `--headless`. Física, navegación y `WorkerThreadPool` funcionan en headless; el `SubViewport` de huellas y las partículas no se crean en servidor (`if not Net.is_server`).
- **Autoridad**: servidor = mundo, tiempo, clima, loot, zombis, daño, estructuras. Cliente = movimiento de su propio personaje (validado: velocidad, suelo, no atravesar) y su coche mientras conduce (§6.2). Ataques cuerpo a cuerpo: el cliente envía `attack(target_guid)`; el servidor valida distancia (≤ 2.5 m + margen de latencia) y aplica daño.
- **Replicación**: `MultiplayerSpawner` para jugadores, zombis activos, vehículos y estructuras; `MultiplayerSynchronizer` con `REPLICATION_MODE_ALWAYS` (no fiable) para transform/velocidad/estado de animación a 20–30 Hz y `ON_CHANGE` (fiable) para hp, estado de puerta, combustible. Limitación documentada: no se sincronizan propiedades `Object`/`Resource` ni RIDs ⇒ todo estado replicado es escalar, `Vector3`, `Array`/`Dictionary` planos.
- **Interest management**: `add_visibility_filter(func(peer): return chunk_dist(entity, peer_player) <= 1)` en cada sincronizador de entidad dinámica, `visibility_update_mode = PHYSICS`; con ello el *spawn/despawn* sigue la visibilidad (los zombis "aparecen" en el cliente al entrar en su anillo 1). Presupuesto: ≤ 40 kbit/s por jugador.
- **Reglas de servidor** (`server.cfg`, replicadas en `world_meta`): `pvp`, `friendly_fire`, `loot_respawn_days`, `zombie_density`, `day_length_sec`, `max_players = 4`. `friendly_fire` y `pvp` se consultan en un único punto: `DamageResolver.apply(attacker, victim, dmg)`; la UI muestra el estado en el HUD (icono) y en el navegador de servidores.
- **Reconexión**: al desconectar, el personaje queda 60 s en el mundo (servidor lo guarda en `players`); al volver, se restaura del SQLite.

---

## 10. Stack recomendado y arquitectura de carpetas

### 10.1 Stack

| Capa | Elección | Versión / licencia | Estado verificado |
|---|---|---|---|
| Motor | Godot 4.7.2, GDScript tipado | MIT | Estable 18‑ago‑2026 |
| Física | Jolt (integrado) | MIT | Default en proyectos nuevos desde 4.6; activar por clave |
| Terreno | Propio (`TerrainChunk`, `HeightMapShape3D`) | — | Evolución de `terrain.gd` |
| Streaming | Propio (`WorldStreamer`) inspirado en OWDB/chunx | — | OWDB (MIT, último commit 7‑ago‑2026) avisa de "desarrollo activo, puede borrar nodos"; chunx (MIT, 4.2+) es beta y para mundos a mano ⇒ no se adoptan, se toman ideas |
| Nieve/huellas | `SubViewport` cenital → `DrawableTexture2D` cuando madure | — | Referencias: godotshaders "Car tracks", `Flynsarmy/gd-snow-project` (MIT, 4.7) |
| Vehículos | Fork interno de Godot Easy Vehicle Physics | MIT, Godot 4.2+, Jolt OK | Ajustar a 60 Hz |
| Carreteras | Cinta propia; `godot-road-generator` solo si la autovía lo pide | MIT, 0.9.1 (4.4+) | Opcional |
| Navegación | `NavigationServer3D` directo, horneado async por chunk | — | Docs 4.7 |
| Red | Alto nivel de Godot (ENet, Spawner/Synchronizer) | — | Netfox (MIT) como opción futura para predicción |
| Persistencia | `godot-sqlite` | MIT, Godot 4.x, headless OK | |
| Arte | Blender 5.0.1 bpy → glTF con `-convcolonly` (como hoy), kits modulares en rejilla de 1 m | — | `ASSET_SPEC.md` a extender |
| Tests | Scripts `SceneTree` headless (como `tests/`) + `perf_drive`/`perf_horde` | — | |

### 10.2 Carpetas (evolución de `ARCHITECTURE.md` §2)

```
winter-survival/
├── project.godot                  # + physics/3d/physics_engine="Jolt Physics"; features 4.7
├── addons/                        # godot-sqlite (GDExtension). Nada más de terceros en v1.
├── assets/
│   ├── models/{characters,zombies,animals,props,vehicles,vegetation,kits/<kit_name>/,poi/}
│   ├── icons/ materials/ shaders/ (terrain.gdshader, snow_include.gdshaderinc, cutaway.gdshaderinc, trail_stamp.gdshader)
│   └── themes/
├── blender/                       # scripts bpy: build_all.py + kits/ (generadores de módulos por rejilla)
├── data/
│   ├── world/ (macro_map.png, macro_roads.json, biomes.gd, poi_registry.gd, stamps/*.exr)
│   ├── buildings/ (plantillas de planta *.json, kits.gd)
│   ├── loot/ (loot_tables.gd)  items.gd  recipes.gd  balance.gd  zombies.gd  vehicles.gd
│   └── server_rules.gd
├── scenes/
│   ├── main/ (boot.tscn, main_menu.tscn, game_client.tscn, game_server.tscn)
│   ├── world/ (chunk.tscn, poi/*.tscn [a mano], buildings/*.tscn [ensambladores], roads/)
│   ├── player/ actors/ (zombie.tscn, wolf.tscn, deer.tscn) vehicles/ (car_base.tscn, variantes)
│   ├── effects/ (snowfall, snow_trails, fire, blizzard_fog)
│   └── ui/
├── scripts/
│   ├── autoload/ (Events, Net, GameState, Assets, AudioManager, Persistence, WorldGen)
│   ├── core/ (guid.gd, rng.gd, spatial_hash.gd, budget_queue.gd)
│   ├── world/
│   │   ├── terrain/ (height_function.gd, terrain_chunk.gd, surface.gd)
│   │   ├── streaming/ (world_streamer.gd, chunk_layers.gd, chunk_state.gd)
│   │   ├── scatter/ (scatter_gen.gd, scatter_index.gd, multimesh_chunk.gd)
│   │   ├── towns/ (settlement_gen.gd, road_graph.gd, road_mesh.gd, parcel_obb.gd, building_assembler.gd, lot_assign.gd)
│   │   ├── nav/ (nav_baker.gd, nav_query_queue.gd)
│   │   ├── weather/ day_night.gd weather.gd snow_state.gd
│   │   └── cutaway/ (cutaway_manager.gd)
│   ├── ai/ (zombie_brain.gd, population_manager.gd, ai_lod.gd, steering.gd, flowfield.gd [v2])
│   ├── vehicles/ (raycast_vehicle.gd, tire_model.gd, vehicle_net.gd)
│   ├── net/ (server/ (server_main.gd, chunk_interest.gd, damage_resolver.gd, validation.gd), client/ (client_main.gd, interpolation.gd), replication/)
│   ├── persistence/ (backend.gd, sqlite_backend.gd, file_backend.gd, chunk_delta.gd, migrations/)
│   ├── components/ player/ effects/ ui/
│   └── main/
├── server/ (export_presets: preset "Dedicated Server"; run_server.sh; server.cfg.example)
├── tools/ (plugin de editor: vista del plano macro, previsualización de asentamiento por semilla, editor de POI con sellos)
└── tests/ (smoke_test.gd, screenshot.gd, perf_drive.gd, perf_horde.gd, net_smoke.gd [servidor headless + 2 clientes headless])
```

Reglas: todo generador vive en `scripts/world/**` y es **puro** (sin acceso a `SceneTree`) hasta la fase de instanciación; `Net` es el único autoload que sabe si somos servidor; los sistemas consultan `Net.is_server` una vez en `_ready` y se desactivan (`set_process(false)`) donde no toque.

---

## 11. Migración desde VENTISCA (fases, cada una jugable)

| Fase | Entregable | Cambios clave |
|---|---|---|
| **0. Base técnica** (1 semana) | El slice actual corre en Jolt, 4.7.2, con tests verdes | Añadir `physics/3d/physics_engine="Jolt Physics"`; revisar `floor_max_angle`, márgenes de cápsulas y `HeightMapShape3D` bajo Jolt; capa `zombies`; `Camera3D.far = 60`; sombras 2 splits/4096. |
| **1. Terreno por chunks** (2 semanas) | El claro es 9 chunks de un mundo de 3 × 3 km de bosque | `terrain.gd` → `height_function.gd` + `terrain_chunk.gd` (flat shading por derivadas); `world.gd` → `world_streamer.gd`; el pad del claro y el lago pasan a sellos; `Bounds` → borde del mundo. `scatter.gd` → `scatter_gen.gd` + MultiMesh por chunk + `scatter_index.gd` (talar árboles sigue funcionando). Test: caminar 3 km sin *hitches*. |
| **2. Nieve nueva** (1 semana) | Huellas de jugador/lobo/coche por viewport; acumulación global | `footprints.tscn` → `snow_trails.tscn`; `snow_include.gdshaderinc` en todos los materiales del mundo; `GPUParticles3D` para nevada. |
| **3. Carreteras, POIs y aldea** (3 semanas) | Una aldea procedural + gasolinera a mano + camino al claro | `road_graph`/`road_mesh`, `parcel_obb`, primer kit modular (bpy), 10 plantillas de planta, `cutaway_manager` (generaliza `cutaway.gd`), loot determinista por contenedor. |
| **4. Zombis y navmesh** (3 semanas) | 100 zombis en la aldea a 60 FPS; lobos migrados a la misma IA | `nav_baker` por chunk (async), `nav_query_queue`, `ai_lod`, `population_manager`; `wolf.gd`/`steering.gd` se apoyan en el navmesh en lugar de whiskers. |
| **5. Vehículos** (2 semanas) | Camioneta conducible con tracción por superficie, gasolina y daño | `raycast_vehicle.gd`; `pickup_truck.tscn` pasa a `car_base.tscn` + variante; hielo del lago con μ 0.12. |
| **6. Red y servidor** (4 semanas) | 4 jugadores en servidor headless; PvP por flag | `Net`, `game_server.tscn`, `MultiplayerSpawner/Synchronizer`, filtros por chunk, `damage_resolver`, `Inventory`/`GameState` pasan de autoload global a **componentes por jugador** (`PlayerState`) — es el mayor refactor del slice y conviene hacerlo antes de la fase 3 si el equipo lo permite. |
| **7. Persistencia** (2 semanas) | Reinicio del servidor sin perder nada | `godot-sqlite`, `chunk_delta`, migraciones, backups. |
| **8. Pueblo y contenido macro** (continuo) | Pueblo de 120+ edificios, autovía, checkpoint | Plano macro completo; kits comerciales/servicios; `perf_drive`/`perf_horde` como puertas de calidad. |

Deuda del slice que hay que pagar en el camino: `Inventory`/`GameState`/`QuestManager` como autoloads de un solo jugador (fase 6); árboles como nodos individuales (fase 1); huellas como mallas (fase 2); `RegionTracker` por polling (pasa a evento de chunk); textos de UI acoplados (sin cambio).

---

## 12. Riesgos y mitigaciones

| Riesgo | Prob. | Impacto | Mitigación |
|---|---|---|---|
| Rendimiento de `CharacterBody3D` en masa incluso con Jolt (issue #93184 sigue abierto) | Media | Alto | LOD de IA (§5.3): cuerpo físico solo < 40 m; `perf_horde` desde la fase 4; plan B: zombis activos como `RigidBody3D` cinemáticos o movimiento por `PhysicsServer3D` sin nodos. |
| Stutter de streaming en coche | Media | Alto | Presupuesto de 2 ms, anillo 2 precargado, edificios sub‑divididos, `perf_drive`; *shader baker* al exportar (4.5+) para evitar compilaciones en caliente. |
| Refactor a multijugador tardío (autoloads de un jugador) | Alta | Alto | Hacer `PlayerState` por jugador en la fase 1–2 aunque el juego siga siendo *single*. |
| `DrawableTexture2D` experimental / bug D3D12 | Alta | Bajo | Implementar huellas con `SubViewport`; interfaz `SnowTrailMap` para cambiar después. |
| Terrain3D si se decidiera usar (4.7 no listado oficialmente; `precision=double` roto; colisión ligada a cámara) | — | — | No se usa en v1; si el mundo creciera o se quisiera esculpir en editor, evaluar 1.1.0 estable con `Full/Game` en servidor. |
| Determinismo cliente/servidor de generadores (float, orden de iteración de `Dictionary`) | Media | Alto | Generadores con enteros/`RandomNumberGenerator` sembrado, arrays ordenados, nunca `Dictionary.keys()` sin ordenar; test que compara hashes de chunk entre dos procesos. |
| Trampas con autoridad de cliente (PvP opcional) | Media | Medio | Validación de servidor; documentar que PvP es "entre amigos"; netfox si hiciera falta autoridad de servidor con predicción. |
| Límite de 8 luces por malla en Compatibility | Alta | Medio | Preset Compat: farolas sin luz real (solo emisivo + halo), fogatas/faros priorizados; `distance_fade` en luces. |
| Tamaño de contenido del pueblo (kits, plantillas) | Alta | Alto | Empezar por 1 aldea (fase 3) y medir el ritmo de producción bpy antes de fijar 120 edificios. |
| Navmesh con puertas/barricadas dinámicas | Media | Medio | Rehorneado por chunk con *cooldown*; puertas como `NavigationLink3D` desactivables en vez de geometría. |

---

## 13. Fuentes consultadas

**Godot (documentación y código, leídos vía GitHub porque `godotengine.org` y `docs.godotengine.org` estaban bloqueados desde el entorno de investigación)**

- Large world coordinates — https://raw.githubusercontent.com/godotengine/godot-docs/master/tutorials/physics/large_world_coordinates.rst
- Demo Large World Coordinates — https://raw.githubusercontent.com/godotengine/godot-demo-projects/master/misc/large_world_coordinates/README.md
- Background loading — https://raw.githubusercontent.com/godotengine/godot-docs/master/tutorials/io/background_loading.rst
- Occlusion culling — https://raw.githubusercontent.com/godotengine/godot-docs/master/tutorials/3d/occlusion_culling.rst
- Visibility ranges (HLOD) — https://raw.githubusercontent.com/godotengine/godot-docs/master/tutorials/3d/visibility_ranges.rst
- Mesh LOD — https://raw.githubusercontent.com/godotengine/godot-docs/master/tutorials/3d/mesh_lod.rst
- Using MultiMesh — https://raw.githubusercontent.com/godotengine/godot-docs/master/tutorials/performance/using_multimesh.rst
- Using servers — https://raw.githubusercontent.com/godotengine/godot-docs/master/tutorials/performance/using_servers.rst
- GPU optimization — https://raw.githubusercontent.com/godotengine/godot-docs/master/tutorials/performance/gpu_optimization.rst
- 3D rendering limitations — https://raw.githubusercontent.com/godotengine/godot-docs/master/tutorials/3d/3d_rendering_limitations.rst
- Renderers (tabla comparativa) — https://raw.githubusercontent.com/godotengine/godot-docs/master/tutorials/rendering/renderers.rst
- Navigation: optimizing performance — https://raw.githubusercontent.com/godotengine/godot-docs/master/tutorials/navigation/navigation_optimizing_performance.rst
- Navigation: using navigation meshes (baking runtime, chunks) — https://raw.githubusercontent.com/godotengine/godot-docs/master/tutorials/navigation/navigation_using_navigationmeshes.rst
- Navigation: using NavigationAgents (avoidance) — https://raw.githubusercontent.com/godotengine/godot-docs/master/tutorials/navigation/navigation_using_navigationagents.rst
- Navigation: using NavigationServers — https://raw.githubusercontent.com/godotengine/godot-docs/master/tutorials/navigation/navigation_using_navigationservers.rst
- Using Jolt Physics — https://raw.githubusercontent.com/godotengine/godot-docs/master/tutorials/physics/using_jolt_physics.rst
- High-level multiplayer — https://raw.githubusercontent.com/godotengine/godot-docs/master/tutorials/networking/high_level_multiplayer.rst
- Exporting for dedicated servers — https://raw.githubusercontent.com/godotengine/godot-docs/master/tutorials/export/exporting_for_dedicated_servers.rst
- Saving games — https://raw.githubusercontent.com/godotengine/godot-docs/master/tutorials/io/saving_games.rst
- Clase `VehicleBody3D` — https://raw.githubusercontent.com/godotengine/godot/master/doc/classes/VehicleBody3D.xml
- Código `vehicle_body_3d.cpp` (raycasts a nivel de escena) — https://raw.githubusercontent.com/godotengine/godot/master/scene/3d/physics/vehicle_body_3d.cpp
- Clase `HeightMapShape3D` — https://raw.githubusercontent.com/godotengine/godot/master/doc/classes/HeightMapShape3D.xml
- Clase `GPUParticles3D` — https://raw.githubusercontent.com/godotengine/godot/master/doc/classes/GPUParticles3D.xml
- Clase `DrawableTexture2D` (4.7) — https://raw.githubusercontent.com/godotengine/godot/master/doc/classes/DrawableTexture2D.xml
- Clase `NavigationServer3D` — https://raw.githubusercontent.com/godotengine/godot/master/doc/classes/NavigationServer3D.xml
- Clase `MultiplayerSynchronizer` — https://raw.githubusercontent.com/godotengine/godot/master/modules/multiplayer/doc_classes/MultiplayerSynchronizer.xml
- Clase `SceneReplicationConfig` — https://raw.githubusercontent.com/godotengine/godot/master/modules/multiplayer/doc_classes/SceneReplicationConfig.xml
- CHANGELOG 4.7 — https://raw.githubusercontent.com/godotengine/godot/4.7-stable/CHANGELOG.md ; 4.6 — https://raw.githubusercontent.com/godotengine/godot/4.6-stable/CHANGELOG.md ; 4.5 — https://raw.githubusercontent.com/godotengine/godot/4.5-stable/CHANGELOG.md ; 4.4 — https://raw.githubusercontent.com/godotengine/godot/4.4-stable/CHANGELOG.md
- Release 4.7-stable (fecha) — https://github.com/godotengine/godot/releases/tag/4.7-stable
- PR "Use Jolt Physics by default in newly created projects" — https://github.com/godotengine/godot/pull/105737
- Issue CharacterBody3D vs Jolt (10–40 vs ~800 instancias) — https://github.com/godotengine/godot/issues/78761
- Issue rendimiento CharacterBody3D en niveles complejos — https://github.com/godotengine/godot/issues/93184
- PR agentes añadidos a la evitación tras pausa (2 000 agentes, CPU 5 % → 40 %) — https://github.com/godotengine/godot/pull/120249
- Issue `DrawableTexture2D.setup()` vacío en D3D12/Forward+ — https://github.com/godotengine/godot/issues/123507
- Límite de luces por objeto (Compatibility/Mobile) — https://github.com/godotengine/godot/issues/107070 y https://github.com/godotengine/godot/issues/83280
- Godot 4.7.2 (18‑ago‑2026, 57 fixes) — https://www.opensourceforu.com/2026/08/godot-4-7-2-released/ ; https://godotengine.org/article/maintenance-release-godot-4-7-2/ (vía resultados de búsqueda)
- Resúmenes de 4.5/4.6/4.7 (vía búsqueda): https://godotengine.org/releases/4.7/ ; https://godotengine.org/releases/4.6/ ; https://godotengine.org/releases/4.5/ ; https://gamefromscratch.com/godot-4-6-released/ ; https://alternativeto.net/news/2025/9/godot-4-5-adds-stencil-buffer-screen-reader-support-visionos-export-shader-baker-and-more

**Terreno y addons**

- Terrain3D (repo, README, releases, docs en `doc/docs`) — https://github.com/TokisanGames/Terrain3D ; https://github.com/TokisanGames/Terrain3D/releases ; https://raw.githubusercontent.com/TokisanGames/Terrain3D/main/doc/docs/platforms.md ; https://raw.githubusercontent.com/TokisanGames/Terrain3D/main/doc/docs/collision.md ; https://raw.githubusercontent.com/TokisanGames/Terrain3D/main/doc/docs/navigation.md ; https://raw.githubusercontent.com/TokisanGames/Terrain3D/main/project/addons/terrain_3d/plugin.cfg ; issue precisión doble en 4.7.2 — https://github.com/TokisanGames/Terrain3D/issues/1043
- HTerrain (Zylann) — https://github.com/Zylann/godot_heightmap_plugin
- Godot Open World Database — https://github.com/DigitallyTailored/Godot-Open-World-Database (y su historial de commits)
- chunx — https://github.com/SlashScreen/chunx
- godot-road-generator — https://github.com/TheDuckCow/godot-road-generator
- Godot Easy Vehicle Physics — https://github.com/DAShoe1/Godot-Easy-Vehicle-Physics
- netfox — https://github.com/foxssake/netfox
- godot-sqlite — https://github.com/2shady4u/godot-sqlite
- Snow deformation con DrawableTexture (4.7) — https://github.com/Flynsarmy/gd-snow-project
- Shaders de nieve por normal mundial — https://github.com/walterpalladino/godot-shaders ; godotshaders "Car tracks on snow or sand" — https://godotshaders.com/shader/car-tracks-on-snow-or-sand-using-viewport-textures-and-particles/ y "World normal mix" — https://godotshaders.com/shader/world-normal-mix-shader/ (vía búsqueda; el sitio estaba bloqueado); goeshard "Snow deformation (with Godot)" — https://goeshard.org/2025/05/20/snow-deformation/ (vía búsqueda)

**Generación procedural y multitudes**

- Survey de ciudades procedurales (Parish–Müller, campos tensoriales, agentes, parcelas) — https://github.com/phiresky/procedural-cities/blob/master/paper.md
- Parish & Müller 2001 "Procedural Modeling of Cities" — https://www.semanticscholar.org/paper/Procedural-modeling-of-cities-Parish-M%C3%BCller/0d84fe2f56e333121a3a66837da3dc2769a3e079
- Vanegas et al. 2012 "Procedural Generation of Parcels in Urban Modeling" (OBB / straight skeleton) — https://twak.org/project/parcels/
- Flow fields: Game AI Pro cap. 23 (Emerson, "Crowd Pathfinding and Steering Using Flow Field Tiles") — https://www.gameaipro.com/GameAIPro/GameAIPro_Chapter23_Crowd_Pathfinding_and_Steering_Using_Flow_Field_Tiles.pdf ; Supreme Commander 2 — https://www.gamereplays.org/community/Supreme_Commander_2_FlowField_Pathfinding-t587422.html ; https://howtorts.github.io/2014/01/04/basic-flow-fields.html (vía búsqueda)
- Godot procedural3d (kits modulares) — https://github.com/RodZill4/godot-procedural3d ; Gaea — https://github.com/gaea-godot/gaea

**Juegos de referencia**

- Project Zomboid B42 (celdas 256×256, chunks 8×8) — https://github.com/kaatbailey/PZMapCreation ; https://pzfans.com/HowBigIsProjectZomboidMap/ (vía búsqueda) ; StreamZed (streaming) — https://projectzomboid.com/blog/news/2019/09/streamzed/ (vía búsqueda)
- DayZ Chernarus 225 km² / Livonia 163 km² — https://xgamingserver.com/tools/dayz/map ; https://wobo.tools/dayz-map-tool?map=chernarus (vía búsqueda)
- 7 Days to Die Navezgane ≈ 32 km², RWG — https://www.exitlag.com/blog/7-days-to-die-map/ (vía búsqueda)
- Unturned tamaños de mapa — https://steamcommunity.com/sharedfiles/filedetails/?id=2975937581 ; https://steamcommunity.com/app/304930/discussions/0/613935404035790573/ (vía búsqueda)
- State of Decay 2 ≈ 5 km² por mapa — https://gameinformer.com/games/state_of_decay_2/b/xboxone/archive/2017/04/06/undead-labs-talks-map-size-in-state-of-decay-2.aspx ; https://www.gamedeveloper.com/design/procedurally-generating-enemies-places-and-loot-in-i-state-of-decay-2-i- (vía búsqueda)
- The Long Dark regiones — https://thelongdark.fandom.com/wiki/Region ; https://howbigisthemap.com/the-long-dark-run-across-the-maps/ ; GDC 2018 "A Long Dark Road" — https://www.gdcvault.com/play/1024896/A-Long-Dark-Road-Blending (vía búsqueda)

**Rendimiento (secundarias)**

- Draw calls (5 000 ≈ 8–10 ms de submisión) — https://bugnet.io/blog/optimizing-draw-calls-for-better-game-performance (vía búsqueda)
- CharacterBody3D vs MultiMesh a escala — https://www.slashskill.com/godot-4-characterbody3d-vs-multimesh-scaling-hundreds-of-units-without-killing-performance/ (vía búsqueda)
