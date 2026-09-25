# 06 — Gráficos y render: look‑dev "low‑poly premium" (hito G1)

> Proyecto: VENTISCA. Motor **Godot 4.7.2**, renderer real **Forward+** (Compatibility = respaldo/web).
> Fecha: 2026‑09‑24. Estado: **investigación + prototipo de look‑dev renderizado y comparado con las referencias**.
> Prototipo: `prototypes/lookdev/godot/` (proyecto Godot propio, ignorado por el juego vía `prototypes/.gdignore`).
> Complementa `01_mundo_abierto_tecnologia.md` §7 (presupuestos), `04_arte_animacion_pipeline.md` (materiales por
> color de vértice) y el doc de arte de Opus (`05_graficos_arte.md`, assets HD en `prototypes/lookdev/godot/assets/hd/`).

---

## 0. Resumen ejecutivo

**Diagnóstico.** Las capturas actuales del juego (`docs/screenshots/day.png`, `night.png`, `blizzard.png`) se ven
"planas" por siete causas concretas, todas de render, ninguna de modelado:

| # | Ahora (slice) | Efecto visible | Referencia |
|---|---|---|---|
| 1 | `tonemap_mode = LINEAR`, sol `energy ≈ 0.26·sqrt`, ambiente gris | nieve quemada a blanco, sombras gris‑lavanda | nieve **azul pastel** (171,196,220), sombras **azul saturado** (~107,138,176) |
| 2 | sol a 38° de elevación máxima, `shadow_blur 1.5`, sin PCSS | sombras cortas, borde duro/dither | sol bajo (≈ 20–25°) a **contraluz** desde arriba‑derecha: sombras largas hacia la cámara, borde suave |
| 3 | sin AO (SSAO apagado en `medio/compat`, ninguna AO horneada) | el porche, el camión y las bases de árbol "flotan" | oscurecimiento suave y azulado bajo porche/objetos |
| 4 | terreno **flat‑shaded** (normal por cara) con color por cara | facetas visibles, nieve "arrugada" | nieve **lisa** con ondulaciones grandes |
| 5 | niebla exponencial gris‑clara (`#C9D8EA`, 0.006) | lo lejano se **blanquea** | lo lejano se **azulea** (de día) o se **aclara a gris‑azul** (de noche, más claro que el suelo) |
| 6 | huellas = discos planos semitransparentes | manchas grises | huella con **hundimiento + reborde** iluminado |
| 7 | ventanas emisivas sin luz proyectada; farol/hoguera sin sombras | la luz "no sale" de la cabaña | **derrame** cálido en la nieve con patrón de montantes, farol que ilumina el porche |

**Resultado del look‑dev** (mismo motor, assets actuales + héroes HD de Opus, cámara del juego −48°/FOV 36/27 m):

| Preset | Antes (juego, Compatibility) | Referencia | Después (look‑dev, Forward+) |
|---|---|---|---|
| Día | `docs/screenshots/day.png` | `lookdev_render/ref_day.jpg` | `lookdev_render/day_forward_plus.png` |
| Atardecer | — | `lookdev_render/ref_dusk.jpg` | `lookdev_render/dusk_forward_plus.png` |
| Noche | `docs/screenshots/night.png` | `lookdev_render/ref_night.jpg` | `lookdev_render/night_forward_plus.png` |
| Ventisca | `docs/screenshots/blizzard.png` | — | `lookdev_render/blizzard_forward_plus.png` |
| Hojas de comparación | | | `lookdev_render/sheet_final_*.png`, `sheet_tonemap2.png`, `sheet_gi_compat.png` |

(`lookdev_render/` = `/tmp/claude-0/-home-user-Quotas/3c3b507e-0838-5643-8cd6-6e5a40202a08/scratchpad/lookdev_render/`;
las versiones Compatibility están al lado con sufijo `_compat.png`.)

**Decisiones (resumen):**

1. **Tonemapper Filmic, exposición 0.55** (día). AgX y ACES desaturan la nieve clara hacia gris (medido: AgX e1.0
   → (200,201,204); Filmic e0.6 → azul conservado). Linear (actual) recorta.
2. **El azul vive en el albedo y en el ambiente, no en el sol**: albedo nieve `#CDDEF5` (lineal 0.80/0.87/0.96),
   ambiente `#6A88C4` × 1.45, sol casi neutro débil `#F8F3EA` × 0.5, elevación 23°, contraluz (yaw 168° con cámara a 45°).
3. **Sombras PCSS** (`light_angular_distance 1.2`, `shadow_blur 1.0`) en `alto`; PCF suave en `medio/compat`.
4. **AO en dos capas**: SSAO (Forward+; radio 1.4, intensidad 2.5, `light_affect 0.15`) + **AO horneada en
   `COLOR.a`** (terreno: ocluyentes del scatter; props: horneada por Opus). La horneada es la que da el look y
   funciona en Compatibility.
5. **Nieve**: terreno con normales suaves, shader `snow_terrain.gdshader` (wrap 0.45, brillo tenue, rim de cielo,
   destellos solo de día, ruido de tono sin texturas) y `world_vcol_v2.gdshader` (misma iluminación para props).
6. **Huellas por mapa de rastro** (textura R = hundimiento, G = reborde) leída por el shader del terreno como
   desplazamiento + normal + oscurecido; back‑end `Image`/`ImageTexture` (todos los renderers) o
   `DrawableTexture2D` (4.7, GPU). Huellas de malla (`footprint_hd.glb`) como opción "héroe".
7. **Ventanas**: `SpotLight3D` con **proyector** de 4 cristales + omni de baño + material emisivo (glow softlight).
   `AreaLight3D` (4.7) descartada por coste. Compatibility: mismo spot sin proyector.
8. **Niebla**: exponencial de profundidad muy suave (0.004 día) de color azul claro; **de noche más clara que el
   suelo** (`#66788C`); niebla de altura para bruma al atardecer/noche; volumétrica solo en ventisca (`alto`).
9. **SDFGI, SSIL, VoxelGI, LightmapGI: no.** SDFGI cambia < 3 % la imagen a este ángulo y cuesta ×1.6 (lavapipe);
   SSIL rompe el ambiente de color plano; VoxelGI/Lightmap no encajan con mundo procedural.
10. **Hito G1 (después de M2): tamaño M (Fable) + S (Opus)**, ~12 ficheros del juego (§6).

---

## 1. Método

- **Referencias**: 5 capturas del juego de referencia (día, atardecer, noche ×2, interior). Se midieron colores
  medios (sRGB) por zonas con Pillow para no "ajustar a ojo" (§2).
- **Prototipo** `prototypes/lookdev/godot/`: escena construida por script (`scripts/lookdev.gd`) que recrea la
  composición (cabaña con porche y chimenea, A‑frame al fondo, camión, poste indicador, pinos, árboles secos,
  arbustos con bayas, superviviente junto al porche, rastro de huellas), la cámara del juego y cuatro presets de
  `WorldEnvironment` (`scripts/presets.gd`). Shaders en `shaders/`. Assets: copia de `assets/models/*.glb` +
  `assets/hd/*_hd.glb` (Opus: cabaña, pinos ×2, árbol seco, huella, loseta de terreno) elegidos automáticamente.
- **Render en el contenedor**: Forward+ real sobre Vulkan por software (lavapipe) y Compatibility sobre OpenGL
  (llvmpipe), 1280×720, vía `tools/render.sh`:
  ```
  tools/render.sh fp     list=day,dusk,night,blizzard frames=8          # Forward+
  tools/render.sh compat list=day,night                                 # Compatibility
  tools/render.sh fp preset=day gi=sdfgi frames=40 tag=_sdfgi           # experimentos
  # user args: preset|list (preset[:tonemap[:exposure]]), tonemap=agx|aces|filmic|linear, exposure, gi=ssao|none|ssil|sdfgi,
  #            pcss=0|1, cookie=0|1, spill=0|1, volumetric=0|1, trail=cpu|drawable|none, hd=0|1, hdterrain=0|1,
  #            arealight=0|1, msaa=0|2|4, dist, yaw, pitch, fov, target=x,z, out=/dir, tag=_x
  ```
  El script imprime `viewport_get_measured_render_time_gpu` (en lavapipe = tiempo de CPU del rasterizador; sirve
  como **coste relativo**, no absoluto) y draw calls/primitivas.

---

## 2. Qué hace que la referencia se vea "premium" (medido)

Valores medios sRGB (R,G,B) de zonas de las capturas de referencia y de nuestros renders:

| Zona | Referencia | Juego actual (Compat) | Look‑dev Forward+ (final) |
|---|---|---|---|
| Nieve al sol, día | (171,196,220) / (153,179,204) | ≈ (236,240,246) quemada | (183,198,223) F+; (182,207,241) Compat e0.28 |
| Nieve en sombra de árbol, día | ≈ (107,138,176) | ≈ (178,192,214) | (95,122,174) |
| Nieve lejana (arriba), día | (158,184,209) (ligeramente más oscura/azul) | blanquea | (121,146,190) |
| Nieve abierta, atardecer | (100,122,161) (G > R: azul‑cian, no lavanda) | — | (89,112,159) |
| Nieve abierta, noche | (51,69,93) (azul **desaturado**) | ≈ (95,110,150) azul saturado | (67,85,114) F+; (46,65,98) Compat e0.20 |
| Nieve lejana, noche | (107,124,140) — **más clara** que la cercana | — | (70,88,115) |
| Derrame de ventana en nieve, noche | (173,141,121) (melocotón suave, no naranja) | — | (178,154,134) |

Lecturas: (a) la nieve iluminada es un azul pastel a ~80 % de luminancia, nunca blanco; (b) el ratio luz/sombra es
≈ 1.6 en R y ≈ 1.3 en B (la sombra es más azul, no solo más oscura); (c) la profundidad se consigue con una niebla
**del color del cielo**: de día apenas oscurece, de noche aclara; (d) las luces cálidas son de baja energía y
gran radio, sin quemar; (e) las sombras tienen borde suave pero forma reconocible (PCSS con ángulo pequeño, no
un desenfoque uniforme).

Geometría/cámara de la referencia: pitch ≈ 45–48°, FOV estrecho, distancia ≈ 22–27 m; sol a ≈ 20–25° de
elevación desde el borde superior derecho de pantalla (contraluz): las sombras de cabaña y árboles caen **hacia la
cámara**, que es lo que da las diagonales azules largas del suelo.

---

## 3. Investigación por tema (Godot 4.7 Forward+, cámara fija alta)

### 3.1 Tonemapping y exposición

| Modo | Comportamiento en nuestra escena (nieve clara, ambiente azul) | Veredicto |
|---|---|---|
| Linear (actual) | recorta brillos; obliga a energías muy bajas; sin "hombro" | ✗ |
| Reinhard | aplana el contraste medio; con `white 1.0` = Linear | ✗ |
| **Filmic** | conserva el matiz azul de la nieve hasta ~85 % de luminancia; contraste suave en sombras; es el que más se parece a la referencia (e0.6 → nieve (204,210,223)) | **✓ elegido**, exposición 0.55–0.7 |
| ACES | desatura los brillos (por diseño) y contrasta más: la nieve tiende a blanco (e0.6 → (211,216,228)); sombras más negras | ✗ (aceptable como 2.ª opción) |
| AgX | "mantiene el tono de los colores al aclararse" pero **desatura fuertemente los pasteles**: nieve gris (200,201,204) a e1.0 y (165,171,180) a e0.65; necesita ×2 exposición; `tonemap_agx_contrast` no lo arregla | ✗ para este estilo |

Reglas: exposición **0.55 (día), 0.65 (atardecer), 0.60 (noche), 0.55 (ventisca)**; `tonemap_white 1.0`. En
Compatibility el mismo preset sale **más claro** (§3.13): factor de exposición 0.5 (exposición 0.28 frente a 0.55) con sol × 0.75.
`adjustment_*` (brillo/contraste/saturación) se aplica **después** del tonemap y funciona en los tres renderers:
lo usamos solo como retoque (`saturation 1.05` de noche); no hace falta LUT 3D.

### 3.2 Cielo y ambiente

- `ambient_light_source = COLOR`, `ambient_light_sky_contribution = 0`, `reflected_light_source = DISABLED`
  (nieve mate; el cielo nunca entra en cámara a −48°). Determinista, gratis y el color exacto se controla por hora.
- El ambiente **lleva el azul** (día `#6A88C4` × 1.45; atardecer `#5A80B2` × 1.0; noche `#3E4A66` × 0.42, más gris)
  y el sol es cálido débil. Con sol fuerte + ambiente gris (slice) la nieve al sol es blanca y la sombra gris.
- `ProceduralSkyMaterial` se mantiene solo para la radiancia (irrelevante con reflejos desactivados); podría
  sustituirse por `BG_COLOR` sin cambio visible.

### 3.3 Sol, luna y sombras direccionales

| Parámetro | alto | medio | compat | Nota |
|---|---|---|---|---|
| Elevación máx. del sol | **26°** (curva `sin` × 26, hoy 38) | = | = | sombras largas todo el día; a 23° la sombra de la cabaña llega al borde inferior |
| Acimut | contraluz: `yaw = cam_yaw + 123°` (opción `sun_follows_camera`) o fijo 168° | = | = | ver riesgo R‑G4 |
| `directional_shadow_mode` | `PARALLEL_2_SPLITS` | = | = | 4 splits no aporta nada: el frustum es fijo y corto |
| `directional_shadow_max_distance` | 60 | 60 | 50 | cámara far 70–90 |
| `directional_shadow_split_1` / `fade_start` | 0.35 / 0.85 | = | = | |
| `shadow_bias` / `shadow_normal_bias` | 0.04 / 1.8 | = | 0.05 / 2.0 | con PCSS hace falta más normal bias en las barandillas |
| `shadow_blur` | 1.0 | 1.5 | 2.0 | |
| `light_angular_distance` (PCSS) | **1.2°** (sol), 3.0° luna, 4° ventisca | 0 | 0 (no soportado) | coste: +16 % del frame de día (243 → 210 ms sin PCSS) (lavapipe) |
| atlas / filtro (`Quality`) | 4096, `SOFT_HIGH` | 2048, `SOFT_MEDIUM` | 2048, `SOFT_LOW` | |
| Luna | `#8EA0C4` × 0.12, −42°, sombras suaves (blur 3) | = | sin sombras | la referencia nocturna casi no tiene sombra proyectada |

Hallazgos: PCSS con ángulo 1–1.5° da el "borde suave pero definido" de la referencia; por encima de 2.5° las
sombras de ramas finas se rompen (issues #63610, #91142) y el desenfoque depende de la distancia al origen del
mundo (#86536) → en el mundo de 3 km (M3) hay que **desplazar el origen** o limitar PCSS a la zona cercana.
`Sombras de contacto` (screen‑space) no aportan a 27 m. Las omni con sombra (farol, hoguera) sí se notan de noche
(barandilla del porche sobre la nieve): permitir **2 omni con sombra** en `alto`, 0 en `medio/compat`.

### 3.4 Iluminación global y oclusión

| Técnica | Prueba | Coste (lavapipe, relativo al día base) | Veredicto |
|---|---|---|---|
| SSAO (`radius 1.4, intensity 2.5, power 1.6, detail 0.4, light_affect 0.15`; proyecto: `ssao/quality = 2 (medium)`, `half_size = true`) | oscurece porche, bajos del camión y bases de pino | +28 % (243 vs 189 ms sin SSAO) | **✓ alto y medio** |
| AO horneada en `COLOR.a` (terreno por lista de ocluyentes; props por Blender) + `AO_LIGHT_AFFECT 0.35` | es la que se ve a 27 m y funciona en Compatibility | 0 | **✓ siempre** |
| SSIL (`radius 4, intensity 1.2`) | con ambiente de color plano **apaga** la escena (gris) y añade ruido | ×1.25 | ✗ |
| SDFGI (4 cascadas, celda 0.4, `y_scale 50 %`, `read_sky_light`) | rebote apenas perceptible a este ángulo (sombras un 2–3 % más claras); 30 frames de convergencia; cascadas visibles al mover cámara; no soporta ocluyentes dinámicos | ×1.6 | ✗ |
| VoxelGI | bounded, hay que hornear por zona; mundo procedural de 3 km | — | ✗ |
| LightmapGI | estático; solo tendría sentido en interiores de edificios a mano (M6/M9) | — | ✗ (revisar en M9 si los interiores lo piden) |
| Compatibility SSAO (docs 4.6+: versión simplificada) | **sin efecto en 4.7.2** con `ssao_enabled = true`: imagen idéntica píxel a píxel con y sin SSAO (`day_filmic_e0.28_compat.png` vs `day_nossao_filmic_e0.28_compat.png`); el oscurecido del porche que se ve en `compat` es la AO horneada | 0 | ✗ (no contar con ella) |

### 3.5 Niebla

| Preset | `fog_mode` | `fog_light_color` | `fog_density` | `fog_height` / `height_density` | `fog_aerial_perspective` | Volumétrica |
|---|---|---|---|---|---|---|
| Día | EXPONENTIAL | `#A9BEDC` | 0.0040 | −2 / 0 | 0.10 | no |
| Atardecer | EXPONENTIAL | `#6E86B8` | 0.010 | −1 / 0.015 | 0.15 | no |
| Noche | EXPONENTIAL | `#66788C` (**más claro que la nieve**) | 0.011 | −1 / 0.020 | 0 | no |
| Ventisca | EXPONENTIAL | `#AEB8C9` | 0.022 (compat 0.035) | 0 / 0 | 0 | `alto`: densidad 0.028, albedo `#D8DEE8`, anisotropía 0.35, `ambient_inject 0.5`, `length 64`, reproyección temporal ON en juego (OFF para capturas) |

`fog_sky_affect = 0` siempre. La niebla de altura (`fog_height`, `fog_height_density`) da la bruma baja del
atardecer y funciona en Compatibility. La volumétrica solo aporta en ventisca (haces de farol/ventanas en la
nieve en suspensión); coste +12 % de día (271 vs 243 ms) y +6 % en ventisca (314 vs 296 ms) (lavapipe) con `volume_size 64 / depth 64`. `FogVolume` locales
(hoguera, chimenea) quedan para M8 si sobra presupuesto.

### 3.6 Glow / bloom

`glow_enabled` solo cuando hay luces cálidas (atardecer/noche): `blend_mode SOFTLIGHT`, `intensity 0.55–0.7`,
`hdr_threshold 1.0–1.05`, `bloom 0.02` (noche), niveles por defecto. Las ventanas usan material **unshaded
emisivo** `#FFC070` × 3.0 (hoy 2.5). En Compatibility el glow existe (implementación distinta, sin niveles ni
blend) y da un resultado equivalente (`night_compat.png`).

### 3.7 Material de nieve (`shaders/snow_terrain.gdshader`) y variante para props (`world_vcol_v2.gdshader`)

Ambos incluyen `stylized_light.gdshaderinc` (función `light()` propia; soportada en los tres renderers):

| Uniform | Valor | Qué hace |
|---|---|---|
| `wrap` | 0.45 | difuso `(N·L + w)/(1 + w)`: sin terminador duro en drifts y troncos; la sombra proyectada sigue cortando |
| `sheen` / `sheen_power` | 0.08 / 12 | brillo ancho y débil (nieve no es glossy) |
| `shadow_fill` / `shadow_fill_color` | 0 / `#8CA8EB` | relleno azul ligado al sol (opcional; el ambiente ya lo hace) |
| `snow_color` (terreno) | `#CDDEF5` | albedo azul pastel |
| `ao_strength`, `ao_tint` | 1.0, `#9EB3E0` | AO de vértice (COLOR.a) oscurece **y azulea** |
| `rim_strength`, `rim_power`, `rim_color` | 0.12 / 3 / `#CCE0FF` | tinte de cielo en siluetas (mezclado en el albedo: sin brillo de noche) |
| `sparkle_strength`, `sparkle_density`, `sparkle_scale` | 0.8 / 0.975 / 18 (día); 0 de noche | destellos por celda de mundo, solo bajo sol directo; escala ≈ 2 px a 27 m |
| `noise_strength`, `noise_scale` | 0.022 / 0.06 | variación de tono con value‑noise (sin texturas) |
| `trail_*` | ver §3.10 | mapa de huellas |
| `snow_tint` (props) | `#DBE8FA` | los blancos de paleta (`snow #F1F5FA`) se tiñen para igualar al terreno; en producción, cambiar la paleta (Opus, v2.1) |
| `ao_height`, `ao_floor` (props) | 0.6 m, 0.55 | banda de contacto para assets sin AO horneada |
| `roughness_value`, `specular_value` | 0.85 / 0.2 (nieve), 0.9 / 0.15 (props) | |

Todo sin texturas (contrato ASSET_SPEC). Normales: el terreno usa **normales suaves** del campo de alturas; los HD
de Opus exportan normales propias (chaflanes endurecidos): **no forzar `dFdx/dFdy`** en el fragment como planeaba
ARQ v2 §8.3.

### 3.8 Terreno liso con AO por color de vértice

`scripts/terrain_builder.gd`: malla **indexada** (100 m, celda 0.5 m = 40 401 vértices / 80 000 tris), normal por
vértice desde las alturas vecinas, `COLOR.a = AO` calculada de una lista de ocluyentes (rect de cabaña con
`soft 2.2` y refuerzo bajo el porche; discos por pino/arbusto/roca/poste/personaje). Coste: 40 k vértices ×
50 ocluyentes en GDScript ≈ 1 s (una vez); en el juego se hace por chunk (65×65 ó 129×129) contra el scatter
del chunk y vecinos, con rejilla espacial. Es lo que da el "asentamiento" de los objetos en las capturas.

### 3.9 Huellas con reborde

| Opción | Cómo | Pros | Contras | Renderers |
|---|---|---|---|---|
| **A. Mapa de rastro** (elegida) | textura RG (1024² sobre 52 m) → shader del terreno: `VERTEX.y += −R·0.10 + G·0.035`, normal por diferencias finitas (×2.4), albedo ×(1−0.30·R)(1+0.15·G) | cualquier número de huellas, sin draw calls, acumula (surco), decae, ruedas/arrastres gratis, borde iluminado por el sol real | necesita malla ≥ 0.5 m para el hundimiento (la normal hace el resto), reproyección al cruzar 8 m (ARQ §14) | todos (`Image`/`SubViewport`); `DrawableTexture2D` 4.7 **funciona en Forward+ y en Compatibility** (4.7.2 sobre lavapipe/llvmpipe): 16 sellos pre‑rotados (22.5°) + `BlitMaterial BLEND_MODE_ADD`; resultado idéntico al back‑end `cpu` (`sheet_experiments.png`) |
| B. Huella de malla (`footprint_hd.glb`, 84 tris, reborde geométrico, MultiMesh) | instancia por pisada | nítida al hacer zoom (16 m), sombra propia | sin surco ni acumulación, z‑fight en pendiente, desvanecido por color de instancia | todos |
| C. `Decal` | proyecta normal + albedo | fácil | **no existe en Compatibility**; sin desplazamiento | Forward+/Mobile |

Back‑ends de A probados: `cpu` (`Image.set_pixel` + `ImageTexture.update`, ~0.1 ms por pisada + subida de 4 MB
por `flush`, válido en todos los renderers; en juego hacer `flush` como mucho una vez por frame) y `drawable`
(`DrawableTexture2D.blit_rect` con `trail_stamp.gdshader` `blend_add`; sin lectura de vuelta): **funciona en Forward+ y en Compatibility** (4.7.2 sobre lavapipe/llvmpipe): 16 sellos pre‑rotados (22.5°) + `BlitMaterial BLEND_MODE_ADD`; resultado idéntico al back‑end `cpu` (`sheet_experiments.png`).
Comparación con las huellas de malla de la loseta HD de Opus (`day_hdtile_forward_plus.png`): las huellas de malla son nítidas al hacer zoom pero no dejan surco ni se acumulan; a 27 m se leen como anillos claros sueltos (`sheet_footprints.png`). Recomendación: mapa de rastro siempre + malla opcional solo para las últimas 6 pisadas del jugador local.

### 3.10 Luz de las ventanas (derrame en la nieve)

`SpotLight3D` en el centro del cristal, apuntando 45° hacia abajo: `spot_angle 48`, `spot_range 9`,
`spot_attenuation 1.2`, `energy 9` (× `spill_scale`: 0.3 atardecer, 0.45 noche, 0.7 ventisca), color `#FFC070`,
`light_projector` = textura procedural 128² de 4 cristales (montantes al 25 %, borde suave) + `OmniLight3D` de
baño (`energy 2.2`, `range 4`) junto al marco. Sin sombra. Resultado: patrón de montantes en la nieve como en
`ref_night.jpg`. En Compatibility no hay proyectores → el mismo spot sin textura (mancha lisa; aceptable).
`AreaLight3D` (nuevo en 4.7) como "el propio cristal": funciona (baño ancho y suave desde el cristal, `night_arealight_forward_plus.png`) pero multiplica **× 6.4** el frame nocturno en lavapipe (1 874 vs 293 ms) y la doc avisa de coste en todos los objetos: **descartada**.

### 3.11 Partículas de ventisca

`CPUParticles3D`/`GPUParticles3D` con quad **5 × 22 cm alineado a la velocidad** (`particle_flag_align_y`), disco
suave procedural 32², alfa 0.7, viento (−0.8, −1, 0.3) × 5–8 m/s, `preprocess 5`. Los copos cuadrados de 8 cm
del prototipo inicial se leían como píxeles; las estrías se leen como viento. Cantidad por preset: 2 200 / 1 200 /
600.

### 3.12 Cámara

Se mantiene la del juego (pitch −48°, FOV 36, 27 m, yaw 45° en pasos). Con `CAMERA_DIST 24` la cabaña ocupa lo
mismo que en la referencia; recomendación: **por defecto 24 m** (rango 16–38 sin cambios).

### 3.13 Compatibility: qué se degrada y cómo

| Función | Forward+ (`alto`) | Compatibility (`compat`) | Mitigación |
|---|---|---|---|
| PCSS | sí | no (ignora `light_angular_distance`) | `shadow_blur 2.0`, filtro `SOFT_LOW` |
| SSAO | completa | sin efecto medible en 4.7.2 (imagen idéntica con/sin) | AO horneada lleva el look |
| Volumétrica | sí | no | niebla exponencial 0.035 |
| Proyector de luz | sí | no | spot liso |
| Glow | completo | simplificado | igual de válido |
| Luces por malla | ilimitado (clustered) | 8 omni + 8 spot | 3 luces de derrame + farol + hoguera + interior = 6 |
| Tonemap | Filmic | Filmic, **más claro** (las luces con sombra se mezclan en sRGB, issue #90259) | exposición × 0.5 (exposición 0.28 frente a 0.55) con sol × 0.75 en `compat` |
| `DrawableTexture2D` | **funciona en Forward+ y en Compatibility** (4.7.2 sobre lavapipe/llvmpipe): 16 sellos pre‑rotados (22.5°) + `BlitMaterial BLEND_MODE_ADD`; resultado idéntico al back‑end `cpu` (`sheet_experiments.png`) | funciona (probado) | back‑end `cpu` |
| Shader `light()` propio, `COLOR.a`, rim, sparkle | sí | sí (probado: `day_compat.png`, `night_compat.png`) | — |

---

## 4. Ajustes recomendados (tablas)

### 4.1 `Environment` por hora (claves de `day_night.gd`)

| Clave | Día (12 h) | Atardecer (19 h) | Noche (0 h) | Ventisca (mezcla) |
|---|---|---|---|---|
| Sol color / energía / elevación | `#F8F3EA` / 0.5 / 23° | `#FFB27A` / 0.12 / 6° | — | `#E6EAF2` / 0.25 |
| Luna | — | — | `#8EA0C4` / 0.12 / −42° | — |
| `ambient_light_color` × energía | `#6A88C4` × 1.45 | `#5A80B2` × 1.0 | `#3E4A66` × 0.42 | `#8E9DBA` × 1.25 |
| `fog_light_color` / densidad | `#A9BEDC` / 0.0040 | `#6E86B8` / 0.010 | `#66788C` / 0.011 | `#AEB8C9` / 0.022 |
| `fog_height` / `fog_height_density` | −2 / 0 | −1 / 0.015 | −1 / 0.020 | 0 / 0 |
| `fog_aerial_perspective` | 0.10 | 0.15 | 0 | 0 |
| `tonemap_mode` / `exposure` | FILMIC / 0.55 | FILMIC / 0.65 | FILMIC / 0.60 | FILMIC / 0.55 |
| `adjustment_saturation` | 1.0 | 1.0 | 1.05 | 0.9 |
| Glow | off | softlight 0.55, umbral 1.05 | softlight 0.7, umbral 1.0, bloom 0.02 | off |
| SSAO | 1.4 / 2.5 / 1.6 / 0.4 / 0.15 | 1.4 / 2.2 | 1.4 / 2.0 | 1.4 / 1.6 |
| Volumétrica | off | off | off | `alto`: 0.028 |
| Ventanas / farol / hoguera | off | on (spill 0.3) | on (spill 0.45) | on (spill 0.7) |
| `snow_amount` global | 0 | 0 | 0 | 0.7 |

Los valores exactos están en `prototypes/lookdev/godot/scripts/presets.gd` (fuente de verdad de este doc).

### 4.2 Presets de calidad (`Quality`)

| | `alto` | `medio` | `compat` |
|---|---|---|---|
| Renderer | Forward+ | Forward+ | gl_compatibility |
| Sombra direccional | 4096, 2 splits, `SOFT_HIGH`, PCSS 1.2°, blur 1.0 | 2048, 2 splits, `SOFT_MEDIUM`, PCSS 0, blur 1.5 | 2048, 2 splits, `SOFT_LOW`, blur 2.0 |
| Omni con sombra | 2 (farol, hoguera) | 0 | 0 |
| SSAO | medium, half_size | low, half_size | off (sin efecto, §3.4) |
| Volumétrica (ventisca) | on 64/64 | off | off |
| Proyectores de ventana | on | on | — |
| Glow | on | on | on |
| MSAA | 2× | 2× | 2× |
| Partículas | 1.0 | 0.6 | 0.35 |
| Huellas | mapa de rastro (`drawable` si 4.7 lo soporta, si no `cpu`) | igual | `cpu` |
| Exposición | preset | preset | 0.28 / 0.33 / 0.20 / 0.28 (día/atardecer/noche/ventisca) y sol × 0.75 |
| `snow_amount_max` | 0.7 | 0.7 | 0.6 |

---

## 5. Costes

### 5.1 Medidos en el contenedor (lavapipe/llvmpipe, 1280×720, escena look‑dev: 47 draw calls, 122 k prims)

Tiempo de "GPU" por frame que reporta el motor (rasterizador por software: **solo vale como ratio**):

| Configuración (misma escena y proceso, media de 10 frames) | ms (lavapipe) | Ratio vs. día base |
|---|---|---|
| Día `alto` (SSAO medium half + PCSS 1.2° + MSAA 2×) | 243 | 1.00 |
| Día sin PCSS | 210 | 0.86 |
| Día sin SSAO | 189 | 0.78 |
| Día sin MSAA | 226 | 0.93 |
| Día + glow | 280 | 1.15 |
| Día + volumétrica 64/64 | 271 | 1.12 |
| Día + SDFGI 4 cascadas (tras 30 frames) | 394 | 1.62 |
| Día + SSIL | 305 | 1.25 |
| Noche (glow + 3 spots con proyector + 2 omni con sombra) | 293 | 1.20 |
| Noche sin sombras omni | 288 | 1.18 |
| Noche sin proyectores | 297 | 1.22 (el proyector es gratis) |
| Ventisca (volumétrica + 2 200 partículas) | 314 | 1.29 |
| Ventisca sin volumétrica | 296 | 1.22 |
| Compatibility día / atardecer / noche / ventisca | 146 / 266 / 259 / 247 | — (127–136 draw calls: sin agrupación por material) |

Lectura: en este rasterizador el pixel‑shading domina; en una GPU real las sombras (2 splits × 48 draw calls) y
el SSAO pesan más en proporción y el shader de nieve menos. Los ratios sirven para ordenar, no para presupuestar.

### 5.2 Esperado en GPU media (GTX 1060 / RX 580 / Vega 8 de portátil, 1080p) — estimaciones a partir de la documentación y de informes de usuarios, sin medir aquí

| Efecto | Coste típico 1080p GPU media | Fuente/razón |
|---|---|---|
| Sombra direccional 4096, 2 splits, `SOFT_HIGH` | 1–2 ms (depende de draw calls; cada split re‑dibuja la escena) | docs lights_and_shadows: "doubling resolution is significant" |
| PCSS direccional 1.2° | +0.5–1.0 ms | docs: "noticeable performance cost" |
| SSAO medium half‑size | 0.6–1.2 ms | docs (half_size), informes |
| Glow (7 niveles) | 0.3–0.6 ms | |
| Volumétrica 64×64×64 | 1–2 ms (+ luces que la atraviesan) | docs: coste crece con `volume_size/depth` |
| SDFGI 4 cascadas | 3–6 ms + picos al mover cámara | docs: "one of the most demanding" |
| SSIL | 2–4 ms | informes ("15 fps por casi nada") |
| `AreaLight3D` visible | +coste en **todos** los objetos | docs class_arealight3d |
| Shader nieve (wrap + sparkle + 5 lecturas de mapa) | despreciable (fill‑rate de una sola capa opaca) | |

Presupuesto ARQ v2 §17.1 (frame ≤ 16.6 ms, objetivo 12): `alto` suma ≈ 4–6 ms de post/sombras; `medio` ≈ 2–3 ms.

---

## 6. Plan de integración: hito **G1 — Look premium** (después de M2, antes o en paralelo con M3)

**Tamaño**: **M** (Fable, un pase) + **S** (Opus: paleta v2.1 con nieve `#CDDEF5`, `COLOR.a` = AO horneada en
todos los assets, héroes HD ya en curso). Sin cambios de red ni de servidor (todo cliente).

| # | Fichero | Cambio |
|---|---|---|
| 1 | `assets/shaders/stylized_light.gdshaderinc` (nuevo) | copiar de `prototypes/lookdev/godot/shaders/` |
| 2 | `assets/shaders/world_vcol.gdshader` | sustituir por `world_vcol_v2.gdshader` (misma interfaz: `snow_include`, `frost_*`, `cutaway_tint`, `OUTPUT_IS_SRGB`; añade `light()` wrap, `AO = COLOR.a`, banda de contacto, rim, `snow_tint`) |
| 3 | `assets/shaders/terrain.gdshader` (nuevo, = `snow_terrain.gdshader`) + `assets/materials/terrain.tres` | material único del terreno (M3: lo comparten los chunks) |
| 4 | `scripts/world/terrain.gd` | malla **indexada con normales suaves** (quitar `_face` plano), `COLOR.a` = AO: nuevo `bake_ao(occluders)` llamado por `world.gd` después de `Scatter` (rect cabaña/A‑frame/camión + discos de árboles/rocas/arbustos); celda 0.5 m en el claro (o 1 m + normal del mapa de huellas). M3 hereda en `terrain_chunk.gd` |
| 5 | `scripts/world/day_night.gd` | `KEYS` con las columnas de §4.1 (ambiente, niebla, altura, exposición, saturación, glow, SSAO, spill); `tonemap FILMIC`; elevación máx. 26°; opción `sun_follows_camera` (yaw = cam + 123°); luna 0.12; `apply_preset_to_lights()` para farol/hoguera/ventanas |
| 6 | `scripts/autoload/quality.gd` | tabla §4.2: `pcss_angular`, `shadow_blur`, `ssao` (params), `volumetric`, `projectors`, `omni_shadows`, `exposure_scale` (compat), `trail_backend`; `apply_to_sun` fija `light_angular_distance`; `apply_to_environment` fija SSAO/volumétrica/glow **sin** pisar colores del `DayNight` |
| 7 | `scripts/world/cabin.gd`, `a_frame.gd`, `lantern.gd`, `campfire.gd` | `WindowSpill` (spot + proyector + omni de baño) por ventana con `spill_scale` por hora; farol/hoguera `shadow_enabled` según preset; `Assets.get_glow_material()` energía 3.0 |
| 8 | `scripts/effects/footprints.gd` → `scripts/effects/snow_trail_map.gd` (+ `assets/shaders/trail_stamp.gdshader`) | `SnowTrailMap` (ARQ v2 §14) con `stamp(pos, yaw, size, strength)`, back‑ends `cpu`/`drawable`, decaimiento, reproyección cada 8 m; `footprint_emitter.gd` llama a `stamp` en vez de instanciar mallas; el terreno recibe `trail_map`/`trail_rect` |
| 9 | `scripts/effects/snowfall.gd` | quad 5×22 cm alineado a velocidad, disco suave, alfa 0.7, cantidades por preset |
| 10 | `project.godot` | `environment/ssao/quality=2`, `ssao/half_size=true`, `volumetric_fog/volume_size=64`, `volume_depth=64`, `directional_shadow/soft_shadow_filter_quality=3` (Quality lo baja en `medio/compat`) |
| 11 | `scripts/data/balance.gd` | `CAMERA_DIST := 24.0` |
| 12 | `tests/screenshot.gd` + `tests/run_screenshots.sh` | presets `day/dusk/night/blizzard` en Forward+ (lavapipe) **y** Compatibility; contact sheet con las referencias (`tools/contact.py` del look‑dev) |

**Aceptación**: (1) `run_smoke.sh` y `run_screenshots.sh` en verde en ambos renderers; (2) capturas revisadas
contra `docs/screenshots/` viejas y las referencias (nieve al sol ≈ (170–200, 195–215, 220–235), sombra
≈ (105–120, 135–150, 175–190) de día; noche (50–70, 70–90, 95–120)); (3) presupuesto `alto` ≤ 12 ms en la GPU del
usuario (`tests/run_perf.sh` con `RENDER_*` monitors); (4) ARQ v2 §8.3 (normales por derivadas) y §14 actualizados.

**Fuera de G1**: SDFGI/SSIL/VoxelGI, LUT 3D, `AreaLight3D`, `FogVolume` locales, decals.

**Riesgos**

| # | Riesgo | Mitigación |
|---|---|---|
| R‑G1 | PCSS en mundo de 3 km: desenfoque ligado a la distancia al origen (#86536) y sombras de ramas rotas (#63610) | desplazamiento de origen ya previsto en ARQ §8 ("coordenadas grandes"); si no, `pcss` solo en `alto` y ángulo ≤ 1.2° |
| R‑G2 | Compatibility más claro que Forward+ (mezcla en sRGB con sombras) | `exposure_scale` por renderer en `Quality` (medido 0.5 (exposición 0.28 frente a 0.55) con sol × 0.75) y capturas de ambos en el test |
| R‑G3 | SSAO half‑size parpadea en barandillas finas al mover la cámara | `ssao_sharpness 0.98`, `detail 0.4`; si molesta, `half_size=false` en `alto` (+0.5 ms) |
| R‑G4 | Sol que sigue a la cámara (contraluz siempre) es una "trampa" que se nota al rotar en 45° | animar el yaw del sol con el tween de cámara (0.25 s) o dejar el sol fijo y aceptar que 2 de 8 orientaciones sean frontales |
| R‑G5 | AO horneada del terreno queda desfasada al talar árboles / construir | rehornear solo los vértices en 3 m del cambio (chunk local); tocón conserva el disco |
| R‑G6 | Mapa de rastro y streaming de chunks (M3) | el mapa es de mundo (52 m alrededor del jugador), independiente de chunks; reproyección al cruzar 8 m (ARQ §14) |
| R‑G7 | Coste de lavapipe no es el de GPU | verificar en la máquina del usuario con `--print-fps` y los monitores `RENDER_*` antes de cerrar G1 |

---

## 7. Índice de imágenes

| Fichero (en `lookdev_render/`) | Qué es |
|---|---|
| `ref_day.jpg`, `ref_dusk.jpg`, `ref_night.jpg`, `ref_night_campfire.jpg`, `ref_interior.jpg` | referencias del usuario |
| `before_day_game_compat.png`, `before_night_game_compat.png`, `before_blizzard_game_compat.png` | juego actual (Compatibility) |
| `day_forward_plus.png`, `dusk_forward_plus.png`, `night_forward_plus.png`, `blizzard_forward_plus.png` | look‑dev final Forward+ |
| `day_filmic_e0.28_compat.png`, `dusk_filmic_e0.33_compat.png`, `night_filmic_e0.20_compat.png`, `blizzard_filmic_e0.28_compat.png` | look‑dev en Compatibility (exposición compensada) |
| `sheet_tonemap.png`, `sheet_tonemap2.png` | AgX / ACES / Filmic vs referencia |
| `sheet_gi_compat.png` | SSAO / SDFGI / SSIL / Compatibility |
| `sheet_final_day.png`, `sheet_final_night.png` | antes / referencia / después |
| `day_hdtile_forward_plus.png` | loseta de terreno HD de Opus (huellas de malla) |
| `day_nopcss_forward_plus.png`, `day_nossao_forward_plus.png`, `blizzard_novol_forward_plus.png` | matriz de costes |
| `night_drawable_forward_plus.png`, `night_drawable_compat.png` | back‑end `DrawableTexture2D` |
| `night_arealight_forward_plus.png` | `AreaLight3D` |
| `sheet_experiments.png`, `sheet_footprints.png`, `sheet_presets2.png`, `sheet_compat_exp.png` | AreaLight / DrawableTexture2D / SSAO en Compatibility; huellas (mapa vs malla vs Drawable); presets vs referencias; exposición en Compatibility |

---

## 8. Fuentes

- Godot docs (mirror GitHub `godotengine/godot-docs`, master, sept‑2026): `tutorials/3d/environment_and_post_processing.rst`,
  `tutorials/3d/lights_and_shadows.rst`, `tutorials/3d/global_illumination/introduction_to_global_illumination.rst`,
  `tutorials/3d/global_illumination/using_sdfgi.rst`, `tutorials/3d/volumetric_fog.rst`,
  `tutorials/rendering/renderers.rst`, `tutorials/rendering/drawable_textures.rst`,
  `tutorials/shaders/shader_reference/spatial_shader.rst`, `classes/class_environment.rst`,
  `classes/class_drawabletexture2d.rst`, `classes/class_arealight3d.rst`.
- Godot PRs/issues: #87260 (AgX), #102425/#102435/#106940 (AgX white/contrast), #101365 (AgX en Compatibility),
  #63610, #91142, #86536, #103069, #113976 (PCSS direccional), #90259 (Compatibility: luces con sombra más claras),
  proposal #12059 (SSAO en Compatibility, 4.6), PR #105701 (DrawableTextures), #123507 (DrawableTexture2D en D3D12).
- Godot 4.5/4.6/4.7 notas de versión (stencil, SMAA, AreaLight3D, DrawableTexture2D, HDR output).
- Mediciones propias: `prototypes/lookdev/godot/` + `tools/contact.py`.
