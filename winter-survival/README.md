# VENTISCA

*Sobrevive cinco días en el bosque helado.* Juego de supervivencia invernal low-poly hecho con **Godot 4.7.2** (GDScript).

Documentación de diseño y técnica en `docs/` (`GDD.md`, `ARCHITECTURE.md`, `ASSET_SPEC.md`).
El plan para la versión de mundo abierto con zombis y cooperativo de 1–4 jugadores está en
`docs/PLAN_MAESTRO.md` (con el diseño, la arquitectura y el contrato de arte v2 en `docs/v2/`).

Capturas con los gráficos de G1 (Forward+):

| Día | Noche | Interior (corte) | Ventisca |
|---|---|---|---|
| ![Día](docs/screenshots/g1/day.jpg) | ![Noche](docs/screenshots/g1/night.jpg) | ![Interior](docs/screenshots/g1/interior.jpg) | ![Ventisca](docs/screenshots/g1/blizzard.jpg) |

Comparación con la referencia: `docs/screenshots/g1/referencia_vs_g1.jpg`. Las capturas del slice original
(antes de G1) siguen en `docs/screenshots/*.png`.

## Abrir el proyecto

1. Instala Godot **4.7.2** (renderizador Forward+ recomendado; también funciona en Compatibility/OpenGL).
2. Abre `winter-survival/project.godot` desde el gestor de proyectos (o `godot --path winter-survival`).
3. Pulsa *Ejecutar* (F5). La escena principal es `scenes/main/main_menu.tscn`.

Los modelos `.glb` de `assets/models/` son opcionales: si falta alguno, el juego usa un
sustituto de primitivas con los mismos nombres de nodo (`scripts/data/placeholders.gd`).

## Controles

| Acción | Teclado / ratón | Mando |
|---|---|---|
| Moverse | W A S D / flechas | Stick izquierdo |
| Correr | Mayús (mantener) | L3 |
| Interactuar / atacar lo que hay bajo el cursor | Clic izquierdo (R: lo más cercano) | X |
| Atacar al lobo más cercano | Espacio | RT |
| Cancelar / cerrar panel | Clic derecho, Esc | B |
| Pausa | Esc | Start |
| Girar cámara | Q / E | LB / RB |
| Zoom | Rueda del ratón | D-pad arriba/abajo |
| Ranuras de la barra | Teclas 1–9 | D-pad izq/der + A |
| Fabricación | Tab | Y |
| Equipar/guardar antorcha | T | D-pad abajo (mantener) |
| Comer lo mejor disponible | F | — |

## Pruebas

```bash
tests/run_all.sh                 # parse, unit (persistencia), smoke, inspect_models, perf, red (basic/shared_world/far), determinismo, perf walk
tests/run_smoke.sh               # solo el smoke test (servidor local en el mismo proceso)
tests/net/run_net_test.sh --clients 4 --duration 60 --soak 90                              # escenario basic (M1)
tests/net/run_net_test.sh --clients 3 --duration 60 --soak 90 --scenario shared_world      # mundo compartido (M2)
tests/net/run_net_test.sh --clients 2 --duration 30 --soak 45 --scenario far --port 7797   # 2 jugadores a 1 km (M3)
tests/run_determinism.sh         # 50 chunks generados por cliente y servidor en dos procesos: hashes iguales (M3)
tests/run_perf_walk.sh --cpu     # 2.26 km a 25 m/s: coste de streaming ≤ 2 ms/frame (headless); sin --cpu: xvfb + llvmpipe
RENDER=forward tests/run_screenshots.sh /tmp/shots   # capturas (Compatibility por defecto; Forward+ con lavapipe)
tests/run_multi_shot.sh /tmp/shots/multi.png         # captura con 2 jugadores remotos (chaquetas distintas)
```

## Reconstruir los modelos 3D (Blender)

```bash
cd winter-survival/blender && python3 build_all.py
```

Genera `assets/models/*.glb` y ejecuta `verify_assets.py`. Después, reimporta en Godot
(`godot --headless --path winter-survival --import`).

## Multijugador (M1)

Siempre hay un **servidor dedicado autoritativo** (PLAN C14): *Jugar* lanza este mismo ejecutable como proceso hijo
(`--headless -- --server --config user://server.cfg`) y se conecta a `127.0.0.1:7777`; *Unirse a servidor* conecta a
`ip:puerto` con contraseña (nonce + HMAC‑SHA256, versión y protocolo comprobados, identidad en `user://identity.cfg`).
En la web (o con `--offline`) el servidor corre dentro del mismo proceso (`OfflineMultiplayerPeer`), que es también el
modo de las pruebas. Chat: Intro. HUD de red: F3 (RTT, pérdida, kB/s, correcciones/s).

```bash
godot --headless --path . -- --server --config server/server.cfg.example   # servidor dedicado (UDP 7777, admin TCP 127.0.0.1:7778)
server/admin.sh status | players | save | save-and-quit | "say hola" | "rule friendly_fire full"
```

`server.cfg` (`server/server.cfg.example`): nombre, contraseña, puerto, `max_players`, `admin_port`/`admin_token`,
semilla, `day_length_sec`, y las reglas `pvp` / `friendly_fire` (`off|reduced|full`) que solo lee `DamageResolver`.
El apagado limpio es siempre por el socket de admin (`save-and-quit`): el headless muere al instante con SIGTERM.

## Mundo compartido (M2)

Todo lo que hace el slice (talar, recoger, estufa, armario, fabricar, colocar, comer, cazar) lo valida el servidor por
`wid` (`NetWorld.request_interact(wid, acción, arg)`: distancia + tolerancia, herramienta, acción declarada por el
objeto, *rate limit*, infracciones). El estado del mundo que se aparta de la semilla vive en un `ChunkDelta` por chunk
(el claro son los chunks 23–25): los cambios se difunden como eventos y el que entra tarde recibe cada chunk comprimido.
Los armarios y la camioneta son de uso exclusivo ("en uso" para los demás). El servidor dedicado guarda perfiles,
reloj y deltas en `world_save.json` (`FileBackend`, escritura atómica; SQLite llegará en M5) y los reaplica al arrancar:
un árbol talado sigue talado. El jugador es ya el **superviviente esquelético** (`chars/survivor_*.glb`, una chaqueta
distinta por jugador, `AnimationTree` con el ciclo escalado a la velocidad real, cabeza que sigue al cursor, herramienta
en la mano). Con `debug_commands=true` en `server.cfg` (o sin red) el chat acepta `/kit`, `/give <item> <n>` y
`/tp <x> <z>`.

## Mundo abierto por chunks (M3)

El mundo mide **3 × 3 km**: 48 × 48 chunks de 64 m alrededor del claro, que queda en el centro exactamente como era.
Alrededor hay un bosque determinista generado con la semilla del servidor, que el cliente recibe al conectarse y con
la que genera el mismo mundo. Tiene:

- el relieve del plano macro (`data/world/macro_map.png`, generado por `tools/gen_macro_map.gd` a partir del mapa
  de PLAN §4.2);
- el Lago de las Ánimas, de hielo plano y transitable, al suroeste;
- lechos de carretera con roderas;
- 4 cabañas aisladas y una torre de vigilancia (con corte al entrar), y restos de acampada;
- un muro con niebla en el borde (±1450 m).

Los chunks se generan en hilos de fondo (`WorkerThreadPool`). En el hilo principal solo se montan, en pasos de
≤ 2 ms por frame: el anillo 1 completo y el anillo 2 precargado, con prioridad hacia donde vas. Los árboles son
MultiMesh; uno se convierte en árbol real solo cuando lo golpeas, y el talado persiste por chunk.

En red, cada jugador recibe solo lo que pasa en los 3 × 3 chunks a su alrededor: poses, animales, eventos e
instantáneas. El servidor hiberna los chunks vacíos al cabo de 60 s. Con `debug_commands`, `/tp <x> <z>` lleva
a cualquier punto (por ejemplo, `/tp -780 340` al lago).

### Probar el cooperativo con amigos (hasta 4)

1. **Descarga la versión de escritorio.** En GitHub, pestaña *Actions* → última ejecución de **VENTISCA** del PR →
   sección *Artifacts* → `ventisca-windows` (o `ventisca-linux`). Descomprime y abre `Ventisca.exe`
   (`ventisca.x86_64` en Linux). Cada cambio del PR genera una versión nueva.
2. **Anfitrión:** pulsa **Jugar**. El juego arranca un servidor dedicado propio en segundo plano (UDP 7777). En
   Windows, acepta el aviso del cortafuegos para las redes privadas.
3. **Amigos en la misma red:** **Unirse a servidor** → IP local del anfitrión (`ipconfig` en Windows) → puerto 7777.
4. **Amigos por internet**, una de estas tres:
   - una VPN de juego (Tailscale, ZeroTier o Radmin VPN) y la IP que os dé;
   - redirigir **UDP 7777** del router al PC del anfitrión y usar su IP pública;
   - un servidor dedicado en un VPS Linux: `./ventisca.x86_64 --headless -- --server --config server.cfg`
     (plantilla en `server/server.cfg.example`; ponle contraseña).
5. Todos deben usar **la misma versión** (el servidor rechaza versiones distintas). `F3` muestra ping y tráfico.

La demo del navegador es solo para un jugador: el navegador no puede abrir conexiones UDP.

## Pruebas

```bash
cd winter-survival
./tests/run_all.sh [--shots] [--no-walk-render]   # todas las puertas M0–M3: import, parse, persistencia, humo, contrato de arte, perf, red (basic, shared_world, far), determinismo, perf walk [, capturas]
./tests/run_smoke.sh                 # importa + prueba de humo sin pantalla (SMOKE TEST OK / FAILED); offline = servidor local en proceso
./tests/net/run_net_test.sh --clients 4 --duration 60 --soak 90   # 1 servidor + 4 clientes headless: se ven moverse, chat, FF bloqueado, reconexión, ≤ 5 kB/s, soak
./tests/run_screenshots.sh [carpeta] # capturas day/dusk/night/blizzard/interior/menu con xvfb + OpenGL; RENDER=forward = Forward+ con lavapipe (preset `multi` = cliente unido a un servidor)
python3 tools/contact_sheet.py hoja.png 3 "ref=…jpg" "antes=…png" "después=…png"   # hoja de comparación (Pillow)
./tests/run_perf.sh [--placeholders] # sonda de rendimiento (draw calls, objetos, ms) → tests/perf/last.json vs tests/perf_budgets.json
godot --headless --path . -s tests/inspect_models.gd [++ --quiet] [--placeholders]  # contrato ASSET_SPEC v2 de cada .glb (o de los placeholders)
```

Convenciones v2 (`docs/v2/`): frente de los modelos = **+Z** (`Vector3.MODEL_FRONT`), color de vértice + material
compartido `assets/materials/world_vcol.tres` (`snow_amount` global; desde G1 el alfa de `COLOR_0` es AO horneada),
física **Jolt**, partículas GPU y presets de calidad `alto/medio/compat` (autoload `Quality`, `user://settings.cfg`).

Look G1 (`docs/research/06_graficos_render.md`, sección "G1 integrado"): tonemap Filmic con exposición por hora
(`DayNight.KEYS`) y por renderizador (`Quality.exposure_scale`: Compatibility ×0.5), sol bajo a contraluz, ambiente
azul, terreno liso con AO horneada (`Terrain.bake_ao`) y shader `assets/shaders/terrain.gdshader`, huellas en mapa de
rastro (`Footprints`, `DrawableTexture2D`), derrame de ventanas (`WindowSpill`) y cámara a 24 m por defecto (zoom 16–38).
Presets: `alto` = PCSS + SSAO + niebla volumétrica en ventisca + 2 luces omni con sombra; `medio` = SSAO bajo, sin PCSS;
`compat` = Compatibility (sin SSAO/volumétrica/proyectores; la AO horneada lleva el look).
