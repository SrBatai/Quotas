# 05 — Gráficos: arte 3D, estrategia de assets y guía de arte v2.1

> Proyecto VENTISCA (Godot 4.7.2, cámara alta tipo isométrica: pitch −48°, yaw 45°, FOV 36°, 16–38 m, 27 m por
> defecto — `scripts/data/balance.gd`). Arte 100 % procedural con Blender 5.0.1 (`bpy`).
> Fecha: 2026‑09‑24/25. Autor: agente de arte 3D (Opus). Estado: **investigación cerrada + prueba de concepto (PoC)
> construida, verificada y renderizada** (§3).
> Pedido del usuario: *«hay que investigar para mejorar los gráficos, quizás usar ASSETS mejores. En estas imágenes se
> ve genial y perfecto»* (5 capturas de referencia de un juego de supervivencia invernal).
> Complementa `04_arte_animacion_pipeline.md` (pipeline, esqueleto, color de vértice) y `06_graficos_render.md`
> (agente de render: luz, tonemapping, SSAO, shader de nieve, mapa de huellas). Este documento cubre **la geometría,
> la paleta y los assets**; lo que es de iluminación/post se marca como tal y se deja a 06.

---

## 0. Resumen ejecutivo

| Pregunta | Respuesta |
|---|---|
| ¿Por qué la referencia se ve mejor? | Mitad **arte** (formas de nieve gruesas y redondeadas, densidad de detalle en la arquitectura, pinos de estrella casi cubiertos de nieve, árboles desnudos con muchas ramas finas, personaje de proporciones naturales y ropa oscura, paleta desaturada, AO) y mitad **render** (nieve nunca blanca, sol bajo a contraluz, ambiente azul, SSAO, sombras suaves: doc 06). |
| ¿Comprar/descargar assets mejores? | **No como base.** Ningún paquete compatible en licencia tiene el estilo de la referencia *y* nuestro contrato (partes de corte, anclas, colisión, esqueleto `SkeletonProfileHumanoid`, color de vértice sin texturas). Kenney/KayKit/Quaternius (CC0) son más *juguete* que lo que ya tenemos; Poly Pizza mezcla licencias (≈ 69 % CC‑BY); Poly Haven es fotorrealista; Synty es de pago con EULA que prohíbe redistribuir y restringe el uso con programas de IA generativa. Además, **desde este entorno solo GitHub (raw/releases), npm y PyPI son accesibles**: kenney.nl, quaternius.com, itch.io, poly.pizza, polyhaven y syntystore devuelven 403. |
| Recomendación | **Procedural HD en `bpy` (estrategia a) para todas las familias visibles**, con reglas nuevas (guía v2.1, §4): chaflanes con normales endurecidas en lo duro, nieve como "almohadas" subdivididas con bordes gruesos redondeados y cornisas, sombreado suave en nieve/tela/corteza, **AO horneada en `COLOR_0.a`**, paleta v2.1 desaturada. Externo solo donde ya estaba decidido: **Quaternius UAL (CC0, espejo en GitHub descargable aquí) para animaciones difíciles**, y CC0 de Kenney/KayKit **solo como *blockout* temporal**. |
| ¿Funciona? | Sí: PoC con cabaña, 2 pinos, árbol desnudo, loseta de terreno con camino/bermas/ventisqueros/huellas y superviviente de proporciones naturales (4 variantes) **en el mismo esqueleto**: `humanoid_loco.glb` se reproduce sin cambios (verificado en Blender y en importación Godot 4.7.2, 0 errores). Comparación antes/después: `compare_old_vs_new_gamecam24.png` (§3.4). |
| Coste de migración | 33 assets actuales: **≈ 26–28 h de agente** + librería/verificadores ≈ 6 h = **32–34 h (4–5 pases de Opus)**; solo los "héroes" del claro ≈ 10 h. Plan futuro (zombis, kit de pueblo, vehículos, props): **+8–10 días de agente** sobre el plan v2 (≈ +25–40 % por familia). Rendimiento: tris ×3–12 por asset, superficies/draw calls iguales (§5). |

---

## 1. Análisis de brecha (referencia vs VENTISCA hoy)

Material comparado: las 5 capturas de referencia (recortes ampliados en `…/scratchpad/lookdev_art/ref/`), nuestras
capturas (`docs/screenshots/*.png`, `…/scratchpad/shots_m1/*.png`) y el superviviente M1
(`…/scratchpad/previews_m1/variants_front.png`). Escala de lectura: a 27 m y 1080p la cámara ve ≈ 17.5 m en vertical
→ **≈ 62 px/m** (104 px/m a 16 m, 44 px/m a 38 m); un humano de 1.8 m ocupa ≈ 75 px (vertical × cos 48°).
**1 px ≈ 1.6 cm**: lo que mide < 5 cm (3 px) solo se ve como brillo/sombra, no como forma.

### 1.1 Edificios (cabaña)

| Aspecto | Referencia | Nuestro `cabin.glb` (1 674 tris, 10 superficies visibles) |
|---|---|---|
| Tejado | Oscuro (carbón‑ciruela) con **juntas alzadas** (paneles), nieve en **terrones** redondeados sobre el tejado oscuro y **losas gruesas (~20–25 cm) con borde redondeado** en los faldones bajos, que **vuelan sobre el alero** (cornisa). El contraste oscuro/blanco es lo que dibuja la casa. | Losa blanca continua, 12 cm, aristas vivas, cubre todo el faldón: el tejado es un plano blanco sin forma ni contraste. |
| Porche | **Hastial propio** sobre la entrada con cercha abierta (tirante, pendolón, tornapuntas), postes con jabalcones, tablas de suelo, escalones, barandilla de balaustres densos, farol. | Tejadillo a un agua que tapa el porche; postes finos; balaustres cada 0.30 m. |
| Fachada | Tablilla solapada azul‑gris desaturado, **cantoneras y marcos crema**, ventana grande **2×3 con marco grueso, alféizar y nieve en el alféizar**. | Azul cielo saturado `#5D7FA6`, tablilla de 0.30 m casi invisible, ventana con 1 parteluz, sin nieve en repisas. |
| Chimenea | Ladrillo/piedra con **hiladas visibles** y remate con nieve. | Caja roja lisa. |
| Suelo alrededor | **Ventisqueros apoyados en las paredes**, bancos de nieve junto a los escalones. | Nada: la casa "flota" sobre la nieve. |
| Sombreado | Madera nítida con **brillo en aristas**; nieve suave; **oclusión** bajo aleros/porche. | Todo facetado, sin AO. |

### 1.2 Pinos

| Referencia | `pine_a/b/c` (178–226 tris) |
|---|---|
| 6–7 pisos en **estrella** (7–9 puntas, puntas caídas y anchas), **casi totalmente cubiertos de nieve** con un canto visible; el verde oscuro azulado solo asoma en las **puntas y el envés**; tronco visible bajo el primer piso; facetas nítidas (aquí el facetado **sí** es parte del estilo). | 3–4 conos de 8 lados con bandas verdes saturadas grandes (`#4B8A55`) y un collar fino de nieve: lectura de "árbol de Navidad de juguete". |

### 1.3 Árboles desnudos

| Referencia | `dead_tree` (178 tris) |
|---|---|
| Tronco gris azulado oscuro, **3 niveles de ramas**, decenas de ramillas finas (2–4 px de grosor), copa extendida, algo de nieve sobre las ramas gruesas. | Tronco inclinado marrón rojizo con 7 palos rectos de 4 lados: se lee como una estaca. |

### 1.4 Terreno, caminos y huellas

| Referencia | Hoy |
|---|---|
| Nieve **lisa** con ondulaciones grandes; **caminos hundidos con bermas** largas y suaves (las diagonales que cruzan la escena); ventisqueros; **huellas profundas con reborde** (anillos) en rastro alternado. | Terreno con normales por cara (`dFdx/dFdy`) en malla de 1 m: facetas visibles, nieve "arrugada"; sin caminos ni bermas; huellas planas. (La solución de shader/huellas es de 06; la forma y las reglas de arte, aquí.) |

### 1.5 Personaje

| Referencia | `survivor_*.glb` M1 (954 tris) |
|---|---|
| Proporciones naturales (≈ 7.5 cabezas), **parka oscura** (marrón/gris) hasta medio muslo con **cuello de piel** y capucha, gorro oscuro, **mochila grande con esterilla**, pantalón oscuro, botas marrones con calcetín claro. Pequeño y oscuro: contrasta con la nieve. | Cabeza caja de 0.30 m (≈ 1/5.5 de la altura), plumífero rojo/azul/verde/mostaza saturado, bufanda amarilla, pompón, pantalón azul eléctrico: lectura "Lego". |

### 1.6 Vehículo (pickup)

Referencia: caja oliva‑gris desaturada, guardabarros redondeados, ruedas grandes, **losas de nieve redondeadas en
capó, techo y bordes de la caja**. Nuestro `pickup_truck`: verde saturado, nieve como caras blancas planas, sin
chaflanes. (No entra en la PoC; ver receta en §4.3 y coste en §5.)

### 1.7 Paleta y valores

La referencia usa **azules grises desaturados** (paredes, sombras), **verdes apagados casi negros** (pinos),
**acentos cálidos de madera** (tarima, cartel) y **crema** en molduras; la nieve iluminada es **azul pastel** al
~80 % de luminancia, nunca blanca (medido en 06 §2). Nosotros: primarios saturados en personajes y paredes, verdes
de hierba, nieve blanca pura.

### 1.8 Qué parte de la brecha NO es arte (doc 06)

Exposición/tonemapping (nieve nunca quemada), sol bajo a **contraluz** desde arriba‑derecha de pantalla (sombras
hacia la cámara), ambiente azul, niebla del color del cielo, SSAO, sombras PCSS, destellos y *rim* de la nieve, derrame
cálido de ventanas de noche. Los assets v2.1 están hechos para ese look (AO horneada, nieve `#CDDEF5`, normales
propias), pero sin 06 la mitad de la mejora no aparece.

---

## 2. Estrategia de assets

### 2.1 (a) Procedural de mayor fidelidad en `bpy` — técnicas evaluadas (todas probadas en la PoC)

| Técnica | Resultado | Decisión |
|---|---|---|
| **Chaflán (Bevel) + `harden_normals`** en piezas duras (1.2–2.5 cm, 1 segmento, límite por ángulo 30°) | caras planas + fila de 1–2 px de brillo en cada arista: la madera/molduras se leen "fabricadas" a 27 m. Coste ×3.7 tris por caja (12 → 44). | **Sí** en molduras, postes, vigas, tablas, marcos, remates. **No** en tablillas, balaustres, piedras pequeñas (basta la AO). |
| **"Almohadas" de nieve**: jaula de cuadrículas con filas de soporte a `rim` del borde → Catmull‑Clark (nivel 1–2) → suave; cornisa por desplazamiento del borde; bordes ondulados por ruido; **se borra el envés oculto** | losas gruesas con bordes redondeados, terrones, nieve en barandillas/alféizares, ventisqueros: exactamente la forma de la referencia. | **Sí**. Nivel 2 solo si el lado mayor ≥ 1.5 m; nivel 1 en piezas pequeñas (regla de presupuesto automática en `hdlib.pillow`). |
| **Sombreado suave + aristas duras por ángulo** (`Mesh.shade_smooth` + `set_sharp_from_angle`) | tela, corteza, nieve y terreno redondos con 8–14 lados. | **Sí** (nieve, tela, cuero, corteza, terreno). |
| **Normales custom congeladas antes de unir** (`normals_split_custom_set`) | permite mezclar en un mismo objeto plano + suave + endurecido; el exportador glTF las respeta y Godot también. | **Sí** (necesario para 1 superficie por parte). |
| **Desplazamiento** para capas/ventisqueros | se hace más barato con ruido en la jaula (almohadas) y con la función de altura (terreno) que con el modificador Displace. | Ruido en jaula/función, sin modificador. |
| **Molduras modulares** (`lap_siding`, `window`, `corner_boards`, `base_bands`, `beam`, `snow_strip`) | funciones parametrizadas por cara de muro: son las piezas del kit M6a. | **Sí** → pasar a `lib/kit.py`. |
| **AO horneada en color de vértice** (Cycles bake AO → atributo temporal → **`COLOR_0.a`**) | 2–5 s por asset; oscurece solapes de tablilla, bajo aleros, envés de pisos de pino, pliegues de la parka, huellas. RGB sigue siendo el color exacto de paleta. Godot conserva el alfa (verificado). | **Sí** (contrato nuevo, §4.6). Shader: `AO = COLOR.a` (06 §3.7). |
| Resaltado de aristas por **curvatura** horneado en color | los chaflanes endurecidos ya dan el brillo con la luz real; hornearlo en RGB rompe la comprobación de paleta y "pinta" luz fija. | **No** (aplazado; si hiciera falta, en un canal aparte del shader). |
| **Segunda UV** / texturas de detalle | contrario al contrato sin texturas; el grano de nieve/ruido de tono va en el shader en espacio mundo (06). | **No**. |

### 2.2 (b) Paquetes externos — licencia, estilo y viabilidad de descarga

Pruebas de red hechas desde este contenedor el 2026‑09‑24 (`curl` a través del proxy; `WebFetch` para páginas):

| Fuente | Licencia | ¿Comercial? | Encaje de estilo | Encaje de pipeline | ¿Descargable aquí? | Qué tendría que hacer el usuario |
|---|---|---|---|---|---|---|
| **Kenney** (Holiday Kit 100, Nature Kit 330, City…) | **CC0 1.0** | Sí, sin atribución | Bajo: muy simple, colores planos saturados, escala "juguete" (por debajo de lo que ya tenemos) | glTF con material/texturas simples; sin cortes ni anclas | **No** (`kenney.nl` → CONNECT 403). Sí los modelos incluidos en `KenneyNL/Starter-Kit-*` vía `raw.githubusercontent.com` (200) | Descargar a mano de kenney.nl/itch.io, copiar a `third_party/kenney/<pack>/` con `License.txt` |
| **Quaternius** (Stylized Nature MegaKit, Zombie Apocalypse Kit, UAL 1/2) | **CC0 1.0** | Sí | Medio‑bajo: estilizado limpio y brillante; personajes cartoon; la naturaleza nueva usa texturas y mapas normales | Texturas/atlas + rigs propios (UAL es humanoide universal → retarget) | **No** (`quaternius.com`, `itch.io`, `poly.pizza` → 403). **Sí** el espejo CC0 `J-Ponzo/gltf-universal-animation-library` (raw 200) | Descargar a mano; para UAL basta el espejo de GitHub |
| **KayKit** (Kay Lousberg: City Builder Bits, Adventurers, Furniture…) | **CC0 1.0** (`LICENSE.txt` leído: "free to use in personal, educational and commercial projects") | Sí | Bajo: chibi, formas gruesas | Atlas degradado 1024² (necesita UV) | **Sí**: `raw.githubusercontent.com/KayKit-Game-Assets/…` (200). Página/API/`codeload` del repo requieren `add_repo` (403 "not enabled") | Nada, o pedir `add_repo` para listar ficheros |
| **Poly Pizza** | **Mixta**: ≈ 69 % CC‑BY (p. ej. Google Poly CC‑BY 3.0, atribución obligatoria), resto CC0 | Sí, con atribución en CC‑BY | Heterogéneo (autores distintos) | Variable | **No** (403, también por WebFetch) | Filtrar `CC0`, verificar modelo a modelo, guardar créditos: **no recomendado** |
| **Poly Haven** | **CC0 1.0** | Sí | Nulo: fotorrealista PBR | Texturas 1k–8k, alta densidad | **No** (`polyhaven.com`, `api.`, `dl.` → 403) | — |
| **Synty POLYGON** (Snow Kit; Survival/Apocalypse/Town serían los relevantes) | **Propietaria (EULA)**: uso comercial sí; licencia por compra (5 puestos) o suscripción; **prohibido redistribuir** los assets fuente; la EULA prohíbe la **inclusión en datasets usados por programas de IA generativa y su uso en su desarrollo** | Sí, bajo EULA | Medio‑alto en props/edificios (low‑poly plano); personajes estilizados | Atlas de textura + UV (habría que hornear a color de vértice); sin cortes/anclas | **No** (`syntystore.com` → 403) y de pago | Comprarlo, mantenerlo **fuera del repositorio público** (repo privado o carpeta ignorada) y obtener **revisión legal/excepción de Synty** porque nuestro pipeline lo manipularían agentes de IA. Snow Kit (9.99 USD) es temático de esquí: esquís, tablas, moto de nieve, 2 personajes. **No recomendado.** |
| npm / PyPI | — | — | — | — | Accesibles (200), pero **no hay paquetes oficiales** de estos packs (solo terceros, p. ej. `kenney-hexagon-pack`, o índices que a su vez descargan de las webs bloqueadas) | No usar como canal (procedencia no verificable) |

Conclusión (b): lo único descargable aquí con licencia limpia es KayKit, algunos modelos Kenney de los *starter kits*
y el espejo de Quaternius UAL; ninguno sube el listón visual respecto a la PoC y todos rompen el contrato de assets
(texturas/atlas, rigs, sin partes de corte). **Nunca se usará un asset de licencia dudosa**; cualquier asset externo
irá con su `LICENSE` en `third_party/` y una línea en `LICENSES.md` (ASSET_SPEC_V2 cabecera).

### 2.3 (c) Híbrido

Procedural HD como base + externo CC0 solo para: (1) **animaciones** difíciles (Quaternius UAL, ya decidido en 04,
retarget al `BoneMap` identidad); (2) ***blockout*** temporal de props de relleno mientras se hacen los propios
(Kenney/KayKit), marcados `placeholder` y sustituidos antes de un hito visual. No se mezclan estilos en pantalla.

### 2.4 Recomendación por familia

| Familia | Estrategia | Por qué |
|---|---|---|
| Edificios (cabaña, A‑frame, kit de pueblo M6a) | **Procedural HD** (molduras modulares + almohadas de nieve por plantilla) | Partes de corte, anclas `Spawn_*`, colisión y plantillas JSON son nuestras; ningún paquete las trae; la PoC ya alcanza la referencia |
| Nieve (tejados, repisas, barandillas, ventisqueros, montones) | **Procedural** (`pillow`, `snow_strip`, `mound`) | Depende de la geometría concreta de cada asset |
| Terreno + caminos + bermas | **Código Godot** (06) con las **reglas de forma** de §4.3 | Es un campo de alturas en tiempo de ejecución |
| Huellas | **Mapa de rastro** (06, elegida) + `footprint_hd.glb` como malla de respaldo/decal | Sin draw calls y acumulable |
| Pinos, árboles desnudos, arbustos, rocas | **Procedural HD** | Técnica de estrella/ramificación recursiva ≈ 1–2 k tris; los packs CC0 son cartoon |
| Jugador | **Procedural HD** sobre nuestro rig | El esqueleto, sockets y `Outfit_*` son contrato; los personajes externos traen otro rig y atlas |
| Zombis | **Procedural HD** (misma receta que el superviviente + `zombify`) | Consistencia con el jugador; Quaternius Zombie Kit solo como referencia |
| Animales | **Procedural** (M9b, cuadrúpedo) | Mismo motivo que el jugador |
| Vehículos | **Procedural HD** (generador M7 con chaflanes 3–5 cm y almohadas de nieve) | Anclas/física propias |
| Armas, herramientas, botín, muebles | **Procedural HD**; Kenney/KayKit solo *blockout* | Presupuesto pequeño; chaflán + AO basta |
| Animaciones | Script + **Quaternius UAL (CC0)** | Sin cambios respecto a 04 |

---

## 3. Prueba de concepto (ejecutada)

### 3.1 Ficheros

`prototypes/lookdev/blender/` (no toca `blender/`, `assets/`, `scripts/`, `scenes/`; importa `blender/lib` sin modificarlo):

| Script | Qué hace |
|---|---|
| `hdlib.py` | Paleta v2.1 (en tiempo de ejecución), `pillow` (almohada de nieve), `snow_strip`, `mound`, `bevel` (endurecido), `smooth`/`flat`, `freeze_normals` + `join` (1 objeto por parte de corte), `snap_colors` (cara → color exacto de paleta tras chaflanes), `drop_faces` (envés oculto), `bake_ao` (Cycles AO → `COLOR_0.a`), `export_hd` (glTF con `COLOR_0` RGBA), manifiesto |
| `build_cabin_hd.py` | Cabaña con **la misma estructura de corte** que `cabin.glb`: `Floor`, `WallBack`, `WallLeft`(+`WindowsLeft`), `WallRight`(+`WindowsRight`, nueva ventana), `WallFront`(+`WindowsFront`), `Roof`, `Chimney`, `Porch`, `DoorAnchor`, `LanternSocket`, mismas cajas `Col*-convcolonly` + `ColSteps` + `ColPostL/R` |
| `build_trees_hd.py` | `pine_hd_a` (7 pisos, 8 puntas), `pine_hd_b` (6 pisos, 7 puntas, más nieve), `bare_tree_hd` (tronco → 9 ramas → 3 → 2 ramillas) |
| `build_terrain_hd.py` | `terrain_tile_hd` (44 × 44 m, celda 0.4 m: ondulación, sendero hundido con bermas desde el porche, pista con bancos de 0.45 m, 3 ventisqueros asimétricos, `Footprints` con reborde), `footprint_hd` (una huella), `terrain_flat_1m_ref.glb` (mismas alturas a 1 m facetadas = "antes") |
| `build_survivor_hd.py` | `chars/survivor_hd_{brown,olive,navy,rust}` sobre `rig.build_armature()` (27 huesos idénticos), `Body` + `Outfit_backpack_m`; `.import` "char" y `rig/humanoid_bonemap.tres` propios del proyecto look‑dev |
| `verify_survivor_hd.py` | Contrato de esqueleto y animación (Blender + Godot headless en un proyecto temporal del scratchpad) |
| `render_lookdev.py` | Previews Cycles desde la cámara del juego y primeros planos; comparación antes/después |
| `build_all_hd.py` | Todo lo anterior: `python3 build_all_hd.py [--render] [--no-godot]` → `ALL OK` (≈ 25 s sin renders) |

Salida en `prototypes/lookdev/godot/assets/hd/` (la recoge el proyecto de look‑dev de 06): `*.glb`, `chars/*.glb`
(+ `.import`), `rig/humanoid_bonemap.tres`, **`hd_manifest.json`** (convenciones, tris, partes, qué sustituye cada
asset) y **`lookdev_layout.json`** (posiciones sugeridas de árboles/superviviente sobre la loseta).

### 3.2 Resultados

| Asset HD | Tris | Superficies visibles | Antes | Notas |
|---|---|---|---|---|
| `cabin_hd` | 23 264 | 11 (8 `palette_vcol` + 3 `window`) | 1 674 / 10 | Roof 8.4 k, Porch 6.3 k, Floor 1.9 k, Chimney 1.7 k, muros 0.4–2.0 k. AO 96 muestras, 1.2 m |
| `pine_hd_a` / `pine_hd_b` | 1 125 / 873 | 1 | 226 / 178 | MultiMesh‑friendly (1 objeto `Tree`, sin hijos) |
| `bare_tree_hd` | 2 086 | 1 | 178 | ~90 tubos, radio mínimo 1.4 cm |
| `terrain_tile_hd` | 24 200 + 2 184 (26 huellas) | 2 | chunk de juego: 8 192 / 64 m | loseta de look‑dev, no asset de juego |
| `footprint_hd` | 84 | 1 | — | reborde 4.5 cm, suelo `snow_hole` |
| `survivor_hd_*` | 2 650 (Body 2 226 + mochila 424) | 1 + 1 | 954 | faldón con pesos mezclados Hips→UpperLeg (≤ 2 influencias) |

Tiempo de construcción de todo: ≈ 25 s (incluidos los horneados de AO). Tamaños: `cabin_hd.glb` 1.2 MB (antes
144 KB; el alfa por esquina y las normales partidas multiplican vértices), pino 80–104 KB, superviviente 200 KB.

### 3.3 Verificación del superviviente (mismo esqueleto, mismas animaciones)

`verify_survivor_hd.py` (informe en `…/scratchpad/lookdev_art/verify_survivor_hd.json`):

- **Blender**: 27 huesos; matrices de reposo idénticas a `assets/models/chars/survivor_red.glb` y al armature de
  `assets/models/anims/humanoid_loco.glb` (**diferencia máxima 0.0**). Las 6 acciones (`Loco_Idle`, `Loco_Idle_Cold`,
  `Loco_Walk`, `Loco_Run`, `Crouch_Idle`, `Crouch_Walk`) se enlazan con 27 canales, **0 huesos ausentes**; las suelas
  deformadas quedan en [−0.07, 0.0] cm en andar, [−0.06, 0] cm agachado, ≥ −0.91 cm en correr (la subida a 9.9 cm es
  la fase de vuelo de la carrera). **OK**.
- **Godot 4.7.2** (importación con las plantillas `char`/`anim` del juego): `GeneralSkeleton` con 27 huesos,
  `Body` y `Outfit_backpack_m` con *skin*, **`COLOR` con alfa (AO) conservado** (mín. 0.0), la librería `loco` se
  reproduce y mueve los huesos exactamente igual que en `survivor_red.glb` (giro de cadera en el ciclo: andar 64.6°,
  correr 61.8°, agachado 83.2° en ambos). **0 errores**.
- Poses renderizadas con la librería del juego: `survivor_hd_anim_{Loco_Walk,Loco_Run,Crouch_Walk}_{side,gamecam}.png`.

### 3.4 Previews (Cycles, cámara del juego: pitch 48°, yaw 45°, FOV 36°, 16–24 m)

Carpeta: `/tmp/claude-0/-home-user-Quotas/3c3b507e-0838-5643-8cd6-6e5a40202a08/scratchpad/lookdev_art/`

| Fichero | Qué muestra |
|---|---|
| `compare_old_vs_new_gamecam24.png` | **Antes \| después** con la misma cámara, luz y disposición (assets de hoy sobre las mismas alturas a 1 m facetadas vs HD) |
| `ref_vs_hd_dusk.png`, `ref_vs_hd_day.png` | **Referencia \| HD** lado a lado (uso interno). Lo que queda de diferencia es sobre todo luz/exposición (06) y que la referencia usa la cámara más cerca (≈ 18–20 m frente a nuestros 27 m por defecto; recomendación a código/diseño: probar 20–22 m por defecto) |
| `scene_hd_day_gamecam24.png`, `scene_hd_day_gamecam16.png` | Escena HD de día (contraluz bajo como la referencia) |
| `scene_hd_dusk_gamecam24.png` | Escena HD al atardecer con ventanas encendidas |
| `scene_old_day_gamecam24.png` | Escena actual equivalente |
| `cabin_hd_closeup.png`, `cabin_hd_gamecam24.png`, `cabin_old_closeup.png` | Cabaña HD vs actual |
| `trees_new_left_old_right.png`, `trees_hd_closeup.png` | Pinos/árbol HD (izq.) vs actuales (der.) |
| `terrain_flat1m_before.png`, `terrain_hd_after.png`, `terrain_hd_footprints_closeup.png` | Terreno facetado 1 m vs liso con camino, bermas, bancos y huellas |
| `survivor_hd_variants_front_vs_old.png`, `survivor_hd_variants_back.png`, `survivor_hd_variants_gamecam22.png` | 4 variantes HD vs superviviente M1 |
| `survivor_hd_anim_*` | Poses de `humanoid_loco.glb` sobre el superviviente HD |

Las previews multiplican el albedo por `mix(1, COLOR.a, 0.75)` (la AO de la propuesta de shader); la luz es una
aproximación en Cycles de la de 06, no la final de Godot.

---

## 4. Guía de arte v2.1 (sustituye/añade a ASSET_SPEC_V2 §2.5, §3, §14 al migrar)

### 4.1 Paleta v2.1

Regla general: **desaturar y oscurecer** lo que era primario; la nieve pasa a azul pastel (= albedo del terreno de
06, así props y suelo casan sin tinte); saturación reservada a acentos raros (señalética, botín, `hivis_orange`).

Cambian (nombre: v2 → **v2.1**):

| Nombre | v2 | v2.1 | | Nombre | v2 | v2.1 |
|---|---|---|---|---|---|---|
| `snow` | `#F1F5FA` | **`#CDDEF5`** | | `stone` | `#7C8592` | **`#7B8089`** |
| `snow_shadow` | `#B9CBE3` | **`#AFC3E0`** | | `stone_dark` | `#5A616B` | **`#565B63`** |
| `pine_dark` | `#2F5D3A` | **`#1F342E`** | | `brick` | `#8E5A4A` | **`#735F5D`** |
| `pine_light` | `#4B8A55` | **`#2F4A3D`** | | `cabin_wall` | `#5D7FA6` | **`#6C829C`** |
| `bark` | `#5B3F2E` | **`#4A3D35`** | | `cabin_trim` | `#DDE6F0` | **`#D3CFC6`** (crema) |
| `wood` | `#8B6543` | **`#7A5F4B`** | | `roof` | `#33383F` | **`#48434A`** |
| `wood_light` | `#C7A16B` | **`#A88E70`** | | `iron` | `#2B2E33` | **`#2A2B2E`** |
| `wood_dark` | `#4A3426` | **`#4A3B31`** | | `truck_paint` | `#5B6B3F` | **`#5E6650`** |

Nuevos:

| Nombre | Hex | Uso | | Nombre | Hex | Uso |
|---|---|---|---|---|---|---|
| `snow_packed` | `#BFD0E8` | camino pisado (mezcla por vértice en terreno) | | `pack` | `#5D4C3C` | mochila |
| `snow_hole` | `#93AACB` | fondo de huella | | `pack_dark` | `#3D352D` | tapa/bolsillos/correas |
| `snow_deep` | `#D6E4F7` | crestas, nieve fresca | | `boots_brown` | `#5B412F` | botas |
| `roof_seam` | `#2C2A2E` | juntas, cumbrera | | `sock` | `#D9D4CB` | vuelta del calcetín |
| `bark_grey` | `#4E4843` | árbol desnudo | | `skin_hd` | `#C29478` | piel (menos rosa) |
| `pine_mid` | `#27402F` | cara superior del piso de pino | | `glove` | `#2F2B28` | guantes |
| `parka_brown` / `parka_olive` / `parka_navy` / `parka_rust` | `#4F4135` / `#4C5040` / `#3A4457` / `#7A4536` | 4 variantes co‑op del jugador | | `mat_roll` | `#6D7558` | esterilla |
| `pants_dark` | `#35383D` | pantalón | | `strap` | `#2B2826` | correas |
| `beanie` | `#2E3035` | gorro | | `beard` | `#4A3A30` | barba/cejas |
| `fur` | `#CEC8BD` | cuello de piel | | | | |

Las variantes de color de jugador pasan de "rojo/azul/verde/mostaza" a **parkas desaturadas** (marrón/oliva/azul
noche/óxido): siguen distinguiéndose en co‑op por matiz y valor; si hace falta más contraste, un acento pequeño
(gorro o esterilla) por jugador. `zombify()` sigue funcionando sobre la paleta nueva.

### 4.2 Sombreado y chaflanes

| Tipo de superficie | Regla v2.1 |
|---|---|
| Madera trabajada, molduras, postes, vigas, marcos, muebles, metal | caras **planas** + **chaflán 1.2–2.5 cm** (1 segmento, ángulo ≥ 30°, `harden_normals`); piezas < 5 cm de sección sin chaflán |
| Tablilla, balaustres, piedras pequeñas, juntas | planas sin chaflán (la AO hace el trabajo) |
| Nieve (losas, terrones, repisas, ventisqueros, montones, huellas) | **suave**, jaula subdividida ("almohada"), borde redondeado ≥ 8 cm de radio, sin envés oculto |
| Tela, piel, cuero, pelo | **suave**, lofts de 10–14 lados, aristas duras solo en dobladillos/puños (ángulo 55°) |
| Corteza (troncos, ramas) | **suave** (tubos de 4–7 lados según grosor) |
| Pisos de pino, rocas grandes | **facetado** (es parte del estilo de la referencia), con AO |
| Terreno | **normales suaves** del campo de alturas (nunca `dFdx/dFdy`) |

Un objeto puede mezclar los tres tipos: se congelan las normales (`freeze_normals`) antes de unir, y se exportan como
normales custom.

### 4.3 Recetas de nieve y de forma (lo que "hace" la referencia)

- **Tejados**: nieve **parcial**: losa de 18–24 cm con borde redondeado desde el alero (cornisa que vuela 10–15 cm y cae
  8–11 cm) hasta el 60–80 % del faldón, borde superior ondulado; **terrones** (0.5–0.9 m × 0.35–0.6 m × 13–16 cm) en la
  banda oscura; faldones pequeños/porches cubiertos del todo. El tejado oscuro con juntas debe verse.
- **Repisas, barandillas, remates de poste, alféizares, capó**: `snow_strip`/almohada de 4.5–7 cm.
- **Suelo junto a paredes**: ventisquero en cuña (0.45–0.62 m junto al muro → 0 a 0.8–1.05 m), montones junto a escalones.
- **Pinos**: pisos en estrella (7–9 puntas, radio interior 0.6), puntas caídas 12 %, capa de nieve **calculada sobre la
  superficie verde** (7.5–9.5 cm, ligeramente más corta que las puntas para dejar un filo oscuro), envés cóncavo
  `pine_dark`, tronco visible bajo el primer piso, montículo suave en la base (hundido 20 cm para no "flotar" en pendiente).
- **Árbol desnudo**: 3 niveles de ramificación (9 × 3 × 2), tubos curvados, radio final ≥ 1.4 cm, nieve en caras
  superiores de tronco y ramas principales.
- **Terreno** (para el código, 06): ondulación 0.35 m/14 m + 0.12 m/4.5 m; sendero 1.4 m hundido 12 cm con bermas de
  13 cm a 1.05 m del eje; pista con bancos de 0.45 m a 2.25 m del eje; ventisqueros asimétricos (barlovento largo,
  sotavento corto); color `snow_packed` mezclado **por vértice** (no por cara: dientes de sierra); celda ≤ 0.5 m cerca
  de la cámara.
- **Huellas**: 0.44 × 0.26 m (nieve profunda), reborde 4.5 cm, fondo `snow_hole`, alternadas ±13 cm cada 0.72 m.

### 4.4 Densidad de detalle (a 27 m, 1080p ≈ 62 px/m)

| Elemento | Mínimo para que se lea | Objetivo PoC |
|---|---|---|
| Forma (tabla, moldura, parteluz) | ≥ 3–4 px → **≥ 5 cm** | marcos 9 cm, parteluces 3.5–4 cm (se leen como línea), balaustres 4.4 cm cada 15 cm |
| Brillo de arista | 1–2 px | chaflán 1.2–2.5 cm |
| Borde de nieve redondeado | radio ≥ 8 cm (≥ 5 px) con ≥ 4 segmentos | nivel 2 en losas ≥ 1.5 m; nivel 1 en piezas pequeñas |
| Ramillas | ≥ 2 px | radio ≥ 1.4 cm |
| Personaje | silueta, cabeza ≈ 1/7.5, mochila, contraste oscuro sobre nieve | 1.79 m, cabeza 0.23 m + gorro |
| Cara | no se lee: 2 ojos oscuros, nariz, cejas/barba como manchas | idem |

### 4.5 Presupuestos v2.1

| Categoría | v2 | **v2.1** | PoC |
|---|---|---|---|
| Jugador (Body + outfits activos) | 800–1 500 | **2 000–3 500** | 2 650 |
| Zombi / NPC | 700–1 300 | **1 500–2 500** | — |
| Casa "héroe" (cabaña, POI) | 2–12 k | **12–24 k** | 23 264 |
| Casa del kit (pueblo) | 2–12 k | **6–14 k** | — |
| Pino | 150–400 | **700–1 200** | 1 125 / 873 |
| Árbol desnudo | 80–250 | **1 500–2 600** | 2 086 |
| Roca / arbusto | 40–400 | **150–700** | — |
| Mueble / prop | 20–400 | **100–1 200** | — |
| Vehículo (sin ruedas) | 1.5–4.5 k | **4–8 k** | — |
| Arma en mano | 40–600 | **100–900** | — |
| Huella (malla) | — | **≤ 100** | 84 |
| Escena visible | ≤ 300 k | **≤ 400 k** objetivo (≤ 1.5 M máx.) con el auto‑LOD de Godot y `visibility_range` | estimación típica: cabaña 23 k + 2 casas kit 20 k + 40 pinos 45 k + 10 árboles 21 k + 4 jugadores 11 k + 30 zombis 60 k + terreno ≈ 30 k + 200 props × 300 = 60 k ≈ **270 k** |
| Superficies / draw calls | 1 por malla | **sin cambio** (1 por malla / parte de corte; cabaña 11) | ✓ |

### 4.6 Contrato de exportación v2.1 (cambios respecto a ASSET_SPEC_V2 §2.5/§2.8/§16)

- `COLOR_0` = **RGBA**: RGB = color de paleta (lineal + `GODOT_BIAS`, igual que hoy); **A = AO horneada** (1 = abierto,
  0 = ocluido). Exportador: `export_vertex_color='NAME', export_vertex_color_name='Col'` (con `'MATERIAL'` el alfa se
  descarta). `StandardMaterial3D` ignora el alfa (opaco); el shader del juego lo usa: `AO = COLOR.a;
  AO_LIGHT_AFFECT = 0.35` (06 §3.7, con `ao_tint`).
- `use_smooth` permitido y **normales custom** exportadas (quitar la regla "todo plano" y la comprobación
  correspondiente de `verify_assets.py`; añadir: `COLOR_0` VEC4 con alfa en [0, 1], alfa mínimo < 1 en todo asset
  con AO).
- Excepción al "un color de paleta por cara": el **terreno** (y solo él) mezcla colores por vértice.
- Sin UV, sin imágenes, 1 superficie por malla (edificios: por parte de corte + `window`), nombres/pivotes/frentes
  sin cambios. Los `Outfit_*` del personaje son hijos del armature (ya en §4.4 de la spec).
- Horneado de AO: distancia 1.2 m (edificios, pinos), 0.8 m (árboles), 0.25 m (personajes, huellas), con plano de
  suelo temporal; 48–96 muestras.

### 4.7 Lo que el arte pide al render (acordado con 06)

`world_vcol_v2.gdshader` con `AO = COLOR.a`; terreno con normales suaves; `snow_color` = `snow` de la paleta
(`#CDDEF5`); sol bajo a contraluz y ambiente azul; ventanas con material `window` emisivo de noche. El proyecto
`prototypes/lookdev/godot/` ya carga `assets/hd/` (plantillas `.import` generadas).

---

## 5. Coste de migración

Unidad: horas de agente (Opus). Incluye construir, verificar y renderizar. Paralelizable por familias.

### 5.1 Base común (una vez)

| Trabajo | h |
|---|---|
| `blender/lib/hd.py` (portar `hdlib`: almohadas, tiras, montículos, chaflán endurecido, unión con normales, `snap_colors`, AO), `export.py` (COLOR_0 RGBA), `palette.py` v2.1 | 3 |
| `verify_assets.py` / `verify_chars.py` v2.1 (suave + normales custom, alfa de AO, presupuestos nuevos) + actualizar ASSET_SPEC | 3 |
| **Subtotal** | **6** |

### 5.2 Los 33 assets actuales (+ 4 supervivientes)

| Assets | Acción | h |
|---|---|---|
| `cabin` | portar `cabin_hd` (interior y anclas iguales; en M6a lo sustituye `house_hunter` del kit con las mismas reglas) | 1.5 |
| `a_frame_cabin` | HD: cercha vista, almohadas en faldones, porche | 3 |
| `pine_a/b/c` | `pine_hd_a/b` + `pine_hd_c` (joven, 3.5 m) | 1 |
| `dead_tree`, `stump` | `bare_tree_hd` + variante; tocón con anillos y nieve almohada | 1.5 |
| `rock_a/b/c`, `stone` | facetadas + AO + casquete de nieve almohada | 1.5 |
| `berry_bush` | racimos suaves + nieve; mantiene `Berries` | 1 |
| `fallen_log`, `firewood` | corteza suave, testas con anillos, nieve | 1 |
| `campfire`, `torch`, `lantern` | chaflanes, piedras suaves, AO | 1.5 |
| `stone_axe` | chaflán | 0.5 |
| `bed`, `desk`, `chair`, `shelf`, `clock`, `cabinet`, `wood_stove` | chaflanes, tiradores, manta suave, AO | 3.5 |
| `pickup_truck` | carrocería con chaflán 3–5 cm, pasos de rueda, neumáticos suaves, nieve en capó/techo/caja (la brecha más visible tras la cabaña) | 4 |
| `signpost`, `fence` | tablas con chaflán, tiras de nieve | 1.5 |
| `tent`, `storage_box` | lona suave, chaflanes | 1.5 |
| `wolf`, `deer` | paleta + suavizado provisional (esqueleto en M9b) | 2 |
| `player` | se retira en M2 | 0 |
| `survivor_*` ×4 | portar `survivor_hd_*` (hecho), cambiar `CharacterVisual.VARIANTS` a los nombres nuevos | 1 |
| **Subtotal** | | **≈ 26–28** |

Total migración actual: **≈ 32–34 h ≈ 4–5 pases de Opus** (1 si solo se hacen los "héroes" visibles en el claro:
cabaña, pinos, árbol, rocas, camión, superviviente ≈ 10 h).

### 5.3 Plan futuro (delta sobre lo ya planificado en ASSET_SPEC_V2 §18)

| Hito / familia | Delta v2.1 | Estimación |
|---|---|---|
| M2 zombis caminantes (8) + armas cuerpo a cuerpo | receta del superviviente (lofts suaves, AO) + `zombify` sobre paleta v2.1 | +4–6 h (+30 %) |
| M3 vegetación/rocas/nieve/suelo (§13) | recetas de §4.3 ya escritas | +6 h (+25 %) |
| M4 zombis lote 1 (runner, crawler, bloater, frozen) | idem | +6 h |
| M5 armas de fuego, botín (~40) | chaflán + AO | +5 h (+15 %) |
| M6a kit de pueblo (3 estilos) + plantillas + carreteras | molduras modulares y almohadas **por plantilla** (bordes de tejado, alféizares y porches se conocen) + bermas en carreteras | +2–3 días (+40 %) |
| M6b props urbanos (~40), restos de coche | chaflán + nieve almohada | +1 día |
| M7 vehículos (generador) | chaflanes grandes, almohadas de nieve, neumáticos suaves | +1 día |
| M8–M10 (ropa, POIs, militares) | +20 % por asset | +1–2 días |
| Animaciones | **0** (esqueleto idéntico) | 0 |
| **Total** | | **≈ +8–10 días de agente** |

Rendimiento: tris ×3–12 por asset pero **mismas superficies** (los draw calls, que eran el límite medido en 04, no
cambian); escena típica ≈ 270 k tris (§4.5). Memoria de mallas ×5–8 (la cabaña pasa de 144 KB a 1.2 MB): irrelevante
en escritorio, a vigilar en *Compatibility*/móvil (06 §3.13). Riesgo principal: el alfa de AO y las normales custom
dependen de que el shader del juego pase a `world_vcol_v2` (06 §6, hito G1); sin él los assets se ven bien pero sin AO.

---

## 6. Riesgos y siguientes pasos

1. **Aprobación visual del usuario** con `compare_old_vs_new_gamecam24.png` y los renders de Godot de 06 (G1).
2. Integrar en este orden: base común (§5.1) → paleta v2.1 en todo (≈ 1 h, efecto global inmediato) → héroes del claro
   → resto; mantener `verify_assets.py` en ALL OK en cada paso.
3. Las variantes de parka desaturadas reducen la distinción entre jugadores a distancia: validar en co‑op (acento de
   color pequeño si hace falta).
4. Kit M6a: presupuestar 6–14 k tris por casa y usar las funciones de molduras de `build_cabin_hd.py` como piezas.
5. No introducir assets externos salvo CC0 documentado en `LICENSES.md`; Synty solo tras compra, revisión legal de la
   cláusula de IA y fuera del repositorio.

---

## Fuentes

- Kenney — licencia CC0 y kits: [Holiday Kit](https://kenney.nl/assets/holiday-kit), [Nature Kit](https://kenney.nl/assets/nature-kit), [Kenney's Assets (CC0) — Godot Forum](https://forum.godotengine.org/t/kenneys-assets-free-and-creative-commons-cc0/36658), [KenneyNL/Starter-Kit-City-Builder](https://github.com/KenneyNL/Starter-Kit-City-Builder), [KenneyNL/Starter-Kit-3D-Platformer](https://github.com/KenneyNL/Starter-Kit-3D-Platformer)
- Quaternius — CC0: [Stylized Nature MegaKit](https://quaternius.com/packs/stylizednaturemegakit.html), [Zombie Apocalypse Kit](https://quaternius.com/packs/zombieapocalypsekit.html), [Animated Zombie Pack](https://quaternius.com/packs/animatedzombie.html), [Universal Animation Library](https://quaternius.com/packs/universalanimationlibrary.html), espejo glTF [J-Ponzo/gltf-universal-animation-library](https://github.com/J-Ponzo/gltf-universal-animation-library)
- KayKit — CC0: [KayKit-Game-Assets (GitHub)](https://github.com/KayKit-Game-Assets), [KayKit-Character-Pack-Adventures-1.0](https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0), [KayKit-City-Builder-Bits-1.0](https://github.com/KayKit-Game-Assets/KayKit-City-Builder-Bits-1.0)
- Poly Pizza — licencias mixtas: [búsqueda CC0](https://poly.pizza/search/CC0), [integración Poly Pizza (≈ 69 % CC‑BY)](https://mcp-for-blender.com/integrations/poly-pizza)
- Poly Haven — CC0: [License](https://polyhaven.com/license), [API](https://polyhaven.com/our-api), [3D Model Standards](https://docs.polyhaven.com/en/technical-standards/models)
- Synty — [One-Time Purchase Licence & EULA](https://syntystore.com/pages/one-time-purchase-licence), [Licences overview](https://syntystore.com/pages/licences-overview), [FAQ](https://syntystore.com/community/faq), [POLYGON Snow Kit](https://syntystore.com/products/polygon-snow-kit)
- Pruebas de red propias (2026‑09‑24): `curl` vía proxy a kenney.nl, quaternius.com, poly.pizza, polyhaven.com (+api/dl), itch.io, syntystore.com, opengameart.org, sketchfab.com, ambientcg.com, jsdelivr, unpkg → CONNECT 403; github.com release asset, raw.githubusercontent.com, registry.npmjs.org, pypi.org → 200; GitHub API/codeload/página de repos no añadidos → 403 "not enabled".
