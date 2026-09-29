# VENTISCA — Audio (carril S1)

> Estado: **S1 entregado** (armas, cuerpo a cuerpo, zombis, lobos, jugador, mundo, ambiente, interfaz y *stingers*).
> Demo de escucha (42 s, 0,54 MB): [`docs/audio/demo_mix.ogg`](audio/demo_mix.ogg) — el valle al anochecer (viento,
> fogata, pasos en nieve, un zombi que te ve, pistola, escopeta con su corredera, recarga) y luego una calle de
> Altavega (viento entre edificios, alarma lejana, perros, un letrero que cruje, una lona, un disparo lejano, un grito,
> cristales).

Índice: [1 Resumen](#1-resumen) · [2 Mapa de sonidos](#2-mapa-de-sonidos) · [3 Director de ambiente](#3-director-de-ambiente) ·
[4 Tabla de eventos y cómo añadir un sonido](#4-tabla-de-eventos-y-cómo-añadir-un-sonido) · [5 Reglas de mezcla](#5-reglas-de-mezcla) ·
[6 El oyente con cámara isométrica alta](#6-el-oyente-con-cámara-isométrica-alta) · [7 Fuentes y licencias](#7-fuentes-y-licencias) ·
[8 Pruebas](#8-pruebas) · [9 Presupuestos y Web](#9-presupuestos-y-web) · [10 Pendiente](#10-pendiente)

---

## 1. Resumen

| Pieza | Fichero | Qué hace |
|---|---|---|
| `AudioManager` (autoload) | `scripts/autoload/audio_manager.gd` | API por nombre de evento (`play`, `play_ex`, `start_loop`, `stop_loop`, `set_wind`, `schedule`, `heartbeat`, `clip_started`); *pool* de voces 3D (40, Web 24) y 2D (16) con prioridad y robo de voz; presupuestos por grupo; tipos de evento (disparo por capas, paso por superficie, impacto, *swing*…); bucles adjuntos a su dueño; buses; oyente; envío de reverb. Mantiene la API de H2 (`STREAM_FILES`, `register()`, `has_stream()`). |
| `AudioTable` | `scripts/audio/audio_table.gd` | Carga `data/audio_events.json` y lo resuelve contra `assets/audio/manifest.json` (los *globs* `weapons/pistol_close_*`); `validate()`. |
| `AmbienceDirector` | `scripts/audio/ambience_director.gd` | Lechos estéreo por lugar / hora / clima / interior, *one-shots* dispersos, zumbido de generador, *stinger* de anochecer. |
| `ZombieVoices` | `scripts/audio/zombie_voices.gd` | Gruñidos en reposo, respiraciones de persecución, pasos arrastrados, tambaleo y derribo leídos de los registros de `ZombieClient` (8 Hz), dentro del presupuesto de voces. |
| `CombatAudio` | `scripts/audio/combat_audio.gd` | Sonidos por eventos de animación (recargas, *swings*, empujón, pisotón, ejecución, desencasquillar, tensar el arco), impactos de bala por material, silbido de bala, flechas, encasquillado, botín, derribado, respiración del jugador, *stinger* de peligro. |
| `AudioSettings` + `AudioSettingsPanel` | `scripts/audio/audio_settings.gd`, `scripts/ui/audio_settings_panel.gd` | Volúmenes General / Efectos / Ambiente / Interfaz / Música en `user://settings.cfg` `[audio]`; botón «Sonido» del menú de pausa. |
| Buses | `default_bus_layout.tres` (lo escribe `tools/audio/gen_bus_layout.gd`) | §5. |
| Sonidos | `assets/audio/{weapons,creatures,player,world,ambience,ui,music}/` | 557 ficheros, 8,37 MB (OGG Vorbis; + el WAV de H2). |
| Construcción | `tools/audio/` | `fetch_sources.sh` (grabaciones CC0 fijadas por commit), `build_audio.py` + `recipes_*.py` (diseño y procesado, determinista), `audiolib.py` (DSP), `render_demo.py`, `gen_bus_layout.gd`. |

**Servidor dedicado**: `AudioManager.enabled = false` (rol `SERVER`, *feature* `dedicated_server`, `--server` o
`--no-audio`): no crea voces ni carga nada y todas las llamadas vuelven al instante. El preset «Dedicated Server»
excluye `assets/audio/*`.

**Ensayo sin sonido (*dry run*)**: en procesos *headless* y con el driver `Dummy` (pruebas, bancos con xvfb,
clientes de red *headless*; o `--audio-dry-run`) el gestor resuelve cada evento igual que en el juego (voz, bus,
posición, presupuestos, bucles, lechos) pero **nunca arranca una reproducción real**: una voz cuenta como sonando
durante la duración de su fichero. Así ninguna reproducción del `AudioServer` sobrevive al salir (saldría «ERROR:
resources still in use at exit», que todas las puertas de prueba buscan). En el juego real, `stop_all()` para todas
las voces al cerrar la ventana y al liberarse el autoload.

## 2. Mapa de sonidos

Todos los eventos que dispara el código tienen sonido o están en la lista de silencios documentada (`silent` de la
tabla); la prueba unitaria lo comprueba leyendo el código.

### 2.1 Armas de fuego (`Firearms.TABLE[...]["sfx"]`: `gun_pistol`, `gun_revolver`, `gun_shotgun`, `gun_rifle`)

Un disparo (`type: shot`) son **capas** que el gestor elige por la distancia al oyente y el entorno:

| Capa | Ficheros | Regla |
|---|---|---|
| Cercana | `weapons/<arma>_close_01…04` (4 variaciones) | ganancia 1 hasta 20 m → 0 a 60 m; unidad 6 m, pasa-bajos 9 kHz |
| Lejana | `weapons/<arma>_far_01…03` | 0 hasta 15 m → 1 a 45 m; unidad 22 m, pasa-bajos 2,5 kHz (sin transitorio, «bum» rodado) |
| Cola | `weapons/tail_<entorno>_<light\|heavy>_01…03` | siempre; entorno del disparo: `forest` (T60 ≈ 2 s), `open` (nieve: casi seco + ecos de laderas), `city` (eco de aleteo entre fachadas, T60 ≈ 3,4 s), `interior` (sala 0,55 s) — `interior` cuando el jugador local está dentro y a < 25 m |
| Mecánica | `gun_pump_back/fwd` (escopeta, +0,32 / +0,47 s), `gun_bolt_open/back/fwd/close` (rifle, +0,48…0,82 s) | solo a < 25 m |
| Vaina | `casing_brass_*` (pistola +0,38 s, rifle +0,86 s), `casing_hull_*` (escopeta +0,66 s); `*_snow` (un «pff» amortiguado) o `*_hard` (tintineo con 3–4 botes) según la superficie | solo a < 12 m |

El alcance audible es el radio de ruido de la tabla (GDD §6.3: pistola 80 m, revólver 90, rifle 120, escopeta 150)
× 1,3: **la cola audible coincide con el radio al que la oyen los zombis** (`SoundEvents`). Los disparos de **los
demás jugadores** llegan por `Events.shot_fired` a todos los clientes en alcance (`FirearmFx._on_shot` ya llamaba a
`AudioManager.play(sfx, boca)`), así que se oyen igual que los propios, con su capa lejana si están lejos.

Diseño (no hay grabaciones CC0 de estos calibres accesibles): onda de choque de Friedlander (+ la onda N supersónica
del rifle), ráfaga de gas en 4 bandas con caídas distintas (los agudos mueren en ≈ 8 ms, los medios-graves cargan el
cuerpo), crepitar turbulento, un golpe grave con caída de tono, reflexión en el suelo, nube de reflexiones tempranas,
saturación y limitador con *look-ahead*; unos milisegundos de un petardo CC0 grabado (rubberduck) aportan textura
orgánica. Pistola con el ciclo de la corredera; revólver con el anillo del armazón. Las colas son la convolución del
disparo con una respuesta al impulso algorítmica de cada entorno.

**Recargas y acciones** — por eventos de animación (`data/anim_events.json`), para el dueño y para los jugadores
remotos (`PlayerView.on_swing` → `AudioManager.clip_started`):

| Clip | Eventos → sonido |
|---|---|
| `Pistol_Reload` | `mag_out` → `rl_mag_out`, `mag_grab` → `rl_pouch`, `mag_in` → `rl_mag_in`, `slide` → `rl_slide` |
| `Pistol_Reload_Revolver` | `cyl_open`, `mag_out` → `rl_eject` (seis vainas que caen), `shell_grab`, `shell_in_1…6` → `rl_chamber_in`, `cyl_close` |
| `LongGun_Reload_Shell` (bucle) | `shell_grab` → `rl_pouch`, `shell_in` → `rl_shell_in` |
| `LongGun_Reload_Bolt` | `bolt_open`, `bolt_back`, `shell_in_1…5` → `rl_round_in`, `bolt_fwd`, `bolt_close` |
| `Act_Unjam(_LongGun)` | `tap` → `unjam_tap`, `rack` → corredera / corredera de escopeta |
| `Bow_Draw` | `draw_start` → `bow_draw` (crujido de palas por fricción) |

`gun_dry` (dueño 2D y servidor), `gun_jam` (el servidor y, en clientes, `Events.fire_result` «encasquillada»; el
*cooldown* evita el doble en modo local). `reload_pistol / reload_longgun / reload_bow` quedan en **silencio**: los
llama `Gunplay` en el servidor; los pasos los dan las animaciones.

**Impactos** (`Events.shot_fired`, cada extremo de bala/perdigón a < 45 m, máx. 4 por disparo): `impact_snow`,
`impact_wood`, `impact_metal`, `impact_concrete` por material (suelo según la superficie; algo en pie: ciudad →
hormigón/metal, fuera → madera), con retardo de vuelo; los extremos en un zombi o un jugador los suena su evento de
golpe. `ricochet` (12 % en duro), `bullet_whiz` cuando la línea de tiro de **otro** pasa a < 3 m del oyente. Flechas:
`projectile_spawned` → impacto al aterrizar. Arco: `bow_release`.

### 2.2 Cuerpo a cuerpo

| Evento | Qué | Cuándo |
|---|---|---|
| `melee_swing` | `player/swing_{light,medium,heavy}_*` por peso del arma (`weights`: puños/cuchillo ligero, palanca/machete medio, bate/hacha pesado; cargado = pesado +2 dB) | evento `swing` del clip (`Melee1H_Light_*`, `Melee2H_Swing_*`, `Melee_Charged`) |
| `zombie_hit` (`type: hit`) | **3 capas** (GDD §7.5): impacto del arma — contundente, cortante, puño (si ese jugador golpeó a < 3,5 m en 0,7 s) o bala en carne — + carne + reacción (`zombie_hurt`, 70 %, presupuesto de voces); a > 25 m solo el impacto | `ZombieClient` EVT_HIT / EVT_CRIT |
| `melee_blocked` | madera/metal | `Events.hit_result` bloqueado |
| `melee_shove`, `melee_stomp`, `melee_stab`, `melee_throw` | empujón, pisotón (crujido + hueso), ejecución, lanzar | `Act_Shove`, `Act_Stomp`, `Act_Execute`, `Act_Throw` |
| `tool_break` | madera que se parte + metal | inventario |
| `melee_hit_wood/metal` | disponibles para objetos | — |

### 2.3 Zombis y lobos

| Evento | Ficheros | Disparador | Notas |
|---|---|---|---|
| `zombie_groan` | 12 gemidos lentos | `ZombieVoices`: reposo / vagar ≈ cada 9 s, persiguiendo ≈ 4,5 s | grupo `zombie_voice` |
| `zombie_alert` («te he visto») | 6: inspiración seca + gruñido | EVT_WAKE arg 1 (ZombieSystem al pasar a CHASE sin objetivo previo) | prioridad 75 |
| `zombie_attack` | 6: gruñido + *swipe* del brazo a 0,3 s (`Zom_Attack_A.swing`) | EVT_ATTACK | |
| `zombie_hurt`, `zombie_die` | 6 / 5 (la muerte cae de tono, gorgoteo, cuerpo en la nieve a ≈ 0,6 s = `Zom_Death_A.ground`) | EVT_HIT, EVT_DIE | |
| `zombie_breath` | 6 jadeos roncos | corredor persiguiendo | |
| `zombie_step` | 8 pasos arrastrados en nieve | cada 0,75 m recorridos (< 16 m) | grupo `zombie_step` ≤ 8 |
| `zombie_stagger`, `zombie_knock` | quejido + tambaleo / cuerpo que cae | cambio de estado a STAGGER / KNOCKED | |
| `frozen_wake` | 3: dos crujidos de hielo a 0,30 y 0,62 s (`Zom_Wake crack_1/2`) y el gemido al soltarse (1,05) | EVT_WAKE arg 0 | |
| `bloater_pop` | 3: estallido húmedo, golpe grave, silbido de gas, salpicaduras | EVT_CLOUD | |
| `wolf_growl/bite/hurt/die/howl` | aullido y gruñido diseñados (pulsos glotales por formantes de lobo), gemido CC0 | `wolf.gd`, `wolf_spawner.gd` | `wolf_howl` 2D con reverb de bosque |

**Presupuesto de voces**: el grupo `zombie_voice` admite **6** vocalizaciones a la vez; entra la más cercana (si el
grupo está lleno, una nueva más cerca que la más lejana la sustituye; si no, se descarta). Con 50 zombis alrededor
(prueba de humo) el pico es 6.

### 2.4 Jugador

| Evento | Qué |
|---|---|
| `footstep_snow` (`type: footstep`) | lo llama `FootprintEmitter` en cada zancada de **todos** los personajes; la **superficie bajo el pie** elige el juego de 8: `snow` (nieve fresca), `packed` (carreteras, pistas, nieve pisada: `surface_at` r/b), `ice` (g, agua de W1), `wood` (dentro de la cabaña, porches), `concrete` (suelos en la ciudad), `metal` (reservado); corriendo +3 dB y ×1,05, agachado −8 dB; lobos y ciervos −9 dB y más agudos |
| `player_hurt`, `player_downed`, `player_die` (+ `stinger_death`) | voz; el derribo de un compañero suena además `ui_mate_down` |
| `player_breath_cold`, `player_breath_run`, `player_shiver` | vaho de noche o en ventisca fuera, jadeo tras 3 s corriendo, castañeteo con frío |
| `heartbeat` | **gancho para H3**: `AudioManager.heartbeat(intensidad 0–1)` late a 68–140 ppm, −16…−4 dB; `heartbeat(0)` lo apaga |
| `eat`, `bandage`, `pickup`, `craft_done`, `place` | *foley* |

### 2.5 Mundo

`chop_hit` (hacha + golpe + nieve que cae de las ramas), `tree_fall` (fibras que gimen, crujidos, barrido de la copa,
golpe y explosión de nieve, 4,5 s), `fire_loop` (bucle 3D de 10 s), `stove_loop` (fuego en hierro + chasquidos
térmicos), `fire_add_wood`, `fire_out`, `flare_burn`, `can_land` (`type: surface`: lata en nieve o en duro),
**puertas para M6a: `door_open`, `door_close`, `door_locked`** (+ `door_break`), cofres (`container_open_wood`,
`container_open_metal`, `container_rummage` por `LootTables.model_for`), `glass_break`, `ice_crack`, `ice_break`,
`car_alarm` (3 patrones), `generator_loop`, `metal_creak`.

### 2.6 Interfaz «Susurro» y *stingers*

UI (bus UI, 2D, suave: tic de madera, papel, cuerda apagada, cristal frío; nunca un pitido puro): `ui_click`,
`ui_open`, `ui_close`, `ui_map_open`, `ui_map_close`, `ui_tab`, `ui_mark`, `ui_info_open`, `ui_info_close`,
`ui_pickup` (≤ 8/s), `ui_warn` (pitido de radio doble y grave), `ui_hazard` (más grave + ráfaga; baja el ambiente),
`ui_objective_update` (pulsación seca de cuerda), `ui_objective_done` (dos notas en quinta), `ui_craft`,
`ui_mate_down` (doble latido + estática; baja el ambiente −6 dB), `ui_hold_tick`, `ui_hold_done`, `ui_level`,
`ui_zone_discover` (el de H2, se mantiene; baja el ambiente −4 dB 1,5 s como pide el doc 10 §5.6).

Música mínima (bus Music, nunca en bucle, GDD §14): `day_start` → amanecer, `stinger_night` (anochecer,
`Events.night_started`), `stinger_danger` (≥ 5 zombis persiguiendo a < 30 m; 90 s de enfriamiento), `ui_mission_done`
y `quest_done` → misión cumplida, `win`, `stinger_death`.

## 3. Director de ambiente

- **Dónde**: cada 0,5 s el bioma del mapa macro (`World.hf.macro.biome_at`) en el oyente (peso 2) y 4 puntos a
  35 m (peso 1) → familias: `forest` (DENSE_FOREST, FOREST), `open` (FIELD, SETTLEMENT, SUBURB, AIRBASE), `pass`
  (MOUNTAIN, SKI), `ice` (LAKE, RIVER), `city` (OLD_TOWN, ENSANCHE, FINANCIAL, BARRIADA, INDUSTRIAL), `port` (PORT). El
  **rastreador de zonas de H2** manda cuando está: una zona de Altavega (`chain`) fija la ciudad; una zona con
  `power: generator` pone un **generador** 3D en su centro mientras el oyente está a < 120 m.
- **Lechos** (estéreo, 24 s en bucle, −20 LUFS): `forest_day`, `forest_night`, `open`, `pass` (viento que aúlla en
  el puerto), `ice` (río/lago: el hielo «canta» y retumba), `city_day`, `city_night` (viento en los cañones, silbidos
  en cables, lonas), `port` (drizas que tintinean en los mástiles), `interior`. Fundido ≈ 3 s.
- **Viento**: capa `wind_layer` escalada por `set_wind` (0,2 día, 0,5 noche, 0,6 aviso, 1,0 ventisca); capa
  `blizzard` con el `wind_loop` de `Weather` (o `WorldState.weather`).
- **Dentro** (`in_house`): lecho `interior` (tono de sala + la tormenta a través de las paredes), exteriores −14 dB,
  pasa-bajos del bus Ambience a 700 Hz, envío de reverb a la sala.
- **One-shots** por familia (tabla `ambience.oneshots`): bosque: cuervos (día), pájaro carpintero, nieve que cae de
  una rama, rama que se rompe, búho (noche), aullido lejano; puerto de montaña: desprendimiento lejano; hielo: «pew»
  del hielo, estampido; **Altavega**: alarma lejana, perros, chapa que cruje, lona, persiana que golpea, **disparo
  lejano sin fuente** (`amb_gunshot_far`, nunca un `SoundEvent`), **grito lejano** (más de noche), cristales; interior:
  crujidos de la casa, cristal que vibra con viento fuerte. Se colocan en 3D a un rumbo aleatorio alrededor del oyente.

## 4. Tabla de eventos y cómo añadir un sonido

`data/audio_events.json`:

```json
"door_open": {"files": "world/door_open_*", "bus": "World", "max_distance": 25.0, "unit_size": 3.0,
              "priority": 55, "cooldown": 0.15}
```

Campos (por defecto en `defaults`): `type` (simple, shot, footstep, surface, hit, melee_swing, stinger, layer), `bus`,
`mode` (3d/2d), `volume_db`, `pitch_rand` (±fracción), `vol_rand_db`, `max_distance` (más lejos no se reproduce),
`unit_size` (m a 0 dB, distancia inversa), `lpf_hz` (pasa-bajos por distancia), `priority` (0–100), `max_instances`,
`cooldown`, `group` (presupuesto, tabla `groups`), `loop`, `follow` ([{event, delay}]), `duck` ({bus, db, seconds}).
`files` es una ruta, un *glob* con `*` o una lista, relativa a `assets/audio/`, resuelta contra el manifiesto (un
fichero que falta en una exportación recortada se ignora). Otras secciones: `silent` (eventos mudos con el motivo),
`groups`, `tails`, `anim` (clip → evento de animación → sonido), `weights`, `ambience` (lechos, capas, familias,
*one-shots*).

**Añadir un sonido**:
1. Receta en `tools/audio/recipes_<grupo>.py` (`out("world/mi_sonido_01", señal, "world")`; la categoría fija nivel,
   calidad y canales, §5). Grabaciones solo con `sources.use(paquete, fichero)` (CC0; el paquete se añade a
   `fetch_sources.sh`).
2. `tools/audio/fetch_sources.sh && python3 tools/audio/build_audio.py <grupo>` → escribe los OGG, el manifiesto y
   `LICENSES.md`.
3. Entrada en `data/audio_events.json`; llamar `AudioManager.play(&"mi_evento", pos)` desde el código.
4. `godot --headless --path . --import`, `tests/unit/audio_test.gd` (falla si el código llama a un evento sin
   sonido), `tests/run_smoke.sh`.

Un sonido grabado a mano también sirve: deja el `.ogg` en `assets/audio/…`, añádelo al manifiesto (o crea una receta
que lo copie con `A.load`) y a `LICENSES.md`.

## 5. Reglas de mezcla

- **Buses**: `Master` (limitador −0,3 dB) → `Music` (−4 dB), `SFX` (compresor de pegamento −14 dB 3:1) ← `Weapons`,
  `Creatures`, `Foley`, `World`; `Ambience` (−2 dB; pasa-bajos del director + compresor con **sidechain de
  Weapons**: los disparos hunden el ambiente), `UI` (−3 dB); retornos de reverb `RevOutdoor`, `RevInterior`,
  `RevCity` (100 % húmedos) alimentados por un `Area3D` de envío (capa física 20) que sigue al oyente: el director
  elige el retorno y la cantidad (bosque 0,18, abierto 0,10, ciudad 0,30, interior 0,35). Cada voz 3D tiene
  `area_mask` = capa 20.
- **Niveles** (`build_audio.py`, `CATEGORIES`): *one-shots* por el máximo momentáneo (400 ms): disparos cercanos
  −9 LUFS (limitados a −1 dBFS), lejanos −14, colas −19, mecánica −22, vainas −24, impactos −18, voces de criaturas
  −16, pasos −22, *foley* −20, cuerpo a cuerpo −17, UI −22, *stingers* −16; **lechos −20 LUFS integrados**, capas
  −24, bucles del mundo −22. Todos con picos ≤ −1 dBFS, sin DC, recortados y con fundidos (sin clics).
- **Canales**: fuentes 3D mono, lechos y *stingers* estéreo (la prueba lo comprueba en las cabeceras).
- **Variación**: bolsa barajada por evento (nunca el mismo fichero dos veces seguidas) + tono ±3–6 % + volumen
  ±1–1,5 dB.
- **Voces**: el *pool* lleno roba la voz menos importante (prioridad − 25 × distancia/máx.); `max_instances` roba la
  menos importante del mismo evento, nunca una más importante; los grupos, la más lejana.
- **Distancia**: atenuación de distancia inversa (`unit_size`) + el filtro pasa-bajos de `AudioStreamPlayer3D`
  (`lpf_hz`); un evento 3D más allá de su `max_distance` ni se reproduce.

## 6. El oyente con cámara isométrica alta

**Decisión: `AudioListener3D` en la cabeza del jugador local (+1,7 m), orientado con el *yaw* de la cámara (sin su
inclinación).** Motivos:

1. **Distancias honestas**: la cámara está a ≈ 22–30 m del jugador. Con el oyente en la cámara todo lo cercano al
   personaje estaría a 25–30 m y la atenuación no distinguiría un zombi a 2 m de uno a 15 m. En el jugador, la
   distancia es la misma que usan los zombis para oír (`SoundEvents`) y el diseño de juego (radios de ruido, «te he
   visto» a 12–25 m).
2. **Paneo por pantalla** (GDD §14: «paneo por posición en pantalla, no por orientación del personaje»): la derecha
   del oyente es la derecha de la cámara; lo que está a la derecha de la pantalla suena a la derecha, gire el
   personaje o no. Al rotar la cámara (Q/E) el paisaje sonoro gira con la imagen.
3. **Punto medio descartado**: un oyente entre jugador y cámara (p. ej. al 30 %) añade 7–9 m de distancia mínima a
   todo, aplana la mezcla cercana y hace que los propios pasos y disparos suenen «lejos»; no ganaba nada que no dé el
   paneo por pantalla.

En menús (sin jugador) manda la cámara. En cooperativo cada cliente tiene su oyente.

## 7. Fuentes y licencias

Solo **CC0 1.0 / dominio público** u obra propia dedicada a CC0. Ningún paquete Sonniss/GDC ni «uso personal».
Sondeo de red (27‑09): `opengameart.org`, `kenney.nl`, `freesound.org`, `archive.org`, `wikimedia`, `pixabay`,
`zenodo`, `bigsoundbank` **no accesibles** desde la máquina de construcción; **GitHub sí**. Se usan dos espejos en
GitHub fijados por commit (`tools/audio/fetch_sources.sh`):

- **Kenney** (kenney.nl, CC0; cada paquete trae su `License.txt`): *Impact Sounds*, *RPG Audio*, *Interface Sounds*,
  *UI Audio* — espejo `github.com/ETdoFresh/kenney.nl` @ `45df48c4`.
- **OpenGameArt**, paquetes publicados con licencia CC0 (cada `pack.json` trae autor, `"license": "CC0-1.0"` y la
  página de OGA): qubodup (pasos en nieve y grava, puertas, crujidos de madera, golpes, impactos húmedos, voces de
  esfuerzo), artisticdude (*Zombies Sound Pack*, *swishes*, *RPG sound pack*), rubberduck (criaturas, metal y madera,
  petardos, rotura, agua), ogrebane, haeldb, tinyworlds, Fantozzi (vía qubodup), badre-eddine, owlishmedia… — espejo
  `github.com/novincode/atomcut-library` @ `391f87ff` (m4a AAC 129 kb/s; se decodifican y procesan).

`assets/audio/LICENSES.md` (lo escribe la construcción) lista **cada fichero** con las grabaciones de las que sale
(o «original») y cada grabación con paquete, autor, licencia y página. De 557 ficheros, ≈ 230 son diseño original
(disparos, colas, mecánica, viento, fuego, lechos, UI, *stingers*…); el resto procesa grabaciones CC0. El
`ui_zone_discover.wav` es de H2 (`tools/gen_ui_sounds.py`, CC0, `assets/audio/ui/LICENSE.txt`).

## 8. Pruebas

- `godot --headless --path . -s tests/unit/audio_test.gd` (en `tests/run_all.sh` y en CI, trabajo «Headless
  tests»): la tabla valida; **cada nombre de evento del código** (llamadas literales + `Firearms` sfx + clases de
  recarga + los dinámicos: impactos, vainas, puertas) tiene sonido o está en `silent` con motivo; cada fichero carga,
  canales según las cabeceras OGG/WAV (3D mono, lechos y *stingers* estéreo), longitud 0,02–40 s = manifiesto, picos
  ≤ −1 dBFS; licencias de todos; variaciones mínimas (≥ 3 por disparo, ≥ 6 por superficie de paso, ≥ 4 gemidos);
  ≤ 10,5 MB; en el gestor: 2D/3D por bus, recorte por distancia, **presupuesto de 6 voces de zombi con los más
  cercanos**, `max_instances`, capas del disparo a 2 m y a 95 m, la corredera de la escopeta, bucles (adjuntos,
  únicos, parada con fundido, se van con su dueño), capa de ventisca, latido, ajustes → volumen de bus.
- Paso 20 de la prueba de humo (`tests/s1_audio_smoke_steps.gd`): oyente en la cabeza y con la derecha de la cámara;
  **disparo local = voz 3D en la boca del arma** + cola del entorno; **escopeta de otro jugador a 30 m** = capas
  cercana y lejana + impactos; la estufa de la cabaña con su bucle; `start_loop`/`stop_loop`; **el director elige
  la ciudad en Altavega y el bosque en el valle**, el interior dentro; un paso resuelve su superficie; **50 zombis
  alrededor: pico ≤ 6 voces** y gimen; sonidos de animación programados por los clips de M4/M5.

## 9. Presupuestos y Web

Total **8,37 MB** (≤ 10 MB): ambiente 3,29 · mundo 1,48 · armas 1,16 · jugador 1,04 · criaturas 0,88 · UI 0,30 ·
música 0,23. El preset **Web** va justo de tamaño (ver W1/C0 en el README): si hay que recortar, las dos opciones
medidas son:

- **Web A (≈ 6,1 MB, −2,3 MB)**: fuera `ambience/{forest_night,city_night,port,pass,ice,open}.ogg`, la tercera
  variación de las colas, la cuarta de los disparos, `player/step_*_0[78]`, gemidos 7–12, `dog_far_0[34]`,
  `scream_far_0[23]`, `glass_far_0[23]`, `rockfall_*`, `halyard_*`, `woodpecker_*`, `car_alarm_03`, `fire_loop_02`,
  `stinger_win`.
- **Web B (≈ 4,0 MB, 274 ficheros)**: 3 disparos + 1 lejano + 2 colas bosque/abierto + 1 ciudad/interior por
  arma, 6 pasos por superficie, 4 gemidos, las variantes `_01` del resto, lechos `forest_day`, `city_day`,
  `interior`, `wind_layer`, `blizzard`, toda la UI y la música. Sin lechos (−0,6 MB más) el viento lo genera
  `Balance.PROCEDURAL_AUDIO = true` (el ruido filtrado de antes de S1, ahora solo como respaldo).

Se aplica con `exclude_filter` del preset Web; la tabla ignora los ficheros que no están (la variación baja, no se
rompe nada). CPU: `ZombieVoices` recorre los registros a 8 Hz, el director 5 muestras de bioma cada 0,5 s, los
*one-shots* se precargan de 3 en 3 por fotograma tras `world_ready`.

## 10. Pendiente

- **Sonidos que solo suenan en el servidor** (en un cliente de red no se oyen): `place` (`NetWorld`, al colocar una
  estructura) — conviene dispararlo desde el `WEVENT` de la estructura en cada cliente (carril M2). `can_land` y
  `day_start` también se llaman en el servidor, pero los clientes ya los oyen (`FirearmFx`, `Events.day_started`
  en el director; el *cooldown* evita el doble en modo local).
- **Vehículos** (M7): motor, arranque, fallo, claxon, choque, motonieve — la tabla y el director ya admiten bucles 3D.
- **Especiales** (M9b): `screamer_scream`, `stalker_breath`, `colossus_roar`, `runner_breath` propio.
- **H3**: conectar `heartbeat()` a la salud baja y a compañero desangrándose; `ui_mate_down` ya suena al derribo de
  un compañero. **H6**: rótulos de sonido con dirección (`AudioManager.event_played` da evento, voz y posición).
- **M6a**: llamar `AudioManager.play(&"door_open" | &"door_close" | &"door_locked", pos)` (los eventos existen).
- Reverb por `Area3D` de edificio (cuando C1/M6a tengan interiores con volumen) en lugar del envío global.
