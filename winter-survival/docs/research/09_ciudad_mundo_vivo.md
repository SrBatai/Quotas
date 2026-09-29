# 09 — Ciudad con rascacielos, mundo vivo y problemas ambientales (mundo de 6 × 6 km)

> Investigación y diseño para ampliar VENTISCA de 3 × 3 km a **≈ 6 × 6 km** con una ciudad (**ALTAVEGA**) con centro de rascacielos, autovía, río helado con puerto fluvial, polígono industrial, base aérea, suburbios y una sierra con estación de esquí; y para convertirlo en un **post‑apocalipsis habitado** con **problemas ambientales invernales como sistemas**. Fecha: 26‑sep‑2026. Motor **Godot 4.7.2**.
>
> **Decisiones del propietario (vinculantes, entrada de este documento)**: (1) post‑apocalipsis **habitado**: ciudades abandonadas llenas de rastros reales (atascos, luces que parpadean, humo, animales, pájaros) más vida dinámica (grupos de supervivientes, convoyes militares, quitanieves, saqueadores, eventos); **sin tráfico civil vivo**. (2) Mapa de **≈ 6 × 6 km**: el bosque y los pueblos actuales se quedan a un lado; se añade una ciudad con rascacielos, autovía, río helado o puerto e industria. (3) Sigue siendo invierno, con sus **problemas ambientales**.
>
> **Cámara de referencia** (código, `scripts/data/balance.gd`, hito G1): perspectiva, *pitch* **−48°**, FOV vertical **36°**, distancia **24 m** (zoom **16–38 m**), `far` 70 m, el pivote va 3 m por delante del jugador. El GDD v2 §3.1 aún dice −52° / 35° / 22 m (14–30): aquí se usan las cifras del código.
>
> **Prototipo ejecutado** (fuera del repo, en el *scratchpad* de la sesión, con `taskset -c 0,1`): escena sintética de centro urbano (8 × 8 manzanas, torres de 2–40 plantas, calle‑cañón de 12 m, 14 zombis) con la cámara del juego, en Compatibility (llvmpipe) y Forward+ (lavapipe). El shader completo está en §3.3 para recrearlo en `prototypes/citycut/` en el hito W0. Resultados en §3.8.
>
> Documentos que este informe propone tocar (tabla en §8.6): `PLAN_MAESTRO.md` (C2, C6, C8, C21, §4, §7, §9, §10), `GDD_MUNDO_ABIERTO.md` (§3.1, §4.5, §6.4, §17, §18), `ARQUITECTURA_V2.md` (§8, §9.3, §10, §13), `ASSET_SPEC_V2.md` (kit urbano), y alinea los docs 07 y 08, escritos en paralelo (§0.1). **Este documento no cambia código.**

---

## 0. Resumen ejecutivo

| Tema | Recomendación | Por qué (en una línea) |
|---|---|---|
| **Oclusión en ciudad** | **«Corte urbano»**, en capas: (A) **corte de altura ajustado al forjado** (todo lo que queda por encima de la losa de la planta siguiente a la del jugador se descarta si está entre la cámara y el jugador o si tapa el suelo a menos de 16 m de él); (B) **cápsula con tramado** cámara → pecho para árboles, farolas, pasos elevados y grúas; (C) **tapas de sección**: las caras traseras se pintan en un color de sección, de modo que un edificio cortado se lee como una **planta arquitectónica**; (D) **siluetas** con `depth_test_inverted` para los jugadores (siempre) y los zombis percibidos; (E) interior del edificio propio con el `CutawayManager` de M6a (tejado y plantas superiores en `SHADOWS_ONLY`) | Es la única combinación que resiste la **cámara dentro de una torre** (a 24 m la cámara está a 17.8 m de altura y 13 m por detrás del jugador). Prototipo en calle‑cañón: **100 %** de los píxeles del jugador y de los zombis visibles a 16, 24 y 38 m, frente a **0–15 %** sin corte y **28–59 %** con solo la cápsula (3.5–5.5 m) a 38 m. Todo va en los materiales compartidos `world_vcol` / `world_vcol_struct` (C2): 5 *globals*, 4 uniformes por instancia, `discard` con umbral Bayer, sin *stencil* obligatorio; compilado y medido en Forward+ y Compatibility |
| **Tamaño y rejilla** | **6 144 × 6 144 m = 96 × 96 chunks de 64 m.** El valle actual se queda en el **cuadrante noroeste con sus coordenadas, índices de chunk y `wid` intactos** (el chunk 24 sigue centrado en el origen); el mundo crece hacia el **este y el sur**. Macro **768 × 768** a 8 m/px. Sin *origin shifting* (máximo 4.6 km del origen) | No cambia ni un hash del valle: los tests de determinismo, las rutas de *perf walk* y los deltas guardados siguen valiendo. Chunks de 64 m: todos los presupuestos (streaming 2 ms, horneado de navmesh 20–85 ms, deltas) están medidos a ese tamaño |
| **Mapa** | Valle de Valdenieve (NO, sin cambios) · **ALTAVEGA** (NE): casco viejo, río Albo, distrito financiero con torres, ensanche, estación, A‑14 con el Gran Atasco · puerto fluvial y **polígono** (centro‑E) · **base aérea** y suburbios (SE) · **sierra de Peña Blanca** con estación de esquí, desfiladero con aludes y el túnel derrumbado de la N‑140 (SO) | El valle sigue siendo el principio seguro; la ciudad es el juego tardío, a 1.6–2.7 km del claro por un puerto de montaña con control militar; la periferia (4–5 km) es el final |
| **Generación de la ciudad** | **Híbrido**: herramienta **offline** (`tools/gen_city.gd`) que hornea trazado, manzanas, parcelas, arquetipos y alturas a `data/world/city/altavega_*.json` (como el `macro_map.png`); **≈ 14 bloques héroe** hechos a mano como escenas; **familias de torres por gramática** (zócalo + planta tipo + coronación) generadas en Blender (bpy); el mundo por semilla solo **viste** (coches, daños, botín, cadáveres). Las torres CC0 winterizadas del doc 07 sirven de **materia prima** para las torres no enterables, tras una etapa nueva «listo para corte» | La ciudad es la misma en todos los servidores (se aprende, «nos vemos en la catedral»), el determinismo es trivial (se leen datos), los bloques héroe dan hitos, y las familias por gramática cumplen el contrato de corte (losas por planta, grupos, anclas) que ningún paquete CC0 trae |
| **Rendimiento** | **Sin *occlusion culling*** en la ciudad (culling por ocluso­res que el corte vuelve invisibles = bug). **Sin HLOD/impostores en juego** (la cámara no ve el horizonte); solo una «silueta de distrito» (1–3 *draw calls*) para **miradores** y menú. Torres **por grupos de plantas** (el *frustum* descarta las de arriba) + **proxy de sombra** (`SHADOWS_ONLY`). Congelados como **estatuas en MultiMesh**. Presupuesto de ciudad: **≤ 1 000 *draw calls* típicos / ≤ 1 500 máx.** | El rayo superior de la cámara baja 30°: nada por encima de la altura de la cámara más allá de ≈ 31 m entra en pantalla. Lo caro de una torre no es verla, es su sombra y su navmesh |
| **Mundo vivo** | Tres capas: **estática por semilla** (atascos, controles, campamentos, grafitis, ventanas encendidas por generador, humo, tendederos: 0 B/s); **ambiental en cliente** (cuervos que delatan movimiento, ratas, perros, restos al viento, neón: ~0 B/s); **dinámica en servidor** (comerciantes y saqueadores, convoyes, helicópteros, quitanieves, radio, lanzamientos, director del mundo: ≤ 3 kB/s por cliente) | La historia se cuenta con rastros baratos; lo caro (IA humana) se limita a **≤ 12 humanos L0 por servidor** y sin diálogos. **Exige enmendar el no‑objetivo 2** del PLAN §10 |
| **Problemas ambientales** | 13 sistemas sobre un **`HazardSystem`** común (global en `WorldState`, regional por distrito/masa de agua, local por edificio en `ChunkDelta`). Los de más juego por coste: **red eléctrica por sectores** (devolver la luz tiene precio: alarmas, tuberías que revientan, zombis que se descongelan), **tormenta de hielo**, **aludes** en la sierra, **hielo fino** en el río, **tuberías → inundación → placas de hielo**, **inversión térmica** (subir a una torre = salir del *smog* y del frío) | Cada sistema tiene lectura cenital clara, interactúa con zombis (congelar, despertar, enterrar, atraer), con vehículos (μ, arranque, bloqueo de carreteras) y con el co‑op (rescates, reparto de tareas) |
| **Roadmap** | **W0** *spike* del corte urbano (S, en paralelo con el arte de M5) → **W1** mundo de 6 km (M) **antes de M5** → M5 → M6a (kit «listo para corte») → M6b → M7 → **C1** Altavega núcleo (L/L) → **V1** vida estática y ambiental (M/M) → M8 → **E1** clima extremo (L/M) → M9a → **C2** hitos, puerto e industria (L/L) → M9b → **E2** peligros urbanos (L/M) → **C3** periferia sur (M/L) → **V2** vida dinámica (L/M) → M10 | Lo arriesgado primero (legibilidad y rejilla), la rejilla antes de que SQLite (M5) congele claves y `wid`; el contenido urbano detrás del kit (M6a) y los coches (M7); la IA humana detrás del director completo (M9b). Se dobla el trabajo restante: §8.4 marca dónde cortar para v2.0 |

### 0.1 Relación con los documentos 07 y 08 (escritos en paralelo)

- **Coincidencias.** El doc 08 §1.1 llega al mismo hallazgo geométrico (el *skyline* no existe en juego; cuentan la base, la azotea baja y la sombra) y propone lo mismo en ventanas por celdas con ocupación por *hash*, torres en tres piezas con proxy de sombra `SHADOWS_ONLY`, deshielo visible junto a fuentes de calor y silueta del jugador. Este documento adopta esas piezas.
- **Oclusión.** El P0 del doc 08 (fundido tramado en un cilindro cámara → jugador de 4–6 m, activado por edificio) es la **capa B** de §3. El prototipo de §3.8 muestra que sola no basta: a 38 m, con la cámara dentro de una torre, deja ver el 28 % de los zombis con radio 3.5 m y el 59 % con 5.5 m, y enseña un «ojo de buey» rodeado de forjados. Recomendación: implementar ese P0 **como el corte urbano completo** (capas A + B + C + D; mismo shader, mismo orden de coste, mismo registro de edificios) y hacer las siluetas con `depth_test_inverted` (probado en 4.7.2 en ambos renderizadores) antes que con `STENCIL_MODE_XRAY` (experimental). **W0 y G2a comparten este trabajo**: se hace una vez y antes del kit de M6a.
- **HLOD.** El doc 08 §3.13 propone HLOD por manzana para más de 120 m, el mapa y el menú; aquí se limita a miradores y menú, porque en juego nada lejano entra en el *frustum*. Es el mismo artefacto; solo cambia cuándo se dibuja.
- ***Occlusion culling*.** El doc 08 lo deja en P3 («medir»); aquí se desaconseja en la ciudad porque es incompatible con el corte (§4.6).
- **CC0.** El doc 07 encontró espejos en GitHub (Kenney en `series-ai/jam-ready-assets`, KayKit oficial, Quaternius en `.usda`) y un pase `winterize` que lleva esos modelos al contrato de color de vértice. Eso cambia la columna (a) de §4.5: los CC0 ya no están bloqueados ni rompen C2. Les sigue faltando lo que exige el corte (volumen cerrado, una losa por planta, grupos de plantas, anclas `Spawn_*`). Propuesta: **añadir a `winterize` una etapa «listo para corte»** (cerrar el volumen, insertar losas a la altura de planta que ya detecta, trocear en grupos de 4 plantas, generar el proxy de sombra) y usar las torres winterizadas como **fuente de las familias de torres no enterables**; bpy sigue haciendo zócalos enterables, interiores y bloques héroe.
- **Precisión y PCSS.** Los docs 06 (R‑G1) y 08 avisan de que el desenfoque PCSS depende de la distancia al origen (#86536). Con el valle en el origen y la ciudad a 2–4.6 km, el problema aparece justo en la ciudad. Opciones: PCSS solo en `alto` con ángulo ≤ 1.2°, o desplazamiento de origen **solo en el cliente** (doc 01 §4.3; el servidor sigue en coordenadas absolutas). Riesgo R23 (§8.5).

---

## 1. Lo que ve la cámara en una ciudad

Con la cámara del código (pitch −48°, FOV 36°: el rayo superior del *frustum* baja **30°** y el inferior **66°**; el pivote va 3 m por delante del jugador):

| Zoom | Altura de cámara | Cámara detrás del jugador (horizontal) | Suelo visible (detrás → delante del jugador) | Altura máx. visible sobre el jugador | Un ocluso­r a 3 / 6 / 10 m del jugador (hacia la cámara) tapa el pecho si mide más de |
|---|---|---|---|---|---|
| 16 m | 11.9 m | 7.7 m | 2.4 m → 12.9 m | 7.4 m | 5.4 / 9.5 / 15.1 m |
| **24 m** | **17.8 m** | **13.1 m** | **5.1 m → 17.8 m** | **10.3 m** | **5.0 / 8.8 / 13.9 m** |
| 38 m | 28.2 m | 22.4 m | 9.9 m → 26.5 m | 15.3 m | 4.8 / 8.4 / 13.3 m |

Consecuencias, todas vinculantes para el diseño de la ciudad:

1. **El horizonte urbano (*skyline*) no existe en juego.** Un punto más alto que la cámara solo entra en pantalla si está a menos de ≈ 31 m por delante de ella. Las torres que están «más allá» del jugador enseñan como mucho sus 7–15 m inferiores. Una silueta de rascacielos solo se ve en **miradores** (§3.7), en el menú y en el mapa de papel. Por eso los impostores y el HLOD del horizonte no sirven en juego (§4.6), igual que concluía el doc 01 §1.2 para el bosque.
2. **Los tejados que se ven son los bajos.** A 24 m solo se ve entero el tejado de un edificio de hasta 2–3 plantas a la altura del jugador (4–5 plantas con el zoom a 38 m). El «paisaje de tejados» de la ciudad en juego son **casas, naves, gasolineras, zócalos de torre, las tapas de sección de los edificios cortados y la azotea en la que uno está** (§3.6).
3. **Cualquier edificio de 2 plantas en el lado de la cámara tapa al jugador** si está a menos de 3 m, y uno de 4–5 plantas lo tapa a 10 m. En una calle de 12 m eso es siempre.
4. **La cámara acaba dentro de las torres.** A 24 m la cámara está a 17.8 m de altura y a 13.1 m detrás del jugador: cualquier edificio de 6 o más plantas cuya planta cubra ese punto **contiene la cámara**. Con renderizado normal se ven las losas de sus forjados desde dentro: en el prototipo, **0 % del jugador y 15 % de los zombis visibles** (§3.8). Un truco clásico («las carcasas de una cara son invisibles desde dentro») falla en cuanto el edificio tiene forjados.
5. **Sombras largas.** Con el sol de invierno bajo (≈ 25° a mediodía a 42° N) una torre de 100 m proyecta más de 200 m de sombra: las calles del centro están en sombra casi todo el día. Es coste (el paso de sombras dibuja la torre entera, §4.6) y es juego (calle en sombra = −2 °C, hielo que no se funde).
6. **La inclinación hacia el cursor** con arma (3 m; 6 m con mira) desplaza la zona que hay que despejar: el corte debe proteger también el punto de mira (§3.2).

---

## 2. Cómo lo resuelven otros juegos

| Juego | Qué hace | Qué tomamos | Qué evitamos |
|---|---|---|---|
| **Project Zomboid** (B41/B42) | Paredes con *cutaway* alrededor del jugador y al apuntar; se ve «a través de las paredes» solo **en la misma planta** del personaje; las plantas superiores se ocultan dentro. B42 amplía la altura máxima (sótanos y edificios muy altos, rascacielos de Louisville) | Visión por planta; corte a muñón de las paredes que dan a la cámara; lo que el personaje no ve, no se dibuja | Las quejas de B42 por ver el interior de edificios desde fuera («arruina la inmersión»): nuestro corte enseña la **planta de la siguiente losa**, no el interior de la planta baja |
| **XCOM / XCOM 2** | Selección de nivel (la rueda cambia la planta visible; techos y tejados transparentes); paredes que bajan cerca del cursor; mapas procedurales a partir de **parcelas hechas a mano** («Plot and Parcel», GDC 2018) | Corte **ajustado a forjados**; el mapa como parcelas: generador + bloques héroe | Tejados que «vuelven» durante animaciones (bug documentado por jugadores): el corte debe depender solo del jugador local y de la cámara, nunca del estado de animación |
| **Baldur's Gate 3** (recreaciones públicas) | Máscara esférica/cápsula localizada en el avatar: *spherecast* del avatar a la cámara, tramado con ruido; paredes y techos que se disuelven al entrar | La **cápsula tramada** para props, follaje y pasos elevados; la sombra se conserva | Cápsula como única técnica: en el prototipo, a 38 m deja ver el 28–59 % de los zombis (radio 3.5–5.5 m) |
| **Diablo IV y ARPG isométricos** | El arte se diseña para la cámara: formas grandes, se quita el detalle que estorba la lectura; ocultación de paredes entre cámara y jugador («Diablo‑style wall hiding») | Regla de autor para los bloques héroe: **nada alto en el lado de la cámara** de los recorridos principales; el corte como red de seguridad | Confiar solo en la puesta en escena: una ciudad generada no se puede «autorar» calle a calle |
| **The Ascent** | Cámara isométrica fija; verticalidad usada «de forma deliberada» para mostrar escala; algunos momentos cambian el encuadre | **Miradores** con encuadre especial (§3.7) para enseñar el *skyline*; capas (pasarelas, puentes) bajo el corte | Cambiar la cámara en combate |
| **Commandos: Origins** | Edificios de varias plantas integrados en el mapa; el interior solo se revela con un comando junto a la entrada (queja de jugadores: no se puede planificar el piso de arriba) | Revelar también por **cursor** (planificar sin estar dentro): el corte de §3.2 acepta un segundo centro (punto de mira) | Obligar a colocar una unidad en la puerta para ver |
| **Desperados III** | Conos de visión sombreados por obstáculos; contorno de los personajes (la opción «Outline Strength» no se puede apagar del todo) | **Siluetas siempre** para los jugadores; intensidad ajustable como opción de accesibilidad | — |
| **Shadowrun Returns** | 2D prerenderizado; al entrar, tejado y primer plano se desvanecen | Tiempos cortos de transición (≈ 0.25 s) | — |
| **Frostpunk** | La ciudad se ve desde arriba bajo la nieve; zonas de calor y mapa de calor como capa de lectura | El **tejado es el lienzo**: calor legible en tejados (nieve fundida, carámbanos, vapor = edificio habitado o calentado) | — |
| **Company of Heroes** | Edificios guarnecibles como contenedores tácticos (fuego desde ventanas, cobertura); la información de quién está dentro se da con la interfaz, no quitando el tejado (observación de juego, sin fuente técnica) | Edificios como posiciones defensivas (bases, NPC) con indicadores de ocupación | — |

Lo que Godot 4.7 ofrece de serie para esto (según la documentación de la rama *master*; lo que usa el prototipo —`depth_test_inverted`, `IN_SHADOW_PASS`, `CAMERA_POSITION_WORLD`, `global uniform`, `instance uniform`— además compilado y ejecutado en 4.7.2):

- `depth_test_inverted` en *spatial shaders*: el píxel se descarta si está **delante** de otros → siluetas solo donde el personaje está tapado.
- **Stencil** desde 4.5 (`read`, `write`, `write_if_depth_fail`, `compare_*`); `StandardMaterial3D` trae los modos *Outline* y *X‑Ray* como `next_pass` preconfigurado. **Restricción**: solo se puede **leer** el stencil en el **pase transparente**, y los materiales que lo escriben se dibujan en el pase transparente. Por eso el corte **no** usa stencil (los edificios perderían el pre‑pase de profundidad y el orden opaco).
- `IN_SHADOW_PASS` en *vertex* y *fragment*: el corte no se aplica en el pase de sombras → **la sombra de la torre cortada se conserva** (la calle sigue en sombra y el interior del edificio propio sigue oscuro).
- `CAMERA_POSITION_WORLD`, `FRAGCOORD`, `FRONT_FACING`, `global uniform` (`RenderingServer.global_shader_parameter_set`) e `instance uniform` (`GeometryInstance3D.set_instance_shader_parameter`, sin duplicar el material compartido de C2).
- *Occlusion culling* por CPU (Embree): pensado para interiores con muchas salas; en Forward+ el pre‑pase de profundidad ya reduce su beneficio; mover `OccluderInstance3D` en juego es caro. *Visibility ranges* con `visibility_parent` para HLOD y fundido por tramado.

---

## 3. Técnica recomendada: «Corte urbano»

### 3.1 Capas

| Capa | Qué hace | A qué se aplica | Dónde se decide | Coste |
|---|---|---|---|---|
| **A. Corte por forjado** | Descarta (con tramado en el borde) todo fragmento por encima de `y_corte` que esté en el **lado de la cámara** y dentro del **pasillo cámara → jugador** o que **tape el suelo** a menos de `R_zona` del jugador | Estructura de edificios (`cut_class = 1`) | Shader (`world_vcol_struct` + *include*), 5 *globals* por frame | ≈ 30–40 ALU por fragmento de edificio; `discard` |
| **B. Cápsula tramada** | Descarta con tramado lo que esté a menos de `R_cápsula` del segmento cámara → pecho | Todo lo que se pueda recortar: estructura, árboles, farolas, carteles, pasos elevados, grúas (`cut_class ≥ 1`) | Shader | ≈ 12 ALU |
| **C. Tapas de sección** | Las caras traseras visibles a través del corte se pintan con `cap_color` y normal hacia arriba: el edificio cortado parece macizo y enseña su planta (losa + tabiques como líneas oscuras) | Estructura (materiales `cull_disabled`) | Shader + contrato del kit (volúmenes cerrados, una losa por planta) | Rasterizar caras traseras de mallas low‑poly |
| **D. Siluetas** | `next_pass` con `depth_test_inverted`, sin sombreado, color plano: el personaje solo aparece como silueta donde algo lo tapa | Jugadores (siempre, color de su chaqueta); zombis **percibidos** (los que la «visibilidad honesta» del GDD §3.1 ya dibuja) | Material del personaje | +1 *draw call* por superficie de personaje, pase transparente |
| **E. Edificio propio** | `CutawayManager` (M6a): tejado y plantas > k en **`SHADOWS_ONLY`** (no `visible = false`: el interior debe seguir en sombra); paredes de la planta k del lado de la cámara → muñón de 0.6 m por shader (`inside = 1`) | El edificio en el que está (o apunta) el jugador local | CPU al cambiar de planta/edificio/guiñada | Despreciable |
| **F. Coherencia de juego** | Función pura `CityCut.is_cut(p)` idéntica al shader: el rayo del cursor ignora colisionadores cortados; la IA, la línea de visión y el ruido **no** cambian | Cliente | CPU | Despreciable |

El corte es solo una ayuda de dibujado: **no cambia qué ve el personaje**. Lo que el personaje no ve (GDD §3.1) sigue dibujándose desaturado y sin zombis, aunque el corte lo deje a la vista.

### 3.2 Reglas y parámetros

Sea `P` el pie del jugador local, `C` la cámara, `d̂` la dirección horizontal de `P` hacia `C`, `p` el fragmento en espacio mundo:

```
k        = planta del jugador en ese edificio = ceil((P.y + 0.5 − base_y − ground_h) / floor_h)   (0 en la calle)
y_corte  = base_y + ground_h + (k) · floor_h + stub                  # losa de la planta k+1 + muñón
lado     = smoothstep(−3, 1, dot(p.xz − P.xz, d̂))                    # 1 = entre el jugador y la cámara
pasillo  = 1 − smoothstep(W − 4, W, dist(p.xz, segmento C.xz → P.xz))  # incluye la torre que contiene la cámara
zona     = 1 − smoothstep(R − 4, R, |g.xz − P.xz|),  g = C + (p − C) · (C.y − P.y)/(C.y − p.y)
                                                                    # g = punto del suelo que p tapa
cápsula  = (1 − smoothstep(0.55·Rc, Rc, dist(p, segmento C → pecho))) · [t < 0.96]
fade     = max( [p.y > y_corte] · lado · max(pasillo, zona),  cápsula )
descartar si fade > umbral_Bayer4x4(FRAGCOORD)          (nunca en IN_SHADOW_PASS)
```

| Parámetro | Valor inicial | Nota |
|---|---|---|
| `floor_h` / `ground_h` | 3.0 m / 3.0 m (4.0 m en zócalos comerciales) | C8; `ground_h` por instancia |
| `stub` (muñón sobre la losa) | 0.4 m | Deja ver la planta de la losa siguiente como «plano»; 0.6 m dentro del edificio propio (GDD §3.1) |
| `W` (semiancho del pasillo) | 10 m (borde 4 m) | Despeja la torre que contiene la cámara aunque no tape la zona |
| `R` (zona protegida) | 16 m (20 m con zoom ≥ 32 m) | Cubre casi todo el suelo visible alrededor del jugador (§1) |
| Segundo centro | Punto de mira si se apunta a > 3 m (rifle con mira: 6 m) | `ws_aim` global; misma regla de zona |
| `Rc` (cápsula) | 3.5 m (4.5 m a zoom ≥ 32 m) | Árboles, farolas, pasos elevados, grúas |
| Transición de planta | `y_corte` interpola 0.25 s | Evita saltos de 3 m al subir escaleras |
| Tramado | Bayer 4 × 4 por `FRAGCOORD` | Estable (sin parpadeo temporal), idéntico en todas las GPU; con TAA/MSAA se suaviza |

Lo que **no** se corta nunca: el suelo (terreno, calles), los personajes, los vehículos conducidos, los contenedores interactivos bajo el cursor y todo lo que está por debajo de `y_corte` (plantas bajas: escaparates, portales, coches aparcados). Lo que está **más allá** del jugador (lado contrario a la cámara) tampoco: las fachadas del fondo se ven enteras hasta el borde superior de la pantalla.

### 3.3 Shader (include para `world_vcol.gdshader`)

Versión en *include* del shader del prototipo, **compilada y medida en 4.7.2** (Compatibility y Forward+; mismas cifras que §3.8). Los *built‑ins* de etapa (`CAMERA_POSITION_WORLD`, `FRAGCOORD`, `IN_SHADOW_PASS`) se pasan como parámetros, de modo que el *include* no depende de la etapa y la misma función se puede reproducir en GDScript (`CityCut.is_cut`). En el juego va como `shaders/include/city_cut.gdshaderinc`, incluido por el material compartido `world_vcol` (C2) y por los materiales de excepción de edificios (`window`, `glass`).

```glsl
// city_cut.gdshaderinc — corte urbano (doc 09 §3). The material needs render_mode cull_disabled.
global uniform vec3 ws_cut_player;   // feet of the local player
global uniform vec2 ws_cut_dir;      // horizontal unit vector player -> camera
global uniform vec4 ws_cut_params;   // x: stub (m), y: corridor half-width W (m), z: zone radius R (m), w: 1 = on
global uniform vec4 ws_capsule;      // xyz: player chest, w: capsule radius (m)
global uniform vec4 ws_aim;          // xyz: aim point, w: 1 = second zone centre

instance uniform float cut_class = 0.0; // 0 never, 1 structure (cut + capsule), 2 prop/foliage (capsule)
instance uniform float base_y = 0.0;    // ground slab of the building
instance uniform float ground_h = 3.0;  // ground floor height
instance uniform float inside = 0.0;    // 1 = the local player is inside this building
uniform float floor_h = 3.0;
uniform vec3 cap_color : source_color = vec3(0.16, 0.18, 0.22);

float cc_bayer4(vec2 p) {
	uvec2 q = uvec2(p) & uvec2(3u);
	uint xy = q.x ^ q.y;
	uint v = ((xy & 1u) << 3u) | ((q.y & 1u) << 2u) | (xy & 2u) | ((q.y & 2u) >> 1u);
	return (float(v) + 0.5) / 16.0;
}

// Does p hide the ground within r of centre (seen from camera c)?
float cc_zone(vec3 p, vec3 c, vec3 centre, float r) {
	float h = c.y - p.y;
	if (h <= 0.05) {
		return 1.0;
	}
	vec3 g = c + (p - c) * ((c.y - ws_cut_player.y) / h);
	return 1.0 - smoothstep(r - 4.0, r, length(g.xz - centre.xz));
}

// Stage built-ins are passed in by the caller (stage-independent include).
bool city_cut_discard(vec3 p, vec3 c, vec2 fragcoord, bool shadow_pass) {
	if (shadow_pass || ws_cut_params.w < 0.5 || cut_class < 0.5) {
		return false;
	}
	float fade = 0.0;
	if (cut_class < 1.5) {
		float side = smoothstep(-3.0, 1.0, dot(p.xz - ws_cut_player.xz, ws_cut_dir));
		float k = max(0.0, ceil((ws_cut_player.y + 0.5 - base_y - ground_h) / floor_h));
		float y_cut = base_y + ground_h + k * floor_h + ws_cut_params.x;
		if (inside > 0.5) {
			y_cut = base_y + (k > 0.0 ? ground_h + (k - 1.0) * floor_h : 0.0) + 0.6;
		}
		vec2 ab = ws_cut_player.xz - c.xz;
		float u = clamp(dot(p.xz - c.xz, ab) / max(dot(ab, ab), 1e-4), 0.0, 1.0);
		float corridor = 1.0 - smoothstep(ws_cut_params.y - 4.0, ws_cut_params.y, length(p.xz - (c.xz + ab * u)));
		float zone = cc_zone(p, c, ws_cut_player, ws_cut_params.z);
		if (ws_aim.w > 0.5) {
			zone = max(zone, cc_zone(p, c, ws_aim.xyz, ws_cut_params.z * 0.5));
		}
		fade = p.y > y_cut ? side * max(corridor, zone) : 0.0;
	}
	vec3 ba = ws_capsule.xyz - c;
	float t = clamp(dot(p - c, ba) / dot(ba, ba), 0.0, 1.0);
	float cap = (1.0 - smoothstep(ws_capsule.w * 0.55, ws_capsule.w, length(p - (c + ba * t)))) * step(t, 0.96);
	return max(fade, cap) > cc_bayer4(fragcoord);
}

// Uso en el material (world_vcol.gdshader; render_mode cull_disabled en la variante de estructura):
//   #include "res://shaders/include/city_cut.gdshaderinc"
//   varying vec3 wpos;
//   void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
//   void fragment() {
//       if (city_cut_discard(wpos, CAMERA_POSITION_WORLD, FRAGCOORD.xy, IN_SHADOW_PASS)) { discard; }
//       if (FRONT_FACING) { ALBEDO = COLOR.rgb; /* ... resto de world_vcol ... */ }
//       else { ALBEDO = cap_color; NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz); }
//   }
```

Materiales: el contrato C2 pasa de **uno a dos materiales compartidos**: `world_vcol` (props, mobiliario, vegetación: `cull_back`, solo la cápsula, `cut_class = 2`) y **`world_vcol_struct`** (estructura de edificios: `cull_disabled`, corte + tapas, `cut_class = 1`). Las excepciones `window`/`glass` incluyen el mismo *include*. Sigue habiendo un material por familia, sin duplicados por instancia: todo lo variable va en `instance uniform`.

Silueta (siguiente pase del material de personaje; equivalente al modo *X‑Ray* de `StandardMaterial3D`):

```glsl
shader_type spatial;
render_mode unshaded, depth_test_inverted, depth_draw_never, cull_back, shadows_disabled, fog_disabled;
uniform vec4 tint : source_color = vec4(0.25, 0.9, 1.0, 0.6);   // color de la chaqueta del jugador; zombis: ámbar
void fragment() { ALBEDO = tint.rgb; ALPHA = tint.a; }
```

### 3.4 Parte CPU: `CutManager` (cliente, solo jugador local)

- **Por frame** (≈ 0.05 ms): escribe `ws_cut_player`, `ws_cut_dir`, `ws_capsule`, `ws_aim` y ajusta `W`, `R`, `Rc` al zoom (`ws_cut_params`). Con la cámara girando (tween de 0.35 s) el corte gira solo, porque lee `CAMERA_POSITION_WORLD`.
- **Por edificio instanciado** (al crearse): `cut_class`, `base_y`, `ground_h`. Opcional: poner `cut_class = 0` a los edificios cuyo AABB no toca el pasillo ni la zona (prueba AABB de ≈ 100 edificios por frame, trivial) para que su *fragment* no evalúe el corte; como es un uniforme por instancia, la rama es coherente.
- **Al cambiar de edificio o de planta** (evento de `CutawayManager`): `inside` del edificio, grupos `Roof` y `Floor>k` a `SHADOWS_ONLY`, `y_corte` con tween de 0.25 s. **Nunca `visible = false` para tejados**: un tejado oculto que no proyecta sombra ilumina el interior con sol (error documentado en otros motores, ver §9).
- **Planta sin ver**: las plantas por debajo de la del jugador dentro de la torre se ocultan en CPU (las tapa su propia losa): es el «*occlusion culling*» que sí sirve aquí, y es gratis.
- **Cursor**: `CityCut.is_cut(point)` (misma fórmula en GDScript, sin tramado: umbral 0.5) → si el primer impacto del rayo del ratón está cortado, se repite el rayo excluyendo ese colisionador (máx. 4 iteraciones).
- **Accesibilidad**: `R` y la intensidad de las siluetas en Opciones.

### 3.5 Siluetas: política

- **Jugadores**: siempre (color de la chaqueta, alfa 0.6). Es el pilar «Nunca separes al grupo» en ciudad.
- **Zombis y NPC**: solo si están **percibidos** (ya dibujados por la visibilidad honesta: en cono y con línea de visión, o marcados por un *ping*). Los que solo se oyen siguen siendo **anillos de sonido**. Así la silueta no es un *wallhack*.
- **Vehículos**: silueta del vehículo que conduce el grupo (color neutro) para no perder el coche entre torres.
- Coste: 4 jugadores + ≤ 30 zombis percibidos ≈ **+34–60 *draw calls*** en el pase transparente.

### 3.6 «Los tejados primero»: cómo se ve la ciudad desde arriba

Como la cámara casi nunca ve una torre entera (§1), el aspecto de la ciudad lo deciden cuatro superficies horizontales. Reglas para el arte (entrada al `ASSET_SPEC_V2` del kit urbano):

1. **Tejados bajos** (casas, naves, gasolineras, zócalos de torre, mercado, estación): son el 40–60 % de la pantalla en barrios bajos. Gramática: pretil, casetas de ascensor, **climatizadoras**, **depósitos de agua**, antenas, lucernarios, placas solares, chimeneas. Nieve con **ventisqueros a sotavento** (según `wind_yaw` dominante del mapa), almohadas de nieve en pretiles (doc 05 §2.1) y **carámbanos** en los aleros.
2. **Tapas de sección** (edificios cortados): la planta de la losa siguiente con tabiques como líneas oscuras de 0.2 m, suelo en color de losa, huecos de escalera y de ascensor en negro. Es la «cara de arriba» de la ciudad en juego: legible, arquitectónica, y sin revelar el interior de la planta baja.
3. **Azoteas transitables** (bloques héroe y torres con escalera): **helipuerto** con un helicóptero estrellado, depósitos, antenas de telefonía, **«SOS» escrito con letras de 3 m** (malla, sin textura), campamentos de supervivientes, cuervos, un francotirador muerto; son lugares de juego (lanzamientos de suministros, evacuación, torre de radio, salir del *smog*, §6.10).
4. **El calor se lee en el tejado** (idea de Frostpunk): un edificio calentado tiene el tejado con **nieve fundida en manchas oscuras**, carámbanos y vapor en las chimeneas; uno con generador tiene ventanas encendidas y el zumbido. Es la señal de «aquí hay alguien».

**Miradores** (§3.7): el único sitio donde se ven los rascacielos como silueta.

### 3.7 Restricciones de cámara

1. **Se mantiene la regla del PLAN**: la cámara no colisiona ni gira sola. El corte hace innecesario acercarla (validado con la cámara dentro de una torre a 38 m).
2. **`far` dinámico**: `far = 70 + clamp(altura del jugador sobre el suelo bajo la cámara, 0, 150)`. En una azotea a 90 m se ve la calle; con niebla de altura para que el fondo no sea vacío.
3. **Zoom** 16–38 m sin cambios; `W`, `R` y `Rc` escalan con él (§3.2).
4. **Guiñada** en pasos de 45°. La cuadrícula del ensanche y del distrito financiero va **alineada con los ejes del mundo**: con la guiñada por defecto (45°) se ve en diagonal, como un isométrico clásico; nunca cuadrículas a 22.5° (la vista quedaría siempre torcida).
5. ***Pitch* urbano** (−55° en distritos densos): evaluado y **no recomendado por defecto** (mueve la cámara sola y el corte ya resuelve la lectura); queda como opción de accesibilidad si el *playtest* muestra desorientación.
6. **Miradores** (6: azotea de la Torre Albo, Torre de Telecomunicaciones, presa del Cierzo, Puente de Hierro, cima del telesilla de Peña Blanca, torre de control de la base aérea): mantener `V` 1 s en un punto marcado inclina la cámara a −20°, sube `far` a 1 500 m y dibuja las **siluetas de distrito** (§4.6). Revela regiones en el mapa de papel, humo de incendios y distritos con luz. Sin control del personaje mientras dura (3–6 s); se cancela con cualquier tecla.
7. **Cinemáticas** a pie de calle: solo en eventos de guion (llegada al Puente de Hierro, evacuación), nunca durante combate.

### 3.8 Prototipo y medidas

Escena: 8 × 8 manzanas de 34 × 34 m con calles de 12 m, un edificio por manzana de 2–40 plantas (volumen cerrado, losa por planta, tabique central, bandas de ventana por color de vértice), jugador en mitad de una calle N–S, 14 zombis a ≤ 16 m, sol de invierno a 28° con sombras. Métrica: píxeles del color del jugador/zombis frente a una referencia sin edificios (1280 × 720, remuestreo 640 × 360). Informativo: tiempos en render por software (llvmpipe/lavapipe), no representativos de una GPU.

| Modo (zoom 24 m) | Jugador visible | Zombis visibles | Jugador legible (visible o silueta) | Zombis legibles |
|---|---|---|---|---|
| `StandardMaterial3D` (sin corte) | 0 % | 15 % | 0 % | 15 % |
| Shader del corte, desactivado (caras traseras) | 0 % | 0 % | 0 % | 0 % |
| Solo siluetas | 0 % | 0 % | 100 % | 100 % |
| Solo cápsula (3.5 m) | 100 % | 92 % | 100 % | 92 % |
| Corte (semiespacio + radio) | 100 % | 100 % | 100 % | 100 % |
| **Corte recomendado (pasillo + zona) + siluetas** | **100 %** | **100 %** | **100 %** | **100 %** |

| Modo (zoom 38 m, cámara dentro de una torre) | Zombis visibles |
|---|---|
| `StandardMaterial3D` | 0 % |
| Solo cápsula (3.5 m) | 28 % |
| Solo cápsula (5.5 m, el radio del P0 del doc 08) | 59 % (a 24 m: 100 %) |
| Solo zona (16 m) | 96 % (queda un anillo de losas de la torre que contiene la cámara) |
| **Pasillo + zona** | **100 %** |

A 16 m, en ese punto, no hay oclusión (cámara más baja y cerca). Coste relativo en llvmpipe con los mismos píxeles: pasar de `StandardMaterial3D` al shader con `cull_disabled` y ruta de `discard` +32 %; evaluar las reglas +5 %; siluetas +1 *draw call* por personaje. Lo que el prototipo **no** mide: el coste en una GPU real, el kit definitivo (paredes de 0.2 m, escaleras), interiores ni la transición de plantas. W0 lo repite con `perf_probe` en escritorio.

### 3.9 Costes y riesgos

| Área | Coste | Mitigación |
|---|---|---|
| GPU | ≈ 30–40 ALU por fragmento de edificio + `discard` (el pre‑pase de profundidad de Forward+ también lo ejecuta). Estimado **≤ 0.3 ms a 1080p** en GTX 1060/RX 580 (una implementación comparable estima 0.1–0.3 ms a 2 MP en iGPU) | `cut_class = 0` por CPU en edificios lejos de la zona; Compatibility igual (no usa stencil) |
| Geometría | `cull_disabled` en estructura: el doble de triángulos rasterizados en edificios (30–60 k visibles: despreciable) | Solo en la malla de estructura; mobiliario y props siguen con `cull_back` |
| CPU | 5 *globals* por frame + pruebas AABB | — |
| Arte | El kit debe ser **cerrado** (sin paredes de una cara), con **una losa por planta** y tabiques con grosor, y un `cap_color` en la paleta | Se fija en W0, **antes** de producir el kit de M6a |
| Juego | El cursor golpea colisionadores cortados; interiores revelados | `CityCut.is_cut` compartido con el shader; la tapa enseña la losa superior, no la planta baja |
| Popping | Saltos de `y_corte` al cambiar de planta | Tween de 0.25 s + tramado en todos los bordes |
| Sombras | Una torre cortada que no proyectara sombra rompería la luz de la calle | `IN_SHADOW_PASS` → nunca se descarta en sombras (verificado) |

### 3.10 Alternativas descartadas

| Alternativa | Por qué no |
|---|---|
| Fundido por edificio (alfa del material o `transparency`) | Obliga al pase transparente y a ordenar; una torre entera desaparece (se pierde la ciudad); la sombra se pierde o hay que duplicarla |
| Círculo en espacio de pantalla | No sabe qué está delante o detrás; falla con la cámara dentro de una torre |
| Carcasas de una sola cara («invisibles desde dentro») | Los forjados tapan igual: 15 % de zombis visibles en el prototipo |
| Solo siluetas (*X‑ray*, Commandos/Desperados) | Se ve al personaje pero no el suelo, los obstáculos ni la nieve: no se puede jugar |
| Cilindro de stencil (opción M10 del PLAN) | Leer stencil exige el pase transparente: los edificios perderían el pre‑pase y el orden opaco. Útil solo como mejora de las tapas, no como base |
| Acercar la cámara o colisionar | Rompe el pilar «legible desde arriba» y la regla de cámara del PLAN |
| *Pitch* más vertical en ciudad | Reduce el problema (a −60° el ocluso­r a 3 m necesita 7.7 m) pero no lo elimina y mueve la cámara sola |

---

## 4. Expansión a 6 × 6 km

### 4.1 Rejilla, coordenadas y bordes

| Tema | Hoy (M3/M4) | Propuesta | Por qué |
|---|---|---|---|
| Tamaño | 3 072 m (48 × 48 chunks) | **6 144 m (96 × 96 chunks)** | «≈ 6 × 6 km» con chunks enteros; 37.7 km², ≈ 34 km² dentro del muro (×4 del actual) |
| Dónde queda el valle | Centrado en el origen | **Cuadrante noroeste**, mismas coordenadas: el mundo crece hacia **+x (este)** y **+z (sur)** | El chunk 24 sigue centrado en el origen y los índices 0–47 del valle no cambian. `wid` procedurales, semillas de *scatter* (celdas absolutas de 4/8/16 m), `PoiRegistry`, rutas de `perf_walk` y deltas guardados siguen valiendo |
| Índices de chunk | 0–47, `CENTER_CHUNK = 24` | **0–95, `CENTER_CHUNK = 24`** | Sin índices negativos: `key(cx, cz)` (16 + 16 bits), `in_grid` y los arrays empaquetados siguen igual |
| Extensión en metros | −1 568 … +1 504 | **−1 568 … +4 576** en ambos ejes | Mundo asimétrico respecto al origen; la precisión simple sobra (a 4.6 km el paso es ≈ 0.0005 m; el doc 01 §4.3 fija el límite práctico en ~8 km) |
| Muro jugable | ±1 450 m | **x, z ∈ [−1 450, +4 420]**: `WALL_MIN`/`WALL_MAX` por eje | El anillo de borde (montaña, niebla) sigue siendo de ≈ 384 m en los cuatro lados |
| Niebla del borde | Chebyshev desde el centro | **Distancia al muro más cercano** | `BORDER_START` deja de ser simétrico |
| Plano macro | 384² a 8 m/px (±1 536 m) | **768² a 8 m/px** (−1 536 … +4 608 m): 2.4 MB en RGBA8 | Las carreteras siguen en *splines* (`macro_roads.json`); 16 m/px bastaría para biomas pero no para los muelles ni el borde del río |
| Biomas (canal G) | 0 bosque denso … 5 asentamiento | + 6 casco viejo, 7 ensanche, 8 financiero, 9 barriada, 10 suburbio, 11 industrial, 12 puerto, 13 base aérea, 14 esquí/aludes, 15 río helado | Alimentan *scatter*, población y el generador de ciudad |
| Tamaño de chunk | 64 m | **64 m (sin cambios)** | Ver tabla siguiente |
| Mapa ASCII | 24 × 24 en `PoiRegistry.ASCII` | **48 × 48**, el de §4.2 (apéndice A en formato de código) | `char_center(c, r) = ((c − 12)·128, (r − 12)·128)`: la fórmula no cambia |

**¿Chunks de 64 m o de 128 m?**

| | 64 m (96² = 9 216 chunks) | 128 m (48² = 2 304 chunks) |
|---|---|---|
| Trabajo por frame (streaming, IA, red) | **Igual que hoy**: depende de los anillos alrededor de los jugadores, no del tamaño del mundo | Anillo 1 de 384 m: ×4 terreno, colisión y nodos residentes |
| Generación de un chunk | 20–35 ms en hilo (medido) | ≈ 80–140 ms: peor para coches a 25–30 m/s |
| Horneado de navmesh | 20–85 ms por chunk (medido) | ≈ 4× (y peor en ciudad) |
| Granularidad de hibernación y deltas | Fina | Gruesa: un chunk con un jugador mantiene caliente 1.6 ha |
| Coste de tener más chunks | Tablas O(N): población 9 216 × ~24 B ≈ 220 kB, índice de SQLite solo de chunks tocados | — |

**Decisión: 64 m.** Los edificios grandes que cruzan chunks (estadio, estación, naves) se registran como **POI multichunk** (se cargan si cualquiera de sus chunks entra en el anillo 2), igual que los *pads* actuales.

### 4.2 Mapa macro (ASCII; 1 carácter = 128 m; 48 × 48 = 6 144 m; norte arriba, x → este, z → sur)

Las filas 0–21 y columnas 0–22 son el mapa de PLAN §4.2 **carácter a carácter**, salvo la carretera nueva de la fila 9 (columnas 18–22), comprobado por script. El antiguo borde este (columna 23) pasa a ser la **Sierra del Cierzo** con un puerto de montaña; el antiguo borde sur (filas 22–23), la **Sierra de Peña Blanca** con el túnel de la N‑140.

```
        0                   1                   2                   3                   4
        0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7
      +-------------------------------------------------------------------------------------------------+
 z  0 | ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ~ ~ ~ ^ ^ ^ ^ ^ ^ ^ ^ U ^ ^ U ^ ^ ^ |  borde norte; ~ EMBALSE DEL CIERZO; U túneles del tren (c41) y de la A-14 (c44)
    1 | ^ ^ ^ # # # # # # # # # # # # # # X ^ ^ ^ ^ ^ ^ ^ ^ # # # # ~ ~ ~ # # # # # # # # : # # = ^ ^ ^ |  X = PUNTO DE EVACUACIÓN (sin cambios)
    2 | ^ # # # # # # # # # # # # # # # # = # # # # # ^ ^ ^ s s s s s D # s s s s s s s s : # # = ^ ^ ^ |  D = PRESA DEL CIERZO (central hidroeléctrica)
    3 | ^ # # # # # # # # # # # # # # # # M # # # # # ^ ^ ^ s s s s s ~ # s s s s s s s s : # # = ^ ^ ^ |  M = CONTROL MILITAR KM 12 (sin cambios)
    4 | ^ # # # # # # # # # # # # # # # # = # # # # # ^ ^ # = = = = = = = = = = = = = = = : = = = ^ ^ ^ |  = RONDA NORTE; Q = TORRE DE TELECOMUNICACIONES (Monte Cierzo)
    5 | ^ # # # # # # # # # # f # # # # # = # # # # # ^ ^ # # Q o o o ~ E E E E E E E E E : s s = ^ ^ ^ |  o = CASCO VIEJO; E = ENSANCHE
    6 | ^ # # # # # v S # # # . . . . . # = # # # # # ^ ^ # # o o o o ~ E E E E E N E E E : s s = ^ ^ ^ |  N = HOSPITAL PROVINCIAL
    7 | ^ # # # # # - - - - - - T T T . - = # # # # # ^ ^ # o o o o o ~ B B B E E E E E E : s s = ^ ^ ^ |  B = DISTRITO FINANCIERO (rascacielos)
    8 | ^ # # # # # # # # # # . T H T P - = # # # # # ^ ^ # o o o + o ~ B B B E E E E E E : s s = ^ ^ ^ |  + = CATEDRAL; T = VALDENIEVE (sin cambios)
    9 | ^ # # # # # # # # # # . T T T . # G - - - - - - M - = = = = = = = = = = = = = = = : = = = ^ ^ ^ |  - CARRETERA DEL PUERTO → M = CONTROL DEL PUERTO → = GRAN VÍA (PUENTE DE HIERRO en c31)
   10 | ^ # # # # # # # # # # # | # # # # = # # f # # ^ ^ # o o o o o ~ B B B E E E E E E F s s = ^ ^ ^ |  F = ESTACIÓN CENTRAL
   11 | ^ # # R # # # # # # # # | # # # # = # # # # # ^ ^ # o o o o o ~ B B B E E E m m E : s s = ^ ^ ^ |  m = CENTRO COMERCIAL
   12 | ^ # # # # D # # # # # # C # # # # = # # # # # ^ ^ # . Y b b b ~ E E E E E E E E E : s s = ^ ^ ^ |  C = CLARO DEL CAZADOR (origen, sin cambios); Y = UNIVERSIDAD
   13 | ^ # # # # ~ ~ # # - - - # # # # # A # # # # # ^ ^ # b b b b b ~ . E E E P E E E E : s s = ^ ^ ^ |  b = BARRIADA DE SAN LÁZARO; P = JEFATURA DE POLICÍA
   14 | ^ # # # ~ ~ ~ ~ ~ # | # # # # # # = # # # # # ^ ^ # b b b b b ~ . E E E E E E E E : s s j ^ ^ ^ |  j = EL GRAN ATASCO (A-14)
   15 | ^ # # # ~ ~ ~ ~ ~ # | # # # # f # = # # # # # ^ ^ # b b b b b ~ . E E E E E E O E : s s j ^ ^ ^ |  O = ESTADIO
   16 | ^ # # # # ~ ~ ~ ~ v # # # # # # # = # # # # # ^ ^ # b b b b b ~ E E E E E E E E E : s s j ^ ^ ^ |
   17 | ^ # # # # # ~ ~ # # # # # # # # # G # # # # # ^ ^ # = = = = = = = = = = = = = = = : = = j ^ ^ ^ |  RONDA SUR
   18 | ^ # # # # # # # # # # # # # # # # = - v + # # ^ ^ # . . G . . ~ I I I I I I I I I : # # j ^ ^ ^ |  I = POLÍGONO DEL ALBO; G = GASOLINERA DE LA RONDA
   19 | ^ # # # # # # # # # # # # # L # # = # # # # # ^ ^ # . . . . . ~ I I e I I I I I I : # # j ^ ^ ^ |  e = CENTRAL TÉRMICA Y SUBESTACIÓN
   20 | ^ # # # # # # # # # # # # # # # # = # # # # # ^ ^ # . . . W ~ ~ ~ W I I I I I I I : # # j ^ ^ ^ |  W ~ W = PUERTO FLUVIAL (dársena); q = PARQUE DE COMBUSTIBLES
   21 | ^ # # # # # # # # # # # # # # # # = # # # # # ^ ^ # . . . W ~ ~ ~ W I I I I q q I F # # j ^ ^ ^ |  F = ESTACIÓN DE MERCANCÍAS
   22 | ^ ^ # # # # # # # # # # # # # # # U # # # # ^ ^ ^ # . . . W ~ ~ ~ W I I I I q q I : # # j ^ ^ ^ |  U = TÚNEL DE PEÑA ROYA (boca norte, derrumbado)
   23 | ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ # . . . W ~ ~ ~ W I I I I I I I : # # j ^ ^ ^ |  ^ SIERRA DE PEÑA BLANCA (antiguo borde sur)
   24 | ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ # # # . . . # # ~ I I I I I I I I I : # G j ^ ^ ^ |  G = GASOLINERA DE LA A-14
   25 | ^ ^ ^ % % % % % % % % % ^ ^ ^ # # U # ^ ^ ^ ^ # # # . . . # # ~ I I I I I q I I I : # # j ^ ^ ^ |  U = boca sur del túnel; % = pistas / laderas de aludes; q = QUÍMICAS DEL ALBO
   26 | ^ ^ ^ % % % % % % % % % ^ ^ ^ % % = # ^ ^ ^ ^ # # # . . . # # ~ I I I I I I I I I : # # j ^ ^ ^ |  la N-140 baja por el DESFILADERO DE PEÑA ROYA
   27 | ^ ^ ^ % % % % % % % % % ^ ^ ^ % % = % % ^ ^ ^ # # # s s s s # ~ I I I I I I I I I : # # j ^ ^ ^ |  s = VEGA BAJA
   28 | ^ ^ ^ % % % % % % % % % ^ ^ ^ % % = % % ^ ^ ^ # # # s s s s # ~ # s s s s s s s s : # # j ^ ^ ^ |  s = URBANIZACIÓN LOS ÁLAMOS
   29 | ^ ^ % % % % ^ K ^ ^ ^ ^ ^ ^ ^ % % = % % ^ ^ ^ # # # s s s s # ~ # s s s s s s s s : # # j ^ ^ ^ |  K = ESTACIÓN DE ESQUÍ PEÑA BLANCA
   30 | ^ ^ % % % % ^ | ^ ^ ^ ^ ^ ^ ^ % % = % % # # # # # # s s s s # ~ # s s s s s s s s : # # j ^ ^ ^ |
   31 | ^ # # # # # # - - - - - - - - - - = % % # # # # # # # # # # # ~ # s s s s s s s s : # # = ^ ^ ^ |  - carretera de la estación de esquí
   32 | U : : : : : : : : : : : : : : : : = : : : : : : : : : : : : : : : : : : : : : : : : # # = ^ ^ ^ |  : = FERROCARRIL DEL ALBO (U = túnel en el borde oeste)
   33 | ^ ^ ^ # # # # # # # # | # # # # # = # # # # # # # # # # # # # ~ # s s s s s s s s # # # = ^ ^ ^ |
   34 | ^ ^ ^ # # # # # # # # | # # # # # = # # # # # # # # # # # # # ~ # s s s s s s s s # # # = ^ ^ ^ |
   35 | ^ # # ~ ~ ~ # # # # # | # # # # # = = = = = = = = = = = = = = = = = = = = = = = = = = A = ^ ^ ^ |  = N-140 sur → A = ÁREA DE SERVICIO LA VEGA → A-14
   36 | ^ # # ~ ~ ~ # # # # # v # # # # # # # # # # # # . . . . . . . ~ # M # # # # # # # # # # = ^ ^ ^ |  v = SANTA MARÍA DEL PUERTO; ~ = IBÓN HELADO; M = puerta de la base
   37 | ^ # # ~ ~ ~ # # # # # # # # # # # # # # # # # # . . . . . . . ~ Z Z Z Z Z Z Z Z Z Z Z Z = ^ ^ ^ |  Z = BASE AÉREA DE LA VEGA
   38 | ^ . . . . . . . . . . . . # # # # . . . . . . . . . . f . . . ~ Z Z Z Z Z Z Z Z Z Z Z Z = ^ ^ ^ |
   39 | ^ . . . . . . . . . . . . # # # # . . . f . . . . . . . . . . ~ Z Z Z Z Z Z Z Z Z Z Z Z = ^ ^ ^ |
   40 | ^ . . . . . . . . . . . . # # # # . . . . . . . . . . . . . . ~ _ _ _ _ _ _ _ _ _ _ _ _ = ^ ^ ^ |  _ = pista de aterrizaje (1.5 km)
   41 | ^ # # # # # # . f . . . . # # # # . . . . . . . . . . . . . . ~ Z Z Z Z Z Z Z Z Z Z Z Z = ^ ^ ^ |  f = granjas de la vega
   42 | ^ # # # # # # . . . . . . . . . . . . . . . . . . . . . . . . ~ Z Z Z Z Z Z Z Z Z Z Z Z = ^ ^ ^ |
   43 | ^ # # # # # # . . . . . . . . . . . . . . . . . . . f . . . . . . . . . . . . . . . x . = ^ ^ ^ |  x = AVIÓN ESTRELLADO
   44 | ^ # # # # # # . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . f . . . . . = ^ ^ ^ |
   45 | ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ~ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ = ^ ^ ^ |  borde sur (anillo de montaña); la A-14 sale por un túnel
   46 | ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ~ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ = ^ ^ ^ |
   47 | ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ~ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ ^ U ^ ^ ^ |
      +-------------------------------------------------------------------------------------------------+
   ^ montaña / borde    # bosque    . campo abierto, parque o vega    ~ agua helada (lago, embalse, río Albo, dársena)
   = carretera principal (N-140, A-14, rondas, Gran Vía)    - | carreteras secundarias    : ferrocarril    U boca de túnel
   s suburbio / urbanización    o casco viejo    E ensanche (5–8 plantas)    B distrito financiero (torres de 12–45 plantas)
   b barriada de bloques (8–14 plantas)    I polígono industrial    W muelles    Z base aérea    _ pista    % pistas de esquí / laderas de aludes
   j Gran Atasco (A-14)    letras = POI con nombre (leyenda de cada fila; las del valle, como en PLAN §4.2)
```

Distancias en línea recta desde el claro (0, 0) (a pie a 2.2 m/s · en coche a 60 km/h):

| Destino | Coordenadas | Distancia | A pie | En coche | Ruta real |
|---|---|---|---|---|---|
| Control del Puerto (entrada a la ciudad) | (1 536, −384) | 1.6 km | 12 min | 1.6 min | Gasolinera Norte → Carretera del Puerto (1.1 km de puerto de montaña) |
| Catedral (casco viejo) | (2 176, −512) | 2.2 km | 17 min | 2.2 min | + Gran Vía |
| Distrito financiero | (2 688, −384) | 2.7 km | 21 min | 2.7 min | + Puente de Hierro |
| Puerto fluvial | (2 432, 1 216) | 2.7 km | 21 min | 2.7 min | Por la ciudad y la ronda sur (≈ 4 km) |
| Estación de esquí | (−640, 2 176) | 2.3 km | 17 min | 2.3 min | N‑140 sur → túnel derrumbado (a pie) → desfiladero (≈ 3.2 km) |
| Estación central / Hospital Provincial | (3 712, −256) / (3 200, −768) | 3.7 / 3.3 km | 28 / 25 min | ≈ 3.5 min | — |
| Gran Atasco (A‑14) | (4 096, 1 280) | 4.3 km | 33 min | 4.3 min | — |
| Base aérea | (3 264, 3 520) | 4.8 km | 36 min | 4.8 min | Ciudad → A‑14 sur, o N‑140 sur (≈ 7 km) |

Un día de juego dura 30 min reales: **la ciudad está a medio día a pie** y la periferia a un día. Es intencionado: el coche (M7), las casas seguras intermedias y el quitanieves pasan a ser necesarios, y separarse «duele» (pilar 4).

### 4.3 Regiones (banner `REGIÓN — NOMBRE`)

Las del valle no cambian (PLAN §4.3). Nuevas:

| Región (banner) | Tipo | Centro (x, z) | Extensión | Contenido | Zombis por chunk | Hito |
|---|---|---|---|---|---|---|
| SIERRA DEL CIERZO | Cresta autorada | x ≈ 1 400–1 600 | 2 × 24 car. | Divisoria valle/ciudad; pinar, aludes menores | 0–1 | W1 |
| CARRETERA DEL PUERTO | Carretera de montaña | (1 150, −384) | 1.1 km | Curvas, quitamiedos, coches despeñados, **jalones** de nieve | 1–4 | W1 (trazado), C1 |
| CONTROL DEL PUERTO | POI a mano | (1 536, −384) | 80 × 60 m | Control militar caído a la entrada de la ciudad: barreras, garita, fosa, carteles de cuarentena | 15–30 | C1 |
| ALTAVEGA — CASCO VIEJO | Ciudad procedural (trazado orgánico) | (2 048, −512) | 640 × 900 m | Calles de 6–8 m, 3–4 plantas, soportales, plaza mayor | 10–20 | C1 |
| CATEDRAL DE ALTAVEGA | POI héroe | (2 176, −512) | 90 × 60 m | Nave, torre campanario (mirador bajo), cripta; refugio de horda | 20–35 | C2 |
| MONTE CIERZO — TORRE DE TELECOMUNICACIONES | POI héroe | (1 920, −896) | 60 × 60 m | Torre de 120 m con **mirador**; emisora de la radio de emergencia (§5.4) | 5–15 | C2 |
| UNIVERSIDAD | POI | (1 920, 0) | 200 × 150 m | Aulas, laboratorios (químicos), biblioteca | 15–30 | C2 |
| BARRIADA DE SAN LÁZARO | Ciudad procedural (bloques abiertos) | (2 048, 256) | 640 × 640 m | Bloques de ladrillo de 8–14 plantas, patios, comercios en bajos | 10–20 | C1 |
| RÍO ALBO | Río helado | x ≈ 2 432 | 128 m de ancho, 5.5 km | Hielo grueso/fino, canales, restos de barcas, **atajo sobre el hielo** | — | W1 (superficie), E1 (hielo fino) |
| PUENTE DE HIERRO | POI | (2 432, −384) | 140 m | Puente de celosía; control militar de la Gran Vía; **mirador** | 20–40 | C1 |
| PRESA DEL CIERZO | POI héroe | (2 432, −1 280) | 200 × 80 m | Central hidroeléctrica (fuente de la red, §6.11), **mirador** | 5–15 | C2 |
| ALTAVEGA — LAS TORRES | Distrito financiero (generador + torres héroe) | (2 688, −384) | 384 × 640 m | 25–35 torres de 12–45 plantas, plazas, zócalos comerciales; **Torre Albo** (45 plantas, azotea con helipuerto) | 20–40 | C1 (v0), C2 (héroes) |
| ALTAVEGA — ENSANCHE | Ciudad procedural (cuadrícula con chaflanes) | (3 072, −192) | 1.1 × 1.5 km | Manzanas cerradas de 5–8 plantas con patio, tiendas en bajos, farmacias, bancos | 12–25 | C1 |
| HOSPITAL PROVINCIAL | POI héroe | (3 200, −768) | 160 × 120 m | 6 plantas, urgencias, quirófanos, helipuerto; **objetivo de sesión de 4** | 40–60 | C2 |
| JEFATURA DE POLICÍA | POI héroe | (3 072, 128) | 80 × 60 m | Armería, calabozos, garaje de antidisturbios | 20–40 (30 % acorazados) | C2 |
| CENTRO COMERCIAL | POI héroe | (3 392, −128) | 256 × 128 m | Tres plantas, techo plano de gran luz (**colapso por nieve**, §6.12), aparcamiento | 30–50 | C2 |
| ESTACIÓN CENTRAL | POI héroe | (3 712, −256) | 200 × 90 m | Vestíbulo, andenes, un tren de evacuación atascado | 30–50 | C2 |
| ESTADIO — CAMPO DE REFUGIADOS | POI héroe | (3 456, 384) | 240 × 200 m | Campo de refugiados caído: tiendas, hospital de campaña, fosas; **comerciantes** en una tribuna (§5.4) | 60–100 (evento de horda) | C2 |
| URBANIZACIONES DEL NORTE / DEL ESTE | Suburbios procedurales | (2 048, −1 216) · (3 200, −1 216) · (3 904, −192) | ≈ 1.5 km² | Chalets y adosados (plantillas de M6a/M9a) | 3–8 | C3 |
| AUTOVÍA A‑14 | Autovía autorada N–S | x ≈ 4 096 | 6 km | Túneles norte y sur, enlaces con las rondas, gasolinera | 2–6 | W1 (trazado), C2 |
| EL GRAN ATASCO | POI lineal generado | x ≈ 4 096, z 256 … 2 304 | 2.2 km | Éxodo hacia el sur bloqueado: 1 500–2 500 coches, autobuses, ambulancias, camiones cisterna; **zombis atrapados en coches** | 20–40 | C2 |
| RONDA NORTE / RONDA SUR / GRAN VÍA | Vías urbanas | filas 4, 17, 9 | 2.3 km cada una | Pasos elevados (cápsula tramada), atascos urbanos | 4–10 | C1 |
| PUERTO FLUVIAL DEL ALBO | POI héroe + procedural | (2 432, 1 216) | 640 × 512 m | Dársena helada, grúas, silos, gabarras atrapadas en el hielo, naves | 6–12 | C2 |
| POLÍGONO DEL ALBO | Industrial procedural | (3 072, 1 344) | 1.2 × 1.3 km | Naves (50 % enterables, interiores grandes y baratos), talleres, concesionarios | 4–10 (naves 10–30) | C2 |
| CENTRAL TÉRMICA DEL ALBO | POI héroe | (2 816, 896) | 200 × 150 m | Torres de refrigeración, subestación (fuente de la red, §6.11) | 10–20 | C2 |
| PARQUE DE COMBUSTIBLES / QUÍMICAS DEL ALBO | POIs héroe | (3 392, 1 216) · (3 200, 1 664) | 150 × 150 m c/u | Depósitos (gasolina), planta química; **vertidos** y fugas (§6.7–6.8) | 10–20 | C2 |
| ESTACIÓN DE MERCANCÍAS | POI | (3 712, 1 152) | 300 × 80 m | Vagones, contenedores, cisternas descarriladas | 8–15 | C3 |
| VEGA BAJA / URBANIZACIÓN LOS ÁLAMOS | Suburbios procedurales | (1 984, 2 112) · (3 136, 2 368) | ≈ 1.3 km² | Chalets, colegio, supermercado | 3–8 | C3 |
| FERROCARRIL DEL ALBO | Línea autorada | fila 32 y columna 41 | 6 km | Tren de mercancías nevado, apeaderos, túnel oeste | 2–6 | C3 |
| ÁREA DE SERVICIO LA VEGA | POI | (3 968, 2 944) | 120 × 80 m | Gasolinera, restaurante de carretera, camiones | 8–15 | C3 |
| BASE AÉREA DE LA VEGA | POI héroe | (3 264, 3 520) | 1.5 km × 770 m | Pista, hangares (techos de gran luz), torre de control (**mirador**), helicópteros, puesto de mando; **Coloso**; punto de evacuación alternativo (§8) | 40+ | C3 |
| AVIÓN ESTRELLADO | POI | (3 840, 3 968) | 200 × 60 m | Avión de transporte partido en tres; botín militar | 15–25 | C3 |
| LA VEGA | Campo | filas 38–44 | ≈ 4 km² | Granjas, vallas, pajares | 1–4 | C3 |
| TÚNEL DE PEÑA ROYA | POI | (640, 1 280) → (640, 1 664) | 384 m | Derrumbado: se cruza **a pie** por una galería de servicio (oscura); el coche necesita el quitanieves o explosivos | 10–25 | W1 (trazado), C3 |
| DESFILADERO DE PEÑA ROYA | Carretera + laderas de aludes | x ≈ 640, z 1 790 … 2 820 | 1 km | N‑140 entre laderas `%`: **aludes** que cortan la carretera (§6.4) | 1–4 | E1 |
| ESTACIÓN DE ESQUÍ PEÑA BLANCA | POI héroe | (−640, 2 176) | 400 × 300 m + pistas | Hotel, telesillas (**mirador** en la cima), máquinas pisanieves, tienda de deportes (motonieves) | 8–20 | C3 |
| SANTA MARÍA DEL PUERTO | Aldea procedural | (−128, 3 072) | 150 × 150 m | Aldea de montaña (plantillas M6b), iglesia | 3–8 | C3 |
| IBÓN HELADO | Lago de montaña | (−896, 3 072) | 384 × 384 m | Hielo fino, cabaña, cadáver con botín en el centro | — | E1 |
| SIERRA DE PEÑA BLANCA | Montaña | filas 23–30 | — | Borde sur del valle; laderas de aludes | 0–1 | W1 |

### 4.4 Impacto técnico

**Código que cambia en W1** (lista cerrada, sin tocar la jugabilidad del valle): `WorldConst` (`WORLD_CHUNKS = 96`, `WALL_MIN/WALL_MAX`, `in_playable`, borde por lado), `MacroMap` (768², *half‑size* asimétrico), `tools/gen_macro_map.gd` (48 × 48, biomas nuevos, splines de A‑14, rondas, N‑140 sur y ferrocarril como sellos de terreno), `PoiRegistry` (ASCII 48 × 48, regiones y *pads* nuevos, reservas de terreno plano para los POI héroe aunque aún no tengan modelo), `Bounds`, `World` (niebla del borde), `chat.gd` (`/tp` con los muros nuevos), y los tests que afirman `WORLD_CHUNKS == 48`.

**Streaming.** El trabajo por frame depende de los anillos, no del tamaño del mundo. Cambian dos cosas: (1) la **A‑14** permite 30 m/s (un chunk cada 2.1 s, por encima de los 25 m/s probados); con el anillo 2 precargado y pocos edificios en la autovía cabe, pero `perf_drive` debe probarlo; (2) en ciudad la capa `BUILDINGS` pesa más: 4–20 edificios por chunk, cada torre con 3–10 grupos de plantas. Cada variante de familia es una `PackedScene` pre‑cargada (instanciar cuesta 0.2–0.5 ms): un chunk denso se monta en 3–5 frames con el presupuesto de 2 ms. A 15 m/s por calles (un chunk cada 4 s) sobra; se limita la velocidad efectiva en ciudad con el propio tráfico muerto.

**Servidor: memoria e hibernación.** Con 4 jugadores en 4 cuadrantes: ≤ 36 chunks calientes y ≤ 100 tibios, como hoy. Un chunk urbano caliente pesa más (50–150 formas de colisión de edificios, teselas de navmesh, `Spawn_*` registrados): **2–4 MB** frente a < 1 MB de bosque. Estimación de RSS del servidor: 250 MB base + 150–400 MB de chunks + 4 MB de datos de ciudad ⇒ **≤ 1.2 GB**, compatible con un VPS de 2 vCPU/4 GB. La hibernación no cambia; los sistemas con tiempo (fuego, carga de nieve, tuberías, §6) se **resuelven al despertar** el chunk a partir del tiempo transcurrido, sin simular chunks dormidos.

**Determinismo.** La ciudad **no se genera en tiempo de ejecución**: el trazado sale de datos horneados (mismos bytes en cliente y servidor, x86 y arm64). Lo que sí se genera por semilla (coches, daños, cadáveres, botín, vestido) usa `hash64(world_seed, GEN_CITY, lot_id, pieza)` — independiente del índice de chunk — y RNG entero. `determinism.gd` añade: hash del fichero de ciudad + hash del vestido de 50 parcelas en dos procesos.

**Navmesh a escala de ciudad.** Tres niveles:

| Nivel | Qué | Cuándo se hornea | Coste |
|---|---|---|---|
| Calle | Por chunk, como en M4 (calles, aceras, patios; los edificios son obstáculos de caja) | Anillo del jugador (≤ 96 m) | 20–40 ms en hilo (menos agujeros que un bosque) |
| **Planta de edificio** | Una tesela por planta enterable (`NavFloorTile`, ≤ 40 × 40 m) | Solo si un jugador está en el edificio o a < 30 m de su puerta, y solo las plantas k−1 … k+1 | 2–8 ms en hilo; ≤ 12 teselas/s |
| Enlaces | Escaleras (rampas horneadas en el núcleo de escalera o `NavigationLink3D` entre teselas), puertas (M6a), ascensores (enlace activo solo con corriente, §6.11) | Con la tesela | Despreciable |

Los zombis de plantas sin tesela son **población por planta** (L3: un contador por planta y edificio) y se materializan cuando su planta se hornea. Las consultas siguen acotadas (1 200 polígonos, 90 m, 1.5 ms por tick). *Flow fields* para hordas en calles siguen fuera de v2.0.

**Población de zombis en distritos densos.** La densidad por chunk sube (tabla §4.3) pero los topes de C9 no: **≤ 150 L0 por servidor, ≤ 60 por zona**. La ciudad parece llena por tres trucos:

1. **Estatuas congeladas.** Un congelado ya no tiene cuerpo en el servidor (ARQ §10.7). En el cliente, en vez de ocupar una de las 48 vistas esqueléticas, se dibuja como **instancia de MultiMesh** de 4–6 **poses congeladas horneadas** por variante (mallas estáticas con la malla `Ice`). Al despertar se cambia por una vista esquelética con `Zom_Wake`. Red: solo `ENTER` con bandera de congelado, **0 B/s** después. Presupuesto: ≤ 300 estatuas visibles en 6–12 *draw calls*. Encaja con el pilar 2 («un campo de minas dormido»).
2. **Atrapados en coches** (Gran Atasco, atascos urbanos): zombis con cinturón que golpean las ventanillas; sin navegación (animación en bucle), solo salen si se abre la puerta o se rompe el cristal (ruido 20 m). Mismo coste que una estatua.
3. **Hordas L2 por el grafo de calles** del generador (el M9b ya prevé hordas por el grafo de carreteras).

**Persistencia.** SQLite (M5) usa las claves de chunk de 96² desde el principio; `world_meta` guarda `world_version = 2` y `city_version`. Cambiar el generador de ciudad cambia `lot_id` y `wid` ⇒ migración explícita; por eso los datos de ciudad se versionan y se congelan por hito.

**Red.** Interés 3 × 3 chunks, igual. Nuevo filtro **vertical**: dentro de una torre, un peer solo recibe zombis y objetos a |Δy| ≤ 9 m (3 plantas) de él salvo que estén al exterior; evita enviar la población de 30 plantas que comparten chunk.

### 4.5 Cómo se genera la ciudad

**Comparativa**

| Criterio | (a) Generador de manzanas y parcelas + kit modular + rascacielos CC0 | (b) Manzanas héroe a mano | **(c) Híbrido (recomendado)** |
|---|---|---|---|
| Cobertura (≈ 1 500–2 500 edificios) | Alta | Inviable (R5 ya es «alta» para 130 edificios en Valdenieve) | Alta: el generador cubre el 85–90 % |
| Hitos y memoria del lugar | Baja: ciudad «igual en todas partes» | Máxima | ≈ 14 bloques héroe + trazado fijo (no depende de la semilla) |
| Contrato de arte (C1, C2, C8: frente −Y, color de vértice, grupos de corte, `Spawn_*`, colisión `Col*`) | Color de vértice y escala: resueltos por `winterize` (doc 07). **Sin resolver**: volumen cerrado, losas por planta, grupos de plantas, anclas, interiores | Cumplido | Cumplido: familias por gramática (bpy) para lo enterable; torres CC0 winterizadas + etapa «listo para corte» para las no enterables |
| Legibilidad con el corte urbano | Mala sin la etapa «listo para corte» (carcasas abiertas, sin forjados) | Buena | Buena: el contrato se fija en W0 |
| Determinismo | Bueno si es función pura; frágil entre versiones | Trivial | Trivial: trazado horneado + vestido por semilla |
| Coste de producción | Bajo al principio, alto al pulir | Muy alto | Medio: herramienta + 6 familias + 14 héroes |
| Riesgo | Ciudad sosa | No se termina | Ritmo de producción de interiores (se mide en C1) |

**Tubería recomendada**

1. **Distritos** (`data/world/city/districts.json`): polígonos de cada distrito, dibujados por Fable sobre el ASCII de §4.2, con sus reglas.
2. **Herramienta offline** `tools/gen_city.gd` (Godot *headless*, como `gen_macro_map.gd`): calles por distrito → manzanas → parcelas → arquetipo, altura, estilo, paleta, uso de planta baja, enterable, reservas de bloques héroe. Salida `data/world/city/altavega_lots.json` (coordenadas en cm enteros) + índice `chunk → lotes` + grafo de calles (para hordas L2, convoyes y quitanieves) + **siluetas de distrito** para miradores. Validaciones: toda parcela con frente a calle, toda puerta conectada a la navmesh de calle, ningún edificio sobre un bloque héroe, `city_version`.
3. **Familias de edificios** (bpy, Opus): gramática **zócalo + planta tipo + coronación** (Müller et al. 2006, CGA *shape*), exportadas como piezas fusionadas por grupos de corte (C8) con **una losa por planta**, volúmenes cerrados y tabiques con grosor. La torre se apila en tiempo de ejecución: `Podium` (1–3 plantas, enterable) + N × `FloorGroup` (grupos de 4 plantas tipo: `MeshInstance3D` independientes para que el *frustum* descarte los de arriba) + `Crown` + `ShadowProxy` (prisma `SHADOWS_ONLY`). Es una **enmienda a C8**: el generador sigue sin ensamblar módulos en vivo, pero sí **apila plantas ya fusionadas**. Las familias de torres no enterables pueden salir de las torres Kenney winterizadas (doc 07) si `winterize` añade la etapa «listo para corte».
4. **Bloques héroe** (`scenes/world/poi/city/*.tscn`): escenas a mano como los POI de §9.5 de ARQ, con su trazado reservado en `districts.json`.
5. **En tiempo de ejecución**: el `ChunkJob` lee los lotes cuyo centroide cae en el chunk; `BuildingAssembler` instancia la familia; el vestido por semilla (coches, daños, cadáveres, barricadas, botín) sale de `hash64(seed, GEN_CITY, lot_id, …)`.

**Reglas por distrito**

| Distrito | Calles | Manzana / parcela | Alturas (plantas) | Arquetipos | Enterables |
|---|---|---|---|---|---|
| Casco viejo | Orgánicas (Voronoi relajado a lo largo del río), 6–8 m, plazas | Parcelas estrechas de 6–12 m de frente | 3–4 | Casa de piedra/revoco, soportales, iglesia | 25 % |
| Ensanche | Cuadrícula alineada con los ejes, calles de 16–20 m, **chaflanes** de 12 m | Manzana cerrada de 96 m con patio; 10–16 parcelas de 15–25 m de frente | 5–8 | Edificio de ensanche (balcones de hierro, ático), bajos comerciales de 4 m | 12 % (40 % de los bajos, 10 % de los pisos) |
| Las Torres | Supermanzanas de 112 × 80 m, calles de 20 m, Gran Vía de 30 m | 1–4 parcelas; zócalo + torre | 12–45 | Torre de cristal, torre de hormigón, torre hito | Vestíbulo + 2 plantas en el 30 %; **2 torres héroe** con escalera, 4–6 plantas amuebladas y azotea |
| Barriada | Bloques abiertos en parque | Bloques lineales de 10–12 × 40–60 m | 8–14 | Bloque de ladrillo | 10 % |
| Suburbios | Anillos y fondos de saco | Parcelas de 400–700 m² (OBB, doc 01 §5.1) | 1–2 | Plantillas de casa de M6a/M9a + 4 chalets | 45 % |
| Polígono / puerto | Viales de servicio, muelles | 2 000–20 000 m² | 1–3 (naves de 8–12 m) | Nave, taller, concesionario, silo, almacén | 50 % (interiores grandes, baratos) |

**Familias de torres** (6 × 3 paletas × 2–3 plantas tipo ≈ 30 variantes): torre de cristal (oficinas, 20–40 plantas, muro cortina en bandas), torre de hormigón de los 70 (12–24, bandas de balcón, depósitos en azotea), bloque de ladrillo (8–14, barriada), edificio de ensanche (5–8, balcones, chaflán), casa del casco viejo (3–4, teja), **torre hito** («Torre Albo», 45 plantas, coronación escalonada con helipuerto; héroe).

**Bloques héroe (14)**: Control del Puerto, Puente de Hierro, Catedral y plaza mayor, Torre de Telecomunicaciones, Torre Albo, Hospital Provincial, Jefatura de Policía, Centro Comercial, Estación Central, Estadio (campo de refugiados), Presa del Cierzo, Central Térmica, Puerto fluvial (dársena), Base aérea. Cada uno cuenta una historia con rastros (§5.2).

**Estimación de producción (arte)**

| Hito | Arte (Opus) | Tamaño |
|---|---|---|
| C1 | Kit urbano (≈ 120 piezas: muro cortina, bandas de balcón, fachadas de ensanche, escaparates de 4 m, persianas metálicas, toldos, núcleo de escalera, hueco de ascensor, vestíbulo), 4 familias × 5 variantes, 20 sets de interior (piso, oficina, 8 tipos de tienda, vestíbulo, escalera), set de azotea (15 piezas), 30 props de calle (semáforo, quiosco, marquesina, boca de metro cerrada, valla publicitaria, contenedor soterrado, bolardos) | L |
| C2 | 10 POI héroe, set portuario (grúas, silos, gabarras, contenedores), set industrial (depósitos, torres de refrigeración, tuberías), Torre Albo | L |
| C3 | Base aérea (hangares, torre, aviones, helicópteros), estación de esquí (hotel, telesilla, pisanieves), 4 chalets, tren (locomotora, vagones, cisterna) | M–L |

### 4.6 Rendimiento

- **HLOD e impostores del *skyline*: no en juego.** El rayo superior baja 30° (§1): nada alto y lejano entra nunca en pantalla. Solo en **miradores** y menú: la herramienta de ciudad genera una **silueta por distrito** (huellas de parcela extruidas a su altura, fusionadas, ventanas por color de vértice + emisivo según la red eléctrica), ≈ 10 mallas de 5–20 k triángulos, **1 *draw call* cada una**, en una capa que solo activa el modo mirador. Sin impostores octaédricos: una malla low‑poly es más barata y coherente con el estilo.
- ***Occlusion culling*: desactivado en la ciudad.** Los `OccluderInstance3D` no saben nada del corte: un edificio cortado seguiría ocultando (y el motor descartaría) lo que el jugador ve a través de él → zombis y props desapareciendo. Además la cámara alta ve casi todo desde arriba y Forward+ ya tiene pre‑pase de profundidad (doc de Godot). Lo que sí se hace: **ocultar en CPU las plantas por debajo de la del jugador** dentro de su torre y las plantas altas que el *frustum* no ve (gratis con grupos de plantas).
- **Grupos de plantas + proxy de sombra.** Una torre de 30 plantas son ≈ 8 grupos; en pantalla hay 1–2. Las fachadas de los grupos no proyectan sombra (`cast_shadow = OFF`); lo hace un prisma `SHADOWS_ONLY` de 12–40 triángulos. Así la sombra de 200 m de una torre cuesta una *draw call* por *split*.
- **MultiMesh** para coches de atasco (por chunk × modelo, color por `custom_data`, interacción por índice espacial como los árboles: `scatter_index`), farolas, papeleras, restos, **estatuas congeladas** y bandadas. Las **ventanas no son instancias**: son parte de la fachada (color de vértice) y se encienden en el shader de `window` con un *hash* por celda de ventana en espacio mundo y dos uniformes por instancia (`power`, `occupied`): 0 *draw calls* extra.
- **Luces**: farolas y rótulos emisivos; ≤ 6 luces reales con sombra cerca del jugador (política actual); con la red restaurada, más luces sin sombra en Forward+ (*clustered*); en `compat`, solo emisivo + halo (R7).

Presupuesto de un encuadre del distrito financiero (zoom 24 m, 1080p, Forward+):

| Elemento | *Draw calls* |
|---|---|
| Terreno y cintas de calle | 20–40 |
| Edificios (10–20 visibles × zócalo 6–10 superficies + 1–2 grupos de planta) | 150–300 |
| Sombras (2 *splits*): proxies de torre, zócalos, props con sombra | 80–160 |
| Coches y props en MultiMesh | 30–60 |
| Props únicos (farolas, señales, contenedores interactivos) | 80–150 |
| Estatuas congeladas | 6–12 |
| Personajes (4 jugadores + ≤ 30 zombis + ≤ 8 NPC) + siluetas | 90–140 |
| Pájaros, partículas, UI | 15–30 |
| **Total** | **≈ 470–890 → presupuesto ≤ 1 000 típico / ≤ 1 500 máx.** (`compat`: ≤ 700) |

---

## 5. Mundo vivo: un post‑apocalipsis habitado

### 5.1 Principios

1. **Rastros antes que actores.** El 90 % de la «vida» es escenografía por semilla que cuenta lo que pasó (el éxodo, la cuarentena, los que resistieron). Coste de red cero; coste de CPU casi cero.
2. **La vida ambiental delata.** Pájaros, perros y ratas no son decorado: reaccionan a jugadores y zombis y avisan de lo que la cámara no ve.
3. **La vida dinámica es escasa, ruidosa y persistente.** Pocos actores humanos, en el servidor, con LOD y con consecuencias (un convoy que pasa arrastra una horda; un campamento saqueado queda saqueado).
4. **Sin tráfico civil vivo.** Todo lo que se mueve con motor es de alguien: jugadores, militares, saqueadores, el quitanieves de los supervivientes.
5. **Enmienda necesaria del PLAN §10, no‑objetivo 2** («NPC supervivientes con moral, comercio o diálogos»): pasa a **«NPC sin moral ni diálogos ramificados»**. Sí hay comercio por trueque, frases cortas (*barks*), actitud por facción y rutina; no hay árboles de diálogo ni compañeros reclutables en v2.0.

### 5.2 Vida estática (por semilla; persiste como delta cuando se toca)

| Elemento | Cómo se genera | Valor de juego | Red | Coste | Hito |
|---|---|---|---|---|---|
| **Atascos y coches estrellados** (A‑14, N‑140, rondas, calles) | Carriles de la *spline* con densidad por «cuello de botella» (controles, enlaces, accidentes en cadena); tipos por distribución; puertas abiertas, maletas, huellas; **1 de cada 8 funcional**; **10 % con zombi atrapado** | Botín (gasolina, llaves, maletas), cobertura, laberinto para hordas, elección de ruta | 0 (+ delta al saquear o mover) | MultiMesh por chunk × modelo; interacción por índice espacial (como los árboles) | M7 (N‑140), C1 (calles), C2 (Gran Atasco) |
| Autobuses, ambulancias, patrullas, cisternas, tren nevado | Restos héroe con contenedor | Medicina (ambulancia), armas (patrulla), combustible (cisterna: **vertido**, §6.8) | 0 | Props | C2–C3 |
| **Controles y barricadas** (militares y vecinales) | En los bordes de distrito, puentes y la entrada del puerto de montaña | Cuellos de botella, historia de la cuarentena, botín militar | 0 | Props | C1 |
| **Campamentos y tiendas** | Estadio (campo de refugiados), parques, bajo los puentes, dársena | Botín, notas, cadáveres; algunos habitados (§5.4) | 0 | Props | C2 |
| **Grafitis, carteles, vallas publicitarias** | Mensajes con dirección («ZONA SEGURA → ESTADIO», «NO ENTRAR: INFECTADOS», «MARÍA, ESTAMOS EN LA CATEDRAL»), recuentos de días. **Los grandes** (azoteas, nieve, calzada: «SOS», flechas) son **letras de malla** sin textura; los carteles y rótulos pequeños usan **un atlas `signage`** (nueva excepción a C2) | Navegación sin minimapa, objetivos secundarios del tablón, historia | 0 | 1 material más | C1 |
| **Ventanas encendidas por generador** | 1–2 % de los edificios con generador en marcha y un día de agotamiento por semilla | Señal de supervivientes o de botín (el generador y su combustible); el generador hace **30 m de ruido** | ON_CHANGE por edificio (estado + día fin) | Shader de `window` (§4.6) | V1 |
| **Columnas de humo** | Coches y edificios ardiendo, chimeneas de campamentos, fuegos de petróleo | Pista de navegación (miradores, mapa), señal de NPC | 0 / evento | Partículas GPU | V1 |
| **Tendederos, macetas, persianas a media altura** | Edificios ocupados por NPC | «Aquí vive alguien» leído desde arriba | 0 | Props | V1–V2 |
| **Escenas de rastro** | ≈ 40 plantillas colocadas por el generador en parcelas (la última cena, el coche con la puerta abierta y huellas hacia una casa, el francotirador de la azotea, la barricada que no aguantó) | Historia ambiental, notas, botín con sentido | 0 | Props | V1 |
| Cadáveres, bolsas, fosas, triaje | Alrededor de hospitales, controles y el estadio | Historia, botín, cuervos (§5.3) | 0 | Props | C1–C2 |

### 5.3 Vida ambiental (cliente; la que afecta al juego, con un registro mínimo en el servidor)

| Elemento | Comportamiento | Valor de juego | Red | Coste | Hito |
|---|---|---|---|---|---|
| **Cuervos y palomas** | Bandadas posadas en tejados, farolas, coches y cadáveres; despegan si un actor (jugador, zombi o NPC) pasa a 8–12 m o hay un ruido cerca; los cuervos **rondan en círculo sobre cadáveres** | **Delatan movimiento** fuera de la vista («se han levantado los cuervos en esa calle»); marcan cadáveres y mochilas. El despegue emite un `SoundEvent` de 12 m (el ruido como préstamo, en pequeño) | Registro de bandada en el servidor (≤ 24 por zona: posada/vuela/aterriza) + evento `FLOCK_SCARE` (≈ 10 B) | *Boids* en MultiMesh, ≤ 200 pájaros, ≈ 0.2 ms CPU cliente | V1 |
| **Perros callejeros** | Manadas de 3–6: carroñeros de día, hostiles de noche o con hambre; pelean con zombis | Amenaza y alarma: **ladrar = ruido 40 m** | Como zombis (9 B por instantánea) | `ZombieSystem` (tipo animal) | V2 (necesita el esqueleto cuadrúpedo de M9b) |
| Ciervos y jabalíes en las afueras | Como hoy | Caza | Como hoy | — | M9b |
| **Ratas** | Enjambres de 20–40 en sótanos, junto a cadáveres y comida; huyen de la luz | Indican comida o cadáveres; asustan (sin daño) | 0 | MultiMesh + dirección simple | V1 |
| **Restos al viento** | Papeles, bolsas y remolinos de nieve alineados con `wind_yaw` | **Lectura del viento** (olfato del acechador, humo, polvo de un alud) | 0 (el viento ya viaja en `WorldState`) | Partículas GPU | V1 |
| Neón y semáforos | Parpadeo del neón, semáforos en ámbar intermitente | Señal de sector con corriente (§6.11) | 0 | Shader emisivo | V1 / E2 |
| Paisaje sonoro urbano | Viento silbando entre torres, rótulos que crujen, lonas, alarmas y disparos lejanos | Orientación y tensión | Los lejanos los emite el director del mundo | Audio | V1 |

### 5.4 Vida dinámica (servidor)

| Elemento | Qué hace | Valor de juego | Red | Coste IA/CPU | Hito |
|---|---|---|---|---|---|
| **Comerciantes** | 3–4 campamentos fijos (tribuna del estadio, gabarra de la dársena, hotel de la estación de esquí, iglesia de Santa María) con un comerciante y 2–4 guardias; **trueque** (sin moneda: valor por objeto y reputación por servidor); horarios anunciados por radio; caravanas entre campamentos (sistema de convoyes) | Sumidero y fuente de botín, munición, combustible y planos; objetivos secundarios (encargos) | Como zombis + RPC de trueque | Guardias quietos; L0 solo cerca | V2 |
| **Saqueadores** | Grupos de 3–6 con base en edificios fortificados (control caído, gasolinera, una planta de torre); patrullan de noche (L2 por el grafo de calles); **emboscadas** en carreteras (barricada + restos); atacan bases con mucho «calor de ruido»; se retiran al 50 % de bajas | Enemigo humano con armas de fuego: **sus disparos atraen zombis** (peleas emergentes que se oyen de lejos); botín de armas | Como zombis + 2 B (apuntado) + eventos de disparo | Cerebro humano: coberturas precalculadas (`Spawn_Cover` del kit y alrededor de restos), disparar, huir; **≤ 12 humanos L0 por servidor** (≈ 3 zombis L0 cada uno: el tope de zombis L0 baja a 130 cuando hay humanos) | V2 |
| **Convoyes militares** | 2–4 vehículos por el grafo de carreteras: lejos, un punto L2; a < 150 m de un jugador, vehículos **cinemáticos sobre la *spline*** (no física); se paran ante el atasco y abren paso con una pala o se desvían; los soldados bajan en controles | Actitud por opción de servidor (`military_attitude`: `neutral` u `hostile`); disparan a zombis (ruido que mueve hordas), sueltan cajas; el convoy de evacuación de M10 es este sistema | ≈ 0.9 kB/s con 3 vehículos en interés; nada de lejos (solo un evento de sonido) | 1 entidad L2; cuerpos solo cerca | V2 |
| **Helicópteros** | Patrullas sobre la ciudad (foco de noche), lanzamientos, **accidentes** (restos con botín militar, como los de DayZ) | Desde la cámara alta se ven por su **sombra**, el **remolino de nieve** y el **cono del foco**, y se oyen. El meta‑evento del GDD §6.4 (mueve zombis hacia el más ruidoso) | *Spline* + t0 (≈ 50 B por evento) | Ninguno (ruta determinista) | V2 |
| **Quitanieves de los supervivientes** | Recorre la A‑14 y las rondas cada 2–3 días: baja la nieve de cada tramo (los coches van más rápido), aparta restos (el atasco gana un carril, persistente), deja bermas | Carreteras que cambian; seguirlo es seguro… y ruidoso (70 m): arrastra hordas | Nieve por tramo en `WorldState` (ON_CHANGE) | 1 vehículo cinemático | V2 |
| **Radio** | `RadioSchedule` con canales: **emergencia automática** (Gran Ventisca, olas de frío, tormentas de hielo, red eléctrica), **supervivientes** (horarios de comercio, peticiones de ayuda → tablón), **saqueadores** (amenazas), **militar** (convoyes, lanzamientos, evacuación), estación de números. Fuentes: radio portátil (pilas que el frío agota), del coche, de la base (N3) y la **Torre de Telecomunicaciones** (repararla amplía el alcance a todo el mapa) | Previsión del tiempo y de eventos; objetivos; historia | Id de evento + parámetros | Ninguno | V2 (la parte meteorológica, con E1) |
| **Lanzamientos de suministros** | Pasada de avión (sombra + sonido) → cajas con paracaídas; humo rojo 3 min al tocar suelo; aviso por radio 10 min antes | Botín de nivel alto disputado: el lanzamiento hace 150 m de ruido y el humo atrae zombis y saqueadores | Evento + `wid` del contenedor | Ninguno | V2 |
| **Director del mundo** | Programa eventos por día con pesos por región, clima, día y *gamestage*; enfriamientos; reglas de cortesía (nunca en Gran Ventisca; ≤ 1 evento grande por zona y hora; nunca en los 60 s siguientes a un pico del director de combate). Modelo tipo *Central Economy* de DayZ (`events.xml`: nominal, vida, radio de limpieza) | Un mundo que cambia sin guion | Eventos | Tabla + temporizadores | V2 |

### 5.5 Presupuesto del mundo vivo

| Capa | CPU servidor | CPU cliente | Red por cliente |
|---|---|---|---|
| Estática | 0 (datos) | Instanciación dentro de los 2 ms/frame | 0 (+ deltas) |
| Ambiental | Bandadas: < 0.05 ms/tick | ≤ 0.4 ms/frame (pájaros, ratas, partículas) | ≈ 0.01 kB/s |
| Dinámica | Humanos L0 ≤ 12 (≈ 36 zombis‑equivalente), convoyes y helicópteros como L2 | Vistas de personaje dentro del tope de 60 esqueletos | ≤ 3 kB/s (humanos ≈ 1, vehículos ≈ 1, eventos y radio ≈ 0.2) |

Con esto la bajada típica sigue en **≤ 15 kB/s** (C11): hoy 4.9 kB/s con ~94 zombis.

---

## 6. Problemas ambientales invernales como sistemas

### 6.0 Arquitectura común: `HazardSystem` (servidor)

| Escala | Estado | Dónde vive | Cómo llega al cliente |
|---|---|---|---|
| Global | Clima (ventisca, *whiteout*, tormenta de hielo, ola de frío, inversión, deshielo), viento, `ice_glaze`, `smog {top_y, density}` | `WorldState` | Cada 5 s + extrapolación (C10); *globals* de shader (`snow_amount`, `ice_glaze`, `wind_vec`) y `Environment` |
| Regional | Sectores de la red eléctrica, mapa de hielo por masa de agua, carga de cada ladera de aludes, nieve por tramo de carretera | Tablas en `WorldState` (ON_CHANGE) | Uniformes por instancia (ventanas, farolas), máscaras |
| Local | Por edificio: tuberías, gas, fuego, carga del tejado, plantas inundadas; vertidos (polígonos); depósitos de alud | `ChunkDelta` (por `wid`) | Instantánea de delta al entrar en interés + eventos |

Reglas de diseño (derivadas de los pilares): todo peligro se **anuncia o se telegrafía** (radio, sonido, ≥ 3 s de aviso), se **lee desde arriba**, tiene **contrajuego** e **interactúa con los zombis**. Los sistemas con tiempo se evalúan **perezosamente** en chunks tibios o hibernados (estado = f(tiempo transcurrido, historial del clima)), nunca con un *tick* global.

Resumen:

| Sistema | Lectura cenital | Juego | Zombis | Vehículos | Co‑op | Hito |
|---|---|---|---|---|---|---|
| Ventisca / *whiteout* | Contraste nulo, sin sombras, solo luces y siluetas; jalones con punta reflectante | Orientarse, refugio | Vista 3 m, acechador ×2 | Faros cortos, carretera invisible | Siluetas de compañeros a 15 m | E1 |
| Tormenta de hielo | Todo brilla, carámbanos, cables combados | Resbalar, puertas heladas, apagones | Resbalan y caen | μ 0.15 | Reparar líneas en pareja | E1 |
| Ola de frío | Escarcha, vaho grande, hielo del río que espesa | Baterías, gasóleo, tuberías | Congelan en 60 s: ciudad de estatuas | Gasóleo gelificado | Calor compartido | E1 |
| Aludes | Ola blanca y nube de polvo | Cortes de carretera, sepultados | Los entierra (limpia población) | Enterrados | Excavar al compañero | E1 |
| Hielo fino (río, ibón) | Colores del hielo, grietas, vapor sobre el agua abierta | Atajos arriesgados | Las hordas lo rompen | > 30 cm para coche | Sacar al compañero | E1 |
| Tuberías → inundación → hielo | Chorros, cascadas heladas, placas brillantes | Suelos resbaladizos, escaleras bloqueadas, agua | Atrapados en hielo | Placas de hielo en calles | Purgar tuberías | E2 |
| Fugas de gas | Nieve fundida y burbujas, siseo, pájaros muertos | Trampas explosivas | Explosión los mata y atrae | Vuelca coches | Fuego amigo de explosivos (C20) | E2 |
| Vertidos | Manchas negras / amarillo‑verdosas | Zonas tóxicas, combustible, barrera de fuego | Evitan la nube química | μ 0.1 sobre hielo | Máscaras | E2 |
| Incendios | Llamas en ventanas, resplandor en la niebla | Calor, luz, ruinas | Despiertan congelados a 30 m | Arden | Extintores | E2 |
| Inversión / *smog* | Capa ocre hasta `top_y`; cielo limpio por encima | Subir a una torre = ver y abrigarse | Vista reducida | — | Tos = ruido | E2 |
| Red eléctrica | Sectores iluminados de noche, resplandor | Ascensores, calefacción, bombas… y alarmas | Luz atrae, calor despierta | Cargar baterías | Repartir tareas | E2 |
| Carga de nieve → colapso | Tejados que se combean, polvo que cae | Retirar nieve, peligro en naves | Los entierra | Hangares | Rescate | E2 |
| Congelación | Muñeco corporal, manos blancas/azules | Puntería, velocidad | — | Volante inestable | Calentarse juntos | E1 (M8 hace la base) |

### 6.1 Ventisca y *whiteout*

- **Qué**: la ventisca actual (GDD §4.5: visibilidad 6 m, 2–4 min) gana una variante **whiteout** en terreno abierto (campo, río, pista, laderas `%`) y durante la Gran Ventisca: visibilidad **3 m**, suelo y cielo indistinguibles.
- **Visual**: el shader de terreno baja el contraste a casi cero, las sombras direccionales se apagan, la niebla lo llena; solo se leen las luces, las siluetas (§3.5) y los **jalones** de carretera cada 25 m con punta reflectante (emisivo), que por fin tienen función. En calles, el viento se **canaliza** (×1.3 a lo largo del eje de la calle, ×0.5 a sotavento de los edificios): se elige por dónde andar.
- **Juego**: *pings* visibles a 25 m; brújula con ruido; el ventisquero a sotavento es refugio (−viento). Viento efectivo en el termómetro por calle.
- **Zombis**: vista 3 m, ruido ×0.6 (como ventisca); acechador ×2 de probabilidad en terreno abierto.
- **Vehículos**: los faros largos deslumbran (retrodispersión: se ve menos); la carretera solo se sigue por los jalones.
- **Co‑op**: siluetas de compañeros hasta 15 m; alejarse > 10 m llama al acechador (GDD).
- **Técnica**: `weather.whiteout` + máscara de «abierto» del macro; cliente: `Environment` y *globals*. **E1**.

### 6.2 Tormenta de hielo (lluvia engelante)

- **Qué**: evento raro (1 cada 8–12 días, nunca antes del día 5): 6–10 min reales de lluvia engelante; el **hielo glaseado** dura un día de juego (se va con T > −2 °C y sol). Referencia real: la tormenta de 1998 (hasta 100 mm de hielo, más de 1 000 torres de alta tensión derrumbadas, millones sin luz durante semanas).
- **Visual**: `ice_glaze` global (0–1) sube el especular y baja la rugosidad de todo (brillo azulado), carámbanos en aleros, ramas y cables (MultiMesh precolocado que crece), cables combados, destellos al salir el sol; crujidos.
- **Juego**: calles y aceras con μ 0.15; correr y girar > 60° con 8 %/s de resbalar (caída 1.2 s, ruido 8 m); puertas y maleteros helados (+3 s o palanca); **ramas que caen** (ruido 20 m, 30 de daño si aciertan); la capa exterior se moja (+20 % humedad por minuto a la intemperie); armas +5 % de encasquillamiento.
- **Red eléctrica**: cada sector tiene un 35 % de sufrir **cortes de línea** (apagón, §6.11) y cables caídos que bloquean coches (y electrocutan, 60 de daño + aturdimiento, si el sector tiene corriente). Repararlos: 20 s con herramientas en cada punto marcado.
- **Zombis**: al perseguir o girar, 5 %/s de resbalar y caer 1.5 s; los congelados quedan **encapsulados** (contundente ×2).
- **Vehículos**: μ 0.15 sin cadenas (0.35 con cadenas).
- **Co‑op**: reparar una línea exige que alguien vigile (ruido de herramientas 10 m). **E1**.

### 6.3 Ola de frío extremo

- **Qué**: anunciada por radio 24 h antes; −12 °C adicionales durante 1–2 días de juego.
- **Visual**: escarcha en los bordes de pantalla y en los cristales, vaho más grande, árboles que crujen (ruido 25 m aleatorio), río que se vuelve blanco (hielo grueso).
- **Juego**: baterías −2 %/h extra; el **gasóleo gelifica** por debajo de −20 °C de ambiente (camiones y el quitanieves no arrancan sin aditivo o sin calentar el depósito 60 s con soplete); tuberías congeladas en edificios sin calefacción (preparan el §6.6); consumo de leña de la base ×1.5. **Oportunidad**: el hielo del río pasa a grueso en un día: se abren atajos.
- **Zombis**: un caminante sin estímulo se congela en **60 s** (no 300 s): la ciudad se llena de estatuas (§4.4); son frágiles (contundente ×2). Ventana de sigilo… hasta que un motor o una hoguera los despierta.
- **Vehículos**: arranque en frío −20 %; calefacción imprescindible.
- **Co‑op**: +5 °C por persona extra en un espacio cerrado (coche, tienda), hasta +15. **E1**.

### 6.4 Aludes

- **Qué**: en las laderas `%` (estación de esquí, desfiladero de Peña Roya, Sierra del Cierzo). Cada ladera tiene zona de salida, trayectoria y zona de depósito autoradas en el macro. Las pendientes de 30–45° concentran casi todos los aludes (el 38° es el ángulo más frecuente): el macro marca como `%` solo esas pendientes.
- **Carga** `L` (0–1) por ladera: ventisca +0.25, Gran Ventisca +0.6, nevada diaria +0.05, viento que carga la cara de sotavento ×1.5, asentamiento −0.1/día, deshielo +0.2 (nieve húmeda).
- **Disparadores** con `L > 0.5`: explosión a < 150 m (100 %), disparo con radio de ruido ≥ 80 m a < 100 m (30 % × L), vehículo o motonieve cruzando la zona de salida (15 % × L), jugador a pie (5 % × L); natural por hora 2 % × (L − 0.6)/0.4.
- **Aviso** (telegrafiado): «uuumpf» y grietas 1 s antes; cornisas visibles; la radio de emergencia da el riesgo por zona.
- **Visual**: una ola blanca que cruza la pantalla + nube de polvo de nieve (partículas) + sacudida; el depósito queda como montones de nieve profunda.
- **Juego**: corta la N‑140 en el desfiladero (quitanieves o 3 min con dos palas); **sepultados**: 30 s para salir solo, 5 s si un compañero excava; Calor −2/s mientras. **Herramienta**: provocar un alud con una bomba de tubo para cerrar el paso a una horda.
- **Zombis**: los que pilla quedan enterrados (salen de la población: limpieza real, persistente).
- **Vehículos**: empujados y enterrados (inutilizados hasta desenterrarlos, 60 s de pala).
- **Técnica**: evento de servidor `(ladera, semilla, t0, severidad)`; el depósito es geometría (mallas convexas + colisión) guardada en `ChunkDelta`, **no** un cambio del campo de alturas (regenerar `HeightMapShape3D` es caro); rehorneado de la navmesh del chunk con el enfriamiento de 2 s. **E1**.

### 6.5 Hielo fino en ríos y lagos

- **Qué**: M8 trae el hielo fino al Lago de las Ánimas; E1 lo extiende al **río Albo**, la dársena y el ibón. Mapa de grosor por masa de agua (semilla + clima): más fino en el centro del cauce, junto a pilas de puentes, en la salida de la presa, en el canal del puerto y **200 m aguas abajo de la central térmica si funciona** (agua templada: agua abierta humeante).
- **Umbrales** (orientativos reales, redondeados): a pie ≥ 10 cm, motonieve ≥ 20 cm, coche ≥ 30 cm. Clases: grueso (≥ 30 cm: coches), medio (20–30: a pie y motonieve), fino (10–20: solo a pie; cruje; 1 %/s de romperse con alguien quieto encima, ×3 corriendo, ×5 con más de una persona en la misma celda), agua abierta (< 10).
- **Visual**: color por clase (blanco‑azul / gris / gris oscuro con grietas / negro con vapor), grietas como mallas, crujidos.
- **Juego**: el río como **atajo** para evitar puentes con controles o hordas; una ola de frío lo abre, un deshielo lo cierra.
- **Zombis**: > 3 zombis L0 en la misma celda de 4 m sobre hielo fino lo rompen (arma ambiental ya prevista para el hinchado y el coloso).
- **Vehículos**: coches solo sobre grueso; motonieve sobre medio.
- **Co‑op**: sacar a un compañero del agua (mantener E 3 s tumbado en el borde); si no, 20 s para salir solo; después hace falta fuego en < 2 min. **E1**.

### 6.6 Tuberías congeladas → inundaciones y placas de hielo

- **Qué**: estado por edificio `pipes = ok | frozen | burst | drained`. Sin calefacción + ola de frío → `frozen`. Al **calentar el edificio** (estufa, generador, red) o con el deshielo, 70 % de **reventón**. Referencia real: la helada de Texas de 2021 (tuberías reventadas en ≈ 16 % de los hogares encuestados).
- **Visual**: chorros de agua en paredes (partículas, 10 min), **placas de hielo** brillantes en pasillos a los 30 min si no hay calor, **cascadas heladas** que bajan por la escalera, carámbanos en ventanas; en la calle, una tubería general rota hace un géiser que deja una pista de hielo de 20–40 m.
- **Juego**: suelos interiores con μ 0.15 (resbalar al correr); escalera bloqueada por hielo (20 s con piqueta o 60 s de soplete); sótanos inundados de agua a 0 °C (entrar = ropa 100 % mojada); el chorro enmascara pasos (10 m de ruido constante: sigilo); agua para la cantimplora. **Tarea de base**: «purgar las tuberías» (30 s por planta) antes de encender la calefacción del edificio reclamado.
- **Zombis**: los de una planta inundada y helada quedan **atrapados en el hielo** (muerden si te acercas; se ejecutan o se esquivan).
- **Vehículos**: placas de hielo en calles (μ 0.12).
- **Técnica**: estado en `ChunkDelta`; volúmenes de superficie `ICE` (`Area3D`) para la fricción. **E2**.

### 6.7 Fugas de gas y explosiones

- **Qué**: red de gas por distrito; 3 % de los edificios de ciudad con fuga (semilla) + fugas nuevas tras colapsos, aludes urbanos, tormentas de hielo o incendios. Concentración `c` (0–1) por edificio: sube con puertas y ventanas cerradas, baja con ventanas rotas.
- **Lectura**: siseo; aviso «Huele a gas» con `c > 0.2`; pájaros y ratas muertos; llama piloto que parpadea; en la calle, **nieve fundida en manchas y burbujas** sobre la fuga; icono de olor.
- **Juego**: disparar, una bengala, una antorcha, un mechero o **las chispas al volver la corriente** (§6.11) con `c > 0.3` ⇒ explosión de radio 4 + 8·c m, 150·c de daño, fuego, ventanas reventadas (el edificio pierde aislamiento), ruido 200 m. **Trampa**: atraer una horda a un portal lleno de gas y lanzar una bengala.
- **Zombis**: la explosión mata y, con su ruido, atrae a los demás.
- **Vehículos**: vuelca coches cercanos.
- **Co‑op**: el fuego amigo de explosivos sigue C20 (×0.5 en `reduced`).
- **Técnica**: `GasCell` por edificio en el servidor; comprobación de ignición en los eventos de fuego/disparo dentro del edificio. **E2**.

### 6.8 Vertidos químicos y de petróleo

- **Fuentes**: parque de combustibles, Químicas del Albo, camiones cisterna del Gran Atasco, vagones cisterna descarrilados, gabarras de la dársena, la base aérea (queroseno).
- **Tipos**: **petróleo/combustible** (mancha negra‑marrón que se extiende pendiente abajo; inflamable; sobre hielo μ 0.1); **químico** (mancha amarillo‑verdosa; nube tóxica más pesada que el aire que se acumula en sótanos, pasos inferiores y el puerto: 1–3 PV/s sin máscara y cono de visión −30 %).
- **Visual**: máscara de manchas en espacio mundo en el shader del terreno (el mismo patrón que el mapa de huellas, pero con polígonos que manda el servidor), vapor, animales muertos. La **nieve nueva tapa la mancha pero no el peligro**: el olor sigue.
- **Juego**: combustible (sifonar la cisterna, con riesgo de vertido); **barrera de fuego** (encender el vertido corta el paso a una horda 90 s); zonas tóxicas como puertas de botín (hace falta máscara de gas: objeto nuevo).
- **Zombis**: rodean las nubes químicas (rutas seguras para quien lleva máscara); arden en el petróleo.
- **Técnica**: vertidos estáticos por semilla + dinámicos (disparar a un depósito); extensión por un grafo de celdas de 8 m cuesta abajo, en el servidor; replicados como polígonos. **E2**.

### 6.9 Incendios

- **Fuentes**: explosiones, molotov, bengalas, petróleo ardiendo, estufas de supervivientes, **cortocircuitos al volver la corriente** (5 % de los edificios dañados del sector).
- **Modelo**: por edificio y planta: sube una planta cada 60 s; pasa a edificios **adosados** (manzanas del ensanche) en 3–5 min; la nieve del tejado lo frena; arde 10–20 min y queda en **ruina** (variante quemada: color de vértice ennegrecido, tejado hundido; botín perdido). Opción de servidor `fire_spread = off | buildings | full` (hoy `off`): en ciudad se propone `buildings`.
- **Visual**: llamas en las ventanas (emisivo + partículas), **resplandor naranja en la niebla** (la cámara no ve la columna de humo lejana, pero sí el color de la niebla de noche en esa dirección), ceniza que cae, columna de humo en los miradores y en el mapa.
- **Juego**: **calor** (+40 °C a ≤ 8 m: salva vidas en una ola de frío), luz, ruina. Extintores (10 s de chorro), nieve a paladas para fuegos pequeños.
- **Zombis**: la luz atrae a 60 m de noche; **el calor despierta a los congelados a 30 m**: un incendio en un distrito helado crea una horda.
- **Técnica**: `FireSystem` a 1 Hz solo en chunks calientes; en tibios/hibernados se resuelve por tiempo al despertar; estado en `ChunkDelta`. **E2**.

### 6.10 Inversión térmica y *smog*

- **Qué**: tras la Gran Ventisca o con calma anticiclónica (1 cada 7–10 días, 1–2 días de juego), el valle del Albo (ciudad, puerto, polígono, suburbios) queda bajo una **bolsa de aire frío** con techo `top_y` a 35–60 m sobre el río. Es el fenómeno de Salt Lake City o del Londres de 1952 a escala de juego.
- **Visual**: niebla de **altura** (`Environment.fog_height` / `fog_height_density`, en Forward+ y Compatibility) de color ocre‑gris, sol pálido (energía ×0.5, sombras blandas), colores lavados. Por encima del techo: cielo limpio y sol.
- **Juego**: visibilidad de 18 m de día; −4 °C bajo la capa y **+4 °C por encima**: subir a una azotea o a Monte Cierzo = ver (mirador) y **abrigarse**. Exposición → **tos** cada 20–40 s (ruido 8 m: rompe el sigilo) salvo mascarilla. La central térmica en marcha (§6.11) y los incendios **espesan** la capa: la luz tiene un precio.
- **Zombis**: la misma vista reducida; el olfato no cambia.
- **Técnica**: `WorldState.inversion {active, top_y, density}`; el servidor aplica `T(y)` en `thermal.gd`. **E2**.

### 6.11 Red eléctrica por sectores

- **Qué**: ≈ 10 sectores (casco viejo, Las Torres, ensanche norte y sur, barriada, puerto, polígono, suburbios norte y sur; la base aérea y la estación de esquí con generadores propios; Valdenieve con una línea rural). Fuentes: **central hidroeléctrica** de la presa del Cierzo (reparar: 3 piezas + limpiar el hielo de la toma; alimenta 3 sectores) y **central térmica** (necesita gasóleo, espesa el *smog*; 4 sectores). Las subestaciones reparten; los jugadores eligen **qué sectores** reciben corriente (capacidad limitada). Además, generadores por edificio (ranura N3 de la base, 30 m de ruido).
- **Con corriente en un sector**: farolas y semáforos en ámbar, **ventanas que se encienden** (muchos interruptores quedaron encendidos), neón; **ascensores** de las torres (subir a una azotea en segundos en vez de 30 plantas de escalera con aguante), calefacción eléctrica (+10 °C en interiores), bombas de gasolinera, cargadores, alcance de la radio.
- **El precio**: 30 % de **alarmas** (tiendas, coches, casas: 150 m de ruido 60 s), **tuberías que revientan** al calentarse (§6.6), **congelados que se despiertan** en interiores calientes, **cortocircuitos e incendios** (§6.9), chispas que prenden el gas (§6.7), luz que atrae de noche.
- **Visual**: de noche, bloques iluminados frente a bloques negros; resplandor de los sectores con luz en la niebla; chispas en líneas rotas; el mapa de papel marca los sectores con luz.
- **Meta‑objetivo** propuesto: «**Devolver la luz a Altavega**» (encaja con la torre de radio y el quitanieves del GDD §11.3 como tercera línea de progreso).
- **Técnica**: `PowerGrid` en el servidor (fuentes, combustible, interruptores por sector, cortes de línea); réplica ON_CHANGE (≈ 16 B); los edificios con generador en `ChunkDelta`; el cliente enciende ventanas y farolas por uniformes de instancia. **E2** (los generadores sueltos, en V1).

### 6.12 Carga de nieve y colapso de tejados

- **Qué**: los techos planos de gran luz (naves, centro comercial, estadio, hangares, polideportivos) tienen una capacidad de 150–300 kg/m²; la nieve pesa de 50 kg/m³ (recién caída) a 200 (asentada) y 400 (húmeda). La carga = espesor × densidad: nevada diaria ≈ 5 cm, ventisca +10, Gran Ventisca +40, ventisquero a sotavento ×1.5, glaseado +20 kg/m², deshielo ×2 de densidad. Los fallos por nieve húmeda son los más frecuentes en la realidad.
- **Aviso** al 80 %: crujidos, polvo y nieve que caen dentro, **flecha visible del techo** (el shader dobla el centro del vano hasta 0.6 m), grietas.
- **Colapso** al 100 %: tejado y última planta caen dentro: escombro y nieve; zombis dentro muertos o enterrados; 50 % de los contenedores de la zona destruidos; jugadores dentro 40–80 de daño y sepultados (rescate co‑op); ruido 80 m.
- **Juego**: tarea de base (**quitar nieve del tejado**, 1 m² cada 2 s, o apuntalar); peligro en naves y hangares tras la Gran Ventisca. Los tejados inclinados sueltan la nieve de golpe sobre la acera (ruido 10 m) y dejan caer carámbanos.
- **Técnica**: carga calculada perezosamente desde el historial del clima (determinista); colapso por evento en chunks calientes o por tiempo al despertar; persistido. **E2**.

### 6.13 Congelación

- **Qué**: amplía la congelación de M8 (hoy: −10 % de salud máxima tras 60 s a Calor 0) a **partes** (manos, pies, cara) y **fases**: `Entumecido` (reversible: balanceo de puntería +30 %, recarga +20 %) → `Congelación superficial` (−20 % precisión en manos, −10 % velocidad en pies; cura: recalentar 60 s junto al calor + vendas) → `Congelación profunda` (−10 % salud máxima permanente por parte; kit de cirugía).
- **Acumula** con la parte sin aislar, Calor < 30, humedad (×2) y viento > 15; **tocar metal con las manos desnudas por debajo de −20 °C** (escaleras de torre, herramientas) da entumecimiento al instante.
- **Visual**: muñeco corporal en el HUD con partes en blanco/azul/negro; manos del personaje más blancas (uniforme por instancia); tiritar con las manos.
- **Vehículos**: volante inestable con manos entumecidas.
- **Co‑op**: calentarse las manos juntos junto al fuego (recalentar ×1.5).
- **Técnica**: `thermal.gd` por parte; espejo en `StatsSync`. **E1** (sobre la base de M8).

---

## 7. Presupuestos

### 7.1 Cliente (Forward+, 1080p, GPU tipo GTX 1060 / RX 580; objetivo interno 12 ms)

| Recurso | Valle (hoy / PLAN) | Ciudad (propuesta) | Nota |
|---|---|---|---|
| *Draw calls* | ≤ 800 | **≤ 1 000 típico / ≤ 1 500 máx.** | Desglose en §4.6 |
| Triángulos | ≤ 1.5 M | ≤ 1.5 M (típico 0.6–1 M) | Grupos de plantas fuera del *frustum* no cuentan |
| Corte urbano (GPU) | — | ≤ 0.3 ms | W0 lo mide en escritorio |
| Esqueletos animados | ≤ 60 | ≤ 60 (jugadores + zombis + NPC) | Estatuas y atrapados **no** cuentan |
| Estatuas congeladas | — | ≤ 300 instancias, 6–12 DC | MultiMesh |
| Pájaros | — | ≤ 200, 1–3 DC | *Boids* en MultiMesh |
| Luces con sombra | ≤ 6 | ≤ 6 | Farolas: emisivo; con red, luces sin sombra en Forward+ |
| Partículas | ≤ 12 000 GPU | ≤ 12 000 GPU | Ventisca + humo + fuego comparten presupuesto |
| GDScript `_process` | ≤ 3 ms | ≤ 3 ms (`CutManager` ≤ 0.05 ms; vida ambiental ≤ 0.4 ms) | |
| Streaming | ≤ 2 ms/frame | ≤ 2 ms/frame | Familias precargadas como `PackedScene` |
| Memoria | ≤ 2.5 GB | ≤ 2.5 GB (+200–400 MB de mallas urbanas compartidas) | |

Preset `compat`: ≤ 700 DC, corte y siluetas activos (no usan stencil), niebla de altura exponencial para el *smog*, sin volumétrica; farolas solo emisivas (R7).

### 7.2 Servidor dedicado (Linux x86_64, 2 vCPU, 4 GB, 4 jugadores)

| Recurso | Presupuesto |
|---|---|
| Tick | p50 ≤ **8 ms** con 150 L0 (o 130 L0 + 12 humanos) + 2 convoyes + `HazardSystem` |
| Horneado de navmesh | Calle 20–40 ms/chunk; planta de edificio 2–8 ms; ≤ 12 teselas/s; todo en `WorkerThreadPool` |
| `HazardSystem` | ≤ 0.5 ms/tick (fuego 1 Hz solo en chunks calientes; el resto perezoso) |
| Memoria | RSS ≤ **1.2 GB** con 4 jugadores en 4 cuadrantes de ciudad |
| Persistencia | Lote SQLite ≤ 5 ms cada 60 s |

### 7.3 Red (por cliente, bajada)

| Flujo | Típico | Pico |
|---|---|---|
| Jugadores (4) | 3.5 kB/s | 4 kB/s |
| Zombis (bandas) | 5–8 kB/s | 12 kB/s |
| Humanos NPC | ≤ 1 kB/s | 2 kB/s |
| Vehículos y convoyes | ≤ 1 kB/s | 2 kB/s |
| Eventos (mundo, peligros, radio, bandadas) | ≤ 0.5 kB/s | 3 kB/s (explosión + colapso + alud) |
| `WorldState` + red eléctrica | 0.1 kB/s | — |
| **Total** | **≤ 15 kB/s** | **≤ 30 kB/s** (C11 sin cambios) |

### 7.4 Producción

| Hito | Piezas nuevas de arte (orientativo) |
|---|---|
| W0 | 2 edificios de prueba listos para corte |
| W1 | ≈ 15 (montaña, jalones, bocas de túnel, guardarraíles) |
| C1 | ≈ 120 piezas de kit + 20 variantes de familia + 20 sets de interior + 15 de azotea + 30 props + 18 poses congeladas |
| V1 | ≈ 12 restos de vehículo + 25 props de rastro + letras + atlas `signage` + 3 animales pequeños |
| E1 | ≈ 15 (carámbanos, hielo, depósitos de alud, pala) + 5 animaciones |
| C2 | 10 POI héroe + sets portuario e industrial |
| E2 | ≈ 20 (variantes quemadas, colapsadas, heladas; tuberías, extintor, máscara de gas) |
| C3 | Base aérea, estación de esquí, 4 chalets, tren |
| V2 | 6 atuendos de NPC, 3 vehículos militares, helicóptero, perros + animaciones humanas |

---

## 8. Propuesta de roadmap

### 8.1 Criterios de orden

1. **Lo arriesgado primero** (como el PLAN): la legibilidad en ciudad (W0) y la rejilla (W1) antes que cualquier contenido urbano.
2. **La rejilla antes de SQLite**: M5 congela el esquema, las claves de chunk y los `wid` en disco. Ampliar el mundo después obliga a migrar partidas; antes, no cuesta nada. Y el código afectado hoy es pequeño (§4.4).
3. **El contrato del kit antes de producirlo**: el PLAN pide el arte del kit de M6a «durante M5». W0 debe cerrarse antes de que Opus empiece ese kit, para que nazca «listo para corte» (volúmenes cerrados, una losa por planta).
4. **La ciudad detrás del kit y de los coches** (M6a, M6b, M7): sin coche, la ciudad está a medio día a pie.
5. **La IA humana detrás del director completo** (M9b) y de las armas (M5).
6. **Cada hito jugable y con tests como puerta**, en el estilo del PLAN.

### 8.2 Hitos nuevos

#### W0 — Corte urbano (*spike*) y contrato del kit urbano · **S (código) + S (arte)**

- **Objetivo**: decidir con medidas la técnica de oclusión y congelar el contrato del kit antes de que se produzca.
- **Fable**: `shaders/include/city_cut.gdshaderinc` (§3.3); material compartido `world_vcol_struct`; `CutManager` (*globals*, uniformes por instancia, tween de planta, `SHADOWS_ONLY`); siluetas como `next_pass`; `CityCut.is_cut` y el rayo del cursor; `prototypes/citycut/` con tres vistas fijas (calle‑cañón, cruce en diagonal, azotea); `tests/citycut_probe.gd` (métrica de píxeles legibles de §3.8).
- **Opus**: dos edificios de prueba listos para corte (torre de 20 plantas: zócalo + 4 grupos + coronación + proxy de sombra; edificio de ensanche de 6 plantas), `cap_color` en la paleta; propuesta de ASSET_SPEC_V2 para el kit urbano.
- **Aceptación**: `citycut_probe` en Compatibility y Forward+: jugador ≥ 99 % y zombis ≥ 95 % legibles en las 3 vistas a 16/24/38 m; la sombra de la torre cortada sigue en la calle (píxeles en sombra ±5 % frente a sin corte); el cursor selecciona un contenedor a través de un edificio cortado; `perf_probe` en escritorio: el corte cuesta ≤ 10 % del frame (en llvmpipe, informativo); `run_smoke.sh` sin cambios.
- **Dependencias**: ninguna; en paralelo con el arte de M5.

#### W1 — Mundo de 6 × 6 km · **M (código) + S (arte)**

- **Objetivo**: caminar (y teletransportarse) por 6 km con el valle idéntico; carreteras, río y sierras nuevas como terreno; nada urbano aún.
- **Fable**: cambios de §4.4 (`WorldConst` 96², muros por eje, macro 768² con biomas nuevos, `gen_macro_map` 48 × 48 con las *splines* de A‑14, rondas, Gran Vía, N‑140 sur, Carretera del Puerto y ferrocarril como sellos, río Albo y dársena como hielo plano seguro hasta E1, `PoiRegistry` 48 × 48 con regiones y *pads* reservados, `Bounds` y niebla por lado, `/tp`); servidor con tablas de población de 96²; `perf_walk` con una ruta de 6.5 km por los cuatro cuadrantes.
- **Opus**: props de cresta y montaña, jalones de carretera, bocas de túnel (abierta y derrumbada), guardarraíles; si sobra, empieza el kit urbano de C1.
- **Aceptación**: **«el valle no cambia»**: hashes de altura, superficie y *scatter* de los chunks con |x|, |z| < 1 152 m idénticos a los previos a W1, salvo los de la Carretera del Puerto (lista cerrada en el test); `determinism.gd` en 60 chunks de los cuatro cuadrantes; `perf_walk --cpu` de 6.5 km a 25 m/s: p99 ≤ 2 ms y 0 tirones; modo render: memoria del cliente ≤ 2.5 GB; `run_net_test.sh --scenario far` con 4 clientes en 4 cuadrantes (hasta 5 km entre sí): cada uno recibe solo su anillo y el RSS del servidor ≤ 400 MB; el banner de región es correcto en 20 puntos de prueba.
- **Dependencias**: M4 (hecho). **Va antes de M5.**

#### C1 — ALTAVEGA: núcleo urbano · **L (código) + L (arte)**

- **Objetivo**: entrar por el Control del Puerto, cruzar el Puente de Hierro y recorrer casco viejo, ensanche, barriada y un bloque de Las Torres (hasta 40 plantas, 2 torres héroe con escalera y azotea) a 60 FPS con 4 jugadores.
- **Fable**: `tools/gen_city.gd` y `data/world/city/*` (distritos, lotes, grafo de calles, siluetas de distrito); `BuildingAssembler` de familias (zócalo, grupos de planta, coronación, proxy de sombra); `NavFloorTile` y enlaces de escalera; filtro vertical de interés; población urbana (estatuas en MultiMesh, atrapados en coches, población por planta); miradores (modo de cámara + siluetas); `far` dinámico; `perf_drive` urbano; `perf_horde_city`.
- **Opus**: kit urbano, 4 familias, 20 sets de interior, set de azotea, props de calle, poses congeladas horneadas, Control del Puerto y Puente de Hierro.
- **Aceptación**: hash de ciudad (fichero + vestido de 50 parcelas) igual en cliente y servidor; `citycut_probe` en 10 puntos aleatorios de la ciudad ≥ 95 %; `perf_drive` Carretera del Puerto → Gran Vía → ensanche a 15 m/s: ≤ 1 000 DC típicos, p99 ≤ 16 ms, 0 tirones > 33 ms; `perf_horde_city` (150 L0 + 300 estatuas + 4 bots en Las Torres): tick p50 ≤ 8 ms; escenario de red `tower` (4 clientes en 3 plantas de una torre héroe): puertas y contenedores coherentes, y el filtro vertical reduce la bajada ≥ 30 %; captura desde una azotea con la calle visible.
- **Dependencias**: W0, W1, M6a, M6b, M7. **Riesgo**: R15.

#### V1 — Rastros y vida ambiental · **M (código) + M (arte)**

- **Fable**: atascos (rondas y primer tramo de la A‑14), escenas de rastro (40 plantillas), grafitis y carteles (letras de malla + atlas `signage`), generadores sueltos con ventanas, humo, tendederos; bandadas (registro en servidor + *boids* en cliente), ratas, restos al viento, neón y semáforos con generador, paisaje sonoro.
- **Opus**: ≈ 12 restos de vehículo nuevos, props de campamento y rastro, set de letras, atlas `signage` (2048², paleta cerrada: primera textura del proyecto), cuervos, palomas y ratas.
- **Aceptación**: `perf_probe` en un cruce con todo activo: ≤ +0.5 ms de CPU del cliente y ≤ +60 DC frente a sin vida ambiental; test `flocks`: en 20 pasadas de un zombi a 10 m de una bandada, despega 20/20 y dos clientes ven el despegue con ≤ 0.2 s de diferencia; el escenario `zombies` no sube la bajada más de un 5 %; capturas de día, noche y ventisca en 3 distritos.
- **Dependencias**: C1.

#### E1 — Clima extremo · **L (código) + M (arte)**

- **Fable**: `HazardSystem` (global y regional); *whiteout*; tormenta de hielo (`ice_glaze`, resbalones, líneas cortadas); ola de frío (gasóleo, baterías, congelación en 60 s); aludes (cargas, disparadores, depósitos, sepultados, excavar); mapa de hielo por masa de agua (río, dársena, ibón y el lago de M8); congelación por partes; parte meteorológico de la radio de emergencia.
- **Opus**: carámbanos, grietas y agujeros de hielo de río, depósitos de alud (3), pala, anims `Act_Dig`, `Buried_Struggle`, `Slip_Fall`, `Act_Pull_From_Ice`.
- **Aceptación**: `tests/unit/hazards_test.gd` (carga y disparo de aludes, grosor de hielo, gelificación, resbalones: los valores de §6); escenario de red `avalanche`: A dispara un alud con una bomba de tubo en el desfiladero, B queda sepultado y A lo desentierra en ≤ 5 s; el depósito corta la N‑140 y persiste tras reiniciar; `run_smoke.sh`: `/weather ice_storm` → μ del asfalto 0.15 y un zombi que resbala; cruzar el río a pie sobre hielo medio y romperlo con un coche.
- **Dependencias**: M8 (modelo térmico), W1 (río y laderas).

#### C2 — Hitos de Altavega, puerto e industria · **L (código) + L (arte)**

- **Objetivo**: los 10 POI héroe de la ciudad, el puerto fluvial, el polígono con central térmica, parque de combustibles y químicas, la universidad y **el Gran Atasco completo**.
- **Fable**: POI como escenas; ascensores (enlaces con corriente, placeholder hasta E2); generador del Gran Atasco (2.2 km, 1 500–2 500 coches en MultiMesh con índice espacial); poblaciones por POI; `perf_drive` por la A‑14.
- **Opus**: los 10 POI, sets portuario e industrial, Torre Albo.
- **Aceptación**: `perf_drive` por la A‑14 a 30 m/s por el carril libre: 0 tirones; en el tramo más denso del atasco ≤ 1 000 DC típicos; escenario `hospital_provincial` (40–60 zombis, 4 jugadores): 0 desincronizaciones de puertas y contenedores; capturas de los 10 POI de día y de noche.
- **Dependencias**: C1, M9a (plantillas de servicios).

#### E2 — Peligros urbanos · **L (código) + M (arte)**

- **Fable**: red eléctrica (sectores, centrales, subestaciones, generadores, ascensores, alarmas), tuberías → inundación → hielo, gas y explosiones, vertidos, incendios (`fire_spread = buildings`), inversión térmica, carga de nieve y colapsos.
- **Opus**: variantes quemadas, colapsadas y heladas de las familias; tuberías, cascadas de hielo, extintor, máscara de gas, manchas de vertido.
- **Aceptación**: `tests/unit/urban_hazards_test.gd` (ignición de gas, propagación del fuego, carga de tejado, `T(y)` de la inversión); escenario `power`: 2 jugadores reparan la presa y activan 3 sectores → las ventanas se encienden en ambos clientes, suena al menos una alarma y los congelados de un interior calentado despiertan; escenario `fire`: un molotov en el ensanche se propaga al edificio adosado en 3–5 min y despierta congelados a ≤ 30 m; un hangar colapsa tras forzar Gran Ventisca + deshielo; todo persiste tras reiniciar; `perf_probe` de noche con 4 sectores encendidos ≤ 16 ms en Forward+.
- **Dependencias**: C2, E1.

#### C3 — Periferia sur · **M (código) + L (arte)**

- **Objetivo**: base aérea (con Coloso) y avión estrellado; suburbios (Vega Baja, Los Álamos, urbanizaciones del norte y del este); estación de esquí y Santa María del Puerto; túnel de Peña Roya (galería a pie) y desfiladero; ferrocarril con tren nevado; estación de mercancías; área de servicio.
- **Aceptación**: hashes de los suburbios; `perf_drive` N‑140 sur → A‑14 → base aérea; escenario `airbase` (4 jugadores, 40+ zombis y Coloso); cruzar el túnel derrumbado a pie en `run_smoke.sh`.
- **Dependencias**: C2, E1.

#### V2 — Vida dinámica · **L (código) + M (arte)**

- **Fable**: humanos (comerciantes y saqueadores) sobre `ZombieSystem` con cerebro humano y coberturas; trueque; convoyes; helicópteros; quitanieves de los supervivientes; `RadioSchedule` completo; lanzamientos; director del mundo; perros.
- **Opus**: 6 atuendos de NPC sobre el superviviente, 3 vehículos militares, helicóptero en vuelo, paracaídas y cajas, perros (esqueleto cuadrúpedo de M9b), anims `Human_Aim`, `Human_Shoot`, `Human_Cover`, `Human_Flee`, `Trade_Idle`.
- **Aceptación**: `tests/unit/world_director_test.gd` (nunca en Gran Ventisca, ≤ 1 evento grande por zona y hora, enfriamientos); escenario `raid`: 4 clientes contra 6 saqueadores, sus disparos atraen ≥ 5 zombis en 60 s y la bajada típica sigue ≤ 15 kB/s; escenario `convoy`: el convoy recorre 2 km de A‑14, se para en el atasco, abre un carril y el carril persiste tras reiniciar; `perf_horde` con 12 humanos L0 + 130 zombis L0: tick p50 ≤ 8 ms; trueque concurrente de 2 clientes con el mismo comerciante sin duplicar objetos.
- **Dependencias**: M9b (director completo, cuadrúpedos), M5, M7, C2.

### 8.3 Cambios en hitos existentes

| Hito | Cambio |
|---|---|
| M5 | Esquema SQLite con `world_version = 2` y `city_version` en `world_meta`; claves de chunk de 96² desde el primer día |
| M6a | Kit **listo para corte** (contrato de W0); `CutawayManager` con `inside` y tejados en `SHADOWS_ONLY` (no `visible = false`); `citycut_probe` en la calle de prueba |
| M6b | Las plantillas de aldea sirven de suburbio en C3 (mismo generador) |
| M7 | `perf_drive` por la A‑14 a 30 m/s (tramo de W1 con atasco provisional) |
| M8 | La congelación por partes se diseña ya con las fases de §6.13 (E1 la completa) |
| M9a | Plantillas de servicios (hospital, comisaría, iglesia, escuela) con variantes urbanas para C2 |
| M9b | Densidades urbanas y hordas L2 por el grafo de calles; el esqueleto cuadrúpedo habilita los perros de V2 |
| M10 | Evacuación por el **puente norte** (hoy) **o por la base aérea** (el convoy de V2 escolta hasta la pista); tercera línea de meta «**Devolver la luz a Altavega**»; capturas de las ≈ 45 regiones |

### 8.4 Orden propuesto y línea de corte

| # | Hito | Fable / Opus | Depende de |
|---|---|---|---|
| 1 | **W0** Corte urbano | S / S | — (en paralelo con el arte de M5) |
| 2 | **W1** Mundo de 6 km | M / S | M4 |
| 3 | M5 Armas, botín, SQLite, operación | L / M | M4, W1 |
| 4 | M6a Kit (listo para corte), carreteras, calle | M / L | M3, M5, W0 |
| 5 | M6b La Herrería y POIs | L / M | M6a |
| 6 | M7 Vehículos | M / M | M5, M6b |
| 7 | **C1** Altavega núcleo | L / L | W0, W1, M6a, M6b, M7 |
| 8 | **V1** Rastros y vida ambiental | M / M | C1 |
| 9 | M8 Frío v2, base, progresión | L / M | M5, M6b |
| 10 | **E1** Clima extremo | L / M | M8, W1 |
| 11 | M9a Valdenieve y regiones | L / L | M6b, M8 |
| 12 | **C2** Hitos, puerto, industria, Gran Atasco | L / L | C1, M9a |
| 13 | M9b Director, especiales, hordas | L / M | M9a |
| 14 | **E2** Peligros urbanos | L / M | C2, E1 |
| 15 | **C3** Periferia sur | M / L | C2, E1 |
| 16 | **V2** Vida dinámica | L / M | M9b, C2 |
| 17 | M10 Meta, co‑op, lanzamiento | L / M | M9b, V2 |

Grafo de dependencias (el orden de ejecución, con un Fable y un Opus, es el de la tabla):

```
W0 ──┐
W1 ──┴─► M5 ─► M6a ─► M6b ─► M7 ─► C1 ─► V1
                        │                   ╲
                        └─► M8 ─► E1 ─► M9a ─► C2 ─► M9b ─► E2 ─► C3 ─► V2 ─► M10
```

Son 17 pases frente a los 8 que quedaban (M5–M10): **el trabajo restante se duplica (×2.1)**. Si hay que recortar para v2.0:

- **v2.0**: W0, W1, M5–M10, C1, V1, E1, C2, y dos versiones ligeras: **E2‑ligera** (red eléctrica e incendios) y **V2‑ligera** (radio, lanzamientos, helicópteros y convoyes **sin humanos a pie**).
- **v2.1**: C3 (periferia sur: la base aérea queda como punto de evacuación alternativo solo si C3 entra), comerciantes y saqueadores a pie, perros, gas, vertidos, *smog* y colapsos.
- **Punto de decisión**: al cerrar C1, con el ritmo real de producción de familias e interiores (como R5 pide para Valdenieve).

### 8.5 Riesgos nuevos

| # | Riesgo | Prob. | Impacto | Señal de alarma | Mitigación / plan B | Hito |
|---|---|---|---|---|---|---|
| R14 | Legibilidad en ciudad insuficiente pese al corte | Media | Alto | `citycut_probe` < 95 % o *playtest* confuso | Prototipo ya al 100 % en calle‑cañón; plan B: *pitch* urbano −55° opcional, siluetas más fuertes, `R` mayor | W0 |
| R15 | Volumen de contenido urbano (kit, familias, interiores, 14 héroes) | Alta | Alto | C1 entrega < 70 % de familias o interiores | Bajar el % enterable; familias parametrizadas (JSON, no scripts); lista de héroes priorizada; línea de corte §8.4 | C1–C3 |
| R16 | CPU de la IA humana | Media | Alto | `perf_horde` con humanos > 8 ms | ≤ 12 humanos L0; coberturas precalculadas; tope de zombis 130; plan B: combates humano‑zombi lejanos resueltos en abstracto (L2) | V2 |
| R17 | Navmesh multiplanta | Media | Medio | Cola de horneado > 2 s | Teselas por planta perezosas, escaleras como enlaces, ≤ 12 teselas/s | C1 |
| R18 | Tirones de streaming en ciudad | Media | Alto | `perf_drive` urbano con frames > 33 ms | `PackedScene` por variante, grupos de plantas, precarga, velocidad limitada por el tráfico muerto | C1 |
| R19 | El generador de ciudad cambia después de publicar | Media | Medio | Hash de ciudad distinto entre versiones | `city_version` + migración explícita; datos congelados por hito | C1+ |
| R20 | La excepción de textura `signage` rompe el estilo | Baja | Bajo | Capturas | Paleta cerrada, solo carteles y rótulos, verificador | V1 |
| R21 | El alcance nuevo desborda el plan | Alta | Alto | Retrasos acumulados tras C1 | Línea de corte §8.4 decidida al cerrar C1 | todos |
| R22 | Coste de `discard` + `cull_disabled` en iGPU (`compat`) | Media | Medio | `perf_probe` `compat` fuera de presupuesto | `cut_class = 0` por CPU lejos de la zona; tapas solo cerca; tramado más simple | W0, C1 |
| R23 | Desenfoque PCSS ligado a la distancia al origen (#86536): la ciudad está a 2–4.6 km | Media | Medio | Sombras borrosas o inestables en Altavega | PCSS solo en `alto` con ángulo ≤ 1.2°; plan B: desplazamiento de origen solo en el cliente (doc 01 §4.3) | W1, C1 |

### 8.6 Documentos que hay que actualizar si se aprueba

| Documento | Secciones |
|---|---|
| `PLAN_MAESTRO.md` | C2 (dos materiales compartidos + excepción `signage`), **C6** (6 144 m, 96², mundo asimétrico), C8 (las torres apilan plantas fusionadas), C9 (≤ 12 humanos L0; 130 zombis L0 con humanos), C21 (densidades urbanas), §4 (mapa 48 × 48 y regiones de §4.3), §7 (hitos W0, W1, C1–C3, V1–V2, E1–E2), §9 (R14–R23), **§10** (no‑objetivo 2 enmendado) |
| `GDD_MUNDO_ABIERTO.md` | §3.1 (cifras de cámara del código, corte urbano, miradores), §4.5 (nuevas formas del frío), §6.4 (densidades, estatuas, atrapados), §8 (gasóleo gelificado, cadenas en hielo glaseado), §9 (tablas de botín de los edificios nuevos), §11.3 («Devolver la luz», evacuación alternativa), §17, §18 |
| `ARQUITECTURA_V2.md` | §8.1/§8.9 (`WorldConst`, macro), §9 (generador de ciudad, `BuildingAssembler` de familias), §9.3 (corte urbano, `SHADOWS_ONLY`), §10 (`NavFloorTile`, humanos), §13 (`HazardSystem`), §6.5 (interés vertical) |
| `ASSET_SPEC_V2.md` | Kit urbano listo para corte (volúmenes cerrados, losa por planta, `cap_color`), familias por gramática, grupos de plantas y proxy de sombra, poses congeladas, atlas `signage` |
| `research/07_assets_cc0.md`, `research/08_graficos_g2.md` | Etapa «listo para corte» en `winterize`; el P0 «fundido de torres» del 08 pasa a ser el corte urbano de §3 (W0 = G2a en lo que se solapan); occlusion culling desaconsejado en ciudad |

---

## 9. Fuentes

Leídas directamente (páginas accesibles desde el entorno):

- Godot docs, *Spatial shader reference* (`depth_test_inverted`, modos de stencil y su restricción al pase transparente, `IN_SHADOW_PASS`, `CAMERA_POSITION_WORLD`, `FRONT_FACING`) — https://raw.githubusercontent.com/godotengine/godot-docs/master/tutorials/shaders/shader_reference/spatial_shader.rst
- Godot docs, *Standard Material 3D* (modos de stencil *Outline*/*X‑Ray*, *Depth Test: Inverted*, *distance fade* por tramado) — https://raw.githubusercontent.com/godotengine/godot-docs/master/tutorials/3d/standard_material_3d.rst
- Godot docs, *Occlusion culling* — https://raw.githubusercontent.com/godotengine/godot-docs/master/tutorials/3d/occlusion_culling.rst
- Godot docs, *Visibility ranges (HLOD)* — https://raw.githubusercontent.com/godotengine/godot-docs/master/tutorials/3d/visibility_ranges.rst
- Implementación documentada de oclusores tramados en cápsula (sombras que se conservan, suelo que nunca se funde, coste estimado 0.1–0.3 ms a 2 MP en iGPU) — https://github.com/tougenrip/thirdfold/issues/283 ; tejados que se funden sin ensuciar la sombra — https://github.com/tougenrip/thirdfold/issues/259 ; el cursor debe ignorar geometría cortada, rebajada o tramada — https://github.com/tougenrip/thirdfold/issues/291
- Tejado oculto que deja de proyectar sombra (interior iluminado por el sol) — https://github.com/APKiwiOrg/KhaozEngine/issues/974

Consultadas a través de resultados de búsqueda (sitios bloqueados por el proxy del entorno o no descargados):

- Stencil en Godot 4.5: PR — https://github.com/godotengine/godot/pull/80710 ; propuesta — https://github.com/godotengine/godot-proposals/issues/7174 ; artículo — https://80.lv/articles/mind-bending-power-of-godot-4-5-s-stencil-support
- Baldur's Gate 3, recreaciones del recorte de oclusión — https://www.artstation.com/artwork/WXVnyD ; https://80.lv/articles/artist-recreated-baldur-s-gate-3-occlusion-cutout-effect ; https://www.therookies.co/projects/78292
- Ocultación de paredes «estilo Diablo» — https://forums.unrealengine.com/t/diablo-style-wall-hiding-in-blueprints/9697 ; https://forum.unity.com/threads/diablo-style-walls-that-become-visible-hidden-depending-on-the-characters-location.76310/
- Diablo IV, arte de entornos para su cámara — https://news.blizzard.com/en-gb/diablo4/23788294/diablo-iv-quarterly-update-march-2022 ; https://www.gamespot.com/articles/diablo-4s-art-direction-emphasizes-hand-crafted-details-plenty-of-customization-and-just-enough-realism/1100-6493411/
- The Ascent, verticalidad con cámara isométrica fija — https://www.windowscentral.com/the-ascent-interview ; https://www.unrealengine.com/en-US/developer-interviews/11-person-studio-neon-giant-delivering-next-gen-passion-project-the-ascent ; https://medium.com/@KonstantinosD/the-arcologies-of-the-ascent-d4551a088624
- Project Zomboid: B42 y edificios altos — https://projectzomboid.com/blog/features-overview-build-42-20/ ; queja de B42 por ver interiores — https://steamcommunity.com/app/108600/discussions/0/846243771540614602/ ; *cutaway* al apuntar — https://steamcommunity.com/app/108600/discussions/0/846243771540728472/ ; electricidad y corte del suministro — https://pzwiki.net/wiki/Electricity ; https://pzwiki.net/wiki/Power_Shutoff
- XCOM 2: GDC 2018 «Plot and Parcel» — https://www.gdcvault.com/play/1025213/Plot-and-Parcel-Procedural-Level ; techos y selección de planta — https://steamcommunity.com/app/268500/discussions/0/1696048786956189267/ ; XCOM: EU, tejados que reaparecen — https://www.giantbomb.com/forums/xcom-enemy-unknown-7982/xcom-pc-graphical-bugs-563866/
- Commandos: Origins, edificios de varias plantas integrados y queja sobre los interiores — https://www.kalypsomedia.com/post/commandos-origins-faq ; https://gamingbolt.com/commandos-origins-everything-you-need-to-know ; https://steamcommunity.com/app/1479730/discussions/0/604153636037097950/
- Desperados III, conos de visión y contorno de personajes — https://www.supercheats.com/desperados-3-walkthrough-guide/enemy-field-of-view ; https://attackofthefanboy.com/guides/desperados-iii-ultimate-beginners-guide-tips-tricks-and-strategies/
- Shadowrun Returns, editor isométrico — https://shadowrun-returns.fandom.com/wiki/Building_An_Exterior_Map
- Frostpunk, calor y mapa de calor — https://frostpunk.fandom.com/wiki/Heat ; https://lexdev.net/tutorials/case_studies/frostpunk_heatmap.html
- Company of Heroes, edificios guarnecidos — https://companyofheroes.fandom.com/wiki/Buildings
- State of Decay 2, enclaves (comerciantes, NPC por comunidad) — https://state-of-decay-2.fandom.com/wiki/Enclaves
- DayZ, eventos dinámicos de la *Central Economy* (`events.xml`, accidentes de helicóptero) — https://dzconfig.com/wiki/events ; https://xgamingserver.com/blog/dayz-helicopter-crash-sites-guide/
- Müller, Wonka, Haegler, Ulmer, Van Gool (2006), *Procedural Modeling of Buildings* (CGA *shape*) — https://dl.acm.org/doi/10.1145/1179352.1141931
- CC0 urbanos (solo maqueta): Kenney *City Kit (Commercial)* — https://kenney.nl/assets/city-kit-commercial ; https://opengameart.org/content/city-kit-commercial ; Quaternius *Downtown City MegaKit* — https://quaternius.com/packs/downtowncitymegakit.html
- Tormenta de hielo de 1998 — https://www.weather.gov/btv/25th-Anniversary-of-the-Devastating-1998-Ice-Storm-in-the-Northeast ; https://vlab.noaa.gov/web/nws-heritage/-/the-great-ice-storm-of-1998
- Ángulo de las laderas y aludes — https://avalanche.org/avalanche-encyclopedia/terrain/slope-characteristics/slope-angle/ ; https://utahavalanchecenter.org/blog/16386
- Inversión térmica y bolsas de aire frío — https://deq.utah.gov/air-quality/inversions ; https://en.wikipedia.org/wiki/Cold-air_pool
- Helada de Texas de 2021 (tuberías) — https://www.ncei.noaa.gov/news/great-texas-freeze-february-2021 ; https://www.groundworks.com/resources/how-many-texans-had-frozen-pipes-during-februarys-crisis/
- Cargas de nieve en tejados — https://www.weather.gov/media/ajk/articles/snowloads.pdf
- Grosor seguro del hielo — https://www.dnr.state.mn.us/safety/ice/thickness.html

Internas: `docs/PLAN_MAESTRO.md` (C1–C24, §4, §7, §9, §10), `docs/v2/GDD_MUNDO_ABIERTO.md`, `docs/v2/ARQUITECTURA_V2.md` (§8.9, §9, §10.7, §12, §13), `docs/research/01_mundo_abierto_tecnologia.md` (§1.2, §2, §4.4, §5), `02_jugabilidad_zombies_armas.md`, `05_graficos_arte.md` (§2.2), `06_graficos_render.md` (R‑G1), `07_assets_cc0.md` y `08_graficos_g2.md` (escritos en paralelo; §0.1), `data/world/poi_registry.gd`, `scripts/data/balance.gd`, `scripts/world/world_const.gd`.

---

## Apéndice A — Mapa 48 × 48 en formato de `PoiRegistry.ASCII`

Filas de 48 caracteres, fila 0 = norte. Las filas 0–21 / columnas 0–22 coinciden con el `ASCII` actual salvo la Carretera del Puerto (fila 9, columnas 18–22).

```gdscript
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
	"^######...................f...............x.=^^^",
	"^######...............................f.....=^^^",
	"^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^~^^^^^^^^^^^^=^^^",
	"^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^~^^^^^^^^^^^^=^^^",
	"^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^~^^^^^^^^^^^^U^^^",
]
```

## Apéndice B — Cómo reproducir el prototipo (W0)

- Escena generada por código: 8 × 8 manzanas (periodo 48 m, calles de 12 m), un edificio de 34 × 34 m por manzana con 2–4 (25 %), 5–10 (35 %) o 12–40 (40 %) plantas de 3 m (semilla 1234); cada planta: 4 muros en 3 bandas de color de vértice, losa superior e inferior, tabique central de doble cara; azotea con pretil de 1 m. Jugador en (0, 0.9, 24), 14 zombis en la calzada a ≤ 16 m. Sol a −28°, sombras de 2 *splits* a 60 m.
- Cámara: la del juego (yaw 45°, pitch −48°, FOV 36°, distancia 16/24/38, pivote 3 m por delante, `near` 0.3, `far` 70).
- Materiales: el *include* de §3.3 en un `ShaderMaterial` con `cull_disabled`; siluetas de §3.3 como `next_pass` de un material sin sombreado (jugador verde, zombis rojos; siluetas cian y ámbar para contarlas).
- Métrica: captura de 1280 × 720, remuestreo a 640 × 360 por vecino más cercano, recuento de píxeles por color frente a una referencia sin edificios; se promedian 20–40 frames para los tiempos.
- Ejecución: `taskset -c 0,1 xvfb-run -a -s "-screen 0 1280x720x24" godot --path prototypes/citycut --rendering-driver opengl3 --rendering-method gl_compatibility ++ --dist=24` (y `--rendering-driver vulkan --rendering-method forward_plus` con lavapipe).
