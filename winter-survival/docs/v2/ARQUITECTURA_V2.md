# VENTISCA v2 — Arquitectura técnica

> Godot **4.7.2**, GDScript tipado, raíz del proyecto `winter-survival/`. Coherente con `docs/PLAN_MAESTRO.md` (decisiones §3, hitos §7), `GDD_MUNDO_ABIERTO.md` (números) y `ASSET_SPEC_V2.md` (arte). Sustituye a `docs/ARCHITECTURE.md` a partir de M2; hasta entonces el documento del slice describe el código que existe.
>
> Cuando este documento dice "servidor" se refiere al proceso headless autoritativo; "cliente" al proceso con render. En modo "un jugador" ambos existen (el cliente lanza el servidor como proceso hijo).

---

## 1. Principios

1. **El servidor es la única verdad.** Mundo, tiempo, clima, botín, zombis, daño, inventarios, estructuras, vehículos (validados) viven en el servidor. El cliente envía **intenciones** (`inputs`, `request_*`) y predice solo su propio movimiento y apuntado.
2. **Un solo camino de código.** Siempre hay servidor dedicado (headless). Un solo `game.tscn`; `game.gd` añade ramas solo‑cliente en tiempo de ejecución. Nada de `call_local`, nada de "si soy host y también jugador".
3. **Mundo determinista + deltas.** Todo generador es una función pura `f(world_seed, cx, cz) → contenido` compartida por cliente y servidor. Solo viajan y se guardan los *deltas* (`wid → estado`).
4. **Datos antes que nodos.** Zombis L1–L3 son registros SoA; solo los L0 tienen `CharacterBody3D` (de un pool). Árboles y props repetidos son instancias de `MultiMesh` indexadas espacialmente; solo se materializan como nodo al interactuar.
5. **Runs headless y en Compatibility.** El servidor no crea partículas, viewports, luces ni UI. El cliente funciona en Forward+ y en `compat`; los efectos exclusivos se activan por preset.
6. **Contrato con el arte.** `Assets.spawn_model(name)` siempre devuelve un `Node3D` con los anclajes requeridos (placeholder si falta el `.glb`). El código nunca lee scripts de Blender; el arte nunca lee GDScript.
7. **Tests como puertas.** Cada hito añade tests headless (humo, red, determinismo, rendimiento) y no se considera terminado sin ellos en verde.
8. **Tipado estático, `class_name` en scripts reutilizables, `@export` para lo ajustable, señales por bus (`Events`), sin `get_node` a hermanos.** Constantes de balance en `scripts/data/balance.gd`; tablas en `data/`.

---

## 2. Topología y arranque

```
                 UDP 7777 (ENet, range coder)                  ┌───────────────────────────┐
  Cliente A ◄──────────────────────────────────────────────►  │ Servidor dedicado (headless)│
  Cliente B ◄──────────────────────────────────────────────►  │  autoritativo · 60 Hz       │
  Cliente C ◄──────────────────────────────────────────────►  │  SQLite (world.db)          │
  Cliente D ◄──────────────────────────────────────────────►  │  admin TCP 127.0.0.1:7778   │
                                                               └───────────────────────────┘
  "Jugar solo" / "Crear partida":
     OS.create_process(OS.get_executable_path(), ["--headless", "--", "--server", "--config", cfg])
     → esperar el banner "READY" en stdout (o 1.5 s) → join("127.0.0.1", 7777)
```

### 2.1 Detección de rol (`Net`)

```gdscript
var args := OS.get_cmdline_user_args()
if OS.has_feature("dedicated_server") or "--server" in args or DisplayServer.get_name() == "headless":
    start_server(_arg(args, "--config", "user://server.cfg"))
```

`OS.has_feature("dedicated_server")` solo es `true` en el export dedicado; con el binario del editor se detecta por `--server`.

### 2.2 Flujo de conexión

1. `ENetMultiplayerPeer.create_client(host, port)`; `peer.host.compress(COMPRESS_RANGE_CODER)`.
2. Servidor: `peer_authenticating` → genera `nonce` (16 B) → `send_auth(id, nonce)`.
3. Cliente: `auth_callback(id, nonce)` → `send_auth(1, JSON{version, proto, name, token, hmac})` con `hmac = HMAC‑SHA256(password, nonce)`; `complete_auth(1)`.
4. Servidor `_server_auth`: comprueba `proto == NET_PROTOCOL`, `version == GAME_VERSION`, contraseña, hueco (`max_players`), lista de baneados (`sha256(token)`, IP). Rechazo: `send_auth(id, "ERR:<motivo>")` + `disconnect_peer(id)`. Éxito: `Players.register(id, name, sha256(token))`, `complete_auth(id)`.
5. `peer_connected(id)` → el servidor carga el perfil (`Persistence.load_player`), instancia `player.tscn` con `name = str(id)`, coloca `net_position`, añade filtro de visibilidad por chunk, `add_child(p, true)` bajo `/root/Game/World/Players` → el `MultiplayerSpawner` lo replica (incluido *late join*).
6. Cliente: `connected_to_server` → `change_scene_to_file("res://scenes/main/game.tscn")` → recibe `WorldState`, su jugador (espejo), `chunk_delta_snapshot` de su anillo.

Parámetros: `auth_timeout = 5 s`, `server_relay = false`, `allow_object_decoding = false`, `refuse_new_connections = true` al llenarse. `Engine.max_fps = 60` en headless. `get_tree().multiplayer_poll = false` y `multiplayer.poll()` en `_physics_process` (inputs alineados con la física).

### 2.3 Modo offline para tests

`tests/` puede arrancar `game.tscn` con `OfflineMultiplayerPeer` (`is_server() == true`, los RPC se ejecutan localmente). Es el modo del `run_smoke.sh` cuando no interesa el proceso hijo. El juego real siempre usa el proceso hijo.

---

## 3. Carpetas

```
winter-survival/
├── project.godot                      # Jolt; features 4.7; autoloads §4; capas §11.4; input §17.3
├── export_presets.cfg                 # Cliente Linux/Windows; "Dedicated Server" Linux x86_64/arm64/Windows (Strip Visuals)
├── addons/godot-sqlite/               # única dependencia de terceros (MIT)
├── assets/
│   ├── models/{chars,zombies,animals,anims,weapons,vehicles,buildings/<style>,props,vegetation,poi,ui}/*.glb
│   ├── rig/humanoid_bonemap.tres      # generado por script (identidad perfil → nuestros nombres)
│   ├── import_templates/*.import      # plantillas de import (chars, anims, buildings, props)
│   ├── materials/ (world_vcol.tres, glass.tres, window_glow.tres, ghost_*.tres, blood.tres)
│   ├── shaders/ (world_vcol.gdshader, snow_include.gdshaderinc, terrain.gdshader, cutaway_include.gdshaderinc,
│   │            trail_stamp.gdshader, frost_vignette.gdshader, outline.gdshader)
│   ├── icons/*.svg   themes/ui_theme.tres   audio/ (vacío o CC0 + LICENSES.md)
├── blender/                           # territorio de Opus (ASSET_SPEC_V2 §1)
├── data/
│   ├── world/ (macro_map.png, macro_roads.json, biomes.gd, poi_registry.gd, stamps/*.exr|*.png)
│   ├── buildings/ (templates/*.json, styles.gd, kits.gd)
│   ├── loot/loot_tables.gd   items.gd   recipes.gd   clothing.gd   weapons.gd   zombies.gd   vehicles.gd
│   ├── anim_events.json               # ventanas de daño, sonidos, eventos de recarga por animación
│   └── server_rules.gd                # claves, tipos y defectos de server.cfg
├── scenes/
│   ├── main/ (boot.tscn, main_menu.tscn, game.tscn)
│   ├── world/ (chunk.tscn, poi/*.tscn, roads/road_tile.tscn, doors/door.tscn, window.tscn)
│   ├── player/ (player.tscn, character_visual.tscn)
│   ├── actors/ (zombie_body.tscn [L0 servidor], zombie_view.tscn [cliente], wolf.tscn, deer.tscn)
│   ├── vehicles/ (vehicle_base.tscn, sedan.tscn, pickup.tscn, van.tscn, snowmobile.tscn, snowplow.tscn)
│   ├── structures/ (campfire.tscn, tent.tscn, crate.tscn, fence.tscn, barricade.tscn, trap.tscn, base_slots/*.tscn)
│   ├── effects/ (snowfall.tscn, blizzard_fog.tscn, snow_trails.tscn, fire_effect.tscn, hit_puff.tscn, blood_splat.tscn, muzzle_flash.tscn)
│   └── ui/ (hud.tscn + paneles: hotbar, rings, thermometer, companions, chat, pings, board, map, wardrobe, backpack,
│            skills, base_panel, storage_panel, craft_panel, vehicle_hud, downed_overlay, death_screen, server_browser, options)
├── scripts/
│   ├── autoload/ (events.gd, net.gd, assets.gd, audio_manager.gd, quality.gd, game_flow.gd, identity.gd)
│   ├── core/ (world_const.gd, guid.gd, rng.gd, spatial_hash.gd, budget_queue.gd, bytes.gd, rate_limit.gd, infractions.gd)
│   ├── net/
│   │   ├── server/ (server_main.gd, players.gd, chunk_interest.gd, validation.gd, admin_socket.gd, admin_commands.gd, lan_beacon.gd)
│   │   ├── client/ (client_main.gd, remote_interp.gd, net_debug_hud.gd, lan_discovery.gd, server_list.gd)
│   │   └── shared/ (net_world.gd, world_state.gd, packets.gd, protocol.gd, chat.gd)
│   ├── player/ (player.gd, player_sim.gd, player_input.gd, player_net.gd, player_view.gd, player_state.gd,
│   │            inventory_component.gd, stats_component.gd, equipment_component.gd, skills_component.gd,
│   │            interactor.gd, placement_controller.gd, camera_rig.gd, aim.gd, downed.gd)
│   ├── world/
│   │   ├── terrain/ (height_function.gd, terrain_chunk.gd, surface.gd, macro_map.gd, stamps.gd)
│   │   ├── streaming/ (world_streamer.gd, chunk.gd, chunk_layers.gd, chunk_state.gd, chunk_delta.gd, world_registry.gd)
│   │   ├── scatter/ (scatter_gen.gd, multimesh_chunk.gd, scatter_index.gd)
│   │   ├── towns/ (settlement_gen.gd, road_graph.gd, road_mesh.gd, parcel_obb.gd, lot_assign.gd, building_assembler.gd, building.gd)
│   │   ├── nav/ (nav_baker.gd, nav_query_queue.gd, nav_links.gd)
│   │   ├── weather/ (day_night.gd, weather.gd, snow_state.gd)
│   │   ├── cutaway/ (cutaway_manager.gd)
│   │   └── objects/ (tree.gd, rock.gd, berry_bush.gd, pickup.gd, drop.gd, door.gd, window.gd, container.gd, campfire.gd,
│   │                 stove.gd, bed.gd, base_slot.gd, ice.gd, corpse.gd, …)
│   ├── ai/ (zombie_system.gd, zombie_brain.gd, zombie_body.gd, zombie_view.gd, zombie_net.gd, senses.gd, sound_events.gd,
│   │        population_manager.gd, director.gd, horde.gd, ai_lod.gd, animal_brain.gd)
│   ├── combat/ (damage_resolver.gd, hit_history.gd, melee.gd, hitscan.gd, projectile.gd, weapon_state.gd, noise.gd)
│   ├── vehicles/ (raycast_vehicle.gd, tire_model.gd, vehicle_builder.gd, vehicle_net.gd, seats.gd, vehicle_parts.gd)
│   ├── systems/ (thermal.gd, clothing.gd, wetness.gd, loot.gd, crafting.gd, base.gd, skills.gd, objectives.gd, sleep_vote.gd)
│   ├── persistence/ (backend.gd, sqlite_backend.gd, file_backend.gd, memory_backend.gd, schema.gd, migrations/*.gd, autosave.gd)
│   ├── components/ (interactable.gd, health.gd, storage.gd, fuel_burner.gd, heat_zone.gd, hover_ring.gd, lootable.gd)
│   ├── effects/ ui/ main/
│   └── data/ (balance.gd, items.gd, placeholders.gd, …)
├── server/ (server.cfg.example, Dockerfile, ventisca.service, admin.sh, run_server.sh, README.md)
├── tools/ (macro_map_viewer.gd [plugin de editor opcional], seed_preview.gd)
└── tests/
    ├── run_all.sh  run_smoke.sh  run_screenshots.sh  run_perf.sh  run_determinism.sh
    ├── smoke_test.gd  smoke_steps.gd  screenshot.gd  inspect_models.gd  parse_check.gd
    ├── net/ (run_net_test.sh, net_smoke.gd, scenarios/*.gd, net_sim.gd)
    ├── perf/ (perf_probe.gd, perf_walk.gd, perf_drive.gd, perf_horde.gd, perf_budgets.json)
    ├── unit/ (thermal_test.gd, loot_test.gd, skills_test.gd, director_test.gd, packets_test.gd, height_test.gd)
    └── determinism.gd
```

Regla: todo lo que hay en `scripts/world/**/gen*` y `scripts/world/terrain/` es **puro** (sin `SceneTree`, sin RNG global) hasta la fase de instanciación.

---

## 4. Autoloads (v2) y lo que deja de serlo

| Autoload | Responsabilidad | Servidor | Cliente |
|---|---|---|---|
| `Events` | Bus de señales. Dividido semánticamente: señales de **simulación** (emitidas en el servidor **con el jugador como argumento**) y de **presentación** (solo cliente). | ✔ | ✔ |
| `Net` | Rol, `server.cfg`, auth, host desde el juego, `poll()`, versión/protocolo, estadísticas ENet. | ✔ | ✔ |
| `Identity` | Token de 32 B en `user://identity.cfg`, nombre, recientes. | — | ✔ |
| `Assets` | `spawn_model`, placeholders, sustitución de `palette_vcol` por el material compartido, caché. En el servidor (Strip Visuals) devuelve el mismo árbol sin píxeles: anclas y `Col*` siguen existiendo. | ✔ | ✔ |
| `Quality` | Preset `alto/medio/compat`, detección de iGPU, aplica ajustes de `Environment`, sombras, partículas. | — | ✔ |
| `AudioManager` | Ganchos por nombre; stub no‑op en servidor. | stub | ✔ |
| `GameFlow` | Menús, conexión, pausa local, muerte/reaparición por RPC, opciones. | — | ✔ |

**Dejan de ser autoloads** (M1): `Inventory` → `InventoryComponent` por jugador (servidor) + espejo; `GameState` → `WorldState` (nodo replicado) + `GameFlow`; `QuestManager` → `ObjectivesComponent` por jugador + tablón compartido.

---

## 5. Escena `game.tscn` (doble sabor)

```
Game (Node3D) [game.gd]
├── Net (rutas fijas para RPC: /root/Game/Net)
├── WorldState (Node + MultiplayerSynchronizer: seed, day, hour, weather, wind_yaw, rules)   ON_CHANGE
├── NetWorld (Node: request_interact/craft/place/take/deposit/fire/melee/…; eventos de mundo)
├── World (Node3D)
│   ├── Streamer (world_streamer.gd)          # chunks como hijos: World/Chunks/c_<cx>_<cz>
│   ├── Chunks (Node3D)
│   ├── Players (Node3D)  + PlayerSpawner (MultiplayerSpawner, spawn_path = Players, escena precargada)
│   ├── Vehicles (Node3D) + VehicleSpawner (spawn_function)
│   ├── Structures (Node3D) + StructureSpawner (spawn_function)
│   ├── Zombies (Node3D)                      # servidor: cuerpos L0 del pool; cliente: vistas del pool (no spawner)
│   ├── Drops (Node3D)                        # replicación propia
│   ├── Nav (Node3D)                          # solo servidor: NavigationRegion3D por chunk
│   ├── Sun, Moon, Env, DayNight, Weather     # DayNight/Weather leen WorldState; luces solo cliente
│   └── Systems (Director, PopulationManager, ZombieSystem, SoundEvents, Persistence, Autosave)   # solo servidor
└── [cliente, añadidos por game.gd en _ready] UI (CanvasLayer), CameraRig, Snowfall, BlizzardFog, SnowTrails,
    CutawayManager, ZombieViewPool, NetDebugHud
```

`game.gd`: `if Net.is_server: _activate_server_branches() else: _add_client_branches()`. Los nodos con RPC viven en rutas idénticas en ambos.

---

## 6. Red

### 6.1 Transporte y canales

| Canal | Modo | Contenido |
|---|---|---|
| 0 | `unreliable_ordered` | Inputs del jugador; estado de jugadores/vehículos (`MultiplayerSynchronizer` ALWAYS) |
| 1 | `reliable` | Interacción, inventario, crafteo, chat, eventos de mundo, snapshots de chunk, `ON_CHANGE` |
| 2 | `unreliable_ordered` | Snapshots de zombis; drops |
| 3 | `unreliable` | Voz (reservado) |

`ENetMultiplayerPeer.create_server(port, max_players, 4)`; compresión `COMPRESS_RANGE_CODER`; `max_sync_packet_size = 1350`; paquetes propios ≤ 1 200 B.

### 6.2 Tick rates (decisión C10)

| Flujo | Frecuencia | Mecanismo |
|---|---|---|
| Física | 60 Hz | ambos |
| Inputs del jugador | 60 Hz generados, **30 Hz enviados** (2 por paquete + redundancia de los 2 anteriores) | RPC `_input(bytes)` canal 0 |
| Estado propio (ack + pos/vel) | 30 Hz | RPC `_state` al dueño |
| Estado de jugadores remotos y vehículos conducidos | 30 Hz (`replication_interval = 1/30`) | `MultiplayerSynchronizer` ALWAYS |
| Vehículos aparcados, estructuras, puertas, contenedores | al cambiar | ON_CHANGE / eventos |
| Zombis | 15 Hz (< 30 m), 10 Hz (30–60 m), 4 Hz (60–120 m); keyframe por chunk cada 1 s | paquetes propios canal 2 |
| Reloj/clima | `hour` cada 5 s ON_CHANGE + extrapolación local; `weather` al cambiar | `WorldState` |
| Interés por peer | recalculado cada 0.5 s | `chunk_interest.gd` |

### 6.3 Paquetes propios (`scripts/net/shared/packets.gd`, `StreamPeerBuffer`)

**Input** (por comando, 30 B):

```
u32 seq | i8 move_x | i8 move_y (mundo, ×127) | i16 aim_yaw (×32767/π) | 3×i16 aim_rel_cm (cursor relativo al jugador, cm)
| u16 buttons (bit0 run, 1 crouch, 2 attack, 3 fire, 4 reload, 5 interact, 6 aim, 7 shove, 8 throw, 9 use_slot, 10 ping, 11 cancel)
| u8 slot | u8 flags (hotbar/aux)
```

Un paquete = `u8 n (1–3)` + n comandos (el más nuevo al final). El servidor descarta `seq` ≤ último aplicado; *jitter buffer* de 1–3 comandos; sin input → repite el último.

**Snapshot de zombis** (canal 2, ≤ 1 200 B):

```
u8 type=ZSNAP | u32 tick | u8 n_chunks | por chunk: u32 chunk_key, u8 n, n × { u16 id, i16 dx, i16 dy, i16 dz (cm desde el origen del chunk), u8 yaw (360/256), u8 state|flags }
```

= **8 B por zombi**. Solo zombis "sucios" desde el último envío a ese peer + keyframe completo por chunk cada 1 s. `state` (u8): 0 idle, 1 wander, 2 investigate, 3 chase, 4 attack, 5 hit, 6 stagger, 7 knocked, 8 dead, 9 frozen, 10 waking, 11 grab, 12 scream, 13 eat, 14 sleep; flags en los 3 bits altos: corredor‑cansado, agarrando, ardiendo.

**Entrada/salida de interés de zombis** (canal 1, fiable): `ZENTER { u16 id, u8 kind, u8 variant, pos (3×f32), u8 yaw, u8 hp_pct, u8 state, u8 equipment }`, `ZLEAVE { u16 id }`, `ZEVENT { u16 id, u8 event (hit, crit, die, dismember, wake, scream), u8 arg, u8 dir }`.

**Snapshot de delta de chunk** (canal 1): `CHUNK_DELTA { u32 chunk_key, PackedByteArray zstd(var_to_bytes(delta_dict)) }` — enviado al entrar el chunk en el interés del peer. `delta_dict = { objects: {wid: {state, hp, data}}, containers: {wid: {items, opened_by}}, structures: [...], vehicles: [...], drops: [...], population: {...} }`.

**Eventos de mundo** (canal 1): `WEVENT { u8 type, u64 wid, Variant data }` — puerta abierta/cerrada/rota, ventana rota, árbol talado, contenedor abierto/cerrado, estructura dañada, fuego encendido/apagado, alarma, ruido (para el anillo), sangre, ping.

### 6.4 Replicación por entidad

| Entidad | Mecanismo | Autoridad | Propiedades |
|---|---|---|---|
| Jugador | `PlayerSpawner` + `ServerSync` (ALWAYS 30 Hz: `net_position`, `net_velocity` (espejo), `aim_yaw`, `aim_point`, `anim_state`, `move_speed`; ON_CHANGE: `display_name`, `hp`, `warmth`, `hunger`, `stamina`, `posture`, `weapon_class`, `downed`, `vehicle_wid`, `seat`, `outfit_ids`) con filtro 3 × 3 chunks **+ siempre el dueño**; `InputSync` no se usa para movimiento (RPC con `seq`). Espejos privados (`InventorySync`, `StatsSync`, `SkillsSync`) con `public_visibility = false` + `set_visibility_for(owner, true)`. | Servidor (inputs del dueño) | Ver §7 |
| Vehículo | `VehicleSpawner.spawn({wid, model, transform})` + sincronizador ALWAYS 30 Hz (`pos`, `rot` quat, `lin_vel`, `ang_vel`, `steer`, `throttle`) con filtro por chunk; ON_CHANGE: `fuel`, `battery`, `parts`, `lights`, `occupants`, `locked`. | **Conductor** mientras conduce (`set_multiplayer_authority(peer)` del nodo del vehículo), servidor cuando no | §12 |
| Estructura colocada | `StructureSpawner.spawn({wid, kind, pos, yaw})`; ON_CHANGE: `hp`, `state`, `fuel`. | Servidor | |
| `WorldState` | Sincronizador ON_CHANGE. | Servidor | `seed, day, hour, weather, wind_yaw, great_blizzard_in, rules` |
| Zombis | Propia (§6.3). Sin nodos en el cliente salvo vistas del pool. | Servidor | |
| Animales | Igual que zombis (`kind` distinto). | Servidor | |
| Drops | Propia: `DROP_ADD {wid, item, count, pos}` / `DROP_REMOVE {wid}` al entrar/salir de interés y al cambiar. | Servidor | |
| Objetos generados (árboles, rocas, edificios, contenedores) | **No se replican**; deltas por `wid` (§6.3). | Servidor | |
| Chat | `say(text)` any_peer fiable → saneado → `broadcast_say(who, text)`. | Servidor | |

Limitaciones respetadas: no se sincronizan `Object`/`Resource`; `CharacterBody3D.velocity` se espeja en `net_velocity`; ≤ 64 propiedades por sincronizador; `ServerSync` antes que cualquier otro sincronizador hijo (GH‑75884); nunca reparentar un nodo con sincronizador (GH‑86501).

**Nota de implementación M1 (vinculante hasta que se revise):** el nodo solo se spawnea en un peer si *todos* sus sincronizadores con autoridad local son visibles para ese peer, así que un sincronizador privado (`InventorySync` con `public_visibility = false`) ocultaría al jugador entero a los demás. Los **espejos privados del dueño** (`slots_packed`, stats, misiones, muerte, antorcha) viajan por un RPC fiable `PlayerNet._mirror(dict)` en canal 1 solo cuando cambian. Las **poses de los jugadores no usan el sincronizador**: `PlayerManager.broadcast_poses()` envía a cada cliente **un paquete crudo por tick de red** (`SceneMultiplayer.send_bytes`, canal 0 no fiable, 30 Hz): `u8 tipo | u32 ack del dueño | 3 × i16 vel | u8 n | n × { u32 peer, 3 × i16 pos cm, i16 yaw }` = 60 B con 4 jugadores (`Packets.pack_poses`); el `ServerSync` conserva solo las propiedades de spawn y las `ON_CHANGE` (`aim_point` a 5 Hz por `delta_interval = 0.2`, flags). Lobos y ciervos replican `net_pose: int` (posición + yaw cuantizados en 64 bits, 12 B) en lugar de `Vector3 + float` (24 B). Medido en `run_net_test.sh` con 4 jugadores moviéndose: **≈ 2.6 kB/s de bajada por cliente (máx. 3.1)**, frente a ≈ 4.8 kB/s con un sincronizador `ALWAYS` por jugador + ack aparte y ≈ 6.4 kB/s con el ack por RPC; el servidor emite ≈ 10 kB/s en total y recibe ≈ 6.7 kB/s (≈ 1.7 kB/s de subida por cliente: inputs 30 Hz con redundancia). Regla derivada: **nunca una `MultiplayerSynchronizer` `ALWAYS` por entidad para lo que cambia cada tick**; un paquete agregado por peer y tick es 2–3× más barato en cabeceras ENet. Otra regla: los `MultiplayerSpawner` van **antes** que `World` en `game.tscn` (y `game.gd` reasigna sus `spawn_path` al estar listo) para que los nodos spawneados salgan del árbol antes que su spawner al apagar: en la plantilla *release* el spawner no reconoce su propia conexión `tree_exiting` al desconectarla en `NOTIFICATION_EXIT_TREE` y escupe `Attempt to disconnect a nonexistent connection` por cada nodo que aún rastrea. En modo `offline` (web, tests) el mismo código corre con `OfflineMultiplayerPeer`: `Net.rpc_to/rpc_all/rpc_server` llaman en directo cuando el destinatario es el propio proceso. El estado del mundo (árboles, pickups, arbustos, fuegos, "en uso" de contenedores) viaja como *deltas* por `wid` (`NetWorld.set_delta` → `_event` / `_delta_snapshot` para los que entran tarde), el `wid` M1 es el hash de la ruta determinista del nodo bajo `World` (M3 lo sustituye por `hash64`).

**Nota de implementación M2 (vinculante hasta que se revise):** cada objeto del mundo expone `interact_actions()`, `server_interact(player, action, arg) -> bool` (solo servidor) y, opcionalmente, `client_preview(player, action)` / `client_preview_cancel` (el cliente dueño muestra el golpe/recogida al instante y lo revierte si el servidor contesta `_interact_result(wid, action, ok, reason)`). `NetWorld.request_interact(wid, action, arg)` valida por este orden: jugador vivo → objeto existe → distancia ≤ alcance + 1 m → acción declarada → herramienta → `can_interact`; cada rechazo suma una infracción (aviso por *toast* a `NET_INFRACTIONS_KICK/2`, expulsión a `NET_INFRACTIONS_KICK`, solo en dedicado) y los *rate limits* son `NetWorld.RATE_LIMITS`. Los deltas viven en un `ChunkDelta` por chunk (`WorldConst`: chunks de 64 m, el claro = chunks 23–25 con el chunk 24 centrado en el origen): `objects` se difunde como `_event(wid, fields)` y viaja entero a cada peer al entrar (`chunk_delta_snapshot(key, size, zstd(var_to_bytes))`, uno por chunk no vacío, M3 lo filtra por interés), `containers` (contenido + `open_by`) solo se persiste, `structures` y `drops` registran lo que crean `StructureSpawner` (`/root/Game/PlacedSpawner`) y `DropSpawner` (`/root/Game/DropSpawner`) para restaurarlo al arrancar. El servidor aplica los deltas guardados al mundo en `world_ready` (`NetWorld.load_from(backend)`): un árbol talado sigue talado tras reiniciar el servidor. Los servidores de prueba (`server.debug_commands=true`, y siempre en *offline*) aceptan los comandos de chat `/kit`, `/give <item> <n>` y `/tp <x> <z>`.

### 6.5 Interest management (`chunk_interest.gd`)

Por peer: conjunto = 3 × 3 chunks alrededor de su jugador (o de su vehículo). Recalculado cada 0.5 s; la diferencia produce `enter/leave`: para nodos con sincronizador vía `add_visibility_filter(func(peer): return Interest.sees(peer, chunk_of(self)))` con `visibility_update_mode = PHYSICS` (el spawn/despawn sigue la visibilidad); para zombis/drops, `ZENTER/ZLEAVE`, `DROP_ADD/REMOVE`. Al entrar un chunk: `CHUNK_DELTA`.

### 6.6 Validación y anti‑abuso (`validation.gd`, `rate_limit.gd`, `infractions.gd`)

- Cada RPC `any_peer`: `get_remote_sender_id()` debe ser el dueño; ids existen y están en interés; distancia ≤ `range + 1.0 m`; cooldowns y `seq`; cantidades en rango.
- *Rate limits*: inputs ≤ 90/s, interact ≤ 5/s, chat ≤ 2/s (≤ 200 chars), craft ≤ 3/s, fire según cadencia × 1.2.
- Movimiento: el servidor **nunca** acepta posiciones del cliente; `move.length() ≤ 1`, desplazamiento por tick ≤ `max_speed × dt × 1.5`, `aim_point` ≤ 40 m.
- Rechazos silenciosos + contador de infracciones por peer → aviso por chat a N/2, *kick* a N (`infractions_kick = 30`).

### 6.7 Predicción y reconciliación del jugador

`PlayerSim.step(body, cmd, dt, params)` es una función pura compartida (aceleración, gravedad, `move_and_slide`, agachado, velocidad efectiva desde `params` que fija el servidor: `move_speed`, `freezing_mult`, `encumbrance_mult`). Cliente dueño: simula, guarda `pending[seq]`, envía; al recibir `_state(ack_seq, pos, vel)`: descarta ≤ ack; si `|pos − pos_srv| > 0.05` → corrige y **re‑simula** los pendientes. Remotos: `RemoteInterp` con buffer de 2–3 snapshots, `t_render = t_srv − 100 ms`, extrapolación ≤ 100 ms. El terreno determinista y los deltas aplicados antes de habilitar la predicción hacen que el error típico sea milimétrico (PoC sin *replay*: 0.33–0.47 m).

### 6.8 *Lag compensation* (`hit_history.gd`)

El servidor guarda 1 s (30 muestras) de posición/yaw/postura de jugadores, zombis L0 y vehículos. `request_fire(seq, client_tick, aim_point)`: cadencia/munición/arma en servidor → `t = client_tick − 100 ms`, rebobinado **≤ 200 ms** → candidatos por esfera → test cápsula (cuerpo) + esfera (cabeza) contra el rayo en GDScript (no se rebobina el `PhysicsServer`) → daño vía `DamageResolver` → `fire_result` al tirador + `WEVENT` a todos. Melee: `request_melee(seq)` → cooldown, cono 90–110° alrededor de `aim_yaw`, alcance + 0.5 m, rebobinado 100–150 ms, ventana de daño de `anim_events.json` evaluada en servidor.

### 6.9 Reglas de servidor en la red

`server_rules.gd` define claves, tipos y defectos; `WorldState.rules` las replica; el HUD muestra `PvP`/`FF`. Solo `DamageResolver` y `Players` (colisión entre jugadores) las consultan (§11.2).

---

## 7. Jugador

```
Player (CharacterBody3D) [player.gd]  name = str(peer_id); _enter_tree: nada de autoridad de cliente salvo InputSync (opcional, no usado para movimiento)
├── ServerSync (MultiplayerSynchronizer, autoridad 1)      # PRIMERO
├── InventorySync / StatsSync / SkillsSync (visibles solo para el dueño)
├── Shape (CapsuleShape3D r 0.35 h 1.7)  · CrouchShape (h 1.1, activada por posture)
├── State (Node) [player_state.gd]                          # servidor: Inventory, Equipment, Stats, Skills, Objectives, Thermal
├── Net (Node) [player_net.gd]                              # inputs, predicción, reconciliación
├── Sim (RefCounted compartido) [player_sim.gd]
├── Downed (Node) [downed.gd]                               # servidor: temporizador, reanimación, muerte
└── [cliente] View (character_visual.tscn) · Input · Interactor · Placement · Aim · CameraRig (top_level) · HoverRing · Breath · TrailEmitter
```

- `character_visual.tscn`: `Model` (glb de personaje con `GeneralSkeleton`) + `AnimationPlayer` (librerías `loco`, `crouch`, `melee`, `guns`, `bow`, `act`, `hit`, `down`, `veh`, `emote`) + `AnimationTree` (ASSET_SPEC v2 §6.5) + `BoneAttachment3D` (`RightHandSocket`, `LeftHandSocket`, `BackSocket`, `HipSocketR`, `HeadSocket`) + `LookAtModifier3D` (cabeza) + `AimModifier3D` (pecho) + `TwoBoneIK3D` (mano de apoyo) + `PhysicalBoneSimulator3D` (ragdoll). Ropa: piezas rígidas ligadas al mismo esqueleto se activan por `outfit_ids`.
- **M2 (`scenes/player/character_visual.tscn` + `character_visual.gd`)**: `Model` (uno de `chars/survivor_{red,blue,green,mustard}.glb` según `Player.outfit`, asignado por el servidor al menos usado; `player.glb` rígido como sustituto si falta) + `AnimationPlayer` (`root_node` = raíz del glb para resolver `%GeneralSkeleton:Hueso`; librería `loco` de `anims/humanoid_loco.glb` + `Act_Chop` generado desde la pose de reposo) + `AnimationTree` construido en código: `Transition "loco"` (Idle | Cold | Walk | Run | CrouchIdle | CrouchWalk, *xfade* 0.12 s) con **`TimeScale` = velocidad real / autorada** (2.2 / 6.0 / 1.3) en el ciclo dominante en lugar de un `BlendSpace1D` (mezclar dos ciclos desliza los pies 21–75 %; el ciclo escalado desliza 1 %), → `Blend2 "upper"` (filtro de torso, capa de clase de arma de M4/M5, peso 0) → `OneShot "action"` (filtro de torso). El árbol y los modificadores avanzan en el *callback* de física, después del `PlayerView` que mide la **velocidad de suelo real por tick** (desplazamiento, no `velocity`: en pendiente o contra un obstáculo `velocity` miente y los pies patinan). `LookAtModifier3D` (Head, eje +Z, límites 75°/35°) bajo `GeneralSkeleton` apunta a `AimTarget` = `aim_point`; `BoneAttachment3D` externos en `RightHandSocket` (herramientas, transformación identidad: mango +Y = pulgar, filo +Z = nudillos) y `HeadSocket` (aliento). Remotos: velocidad del búfer de interpolación suavizada; `crouching`, `running`, `cold` (nuevo, ON_CHANGE) y `outfit` (nuevo) viajan en `ServerSync`. `get_bone_global_pose` devuelve la pose **antes** de los modificadores (el esqueleto la restaura tras actualizar la piel): lo que ve el jugador se lee en los `BoneAttachment3D`.
- `Aim`: proyecta el cursor al plano y = 1.2 m; magnetismo; produce `aim_yaw` y `aim_point`; alimenta la inclinación de cámara.
- `Interactor`: raycast del cursor (capas `world | actors | interactable | vehicles`), hover, *auto‑walk* predicho (línea recta + `ShapeCast3D`), al llegar `NetWorld.request_interact(wid, action)`; UI optimista + `interact_ok/denied`.
- `PlayerState` (servidor): `InventoryComponent` (10 ranuras + mochila por peso; API del slice: `add/remove/count/has/hand_tool/equip_from_slot/use_slot/eat_best/take/deposit`), `EquipmentComponent` (6 ranuras de ropa + arma), `StatsComponent` (§5 del GDD; `thermal.gd` calcula `T_sentida`), `SkillsComponent`, `ObjectivesComponent`. Espejos: `slots_packed: PackedByteArray` (u16 id, u8 count, u8 durability por ranura), `equipment_packed`, `stats_packed` (5 × f32), `skills_packed`.

---

## 8. Mundo

### 8.1 Constantes (`world_const.gd`)

`CHUNK = 64.0`, `CHUNKS = 48`, `HALF = 1536.0`, `SAMPLES = 65` (1 m), `chunk_of(x) = floori((x + HALF) / CHUNK)`, `chunk_key(cx, cz) = (cx << 16) | cz`, `chunk_origin(cx, cz) = Vector3(cx * 64 − 1536, 0, cz * 64 − 1536)`. El origen del mundo (claro) está en el chunk (24, 24).

### 8.2 Función de altura (`height_function.gd`, pura)

```
h(x, z) = base_fbm(seed, x, z) × 6.0                    # FastNoiseLite fBm 3 oct, f 0.012, semilla fija
        + low_fbm(seed, x, z) × 3.0                      # f 0.004
        + macro_height(x, z)                             # bilineal de macro_map.png canal R (0–255 → 0–120 m)
        + Σ stamps(x, z)                                 # sellos: pad(center, r, h) con smoothstep; road(spline, w); lake(poly, level)
surface(x, z) → { SNOW_DEEP, SNOW_PACKED, ASPHALT, DIRT, ICE, INTERIOR, ROCK }  # de macro (canal G), carreteras y lagos
```

Determinismo: enteros y `RandomNumberGenerator` sembrado por `hash64(seed, cx, cz, gen_id)`; nunca `randi()` global ni `Dictionary.keys()` sin ordenar. `tests/determinism.gd` compara hashes de altura (cuantizada a cm), `surface` y listas de scatter de 50 chunks entre dos procesos. Diferencias de coma flotante entre arquitecturas (x86 vs arm64) solo afectan a la altura en < 1 mm y las tolera la reconciliación (5 cm); la colocación de objetos usa RNG entero y es exacta.

### 8.3 `terrain_chunk.gd`

65 × 65 muestras (comparte bordes con vecinos); `ArrayMesh` **indexado** (4 225 vértices, 8 192 tris); normales planas en el fragment (`NORMAL = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)))`); `COLOR` = nieve/nieve‑sombra por pendiente + ruido; `CUSTOM0` = máscara de superficie (asfalto, hielo, tierra, nieve profunda); `StaticBody3D` + `HeightMapShape3D` (capa `world`). Generación en `WorkerThreadPool` (< 3 ms), `add_child` en hilo principal. En servidor, igual sin material.

### 8.4 Plano macro (`macro_map.gd`, `data/world/`)

`macro_map.png` 384 × 384 (1 px = 8 m): R altura base, G bioma (0 bosque denso, 1 bosque, 2 campo, 3 lago, 4 montaña/borde, 5 asentamiento), B "densidad de scatter". `macro_roads.json`: splines (`points`, `width`, `kind: highway|road|track`). `poi_registry.gd`: `{ id, name, region, center, yaw, radius, scene, stamp, chunk_kind }` — las coordenadas del mapa de PLAN §4.2. `biomes.gd`: parámetros de scatter por bioma. Fable dibuja el macro en M3 (v0) y M9a (final); `tools/macro_map_viewer.gd` lo previsualiza en el editor.

### 8.5 Streaming (`world_streamer.gd`)

- Anillos por jugador local (cliente) o por cada jugador (servidor). Prioridad: chunks delante de la velocidad > laterales > detrás; el centro se desplaza 1 chunk hacia `velocity` si |v| > 8 m/s.
- Capas por chunk (`chunk_layers.gd`): `TERRAIN` (r2), `SCATTER` (r2), `BUILDINGS` (r1, memoria en r2), `DYNAMIC` (r1, servidor), `NAV` (r1, servidor).
- Carga: `ResourceLoader.load_threaded_request(path, "", true)` para escenas de edificios/POIs; `load_threaded_get` solo con `THREAD_LOAD_LOADED`; instanciación en cola con presupuesto **2 ms/frame** (`Time.get_ticks_usec()`); edificios grandes divididos en sub‑escenas.
- Descarga: al salir del anillo 2 (cliente) o tras 60 s sin jugador a < 3 chunks (servidor: hibernar = volcar `ChunkDelta` a persistencia y `queue_free`).
- Estados del chunk (`chunk_state.gd`): `UNLOADED → GENERATING → WARM → HOT → HIBERNATING`.

### 8.6 Scatter (`scatter_gen.gd`, `multimesh_chunk.gd`, `scatter_index.gd`)

Muestreo Poisson por chunk con RNG sembrado, por bioma; salida: listas `{kind, variant, pos, yaw, scale}`. Cliente: un `MultiMeshInstance3D` por `(chunk, variant)` con `custom_data` (tinte, nieve). `scatter_index`: hash espacial de celdas de 8 m → índice de instancia; el raycast del cursor golpea un `Area3D`/`StaticBody3D` por chunk con formas por árbol (talables) o consulta el índice por posición. Al talar: instancia a escala 0 en el MultiMesh + `tree.tscn` real para la animación; delta `world_objects[wid].state = REMOVED` (el cliente que entra más tarde lo aplica al construir el MultiMesh).

### 8.7 Identidad y registro (`guid.gd`, `world_registry.gd`)

`wid = hash64(world_seed, cx, cz, generator_id, index)` (procedural) o `random64 | (1 << 63)` (creado por jugador). `WorldRegistry.get(wid)` devuelve el nodo materializado (o materializa desde el índice de scatter / la lista de `Spawn_*` del edificio). Todo RPC de interacción viaja por `wid`.

### 8.8 Deltas y persistencia por chunk (`chunk_delta.gd`)

`ChunkDelta { objects: {wid: {state, hp, data}}, containers: {wid: {items, rolled_day, opened_by}}, structures: {wid: {...}}, vehicles: {wid: {...}}, drops: {wid: {...}}, population: {alive, killed, cleared_until, last_visit} }`, con `dirty` por tabla. Se aplica al chunk al instanciar (cliente y servidor), viaja en `CHUNK_DELTA` y se vuelca en `Autosave`.

M2 (`scripts/net/shared/chunk_delta.gd`): `objects`, `containers`, `structures`, `drops`, `population`; `merge(table, wid, fields)`, `to_net_dict()` (sin `containers`), `pack()/unpack()` (zstd), `to_dict(only_dirty)/from_dict` (wids como cadenas para JSON). Índice `wid → chunk` en `NetWorld` (`chunk_for(wid)`), clave `WorldConst.key(cx, cz)` = `cx << 16 | cz`.

---

## 9. Asentamientos y edificios

### 9.1 Pipeline (`settlement_gen.gd`, determinista por `hash64(seed, settlement_id)`)

1. **Huella** del `poi_registry`: centro, radio, tipo (`town | village | farm`), orientación, carretera de acceso.
2. **Red viaria** (`road_graph.gd`): pueblo = cuadrícula con *jitter* (calles cada 60–90 m, ±10 m, ±8°), recortada por pendiente > 12° y agua; aldea = calle principal + 1–2 ramales (grafo de 3–6 aristas). Anchos: asfalto 8 m (autovía) / 7 m (calle) / 4 m (camino).
3. **Cinta de carretera** (`road_mesh.gd`): malla propia a lo largo de la spline con sección (carriles, arcenes, bermas de nieve), sello de altura (aplana) y máscara `ASPHALT`; en asentamientos, baldosas de 8 × 8 m del kit (`road_tile.tscn`: recta, X, T, curva, fin, cebra, aparcamiento) alineadas a la rejilla.
4. **Parcelas** (`parcel_obb.gd`): polígonos entre calles → subdivisión recursiva por la mediana de la OBB hasta 400–900 m² (casas) o 1 200–2 500 m² (comercio/servicios); sin frente a calle se descarta.
5. **Uso** (`lot_assign.gd`): pueblo 65 % casas / 15 % comercio / 8 % servicios / 12 % vacías‑parques; aldea 80/10/5/5; POIs reservados (iglesia, comisaría, hospital, escuela, depósito) en las mejores parcelas primero. Enterables: 45 % de casas, 100 % de comercios/servicios; el resto con puerta tapiada.
6. **Ensamblado** (`building_assembler.gd`): instancia la `.glb` de la plantilla (`data/buildings/templates/<id>.json` → `assets/models/buildings/<style>/<id>.glb`), aplana el pad, lee `Door_n` (→ `door.tscn`), `Window_n` (→ `window.tscn`), `Spawn_<kind>_n` (→ contenedor, mueble, luz, cama, estufa, zombi dormido, loot suelto), grupos de corte, `Col*`. Sub‑escenas para edificios > 6 k tris (fachada / interior / mobiliario / contenedores).
7. **Botín**: cada `Spawn_Container_n` → `container.gd` con `loot_table_id` (tabla por tipo de edificio) y `wid`; tirada en servidor al primer `request_open` (§9.6).
8. **Zombis**: `Spawn_Zombie_n` y densidad por chunk → `PopulationManager`.

### 9.2 Puertas y ventanas

`door.gd` (servidor autoritativo; `WEVENT` al cambiar): estados `closed | open | locked | broken | barricaded`; acciones `open/close` (6/15 m ruido), `force` (palanca, 8 m, 3 s), `break` (zombis: 3 s por golpe × PV), `lock/unlock` (llave), `barricade`. Navegación: cada puerta tiene un `NavigationLink3D` habilitado solo si `open|broken`. `window.gd`: `intact | broken | boarded`; romper 25 m; entrar por ventana rota (canal 1.5 s); rota = −0.1 de aislamiento del edificio.

### 9.3 Corte (`cutaway_manager.gd`, cliente)

Para cada edificio a < 30 m del jugador local: si el jugador (o el cursor) está dentro en la planta *k*: ocultar `Roof` y todo `Floor/Walls/Interior` de plantas > k; en la planta k, sustituir por `Walls<k>_<dir>_Stub` las fachadas cuya normal exterior satisface `normal.dot(to_camera) > 0.15`. Fuera: todo visible. Recalcula en `camera_yaw_changed`, al cambiar de planta y al cruzar la puerta. Hidden = `visible = false`; los `Col*` son hermanos, no se tocan. Opcional M10: stencil (cilindro invisible + `cutaway_include.gdshaderinc` descarta píxeles).

### 9.4 Interiores

Mobiliario decorativo ya fusionado en `Interior<k>`; mobiliario interactivo (contenedores, camas, estufas, bancos) instanciado desde `Spawn_*` con `wid`. Superficie `INTERIOR` (sin nieve, sin huellas, ruido ÷ 2).

### 9.5 POIs a mano

`scenes/world/poi/<id>.tscn` con nodo raíz `Poi` (`poi.gd`: `stamp`, `chunks`, `spawns`), colocados por `poi_registry`. Se cargan como capa `BUILDINGS` de sus chunks. El claro del cazador es el POI `hunter_clearing` (chunks 23–25 × 23–25).

### 9.6 Botín (`loot.gd`, `data/loot/loot_tables.gd`)

`roll(container_wid, table_id, day) → items` con `rng.seed = hash64(seed, wid, rolled_day)`; se aplican `nominal` por categoría/región (contadores por región en `world_meta`); resultado persistido en `containers`. Reabastecimiento: tarea diaria del servidor que borra filas de contenedores en chunks con `last_visit` > 72 h y sin jugador a < 150 m durante 48 h, con probabilidad `loot_respawn` (la siguiente apertura re‑tira al 60 %).

---

## 10. Navegación e IA

### 10.1 Navmesh (`nav_baker.gd`, servidor)

Por chunk caliente: `NavigationServer3D.parse_source_geometry_data()` (hilo principal, `STATIC_COLLIDERS`, `filter_baking_aabb` = AABB del chunk + `border_size` 0.4) → `bake_from_source_geometry_data_async()` (hilo secundario) → `region_set_navigation_mesh`. `cell_size 0.25`, `cell_height 0.2`, `agent_radius 0.4`, `agent_height 1.8`, `edge_connection_margin 0.5`, `map_set_use_async_iterations(map, true)`. Rehorneado con *cooldown* 2 s ante puertas rotas/barricadas (las puertas normales son `NavigationLink3D`). Coste típico 20–60 ms en hilo. **Sin `NavigationAgent3D`**.

### 10.2 `nav_query_queue.gd`

Cola global ≤ 40 `map_get_path` por tick; prioridad L0 > L1; un agente repite ruta cada 0.5–1 s (L0) / 2 s (L1) solo si el objetivo se movió > 2 m; zombis a < 6 m con el mismo objetivo comparten la ruta del líder.

### 10.3 `ZombieSystem` (servidor, SoA)

```
ids: PackedInt32Array · kind/variant/state/flags: PackedByteArray · pos: PackedVector3Array · yaw: PackedFloat32Array
hp: PackedFloat32Array · target_pos: PackedVector3Array · target_kind: PackedByteArray · path: Array[PackedVector3Array]
lod: PackedByteArray (0–3) · chunk: PackedInt32Array · think_at: PackedFloat32Array · body: Array[ZombieBody|null]
```

- **LOD** (`ai_lod.gd`): recalculado cada 0.5 s por distancia al jugador más cercano (40 / 120 / 400 m) y estado del chunk. L0 toma un `ZombieBody` (`CharacterBody3D`, cápsula, capa `zombies` que no colisiona con otros zombis salvo separación por *spatial hash*) del pool (≤ 150); L1 se mueve por interpolación sobre su ruta con altura de `height_function`; L2 son `Horde` (§10.6); L3 registros por chunk en `PopulationManager`.
- **Brain** (`zombie_brain.gd`): `idle/wander/investigate/chase/attack/hit/stagger/knocked/dead/frozen/waking/grab/scream/eat/sleep`; sentidos (`senses.gd`) con cono, oído (`sound_events.gd`: cola de `SoundEvent` por chunk, consulta por radio), olfato; memoria 20/45 s. Pensar en *round‑robin*: L0 cada 6 ticks (10 Hz), L1 cada 30 ticks (2 Hz).
- **Ataques**: ventana de daño en servidor (cápsula del jugador a ≤ alcance, cono 60°), `DamageResolver`.
- **Congelación**: exterior + T ≤ −10 °C + sin estímulo 300 s → `frozen` (sin proceso, sin cuerpo: pasa a registro L3 aunque esté cerca; se materializa como L0 "frozen" solo dentro de 40 m para poder ejecutarlo/golpearlo).
- RVO (`agent_set_avoidance_enabled`) solo L0 a < 20 m de un jugador; `neighbor_distance 4`, `max_neighbors 6`, `time_horizon_agents 0.5`.

### 10.4 Replicación (`zombie_net.gd`)

Por peer: conjunto de interés = zombis L0/L1 en sus 3 × 3 chunks (≤ 200; recorte por distancia si más). `ZENTER/ZLEAVE` al cambiar; snapshots por bandas (§6.2); presupuesto por paquete (≤ 1 200 B; si sobra, los más lejanos esperan al siguiente); keyframe por chunk cada 1 s.

### 10.5 Cliente (`zombie_view.gd`, `ZombieViewPool`)

Pool de ≤ 64 `zombie_view.tscn` (`character_visual` con variante de malla por `kind/variant`); asignación por `id`; buffer de snapshots + interpolación 100 ms; `AnimationTree` conducido por `state` + velocidad derivada; LOD de animación: `callback_mode_process = MANUAL` a 10–15 Hz fuera de pantalla o > 30 m, desactivado > 60 m; ragdoll solo a < 25 m y dormido a los 3 s; contornos de 2 px (`outline.gdshader`); cadáveres cosméticos 120 s.

### 10.6 Población, hordas y director

- `population_manager.gd`: por chunk `{density_target, alive, killed, cleared_until, last_visit, frozen_seed}`; rellena L3 al calentar un chunk (`density × zombie_count_scale × escala_por_jugadores`, menos `killed`), reaparición según §6.4 del GDD; recicla congelados.
- `horde.gd` (L2): `{id, kind (wandering|migratory|assault), count, center, path (grafo de carreteras), state (sleep|move|attack), target}`; se desempaqueta en L1/L0 al entrar en 120 m de un jugador; la migratoria persiste (`hordes`).
- `director.gd`: intensidad por jugador, zonas activas (fusión a 150 m), fases, presupuesto por zona, eventos ponderados, reglas de cortesía (GDD §6.6). Tests en `tests/unit/director_test.gd` con reloj simulado.
- `animal_brain.gd`: lobos y ciervos como `kind` del `ZombieSystem` con estados propios (M9b); hasta entonces `wolf.gd`/`deer.gd` del slice con `DamageResolver`.

---

## 11. Combate y daño

### 11.1 `DamageResolver.apply(attacker: Ref, victim: Ref, dmg: float, kind: DamageKind, zone: HitZone, ctx) → DamageResult`

`Ref = {kind: PLAYER|ZOMBIE|ANIMAL|VEHICLE|WORLD|FIRE, id, faction}`; `DamageKind = MELEE_BLUNT|MELEE_SHARP|MELEE_PIERCE|BULLET|BUCKSHOT|ARROW|EXPLOSION|FIRE|VEHICLE|FALL|COLD|BITE`. Único punto que lee `rules.pvp` y `rules.friendly_fire`; aplica multiplicadores (crítico ×3, chaleco ×0.5, casco, congelado ×1.5 contundente, `Malherido`), durabilidad, derribo, desmembramiento, `Fiebre`; registra `attacker` para la causa de muerte; emite `WEVENT` (sangre, hit, crit, die). Tests: `tests/unit/damage_test.gd` (matriz pvp × ff × facción × kind).

### 11.2 Política jugador→jugador

```
if victim.kind == PLAYER and attacker.kind == PLAYER:
    if rules.pvp and attacker.faction != victim.faction: mult = 1.0
    else: mult = {off: 0.0, reduced: 0.25 (×0.5 explosivos), full: 1.0}[rules.friendly_fire]
```

Colisión entre jugadores: `Players` fija máscaras (`pvp` → capa `player` en máscara de jugadores).

### 11.3 Armas (`weapon_state.gd`, `data/weapons.gd`)

Estado por arma equipada en servidor: `ammo_in`, `durability`, `jam`, `mods`; cadencia, dispersión actual (cono), retroceso, recarga (temporizador cancelable). Cliente refleja `weapon_class` y `ammo` por espejo. `hitscan.gd` (§6.8), `melee.gd`, `projectile.gd` (servidor spawnea por `spawn_function`; ambos lados integran desde el estado inicial; copia predicha local sustituida por la oficial al emparejar `seq`; impacto lo decide el servidor).

### 11.4 Ruido (`noise.gd`)

`emit(pos, radius, priority, source_kind)` en servidor → `SoundEvents` (IA) + `WEVENT NOISE` (anillo en clientes con interés). Modificadores: interior ÷ 2, ventisca ×0.6, `noise_scale`.

### 11.5 Derribado y muerte (`downed.gd`)

Servidor: `hp ≤ 0` → `downed = true`, temporizador 60/40 s, mordiscos −5 s, `request_revive(target)` (canal 4/2 s, interrumpible), `request_give_up`; muerte → `corpse.gd` (`corpses`, 48 h de juego) con inventario, `request_respawn` tras 20 s en la cama de base o el spawn; contador de derribos se resetea al dormir.

---

## 12. Vehículos

- `raycast_vehicle.gd` (`RigidBody3D`, masa por modelo, `contact_monitor`, `max_contacts_reported 8`): 4 raycasts (o `ShapeCast3D` esférico) desde `WheelXX`, suspensión muelle‑amortiguador (rigidez desde masa y reparto), `tire_model.gd` (lateral ∝ ángulo de deriva saturado; longitudinal por deslizamiento; μ por `surface.gd` desde la máscara del terreno o `surface` en metadatos de colisionadores), motor con curva simple + caja automática, freno, marcha atrás, claxon, faros (`OmniLight3D`/`SpotLight3D` solo cliente).
- `vehicle_builder.gd`: lee anclas de la `.glb` (`WheelFL/FR/RL/RR`, `Seat_*`, `Exit_*`, `Interact_*`, `Headlight_*`, `Taillight_*`, `Exhaust`, `FuelCap`, `ColChassis`, `ColCabin`, `Plow`) y construye `CollisionShape3D` convexos, asientos y puntos.
- `seats.gd`: ocupantes por referencia (`vehicle_wid + seat` en el jugador; su cuerpo se desactiva y su `View` se coloca en el asiento cada frame en el cliente). Entrar/salir por `request_enter(wid, seat)` / `request_exit` (punto libre comprobado con `ShapeCast3D`).
- `vehicle_net.gd`: al entrar el conductor, `set_multiplayer_authority(peer)`; el servidor valida cada estado recibido (velocidad ≤ v_max × 1.2, desplazamiento por tick, altura sobre terreno ± 3 m, no atraviesa estáticos: raycast entre posiciones) → *snap* + infracción si falla; al salir, autoridad al servidor y `sleeping`.
- `vehicle_parts.gd`: `engine`, `wheels[4]`, `battery`, `body` (parabrisas); daño por impulso de contacto; atropello = daño a zombis por velocidad relativa (servidor); `fuel` por rpm; batería por frío; llaves/puentear/alarma; calefacción → `thermal.gd` (fuente para ocupantes).
- Persistencia: `vehicles` (60 s si se movió + al aparcar). Restos estáticos: props con `container.gd` (mismo generador de Blender).

---

## 13. Clima, tiempo, frío

- `WorldState` (servidor avanza `hour`; clientes extrapolan): `day, hour, weather (clear|blizzard|great_blizzard|thaw), wind_yaw, wind_speed, great_blizzard_in_days`.
- `weather.gd` (servidor): planificador de ventiscas (GDD §2.5), Gran Ventisca cada `great_blizzard_days`, deshielo raro; emite cambios. Cliente: `day_night.gd` (sol/luna/entorno del slice), `blizzard_fog.tscn` (`FogVolume` en Forward+, niebla exponencial en `compat`), partículas, `snow_state.gd` (sube `snow_amount` global en ventisca, baja 0.5 %/s).
- `thermal.gd` (servidor, por jugador, 2 Hz): `T_sentida` con `clothing.gd` (capas, cortaviento, humedad) + `wetness.gd` (fuentes, secado) + fuentes de calor (`HeatZone` sumadas + interior de edificio/vehículo con aislamiento) → drenaje/ganancia de Calor, congelación, fiebre. Funciones puras testeadas en `tests/unit/thermal_test.gd`.
- Hielo (`ice.gd`): mapa de grosor por lago desde la semilla (`thick|thin|hole`), crujido al pisar fino, rotura por masa (> 1 200 kg o Coloso/Hinchado), caída al agua.

---

## 14. Nieve y huellas

- `snow_include.gdshaderinc`: `albedo = mix(base, snow_color, smoothstep(0.55, 0.85, world_normal.y) * snow_amount)`; incluido en `world_vcol.gdshader` y `terrain.gdshader`. `snow_amount` = `RenderingServer.global_shader_parameter_set`.
- `snow_trails.tscn` / `SnowTrailMap` (cliente): `SubViewport` 1024² con cámara ortográfica cenital sobre 64 × 64 m alrededor del jugador local, capa de render exclusiva, `render_target_clear_mode = NEVER`, sellos (quads) bajo pies de todos los personajes visibles, ruedas y cadáveres arrastrados; re‑proyección cuando el jugador cruza 8 m; decaimiento 0.5 %/s; la `ViewportTexture` entra a `terrain.gdshader` como desplazamiento de vértice negativo + oscurecimiento. Interfaz `stamp(pos, size, strength)` para migrar a `DrawableTexture2D`.

---

## 15. Persistencia

### 15.1 Interfaz

```gdscript
class_name PersistenceBackend
func open(path: String) -> Error
func load_world_meta() -> Dictionary;            func save_world_meta(d: Dictionary) -> void
func load_player(token_hash: String) -> Dictionary; func save_player(token_hash: String, d: Dictionary) -> void
func load_chunk_delta(cx: int, cz: int) -> ChunkDelta; func save_chunk_delta(delta: ChunkDelta) -> void   # solo tablas sucias
func load_hordes() -> Array; func save_hordes(a: Array) -> void
func log_event(type: String, data: Dictionary) -> void
func backup(path: String) -> Error;               func close() -> void
```

`SqliteBackend` (producción, M5), `FileBackend` (M2: **un** documento JSON con `world`, `players`, `chunks`, `hordes`, `events`; escritura atómica `.tmp` + `rename` en `flush()`, `backup()`; carga también el formato M1 de solo perfiles), `MemoryBackend` (tests, *offline*; `FileBackend` lo extiende). `save_chunk_delta` guarda solo las tablas sucias y limpia `dirty`. La misma suite `tests/unit/persistence_test.gd` corre sobre los dos backends de M2 (y el SQLite cuando exista). `PlayerManager` es quien llama: `save_all()` (autoguardado, `save`, `save-and-quit`) = perfiles conectados + `world_meta` + `NetWorld.save_to(backend)` + `flush()`; `on_world_ready` = `NetWorld.load_from(backend)` antes de aparecer a nadie.

### 15.2 Esquema SQLite (`schema.gd`; `PRAGMA journal_mode=WAL; synchronous=NORMAL; user_version=N`)

```sql
CREATE TABLE world_meta(key TEXT PRIMARY KEY, value TEXT);                 -- seed, version, day, hour, weather, rules_json, nominal_counters_json
CREATE TABLE players(token_hash TEXT PRIMARY KEY, name TEXT, x REAL, y REAL, z REAL, yaw REAL,
  hp REAL, warmth REAL, hunger REAL, stamina REAL, fever REAL, max_hp REAL,
  inventory_json TEXT, equipment_json TEXT, skills_json TEXT, objectives_json TEXT, flags_json TEXT,
  faction TEXT, downs INT, last_seen INT, created INT);
CREATE TABLE chunks(cx INT, cz INT, first_visit INT, last_visit INT, pop_alive INT, pop_killed INT, cleared_until INT,
  PRIMARY KEY(cx, cz));
CREATE TABLE world_objects(wid INT PRIMARY KEY, cx INT, cz INT, kind TEXT, state INT, hp REAL, data_json TEXT, updated INT);
CREATE TABLE containers(wid INT PRIMARY KEY, cx INT, cz INT, items_json TEXT, rolled_day INT, opened_by TEXT, updated INT);
CREATE TABLE structures(wid INT PRIMARY KEY, cx INT, cz INT, kind TEXT, x REAL, y REAL, z REAL, yaw REAL, owner TEXT, faction TEXT,
  hp REAL, data_json TEXT, updated INT);
CREATE TABLE vehicles(wid INT PRIMARY KEY, cx INT, cz INT, model TEXT, transform_json TEXT, fuel REAL, battery REAL,
  parts_json TEXT, inventory_json TEXT, keys_json TEXT, locked INT, updated INT);
CREATE TABLE drops(wid INT PRIMARY KEY, cx INT, cz INT, item TEXT, count INT, x REAL, y REAL, z REAL, expires INT);
CREATE TABLE corpses(wid INT PRIMARY KEY, cx INT, cz INT, owner TEXT, x REAL, y REAL, z REAL, inventory_json TEXT, expires INT);
CREATE TABLE hordes(id INT PRIMARY KEY, kind TEXT, count INT, x REAL, z REAL, target_x REAL, target_z REAL, state TEXT, data_json TEXT);
CREATE TABLE bases(id INTEGER PRIMARY KEY, building_wid INT, faction TEXT, tier INT, slots_json TEXT, heat REAL, updated INT);
CREATE TABLE blueprints(id TEXT PRIMARY KEY, unlocked_by TEXT, day INT);
CREATE TABLE bans(token_hash TEXT PRIMARY KEY, ip TEXT, reason TEXT, ts INT);
CREATE TABLE events(id INTEGER PRIMARY KEY AUTOINCREMENT, ts INT, type TEXT, data_json TEXT);
CREATE INDEX idx_objects_chunk ON world_objects(cx, cz);  -- e idem en containers, structures, vehicles, drops, corpses
```

`items_json` = formato del inventario (`[{id, count, durability, data}]`). Migraciones en `persistence/migrations/NNN_*.gd` por `user_version`.

### 15.3 Autoguardado (`autosave.gd`)

Cada 60 s: una transacción con todos los `ChunkDelta` sucios + jugadores conectados + `world_meta` + hordas. Además: al cerrar contenedor, al desconectar, al hibernar chunk, `/save`, `save-and-quit`. `VACUUM INTO 'backup-YYYYMMDD.db'` diario (conserva 7). El cliente **no guarda** (solo opciones e identidad).

### 15.4 Reconexión

Al desconectar, el jugador se guarda y su cuerpo queda 60 s en el mundo (`grace`); al volver con el mismo token se restaura; si pasan los 60 s, se despawnea y se restaura del SQLite al volver.

---

## 16. Servidor dedicado: build, configuración, operación

### 16.1 Export

Preset "Dedicated Server" (Linux x86_64, Linux arm64, Windows x86_64) con **Export as dedicated server** + **Strip Visuals**. Incluir `addons/godot-sqlite/bin/*.so|.dll`. Salida `ventisca_server.<arch>` + `.pck`. `application/run/flush_stdout_on_print = true`, `debug/file_logging/enable_file_logging = true`.

### 16.2 `server.cfg` (formato `ConfigFile`)

```ini
[server]
name="Ventisca de Pedro"
password=""                       ; vacío = sin contraseña
port=7777
max_players=4
motd="Abrígate."
admin_tokens=["<sha256 del token del admin>"]
lan_beacon=true                   ; responde al descubrimiento LAN (UDP 7776)
infractions_kick=30

[world]
seed=1337
save_path="user://world.db"
backend="sqlite"                  ; sqlite | file
autosave_seconds=60
day_length_sec=1800
great_blizzard_days=7
difficulty="normal"

[rules]                           ; GDD v2 §12.4 (todas replicadas en WorldState.rules)
pvp=false
friendly_fire="off"               ; off | reduced | full
safehouses=true
days_to_claim=3
no_raid_when_offline=true
container_locks="faction"
fire_spread=false
vehicle_theft="faction"
permadeath=false
loot_respawn=0.6
zombie_count_scale=1.0
noise_scale=1.0
cold_scale=1.0
ammo_crafting=true
personal_loot_bags=false
safety_system=true
sleep_vote="majority"

[net]
send_rate=30
zombie_rate=10
interest_chunks=1
max_kbps_per_client=300
admin_port=7778                   ; TCP, solo 127.0.0.1
net_sim=""                        ; "80,20,2" = latencia ms, jitter ms, pérdida % (solo desarrollo)
```

### 16.3 systemd

```ini
[Unit]
Description=Ventisca dedicated server
After=network-online.target
Wants=network-online.target
[Service]
User=ventisca
WorkingDirectory=/srv/ventisca
ExecStart=/srv/ventisca/ventisca_server.x86_64 --headless -- --server --config /srv/ventisca/server.cfg
ExecStop=/srv/ventisca/admin.sh save-and-quit
Restart=always
RestartSec=5
TimeoutStopSec=30
Environment=HOME=/srv/ventisca
Nice=-5
[Install]
WantedBy=multi-user.target
```

El headless de 4.7.2 **termina al instante con `SIGTERM`/`SIGINT`** (verificado): el apagado limpio solo existe por el socket de admin; el autoguardado de 60 s acota la pérdida.

### 16.4 Docker

```Dockerfile
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*
RUN useradd -m ventisca
WORKDIR /srv/ventisca
COPY --chown=ventisca ventisca_server.x86_64 ventisca_server.pck libgdsqlite.linux.template_release.x86_64.so ./
USER ventisca
VOLUME ["/data"]
EXPOSE 7777/udp
ENV HOME=/data
ENTRYPOINT ["./ventisca_server.x86_64", "--headless", "--", "--server", "--config", "/data/server.cfg"]
```

`docker run -d --name ventisca -p 7777:7777/udp -v /srv/ventisca-data:/data --restart unless-stopped ventisca:latest`. El binario oficial solo depende de glibc (`ldd`: libc, libm, libdl, libpthread, librt).

### 16.5 Admin (`admin_socket.gd`, `admin_commands.gd`, `server/admin.sh`)

`TCPServer` en `127.0.0.1:7778`, protocolo de líneas, primera línea = token. Comandos (también por chat con `/` para `admin_tokens`): `status`, `players`, `save`, `save-and-quit`, `kick <name>`, `ban <name> [motivo]`, `unban`, `time <h>`, `day <n>`, `weather clear|blizzard|great_blizzard|thaw`, `give <name> <item> [n]`, `tp <name> <x> <z>|<poi>`, `rule <key> <value>` (pvp, friendly_fire, …), `spawn zombie <kind> [n]`, `horde <kind> <poi>`, `stats` (tick ms, entidades, kB/s), `backup`. Logs: stdout → journald; eventos `[EVT]`; `user://logs/`.

### 16.6 Recursos objetivo del servidor (4 jugadores)

Tick 60 Hz con **≤ 8 ms** de CPU en el peor caso (`perf_horde`); ≤ 150 L0 + 400 L1 + 2 000 L3; ≤ 36 chunks calientes; ≤ 40 rutas/tick; ≤ 60 % de un núcleo; RAM ≤ 500 MB; salida ≤ 120 kB/s. VPS 2 vCPU / 4 GB (≈ 6–10 €/mes) o PC propio.

---

## 17. Cliente

### 17.1 Presupuestos (Forward+, 1080p)

Frame ≤ 16.6 ms (objetivo interno 12); draw calls **≤ 1 500 máx. con sombras / típico 400–800** (`RENDER_TOTAL_DRAW_CALLS_IN_FRAME`); tris ≤ 1.5 M (típico 300–600 k); objetos ≤ 2 500; luces con sombra 1 direccional + ≤ 6 omni/spot (`compat` ≤ 3); esqueletos activos ≤ 64; partículas ≤ 12 000 GPU; GDScript `_process` + `_physics_process` ≤ 3 ms; streaming ≤ 2 ms; RAM ≤ 2.5 GB, VRAM ≤ 1.5 GB. `compat`: draw calls ≤ 1 000, luces reales ≤ 8 por malla (farolas emisivas).

### 17.2 `Quality` (presets)

`alto`: Forward+, `FogVolume`, PCSS, SSAO, sombras 4096/2 splits, MSAA 2×, 12 000 partículas. `medio`: sin volumétrica ni SSAO. `compat`: `gl_compatibility` (requiere reinicio; se guarda en `user://settings.cfg` y se pasa `--rendering-method`), niebla exponencial, PCF, 4 000 partículas, luces limitadas. Autodetección: `RenderingServer.get_video_adapter_type() == INTEGRATED` y nombre antiguo → `compat`.

### 17.3 Input map

El del slice + `crouch` (Ctrl / R3), `aim` (RMB / stick der.), `fire` (= `interact_click` con arma), `reload` (R / X), `shove` (Espacio / B), `throw` (G / LB+RT), `ping` (botón central / RB), `chat` (Enter), `map` (M / Back), `wardrobe` (C), `backpack` (I), `skills` (K), `vehicle_horn` (H / Y), `vehicle_lights` (L / LB), `give_up` (X mantenido / Y). `Escape` resuelve cancelar > pausa local.

### 17.4 Capas de física

| # | Nombre | Miembros |
|---|---|---|
| 1 | `world` | terreno, `Col*` de edificios/POIs, props estáticos, estructuras |
| 2 | `player` | jugadores (máscara entre jugadores solo con `pvp`) |
| 3 | `animals` | lobos, ciervos (L0) |
| 4 | `interactable` | `InteractableComponent`, pickups, drops |
| 5 | `heat` | `HeatZone` |
| 6 | `shelter` | volúmenes interiores de edificios/vehículos |
| 7 | `placement_blocker` | árboles, rocas, estructuras, mobiliario |
| 8 | `zombies` | cuerpos L0 (colisionan con world/player/vehicles, no entre sí) |
| 9 | `vehicles` | `RigidBody3D` de vehículos |
| 10 | `projectiles` | flechas/lanzables |
| 11 | `trail_stamp` | capa de render de los sellos de huellas (viewport) |
| 12 | `cutaway` | (stencil opcional) |

---

## 18. Tests

| Script | Qué | Puerta |
|---|---|---|
| `tests/run_all.sh` | Encadena todo lo siguiente; sale ≠ 0 si algo falla. | cada hito |
| `tests/run_smoke.sh` → `smoke_test.gd` | Arranca `game.tscn` (offline o servidor hijo), reproduce el guion del slice ampliado por hito (zombis, disparo, congelado, puerta, vehículo, hielo, base…). `grep -E "SCRIPT ERROR|ERROR: |FAIL:"`. | M0+ |
| `tests/net/run_net_test.sh --clients N --duration S --scenario X` | Lanza 1 servidor + N clientes headless (`--client --name X --scenario X`), cada proceso imprime `RESULT OK/FAIL`; escenarios: `basic`, `shared_world`, `zombies`, `restart`, `hitscan` (con `net_sim`), `village`, `vehicle`, `base`, `hospital`, `great_blizzard`, `campaign`. *Soak* de 90 s incluido. | M1+ |
| `tests/run_determinism.sh` → `determinism.gd` | Dos procesos generan 50 chunks (terreno, superficie, scatter, aldea) y comparan hashes. | M3+ |
| `tests/run_perf.sh` → `perf_probe/perf_walk/perf_drive/perf_horde` | Escenas y rutas fijas; escriben `tests/perf/last.json`; se comparan con `perf_budgets.json` (draw calls, objetos, ms de frame p50/p99, tirones > 33 ms, ms de tick del servidor, kB/s). En CI (xvfb + `compat`) solo se exigen los presupuestos de CPU/streaming; los de GPU se validan en la máquina del usuario. | M0+ |
| `tests/unit/*.gd` | Funciones puras: térmica, botín, habilidades, director, paquetes (pack/unpack), altura, daño, persistencia (3 backends). `SceneTree` + `assert`‑helpers, sin framework. | M5+ |
| `tests/run_screenshots.sh` | xvfb + `compat`, presets por región/hora; revisión visual. | M0+ |
| `blender/verify_*.py` + `tests/inspect_models.gd` | Contrato de arte. | cada hito de arte |
| `--net-sim` | Cola de envío con latencia/jitter/pérdida configurables (`net_sim.gd`), usada por `hitscan` y `vehicle`. | M5+ |

Regla: **un hito no se cierra con un test en rojo**; si un presupuesto no se cumple, se recorta alcance (menos edificios, menos zombis), no el test.

---

## 19. Convenciones de código

- GDScript tipado, `class_name` en scripts reutilizables, `snake_case` para ficheros/funciones/variables, `PascalCase` para clases y nodos, `SCREAMING_CASE` para constantes; señales en pasado (`tree_felled`), RPC `request_*` (cliente→servidor) y `*_ok/_denied/_event` (servidor→cliente).
- `@rpc` siempre con los cuatro argumentos explícitos; toda función `@rpc any_peer` empieza con `if not multiplayer.is_server(): return` y valida al remitente.
- Nada de `get_node("../..")`; comunicación por `Events` o por referencias inyectadas (`setup(...)`).
- `Net.is_server` se consulta una vez en `_ready` y se desactiva lo que no toque (`set_process(false)`).
- Generadores puros: sin `SceneTree`, sin `randi()` global, `Array` ordenados, `PackedXArray` para datos masivos.
- Constantes de balance solo en `balance.gd` / `data/*.gd`; textos de UI solo en `scripts/ui/strings.gd` (español).
- Cada sistema nuevo llega con: script, escena (si aplica), entrada en este documento, test.
- Rendimiento: medir con `Performance.get_monitor` y `Time.get_ticks_usec()`; nunca optimizar sin número.

---

## 20. Mapa de migración desde el slice (fichero a fichero)

| Slice | Acción | Destino v2 | Hito |
|---|---|---|---|
| `project.godot` | editar | + Jolt, capas 8–12, acciones nuevas, autoloads v2 (`Net`, `Identity`, `Quality`, `GameFlow`), `flush_stdout_on_print` | M0/M1 |
| `scripts/autoload/events.gd` | dividir | señales de simulación (con `player`) / presentación | M1 |
| `scripts/autoload/game_state.gd` | partir | `scripts/net/shared/world_state.gd` (replicado) + `scripts/autoload/game_flow.gd` (cliente) | M1 |
| `scripts/autoload/inventory.gd` | mover | `scripts/player/inventory_component.gd` (servidor) + espejo `InventorySync` | M1 |
| `scripts/autoload/quest_manager.gd` + `data/quests.gd` | mover/ampliar | `scripts/systems/objectives.gd` + `ObjectivesComponent` (tablón) | M1, M10 |
| `scripts/autoload/assets.gd` + `data/placeholders.gd` | ampliar | sustitución `palette_vcol` → material compartido; placeholders de personajes con `Skeleton3D` mínimo; anclas v2 | M0, M2 |
| `scripts/autoload/audio_manager.gd` | mantener | stub en servidor; eventos v2 | M10 |
| `scripts/player/player.gd` | partir | `player.gd` (raíz) + `player_sim.gd` + `player_input.gd` + `player_net.gd` + `player_view.gd` + `player_state.gd` | M1 |
| `scripts/player/player_stats.gd` | mover | `stats_component.gd` (servidor) + `systems/thermal.gd` | M1, M8 |
| `scripts/player/player_animator.gd` | retirar | `character_visual.tscn` + `AnimationTree` | M2 |
| `scripts/player/tool_holder.gd` | reescribir | `BoneAttachment3D` en `RightHandSocket` + `weapon_state` | M2 |
| `scripts/player/interactor.gd` | adaptar | hover local + `request_interact(wid)`; *auto‑walk* predicho | M2 |
| `scripts/player/placement_controller.gd` | adaptar | fantasma local + `request_place`; validación compartida | M2 |
| `scripts/player/camera_rig.gd` | ampliar | inclinación hacia el cursor; `far = 70`; solo cliente | M0, M5 |
| `scripts/player/footprint_emitter.gd` | reescribir | `trail_emitter.gd` → `SnowTrailMap.stamp` (todos los personajes) | M3 |
| `scripts/components/interactable.gd` | ampliar | `wid`, `actions[]`, `server_interact` en el dueño | M2 |
| `scripts/components/storage.gd` | mover | `objects/container.gd` (servidor, exclusión, botín, persistencia) | M2, M5 |
| `scripts/components/health.gd` | retirar | `DamageResolver` + `hp` en SoA/estado | M4 |
| `scripts/components/fuel_burner.gd`, `heat_zone.gd`, `hover_ring.gd` | mantener | (servidor / cliente según toque) | — |
| `scripts/world/world.gd` | reescribir | `world_streamer.gd` + `game.tscn/World`; el claro pasa a `poi/hunter_clearing.tscn` con sello | M3 |
| `scripts/world/terrain.gd` | partir | `terrain/height_function.gd` (puro) + `terrain/terrain_chunk.gd` | M3 |
| `scripts/world/scatter.gd` | reescribir | `scatter/scatter_gen.gd` + `multimesh_chunk.gd` + `scatter_index.gd` | M3 |
| `scripts/world/bounds.gd` | reescribir | borde del mundo (montaña + muro invisible a ±1 500) | M3 |
| `scripts/world/region_tracker.gd` | reescribir | por eventos de chunk + `poi_registry` | M3 |
| `scripts/world/day_night.gd`, `weather.gd` | partir | decisión en servidor (`weather.gd`), render en cliente (`day_night.gd`, `blizzard_fog`) | M1, M3 |
| `scripts/world/respawner.gd` | mover | servidor; crea `drops` | M2 |
| `scripts/world/tree.gd`, `rock.gd`, `berry_bush.gd`, `pickup.gd`, `campfire.gd`, `wood_stove.gd`, `cabinet.gd`, `stump.gd`, `fence.gd`, `signpost.gd`, `lantern.gd`, `wall_clock.gd`, `furniture.gd`, `truck.gd` | mover a `world/objects/` | `server_interact` + `wid`; `truck.gd` → resto estático con `container.gd` (M2) y `vehicles/pickup.tscn` (M7) | M2, M7 |
| `scripts/world/cabin.gd`, `cutaway.gd`, `a_frame.gd` | reemplazar | `building.gd` + `cutaway_manager.gd`; la casa del cazador y la cabaña en A pasan a plantillas del kit (`house_hunter`, `a_frame`) | M6a |
| `scripts/world/wolf_spawner.gd`, `deer_spawner.gd` | reemplazar | `population_manager.gd` (fauna por bioma) | M4/M9b |
| `scripts/actors/wolf.gd`, `deer.gd`, `steering.gd`, `quadruped_animator.gd` | mantener hasta M9b | `ai/animal_brain.gd` + esqueleto cuadrúpedo | M9b |
| `scripts/effects/footprints.gd`, `snowfall.gd` | reescribir | `snow_trails`, `GPUParticles3D` | M0, M3 |
| `scripts/ui/*` | mantener y ampliar | leen espejos y `WorldState`; paneles nuevos (§17) | M1+ |
| `scripts/ui/quest_panel.gd` | renombrar | `board_panel.gd` (tablón) | M10 |
| `scripts/main/game.gd` | reescribir | doble sabor | M1 |
| `scripts/data/balance.gd`, `items.gd`, `recipes.gd`, `regions.gd` | ampliar | valores del GDD v2; `regions.gd` → `poi_registry.gd` | M1–M8 |
| `scenes/world/world.tscn` | retirar | `game.tscn/World` + chunks | M3 |
| `scenes/world/cabin.tscn`, `a_frame_cabin.tscn` | retirar | plantillas del kit | M6a |
| `scenes/world/pickup_truck.tscn` | retirar | `vehicles/pickup.tscn` + resto estático | M7 |
| `scenes/effects/footprints.tscn` | retirar | `snow_trails.tscn` | M3 |
| `tests/smoke_test.gd`, `smoke_steps.gd` | mantener y ampliar | offline = servidor local; pasos por hito | M0+ |
| `tests/screenshot.gd` | ampliar | presets por región | M3+ |
| `tests/inspect_models.gd` | ampliar | esqueletos, animaciones, grupos de corte, anclas de vehículo | M0+ |
| `prototypes/netpoc/*` | fuente de M1 | `Net`, auth, spawner, `player_net` | M1 |
| `prototypes/animpoc/*` | fuente del rig | `blender/lib/rig.py`, `anim.py`, `humanoid_bonemap.tres`, plantillas `.import`, `AnimationTree` | M0–M2 |
