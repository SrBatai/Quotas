# 08 — Pase gráfico G2: ciudad invernal "AAA estilizada" (plan de render)

> Proyecto VENTISCA. Motor **Godot 4.7.2** (Forward+ por defecto; Compatibility para `compat` y la build Web). Estado
> de partida: **G1 integrado** (doc 06 §9: Filmic, ambiente azul, sol bajo a contraluz, PCSS, SSAO, AO horneada en
> `COLOR.a`, shader de nieve con `snow_amount` global, mapa de huellas con `DrawableTexture2D`, derrame de ventanas).
> Fecha: 2026‑09‑26. Autor: dirección de arte / arte técnico (Opus). Base: doc 07 (assets CC0 + pase `winterize`,
> renders de un bloque de ciudad) y la referencia de clases de Godot **4.7.2‑stable** (`godotengine/godot`,
> `doc/classes/*.xml`, tag `ed1daf0`), porque `godotengine.org` está bloqueado desde el entorno.
>
> Pedido: ¿qué debe hacer el render a continuación para un look "AAA estilizado invernal" con **ciudades con
> rascacielos** y un mundo **habitado**? Referencias: *The Long Dark*, *Frostpunk 1/2*, *Sable*, *Tunic*, *Death
> Stranding* (nieve), *The Ascent* (ciudad isométrica), *Diablo IV* (luz isométrica), *Project Zomboid*.

---

## 0. Resumen ejecutivo

**El hallazgo que ordena todo G2**: con nuestra cámara (pitch −48°, FOV 36°, 24 m) la cámara está a **17.8 m** de
altura y el borde superior del encuadre baja **30°** respecto a la horizontal: **nada por encima de la altura de la
cámara entra jamás en pantalla** (28 m con el zoom máximo de 38 m). Un rascacielos de 100 m se ve como sus 18 m de
abajo, su sombra de más de 200 m y —si está entre la cámara y el jugador— como una pared que lo tapa todo
(`previews/city_tower_camera_inside_gamecam24.png`: con el jugador pegado a la torre la cámara queda dentro y la imagen sale negra; `city_tower_camera_inside_fade_gamecam24.png`: la misma con el fundido propuesto). El *skyline* solo existe en el mapa, en menús y en momentos
cinemáticos. Consecuencias: (1) el **fundido de edificios altos** es obligatorio antes que cualquier efecto;
(2) el detalle de las torres se invierte en **base, azotea baja y sombra**, no en el fuste; (3) la "ciudad" se vende a
pie de calle: **tráfico congelado, luces, humo, niebla entre torres y sombras de cañón urbano**.

Prioridades (coste estimado a 1080p en GPU media tipo GTX 1060 / RX 580; ✓ = funciona en Compatibility/Web):

| P | Qué | Por qué | Coste `alto` | Web/compat |
|---|---|---|---|---|
| **P0** | **Fundido de edificios altos** (dither en `world_vcol` dentro del cilindro cámara→jugador) + silueta del jugador tras muros | sin esto la ciudad no es jugable | 0.1–0.4 ms (medido +13 % en lavapipe con una torre a pantalla completa) | ✓ (dither opaco; probado en Compatibility) |
| **P0** | **Nieve por normal v2** en todo (ruido de borde, abrigo por AO, nieve pegada a barlovento, deshielo junto a fuentes de calor) | une Kenney + Quaternius + lo nuestro en una sola familia | 0.1–0.3 ms | ✓ |
| **P0** | **Ciudad de noche**: ventanas por celdas con ocupación "hash" (emisivo, sin luces), farolas reales solo cerca, charcos de luz falsos, balizas | "habitado" y legible | 1.0–1.6 ms | ✓ (emisivo + charcos; ≤ 8 luces/malla) |
| **P0** | **Presupuesto de ciudad**: torres en 3 piezas (base detallada, fuste barato, sombra *proxy*), `visibility_range` + HLOD por chunk, LOD automático | 6 × 6 km con ciudad sin pasar de 1 000 draw calls típicos | ahorra 1.5–3 ms | ✓ (sin fundido de HLOD) |
| **P1** | **Niebla en capas**: exponencial + altura (bruma de calle), `FogVolume` locales (vapor, chimeneas) y volumétrica solo en ventisca/noche | profundidad entre torres, "cañón urbano" | 0.1 / +1.0–2.0 (vol.) | parcial (sin vol.) |
| **P1** | **Viento y nieve que vuela**: serpientes de nieve a ras de suelo, ruido de arrastre en el terreno, viento por vértice | invierno vivo sin geometría | 0.3–0.6 ms | ✓ (menos partículas) |
| **P1** | **Huellas/rodadas a escala de ciudad**: mapa local actual + mapa persistente de baja resolución por chunk (coches, hordas, carreteras aradas) | el mundo "recuerda" | 0.1–0.2 ms | ✓ |
| **P1** | **Gradación por LUT 3D** por clima/hora/región (mezclada en CPU), viñeta, glow retocado | *The Long Dark*: cada hora un cuadro | 0.05–0.1 ms | ✓ |
| **P1** | **Vida**: humo (partículas + sprites CC0), fuegos, luces que parpadean, bandadas, fauna | pilar "habitado" | 0.3–0.8 ms | ✓ |
| **P2** | **Calcomanías** (aceite, sangre, hollín, rodadas en asfalto, escarcha) | detalle a pie de calle | 0.2–0.4 ms | ✗ (malla‑calcomanía) |
| **P2** | **SSR** en hielo del lago, cristal de torres y charcos helados | brillo "premium" puntual | 0.8–1.5 ms (half) | ✗ (sonda/fresnel) |
| **P2** | **AA**: MSAA 2× + **SMAA** en `alto`; FSR2 como opción ≥ 1440p | el flat‑shading tiene bordes durísimos | +0.3–0.5 ms | MSAA solo |
| **P3** | Cielo/HDRI (solo reflejos y menús), *occlusion culling* (medir), `AreaLight3D` (no) | poco retorno con cámara alta | — | — |

**Presupuesto objetivo** (§5): `alto` ≤ 12 ms (día) / ≤ 14 ms (noche en ciudad, ventisca) con FSR2 opcional para
recuperar 2–3 ms; `medio` ≤ 10 ms; `compat` escritorio ≤ 16.6 ms; **Web** 30 fps a 1280 × 720 (≤ 33 ms, objetivo
25) con ≤ 500 draw calls y ≤ 350 k tris.

**Medido en Godot 4.7.2** (§5.0, bloque de ciudad con los shaders del juego, rasterizador por software → solo
proporciones): 152 draw calls y 323 k primitivas en total, de las que **247 k son de las pasadas de sombra** (54 % del
frame); SSAO 16 %, MSAA 2× 9 %, SMAA +9 %, SSR +14 %, volumétrica +18 %, noche de ciudad +10 %, fundido de torre
+12–13 %. Los prototipos de ventanas por celdas y de fundido funcionan en Forward+ y en Compatibility.

**Hito**: G2 en tres pases (G2a ciudad jugable, G2b atmósfera, G2c detalle), §6. Tamaño total: **L (Fable) + M (Opus)**.

---

## 1. Punto de partida y qué cambia con la ciudad

| Tema | G1 (hoy) | Con ciudad (G2) |
|---|---|---|
| Geometría visible | claro/bosque: ≈ 200–270 k tris, 350–700 draw calls | calle con 40 coches, 10 edificios, 30 farolas, props: **400–700 k tris, 600–1 100 draw calls** (contado en la escena de Blender del doc 07: 12 edificios 150 k + 31 coches 138 k + 14 farolas 35 k + barreras 6 k ≈ **329 k tris** solo de assets winterizados, sin terreno, personajes ni vegetación) |
| Sombras | casters bajos (≤ 10 m) | torres de 60–105 m: con el sol a 23° la sombra de una torre mide **≈ 235 m**; casters fuera de pantalla entran en el mapa de sombras |
| Luces | ventanas de 2 casas, farol, hoguera | decenas de farolas, cientos de ventanas, fuegos, balizas |
| Oclusión | `CutawayManager` para interiores | **edificios que tapan al jugador desde fuera** |
| Escala del mundo | 3 × 3 km (PLAN C6) | **6 × 6 km** (decisión del dueño): coordenadas hasta ±3 km en precisión simple (bien; ≈ 0.25 mm de resolución), pero el desenfoque PCSS depende de la distancia al origen (#86536, doc 06 R‑G1) → desplazamiento de origen o PCSS solo cerca del origen |
| Build Web | preset `compat` + plantilla *nothreads* (ARQ §8.9); ojo: el PLAN §10.9 dice "Web fuera de v2.0" pero hay preset de export Web | se fija aquí un presupuesto Web explícito (§5.3) |

### 1.1 Geometría de la cámara (por qué el *skyline* no se ve)

Con distancia `d`, pitch 48° y FOV vertical 36°: altura de cámara `h = d·sin48°` (17.8 m a 24 m; 28.2 m a 38 m);
retroceso horizontal `d·cos48°` (16.1 m). Borde superior del encuadre a 48 − 18 = **30°** bajo la horizontal: corta el
suelo a `h / tan30°` = 30.9 m de la cámara (14.8 m **más allá** del jugador); borde inferior a 66° (8.2 m **antes** del
jugador, del lado de la cámara). Profundidad de suelo visible ≈ 23 m, anchura ≈ 28 m. Cualquier punto más alto que `h` queda fuera del
frustum. Una torre tapa al jugador si su planta corta el segmento jugador→cámara (16 m en planta, en la diagonal de
la cámara) a una altura mayor que la de la línea de visión (0 → 17.8 m).

Lecciones de las referencias con cámara alta: *The Ascent* compensa con **profundidad hacia abajo** (pasarelas sobre
abismos) y cambios puntuales de cámara; *Diablo IV* y *Project Zomboid* ocultan/recortan lo que tapa al personaje y
**nunca** muestran la parte alta de los edificios en juego; el *skyline* es escenografía de fondo o de menú.
Para "vender" los rascacielos sin tocar la cámara de juego: (1) una **cinemática** corta al entrar por primera vez en la
ciudad; (2) una acción **"otear"** desde azoteas y desde la torre de vigilancia (el ancla `ViewAnchor` de
`lookout_tower` ya existe) con cámara a 20–25° de pitch durante unos segundos; (3) **mapa y menú** con la ciudad
renderizada (`city_after_*_aerial.png`); (4) las **sombras** de las torres sobre la calle, que sí se ven siempre.

---

## 2. Qué tomamos de cada referencia

| Referencia | Qué copiar (concreto) | Dónde en G2 |
|---|---|---|
| *The Long Dark* | "acuarela": pocas masas de color, siluetas nítidas, **una gradación por hora del día** (amanecer rosa, mediodía azul, noche azul‑verde) y niebla que pinta la distancia | LUTs por clima/hora (§3.7), niebla en capas (§3.5) |
| *Frostpunk 1/2* | la **nieve cede donde hay calor** (mapa de calor que descubre el suelo y los tejados), vapor y humo como lenguaje de "aquí hay vida", escarcha en el borde de pantalla con frío extremo | deshielo en el shader de nieve (§3.2), humo (§3.9), `frost_vignette` ya existe |
| *Sable* | disciplina de **valores planos**: pocos degradados, sombras legibles, color por grandes zonas | la gradación OKLab del doc 07 y límites de croma |
| *Tunic* | luz **suave que rebota** (lo iluminado aclara lo de al lado), bloom leve, mundo "de maqueta" leído desde arriba | AO horneada + ambiente de color (ya), glow suave, sin DoF (evitar efecto maqueta en ciudad) |
| *Death Stranding* | nieve con **volumen real** que se hunde y guarda las huellas (teselación en ventisqueros; *Batman: Arkham Origins* hacía lo mismo con mapas de desplazamiento en tiempo real) | Godot no tesela: desplazamiento de vértices en malla de 0.5 m cerca de cámara + mapa de huellas (§3.3) |
| *The Ascent* | **capas y verticalidad** en una ciudad densa, cientos de luces pequeñas, niebla que separa planos, **mucho detalle a pie de calle** | fundido de torres, props y tráfico, niebla de calle, luces falsas (§3.1, §3.4) |
| *Diablo IV* | noche con **niebla, sombras suaves y rebote**: la luz local define el espacio; el personaje siempre legible (borde y silueta) | charcos de luz, rim ya presente, silueta X‑ray (§3.1) |
| *Project Zomboid* | ciudad abandonada **legible desde arriba**: coches en atascos, ventanas rotas, luces que se apagan con los días, cortes de edificio | ocupación de ventanas que decae con los días, estados de "apagón" por barrio (§3.4) |

---

## 3. Técnicas (qué, cómo en Godot 4.7, coste, Web)

### 3.1 P0 — Fundido de edificios altos y silueta del jugador

- **Qué**: los píxeles de edificios/props marcados `fadeable` que estén **entre la cámara y el jugador local**, dentro de
  un cilindro de radio 4–6 m alrededor del segmento cámara→jugador (o de una cápsula en espacio de pantalla), se
  descartan con un patrón de *dither* ordenado (Bayer 4×4) hasta un 75–85 %, con transición de 0.25 s. El resto del
  edificio queda opaco. Referencia visual: `previews/city_tower_camera_inside_fade_gamecam24.png` (Cycles) y
  `previews/godot_tower_fade.png` (prototipo en Godot).
- **Caso "cámara dentro"**: la cámara está a 16 m en planta y 17.8 m de altura del jugador; con torres de 13–15 m de
  lado, cuando el jugador camina junto a la fachada opuesta a la cámara **la cámara queda dentro de la torre** (en la
  prueba de Cycles, `city_tower_camera_inside_gamecam24.png` sale negra por eso y `city_tower_camera_inside_fade_gamecam24.png`
  muestra el mismo encuadre con la torre fundida). El fundido debe
  incluir todo el edificio cuya caja contiene la cámara (o recortar su parte por encima de ~2 m, como el corte de
  interiores) y el `near` de la cámara no lo arregla.
- **Cómo**: en `world_vcol.gdshader` (y en `window`), `global uniform vec3 player_pos` + `CAMERA_POSITION_WORLD`,
  distancia punto‑segmento en `fragment()`, `discard` por umbral de Bayer; activación por instancia con
  `instance uniform float fade_enable` (lo pone `CityOcclusion` solo en los 2–6 edificios que cortan el segmento,
  detectados con un `ShapeCast3D`/rayos cada 0.1 s). Es opaco (sin ordenar transparencias), así que funciona igual en
  Forward+ y Compatibility. Complemento: silueta del personaje tras muros con `BaseMaterial3D.stencil_mode =
  STENCIL_MODE_XRAY` (4.5+, **experimental**; verificar en Compatibility) o, si falla, una segunda pasada
  `depth_test_disabled` con alfa 0.35 solo para jugadores/zombis cercanos.
- **Relación con el corte**: `CutawayManager` sigue mandando dentro de edificios enterables; el fundido es el caso
  "exterior" y usa el mismo registro de edificios.
- **Coste**: 0.1–0.4 ms según cuánta pantalla ocupe el edificio (medido: +13 % del frame en lavapipe con una torre a
  pantalla completa, §5.0); el *discard* impide el *early‑Z* solo en esos píxeles. Prototipo funcionando en Forward+ y
  Compatibility: `g2_assets/godot_city/assets/shaders/world_vcol_fade.gdshader`.

### 3.2 P0 — Nieve por normal v2 (acumulación en todo)

Hoy: `apply_snow()` mezcla `snow_color` por `smoothstep(0.55, 0.85, n.y) · snow_amount` y el pase `winterize` hornea
losas de nieve. G2 lo convierte en **un solo modelo de nieve** para assets propios y de terceros:

| Término | Implementación | Por qué |
|---|---|---|
| Borde roto | `n.y` + ruido de valor en espacio mundo (0.6 m y 2.5 m) antes del `smoothstep` | la línea de nieve deja de ser un umbral limpio (se ve "pegada" a la forma) |
| Abrigo | multiplicar por `mix(0.35, 1, COLOR.a)` (la AO horneada) | menos nieve bajo aleros, en huecos y bajos de coche |
| Barlovento | `max(dot(n, -wind_dir), 0)` en caras verticales × `snow_amount` × `wind_strength` | ventisca: nieve pegada a un lado de postes, fachadas y coches (muy *Death Stranding*) |
| Espesor por instancia | `INSTANCE_CUSTOM.a` = "edad" del objeto (coches del atasco: días bajo la nieve) | variedad sin más assets |
| Deshielo | `global uniform vec4 heat_sources[16]` (pos + radio) o un `DrawableTexture2D` de calor de 128² alrededor de la cámara: resta nieve y **oscurece/moja** (roughness 0.35) cerca de hogueras, motores y estufas | *Frostpunk*: el calor se ve; además es información de juego (dónde hay refugio) |
| Escarcha en cristal | los materiales `window`/`glass` reciben `snow_amount`/`frost_amount` como escarcha con máscara de ruido en espacio mundo + `n.y` (sin UV) | coches y ventanas "congelados" |

Coste: 2–3 evaluaciones de ruido por píxel opaco: **0.1–0.3 ms** a 1080p (relleno de una capa). Todo en
`snow_include.gdshaderinc`, válido en los tres renderizadores.

### 3.3 P1 — Nieve deformable a escala de ciudad

- **Local (ya existe)**: mapa de rastro RGBA8 1024² sobre 56 m alrededor de la cámara (`DrawableTexture2D`), huellas de
  jugadores, zombis y animales; decaimiento 0.99/s.
- **Nuevo, persistente y barato**: **mapa de rodadas por chunk** (64 m a 0.25 m/px = 256² R8, 64 KB): vehículos,
  arado (quitanieves M10), caminos muy transitados y el **rastro de la horda** (M9b ya lo pide). Se sella con la misma
  API `stamp()` y se guarda con el chunk en el cliente (cosmético; el servidor no lo conoce, C17). El shader del
  terreno lo lee de un `Texture2DArray` indexado por chunk del anillo 7 × 7 (49 × 64 KB ≈ 3 MB).
- **Carreteras**: estado base "arada con surcos" (como en los renders del doc 07) que se **rellena con `snow_amount`**
  durante una ventisca y se reabre al pasar coches; asfalto que asoma = `snow_packed`/asfalto mojado.
- **Volumen**: sin teselación en Godot; malla del terreno a 0.5 m en el anillo cercano (hoy 1 m) + normal del mapa.
- Coste: 0.1–0.2 ms (1–2 lecturas extra en el terreno) + sellos en GPU. Web: back‑end `cpu` si `DrawableTexture2D`
  falla en WebGL2 (probado en Compatibility de escritorio, doc 06).

### 3.4 P0 — Ciudad de noche: ventanas, farolas, charcos de luz

1. **Ventanas por celdas** (renders `city_after_night_*.png`): el material `window` calcula una celda en espacio
   mundo (planta 3.8 m × vano 2.4 m), `hash(celda)` decide si está encendida (**20–35 %**), su color (cálido 85 %,
   frío/TV 12 %, parpadeo 3 %) y cambia lentamente (`floor(TIME/600)`). Un `global uniform float city_power` por
   distrito permite **apagones** (solo quedan fuegos y 1–2 ventanas de supervivientes: *Project Zomboid*). Coste ≈ 0
   (emisivo). El glow las recoge. Prototipo: `g2_assets/godot_city/assets/shaders/window_city.gdshader` (Forward+ y
   Compatibility).
2. **Farolas reales solo cerca**: `OmniLight3D`/`SpotLight3D` sin sombra en las ≤ 12–16 farolas a < 40 m; más lejos, solo
   bombilla emisiva + **charco de luz falso** (quad aditivo *unshaded* sobre la nieve con degradado radial, 2 tris) y
   halo *billboard*. Así la noche se ve igual en Compatibility (límite de 8 luces por malla).
3. **Presupuesto de luces Forward+** (cluster): ≤ 64 luces visibles, ≤ 2 con sombra (hoguera, linterna del jugador),
   farolas con `light_specular 0.2` y rango 9–12 m. Coste: **1.0–1.5 ms** con 40–60 luces a 1080p.
4. **Balizas y señales**: luz roja de azotea (se ve en el mapa/menú), semáforos en ámbar intermitente, rotativos de
   policía/ambulancia en el atasco: emisivos animados por `TIME` + 1 luz real para el vehículo más cercano.
5. **Volumétrica**: solo `alto`, en niebla nocturna o ventisca (conos de farola); nunca en Web.

### 3.5 P1 — Niebla en capas

| Capa | Godot 4.7 | Valores de partida (ciudad) | Renderizadores |
|---|---|---|---|
| Profundidad | `FOG_MODE_EXPONENTIAL` (o `FOG_MODE_DEPTH` con curva) | día 0.004 (G1); ciudad de noche 0.012 | todos |
| Altura (bruma de calle) | `fog_height` / `fog_height_density` | calle a −1 m, densidad 0.02–0.035 al amanecer/noche: las bases de torre se hunden en bruma y las azoteas bajas quedan limpias | todos |
| Local | `FogVolume` (caja/elipsoide) con material de ruido | vapor de alcantarillas, humo de coche ardiendo, chimeneas industriales, niebla en el río | **solo Forward+** (volumétrica) |
| Volumétrica global | `volumetric_fog_*` | ventisca (0.028, doc 06) y noches de niebla en ciudad; reproyección temporal ON | **solo Forward+** |

Coste: exponencial + altura ≈ 0.05 ms; volumétrica 64×64 ≈ 1–2 ms (+ luces que la atraviesan). La niebla del color
del cielo es lo que da profundidad entre torres (*The Ascent*, *The Long Dark*).

### 3.6 P3 — Cielo / HDRI

La cámara del juego **no ve el cielo** (borde superior 30° bajo la horizontal). El cielo solo importa para: (a)
reflejos (SSR/sondas en cristal de torres y hielo), (b) menú, mapa y cinemáticas. Recomendación: seguir con
ambiente de color (G1) y un `ShaderMaterial` de cielo procedural (gradiente + nubes en capas + sol/luna) para
reflejos y menús. HDRI de Poly Haven solo si se abre el dominio (doc 07 §6) y solo para el menú.

### 3.7 P1 — Gradación, glow, viñeta

- **LUT 3D**: `Environment.adjustment_color_correction` acepta `Texture3D` (y `GradientTexture1D`); **no funciona con
  salida HDR** (4.7 lo documenta). Se generan por script (Python, OKLab: *lift/gamma/gain*, saturación por rango de
  luminancia, virado de sombras) 6–8 LUT de 32³: `dia_claro`, `nublado`, `ventisca`, `atardecer`, `noche`,
  `noche_ciudad` (sodio desaturado), `apagon`, `calor` (junto al fuego). **Mezcla en CPU**: al cambiar de clima o región
  se interpola entre dos LUT en un `ImageTexture3D` (32 768 texels, ≈ 0.1 ms de CPU por actualización, solo durante la
  transición): funciona en los tres renderizadores (la alternativa `CompositorEffect` es solo Forward+/Mobile).
- **Glow**: desde 4.6 se compone **antes** del tonemap y `SCREEN` es el modo por defecto; los valores de G1 se midieron
  en 4.7.2, así que valen; en Compatibility el modo de mezcla se ignora (siempre `SCREEN`). Mantener glow solo con
  luces cálidas + ventanas.
- **Viñeta** 10–15 % (en el `frost_vignette` existente) y **grano** 1–2 % opcional (disimula el *banding* de los
  degradados de nieve; alternativa: `use_debanding`, que no existe en Compatibility).
- Coste total < 0.1 ms.

### 3.8 P2 — Reflejos en hielo (SSR)

SSR reescrito en 4.6 (trazado Hi‑Z, modos de media y resolución completa); **solo Forward+**. Uso: lago helado,
cristal de torres a pie de calle, placas de hielo en la calzada. Activar solo cuando la región lo pide
(`RegionTracker` → `ssr_enabled`), `half_size = true`, `ssr_max_steps` 32–48. Coste: **0.8–1.5 ms**. Compatibility/Web:
`ReflectionProbe` (máx. 2 por malla en Compatibility) o simplemente fresnel hacia el color del cielo + brillo del
sol en el shader del hielo (≈ 0 ms), que a 24 m se lee casi igual.

### 3.9 P1 — "Vida": humo, fuego, luz, animales

| Elemento | Técnica | Coste | Web |
|---|---|---|---|
| Humo de chimeneas/incendios | `GPUParticles3D` 60–200 partículas con *flipbook* (Kenney Particle Pack, CC0), iluminado sin sombras, deriva por viento; `FogVolume` en `alto` para vapor denso | 0.1–0.3 ms por columna cercana (sobredibujado) | ✓ |
| Fuegos (barriles, coches) | llama aditiva + `OmniLight3D` con parpadeo (`LightFlicker`, ya existe) + deshielo del §3.2 | 0.1 ms | ✓ |
| Luces intermitentes | emisivos animados por `TIME` (semáforos, rotativos, alarmas) | 0 | ✓ |
| Bandadas (cuervos) | `GPUParticles3D` con malla de 30–60 tris y aleteo por vértice (`INSTANCE_CUSTOM` = fase) | < 0.05 ms | ✓ |
| Fauna | Quaternius *Ultimate Animated Animals* (doc 07) con LOD de animación 10–15 Hz | según M9b | ✓ |
| Rastros | huellas/rodadas (§3.3), puertas abiertas, ventanas rotas, mantas y ropa tendida con viento por vértice | ≈ 0 | ✓ |

### 3.10 P1 — Viento y nieve que vuela

- **Serpientes de nieve**: `GPUParticles3D` de 400–1 200 quads estirados (0.4 × 2.5 m, alfa 0.15–0.3) a ras de suelo
  en una caja de 40 m que sigue a la cámara, a la velocidad del viento (6–14 m/s), con densidad por `wind_strength`.
- **Arrastre en el terreno**: el shader del terreno desplaza un ruido de albedo/normal en la dirección del viento
  (ondas de nieve suelta que corren por el suelo): 1 lectura de ruido, ≈ 0.02 ms.
- **Viento por vértice**: pinos (balanceo por altura en el `MultiMesh`), cables, lonas, banderas, ropa.
- **Rachas**: pulsos de densidad de niebla y partículas + `frost_vignette` en frío extremo.
- Coste: 0.3–0.6 ms (sobredibujado de partículas; mitad en `medio`, 35 % en Web).

### 3.11 P2 — Calcomanías

`Decal` es *clustered* y barato en Forward+/Mobile (**no existe en Compatibility**; Mobile: 8 por malla). Usos: manchas
de aceite bajo coches, sangre en nieve y asfalto, hollín sobre ventanas quemadas, escarcha en muros, grafitis,
"nieve apartada" delante de puertas usadas. Requiere **un atlas de calcomanías** (1–2 MB, excepción al "sin
texturas"). ≤ 64 visibles; coste 0.2–0.4 ms. Web/compat: la misma lista como **mallas‑calcomanía** (quads con
`world_vcol` + alfa, ya usados por la sangre de M4) o sellos en el mapa de rodadas.

### 3.12 P2 — Antialiasing

| Opción | Renderizadores (4.7.2) | Juicio para nuestro look |
|---|---|---|
| MSAA 2× (hoy) | todos (WebGL2 incluido) | lo mejor para bordes geométricos duros (edificio oscuro sobre nieve clara); no quita el *aliasing* de sombreado (destellos de nieve, rejilla de ventanas, cables) |
| **SMAA** (4.5+) | Forward+/Mobile | **añadir en `alto`** (0.3–0.5 ms): limpia rejillas de ventanas y líneas finas sin fantasmas |
| FXAA | Forward+/Mobile | emborrona la nieve; no |
| TAA | **solo Forward+**; la doc avisa de *ghosting* en partículas y mallas con *skin* | riesgo alto con nieve cayendo y 60 zombis; no por defecto |
| FSR 2 (`SCALING_3D_MODE_FSR2`) | Forward+ | opción "Rendimiento/Calidad" ≥ 1440p (escala 0.67–0.77: ahorra 2–4 ms), con el mismo riesgo de fantasmas que TAA |
| Escalado *nearest* (4.7) / bilinear | todos | Web en iGPU: 0.75–0.85 de escala |

### 3.13 P0 — LOD, HLOD, impostores y oclusión para una ciudad de rascacielos

1. **Torres en tres piezas** (contrato del doc 07 §4.2): `Tower_Base` (0–24 m, detallada: vestíbulo, marquesinas,
   nieve, ventisqueros), `Tower_Shaft` (fuste: en juego nunca se ve por encima de 18–28 m → malla barata con
   ventanas por shader) y `Tower_Shadow` (caja/`low_*` de 150–400 tris con `cast_shadow = SHADOWS_ONLY`). La geometría
   cara no entra en las pasadas de sombra. Medido (§5.0): en la vista de prueba las 5 torres cercanas son el **15 % del
   coste de sombras** (70 k de 247 k primitivas de sombra) aun estando fuera de cuadro; entre torres, más. Ahorro
   estimado 0.3–1 ms.
2. **`visibility_range`**: props 60–80 m, coches 90 m, edificios 120–160 m (con la cámara a 38 m y `far` 70–90);
   `visibility_range_fade_mode` con `visibility_parent` para HLOD (el fundido suave es solo Forward+; en
   Compatibility es un corte con histéresis desactivada).
3. **HLOD por chunk** (64 m): una malla fusionada por manzana (3–8 k tris, mismo `world_vcol`) para distancias > 120 m,
   el mapa y la vista de menú; los `low-detail-building-*` de Kenney sirven de impostor 3D de torres (62–378 tris).
4. **LOD automático** del importador (`meshes/generate_lods`, activo) con `mesh_lod_threshold` 1.0; en `MultiMesh` el
   LOD va por la AABB del conjunto → *multimeshes* por chunk (ya en M3).
5. **Occlusion culling** (`OccluderInstance3D`): CPU con Embree; **no disponible en la plantilla Web por defecto**
   (requiere `module_raycast_enabled=yes`). Con cámara alta ocluye poco; medir en la ciudad antes de activarlo (P3).
6. **Instanciación**: 600–1 000 objetos por pantalla en ciudad exigen `MultiMesh` para farolas, coches aparcados,
   papeleras y señales (una por tipo y chunk) y edificios fusionados por grupo de corte (C8).

### 3.14 Descartes y avisos

- `AreaLight3D` (4.7): ×6.4 el frame nocturno en lavapipe (doc 06); sin sombras en Compatibility. **No**.
- SDFGI/SSIL/VoxelGI/Lightmap: siguen descartados (doc 06 §3.4). Para el "cañón urbano": **AO de cielo horneada**
  en el terreno (las torres como ocluyentes grandes en `terrain.bake_ao`, radio 20–40 m): calles más azules y oscuras
  entre torres por 0 ms.
- DoF / *tilt‑shift*: no (vuelve la ciudad maqueta y emborrona la lectura del peligro, pilar 1).
- Salida HDR (4.7): la LUT no funciona con HDR; si algún día se activa, la gradación pasa a `CompositorEffect`.

---

## 4. Shaders y ficheros previstos

| Fichero | Cambio |
|---|---|
| `assets/shaders/snow_include.gdshaderinc` | nieve v2 (§3.2): ruido de borde, abrigo por AO, barlovento, deshielo, edad por instancia |
| `assets/shaders/world_vcol.gdshader` | + fundido de edificios altos (§3.1), + `instance uniform fade_enable`, + escarcha |
| `assets/shaders/window_city.gdshader` (nuevo) | ventanas por celdas con ocupación, `city_power`, parpadeo (§3.4) |
| `assets/shaders/terrain.gdshader` | mapa de rodadas por chunk (`Texture2DArray`), arrastre por viento, AO de cielo de torres |
| `assets/shaders/light_pool.gdshader` (nuevo) | charco de luz aditivo + halo *billboard* |
| `scripts/world/city_occlusion.gd` (nuevo) | detecta edificios entre cámara y jugador y anima `fade_enable` |
| `scripts/world/day_night.gd` + `scripts/autoload/quality.gd` | claves de niebla de altura/ciudad, LUT por hora/clima, SSR por región, límites de luces, preset **`web`** |
| `tools/make_luts.py` (nuevo) | genera los `.png`/`.exr` de LUT 32³ por script |
| `tests/perf_probe` | escena fija "ciudad" (bloque del doc 07) de día/noche/ventisca con `enforce_gpu` en la máquina del usuario |

---

## 5. Presupuestos

### 5.0 Medido en Godot 4.7.2 (bloque de ciudad del doc 07)

Banco desechable en el scratchpad (`g2_assets/godot_city/`): la misma disposición que los renders de Cycles
(12 edificios, 31 coches, 14 farolas, props, 2 supervivientes, 4 zombis, pinos) cargada desde los `.glb` de
`winterize`, con **los shaders del juego** (`world_vcol`, `terrain`, `stylized_light`) + dos prototipos G2
(`window_city.gdshader`, ventanas por celdas; `world_vcol_fade.gdshader`, fundido con *dither* Bayer), claves de
`DayNight` DAY/NIGHT de G1, sombras 4096 × 2 *splits* con PCSS 1.2°, SSAO *medium half*, MSAA 2×, cámara del juego.
Forward+ sobre **lavapipe** y Compatibility sobre **llvmpipe** (rasterizadores por CPU: los ms **solo valen como
proporción**, igual que en doc 06 §5.1), 1280 × 720, media de 8 frames tras 24 de calentamiento:

| Variante (Forward+) | ms lavapipe | vs. día | Draw calls | Primitivas | Lectura |
|---|---|---|---|---|---|
| Día `alto` (base) | 403 | 1.00 | 152 | 323 k | 47 draw calls y 76 k primitivas en color; **105 draw calls y 247 k primitivas en las 2 cascadas de sombra** |
| sin SSAO | 338 | 0.84 | 152 | 323 k | SSAO = 16 % |
| sin sombra del sol | 186 | 0.46 | 47 | 76 k | **las sombras son el 54 % del frame** (en CPU pesa más el vértice; en GPU real se espera 20–30 %) |
| torres sin sombra propia | 371 | 0.92 | 142 | 253 k | las 5 torres aportan 70 k primitivas y el 8 % solo en sombras → `Tower_Shadow` (§3.13) |
| + SMAA | 438 | 1.09 | 152 | 323 k | SMAA ≈ MSAA 2× en coste |
| sin MSAA | 366 | 0.91 | 152 | 323 k | MSAA 2× = 9 % |
| + SSR | 461 | 1.14 | 152 | 323 k | SSR *half* = 14 % |
| + volumétrica (0.028) | 475 | 1.18 | 152 | 323 k | = doc 06 (+12–18 %) |
| Noche (14 farolas omni + hoguera + ventanas por celdas + glow) | 442 | 1.10 | 140 | 313 k | la noche de ciudad cuesta +10 % con luces reales solo cerca |
| Noche + volumétrica | 499 | 1.24 | 140 | 313 k | |
| Junto a una torre (jugador tapado) / con fundido | 259 / 291 (cámara fuera de la torre); 305 / 345 (cámara **dentro** de la torre) | — / +12–13 % | 48 / 34 | 114 k / 163 k | el *discard* cuesta +12–13 % en lavapipe cuando el edificio fundido ocupa media pantalla o más (sin *early‑Z* en esos píxeles): acotar el fundido al cilindro y a 2–6 edificios. Con la cámara a 16 m en planta del jugador, una torre de 15 m de lado entre ambos **mete la cámara dentro de la torre** en muchas posiciones: el fundido debe cubrir también ese caso (todo el edificio que contiene la cámara) |
| **Compatibility** día / noche / torre con fundido | 380 / 483 / 234 (llvmpipe) | noche +27 % | 169 / 158 / 49 | 323 k / 313 k / 114 k | todo funciona en Compatibility (ventanas, fundido, nieve); sin compensar la exposición (×0.5, doc 06) sale más clara |

Capturas: `previews/godot_city_day.png`, `godot_city_night.png`, `godot_city_night_compat.png`,
`godot_tower_occluded.png`, `godot_tower_fade.png`. Conclusiones que cambian el plan: (1) **el coste lo mandan las
sombras**, no los draw calls (152 en total gracias a 1–3 superficies por asset): *proxies* de sombra para torres,
`cast_shadow = OFF` en props < 1 m y en las losas de nieve pequeñas, y quizá `directional_shadow_max_distance` 50 m en
ciudad; (2) los draw calls de la escena de prueba están muy por debajo del límite: el presupuesto de 600–1 000 de §5.1
deja margen para el mobiliario urbano real (cientos de props) si va en `MultiMesh`; (3) la noche de ciudad con luces
reales solo cerca + ventanas emisivas es barata (+10 %).

### 5.1 `alto` (Forward+, 1080p, GPU media) — estimaciones por efecto

| Partida | Día claro | Noche en ciudad | Ventisca |
|---|---|---|---|
| Opacos (terreno + ciudad 300–700 k tris, 150–1 000 draw calls; medido 152 en §5.0) | 3.0–4.0 | 3.0–4.0 | 2.5–3.5 |
| Sombra direccional 4096, 2 splits (+ PCSS) | 1.8–2.5 (con *proxies* de torre) | 0.8 (luna, sin PCSS) | 1.0 |
| SSAO medium half | 0.8 | 0.8 | 0.6 |
| Luces *clustered* (≤ 64, 2 con sombra) | 0.2 | **1.0–1.5** | 0.6 |
| Nieve v2 + terreno + rodadas + fundido | 0.3–0.5 | 0.3–0.5 | 0.4–0.6 |
| Niebla exp. + altura / volumétrica | 0.05 | 0.05 (+1.2 si niebla vol.) | **1.2–2.0** |
| Partículas (nevada, serpientes, humo) | 0.3 | 0.4 | 0.6–0.9 |
| Glow + LUT + viñeta | 0.1 | 0.5 | 0.4 |
| MSAA 2× + SMAA | 0.8–1.3 | 0.8–1.3 | 0.8–1.3 |
| SSR (solo regiones con hielo/cristal) | (0.8–1.5) | — | — |
| **Total** | **7.4–9.8** (≤ 11.3 con SSR) | **7.7–9.9** (≤ 11.1 con niebla vol.) | **8.1–10.9** |
| Objetivo | ≤ 12 ms | ≤ 14 ms | ≤ 14 ms |

Límites de escena (ARQ §17.1, ampliados para ciudad): draw calls ≤ 1 500 con sombras (típico 600–1 000), tris
≤ 1.5 M (típico 400–700 k), objetos ≤ 2 500, luces visibles ≤ 64 (sombra ≤ 2 + sol), partículas ≤ 12 000, VRAM
≤ 1.5 GB (texturas: atlas de calcomanías 2 MB + LUTs 1 MB + mapas de huellas/rodadas 7 MB).

### 5.2 `medio` / `compat` escritorio

- `medio` (Forward+): sin PCSS, SSAO low, sin volumétrica ni SSR, SMAA off, partículas 0.6, luces ≤ 32: **6–8 ms**.
- `compat` (OpenGL, iGPU): sin SSAO/SSR/volumétrica/calcomanías/SMAA, MSAA 2× o nada, sombra 2048, luces ≤ 8 por
  malla (farolas emisivas + charcos falsos), partículas 0.45, LUT sí, fundido sí: **≤ 16.6 ms**; draw calls ≤ 1 000.

### 5.3 Web (Compatibility / WebGL2, plantilla *nothreads*)

| Partida | Presupuesto |
|---|---|
| Objetivo | **30 fps a 1280 × 720** (≤ 33 ms; objetivo 25 ms) con `scaling_3d_scale` 0.75–0.85 en iGPU |
| Draw calls | **≤ 500** (en WebGL el coste por llamada es 2–3× el de escritorio): *MultiMesh* y HLOD agresivos, `visibility_range` −30 % |
| Triángulos | ≤ 350 k visibles; torres solo `Tower_Base` + fuste barato; sin losas de nieve en cornisas pequeñas (solo shader) |
| Sombras | direccional 2048, 1 split, 40 m; sin sombras de omni; torres con `Tower_Shadow` |
| Luces | ≤ 8 por malla; farolas emisivas + charcos falsos; ventanas por shader |
| Post | tonemap Filmic + exposición compat (×0.5), glow simple, LUT (sí), sin SSAO/SSR/volumétrica/calcomanías/SMAA/TAA |
| Partículas | 35 % de `alto` (≈ 4 000) |
| Huellas | back‑end `cpu` si `DrawableTexture2D` no va en WebGL2; mapa de rodadas por chunk a 0.5 m/px |
| Memoria | ≤ 512 MB de montón (streaming con anillo 1 solo), mallas sin texturas (el color de vértice ayuda: 10 MB para 30 modelos CC0 frente a 66 MB texturizados) |
| Oclusión | **no** (la plantilla Web no trae *occlusion culling*) |

---

## 6. Plan por fases (hito G2)

| Fase | Contenido | Fable (código) | Opus (arte) | Aceptación |
|---|---|---|---|---|
| **G2a — ciudad jugable** (tras M6a) | fundido de torres + X‑ray, nieve v2, ventanas por celdas, charcos de luz, torres en 3 piezas + `visibility_range` + HLOD, preset `web`, `perf_probe` "ciudad" | M | M (`winterize` en el repo, 5 torres, 10 coches, 30 props, manifiesto) | capturas día/noche de la escena "ciudad" en Forward+ y Compatibility; jugador nunca oculto > 0.3 s tras una torre; draw calls ≤ 1 000 típicos; `alto` ≤ 12 ms día en la GPU del usuario |
| **G2b — atmósfera** | niebla en capas + `FogVolume`, viento/serpientes de nieve, LUTs por clima/hora + mezcla, humo/fuego/balizas/bandadas, deshielo por calor | M | S (sprites de humo CC0, LUT script) | hoja de contacto de 8 horas × 3 climas; ventisca ≤ 14 ms |
| **G2c — detalle** | mapa de rodadas por chunk + carreteras que se cubren, calcomanías (+ mallas en compat), SSR por región, SMAA/FSR2 en menú de calidad, AO de cielo de torres | M | S (atlas de calcomanías) | rodadas persisten al volver a un chunk; SSR solo en lago/ciudad; sin regresión de `perf_walk` |

Riesgos: (R1) el fundido con *dither* se ve "de puntos" con MSAA: usar `ALPHA_HASH`‑like con ruido azul o
*alpha‑to‑coverage* en Forward+; (R2) la nieve v2 cambia el aspecto de los assets G1: capturas de regresión del claro
en cada paso; (R3) LUT + HDR incompatibles (si algún día se activa HDR); (R4) luces: Compatibility limita a 8 por
malla y la calzada es una malla grande → trocear la cinta de carretera por chunk (ya se hace) y no depender de luces
reales para leer la calle; (R5) todos los costes de §5 son **estimaciones** (lavapipe solo sirve como ratio, doc 06
§5): cerrar G2a midiendo en la GPU del usuario.

---

## 7. Imágenes de apoyo (Cycles y Godot, prueba del doc 07)

Carpeta `/tmp/claude-0/-home-user-Quotas/3c3b507e-0838-5643-8cd6-6e5a40202a08/scratchpad/g2_assets/previews/`:
`city_after_day_gamecam24.png` (lo que ve el jugador en la ciudad: calle, atasco, ninguna torre en cuadro),
`city_after_day_aerial.png` y `city_after_night_aerial.png` (el *skyline* que solo existe fuera de la cámara de juego;
de noche, ventanas por celdas al 30 %), `city_after_night_gamecam24.png` (farolas + fogata), `city_tower_occluded_gamecam24.png`
(jugador junto a la esquina de una torre de 100 m: solo se ve su base) y `city_tower_fade_gamecam24.png`,
`city_tower_camera_inside{,_fade}_gamecam24.png` (§3.1), hojas `sheet_*.jpg` (antes/después). Son Cycles con materiales que imitan
`world_vcol` (AO de `COLOR.a` con tinte azul): orientan el aspecto, no el coste. Las capturas `godot_*.png` son del
motor real (Godot 4.7.2, shaders del juego, §5.0).

## Fuentes

- Referencia de clases de Godot 4.7.2 (`godotengine/godot`, tag `4.7.2-stable`, `doc/classes`): `Environment.xml`
  (LUT `adjustment_color_correction` con `Texture3D`, sin HDR; SSR solo Forward+; volumétrica solo Forward+; glow
  `SCREEN` fijo en Compatibility; tonemappers), `Viewport.xml` (`screen_space_aa` FXAA/SMAA, `use_taa`,
  `scaling_3d_mode` FSR/FSR2/nearest), `ProjectSettings.xml` (SMAA/TAA solo Forward+(/Mobile), TAA con *ghosting* en
  partículas y *skin*, `occlusion_culling` sin soporte en la plantilla Web, SSR `half_size`), `Decal.xml` (sin
  Compatibility; 8 por malla en Mobile), `OccluderInstance3D.xml`, `GeometryInstance3D.xml` (fundidos de
  `visibility_range` solo Forward+), `BaseMaterial3D.xml` (`stencil_mode` XRAY experimental; `DISTANCE_FADE_PIXEL_DITHER`),
  `AreaLight3D.xml`, `ReflectionProbe.xml` (2 por malla en Compatibility).
- Notas de versión (vía resúmenes de búsqueda; las páginas oficiales están bloqueadas aquí): [Godot 4.7](https://godotengine.org/releases/4.7/) (salida HDR, `AreaLight3D`, `DrawableTexture2D`, escalado *nearest*, base de trazado de rayos), [Godot 4.6](https://godotengine.org/releases/4.6/) (SSR reescrito con Hi‑Z y media/completa resolución, glow antes del tonemap con `SCREEN` por defecto, Jolt por defecto), [CG Channel 4.7](https://www.cgchannel.com/2026/06/discover-5-key-features-for-cg-artists-in-godot-4-7/), [GameFromScratch 4.6](https://gamefromscratch.com/godot-4-6-released/), [Phoronix 4.6](https://www.phoronix.com/news/Godot-4.6-Released).
- Referencias de arte: [The Long Dark Art Analysis](https://austenseeberg3d.blog/2020/03/03/the-long-dark-art-analysis/), [Frostpunk Heatmap case study (Lexdev)](https://lexdev.net/tutorials/case_studies/frostpunk_heatmap.html), [Intel: snow simulation in Frostpunk](https://www.intel.com/content/dam/develop/external/us/en/documents/intel-gpaa-assists-snow-simulation-in-frostpunk.pdf), [Deformable Snow Rendering in Batman: Arkham Origins (GDC 2014)](https://www.slideshare.net/colinbb/gdc2014-deformable-snow-rendering-in-batman-arkham-origins), [Death Stranding — tackling the terrain](https://www.fanatical.com/en/blog/death-stranding-tackling-the-terrain-steam-pc-ps4), [The arcologies of The Ascent](https://medium.com/@KonstantinosD/the-arcologies-of-the-ascent-d4551a088624), [Wireframe: the urban world of The Ascent](https://wireframe.raspberrypi.com/articles/exploring-the-urban-cyberpunk-world-of-the-ascent), [Diablo 4 art and environments](https://www.purediablo.com/diablo-4-quarterly-update-art-and-environments), [Wireframe: Tunic](https://wireframe.raspberrypi.com/articles/wireframe-cover-star-tunic-and-the-art-of-keeping-a-secret).
- Propias: doc 06 (costes relativos medidos en lavapipe), doc 07 (escena de ciudad y pase `winterize`), `tests/perf_budgets.json`, ARQ v2 §17.1.
