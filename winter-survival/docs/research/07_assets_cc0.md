# 07 — Assets CC0 para G2: inventario, prueba práctica y pipeline "winterize"

> Proyecto VENTISCA (Godot 4.7.2, cámara alta: pitch −48°, FOV 36°, 24 m por defecto; arte procedural en Blender
> 5.0.1 con color de vértice + AO en `COLOR_0.a` y un único `world_vcol`). Fecha: 2026‑09‑26. Autor: dirección de arte /
> arte técnico (Opus). Estado: **investigación + prueba práctica ejecutada** (30 modelos CC0 convertidos, renders
> Cycles antes/después y bloque de ciudad de día y de noche).
>
> Pedido del dueño: mejores gráficos **con assets de librerías**, **ciudades con rascacielos**, un mundo **habitado**
> (coches, atascos, luces, humo, animales) siempre nevado. Decidido: **librerías CC0** (Kenney, Quaternius, KayKit,
> Poly Haven…) reestilizadas a nuestro invierno y mapa de **≈ 6 × 6 km** con ciudad.
>
> Complementa `05_graficos_arte.md` (guía de arte v2.1, que en sept‑2026 descartó los packs CC0 como base: este
> documento **revisa esa conclusión** a la luz de la decisión del dueño) y `08_graficos_g2.md` (plan de render G2).
> Todo lo generado en esta prueba vive en el scratchpad (`…/scratchpad/g2_assets/`), **nada** en el repositorio salvo
> este documento y el 08.

---

## 0. Resumen ejecutivo

| Pregunta | Respuesta |
|---|---|
| ¿Hay librerías CC0 que cubran ciudad, coches y props? | **Sí.** Kenney (*City Kit Commercial* con 5 rascacielos, *Roads*, *Industrial*, *Suburban*, *Car Kit* 3.1, *Survival*, *Watercraft*, *Train*), Quaternius (*Downtown City MegaKit*, *Zombie Apocalypse Kit*, *Cars*, *Modular Streets*, *Ultimate Animated Animals*, *Farm Buildings*) y KayKit (*City Builder Bits*). Todas **CC0 1.0** (verificado en su `License.txt`). |
| ¿Se pueden descargar desde este contenedor? | **Sí, por GitHub**, aunque las webs oficiales estén bloqueadas: `series-ai/jam-ready-assets` (322 packs, 318 CC0, Git LFS, cada pack con su `License.txt`), `KayKit-Game-Assets/*` (oficial), `KenneyNL/Starter-Kit-*` (oficial) y `chibifire-stages/quaternius-stage` (Quaternius en OpenUSD `.usda` + texturas). Los ficheros LFS se bajan de `media.githubusercontent.com` (permitido). Detalle en §1. |
| ¿Encajan con nuestro estilo? | **Tras el pase "winterize", sí para ciudad, vehículos realistas y props; no para personajes.** Quaternius (coches, *Zombie Apocalypse Kit*, *Downtown*) tiene proporciones reales y es el que mejor encaja. Kenney *City Kit* da rascacielos limpios y baratos (1.1–1.9 k tris) que, reescalados por altura de planta y alargados, quedan muy bien en nieve; los **coches Kenney** y todo **KayKit** son "juguete" (proporciones chatas, ventanas enormes): solo relleno lejano o nada. Nuestros personajes, zombis, pinos y la cabaña HD siguen siendo mejores que cualquier pack. |
| ¿Funciona el pase automático? | **Sí.** `winterize.py` (prototipo, §4): importa glTF/GLB/FBX/OBJ/USD → escala a metros (por altura de planta detectada) → color por esquina desde el atlas/material → gradación invernal OKLab → suciedad/escarcha/óxido → losas de nieve redondeadas + ventisqueros → AO horneada en `COLOR_0.a` (la misma `lib/hd.bake_ao` del juego) → GLB con nuestro contrato (sin UV, sin imágenes, `palette_vcol` + `window`/`glass`/`emissive_lamp`). **30 modelos en ≈ 50 s**; se importan en Godot 4.7.2 con 0 errores y se ven con los shaders del juego (`godot_*.png`, 08 §5.0). |
| ¿Color de vértice o atlas de textura? | **Color de vértice** para todo lo que usa atlas‑paleta (Kenney, KayKit, Quaternius *Zombie Kit*/coches: conversión exacta, 1 material compartido, sin VRAM de texturas; 10 MB los 30 modelos frente a 66 MB con sus texturas originales, ×27 en un edificio *Downtown*). **Atlas/texturas solo como excepción** para un eventual set "héroe" de *Downtown MegaKit* (ladrillo y molduras pintadas en textura); hoy no compensa (§4.3). |
| Coste de rendimiento | Rascacielos winterizado: 6.4–16.2 k tris (fuente 1.1–1.9 k; las plantas añadidas y la nieve lo multiplican ×5–10), 2 superficies. Coches 2.4–8.1 k, 2–3 superficies. *Downtown* 20–28 k tris por edificio (demasiado para relleno: HLOD obligatorio). |
| Qué pedir al dueño | Permitir en la red del entorno, por orden: **kenney.nl**, **quaternius.com + drive.google.com + drive.usercontent.google.com + www.googleapis.com**, **itch.io + api.itch.io + su CDN**, **polyhaven.com + api.polyhaven.com + dl.polyhaven.org**, **ambientcg.com**. Lista exacta y qué desbloquea cada uno en §6. Los espejos de GitHub bastan para empezar G2; los dominios oficiales dan versiones completas y verificables en origen. |

**Recomendación**: adoptar CC0 como **base de la ciudad y del tráfico abandonado** (edificios de relleno, torres,
coches, mobiliario urbano, industria/puerto), siempre a través de `winterize` y del manifiesto de licencias (§5).
Mantener lo procedural "HD" para lo que define la identidad y el contrato (personajes, zombis, vegetación, casas
enterables con corte, vehículos conducibles con anclas). El pase G2 de render (`08`) es el que hace que todo se
vea "de la misma familia": nieve por normal global, niebla, luces de ciudad y gradación.

---

## 1. Método y red

### 1.1 Qué está bloqueado y qué no (medido el 2026‑09‑26 con `curl` por el proxy)

| Dominio | Resultado | Nota |
|---|---|---|
| kenney.nl, quaternius.com, quaternius.itch.io, itch.io, polyhaven.com, api.polyhaven.com, dl.polyhaven.org, ambientcg.com, opengameart.org, poly.pizza, static.poly.pizza, sketchfab.com, drive.google.com, drive.usercontent.google.com, cdn.jsdelivr.net, huggingface.co, kaylousberg.com, blenderkit.com, godotengine.org | **bloqueado** (CONNECT 403) | WebFetch también bloqueado; WebSearch sí devuelve resúmenes |
| github.com (git clone), raw.githubusercontent.com, **media.githubusercontent.com** (LFS), registry.npmjs.org, pypi.org | **permitido** | La API REST de repos ajenos y `codeload` no sirven; `git clone --filter=blob:none` sí |

### 1.2 Espejos encontrados (todos verificados abriendo su licencia)

| Repositorio | Qué contiene | Licencia (fuente) | Cómo se baja aquí |
|---|---|---|---|
| [`series-ai/jam-ready-assets`](https://github.com/series-ai/jam-ready-assets) | 322 packs (240 de Kenney, 54 de ellos 3D; KayKit "Complete Collection v4" 2026; otros). **Sin Quaternius.** | README: 318 CC0 + 4 MIT; **cada pack lleva su `License.txt` original** (Kenney: "Creative Commons Zero, CC0", con versión y fecha; KayKit: CC0) | `git clone --depth 1 --filter=blob:none --no-checkout` (árbol: 128 097 ficheros) + cada `.glb`/`.png` (punteros LFS) desde `https://media.githubusercontent.com/media/series-ai/jam-ready-assets/main/<ruta>`; SHA‑256 comprobado contra el puntero LFS (todos coinciden) |
| [`KayKit-Game-Assets/KayKit-City-Builder-Bits-1.0`](https://github.com/KayKit-Game-Assets/KayKit-City-Builder-Bits-1.0) (+ 9 packs más de la misma org) | 41 modelos gltf/fbx/obj + 1 atlas 1024² | `LICENSE.txt`: CC0 1.0, Kay Lousberg | `git clone` directo (oficial) |
| [`KenneyNL/Starter-Kit-City-Builder`](https://github.com/KenneyNL/Starter-Kit-City-Builder), [`Starter-Kit-Racing`](https://github.com/KenneyNL/Starter-Kit-Racing) (2026) | subconjunto de City Kit / camiones de carreras | **Código MIT** (`LICENSE.md`); el README declara los **modelos CC0** | `git clone` directo (oficial). Poco contenido: el espejo de `jam-ready-assets` es más completo |
| [`chibifire-stages/quaternius-stage`](https://github.com/chibifire-stages/quaternius-stage) | 82 packs de Quaternius convertidos a **OpenUSD `.usda`** (3 956 ficheros) + texturas PNG | `LICENSE`: CC0 1.0 (y README: "OpenUSD copy of Quaternius CC0 low-poly packs") | `git clone --filter=blob:none` + `git checkout HEAD -- models/<Pack>` (blobs normales, sin LFS). Blender 5.0.1 importa `.usda` (`bpy.ops.wm.usd_import`) |
| [`beep2bleep/FreeAssetsByKenneyNLandQuaternius`](https://github.com/beep2bleep/FreeAssetsByKenneyNLandQuaternius) | Kenney y Quaternius **antiguos** (2016–2019) en formatos originales | `License.txt` por pack (CC0) | `git clone`; útil solo como respaldo |
| [`J-Ponzo/gltf-universal-animation-library`](https://github.com/J-Ponzo/gltf-universal-animation-library), [`J-Ponzo/gltf-medieval-village-megakit`](https://github.com/J-Ponzo/gltf-medieval-village-megakit) | Quaternius UAL / Medieval Village en glTF | CC0 (copia del pack oficial) | ya identificado en doc 05 |
| [`mrdoob/three.js`](https://github.com/mrdoob/three.js) `examples/textures/equirectangular/` | 10 HDRI de Poly Haven 1k (ninguna nevada) | CC0 (Poly Haven) | `git clone --filter=blob:none` |

Advertencias sobre los espejos (se registran en el manifiesto, §5):

- **La conversión a USD de terceros pierde datos a veces**: el autobús de *Public Transport* (2017) llegó con los 7
  materiales en gris 0.8 (colores perdidos) y los coches de *Cars* usan materiales de color plano (bien). *Downtown
  MegaKit* está **incompleto** en el espejo (153 de "300+" piezas, 3 edificios de ejemplo). Para producción conviene
  la descarga oficial (§6), y el espejo solo para prototipar.
- `jam-ready-assets` es un espejo curado de un tercero: la cadena de custodia es su `License.txt` (que es el del
  autor, con versión y fecha) + el SHA‑256 del LFS. Suficiente para CC0 (no hay obligación de atribución), pero el
  manifiesto guarda repo + commit + ruta + hash para poder re‑verificar contra el pack oficial cuando se abra el
  dominio.

---

## 2. Inventario

Leyenda de **encaje de estilo** (con nuestro look: low‑poly "premium", nieve azul pastel, paleta desaturada, AO,
cámara a 24 m): ●●● encaja tras `winterize`; ●● encaja con ajustes (escala, proporciones o limpieza); ● solo relleno
lejano; ○ no. **Tris** = mín / mediana / máx del pack, **contados en los ficheros** (GLB por accesores; USDA por
`faceVertexCounts`; `out/tri_census_*.json`). "Accesible" = hoy, desde este contenedor.

### 2.1 Ciudad: rascacielos, oficinas, viviendas, comercios

| Pack (versión, fecha) | Contenido útil | Licencia | Accesible | Formatos | Tris | Encaje | Notas |
|---|---|---|---|---|---|---|---|
| **Kenney City Kit Commercial** 2.1 (21‑07‑2025) — [kenney.nl](https://kenney.nl/assets/city-kit-commercial) | 5 **rascacielos** (`building-skyscraper-a…e`), 14 edificios comerciales/oficinas (`building-a…n`), 16 **versiones de bajo detalle** (`low-detail-building-*`, 62–378 tris, mediana 150: ¡impostores listos!), toldos, sombrillas | CC0 | **sí** (jam‑ready, LFS) | GLB/FBX/OBJ + `colormap.png` 512² (atlas‑paleta) + `variation-a/b.png` (recoloreados) | 40 / 246 / 5 246 | ●●● torres / ●● comerciales | Escala "maqueta" (planta ≈ 0.35 u): `winterize` la detecta y reescala a 3.8 m/planta (×10–11) y alarga las torres repitiendo plantas (de 7–13 a 18–27 plantas, 63–104 m). Ventanas = geometría con color azul del atlas → material `window` |
| **Quaternius Downtown City MegaKit** — [quaternius.com](https://quaternius.com/packs/downtowncitymegakit.html) / itch | 300+ piezas modulares estilo Boston/NYC (fachadas de ladrillo, cornisas, columnas, tejados de pizarra, escaleras de incendios, aceras, calles, marcas viales) + edificios de ejemplo | CC0 (la versión *Source* de pago añade proyectos y shaders) | **parcial**: 153 piezas `.usda` + 22 texturas en `quaternius-stage` | FBX/OBJ/glTF oficial; USDA en el espejo | 2 / 48 / **45 122** (ejemplos: 18–45 k) | ●●● forma / ● coste | Proporciones reales (m), el más "adulto" de todos; texturas tileables 2k–4k + normales + "fake interior". Media‑altura (≤ 28 m): no hay rascacielos. Pesado para relleno (§3.2) |
| **Quaternius Ultimate Textured Buildings** | 102 piezas/edificios de 1–6 plantas, letreros de tienda (farmacia, panadería, ferretería…) | CC0 | sí (USDA) | idem | 10 / 2 714 / 13 564 | ●● | Texturizado; útil para calles comerciales de pueblo |
| **Quaternius Buildings / Simple Buildings** (packs clásicos) | banco, hospital, pisos, tiendas, casas | CC0 | sí (USDA) | idem | 1 454 / 2 624 / 41 788 | ● | Estilo antiguo, colores planos |
| **Kenney City Kit Suburban** 2.0 (04‑2025) | 21 casas, vallas, caminos, árboles | CC0 | sí | GLB + atlas | 12 / 800 / 2 062 | ●● | Casas enterables: mejor nuestro kit M6a; sirven de relleno de barrio |
| **Kenney Modular Buildings** 2.1 / **Building Kit** 1.0 | fachadas modulares (ventanas, puertas, cornisas) / muros, escaleras, **barricadas de puerta y ventana** | CC0 | sí | GLB + atlas | 12 / 40 / 524 · 10 / 72 / 446 | ●● | Buenas piezas para variar nuestro kit (barricadas ya encajan con el tema) |
| **KayKit City Builder Bits** 1.0 — [GitHub oficial](https://github.com/KayKit-Game-Assets/KayKit-City-Builder-Bits-1.0) | 8 edificios, 5 coches, calles, farola, semáforos, contenedor, hidrante, banco, depósito de agua | CC0 | **sí** (oficial) | glTF/FBX/OBJ + atlas degradado 1024² | 18 / 586 / 1 885 | ○/● | Chibi (edificios de 2×2 u, coches de 0.94 u): no casa con personajes de proporciones reales |
| Kenney **Retro Urban Kit** 2.0 | muros, cables, andamios, barreras, contenedores, camiones | CC0 | sí | GLB + **texturas por material** (22 PNG) | 2 / 24 / 124 | ● | Texturas pixeladas; solo props sueltos |

### 2.2 Carreteras, autovía, puentes y mobiliario urbano

| Pack | Contenido | Licencia | Accesible | Formatos | Tris | Encaje | Notas |
|---|---|---|---|---|---|---|---|
| **Kenney City Kit Roads** 2.0 (03‑2025) | 72 piezas: rectas, cruces, rotonda, **puente** + pilares, rampas/pendientes, **barreras** (`*-barrier`), **farolas** (`light-square/curved`, simples/dobles/en cruz), **señal de autovía** (pórtico), conos y barreras de obra | CC0 | sí | GLB + atlas | 12 / 92 / 1 636 | ●● | Las baldosas de calzada no sirven tal cual (nuestra carretera es cinta generada con surcos, doc 06/ARQ); **sí** puentes, barreras, pórticos, farolas |
| **Quaternius Modular Streets** | calles, **puente elevado + rampa**, farolas ×3, semáforos ×2, señales (stop, prohibido aparcar, triángulo) | CC0 | sí (USDA) | idem | 12 / 394 / 12 562 | ●● | La farola doble (2.5 k tris) es la mejor farola CC0 que hemos visto a 24 m |
| **Quaternius Zombie Apocalypse Kit** | **barreras de tráfico**, conos, semáforos, farolas, **contenedores marítimos**, palés, bidones, tuberías, bolsas de basura, pila de neumáticos, **depósito de agua**, cartel de pueblo, sangre, calles agrietadas | CC0 | sí (USDA; atlas 6 KB) | idem | 74 / 1 446 / 28 105 | ●●● | Temática exacta (post‑apocalipsis), proporciones reales, atlas‑paleta minúsculo → conversión perfecta a color de vértice |
| **Kenney Survival Kit** 2.0 | barriles, cajas, tiendas, estructuras metálicas, vallas fortificadas, fogatas, herramientas | CC0 | sí | GLB + atlas | 28 / 124 / 758 | ●● | Relleno de campamentos de supervivientes ("huellas de vida") |
| **Kenney Holiday Kit** 2.0 | kit de cabaña de troncos con tejados nevados, montones y búnker de nieve, trineos, farolillos, **guirnaldas de luces**, coronas, muñecos, regalos, trenecito | CC0 | sí | GLB + atlas | 10 / 204 / 1 150 | ● | Guirnaldas y farolillos = "vida" de noche; la cabaña es inferior a la nuestra; el resto es demasiado festivo |
| **KayKit City Builder Bits** | farola, semáforos, contenedor, hidrante, papeleras, banco | CC0 | sí | glTF | 18–636 | ● | Chibi |

### 2.3 Vehículos

| Pack | Vehículos | Licencia | Accesible | Tris | Encaje | Notas |
|---|---|---|---|---|---|---|
| **Quaternius Zombie Apocalypse Kit** | pickup, deportivo, camión (+ versiones **blindadas** con rejas/placas) | CC0 | sí (USDA) | 6.4 k (pickup) … 28 k (camión blindado) | ●●● | Proporciones reales (pickup 5.2 m), ruedas separadas, faros/pilotos con material propio → `emissive_lamp`/rojo |
| **Quaternius Cars** | sedán ×2, SUV, **policía**, taxi, deportivos ×2 | CC0 | sí (USDA) | 2 954 / 3 148 / 3 294 | ●●● | Materiales de color plano con nombre (`Windows`, `Headlights`, `TailLights`, `BlueLights`) → clasificación exacta |
| **Quaternius Public Transport** (2017) | **autobús**, autobús escolar, **ambulancia**, taxi, tren, bicicletas, cono, semáforo, señales | CC0 | sí, pero **colores perdidos** en el USD del espejo | 88 / 1 308 / 2 976 | ●● (oficial) | Proporciones algo chatas (autobús 4.1 : 1.7) |
| **Quaternius Tank Pack / Train Pack** (2019) | tanques, trenes | CC0 | sí (beep2bleep, formatos originales) | — | ● | Militar para el control del km 12 |
| **Kenney Car Kit** 3.1 (04‑2026) | sedán, sedán deportivo, SUV, SUV lujo, **policía**, **ambulancia**, **bomberos**, **basura**, reparto (×2), furgoneta, camión (×2), taxi, **tractores** (×3), karts, conos, **restos** (puertas, parachoques, ruedas sueltas) | CC0 | sí | 28 / 1 952 / 3 124 | ● | Juguete: ancho 1.5 × largo 2.5–3.4 × alto 1.3–1.8 u; a escala real quedan de 2.2–3.2 m de alto con ventanas gigantes. Sirven los **restos** (debris) y como relleno lejano del atasco |
| **KayKit City Builder Bits** | 5 turismos | CC0 | sí | 1.2–1.3 k | ○ | Chibi |
| Kenney **Train Kit** 1.1 / **Watercraft** 2.1 | trenes (diésel, eléctricos, mercancías, **contenedores**) / **barcos de carga**, remolcadores, **contenedores**, pesqueros | CC0 | sí | 36 / 416 / 1 944 · 40 / 237 / 2 796 | ●● | Puerto y playa de vías: buena silueta desde arriba |
| Quitanieves, militar pesado | — | — | — | — | — | **Ningún pack CC0 encontrado**: el `snowplow`/`heavy_truck` de M10 siguen siendo procedurales (o *kitbash* sobre el camión de Quaternius + pala propia) |

### 2.4 Industria, puerto y rural

| Pack | Contenido | Accesible | Tris | Encaje |
|---|---|---|---|---|
| **Kenney City Kit Industrial** 1.0 (06‑2025) | 20 naves/fábricas, 4 **chimeneas industriales**, depósito | sí | 92 / 1 162 / 2 422 | ●● (chimeneas + humo = "vida") |
| **Kenney Watercraft** / **Train Kit** | barcos de carga, grúa no; contenedores, vías, vagones cisterna | sí | ver 2.3 | ●● |
| **Quaternius Farm Buildings** | graneros ×4, silo, casa‑silo, **molinos** ×2, **depósito de agua**, pozo, vallas ×2, gallinero | sí (USDA) | 188 / 2 176 / 7 827 | ●● |
| **Quaternius Survival** (53) | bidón, hacha, mochila, cepo, antorchas, radio, bombona, tienda, balsa, armas, latas, botiquín | sí (USDA) | 28 / 454 / 1 752 | ●● botín/props |

### 2.5 Personajes y animales (solo si son mejores que los nuestros)

| Pack | Veredicto |
|---|---|
| Quaternius **Ultimate Animated Animals** (lobo, ciervo, **venado**, zorro, **husky**, caballo ×2, vaca, toro, burro, alpaca, shiba; 1.8–3.7 k tris, riggeados y animados; USDA sí) | **Mejor que nuestros `wolf`/`deer` de piezas rígidas del slice.** Candidato fuerte para M9b (fauna) y para "vida" ambiental (zorros, perros abandonados). Requiere retarget a nuestro esqueleto cuadrúpedo o usar su rig tal cual (no comparte esqueleto con nada nuestro: aceptable para animales). |
| Quaternius **Farm Animal** (vaca, caballo, llama, cerdo, oveja, pug, cebra) | Útil en granjas (reestilizar). |
| Quaternius **Zombie Apocalypse Kit** (4 supervivientes, 4 zombis, 2 perros) / **Universal Base Characters** / KayKit Adventurers / Kenney Animated Characters | **No**: nuestros supervivientes HD (2.65 k tris, proporciones naturales, 4 parkas) y 42 zombis M4 ya son más coherentes con el look y comparten esqueleto/animaciones. Quaternius **UAL** sigue siendo la fuente de animaciones (doc 04/05). |
| Aves (cuervos, bandadas) | No hay pack CC0 específico en los espejos; bandadas como `GPUParticles3D` con malla de 30–60 tris y aleteo por vértice (08 §3.9) — procedural. |

### 2.6 Texturas, HDRI y otros

| Fuente | Qué aportaría | Accesible | Decisión |
|---|---|---|---|
| Poly Haven (HDRI, texturas nieve/hielo/asfalto) | cielos para reflejos, detalle de normal | **no** (3 dominios bloqueados); 10 HDRI 1k en three.js (ninguno nevado) | No imprescindible: la cámara no ve el cielo; ver 08 §3.6 |
| ambientCG (PBR CC0: `Snow0xx`, `Ice00x`, `Asphalt0xx`) | máscaras de ruido/detalle para el shader de nieve y de carretera | **no** | Opcional (G2c): 2–3 texturas de ruido/normal 512² en escala de grises; se pueden generar proceduralmente |
| Kenney Particle Pack (2D, CC0) | sprites de humo, chispas, nieve | sí (jam‑ready, `kenney-particle-pack`) | Útil para humo de chimeneas/incendios (08 §3.9) |
| Poly Pizza / OpenGameArt / Sketchfab | modelos sueltos | no | **No usar** salvo pieza concreta verificada CC0 (licencias mezcladas: CC‑BY dominante) |
| Synty (POLYGON City/Apocalypse) | ciudad completa | no (y de pago con EULA: prohíbe redistribuir y uso en datasets/desarrollo de IA generativa) | **No** (doc 05) |

---

## 3. Prueba práctica

### 3.1 Qué se descargó (fuera del repo)

`/tmp/claude-0/-home-user-Quotas/3c3b507e-0838-5643-8cd6-6e5a40202a08/scratchpad/g2_assets/`:

- `downloads/<pack>/` (Kenney, desde `jam-ready-assets` vía LFS, **SHA‑256 verificado** contra el puntero LFS):
  *City Kit Commercial* ×11 (5 rascacielos, 3 edificios, 2 *low‑detail*, toldo) + atlas y 2 variaciones;
  *City Kit Roads* ×11 (rectas, cruce, paso de cebra, barrera, puente + pilar, 2 farolas, barrera/cono de obra,
  pórtico de autovía); *Car Kit* ×12 (sedán, policía, ambulancia, basura, bomberos, reparto, furgoneta, SUV, taxi,
  2 camiones, tractor‑pala); *City Kit Industrial* ×4 (2 naves, chimenea grande, depósito); *Watercraft* ×3
  (contenedor, carguero, remolcador). Cada carpeta con su `License.txt`.
- `src/chibifire-stages_quaternius-stage/models/` (Quaternius USDA): *Downtown* ×3 edificios + 21 texturas,
  *Zombie Apocalypse Kit* (pickup, barrera, depósito de agua, contenedor) + atlas, *Cars* (SUV, policía),
  *Public Transport* (autobús), *Modular Streets* (farola doble), *Ultimate Animated Animals* (lobo, ciervo).
- `src/KayKit-City-Builder-Bits-1.0/` (oficial, completo).
- Censo de triángulos de **todos** los modelos de 12 packs Kenney (867 GLB), 11 packs Quaternius (456 USDA) y KayKit
  City (41): `out/tri_census_kenney.json`, `out/tri_census_quaternius.json`, `out/tri_census_kaykit_city.json`.

### 3.2 Resultados del pase (30 modelos; `out/winterize_report.json`)

| id | Fuente | Tris fuente → G2 | Medidas finales (m) | Escala | Sup. | Tiempo (s) total / AO |
|---|---|---|---|---|---|---|
| `tower_a` | Kenney skyscraper‑a (+10 plantas) | 1 292 → 12 247 | 14.9 × 14.9 × 69.6 | ×10.98 (planta 0.346 u → 3.8 m) | 2 | 2.0 / 1.3 |
| `tower_b` | skyscraper‑b (+14) | 1 592 → 16 227 | 14.9 × 14.9 × **102.3** | ×10.95 | 2 | 2.7 / 1.8 |
| `tower_c` | skyscraper‑c (+8) | 1 704 → 13 840 | 13.7 × 14.8 × 74.0 | ×10.67 | 2 | 2.3 / 1.5 |
| `tower_d` | skyscraper‑d (+12) | 1 892 → 15 110 | 13.7 × 14.8 × **104.1** | ×10.69 | 2 | 2.6 / 1.7 |
| `tower_e` | skyscraper‑e (+6) | 1 156 → 6 446 | 12.8 × 12.3 × 63.3 | ×9.92 | 2 | 1.2 / 0.8 |
| `office_a` / `office_f` | Kenney building‑a / ‑f | 1 252 → 4 508 · 1 794 → 6 421 | 11.5 × 12.2 × 16.8 · 10.9 × 13.4 × 22.0 | ×13 | 2 | 0.7 · 1.0 |
| `factory_a` | Kenney Industrial building‑a | 2 046 → 7 210 | 27.1 × 16.1 × 19.1 | ×13 | 2 | 1.2 |
| `brownstone_s` / `_m` | Quaternius Downtown (ejemplos) | 18 344 → 20 152 · 25 612 → 28 040 | 12.5 × 14.5 × 17.0 · 15.1 × 13.1 × 25.0 | ×1 | 2 | 13.2 · 6.8 |
| `kaykit_bldg_e` | KayKit building_E | 1 356 → 5 204 | 14.1 × 14.0 × 16.4 | ×7 | 2 | 1.3 |
| `q_suv` / `q_cop` | Quaternius Cars | 3 294 → 4 114 · 3 232 → 4 064 | 2.4 × 4.7 × 1.7 · 2.3 × 4.9 × 1.6 | largo 4.7/4.9 | 3 | 0.9 |
| `q_pickup` | Quaternius Zombie Kit | 6 432 → 8 116 | 2.4 × 5.3 × 1.9 | largo 5.3 | 2 | 1.6 |
| `k_sedan`, `k_police`, `k_taxi`, `k_van`, `k_ambulance`, `k_garbage` | Kenney Car Kit | 2 032–3 124 → 2 656–3 756 | 2.6 × 4.4 × **2.2** (sedán) … 3.5 × 7.5 × 3.5 | largo real | 2 | 0.9–1.5 |
| `kk_sedan` | KayKit car_sedan | 1 222 → 1 696 | 2.0 × 4.4 × 1.7 | ×4.69 | 1 | 0.6 |
| props | farolas (K/Q), barreras (K/Q), pórtico, contenedor, depósito de agua, chimenea | 60–2 486 → 130–4 780 | — | — | 1–3 | ≤ 0.5 |

Total: **30 GLB en 48 s** (2 núcleos), 10 MB (media 330 KB). Validación: los 30 cumplen el formato (JSON del GLB:
solo `POSITION`/`NORMAL`/`COLOR_0` VEC4, 0 imágenes, materiales ⊂ {`palette_vcol`, `window`, `glass`,
`emissive_lamp`}) y se **importan en Godot 4.7.2 con 0 errores** en un proyecto desechable (`godot --headless
--import` + script que instancia cada escena: superficies y tris iguales a los de Blender, alfa de AO conservado).
Faltan, a propósito, `Col*`, anclas y la separación `Wheel*`/`Glass` de los vehículos (§4.2). Los mismos modelos con sus texturas originales
("antes", exportados con la misma transformación) ocupan 66 MB, de los que 35.7 MB son **un solo** edificio de
*Downtown* (texturas 2k–4k con normales).

### 3.3 Previews (Cycles, 1280 × 720, 40–48 muestras + denoise, cámara del juego salvo indicación)

Carpeta: `/tmp/claude-0/-home-user-Quotas/3c3b507e-0838-5643-8cd6-6e5a40202a08/scratchpad/g2_assets/previews/`

| Fichero | Qué muestra |
|---|---|
| `sheet_vehicles_before_after.jpg` (`vehicles_{before,after}_gamecam24.png`) | 6 vehículos (Quaternius SUV/policía/pickup, Kenney sedán/ambulancia, KayKit sedán) + superviviente como escala: CC0 tal cual ↔ `winterize` |
| `sheet_props_before_after.jpg` | farolas Kenney/Quaternius, barreras, pórtico de autovía, contenedor, depósito de agua |
| `sheet_buildings_gamecam24.jpg`, `sheet_buildings_overview.jpg` | oficina Kenney + *brownstone* Quaternius + SUV a 24 m; fila de 5 edificios (Kenney, Quaternius, KayKit, industrial) en vista general |
| `sheet_city_gamecam24.jpg` (`city_before_gamecam24.png` ↔ `city_after_day_gamecam24.png`) | **bloque de ciudad** (avenida de 4 carriles con atasco, cruce con accidente, barreras de policía, farolas, supervivientes con fogata, zombis) a la cámara del juego |
| `sheet_city_aerial.jpg` (`city_before_aerial.png` ↔ `city_after_day_aerial.png`) | el mismo bloque a 150 m: skyline de 7 torres de 63–104 m |
| `city_after_day_close.png`, `city_after_night_close.png` | vista cercana (13 m, pitch 30°) |
| `sheet_city_day_night.jpg`, `city_after_night_{gamecam24,aerial}.png` | noche: ventanas encendidas por celdas (30 %), farolas, fogata |
| `sheet_stages_q_pickup.jpg`, `sheet_stages_office_f.jpg`, `sheet_stages_tower_c.jpg` | las etapas del pase en un mismo encuadre: CC0 tal cual → color + gradación → + intemperie y nieve → + AO (final) |
| `city_tower_{occluded,fade}_gamecam24.png`, `city_tower_camera_inside{,_fade}_gamecam24.png` | el jugador junto a una torre de 100 m (solo se ve su base), el "fundido de edificio alto" propuesto en 08 §3.1 y el caso en que la cámara queda **dentro** de la torre (imagen negra) y su versión con fundido |
| `godot_city_day.png`, `godot_city_night.png`, `godot_city_night_compat.png`, `godot_tower_{occluded,fade}.png` | los mismos `.glb` en **Godot 4.7.2** con los shaders del juego (`world_vcol`, `terrain`) y los prototipos G2 (ventanas por celdas, fundido): Forward+ (lavapipe) y Compatibility (llvmpipe); cifras en 08 §5.0 |

### 3.4 Lo que se aprendió (por pack)

1. **Kenney City Kit**: el atlas‑paleta hace la conversión **exacta** (131–177 colores distintos por torre, 1 material).
   La escala es de maqueta y **no uniforme entre packs** (planta = 0.346–0.383 u en torres; 0.15–0.45 u en comerciales):
   hay que escalar **por altura de planta detectada** (histograma de alturas de vértice → periodo) y no por un factor fijo.
   Las torres son periódicas por planta: repetir la banda central da rascacielos de 100 m sin estirar ventanas
   (`extend_tower`, soldadura exacta). Detalle de cornisas y remates en azotea: buena lectura desde arriba.
2. **Quaternius** (*Cars*, *Zombie Kit*): **metros reales**, frente −Y tras importar (= nuestro contrato), materiales con
   nombre (`Windows`, `Headlights`, `TailLights`, `BlueLights`) → clasificación sin heurística. Es el mejor encaje.
3. **Quaternius Downtown**: la forma es la mejor (molduras, cornisas, escaleras), pero el color vive en texturas
   tileables; a color de vértice queda un tono medio por cara (§4.3). 18–45 k tris por edificio de ejemplo.
4. **Kenney Car Kit / KayKit**: proporciones de juguete; el pase de color y nieve no lo arregla. Descartar para primer
   plano (§3.5).
5. **Ventanas**: en Kenney/KayKit son geometría pintada con los azules del atlas → la regla de tono (190–236°) acierta
   en edificios **si se limita a caras verticales** (|n.z| < 0.35: los remates de peto de Kenney usan el mismo azul y de
   noche "brillaban"); en coches el azul es **pintura** (el pickup azul salía "todo cristal"): en vehículos solo por nombre de
   material o por la muestra exacta del pack (`#606275` en Kenney).
6. **Nieve**: las losas redondeadas sobre islas planas (tejados, cornisas, capós) + ventisqueros en la base son lo que
   más "invierno" aporta; junto con las plantas añadidas multiplican los tris ×5–10 en torres (14–107 losas: cornisas de cada planta; las tiras de < 0.6 m solo se pintan) y ×1.2–1.4 en coches. Presupuesto y alternativa barata
   (nieve solo por shader en cornisas pequeñas) en §4.4.

### 3.5 Veredicto de estilo

| Uso | Pack recomendado | Por qué |
|---|---|---|
| Rascacielos y torres de oficinas | **Kenney City Kit Commercial** (torres) + sus `low-detail` para lejanía | limpios, periódicos, baratos, azotea legible; con nieve y gradación quedan "de la familia" |
| Edificios de media altura del centro | **Quaternius Downtown** (piezas) **ensamblado por nuestro `kit.py`** con color de vértice | proporciones reales; usando piezas (no los ejemplos de 45 k) el coste baja a nuestro presupuesto de 6–14 k |
| Comercios de barrio / pueblo | nuestro kit M6a + fachadas/letreros de Quaternius Textured Buildings y Kenney Modular Buildings | coherencia con casas enterables y corte |
| Industria y puerto | Kenney Industrial + Watercraft + Train; contenedores de Quaternius | siluetas claras desde arriba |
| Coches del atasco y aparcados | **Quaternius Cars + Zombie Kit** (primer plano); Kenney *debris* y coches solo a > 40 m | proporciones reales |
| Mobiliario urbano | Quaternius Modular Streets (farolas, semáforos, señales) + Zombie Kit (barreras, conos, bolsas, palés) + Kenney Roads (pórticos, barreras de autovía, puentes) | tema y escala |
| Personajes, zombis, vegetación, cabaña/casas enterables | **nuestros** (procedural HD) | contrato de esqueleto, corte, anclas; ya son mejores |
| Fauna | Quaternius Ultimate Animated Animals (M9b) | mejores que los del slice |
| KayKit (todo), Kenney Car Kit en primer plano, Public Transport del espejo | **no** | chibi/juguete/colores perdidos |

La frase corta para el dueño: **"la ciudad y el tráfico pueden salir de librerías; la gente, la nieve y la luz son
nuestras"**.

---

## 4. Pipeline `winterize` (diseño para producción)

Prototipo: `…/scratchpad/g2_assets/scripts/winterize.py` (≈ 830 líneas, importa `blender/lib` del repo sin
modificarlo). Render: `render_g2.py`. Propuesta de ubicación en el repo: `blender/third_party/winterize.py` +
`blender/third_party/packs/<pack>.json` (config por pack) + `blender/verify_third_party.py`.

### 4.1 Etapas

| # | Etapa | Qué hace (prototipo) | Producción |
|---|---|---|---|
| 1 | **Import** | `import_scene.gltf` / `import_scene.fbx` / `wm.obj_import` / `wm.usd_import`; hornea transformaciones de padres, quita empties/armatures, une en una malla | igual; guardar la jerarquía cuando el contrato la pide (vehículos: `Wheel*`, `Glass`, `Door*`) |
| 2 | **Conform** | ejes (frente −Y), origen = centro de la base, **escala por altura de planta** (`floor:3.8`), por largo (`len:4.7`) o fija; `extend_tower` repite la banda de una planta N veces | + snap a la rejilla de 2 m del kit (C8) en edificios; tabla de medidas objetivo por familia |
| 3 | **Color** | por esquina: muestrea `Base Color` (textura en la UV de la esquina, 20 % hacia el centroide para no sangrar entre muestras del atlas; o color del material). Texturas tileables (*Downtown*): una media por cara sobre una copia 64² filtrada | igual; caché de muestras por pack → tabla de "colores de pack" |
| 4 | **Clasificar** | por nombre de material (`window`/`glass`/`interior` → `window` o `glass`; `headlight`/`light`/`lamp` → `emissive_lamp`; `taillight`/`brake` → `lamp_red`) y, en atlas, por muestra (azules de ventana en edificios; `#606275` en coches Kenney) | + lista explícita de muestras por pack en su JSON (sin heurística en producción) |
| 5 | **Gradación** | OKLab: `L' = 0.17 + 0.67·L` (blanco → `#CECAC4`, nunca el azul de la nieve; negro `#303034` → `#3D424A`); croma × 0.45–0.76 (más en colores fuertes y en pintura de coche); neutros medios hacia frío (`b −0.012`), casi blancos hacia crema (`b +0.010`) | + **snap opcional a la paleta** v2.1 cuando ΔE_ok < 0.03, y registro de los colores restantes como `ext_<pack>_<n>` (tabla JSON) para que el verificador siga comprobando "color de la paleta" |
| 6 | **Intemperie** | por vértice en espacio mundo: ±6 % de valor con ruido (1 m y 25 cm), **suciedad** que sube del suelo (1.8 m edificios, 0.9 m coches), **churretes** verticales bajo cornisas, **escarcha** en caras inclinadas (0.25 < n.z < 0.75), **óxido** en bajos de coche | igual; opcional exportar la máscara en `UV2` (x = suciedad, y = escarcha) si el shader G2 la quiere modular por clima (08 §3.2) |
| 7 | **Nieve** | islas planas (n.z ≥ 0.8) ≥ 0.6 m² (0.25 en coches) → **losa**: copia, crece 2–4 cm (cornisa), extruye `t = 0.05 + 0.03·√A` (0.06–0.32 m; coches 0.05–0.16), bisela el borde (3 segmentos, perfil circular), subdivide y levanta la cara con ruido (35 % de `t`), sombreado suave; caras pequeñas → pintadas `snow`; edificios → **ventisqueros** en la base (0.55 m a barlovento, 0.3 a sotavento); coches → **montículo** que los entierra hasta el paso de rueda | + reutilizar `hd.pillow` en tejados rectangulares, carámbanos (`props/icicles`) en aleros > 1 m, nieve de barlovento según viento dominante del mapa |
| 8 | **AO** | `lib/hd.bake_ao` (el del juego): 40 rayos (24 si > 40 k tris), 1.2 m edificios, 0.3–1.0 m resto, plano de suelo | igual; torres: AO por planta tipo + copia (evita hornear 100 m) |
| 9 | **Export** | `lib/export.export_kwargs()` (COLOR_0 RGBA, sin UV, sin imágenes), materiales `palette_vcol` + excepciones | + `.import` (plantilla `prop`), `extras` con `source_pack`, `source_file`, `license`, `winterize_version`; `Col*` de colisión generados (cajas por AABB de planta/fachada) |
| 10 | **Verificar** | — | `verify_third_party.py`: contrato §16 de ASSET_SPEC_V2 salvo "color exacto de paleta" (sustituido por **gama**: croma OKLab ≤ 0.09, L ∈ [0.17, 0.84], ningún RGB de fachada dentro de ΔE 0.04 de `snow`), presupuesto de tris por familia, AO presente, sin caras traseras visibles desde la cámara del juego, licencia en el manifiesto |

### 4.2 Contrato: qué cambia (propuesta de sección "G2" para ASSET_SPEC_V2)

- **Nueva familia `third_party`** (`assets/models/city/<familia>/<id>.glb`): mismo formato (COLOR_0 RGBA, AO en
  alfa, sin UV, `palette_vcol` + `window`/`glass`/`emissive_lamp`), **RGB graduado sin exigir paleta exacta** (gama
  de §4.1‑10); extras obligatorios de procedencia.
- **Rascacielos**: grupos `Tower_Base` (0–12 m, corte si es enterable: normalmente no), `Tower_Shaft`, `Tower_Top`
  (+ `Roof_Snow`), `Windows` (material `window` con coordenadas de celda para el shader de ventanas de 08 §3.4), anclas
  `Light_Beacon` (baliza roja de azotea), `Smoke_*` (chimeneas/HVAC), `Col*` por tramo. Una `low_*.glb` de
  150–400 tris por torre (impostor/HLOD, puede salir de los `low-detail-building-*` de Kenney).
- **Vehículos de atasco** (estáticos, M6b/M7 "restos"): `Body` + `Glass` + `Snow` en objetos separados para poder
  "limpiar" la nieve al saquear; anclas `Loot`, `FuelCap`, `Headlight_L/R` (luces de emergencia parpadeando = vida).

### 4.3 Color de vértice vs atlas de textura (argumento)

| Criterio | Color de vértice (elegido) | Atlas / texturas originales |
|---|---|---|
| Fidelidad | **exacta** para atlas‑paleta (Kenney, KayKit, Quaternius Zombie Kit/coches: cada cara muestrea una muestra plana o un degradado suave → se conserva por esquina) | exacta en todos; imprescindible solo para texturas **tileables con detalle pintado** (ladrillo, pizarra, ornamentos de *Downtown*) |
| Detalle a 24 m (1 px ≈ 1.4–1.6 cm) | lo que es geometría se ve (marcos, cornisas); el ladrillo pintado (6.5 cm ≈ 4 px) se pierde | ladrillo visible como textura fina; a 38 m ya es ruido |
| Nieve/escarcha/AO | se hornean en la misma malla; el shader `world_vcol` G1 funciona sin tocar | hay que duplicar el shader (versión con `sampler2D` + UV) y la AO horneada en alfa sigue valiendo |
| Draw calls / batching | **1 material compartido** con todo el mundo (C2) | 1 material por pack/atlas (Kenney 1, Downtown 6–9 por edificio: `MI_Brick`, `MI_Trim`, `MI_Concrete`, `MI_FakeInterior_*`…) |
| Memoria / descarga | 10 MB para 30 modelos; sin VRAM de texturas | 66 MB (35.7 MB un edificio de *Downtown*: 2k–4k + normales); crítico en Web |
| Gradación de color | horneada y verificable offline | en el shader (LUT) o recolorear las texturas: más trabajo y menos control por pieza |
| Contrato y verificador | el de siempre (+ gama) | nuevo camino completo (UV, imágenes, compresión VRAM, mipmaps) |

**Decisión**: color de vértice por defecto. Excepción posible y **aplazada**: un set "héroe" de *Downtown* texturizado
(fachadas de la calle principal de la ciudad) si en G2b las capturas muestran que el ladrillo pintado se echa de
menos; entonces `world_tex.gdshader` = `world_vcol` + `texture()` en UV0, texturas reducidas a 512² BPTC/ETC2 y
**recoloreadas offline** con la misma gradación OKLab.

### 4.4 Presupuestos propuestos (tris con nieve)

| Familia | Fuente | G2 (objetivo) | Máx. | Nota |
|---|---|---|---|---|
| Rascacielos 60–110 m | 1.1–1.9 k | **8–16 k** | 18 k | + `low_*` 150–400 tris; la nieve de cornisas pequeñas por shader si se pasa |
| Edificio medio (4–8 plantas) | 1–5 k (Kenney) / piezas Downtown | 4–12 k | 14 k | = casa del kit M6a |
| Edificio de ejemplo *Downtown* completo | 18–45 k | — | — | **no** usar tal cual: re‑ensamblar piezas |
| Coche de atasco | 2–6.5 k | 2.5–8 k | 9 k | = presupuesto v2.1 de vehículo |
| Prop urbano | 60–2.5 k | 0.1–2.5 k | 3 k | farola Quaternius 2.5 k: vale por su silueta (MultiMesh) |

---

## 5. Licencias y atribución: `assets/third_party/`

CC0 no obliga a atribuir, pero **sí** a poder demostrar la procedencia (un espejo podría contener algo que no sea
CC0). Propuesta:

```
assets/third_party/
  manifest.json                 ← fuente de verdad (lo genera y verifica winterize)
  CREDITS.md                    ← generado del manifiesto; lo muestra la pantalla de créditos
  kenney-city-kit-commercial/License.txt      ← copia literal del License.txt del pack
  kenney-city-kit-roads/License.txt
  quaternius-zombie-apocalypse-kit/LICENSE.txt
  …
blender/third_party/
  packs/<pack>.json             ← config de winterize por pack (escala, reglas de ventana, muestras)
  fetch.py                      ← descarga con URL + SHA-256 fijados a una caché fuera del proyecto
                                   (~/.cache/ventisca/third_party o blender/third_party/_src con .gdignore y en .gitignore)
```

Entrada del manifiesto (ejemplo real de esta prueba):

```json
{
  "id": "kenney-city-kit-commercial",
  "title": "City Kit Commercial", "version": "2.1", "author": "Kenney (www.kenney.nl)",
  "license": "CC0-1.0", "license_file": "kenney-city-kit-commercial/License.txt",
  "official_url": "https://kenney.nl/assets/city-kit-commercial",
  "fetched_from": {"repo": "https://github.com/series-ai/jam-ready-assets", "commit": "<sha del clone>",
                   "path": "kenney-city-kit-commercial/3D/city/Models/GLB format/", "via": "git-lfs media"},
  "files": [{"src": "building-skyscraper-b.glb", "sha256": "…", "bytes": 138480}],
  "outputs": [{"glb": "assets/models/city/towers/tower_b.glb", "modifications":
               "rescaled x10.95, +14 floors, vertex colours graded, snow, AO (winterize 0.1)"}],
  "attribution": "City Kit Commercial by Kenney (CC0)"
}
```

Reglas: (1) nada entra en `assets/` sin entrada en el manifiesto; (2) `verify_third_party.py` falla si falta el
`License.txt` o si el `sha256` de la fuente no coincide; (3) solo se aceptan **CC0** (y MIT/BSD con su aviso copiado);
**nunca CC‑BY‑NC/ND, EULAs de tienda ni "free for personal use"**; (4) atribución voluntaria en créditos para Kenney,
Quaternius y Kay Lousberg (buena práctica; el juego es público); (5) los paquetes fuente **no** se versionan en el
repo (solo el `.glb` resultante): se re‑descargan con `fetch.py`.

---

## 6. Dominios a permitir (configuración de red del entorno)

| Prioridad | Dominios | Desbloquea | Por qué merece la pena |
|---|---|---|---|
| **1** | `kenney.nl` | Todos los packs Kenney oficiales, última versión, ZIP con GLB/FBX/OBJ/**Blend** + `License.txt`: City Kit Commercial/Roads/Industrial/Suburban, Car Kit, Survival, Building Kit, Modular Buildings, Watercraft, Train, Holiday, **Particle Pack**, Nature Kit | verificación en origen; hoy dependemos de un espejo de terceros |
| **2** | `quaternius.com`, `drive.google.com`, `drive.usercontent.google.com`, `www.googleapis.com` | Quaternius: páginas de pack + **descargas en Google Drive** (packs clásicos: Cars, Public Transport con sus colores, Modular Streets, Buildings, Farm Buildings, **Ultimate Animated Animals**, Survival, Zombie Apocalypse Kit, UAL) en FBX/OBJ/**glTF**/Blend | formatos originales (el USD del espejo perdió colores en algún pack) |
| **3** | `itch.io`, `api.itch.io` y el CDN de descargas de itch (la API redirige a un *bucket* de almacenamiento; registrar el host exacto en el primer intento) | Quaternius **MegaKits** (solo en itch: **Downtown City MegaKit completo** con sus 300+ piezas, Medieval Village, Modular Sci‑Fi…), KayKit **Complete Collection** y packs nuevos, espejos de Kenney | *Downtown* completo es el mejor kit urbano CC0 existente; requiere API key de itch (gratuita) para automatizar |
| 4 | `polyhaven.com`, `api.polyhaven.com`, `dl.polyhaven.org` | HDRI CC0 (cielos nublados/nevados para reflejos y menús), texturas de nieve/hielo/asfalto, modelos | opcional (G2c) |
| 5 | `ambientcg.com` (+ el host al que redirige `/get`) | PBR CC0 (Snow, Ice, Asphalt, Concrete) | opcional: máscaras de detalle |
| — | `godotengine.org`, `docs.godotengine.org` | documentación y notas de versión | comodidad de investigación (hoy se usa el XML de `godotengine/godot`) |
| no | `poly.pizza`, `opengameart.org`, `sketchfab.com`, `huggingface.co`, `cdn.jsdelivr.net` | licencias mezcladas o nada que no dé GitHub | no hace falta |

---

## 7. Coste y plan de adopción

| Trabajo | Horas de agente (Opus) |
|---|---|
| Portar `winterize` al repo (`blender/third_party/`), config por pack, `verify_third_party.py`, manifiesto + `fetch.py` | 6–8 |
| Torres: 5 Kenney × 2–3 variantes (alturas/colores con `variation-*.png`) + `low_*` + colisiones + anclas | 4 |
| Edificios medios: re‑ensamblar 6–10 edificios de piezas *Downtown* con `kit.py` (cuando esté el pack completo) | 10–14 |
| Vehículos de atasco: 10 modelos Quaternius + 6 restos Kenney, con `Glass`/`Snow` separados y anclas | 5 |
| Mobiliario urbano, industria, puerto (≈ 40 props) | 5 |
| Fauna Quaternius (lobo, ciervo, zorro, husky) al contrato cuadrúpedo | 6–8 (M9b) |
| **Total G2‑assets** | **≈ 36–44 h (4–5 pases de Opus)**; sin el *Downtown* completo, ≈ 26 h |

Riesgos: (R1) **coherencia** — mezclar Kenney + Quaternius + lo nuestro: mitigado por gradación única, misma nieve
y AO, y reglas de §3.5; (R2) **presupuesto** — la nieve multiplica tris ×2–4 en edificios: HLOD y nieve de cornisa por
shader (08); (R3) **licencia de espejos** — manifiesto con SHA‑256 y re‑verificación contra el oficial al abrir
dominios; (R4) **tamaño del mapa** (6 × 6 km, PLAN C6 dice 3 × 3): contenido urbano concentrado en la ciudad; el resto
sigue procedural.

---

## Fuentes

- Kenney — [City Kit Commercial](https://kenney.nl/assets/city-kit-commercial), [City Kit Roads](https://kenney.nl/assets/city-kit-roads), [City Kit Industrial](https://kenney.nl/assets/city-kit-industrial), [Car Kit](https://kenney.nl/assets/car-kit) (páginas bloqueadas aquí; licencias leídas del `License.txt` de cada pack en [series-ai/jam-ready-assets](https://github.com/series-ai/jam-ready-assets)); [KenneyNL/Starter-Kit-City-Builder](https://github.com/KenneyNL/Starter-Kit-City-Builder), [KenneyNL/Starter-Kit-Racing](https://github.com/KenneyNL/Starter-Kit-Racing).
- Quaternius — [Downtown City MegaKit](https://quaternius.com/packs/downtowncitymegakit.html) / [itch](https://quaternius.itch.io/downtown-city-megakit) (descripción vía WebSearch: "300+ modular environment pieces… Boston/NYC style city blocks… CC0… .FBX, .OBJ and .glTF"), [Cars Bundle (poly.pizza)](https://poly.pizza/bundle/Cars-Bundle-FE5IWe6OMk), espejo USD [chibifire-stages/quaternius-stage](https://github.com/chibifire-stages/quaternius-stage) (CC0; scripts `drive_fetch.py`/`itch_fetch.py` documentan que los packs clásicos están en Google Drive y los MegaKits solo en itch.io), [beep2bleep/FreeAssetsByKenneyNLandQuaternius](https://github.com/beep2bleep/FreeAssetsByKenneyNLandQuaternius), [J-Ponzo/gltf-universal-animation-library](https://github.com/J-Ponzo/gltf-universal-animation-library).
- KayKit — [KayKit-Game-Assets (GitHub)](https://github.com/KayKit-Game-Assets), [City Builder Bits](https://github.com/KayKit-Game-Assets/KayKit-City-Builder-Bits-1.0) (`LICENSE.txt` CC0).
- Poly Haven / three.js HDRI: [mrdoob/three.js examples/textures/equirectangular](https://github.com/mrdoob/three.js/tree/dev/examples/textures/equirectangular).
- Datos propios: `…/scratchpad/g2_assets/out/{winterize_report,tri_census_kenney,tri_census_quaternius,tri_census_kaykit_city}.json`, `progress.md`.
