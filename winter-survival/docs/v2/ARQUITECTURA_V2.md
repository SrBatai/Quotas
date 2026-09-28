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

*M3*: implementado en `NetWorld._update_interest` (radio `WorldConst.INTEREST_RADIUS` = 1) + `PlayerManager` (poses por `sees`) + `actor_interest.gd` (lobos/ciervos); ver §8.9.

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
- **M2 (`scenes/player/character_visual.tscn` + `character_visual.gd`)**: `Model` (uno de `chars/survivor_{red,blue,green,mustard}.glb` según `Player.outfit`, asignado por el servidor al menos usado; `player.glb` rígido como sustituto si falta) + `AnimationPlayer` (`root_node` = raíz del glb para resolver `%GeneralSkeleton:Hueso`; librería `loco` de `anims/humanoid_loco.glb` + `Act_Chop` generado desde la pose de reposo) + `AnimationTree` construido en código: `Transition "loco"` (Idle | Cold | Walk | Run | CrouchIdle | CrouchWalk, *xfade* 0.12 s) con **`TimeScale` = velocidad real / autorada** (2.2 / 6.0 / 1.3) en el ciclo dominante en lugar de un `BlendSpace1D` (mezclar dos ciclos desliza los pies 21–75 %; el ciclo escalado desliza 1 %), → `Blend2 "upper"` (filtro de torso, capa de clase de arma de M4/M5, peso 0) → `OneShot "action"` (filtro de torso). El árbol se avanza **a mano** (`ANIMATION_CALLBACK_MODE_PROCESS_MANUAL`, `CharacterVisual.advance(dt)`) desde `PlayerView._physics_process`, que antes mide la **velocidad de suelo real de ese mismo tick** (desplazamiento, no `velocity`: en pendiente o contra un obstáculo `velocity` miente y los pies patinan) y fija el `TimeScale`; los modificadores del esqueleto van en el *callback* de física. `LookAtModifier3D` (Head, eje +Z, límites 75°/35°) bajo `GeneralSkeleton` apunta a `AimTarget` = `aim_point`; `BoneAttachment3D` externos en `RightHandSocket` (herramientas, transformación identidad: mango +Y = pulgar, filo +Z = nudillos) y `HeadSocket` (aliento). Remotos: velocidad del búfer de interpolación suavizada; `crouching`, `running`, `cold` (nuevo, ON_CHANGE) y `outfit` (nuevo) viajan en `ServerSync`. `get_bone_global_pose` devuelve la pose **antes** de los modificadores (el esqueleto la restaura tras actualizar la piel): lo que ve el jugador se lee en los `BoneAttachment3D`.
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

### 8.9 Nota de implementación M3 (vinculante hasta que se revise)

Sustituye lo anterior de §8.1–§8.7 donde lo contradiga.

- **Rejilla** (`scripts/world/world_const.gd`): 48 × 48 chunks de 64 m con el **chunk 24 centrado en el origen** (convención de M2: el claro sigue siendo los chunks 23–25), así que la rejilla va de −1568 a +1504 m; el plano macro cubre ±1536 m, el muro jugable está en ±1450 m (`Bounds`) y desde 1152 m la niebla del borde crece hasta ×4 (`DayNight.fog_density_scale`). `WorldConst.hash64(a…e)` = *splitmix64* encadenado (63 bits, siempre ≥ 0) da los `wid` procedurales y el RNG sin estado por celda; nada usa `randi()` global ni el orden de un `Dictionary`.
- **Altura** (`scripts/world/terrain/height_function.gd`, pura, segura desde hilos): ruido del slice (amplitud 0.3 dentro del claro) → sellos del slice (lago pequeño, pads del claro: **el claro es idéntico al de M2**) + altura macro relativa (B‑spline cúbica sobre una rejilla global de 4 m, exactamente 0 cerca del claro) → Lago de las Ánimas (unión suave de 4 discos por SDF, hielo **plano a −5 m**, seguro hasta M8) → pads de POI (`data/world/poi_registry.gd`) → lechos de carretera (perfil longitudinal suavizado, arcenes de 7 m). La altura del mundo es la **bilineal de las muestras enteras de 1 m**, que es justo lo que dibujan la malla y el `HeightMapShape3D`. `surface_at` → `CUSTOM0` RGBA8: r asfalto, g hielo, b pista, a distancia lateral al eje de la carretera (128 + 16 × m; `terrain.gdshader` pinta las roderas con ella).
- **Plano macro v0** (`tools/gen_macro_map.gd` → `data/world/macro_map.png` 384² a 8 m/px + `macro_roads.json`): R/A = altura de 16 bits sobre 160 m (relativa a `H0_CODE`, pintada plana alrededor del claro), G = bioma × 40, B = densidad de scatter. Se importa como **Image**: el importador de texturas corrompe los canales empaquetados con `fix_alpha_border`. Las regiones salen por chunk del mapa ASCII 24 × 24 de PLAN §4.2 (`PoiRegistry.region_of_chunk`) y alimentan `RegionTracker`.
- **Generación** (`scripts/world/streaming/chunk_job.gd`, `WorkerThreadPool`, prioridad baja): 67² alturas, scatter propio y oclusores de los vecinos, región, malla de 65² vértices con normales, tinte, AO horneada, `CUSTOM0` (4 cuadrantes de 33² con un índice compartido) y búferes de MultiMesh. Tarda 20–35 ms por chunk en un hilo, nunca en el principal.
- **Instanciación** (`world_chunk.gd`): pasos cortos (deltas → colisión → malla por cuadrante → formas, 24 por paso, en cuerpos fuera del árbol porque Jolt reconstruye el compuesto en cada `add_shape` dentro del árbol, O(n²) → MultiMesh, uno por paso → nodos → hecho). `WorldStreamer._instantiate` estima cada paso con una EMA y deja para el frame siguiente el que no cabe en `STREAM_BUDGET_USEC` (2 ms) con 0.25 ms de margen. La descarga también es incremental: primero se oculta, luego se liberan nodos y datos a trozos dentro del mismo presupuesto.
- **Anillos**: cliente = anillo 1 completo + anillo 2 precargado alrededor del jugador local, adelantado un chunk si |v| > 8 m/s; se descarga con un chunk de histéresis. `ensure_loaded` construye de forma síncrona (aparición, `/tp`). Servidor = unión de los anillos de todos los jugadores (caliente r1, tibio r2), sin mallas; un chunk sin jugador a ≤ 3 chunks durante 60 s **hiberna** (`NetWorld.hibernate_chunk`: guarda su `ChunkDelta` y despawnea estructuras y drops, que `wake_chunk` restaura).
- **Scatter** (`scatter/scatter_gen.gd`, `scatter_catalog.gd`): celdas globales sin estado (árboles 4 m, rocas y pequeños 8 m, troncos y nodos 16 m) con `hash64(seed, gen, ix, iz)`, así que una celda nunca depende de qué chunk la genera. El claro es un **port exacto** del scatter del slice (mismo orden de RNG, 723 entradas). Catálogo de 28 variantes, con colisión, talado y AO leídos de `assets/models/{vegetation,props}/manifest.json` cuando existen. No se pone `bush_b` a < 24 m de un arbusto de bayas. Cliente: un `MultiMeshInstance3D` por bloque de 32 m × variante. Los talables tienen una forma por árbol (el `scatter_index` es `entry_of_hit(body, shape)`) y un *pick* de copa por rayo‑cilindro. `World.materialize_wid` / `WorldRegistry.resolve(wid)` convierten la instancia en un `ChoppableTree` real **solo al golpearla**: la instancia se oculta y el árbol vuelve al MultiMesh si nadie lo toca en 6 s. Un talado (`felled` en `ChunkDelta.objects`) se aplica al generar: queda un tocón y un disco de oclusión.
- **POIs del bosque**: `cabin_small` ×4, `lookout_tower` y `campsite_remains` ×6 van sobre pads, como nodos del chunk con `PoiCutaway` (`scripts/world/poi_cutaway.gd`): corte v2 por `cut_group` (muro frontal → `_Stub` y sus `Door_n`/`Window_n` ocultos; tejado y plantas superiores ocultos). Es provisional hasta el `CutawayManager` de M6a.
- **Red**: `NET_PROTOCOL` 2. La semilla del mundo viaja en el *nonce* de autenticación (16 B aleatorios + s64, todo bajo el HMAC) y el cliente genera el mismo mundo. Interés = 3 × 3 chunks por peer, recalculado cada 0.5 s: al entrar un chunk llega su `chunk_delta_snapshot` y después `_interest_update(entered, left)`; los eventos `_event(wid)` se enrutan por interés y el cliente olvida los chunks que salen. Las poses se filtran con `NetWorld.sees(peer, pos)`, y el paquete lleva ahora una base (i32, i16, i32) + desplazamientos i16, porque con i16 absolutos saturaba a ±327 m. La pose de los actores pasa a 19/19/16/10 bits. **Lección**: el filtro de visibilidad de un `MultiplayerSynchronizer` debe devolver `false` para el peer 0; si no, Godot toma el atajo "visible para todos" y nunca despawnea.
- **Huellas**: se mantiene el `Footprints` de G1 (mapa de rastro en espacio mundo, reproyectado cada 8 m) en lugar del `SubViewport` de §14. Sigue al jugador de chunk en chunk porque todos los chunks comparten `terrain.gdshader`. `snow_amount` no cambia.
- **Rendimiento** (`tests/perf_walk.gd`, ruta de 2.26 km a 25 m/s). `--cpu` es headless con la ruta visual forzada y es la puerta de los 2 ms/frame (`perf_budgets.json` `perf_walk_cpu`): p99 ≤ 2 ms, p99.9 ≤ 2.5 ms, ≤ 1.5 % de frames por encima, máx. ≤ 8 ms y 0 frames > 33 ms por streaming. Los picos aislados de 4–6 ms caen en fases triviales distintas en cada ejecución, así que son fallos de página de la VM o expropiación, no código. El modo render (xvfb + Compatibility en llvmpipe, `LP_NUM_THREADS=2`) mide suelo y memoria: con GPU por software cada frame dura 250–350 ms y el rasterizador compite con el hilo principal, así que las cifras de frame de ese modo son solo informativas. Medido en una VM de 4 núcleos con `run_all.sh`:
  - `--cpu`: streaming p50 0.03 ms, p99 1.84–1.90 ms, p99.9 1.97–2.02 ms, máx. 4.6–6 ms; 0.07–0.12 % de frames por encima de 2 ms; 0 tirones por streaming; RSS 236 MB.
  - Render: RSS máx. 610–662 MB (límite 2.5 GB); el suelo nunca falta; se generan 199 chunks, con 25–28 ms de media en hilos.
- **Arranque**: `World._warm_assets` carga las 28 variantes de scatter y los modelos de los POIs antes del primer chunk. Tarda 45 ms en Compatibility y 18 s en Forward+ sobre lavapipe, porque ahí Godot precompila los *pipelines* de cada superficie con LLVM; en una GPU real es la caché de *pipelines* y evita tirones al entrar en un bioma nuevo.
- **CI** (sin tocar el *workflow*; los comandos se pasan al coordinador): `tests/run_determinism.sh`, `tests/net/run_net_test.sh --clients 2 --duration 30 --soak 45 --scenario far --port 7797`, `tests/run_perf_walk.sh --cpu` y, con xvfb, `tests/run_perf_walk.sh`.
- **Web** (plantilla *nothreads*): `WorldStreamer.threads_ok()` es falso, así que la generación corre en el hilo principal, un chunk por refresco (0.2 s). Es funcional pero cada chunk nuevo cuesta un tirón de 25–60 ms (`perf_walk.gd --cpu --nothreads`, informativo). Para la demo web de un jugador se acepta; si molesta, se trocea `ChunkJob.run` en fases por frame.

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

### 10.7 Nota de implementación M4 (vinculante hasta que se revise)

Sustituye lo anterior de §10.1–§10.6 y §11 donde lo contradiga.

#### Navmesh

`scripts/world/nav/nav_baker.gd`, solo en el servidor. **No** usa `parse_source_geometry_data`, que exige el hilo
principal y recorre nodos. Construye la geometría fuente en código:

- el terreno: las muestras de 1 m del chunk más 3 m alrededor (`HeightFunction.sample_block`, pura);
- los colisionadores de scatter del chunk y de sus vecinos, como *projected obstructions*;
- los nodos de los grupos `nav_static` (cabaña, A‑frame, camioneta, vallas, poste) y `poi_prop`, como caras (cajas,
  convexos, trimesh) o como obstrucciones (formas redondas).

El hilo principal solo recoge arrays (máx. medido ≈ 4 ms). El horneado (`bake_from_source_geometry_data`) corre en
`WorkerThreadPool` y tarda 20–85 ms por chunk. Se hornea **de uno en uno**, solo cuando el streamer está ocioso (sin
chunks generándose ni montándose) y nunca alrededor de un jugador que va a velocidad de vehículo (> 8 m/s,
`FAST_SPEED`): ahí los zombis no pueden seguirle, y el anillo se hornea cuando frena.

Parámetros: `cell_size` 0.25 (web 0.5), `cell_height` 0.2, `agent_radius` 0.5 (el 0.4 del spec redondeado a 2
celdas), `max_climb` 0.4, `max_slope` 45° y `edge_max_error` 1.0.

**Qué chunks se hornean.** Solo los del anillo de cada jugador: centro del chunk a ≤ 96 m (`BAKE_RADIUS`); los
zombis L0 viven a menos de 40 m. El resto de chunks cargados esperan en la cola.

**Costuras entre chunks.**

- *Borde*: `border_size` = radio + 3 celdas (1.25 m) y `filter_baking_aabb` = el chunk crecido por ese borde,
  porque Godot deja el borde no navegable *dentro* del AABB. El suelo del AABB cae en la retícula global de
  `cell_height`. Así los polígonos llegan justo al borde del chunk.
- *Unión exacta*: `edge_connection_margin` **está desactivado** (`map_set_use_edge_connections(false)`), porque
  Godot compara cada arista libre del mapa con todas las demás, y cada agujero de un árbol está rodeado de aristas
  libres. Con 9 chunks eso eran 150–230 ms por reconstrucción del mapa, y el mapa se reconstruye en cada cambio de
  región: perf walk pasaba de p99.9 2.0 a 5.5 ms. En su lugar, cada malla horneada se guarda editable (`NavTile`).
  Al aplicarla, cada costura con un vecino ya horneado recibe la **unión de los vértices de los dos lados**: los
  intermedios se insertan (colineales) en las aristas de la costura, y los coincidentes se copian bit a bit.
  Después se actualizan las dos regiones. Godot las une por clave exacta de arista y la reconstrucción del mapa
  baja a ≈ 1 ms. El cosido cuesta ≤ 0.4 ms.
- *Primera versión de M4*: con AABB = chunk y borde = radio quedaba un hueco de 1 m en cada costura. Ninguna ruta la
  cruzaba, y Godot imprimía "It's not expect to not find the most reachable polygons" en cada búsqueda acotada
  hacia un objetivo del otro lado.
- El smoke comprueba una ruta que cruza la costura x = −32.

**Otros detalles.**

- Al talar un árbol, su chunk se rehornea tras un *cooldown* de 2 s.
- Las regiones de los chunks descargados se liberan en `_process`, nunca dentro del callback del streamer.
- En la web (sin hilos) se hornea con celdas de 0.5 m, de forma síncrona, un chunk cada 0.3 s (20–55 ms cada uno).
- Las regiones se aplican de forma asíncrona (*region async iterations*): los tests esperan a que el mapa las
  recoja antes de pedir una ruta.

#### Consultas de ruta

`nav_query_queue.gd` usa `NavigationServer3D.query_path` con `path_search_max_polygons` 1200 y
`path_search_max_distance` 90 m. Un objetivo a más de 63 m se acorta a un punto intermedio.

Cada consulta cuesta **1–2 ms** en un mapa de 25 chunks (~29 k polígonos) y ≈ 1 ms en el anillo de 9. Por eso:

- como mucho 40 consultas **y** 1.5 ms por tick;
- las rutas se comparten entre zombis cuyo inicio está a ≤ 6 m y cuya meta está a ≤ 2 m, durante < 1 s;
- **dirección directa**: si un rayo a la altura de la rodilla (capa mundo) hasta el objetivo está libre y el
  objetivo está a ≤ 14 m, el zombi va recto (se recomprueba cada 0.35 s). Solo pide ruta si hay algo en medio.

No hay RVO: los zombis se separan por *spatial hash* (0.75 m).

#### `ZombieSystem`

`scripts/ai/zombie_system.gd` guarda los datos en arrays (SoA, con los campos de §10.3 más la velocidad, la meta, la
memoria, los temporizadores y el historial de posiciones para el rebobinado).

- **L0**: un `CharacterBody3D` del pool (≤ 150; web 40) en la capa 8 `zombies`, con máscara solo de mundo. Los
  jugadores no chocan con los zombis, así que la predicción del cliente sigue siendo exacta. A más de 22 m, un L0
  piensa a 5 Hz y se mueve a 15 Hz; más cerca, 10 Hz y 30 Hz.
- **L1**: un registro sin cuerpo que piensa a 2 Hz y sigue su ruta con la altura de la función de terreno.
- **LOD**: se recalcula a 2 Hz y solo se ordena si hay más candidatos que cuerpos.
- **Estados**: los de §10.3. `GRAB`, `SCREAM`, `EAT` y `SLEEP` están reservados.
- **Sentidos**:
  - vista en cono de 120° (25 / 12 / 6 m de día / noche / ventisca), con probabilidad = distancia × visibilidad
    (luz, agachado);
  - visión periférica de 3 m;
  - oído: `SoundEvents` (vida 0.6 s) más los pasos (2 / 6 / 14 m);
  - olfato de 8 m hacia un jugador derribado o con < 25 PV;
  - memoria de 20 s.
- **Congelación**: exterior de noche con 300 s sin estímulo. El congelado no tiene cuerpo. Despierta por ruido
  (`on_noise`), proximidad o calor, con 1.5 s de `Zom_Wake`.
- **Ataque**: la ventana de daño es el `hit_start` del clip (`Zom_Attack_A` 0.34 s, `Zom_Attack_B` 0.40 s,
  `Zom_Crawl_Grab` 0.30 s; `AnimEvents` lee `data/anim_events.json` y quita el `-loop` de las claves). Alcance
  + 0.3 m, cono de 60° + 15°. Cada mordisco a un derribado le quita 5 s de sangrado.

#### Replicación

`scripts/ai/zombie_net.gd` envía paquetes crudos con `SceneMultiplayer.send_bytes`, sin RPC:

- **ZSNAP** (tipo 10, no fiable, canal 2): una base por chunk y **9 B por zombi**: u16 id, x/z de 12 bits sobre
  64 m, i16 y en cm, u8 yaw y u8 `estado | flags << 5`.
- **ZREL** (tipo 11, fiable, canal 1), con cuatro tipos de registro:
  - `ENTER`: kind, variante, posición f32, yaw, PV;
  - `LEAVE`;
  - `EVENT`: hit, crit, die (bit 0 = silencio, bit 1 = cabeza reventada), wake, attack (variante), stagger,
    knock, cloud, execute;
  - `FX`: ruido, sangre, nube, jugador herido.

El interés de cada peer son sus 3 × 3 chunks; se recalcula por turnos, un peer por llamada. Las instantáneas van en
bandas (≤ 30 m cada 4 ticks, ≤ 60 m cada 6 y el resto cada 15), con un fotograma completo por chunk cada 1 s, y cada
paquete ocupa ≤ 1 200 B. Offline, los mismos bytes llegan al `ZombieClient` por llamada directa. `NET_PROTOCOL` 3,
`GAME_VERSION` 0.6.0-m4.

#### Cliente

`zombie_client.gd` + `zombie_view.gd`: buffer de instantáneas e interpolación con un retardo adaptativo de
0.1–0.3 s. Pool de 48 vistas (web 24, offline sin pantalla 16, cliente sin pantalla 0).

- **Modelo**: `zombies/zombie_<kind>_<nn>.glb` (24 caminantes). Los congelados usan `zombie_frozen_NN`, con la
  malla `Ice` visible solo mientras están congelados o despertando.
- **`AnimationTree`**:
  - Transition de locomoción: Idle A/B, Walk (Shamble A–D según la variante), Investigate, Run, Tired, Crawl,
    Heavy, Frozen, Dead (A/B o `Crawl_Death`; una vista que recoge un zombi ya muerto salta al final del clip) y
    Knocked. Lleva `TimeScale` = v_real / v_autorada (1.2, 5.5, 3.0, 1.0, 0.9).
  - OneShot de torso: `Alert` al empezar a perseguir.
  - OneShot de cuerpo entero: los ataques (el zombi se para), `Wake`, `Stagger`, `GetUp` y `Bloat_Pop`.
  - `Zom_Hit` aditivo (Add2 a 1, reiniciado con TimeSeek).
- Sin clips `Gen_*` si la librería está completa.
- **LOD de animación**: cada frame a < 30 m, 15 Hz a < 60 m, congelada más lejos.
- **Muerte**: sin ragdoll; clip de muerte y pose final.
- **Gore‑lite**: un crítico que mata (salvo con cuchillo) o un pisotón escalan el hueso `Head` a 0.001 y lanzan
  `gore/head_fragments` desde `HeadSocket`, con balística propia durante 12 s.
- **Sangre**: `gore/blood_splat_a/b/c` orientadas según el golpe, durante 120 s.

#### Población y director

`population_manager.gd` y `director.gd`. Presupuesto de zombis:

| Momento | Zombis |
|---|---|
| Día 1, de día / de noche | 0 / 3 |
| Día 2, de día / de noche | 2 / 5 |
| Día 3 en adelante | 12 × rampa (×1.3 de noche) |

Ese presupuesto se multiplica por (1 + 0.5 (n − 1)) con n jugadores, ×0.5 en ventisca y ×0.6 en la web, con un
tope de 60. El director pasa por las fases acumulación / pico / alivio y lanza eventos (horda, despertar
congelados). Los zombis aparecen a 35–55 m, fuera de la vista. No hay L2 `Horde` persistente ni zonas fusionadas.

#### Combate

`scripts/combat/melee.gd`, `damage_resolver.gd` y `data/weapons.gd`. El cliente envía
`request_melee(mode, yaw, aim_id)`, limitado a 8 por segundo.

**Al recibirla, el servidor valida** que el jugador esté vivo, no derribado, fuera de cadencia y con aguante
(ligero 8, cargado 12 con ≥ 20, empujón 8). Si todo cuadra, el golpe se reproduce en todos los clientes
(`Player.swing_seq`).

**El daño se evalúa después**, pasados `Weapons.hit_delay` segundos (el `hit_start` del clip):

| Golpe | Retraso |
|---|---|
| Una mano | 0.27 s |
| Dos manos | 0.36 s |
| Cargado | 0.06 s tras soltar |
| Empujón | 0.25 s |
| Pisotón | 0.46 s |
| Ejecución | 0.7 s, con la víctima sujeta (`ZombieSystem.hold`) |

En el golpe cargado, el dueño sostiene la pose `hold_start` mientras carga y al soltar salta a `hold_end`; los demás
lo ven desde `hold_end`.

En ese momento se usa la posición del atacante: cono de 110°, alcance del arma + 0.5 m, y cada zombi se prueba en
su posición actual y en la de hace `rewind` = ½ RTT + 100 ms (≤ 150 ms). `Melee.tick()` corre en
`NetWorld._physics_process` y manda el resultado al atacante (`NetWorld.send_melee_result`).

Multiplicadores: crítico ×3, cargado ×1.5, congelado ×1.5 con arma contundente. Cada golpe hace ruido (acierto o
fallo) por `SoundEvents`. La durabilidad baja 1 punto con probabilidad 100/N por acierto y viaja en el espejo de
ranuras de 4 B (u16 id, u8 cantidad, u8 durabilidad). El arma va en `RightHandSocket` con transformación identidad.

`DamageResolver` sigue siendo el único que lee `pvp` y `friendly_fire` (off 0, reduced 0.25, full 1). Con `pvp`
activo, la capa de jugador entra en la máscara de los jugadores. El jugador herido hace `Hit_Front` en la capa
aditiva de todos los clientes (`FX_PLAYER_HIT`).

#### Derribado y muerte

Solo el daño de combate (mordisco, cuerpo a cuerpo) derriba; el frío y el hambre matan directamente.

- **Derribado**: se arrastra a 0.8 m/s y se desangra en 60 s (40 s con frío). El tercer derribo sin descansar
  mata (el contador se reinicia al amanecer hasta que haya camas).
- **Reanimar**: mantener 4 s a ≤ 2.2 m (`request_revive`). Se levanta con 30 PV y queda "Malherido" (×0.85
  durante 300 s).
- **Solo en el servidor**: se levanta por sí mismo una vez al día, a los 20 s.
- **Rendirse**: mantener 3 s.
- **Muerte**: deja un cadáver, que es una estructura `corpse` de `StructureSpawner` guardada en el `ChunkDelta`
  (`structures` + `containers`), con todo el inventario, durante 48 h de juego. El jugador reaparece a los 20 s
  junto a la `Bed` (`World.get_respawn_point`).

#### Rendimiento

Medido con `taskset -c 0,1 tests/run_all.sh` en 2 núcleos de una VM compartida. `perf_horde` es un servidor
dedicado con 4 bots con hacha y 200 caminantes en el claro.

| Medida | Resultado |
|---|---|
| Tick ocupado | p50 5.5 ms (4.9–6.2 entre ejecuciones; presupuesto 8), p99 9.6 ms, máx. 15 ms |
| `ZombieSystem` | p50 2.4 ms, p99 4.8 ms |
| `ZombieNet` | p50 1.3 ms |
| `move_and_slide` de ~110 cuerpos L0 | p50 1.7 ms |
| Rutas | 7.8/s a ≈ 1 ms cada una (peor tick 2 ms) |
| Datos de zombis por bot | 10 kB/s |
| Escenario de red `zombies` (4 clientes, ~94 zombis) | 4.9 kB/s de media por cliente (máx. 6.7; límite 15) |
| `perf_walk --cpu` | streaming p99 1.86 ms, p99.9 2.03 ms, máx. 3.2 ms (igual que M3) |
| Navmesh | reconstrucción del mapa ≈ 1 ms, cosido ≤ 0.4 ms |
| Web, sin hilos (sonda de escritorio con `force_no_threads`) | 9 horneados de 20–55 ms en el hilo principal al arrancar; p99 del frame sin pantalla 10.7 ms; 40 zombis a 0.5 ms por tick |

#### Lecciones

- Un `PackedXArray` guardado en un `Dictionary` o en un `Array` es un valor: hay que leerlo, modificarlo y
  volver a escribirlo.
- Los monitores `TIME_PROCESS` y `TIME_PHYSICS_PROCESS` dan el máximo del último segundo, no el frame actual:
  `perf_horde` mide con sondas (primer `_physics_process` → último `_process`).
- Godot aplica la navmesh de una región de forma asíncrona.

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
| `tests/run_determinism.sh` → `determinism.gd` | Dos procesos generan los mismos 50 chunks, uno por la ruta del servidor (hilo principal, sin visuales) y otro por la del cliente (mallas + MultiMesh en hilos), y comparan hashes: alturas al cm, máscara de superficie, entradas de scatter + `wid`, props de POI y `height_at` en 200 puntos (M3; las aldeas se añaden en M6). | M3+ |
| `tests/run_perf_walk.sh [--cpu]` → `perf_walk.gd` | Ruta fija de 2.26 km a 25 m/s con streaming; `--cpu` (headless) exige el presupuesto de 2 ms/frame; el modo render (xvfb + llvmpipe) exige suelo siempre y RSS ≤ 2.5 GB (§8.9). | M3+ |
| `tests/run_perf_horde.sh` → `perf_horde.gd` | Servidor dedicado (puerto 7817) + 4 bots con hacha + 200 caminantes en el claro, director apagado: tiempo ocupado por tick medido con sondas (primer `_physics_process` → último `_process`); exige la mediana ≤ 8 ms (`perf_budgets.json` `perf_horde`), informa p99, coste de `ZombieSystem`, `ZombieNet`, rutas y kB/s por bot (§10.7). | M4+ |
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

---

## §17.5 Nota de implementación H1 (HUD)

Vinculante hasta que se revise. Implementa la dirección v2 «Susurro» de `docs/research/10_hud_ux.md` §V (con las
reglas de comportamiento del apéndice v1) y sustituye a §17 y a la fila `scripts/ui/*` de §20 donde lo contradigan.

#### Espacio y capas

- `Hud` (`scripts/ui/hud.gd`, bajo el `CanvasLayer` `UI` de `game.gd`) contiene los efectos de pantalla completa
  (`Frost`, `DamageVignette`), la barra de categorías antigua (solo visible con la fabricación abierta) y `Root`.
- `Root` es un espacio de referencia de **1920 × 1080**: se escala con `k = min(w/1920, h/1080) × escala de UI` (80–150 %,
  115 % en Steam Deck), así que la base del proyecto sigue en 1280 × 720 con `canvas_items` y los paneles antiguos no
  cambian. A 16:10 sobra alto y los bloques se anclan a los bordes reales.
- `Safe`: márgenes de 64 / 52 px, más el ajuste «Margen de pantalla» (0–5 %) y el área segura del sistema cuando la
  ventana ocupa la pantalla. En 21:9 o más ancho, los bloques de esquina quedan en una caja 16:9 centrada (ajuste
  «Ancho del HUD»); el carril de borde y el mundo usan el ancho completo.

#### Tokens, tema y fuentes

- `UiTokens`: colores y opacidades (tinta al 92/70/52/32 %, `hair` 38 %, `accent #FFB454`, `cold`, `blood`, `warn`,
  colores de jugador y su variante Okabe–Ito), tamaños, pesos, formas, tiempos de entrada / lectura / salida, curvas
  (seno: entrada `EASE_OUT`, salida `EASE_IN_OUT`, 6 px de desplazamiento como máximo), umbrales y la fórmula del velo
  `α = mix(0.18, 0.45, smoothstep(0.35, 0.80, luma))`. Formatos en español: «84 m», «640 m», «1,4 km», «−18 °C», «2:40».
- `UiStyle`: fuentes Barlow (ExtraLight, Light, Regular, Medium, SemiBold) y Barlow Condensed (Thin, ExtraLight,
  Light, SemiBold) en `assets/fonts/` con su `OFL.txt`; `FontVariation` con `smcp` + `c2sc` (versalitas reales) y `tnum`.
  Un `LabelSettings` **compartido** por estilo y color: cuando el fondo es claro (nieve, ventisca) o con «Texto
  reforzado», `UiStyle.set_flags()` cambia el peso de todos a la vez (Light → Regular).
- Sombra: Godot dibuja la sombra de las etiquetas como un contorno duro. La sombra difusa de las maquetas se aproxima
  con una sombra de 1 px más **4 contornos apilados** (4 / 9 / 16 / 26 px, α 0,12 / 0,07 / 0,045 / 0,025); el mismo
  apilado se usa en `UiStyle.draw_text()` para lo que se dibuja con `_draw()`.
- `Theme`: `assets/ui/susurro_theme.tres`, generado desde los tokens (`tools/gen_hud_theme.gd`): fuente por defecto
  Barlow Light 18, variaciones `LabelWhisper`, `LabelMain`, `LabelNum`, `LabelSmallCaps`, `LabelZoneTitle`, etc., y todos
  los tokens (colores, constantes, tiempos en ms, fórmula del velo) bajo el tipo `Susurro`. Sin `StyleBox` de panel.
- `Scrim`: velo radial (no es una caja) detrás de cada grupo de texto; su α sale de una **estimación de la luminancia**
  del fondo por hora, clima e interior (leer la pantalla cada 0,25 s costaría una copia GPU → CPU). «Fondo del texto:
  Opaco» lo sube al 70 %. Los velos están en el grupo `hud_scrim` y la medida de cobertura los excluye.
- Iconos de línea (1,5 px, rejilla 24) en `assets/icons/line/*.svg`, importados con *mipmaps*.
- Los paneles y menús antiguos (`UiTheme`) usan ya Barlow en lugar de la fuente por defecto con negrita sintética.

#### Visibilidad, entrada y acento

- `HudVisibility`: una máquina de estados por elemento (oculto → apareciendo → visible → fundiéndose) con `poke(id)`
  (tiempo de lectura), `set_hold(id, on)` (mientras dure una condición) e Info. El preajuste (Mínimo / Estándar /
  Completo) y las anulaciones por elemento (`dinámico / siempre / oculto`) se leen de `UiSettings` y se guardan en
  caché. Elementos: `hotbar`, `hotbar.name`, `vitals.{warmth,health,hunger}`, `mission`, `edge`, `hazard`, `clock`,
  `info.missions`.
- Entrada: acción nueva `hud_info` (Tab + D‑pad ↑) y `map` (M + Back). `HudInput` consume `hud_info`: una **pulsación**
  (< 0,22 s) se reenvía como `InputEventAction` de su uso anterior (`toggle_craft` con Tab, `zoom_in` con D‑pad ↑) y
  **mantener** es Info. Con Info abierta, R / Y siguen otra misión. `HudInput.gamepad` elige los glifos.
- `AccentArbiter` (10 Hz): compañero derribado > fuente de calor más cercana con Calor < 30 (fogatas del grupo
  `heat_source`, estufas encendidas) > objetivo seguido. Da el ámbar y el **único** indicador de borde: siempre para
  las dos primeras; para el objetivo, 5 s tras actualizarse o con Info.

#### Componentes (`scripts/ui/hud/`)

| Script | Qué hace |
|---|---|
| `world_layer.gd` | Todo lo anclado al mundo (30 Hz, un solo `CanvasItem`): rombo del objetivo, ✓ al completar, carril de borde (dirección con la guiñada de la cámara y `sin 48°`, deslizado fuera de la barra, las constantes y la línea de misión), calor cercano, compañeros, indicador de derribado, arco de daño (dirección hacia el zombi o lobo más cercano, o `Events.player_hit_from`), arco de aguante y avisos de interacción con anillo de mantener |
| `vitals.gd` | Constantes abajo a la izquierda, solo las que importan; desglose térmico con Info |
| `mission_line.gd`, `mission_list.gd`, `info_block.gd` | Línea «objetivo actualizado», misiones a petición, hora / temperatura / grupo |
| `zone_tracker.gd`, `zone_title.gd` | Entrada en zonas con histéresis y el título cinematográfico |
| `notify_router.gd`, `notify_banner.gd`, `pickup_stack.gd`, `hazard_line.gd` | Avisos: enrutador, aviso central, columna lateral y línea de peligro |
| `team_tracker.gd`, `downed_overlay.gd` | Compañeros (5 Hz; una entrada puede apuntar a un jugador ya liberado hasta el siguiente refresco: se lee con `TeamTracker.player_of()`) y la pantalla propia de derribado |
| `mission_log.gd`, `mission_targets.gd`, `ui_climate.gd` | Modelo de misiones en el cliente, anclas de objetivos y temperaturas mostradas |
| `../map/map_screen.gd`, `../map/map_fog.gd` | Mapa de papel con niebla de guerra y diario (P1) |
| `../hotbar.gd`, `../hud_settings_panel.gd` | Barra rápida v2 y el panel «Interfaz y accesibilidad» del menú de pausa |

#### Datos

- **Misiones** (`scripts/data/missions.gd`): diccionarios de red `{id, kind: main|side|dynamic, title, giver, state,
  tracked, expires_at, steps: [{id, title, hint, count, progress, done, targets}]}`. `QuestComponent.get_state()` añade
  `missions` (el día como misión principal, `Missions.from_day`) y conserva las claves antiguas. `Quests` lleva `id` y
  `targets` por paso; las anclas (`group:stove`, `pickup:madera`, `group:storage`, `zone:<id>`, `pos`) se resuelven en el
  cliente. `MissionLog` compara cada estado con el anterior y emite `Events.objective_updated` (`mission_new`,
  `progress`, `completed`, `mission_done`).
- **Lugares** (`scripts/data/locations.gd`): las zonas pequeñas del claro, `PoiRegistry.REGIONS` y las regiones
  naturales de `PoiRegistry.region_at` (lago, N‑140, Las Cumbres, Pinos Altos, Bosque profundo), ordenadas de más a menos
  específica, con `kind`, `parent`, `danger`, `power` y `temp`. `depth()` da la profundidad firmada en metros y
  `inset()` el margen de entrada (12 m, o la mitad del tamaño en lugares pequeños). La ciudad **Altavega** y cuatro
  distritos están en `Locations.CITY` desactivados: `Locations.enable_city(true, desplazamiento)` o `register()` los
  activan cuando el mundo los tenga.
- **Zonas** (`ZoneTracker`, 4 Hz): el lugar actual se mantiene hasta estar `inset` fuera; uno más específico entra al
  estar `inset` dentro; hace falta 1,5 s estable. Primera visita: tarjeta completa; re‑entrada: el nombre al 60 % (o
  nada en zonas naturales); 90 s por lugar y 20 s entre tarjetas; espera en combate (golpe, golpe dado o zombi
  persiguiendo a < 25 m en los últimos 5 s) y con un P0 (derribado, congelación). El descubrimiento se guarda por semilla
  en `user://hud_discovered.cfg`. `RegionTracker` y `Events.region_changed` siguen existiendo para quien los use.
- **Temperatura** (`UiClimate`): el juego aún no simula la temperatura del aire (M8); el HUD usa la tabla del GDD §4.1
  (−8 °C de día, −18 °C de noche, −10 °C en ventisca, más el ajuste del lugar) como modelo de presentación, y la
  sensación suma ropa, viento, refugio y fuego. La tendencia sale del Calor real.

#### Señales nuevas en `Events`

`location_entered(info)`, `location_left(id)`, `notify_ex(n)`, `mission_state(missions)`,
`objective_updated(mission_id, step_id, what)`, `hazard_changed(kind, state, data)`, `status_changed(status, severity)`,
`player_hit_from(dir, amount)`, `hud_info(active)`. Los avisos antiguos (`Events.notify`) pasan por `NotifyRouter`, que
los clasifica: la ventisca va a la línea de peligro, frío y hambre a las constantes, «Sin aliento» al arco de aguante,
fabricado / comido / estufa a la columna lateral y el resto al aviso central. Lo recogido sale de la diferencia del
espejo de inventario, que funciona también en clientes remotos (allí `item_picked_up` no se emite).

#### Red

Todo el HUD es del cliente. No se ha tocado el servidor: el descubrimiento de zonas y la niebla del mapa son locales
(por semilla); los compartidos por el grupo del apéndice §6.1 y §6.11 quedan para cuando haya perfil de grupo. La
salud de los compañeros no se replica, así que «herido» usa lo que ya viaja en `ServerSync` (`cold`, `speed_mult`).

#### Rendimiento y pruebas

- Lógica del HUD (todos sus `_process` en un momento cargado): ≈ 0,1–0,3 ms por frame en la VM compartida
  (presupuesto 0,5 ms; `tests/hud_steps.gd` lo mide). Los componentes redibujan solo cuando cambia algo; el mundo, a
  30 Hz. Un pase de pantalla completa (escarcha) solo con Calor < 40; sin `BackBufferCopy` ni lectura de pantalla,
  así que funciona igual en Compatibility (web) y Forward+.
- Cobertura medida con el método de §V.5 (`tests/run_hud_coverage.sh`: solo la capa del HUD, sobre negro y blanco,
  cajas tras un cierre de 15 px): reposo **0,08 %** (puerta ≤ 3 %), acción 1,6–2,1 %, título de zona 2,6–2,9 % (según la corrida), ventisca
  2,53 %, Info 5,80 %.
- `tests/hud_steps.gd` (paso 18 del humo; o solo con `tests/hud_test.gd`): tokens, tema y fuentes, escala y áreas
  seguras (16:9, 21:9, 16:10), máquina de visibilidad y preajustes, reposo, barra con mando, constantes y escarcha,
  misiones, histéresis de zonas (zigzag = 0 cambios), jerarquía de Altavega, combate, avisos (prelación, cola, fusión),
  peligros, Info y la pulsación de Tab, acento, carril de borde en 360 direcciones, mapa y presupuesto de CPU.
- Capturas `hud_idle`, `hud_action`, `hud_zone`, `hud_blizzard` y `hud_info` (`tests/hud_shots.gd`, a 1080p).

#### Pendiente

Cartel de autovía en vehículo (M7), *pings* y rueda de peticiones, subtítulos y rótulos de sonido con dirección, TTS,
paletas de daltonismo para los semánticos (las formas por tipo ya existen), descubrimiento y niebla compartidos por el
grupo en el servidor, salud de los compañeros replicada, capas desbloqueables y notas del mapa, sonidos de UI (los
eventos `ui_*` ya se llaman), y la temperatura simulada de M8.

---

### 9.7 Nota de implementación W0 + G2a (vinculante hasta que se revise)

Implementa el «corte urbano» de `docs/research/09_ciudad_mundo_vivo.md` §3 y el G2a de `docs/research/08_graficos_g2.md` (P0: fundido de edificios altos = el corte completo, nieve por normal v2, ventanas de ciudad y charcos de luz, torres en piezas con `visibility_range` y HLOD por chunk). Complementa §9.3 (el `CutawayManager` de M6a heredará `BuildingCutaway`) y §17 (presupuestos de ciudad).

**Decisión que cambia el doc 09: sin `instance uniform`.** Godot reserva 16 `vec4` del búfer global por cada instancia que usa un shader con uniformes de instancia, y en Compatibility ese búfer es un UBO (4 096 `vec4` en llvmpipe/WebGL2): **256 instancias**. Medido en 4.7.2: con 1 200 cubos, 944 dan `Too many instances using shader instance variables`. Una manzana de ciudad lo supera. Por eso todo lo que el doc 09 ponía por instancia sale de:
- **globales** (`project.godot [shader_globals]`, los escribe `CityCut` cada frame): `ws_cut_player` (pies del jugador local, encendido), `ws_cut_floor` (nivel de planta del jugador de/a + mezcla de 0.25 s + muñón 0.4 m), `ws_cut_view` (dirección a cámara, pasillo W = 10 m, zona R = 16–26 m según la distancia horizontal de la cámara), `ws_cut_capsule` (pecho + Rc 3.5–4.5 m), `ws_cut_aim` (segunda zona, apagada hasta que exista el apuntado), `ws_cut_own` + `ws_cut_own_ext` (huella OBB del edificio en el que está el jugador, muñón 0.6 m y techo de su planta), `ws_cut_cam` + `ws_cut_cam_ext` (huella del edificio que contiene o roza la cámara, **nuevo**: ver abajo) y `ws_cut_style` (intensidad del tramado, cápsula de props, borde);
- **`MODEL_MATRIX[3].y`** = base del edificio (contrato: las piezas no se desplazan en Y);
- **uniformes de material** por familia: `ground_h` / `floor_h` / `cap_color` (`world_vcol_struct.tres` 3.3/3.0, `world_vcol_struct_4m.tres` 4.3/3.0; otra rejilla = un duplicado cacheado por `CityBuilding.struct_material`).

**Familia de materiales `world_vcol`** (un solo cuerpo, `assets/shaders/world_vcol_common.gdshaderinc`; las variantes solo activan `#define`):

| Material | Shader | Para | Corte |
|---|---|---|---|
| `world_vcol.tres` | `world_vcol.gdshader` (`cull_back`) | personajes, bosque, props, POIs (todo lo de antes) | ninguno: sin `discard`, coste de G1 |
| `world_vcol_capsule.tres` | `world_vcol_capsule.gdshader` (`cull_back`, `WV_CUT_CAPSULE`) | props de ciudad, farolas, coches | cápsula cámara→pecho, solo con el perfil de ciudad |
| `world_vcol_struct.tres` / `_4m` | `world_vcol_struct.gdshader` (`cull_disabled`, `WV_CUT_STRUCT`) | estructura de edificios de ciudad | corte por forjado + zona + pasillo + cápsula + edificio propio + edificio de la cámara, tapas |
| `window_city.tres` / `_4m` | `window_city.gdshader` | vidrio de fachada de ciudad | el mismo que la estructura |

Include `assets/shaders/city_cut.gdshaderinc`: `city_cut_struct_discard`, `city_cut_capsule_discard`, `city_cut_plan`; los *built‑ins* de etapa entran como parámetros; nunca en `IN_SHADOW_PASS`. `CityCut.fade_at()` / `is_cut()` son el espejo en GDScript (umbral 0.5): lo usan el rayo del cursor (`CityCut.ray_through_cut`, cableado en `Interactor`) y los tests.

**Capas implementadas** (doc 09 §3.1) y cambios respecto al prototipo:
- **A/B/C** como en §3.2–3.3. Las **tapas** son las caras traseras (`cap_color` oscuro, normal hacia arriba). **Nuevo, la planta legible**: toda cara hacia arriba bajo una columna cortada de su edificio (la losa de la planta siguiente, o la planta propia) se pinta como plano (`plan_color`, `plan_mix` 0.55, algo de emisión que baja de noche) aunque esté en la sombra de las plantas superiores, que siguen proyectándola. Muros con grosor y tabiques → líneas de *poché*; núcleos abiertos → huecos negros.
- **Nuevo: edificio de la cámara.** Si la cámara está dentro de una torre o a < 6 m de su huella por debajo del tejado (`CityBuilding.hugs_camera`), esa torre entera se corta por encima del forjado del lado de la cámara: con solo pasillo + zona, sus losas fuera del pasillo, vistas a través de la fachada cortada, tapaban un tercio de la pantalla (el «anillo» del doc 09 §3.8).
- **D, siluetas**: `material_overlay` por instancia (`assets/shaders/silhouette.gdshader`, `depth_test_inverted`) puesto por `Silhouettes` (cliente, 5 Hz): jugadores siempre, del color de su chaqueta; zombis solo **percibidos** (por defecto: ≤ 24 m y línea de visión desde los ojos del jugador en la capa `world`; `perceive_filter` se sustituye cuando llegue la visibilidad honesta). Para que un personaje no se tiña a sí mismo (desde −48° los hombros tapan los pies a 1.3 m de profundidad) cada vértice se acerca **1.8 m a la cámara por su propio rayo de vista** (mismos píxeles, menos profundidad): sin textura de profundidad ni stencil, igual en Forward+, Compatibility y Web. Un *overlay* ajeno (el hielo de los congelados) no se toca.
- **E, edificio propio**: `CityCut` elige el edificio registrado que contiene los pies del jugador (no cuenta estar en el tejado) y le pasa la planta: `Roof` y los `Shaft_<n>` por encima se ocultan **conservando la sombra** (`SHADOWS_ONLY`; si un `ShadowProxy` ya proyecta por ellos, `visible = false`), nunca `visible = false` en algo que proyecta. En el shader, dentro de su huella: todo por encima del techo de la planta se va y los muros del lado de la cámara bajan a 0.6 m (rampa lateral estrecha, −1.5…0.5 m respecto al jugador; la general del corte es la del doc, −3…1 m). **En una azotea** (`CityCut.roof_building`) el peto y las casetas del lado de la cámara bajan a 0.6 m sobre el tejado y nada se oculta en CPU.
- **F, cursor**: `Interactor` usa `CityCut.ray_through_cut` (hasta 4 reintentos excluyendo el colisionador cortado); sin ciudad es un `intersect_ray` normal.
- **`BuildingCutaway`** (`scripts/world/city/building_cutaway.gd`) es ahora la lógica de grupos de corte de ASSET_SPEC v2 §8.4: `PoiCutaway` la hereda en modo `VISIBLE` (**comportamiento M3 idéntico**, comprobado en `tests/render_steps.gd` con `cabin_small` y `lookout_tower`) y `CityBuilding` en modo `SHADOW` para las partes enterables. La cabaña del claro sigue con su `Cutaway` (el smoke test comprueba `Roof.visible == false`).

**Contrato de edificio de ciudad** (para el arte; lo comprueba `CityBuilding.validate()`):

```
<Edificio>  Node3D, origen = centro de la huella a nivel de calle; lo registra CityBuilding.attach(raíz) (grupo city_building)
  metadatos (meta del nodo o extras glTF de la raíz):
    floor_h 3.0 · ground_h 3.3 (4.3 con bajos de 4 m) · foundation 0.3 · floors · generator (bool) · enterable (bool) · kind
  Base          zócalo / plantas bajas (0 … ≤ 24 m): el detalle                          (alias Tower_Base)
  Shaft | Shaft_<n>   fuste en grupos de ≤ 4 plantas; extras floor_from (obligatorio) / floor_to   (alias Tower_Shaft_<n>)
  Roof          coronación, peto, casetas, depósitos, nieve                               (alias Tower_Top)
  ShadowProxy   prisma cerrado low-poly (12–400 tris), sin material: el único que proyecta sombra (SHADOWS_ONLY)   (alias Tower_Shadow)
  Floor<k> · Walls<k>_{N,S,E,W}(+_Stub) · Interior<k> · Door_<n> · Window_<n> · Spawn_* · Col*   parte enterable (§8.4)
```

Los alias `Tower_*` son los nombres provisionales de la primera exportación de A1; `CityBuilding.canonical()` los traduce. Reglas: piezas **sin desplazamiento en Y ni escala**, solo giro en Y (la base sale del origen de cada pieza); **volúmenes cerrados**, muros exteriores con grosor (cara interior hacia dentro), **una losa por planta** en `base + ground_h + n·floor_h`, tabiques con grosor, núcleos como cajas abiertas por arriba; materiales `palette_vcol` (→ `world_vcol_struct`), `window`/`glass` (→ `window_city`: una celda por vano de 2.4 m y planta), `emissive_*` sin tocar; AO horneada en `COLOR.a` ≤ 0.3 en losas y muros interiores (sin nieve dentro, `snow_shelter` 1) y ≈ 1 al aire libre. `CityBuilding` pone `visibility_range_end` 180 m (`Base`) / 150 m (`Shaft*`, `Roof`) con fundido propio en Forward+ (en Compatibility, corte), sombras solo en `ShadowProxy`, y el HLOD por chunk (`CityHlod.build_for(chunk)` / `remove_from`): una malla fusionada de las huellas (1 *draw call*) visible desde `Quality.hlod_begin()` (140 m; 120 en `compat`, 100 en Web) y `visibility_parent` en las piezas. En juego nunca entra en cuadro; sirve a miradores y menús (`CityHlod.mesh_builder` admite un impostor).

**Nieve por normal v2** (`snow_include.gdshaderinc`, toda la familia): borde roto por ruido de valor en espacio mundo (0.6 m + 2.5 m), abrigo por la AO horneada (sin nieve bajo aleros, bajo coches ni dentro), nieve pegada a barlovento en caras verticales (`snow_wind`: dirección hacia la que sopla + intensidad, `DayNight` desde `WorldState.wind_yaw`: 0.3 en calma, 1 en ventisca) y `snow_base` por familia (0 en `world_vcol`: con tiempo despejado los assets de siempre se ven **igual que en G1**; 0.45 estructura de ciudad, 0.35 props de ciudad). Mismo color de nieve que el terreno (el tinte de blancos de G1).

**Noche de ciudad**: `window_city` divide el vidrio en celdas (vano × planta, en espacio mundo); por celda un *hash* decide encendida (28 % de las alimentadas), cálida / fría (12 %) / parpadeo (3 %), velas de supervivientes (1.5 % sin corriente) y se re‑sortea escalonadamente cada 2 h de juego. La corriente sale de `city_lights.y` (red) o del **mapa de potencia** `city_power_map` (R8, `CityLights.create_power_map` / `paint_power`: sectores de red y **manzanas con generador**). `CityLights` pone los **charcos de luz falsos** (quads aditivos en un `MultiMesh` con `INSTANCE_CUSTOM`: color, intensidad, parpadeo) y los halos de las bombillas (otro `MultiMesh`): 2 *draw calls* por conjunto de farolas; `OmniLight3D` reales solo en las farolas alimentadas más cercanas (`Quality` `lamp_lights`: `alto` 12, `medio` 6, `compat`/Web 0). `DayNight` escribe la noche de ciudad (se encienden un poco antes del ocaso; 0.35 en ventisca de día).

**P1 hecho**: capa de bruma a pie de calle con los perfiles de ciudad (`DayNight.city_haze`: `fog_height` +3 m y `fog_height_density` +0.006 de día / +0.010 de noche, en los tres renderizadores); nieve que arrastra el viento a ras de suelo (`SnowDrift`, `GPUParticles3D` de 900 × ratio de calidad, franjas planas orientadas por la velocidad, 1 *draw call*, apagada con viento de calma) y ondas de nieve suelta que corren por el terreno en ventisca (`terrain.gdshader`, `snow_wind.z` > 0.35). **Diferido**: LUT 3D por clima.

**Perfiles de cámara** (`CameraProfile` / `CameraZone`, `CameraRig`): `default` = la cámara de G1 (−48°, 16–38 m, *far* 70); `city` (−43°, 16–44 m, *far* 95, cápsula de props activa) en los distritos; `rooftop` (−40°, 20–50 m, *far* 130) a más de 7 m sobre el origen de la zona. Pitch y *far* se mezclan (τ 0.45 s), el zoom se recorta al rango del perfil. El corte escala con la cámara, así que el jugador sigue visible con cualquier perfil (medido abajo). `DayNight.city_haze` añade una capa de niebla de altura a pie de calle con los perfiles de ciudad (P1).

**Rendimiento y puertas** (banco `tests/city_bench/`, 12 edificios de 6–40 plantas —los del lado de la cámara procedurales y listos para corte, los demás las torres y edificios winterizados de A1 (`assets/models/city/towers/tower_a…e`, `buildings/bldg_m/n`) cuando existen—, 9 coches y 10 farolas de A1 (o copias CC0 de prueba), jugador y 17 zombis; `tests/run_city_bench.sh`):

- **Puertas bloqueantes** (`tests/run_all.sh` y CI): `tests/render_checks.gd` (*headless*, 78 comprobaciones: el espejo GDScript del corte, contrato de edificio y alias, corte de POIs M3 idéntico, perfiles de cámara, luces, siluetas, HLOD, rayo del cursor, `CityCut.update` < 0.2 ms con 300 edificios: medido 0.02–0.04 ms gracias a una rejilla de 32 m) y `tests/run_city_bench.sh gate` (xvfb): jugador visible ≥ 99 % (o ≤ 6 píxeles de borde) desde 24 m en 15 vistas (calle‑cañón, cruce en diagonal, azotea, planta 3 de un edificio, calle junto a la torre de arte `tower_d` de 100 m; 16–50 m; perfiles `default`/`city`/`rooftop`), zombis legibles ≥ 95 % en las vistas de calle a 24–38 m, sombra de la torre cortada en la calle ±5 % (medido: razón 1.000) y *draw calls*/primitivas del encuadre de ciudad ≤ 700 (Compatibility) / ≤ 1 000 (Forward+).
- **Medido** (1280 × 720, banco con el arte de A1): jugador visible 99.7–101.2 % en Compatibility y 99.6–100.3 % en Forward+ (sin corte: 0 % en la calle‑cañón a 24/38/44 m, junto a la torre de arte a 38/44 m y dentro del edificio; la cámara está dentro o pegada a una torre en 5 de las vistas); zombis de la calle a 24–38 m 100.0–100.1 % / 99.9–100.1 % (a 44–50 m, informativo: 67–98 %); *draw calls* día/noche 117/53 (Compatibility, 343 k/128 k primitivas) y 116/97 (Forward+, 350 k/331 k). Desde una azotea o una planta alta, los zombis al pie del propio edificio los tapa su fachada (por debajo del jugador: no se corta y no hay línea de visión, así que tampoco silueta): esas filas solo informan.
- **Coste** (informativo, rasterizadores por software, `tests/run_city_bench.sh perf` con `ROUNDS=3`): frente al material `world_vcol` de G1 en los mismos edificios, mediana de 3 rondas intercaladas: **Forward+ (lavapipe)**: variante `struct` con el corte apagado +2.0 / +3.2 % (día / noche), evaluando todo el corte sin quitar nada +5.1 / +7.4 % (presupuesto del doc 09: 10 %), corte real +23.4 / +20.5 % (la calle y los personajes que el corte deja a la vista); **Compatibility (llvmpipe)**: +41.6 / +40.3 %, +57.1 / +60.3 % y +16.9 / +37.6 %: sin pre‑pase de profundidad, `cull_disabled` + `discard` pesan (el doc 09 midió +32 % en llvmpipe). Riesgo abierto: medir en una iGPU real; si hace falta, una variante `compat` de la estructura con `cull_back` y sin tapas. En el rasterizador por software lo caro es `cull_disabled` + la ruta de `discard` (la variante `struct` con el corte apagado ya cuesta eso); en GPU real el doc 09 estima ≤ 0.3 ms a 1080p y el *early‑Z* solo se pierde en la estructura de ciudad. El bosque no paga nada: `world_vcol` no tiene `discard` y, sin edificios de ciudad registrados, `CityCut` no escribe los globales. `World` solo añade los nodos visuales de W0 (`CityCut`, `Silhouettes`, `CityLights`, `SnowDrift`) cuando hay pantalla: ni los clientes *headless* ni `perf_walk --cpu` los tienen (ese banco sigue en p99.9 ≈ 2.0 ms, máx. 2.4–5.1 ms en tres pasadas solas).
- **Regresión del bosque**: `world_vcol` antiguo y nuevo sobre cabaña, pino, camioneta, roca, torre de vigilancia y superviviente, misma escena: con tiempo despejado **idénticos al píxel** (diferencia máxima 0); en ventisca cambia la nieve (v2, buscado).

**Diferido**: rayo del cursor en `PlacementController`; zona de apuntado (`aim_zone`) hasta que exista el apuntado de M5; LUT 3D por clima (P1); `FogVolume` locales y volumétrica urbana (G2b); mapa de rodadas por chunk (G2c); integración con el *streaming* de ciudad (C1: `ChunkJob` → `CityBuilding.attach` + `CityHlod.build_for`); un segundo edificio de cámara cuando dos torres rozan la cámara a la vez.

### 15.5 Nota de implementación M5 (vinculante hasta que se revise)

Sustituye lo anterior de §11.3 (armas a distancia), §15 y §16 donde lo contradiga.

#### Persistencia

- **Backends.** `BackendFactory.create(kind, save_path) -> [backend, kind, path]` es la única puerta:
  - `sqlite` es el valor por defecto;
  - un `save_path` `.json` sin clave `backend` da `file`, así que las configuraciones de M2 no cambian;
  - `memory` no guarda nada;
  - si la clase `SQLite` no existe (sin extensión, Linux arm64, web), cae a `FileBackend` en el mismo path con `.json`.

  `SqliteBackend` instancia la clase con `ClassDB.instantiate(&"SQLite")` y la guarda en una variable sin tipo, así que el
  script compila sin el addon. Al abrir la primera vez un store SQLite nuevo, `BackendFactory.import_json` importa el
  `world_save.json` de M2 si existe.
- **godot-sqlite v4.9** (MIT). `tools/fetch_godot_sqlite.sh` fija la URL del *release* y su SHA‑256
  (`c0eed5f0…0dedb`), guarda la descarga en caché en `~/.cache/ventisca` y copia solo los binarios de escritorio y
  servidor, con un `.gdextension` recortado y un sello `VERSION`. La extensión no se versiona (`.gitignore`). El
  preset Web excluye `addons/godot-sqlite/*` y se ha comprobado que no queda ninguna `extension_list` en el `.pck`.
- **Esquema.** `PersistenceSchema.VERSION = 2` es el `PRAGMA user_version`. Las migraciones
  `scripts/persistence/migrations/NNN_*.gd` exponen dos cosas:
  - `statements()`: el SQL, que se ejecuta en una transacción por migración;
  - `document(doc)`: la misma migración aplicada al JSON de `FileBackend`, que también se versiona con `schema_version`.

  Contenido de cada versión:
  - **001**: las tablas de §15.2, más `profile_json` (el perfil entero del jugador), `population_json` en `chunks`,
    `data_json` en contenedores, estructuras y *drops*, y los índices por `(cx, cz)`.
  - **002**: `containers.table_id`, `containers.bags_json`, la tabla `nominal(region, category, spawned)` y las filas
    `world_meta.world_version` y `city_version`.

  `world_version` se lee de `WorldConst.WORLD_VERSION` (2, el mundo de 96² de W1) mediante el mapa de constantes del
  script, para no romper si falta la constante. `city_version` sale de `WorldConst.CITY_VERSION`, o vale 0 hasta que C1
  la cree. `save_world_meta` fusiona con lo guardado y sella siempre las dos versiones.

  Un store con un esquema más nuevo que el del servidor se rechaza con `ERR_FILE_UNRECOGNIZED` y nunca se degrada.
  Un store nuevo, ya sea SQLite o JSON, pasa por todas las migraciones al abrirse, así que `dbinfo` muestra
  `world_version=2` desde el primer segundo.
- **Claves.** Las filas de los chunks usan `(cx, cz)` y `chunk_keys()` devuelve `WorldConst.key(cx, cz)`. No hay
  ninguna otra codificación de clave en la persistencia. Los `wid` son de 63 bits y se guardan como `INT`.
- **SQLite.** Al abrir se aplican `journal_mode=WAL`, `synchronous=NORMAL` y `busy_timeout`, y se ejecuta
  `quick_check`, cuyo resultado se registra en el log y aparece en `dbinfo`.
  - `begin_batch()` / `flush()` equivalen a `BEGIN IMMEDIATE` / `COMMIT`.
  - Un `ChunkDelta` sucio se guarda por tabla, borrando e insertando las filas de ese `(cx, cz)`. Las columnas
    tipadas de §15.2 se rellenan y la entrada completa va en `data_json`.
  - `events` se poda a 5 000 filas.
  - `backup(path)` usa `VACUUM INTO`.
  - `close()` ejecuta `wal_checkpoint(TRUNCATE)`, así que tras un apagado limpio no quedan ficheros `-wal`.
  - La tabla `corpses` existe pero no se usa: los cadáveres siguen siendo estructuras, como en M4.
- **Guardado.** `PlayerManager.save_all()` es un único lote:
  1. los perfiles;
  2. `world_meta` (versión del juego, semilla, día, hora, clima, reglas, `saved_at`);
  3. `NetWorld.save_to` (solo los chunks sucios);
  4. `Loot.take_dirty_nominal`;
  5. `flush`.

  Tarda entre 0.5 y 1.1 ms con 1–2 jugadores y 10–26 chunks. El nodo `Autosave` lo llama cada `autosave_seconds`
  y hace la copia diaria en `<dir>/backups/world-AAAAMMDD.(db|json)`, conservando `backup_keep`. Además se guarda
  al cerrar un contenedor (su chunk, en el momento), al hibernar un chunk, con `save` y con `save-and-quit`.

  Al arrancar se restauran el día y la hora; la restauración se difiere un *frame*, porque `DayNight` aún no está en
  el árbol dentro de `Game._ready`. Si la semilla de `server.cfg` no coincide con la guardada, el servidor avisa.
- **Réplica de lo restaurado.** `StructureSpawner` y `DropSpawner` spawnean siempre con `spawn()` en un servidor
  dedicado, aunque no haya nadie conectado. Antes, un nodo restaurado al arrancar se añadía a mano y no se replicaba a
  quien entraba después: la hoguera existía en el servidor y no en el cliente. Lo encontró el escenario `restart`.
- **Prueba de caída.** Un proceso hijo (`tests/unit/crash_writer.gd`) confirma un lote, abre otro y escribe la
  mitad; la prueba lo mata con `OS.kill` con la transacción abierta. Al reabrir, `quick_check` da `ok`, el lote confirmado está y el lote a medias no.

#### Armas de fuego

- **Datos.** `Firearms.TABLE` contiene la pistola, el revólver, la escopeta, el rifle y el arco (daño, perdigones,
  crítico, cadencia, alcance y máximo, perforación, dispersión mínima, cono, retroceso, ruido, cargador, munición,
  recarga, derribo, durabilidad e inclinación de la cámara). Las constantes `GUN_*`, `BOW_*`, `THROW_*` y `CARRY_*`
  están en `Balance`. La recarga cuenta en el evento del clip (`mag_in`, `shell_in`, `bolt_close`) de
  `data/anim_events.json`; la escopeta carga cartucho a cartucho y puede interrumpirse. Desencasquillar dura lo que
  indica el evento `clear` de `Act_Unjam`.
- **Estado.** `PlayerState.gun` es un `WeaponState` (dispersión, último disparo, recarga, atasco, aceite y disparos).
  El cargador vive en el propio *slot* (`ammo`), así que un arma guardada o soltada conserva sus balas. El espejo
  privado `gun` llega al dueño como `Events.weapon_state_changed`.
- **Dispersión.** El objetivo es el mínimo del arma, más 3° andando, 8° corriendo o −1° agachado, multiplicado por 1.5
  con Calor < 15. Se abre a 30°/s y se cierra de forma lineal a 14°/s, así que en ≤ 0.8 s llega a cualquier objetivo.
  Cada disparo suma el retroceso del arma. Bandas: verde < 4°, ámbar 4–8°, rojo > 8°, gris si hay un aliado en la
  línea de tiro sin fuego amigo.
- **Petición y validación.**
  - El cliente envía `request_fire(seq, aim, view_ms, draw_ms)`, limitado a 10/s (`reload` 4/s, `throw` 3/s).
    `view_ms` es el retraso de interpolación de lo que ve, entre 100 y 300 ms.
  - El servidor (`Gunplay.fire`) comprueba vivo, arma, cadencia × 0.85, munición y atasco, y contesta
    `_fire_result(seq, ok, reason, hits, kills, crit, ammo)`.
  - El retroceso temporal es `clamp(RTT + view_ms, 0, GUN_REWIND_MAX = 0.2 s)`. Los zombis se consultan con
    `ZombieSystem.pos_ago` (su historial pasa a 30 muestras) y los jugadores con `HitHistory` (30 Hz, 1 s).
  - `Hitscan.trace` es un segmento 2D contra círculos de 0.4 m, con perforación y oclusión por un rayo en la capa 1.
    Los aliados sin fuego amigo se marcan como `pass`.
  - Los perdigones salen de `Firearms.shot_yaws(id, yaw, spread, seed)`, sembrados por disparo; el crítico es una
    tirada. El daño se agrega por víctima y pasa por `DamageResolver` con `crit_included`, así que las reglas
    `pvp` / `friendly_fire` siguen teniendo un solo lector.
- **Contrafactual de prueba.** En servidores con `debug_commands`, cada disparo imprime
  `[EVT] shot … rewind= rtt= hits= norewind=`, donde `norewind` indica si la misma bala habría acertado sin
  compensación.
- **Arco.** Es un proyectil en `Projectiles` (nodo de `Systems`, solo en el servidor): avanza por pasos con
  `Hitscan` y cae con gravedad. El 60 % de las flechas se recupera como un *drop* de `flechas`, y el daño y el
  alcance escalan con la tensión.
- **Lanzables.** La lata hace un ruido de 15 m donde cae. La bengala llama a `ZombieSystem.lure(pos, 40 m)` durante
  30 s y da +5 de calor cerca.
- **Ruido.** El ruido va por `SoundEvents` con el radio del arma × `noise_scale`. `ZombieNet.fx_noise` codifica un
  radio > 127.5 m en metros enteros con el bit 7 de `b`, para que el anillo de 150 m de la escopeta llegue intacto.
- **Cliente** (`FirearmClient`, hijo `Firearm` del jugador local):
  - predice el fogonazo, el retroceso y la munición, y aplica magnetismo hacia un zombi a menos de 1.2 m (desactivado
    en el rifle a más de 25 m);
  - emite `Events.reticle_changed(spread, band, aim, radius)` a 30 Hz;
  - la cámara se inclina `lean` 3 m (6 m con el rifle).

  `CharacterVisual.set_weapon_class` usa la biblioteca `guns` y mezcla `guns/<clase>_Aim` en el cuerpo superior; los
  `*_Shoot` van por la capa aditiva de impacto. `FirearmFx` dibuja trazadoras, el fogonazo y los proyectiles con un
  reloj de juego escalado, así que un *frame* congelado los conserva. `ReticleHook` es el gancho mínimo; la retícula
  completa es de H3.

#### Botín

- **Colocación.** `LootSpawns` escucha `streamer.chunk_loaded`, recorre los `poi_model` en busca de los *empties*
  `Spawn_Container_*` / `Spawn_Loot_*`, ordenados por nombre, y crea `LootContainer` en los dos lados con
  `wid = hash64(seed, GEN_LOOT, wid_del_POI, i + 1)`. Así no se replica ningún nodo: solo el delta del contenedor.
  El gancho `LootSpawns.attach(parent, model, parent_wid, seed)` sirve a los POI del valle y a los de C1.
- **Tirada.** `Loot.roll(seed, wid, table, day, salt)` es pura. Se tira en el servidor al abrir el contenedor por
  primera vez, y el resultado se recorta con los topes nominales por región y categoría
  (`LootTables.NOMINAL` × 1 a 1.75 según los jugadores, contadores en la tabla `nominal`). Los contenidos se guardan
  en el delta del contenedor (`items`, `rolled_day`, `table`, `opened_day`, `bags`).
  - `personal_loot_bags`: una bolsa por `token_hash` (sal = hash del token).
  - Reposición: tras 3 días sin abrir, con probabilidad `loot_respawn` (0.6), se tira el 60 % de una tirada y nunca
    munición. Es una versión simplificada de C22.
- **Modelo.** `LootContainer` lee `assets/models/props/loot/manifest.json` (arte T2) para la caja de colisión y las
  bisagras: la tapa, la solapa o las puertas giran `open_deg` sobre `hinge_axis` mientras `open_by ≠ 0`.

#### Servidor operable

- **`AdminCommands`.** Es la única implementación de los comandos; `AdminSocket` y el chat la llaman:
  - todos los canales: `status`, `players`, `stats`, `dbinfo`, `save`, `backup`, `say`/`broadcast`, `kick`, `ban`,
    `unban`, `bans`, `rule`, `rules`, `pvp`, `ff`, `time`, `day`, `weather`, `give`, `tp`;
  - solo el socket: `save-and-quit` y `quit`.

  El chat la usa si el `token_hash` está en `admin_tokens`, y siempre sin red.
  - `Net.ban_check` corta en `_server_auth` con el motivo `banned:<why>`.
  - `tp` limita con `WorldConst.clamp_playable(x, z, 2)`.
  - `save-and-quit` guarda, avisa, cierra la base y sale con el código 0.
- **RPC al dueño.** `PlayerNet.to_owner(method, args)` envía `_mirror`, `_notify` y `_fx`, y los retiene en orden
  hasta que llega el primer input del dueño, que demuestra que su cliente ya spawneó el nodo. El spawn y esos RPC
  fiables van por canales ENet distintos: con pérdida o *jitter* (`--net-sim`), un RPC temprano adelantaba al spawn y
  se descartaba («Node not found»), y el trozo de espejo perdido (ranuras, misión…) quedaba mal hasta que volviera a
  cambiar.
- **Versiones.** `Net.GAME_VERSION` es `0.7.0-m5` y `NET_PROTOCOL` es 4. `Net.rules_from_cfg` lee todas las reglas,
  también en el modo sin red.
- **Export.** El preset «Dedicated Server» (Linux x86_64, `dedicated_server=true`) usa `strip` para todo salvo
  `assets/materials/` y `assets/shaders/`, que se quedan en `keep` porque el material del terreno se carga como
  `ShaderMaterial`. Lleva el `.pck` incrustado y ocupa 79 MB. `server/build_server.sh` añade
  `libgdsqlite.linux.template_release.x86_64.so`, `run_server.sh`, `admin.sh` y `server.cfg.example`.
- **Operación.**
  - `run_server.sh` convierte SIGTERM/SIGINT en `admin.sh save-and-quit`, espera hasta 25 s y devuelve el código real
    del servidor. La primera vez crea `server.cfg` con un `admin_token` aleatorio.
  - La unidad `ventisca.service` usa `KillMode=mixed`, `TimeoutStopSec=35` y `Restart=always`.
  - La imagen Docker parte de `bookworm-slim` (`ARG BASE`), no instala nada y guarda los datos en el volumen `/data`;
    el `HEALTHCHECK` es `admin.sh status`. `admin.sh` usa `/dev/tcp` si falta `nc`.
  - Probado en local: `docker build`, `run`, `exec admin.sh status/dbinfo`, un cliente por `-p …:7777/udp` y
    `docker stop`, que da `save-and-quit` y el código 0; al rearrancar, el mundo se restaura desde `/data/world.db`.
- **Pruebas.**
  - `tests/net/net_sim.gd` es un relé UDP con un RTT de L ± J ms (la mitad en cada sentido) y P % de pérdida por
    sentido. `run_net_test.sh --net-sim L,J,P` hace que los clientes se conecten a través de él, en PORT + 2.
    `NET_BACKEND=sqlite|file` elige el store.
  - `hitscan`: B anda a 2.2 m/s. A ve a B con RTT + 100 ms de retraso (unos 280 ms) y el tope de 200 ms deja a un
    corredor de 6 m/s a 0.5 m, más que el radio de 0.4 m; esa es la limitación del tope de la especificación.
    Pasa con ≥ 60 % de aciertos y más aciertos que el contrafactual sin compensación (15/15 frente a 12, 13 frente a
    7, y 14 frente a 8 con el servidor exportado).
  - `run_restart_test.sh`: dos procesos de servidor sobre el mismo store, sqlite y file.
  - `persistence_m5_test`: 64 comprobaciones; `m5_units_test`: 34; el paso M5 de la prueba de humo.
  - CI: el trabajo `m5`, en paralelo y con un límite de 45 min.

**Diferido**:
- el cuerpo a cuerpo mantiene su retroceso de ½ RTT (150 ms, M4);
- disparar derribado;
- ropa más allá de v0 (abrigo, guantes y gorro sin aislamiento por partes);
- la tabla `corpses`;
- reposición por regiones de C22;
- binario SQLite para Linux arm64 (usa `FileBackend`);
- el modelo de la bengala (placeholder);
- la retícula y el HUD de munición definitivos (H3).

### 8.10 Nota de implementación W1 (vinculante hasta que se revise)

Implementa C25 (PLAN v3.8.2 W1; doc 09 §4.1–4.4): el mundo pasa de 3 × 3 km a **6 144 × 6 144 m** y el valle de M3
queda, sin cambiar un byte, en el cuadrante noroeste. Sustituye a §8.1, §8.4 y §8.9 donde los contradiga.

**Rejilla y claves** (`scripts/world/world_const.gd`):

- `WORLD_CHUNKS = 96` (0…95 en cada eje) y `CENTER_CHUNK = 24`: el chunk 24 sigue centrado en el origen, así que los
  índices, las claves y los `wid` del valle no cambian. Extensión de la rejilla: `EXTENT_MIN … EXTENT_MAX` = −1 568 …
  +4 576 m en los dos ejes.
- **Codificación de las claves de chunk: no cambia.** `key(cx, cz) = ((cx & 0xFFFF) << 16) | (cz & 0xFFFF)`,
  `key_cx(k) = (k >> 16) & 0xFFFF`, `key_cz(k) = k & 0xFFFF`; siempre tuvo 16 + 16 bits, así que 96² cabe sin tocarla
  (máx. `key(95, 95)` = 6 226 015). Persistencia (M5), red e índices usan solo la API (`key`, `key_of`, `chunk_of`,
  `key_cx/key_cz`, `in_grid`). Nuevo: `chunk_index(cx, cz) = cz · 96 + cx` (0…9 215) para tablas densas en memoria
  (**no** se persiste: depende del tamaño de la rejilla), `CHUNK_COUNT = 9 216` y `WORLD_VERSION = 2`
  (`world_meta.world_version`).
- Muros por eje: `WALL_MIN = −1 450`, `WALL_MAX = +4 420`; `in_playable(x, z)`, `clamp_playable(x, z, margen)`
  (lo usa `/tp` vía `AdminCommands.teleport_player`), `wall_distance(x, z)` (distancia al muro más cercano) y
  `quadrant(x, z)` (0 NO valle, 1 NE Altavega, 2 SO Peña Blanca, 3 SE La Vega, alrededor de +1 504 m). `WALL`,
  `HALF` y `BORDER_START` quedan como constantes heredadas.
- `Bounds`: cuatro muros en `WALL_MIN/WALL_MAX`. Niebla del borde: `World.border_fog_scale` = 1 + 3 ·
  smooth(`BORDER_FOG` = 198 m → 0, `wall_distance`): la misma rampa que M3 en los lados oeste y norte del valle
  (1 252 → 1 450 m) y ahora también en los lados este y sur del mundo.

**Plano macro v1** (`tools/gen_macro_map.gd` → `data/world/macro_map.png` 768² a 8 m/px desde −1 536 m +
`macro_roads.json` v2; `MacroMap.SIZE = 768`, `WorldConst.MACRO_ORIGIN`):

- Canal G = bioma × 16 (16 biomas; M3 usaba × 40 para 6). Biomas 6–15: casco viejo, ensanche, financiero, barriada,
  suburbio, industrial, puerto, base aérea, esquí/aludes, río helado. `MacroMap.RELIEF_OF_BIOME` escala el ruido del
  slice por bioma (ciudad, puerto, polígono y base casi planos; río 0); vale **exactamente 1** en los biomas 0–5, y
  `relief_block` devuelve {} cuando todo el bloque es 1 (tabla de áreas sumadas), así que el valle no multiplica nada.
- El generador pinta **con el código v0 intacto** (su mapa 24 × 24, su borde de ±1 536 m) todos los píxeles con
  x, z < 1 224 m (`VALLEY_KEEP`: el núcleo B‑spline ±16 m + retícula 4 m + los 24 m del parecido de bayas + la ventana
  de 40 m del perfil de la N‑140 alrededor de los chunks del valle). Entre 1 224 y 1 400 m el antiguo anillo de borde
  se funde (máx.) con las sierras nuevas; más allá, el generador W1: montañas dentro de las celdas `^`/`%` del mapa
  48 × 48 (distancia con signo a su unión, con el mismo *warp* de v0), el anillo del borde del mundo con la fórmula v0
  sobre la extensión nueva, ciudad/puerto/polígono/base planos, cauces para `PoiRegistry.WATER` y corredores: el puerto
  de la Carretera del Puerto (`PASS_PROFILE`, 5 → 35 m y bajada a la Gran Vía; fuera del valle también rellena), la
  entrada del túnel de Peña Roya y el desfiladero. `++ --check` rehace los dos ficheros y los compara byte a byte
  (puerta en `run_all.sh` y CI).
- Carreteras y ferrocarril como sellos de terreno (`HeightFunction`): las 9 de M3 (la N‑140 termina ahora en la boca
  norte derrumbada del túnel) + Carretera del Puerto (7 m, pendiente ≤ 9 %: `max_grade`), Gran Vía (24 m), rondas
  norte y sur (18 m), A‑14 (22 m, perfil ±96 m), N‑140 sur, esquí, Santa María y el ferrocarril del Albo (`rail`:
  nieve pisada sin roderas). Claves nuevas del JSON: `name` (banner), `smooth`, `shoulder`, `max_grade`, `poles`,
  `pole_model`, `guard` y `pads`. Los lechos se desvanecen 18 m antes del hielo y el perfil cruza el cauce en línea
  recta (tablero del futuro puente; los puentes son POI de C1). Las carreteras W1 (`pads`) van a nivel sobre los *pads*
  W1 que cruzan.

**Datos** (`data/world/poi_registry.gd`):

- `ASCII` 48 × 48 = doc 09 apéndice A con una corrección: el río Albo es continuo (filas 43–44 de la columna 31).
- `REGIONS`: las 16 del valle (sin cambios) + 43 registros W1 con los datos que **H2 migrará a `LocationInfo`**: `id`,
  `name` (banner), `display`, `kind` (city/district/town/village/poi/natural/road), `parent` (id), `danger`, `power`,
  `temp`, `zombies` [mín, máx] por chunk (doc 09 §4.3), `milestone` y `reserved`. Orden del banner: lugares (tier 0) →
  lagos y agua → carreteras con nombre (`ROAD_REGIONS`, `HeightFunction.named_road_at`) → áreas amplias (Altavega,
  Sierra del Cierzo, Sierra de Peña Blanca, La Vega) → LAS CUMBRES (a < 202 m del muro más cercano) → PINOS ALTOS (solo
  dentro del valle) → BOSQUE PROFUNDO. `regions_containing(x, z)` da la jerarquía (distrito antes que ciudad) y
  `natural_depth` las áreas por función. `Locations` (H1) ya lee esos campos (cambio mínimo, sin UI nueva).
- `PADS`: 17 del valle + 8 portales de túnel (arte T2, `carve` respetado: *pad* rectangular a nivel de la boca) y 27
  *pads* reservados de C1–C3 (rectangulares o circulares; opcionales `h`, `h_at`, `blend`, `model_at`). Planos hoy
  para que el terreno no cambie cuando llegue el POI.
- `WATER`: río Albo (polilínea, 128 m), dársena, embalse del Cierzo (+14 m, tras la presa) e ibón (+7 m). **Hielo
  plano y seguro hasta E1**: la altura es exactamente el nivel y la máscara `CUSTOM0.g` es hielo; orilla como el Lago de
  las Ánimas. `Terrain.is_lake` los incluye (población congelada, sin *spawns* del director).

**Scatter**: tablas por bioma W1 (la ciudad es suelo abierto con pocos árboles hasta C1), nada sobre el hielo ni
sobre los *pads*, y dos generadores nuevos con celdas propias (el valle no cambia): props de cresta (celdas de 16 m
por encima de 72 m: `crest_rock_a/b`, `crest_spire`, `scree_field`, `cliff_face`, `cairn`, `cornice`) y mobiliario de
carretera (jalones cada 25–50 m, `road_delineator` en la A‑14 y la N‑140 sur, guardarraíles de 4 m en el tramo de
montaña de la Carretera del Puerto). Variantes añadidas al final de `ScatterCatalog.VARIANTS` (índices estables);
colisiones del `assets/models/world/manifest.json` del arte.

**Población** (`scripts/world/population_table.gd`): tabla 96² (9 216 B, perezosa, `chunk_index`); el valle conserva
la fórmula de M4; fuera, el rango `zombies` de la región más profunda, × 0.2 (máx. 12 por chunk) mientras la región
está `reserved` (suelo sin edificios), o el rango del bioma. `PopulationManager.target_of` la consulta.

**Aceptación** (medida con `taskset -c 0,1` en la VM compartida de 4 núcleos):

- **«El valle no cambia»** (`tests/valley_unchanged.gd`, línea base `tests/data/valley_prew1_hashes.json` tomada antes
  de tocar nada): de los 1 225 chunks con centro en |x|, |z| < 1 152 m (7…41 en cada eje), **1 214 idénticos** en
  altura (bits float32 crudos), superficie y *scatter* (entradas + nodos + `wid`), y los **11 de la lista cerrada** de
  la Carretera del Puerto cambian (fila 18, cx 34…41, + (40, 17), (41, 17), (41, 19)). El nombre de región no entra en
  el hash (el antiguo anillo LAS CUMBRES del este y el sur es ahora SIERRA DEL CIERZO / SIERRA DE PEÑA BLANCA).
- `tests/run_determinism.sh`: **60 chunks** (NO 30, NE 11, SO 9, SE 10) + `height_at` en 300 puntos, servidor y
  cliente en dos procesos: idénticos.
- `tests/w1_world.gd` (25 comprobaciones): rejilla, claves, muros, cuadrantes y niebla; macro 768² con los 16 biomas
  donde los pone el doc 09; **banner correcto en los 20 puntos de prueba**; datos de `LocationInfo` completos (43
  regiones, padres válidos) y leídos por `Locations`; hielo plano en río, dársena (también bajo los futuros puentes),
  embalse e ibón; Carretera del Puerto de 1 169 m con pendiente máx. 9 %; la Gran Vía se corta en el Albo; *pads*
  reservados planos (≤ 0.35 m); portales a nivel dentro del `carve` del arte; props de cresta, jalones y
  guardarraíles; nada sobre el hielo; tabla de población 96² (NO 1 159, NE 4 444, SO 2 427, SE 4 774 residentes base;
  máx. 12 por chunk; 0.4 s en llenarla entera).
- `perf_walk --cpu`, ruta W1 de **6.52 km a 25 m/s** por los cuatro cuadrantes (valle → Carretera del Puerto → Gran
  Vía → barriada → río Albo helado → dársena → Vega Baja → ferrocarril al SO), tres ejecuciones con carga 1–3 de otros
  carriles en la VM: *streaming* (trabajo) **p99 1.75 / 1.78 / 1.78 ms**, p99.9 2.00 / 1.99 / 2.01 ms, máx. sin frames
  con *steal*/bloqueo 3.75 / 6.33 / 4.93 ms, 0.10–0.12 % de frames sobre 2 ms, **0 tirones por *streaming***, suelo
  nunca ausente, RSS 296 MB; 588–591 chunks generados (45–62 ms de media en hilo con esa carga). Pared (informativo):
  p99 2.02 / 1.91 / 1.86 ms, p99.9 8.63 / 7.58 / 5.36 ms, máx. 269 / 274 / 17 ms (esperas en cola de hasta 274 ms).
- Generación de un chunk (un hilo, sin carga): valle 28 ms, ciudad 35 ms, río 36–43 ms, puerto 39 ms. Plano macro:
  decodificación 150 ms (un solo recorrido con tablas locales); `HeightFunction.create` 130 ms (perfiles de 19
  carreteras; agua y *pads* filtrados por carretera). El cliente decodifica el macro mientras conecta, no en la
  respuesta de autenticación (con 4 clientes arrancando a la vez en 2 núcleos, sin eso un cliente superó los 5 s de
  `AUTH_TIMEOUT`).
- `run_net_test.sh --scenario far` con **4 clientes en los 4 cuadrantes** (A valle, B urbanizaciones del norte
  (2 816, −1 216), C Vega Baja (2 176, 2 432), D sur del ferrocarril (256, 3 136); B–D 5.05 km): cada uno ve irse a los
  otros tres, tala su árbol y solo recibe eventos e instantáneas de su anillo; **RSS del servidor máx. 316 MB**
  (puerta ≤ 400 MB en `run_net_test.sh`), 36 chunks calientes.
- *Perf walk* en modo render (xvfb + Compatibility sobre llvmpipe, la misma ruta de 6.52 km): **RSS del cliente máx.
  791 MB** (límite 2.5 GB), suelo siempre presente, 0 tirones por *streaming*; 578 chunks generados.
- Capturas (Forward+ sobre lavapipe, presets `overview_pass`, `overview_city`, `overview_port`, `overview_sw`,
  `overview_se` de `tests/screenshot_steps.gd`) y el plano macro (`tools/macro_preview.py`) en `docs/screenshots/w1/`.

**Picos del *perf walk* (causa raíz).** Los picos aislados de 9–22 ms de un solo paso del *perf walk* `--cpu`
(ya presentes antes de v3, p99.9 ≈ 2.0 ms, en un paso distinto en cada ejecución) **no son código nuestro: son el
hilo principal expropiado**. Evidencia (`SchedProbe`, `scripts/world/streaming/sched_probe.gd`: `run_delay` y
`pcount` de `/proc/thread-self/schedstat`, fallos de página de `/proc/thread-self/stat`, cambios voluntarios de
`/proc/thread-self/status` y *steal* de `/proc/stat`; `perf_walk --sched` los lee alrededor de cada paso):
  - de los pasos ≥ 2.5 ms, 22/23, 10/11 y 32/33 (ruta M3, tres ejecuciones) y 85/87 (ruta W1) tuvieron **espera en
    la cola de ejecución** de ≥ 1.5 ms (o ≥ la mitad de su duración) **dentro del paso**: el hilo estaba listo y otro
    hilo o proceso tenía el núcleo. Los dos restantes (`_step_collision` 6.4 ms, `_step_nodes` 3.1 ms) no tuvieron ni
    espera ni cambio de contexto y < 1 *tick* de CPU: *steal* del hipervisor (la VM es Firecracker/KVM; con
    `CONFIG_PARAVIRT_TIME_ACCOUNTING` el *steal* no cuenta como tiempo del hilo ni como espera);
  - 0 fallos de página mayores y 0–1 menores en los pasos lentos (no son liberaciones grandes ni asignación); los
    mismos pasos (Jolt en `_step_shapes`, subida de MultiMesh, *teardown*) cuestan 0.2–1.5 ms cuando no hay
    expropiación: el tipo de paso afectado es aleatorio;
  - nuestro proceso tiene ≤ 2 hilos ejecutables el 98.7 % del tiempo (muestreo de `/proc/<pid>/task/*/stat` cada
    10 ms durante 50 s: 0 → 72 %, 1 → 23 %, 2 → 3.4 %, ≥ 3 → 1.3 %; el `WorkerThreadPool` ejecuta una sola tarea de
    chunk de baja prioridad a la vez), así que en 2 núcleos fijados nuestros propios hilos no ahogan al principal;
    en cambio, mientras medíamos, los otros carriles fijaban sus Godot (humo, red) y Blender a los mismos núcleos
    (carga media 2–5 en la VM de 4 vCPU; la espera acumulada del hilo principal llegó a 36–42 s en 260 s de paseo).
Arreglo en el código: el único bloqueo nuestro observado (un frame de 31 ms con un cambio de contexto voluntario en
`_collect_jobs`, bajo carga) era el hilo principal esperando el *mutex* del `WorkerThreadPool` que tenía un hilo
trabajador expropiado (`is_task_completed` lo toma por cada trabajo y frame): ahora `ChunkJob.finished` lo marca el
propio trabajo al terminar y el principal solo toca el *pool* una vez por chunk (`wait_for_task_completion` de una tarea
ya acabada). Para el resto (expropiación y *steal*) no hay coste nuestro que quitar; **la medida se hace robusta y
honesta**:
`WorldStreamer.sched_probe` lee la espera en cola del hilo principal al principio y al final de la ventana de
*streaming* de cada frame (dos lecturas de procfs fuera de la ventana cronometrada) y `perf_walk --cpu` puntúa el
**tiempo de trabajo** = pared − espera en cola (p99, p99.9, % sobre presupuesto); un frame > 33 ms solo se atribuye al
*streaming* si su tiempo propio (pared − espera de todo el frame) pasa de 33 ms **y** el *streaming* se pasó de sus
2 ms (los frames cuyo tiempo sin *streaming* también se disparó no cuentan); un frame se marca como **robado por el
hipervisor** cuando la ventana de *streaming* perdió más de un *tick* (4 ms) que no fue ni CPU del hilo (campo 1 de
`schedstat`, que con `CONFIG_PARAVIRT_TIME_ACCOUNTING` no incluye el *steal*) ni espera en cola, y el contador de
*steal* de nuestras CPU creció: entonces su parte de *streaming* se limita a su CPU medida (+1 *tick*); el máximo de un
solo frame excluye esos frames y los de hilo principal bloqueado (cambio voluntario), que se cuentan aparte. Los números de pared se siguen imprimiendo al lado. Sin Linux (o sin `CONFIG_SCHED_INFO`) la puerta
usa los números de pared como en M3.

**Desviaciones**: (1) el apéndice A pinta la vega sobre el río Albo en las filas 43–44 (columna 31): se deja el río continuo; (2) la
Gran Vía y las rondas solo dan banner donde no hay un distrito (los distritos ganan: el cartel de carretera es de H2);
(3) los puentes (Puente de Hierro, N‑140 sur, rondas, ferrocarril) no existen aún: las carreteras se cortan en las
orillas y el perfil cruza el cauce en línea recta para el tablero de C1; (4) la lista cerrada de la Carretera del
Puerto tiene 11 chunks: la fila 18 de x = 608 a 1 120 m (el sello y el despeje del *scatter*) y 3 junto a su último
tramo del valle (el corte del puerto en el plano macro); (5) la población de las regiones urbanas aún sin edificios
es el 20 % del rango del doc 09 (máx. 12 por chunk) hasta que C1/C2 construyan; (6) los portales de la A‑14 son dos de
7 m (uno por calzada), dentro del muro; (7) `WALL`, `HALF` y `BORDER_START` se conservan como constantes heredadas;
(8) el aviso «Navigation region synchronization had N edge error(s)» que aparece en el escenario `far` es de M4 y
también sale en chunks de bosque del valle sin cambios (vértices casi duplicados de las obstrucciones proyectadas de
Recast): no es de W1.

**Diferido**: `LocationInfo`/`ZoneTracker` y el cartel de carretera (H2, con los datos de `REGIONS`/`ROAD_REGIONS`); la ciudad (C0,
C1: lotes, edificios, puentes, Control del Puerto); hielo fino, aludes y peligros del río (E1); carteles de km
(`km_sign`, `km_post` del arte T2) hasta el atlas `signage` (V1); vías y trenes del ferrocarril (C3); el esquema SQLite
con `world_version = 2` es de M5 (`WorldConst.WORLD_VERSION`, claves por `WorldConst.key`).

---

## §17.6 Nota de implementación H2 (zonas: entrar y salir)

Vinculante hasta que se revise. Implementa la tarjeta H2 del PLAN (v3.8.1; C35, C36) con la dirección «Susurro» de
`docs/research/10_hud_ux.md` §V.3–V.4.4 y las reglas del apéndice §6.1 y §6.5. Sustituye lo que §17.5 dice de
«Lugares», «Zonas» y del descubrimiento local (`Locations.CITY` / `enable_city()` ya no existen: la ciudad es la de W1).

#### Datos: `LocationInfo` y `Locations`

- **`LocationInfo`** (`scripts/data/location_info.gd`) es el esquema de un registro (un `Dictionary`: se copia barato,
  viaja por red y se serializa): `id`, `name` (español, mayúsculas y minúsculas), `banner` (el nombre en mayúsculas de
  `PoiRegistry`), `kind` (city | district | town | village | farm | poi | natural | road), `parent` (id), `shape`
  (`circle` [centro, radio] | `rect` [centro, tamaño] | `poly` (`PackedVector2Array`) | `multi` [formas] | `fn`),
  `danger` 0–3, `power` ("" | off | generator | on), `temp` (°C sobre el aire), `zombies`, `milestone`, `reserved`,
  `tier`, `camera`, `article` y, en carreteras, `road` {kind, plate, style}. `validate()` lo comprueba;
  `shape_depth()` da la profundidad con signo (círculo, rectángulo, polígono, varias partes) y `shape_center()` el punto
  representativo (etiqueta del mapa, ancla de misión, distancia del cartel). Barlow no tiene U+2011 (guion que no
  corta) ni U+2192 (→): `make()` cambia U+2011 por U+2010 en los nombres («N‐140», «Autovía A‐14») y la flecha del
  cartel se dibuja; la prueba comprueba que todo nombre y placa se puede dibujar con las fuentes del HUD.
- **`Locations`** (`scripts/data/locations.gd`) construye una vez las **70 zonas** migradas de `PoiRegistry`: las 2 zonas
  pequeñas del claro (`Regions.ZONES`), las 16 regiones del valle (datos en `KNOWN`), las **43 de W1 con sus campos**
  (37 reservadas para C1–C3), el Lago de las Ánimas, las **7 carreteras con nombre** de `ROAD_REGIONS` (lecho + 32 m,
  medidos sobre **sus propias trazas**: la N‑140 ya no toma a la A‑14 por ella), Las Cumbres, Pinos Altos y el Bosque
  profundo por defecto. Dos registros con el mismo *banner* son una zona en varias partes (`Urbanizaciones del norte`:
  el id del rectángulo este queda como alias).
- **Orden** (el del *banner*, `PoiRegistry.region_at`): lugares → agua → carreteras con nombre → áreas amplias
  (Altavega, las sierras, La Vega) → Las Cumbres → Pinos Altos → Bosque profundo. Dentro de los lugares manda el
  **nivel en la jerarquía** (número de antepasados: la Catedral ⊂ Casco viejo ⊂ Altavega va antes que el distrito) y
  luego el tipo (PDI antes que distrito). H1 ordenaba solo por tipo y el Lago helado (natural, dentro del claro) no salía
  nunca: ahora sale.
- `camera = &"city"` en Altavega, sus distritos, sus PDI y sus avenidas; `article` («del Hospital Provincial», «de la
  Catedral de Altavega», «de Las Torres») para las frases. `Locations.road_at()` (la carretera transitable bajo un punto:
  distancia al borde del lecho, nombre, dirección y punto kilométrico), `road_km()`, `next_junction()` (el siguiente
  enlace con otra carretera con nombre por delante) y `road_style()` sirven al cartel. `Locations.hf_override` deja
  usar las carreteras sin mundo (pruebas). Nota GDScript: los `Packed*Array` dentro de un `Array` son valores; se
  rellenan en una copia local y se vuelven a guardar.

#### `ZoneTracker` (`scripts/ui/hud/zone_tracker.gd`, cliente, 4 Hz)

- Posición del jugador, no el centro del chunk. **Histéresis**: una zona entra estando `inset` dentro (12 m; un cuarto
  del lado menor en lugares pequeños) durante **1.5 s**; la actual se mantiene hasta estar `inset` fuera durante 1.5 s.
- **Tarjetas** (`Locations.cards_of`): primera visita → `full`; re‑entrada → `compact` (ciudad, distrito, pueblo, aldea,
  granja, PDI) o nada (natural, carretera); **90 s** por zona; **20 s** entre tarjetas con **cola de 1** (la última
  gana; las demás solo actualizan `location_entered` con `card = none`). Las carreteras con nombre dan `sign` la primera
  vez. **Rápido sobre carretera** (> 40 km/h medidos en los últimos 1.5 s de posiciones, a ≤ 4 m del borde de un lecho
  transitable; un salto > 60 m en un paso es un teletransporte y borra velocidad y rumbo): cualquier tarjeta pasa a
  `sign` con su contenido (`ZoneSign.compose`).
- **Aplazar**: en combate (golpe, golpe dado o zombi persiguiendo a < 25 m en los últimos 5 s, `Hud.in_combat`) la
  tarjeta espera; con un P0 (derribado, Calor < 15 o un aviso P0 del `NotifyRouter` en pantalla, `Hud.p0_active`) la
  tarjeta completa pasa a compacta y espera; si el jugador ya no está en la zona, se descarta.
- **`zone_entered`** (señal propia y `Events.zone_entered`): cada zona confirmada, una vez fuera de combate (la última
  gana), con `{id, name, kind, camera, first_visit, chain, facts, danger}`.
- **Salir**: sin tarjeta; una línea P3 (`Events.notify_ex` prioridad 3 → columna lateral) solo si mejora: el peligro de
  ahora (+1 de noche) baja desde alto o extremo y la zona nueva no está dentro de la que se deja («Has salido del
  Control militar km 12»).
- Un `ZoneTracker` suelto (pruebas) solo emite sus señales (`entered`, `card_shown`, `zone_changed`, `left`,
  `exit_line`) y guarda sus descubrimientos en `discovered`; el del HUD tiene `publish = true` (espeja en `Events` y pide
  los descubrimientos a `ZoneDiscovery`, al que se engancha en cuanto existe: `discovered` es entonces su `known`).
  `step(pos, dt)` es la entrada pública: las pruebas y las capturas son un «móvil guionizado» que le da posiciones.

#### Título, cartel e Info

- `ZoneTitle` (H1) se queda con `full` / `compact`; `ui_zone_discover` solo en la primera visita (la re‑entrada no
  suena). Espaciado animado con `FontVariation.spacing_glyph` (52 → 32 px a 76 px: .78 → .42 em), 5.6 s; re‑entrada 2.5
  s al 60 %.
- **`ZoneSign`** (`scripts/ui/hud/zone_sign.gd`, en el `Safe` del HUD, arriba a la derecha, debajo de la línea de
  peligro si la hay): placa de 420 px, 3 s (entra en 240 ms con 6 px de desplazamiento, sale en 500 ms). Estilos: azul
  con texto blanco (autovía), blanco con texto negro y la placa roja «N‑140» (nacional), blanco (avenidas y el resto).
  Contenido: si la zona es una carretera, el destino por delante (ciudad, pueblo o aldea en ±60° del rumbo, ≤ 8 km, en
  la que no se está) con su distancia en km enteros, y «SALIDA n» con el siguiente enlace por delante («Gran Vía»; si no
  hay, el distrito o PDI de ese destino más cercano a la carretera); si no, la zona de más arriba de la jerarquía y la
  zona en la que se entra. Línea de datos: placa o carretera · electricidad del destino · temperatura. Es la única caja
  del HUD (§V.1 regla 6); un `StyleBoxFlat` reutilizado, sin reservas por frame.
- `InfoBlock`: con Info, una línea con la zona y su padre («Las Torres · Altavega») bajo la temperatura (§V.4.4: la
  ubicación se consulta con Info).

#### Descubrimiento del grupo (`ZoneDiscovery`, `scripts/net/shared/zone_discovery.gd`)

- Nodo con RPC en `/root/Game/ZoneDiscovery` en los dos sabores (lo añade `game.gd` después de `PlayerManager`):
  cliente → servidor `request_sync()` (al aparecer el jugador local) y `request_discover(zone_id)`; servidor → cliente
  `_sync([[id, por], …])` y `_discovered(id, por, peer)`. Canal 1 fiable, como `NetWorld`. `NET_PROTOCOL` pasa a **5**.
- El servidor comprueba que la zona existe y que el jugador está como mucho 40 m fuera de ella con **su** posición
  autoritativa, limita a 12 peticiones cada 2 s y guarda el **primero** por zona y ámbito: `"group"` con la regla
  **`shared_discovery`** (por defecto `true`, `[rules]` de `server.cfg`, replicada en `WorldState.rules`) o el *hash*
  del token del jugador si está a `false`. Avisa a los pares sincronizados de ese ámbito (nunca a uno que aún carga la
  escena: se evita el «Node not found»). El cliente guarda `known` (id → quién) y `pending`; un compañero que descubre
  algo que el jugador no conocía produce la línea P3 «Ana descubrió: Granja del Molino». El `ZoneTracker` da el título
  compacto a lo que el grupo ya conoce.
- **Persistencia** (esquema **3**, `migrations/003_discoveries.gd`): tabla `discoveries(scope, zone_id, by_token,
  by_name, day, ts, PRIMARY KEY(scope, zone_id))`; en el documento JSON, la clave `discoveries` {scope → {zone_id →
  {by, token, day, ts}}}. `PersistenceBackend.load_discoveries()` / `save_discovery()` en memoria, JSON y SQLite
  (`INSERT OR IGNORE`: el primero gana). SQLite escribe al momento (transacción propia o dentro del lote); JSON, en el
  siguiente `flush` (autoguardado, `save`, `save-and-quit`). Al arrancar: «[EVT] discovery: N zones restored». Sin
  servidor dedicado (offline, `MemoryBackend`) el almacén es `user://hud_discovered.cfg` por semilla, el fichero de H1.

#### Cámara (C28)

`CameraRig.zone_profile` sigue a `Events.zone_entered` (`info.camera`): si ninguna `CameraZone` contiene al jugador, se
usa ese perfil; la transición es la mezcla de W0 (`BLEND_TAU` 0.45 s) y nunca empieza en combate, porque
`zone_entered` se aplaza. Hoy solo existe el perfil `city` de W0.

#### Sonido

`AudioManager.STREAM_FILES` carga `assets/audio/ui/ui_zone_discover.wav` (1.8 s, soplo de viento y campana de cristal
grave en La3 con parciales inarmónicos) sintetizado por `tools/gen_ui_sounds.py` (determinista, solo biblioteca
estándar; obra propia, **CC0 1.0**, `assets/audio/ui/LICENSE.txt`). `AudioManager.register()` para los que vengan.

#### Pruebas y números (VM compartida de 4 vCPU, `taskset -c 0,1`)

- `tests/unit/zone_tracker_test.gd` (+ `_steps`): **38/38** en ≈ 1 s: datos (70 zonas válidas y dibujables con Barlow, 43 de W1 con 37
  reservadas, 7 carreteras, padres, partes múltiples, artículos, polígonos); zigzag ±8 m durante 30 s y 20 m fuera
  1.25 s cada vez → **0 cambios**; 11 m dentro 10 s → 0, 13 m durante 1.25 s → 0, 13 m durante 1.5 s → **1 cambio**;
  Altavega → Barriada de San Lázaro (**distrito sobre ciudad**), Catedral ⊂ Casco viejo, Las Torres sobre Ensanche,
  Lago helado ⊂ claro; 90 s por zona, compacta después, 20 s exactos entre tarjetas y cola de 1 (La Herrería sustituida
  por Valdenieve); combate aplaza título y `zone_entered`, lo descarta si te fuiste; P0 → compacta y espera; línea de
  salida (sí al dejar el control militar y el hospital, no al dejar una granja ni al entrar en un PDI del distrito);
  móvil guionizado a 90 km/h por la A‑14 → cartel «Altavega 2 km / SALIDA 1 · Gran Vía →» · «A‑14 · sin electricidad ·
  −9 °C»; por la Gran Vía hacia Las Torres → cartel urbano en vez del título; a pie, títulos y el cartel propio de la
  N‑140, un `/tp` no es velocidad; `zone_entered` → `CameraRig` pasa a `city` en Las Torres (nunca durante la pelea) y
  vuelve a `default` en el valle; **los 20 puntos de W1** dan el título esperado; tiempos del título y del cartel;
  almacén de descubrimientos en memoria, JSON y SQLite (y migración 2 → 3 de los dos); el sonido; **nombres (C36)**: 0
  apariciones de «Albarr» o de la palabra «Albar» en 240+ ficheros de `data/`, `scripts/` y `scenes/`.
- `tests/run_smoke.sh`, paso 19 (`tests/h2_smoke_steps.gd`): **288/288** en ≈ 1 min 50 s. Entra por `/tp` en la Granja del
  Molino y en Valdenieve (título completo; el segundo tras los 20 s), las dos descubiertas por el servidor en proceso y
  en `user://hud_discovered.cfg`, línea P3 al dejar el control militar, el cuerpo real del jugador a 25 m/s por la N‑140
  hasta el Área de descanso → cartel nacional (placa N‑140) en vez del título, perfil de cámara `default`, sin
  `SCRIPT ERROR`.
- `tests/net/run_discovery_test.sh --backend sqlite|file` (escenario `discovery`, `tests/net/net_steps_h2.gd`):
  **PASSED en los dos**: A descubre la granja (título completo; «zone discovered: granja_del_molino by A»), B recibe
  «A descubrió: Granja del Molino» (la espera por evento: con carga los dos clientes se desfasan segundos) y al llegar
  ve el título compacto sin pedir otro descubrimiento;
  `save-and-quit`, servidor nuevo: «discovery: 2 zones restored», `dbinfo` con `schema=3`, y C (jugador nuevo) ya la
  conoce y ve el compacto. `run_restart_test.sh` espera ahora `schema=3`.
  Pasa también con carga media 6–7 de otros carriles en la VM. Los `/tp` del guion van separados 1.2 s y se repiten si
  el jugador no llegó (el chat admite 2 líneas por segundo y con carga el cliente las agrupa).
- HUD: el `ZoneTracker` cuesta 12–15 µs/frame en el momento cargado del humo (lógica del HUD 0.17–0.21 ms, presupuesto
  0.5); `tests/hud_test.gd` 59/59.
- Capturas Forward+ a 1080p (`tests/h2_shots.gd`): `zone_card` (fotograma 2 de la maqueta v2 c, más `zone_card_t05` y
  `zone_card_t46`) y `zone_sign_vehicle`, en `docs/screenshots/h2/`.

#### Desviaciones

1. `zone_card` pone el título real de Las Torres sobre el claro de noche, como la maqueta (Altavega no tiene edificios
   hasta C1); `zone_sign_vehicle` pone al jugador de pie en la A‑14 donde está el móvil guionizado (no hay vehículos
   hasta M7).
2. Las zonas naturales conservan el título completo en la primera visita (C35 da un solo tipo de primera visita; el
   apéndice v1 las ponía compactas); las carreteras con nombre dan el cartel.
3. «SALIDA n» es el punto kilométrico sobre la traza de la carretera y el destino se mide a su centro; el nombre de la
   salida es la carretera del enlace, no un rótulo de V1.
4. Sin la bajada del ambiente de −4 dB del apéndice §5.6: no hay bus de ambiente todavía.
5. Solo el perfil de cámara `city` de W0; «Urbano bajo» / «Torres» de C28 y conservar el zoom relativo son de C0/C1
   (`scripts/world/city/camera_profile.gd`).
6. El «banner permanente del slice» ya no tenía interfaz desde H1; `RegionTracker` y `Events.region_changed` se quedan
   como dato (los usa el humo de M3), sin nadie que los dibuje.

#### Diferido

XP por descubrir (D2); revelar el mapa alrededor de lo descubierto y la niebla compartida (`shared_map`, H5); entrada
del diario; datos de territorio y facción, y «Saqueado 60 %» en la re‑entrada; zonas especiales como peligros (H3); el
vehículo real (M7: el umbral de velocidad ya lo cubre); el sonido definitivo y el bus de UI; `tr()` de las cadenas (H6).

---

### 9.9 Nota de implementación M6a (vinculante hasta que se revise)

Primer paso de §9.1 (pasos 6–7), §9.2, §9.3 y §9.4 sobre el kit listo para el corte urbano (§9.7; arte en ASSET_SPEC
v2 «M6a»), **sin** el generador de asentamientos (M6b / C3): una calle de datos colocada como un POI. Código en
`scripts/world/buildings/`.

**Datos y colocación.** `data/buildings/streets/<id>.json`: `center` (x, z de mundo, sobre un pad llano), `road`
(`half_len`, `half_width`, `sidewalk`), `lots` [{`template`, `style`, `pos` [x, z] desde el centro, `yaw` (0 = frente
+Z), `number`, `shop`}] y `signs` [{`board`, `pos`, `yaw`, `text`, `back`}] — el mismo formato que emitirá el
generador. `KitStreets` (nodo de `Game` tras `LootSpawns`, servidor y clientes) escucha `WorldStreamer.chunk_loaded`
y, al cargarse el chunk que contiene el centro, crea un `KitStreet` bajo `chunk.objects` (vive y muere con ese chunk;
la calle mide ~90 m, dentro del anillo de 5 × 5 de quien está en ella). `KitStreet` construye un edificio por frame
(`KitBuilding`), después los carteles y, en clientes con pantalla, la cinta de la calle (rodadas, nieve pisada,
bordillos y aceras: color de vértice, 1 *draw call*, sin sombra); en el servidor marca el navmesh del chunk
(`NavBaker.mark_dirty_key`). M6a: **`calle_mayor`** en el pad reservado de W1 `santa_maria_del_puerto` (−128, 3072;
C3): 7 edificios (las 5 plantillas en 3 estilos) y 3 carteles; no toca terreno ni *scatter* (el pad ya es llano y está
despejado). Llegar: `/tp -128 3072`.

**Identidad sin red.** Todo se construye igual en servidor y clientes con wids deterministas: edificio
`KitBuilding.wid_for(seed, street_id, i)` (`hash64` con `GEN_BUILDING`), puerta `KitDoor.wid_for(seed, wid_edificio,
n)` (`GEN_DOOR`), contenedores por `LootSpawns.attach` con el wid del edificio. No se replica ningún nodo: solo viajan
los deltas (`NetWorld.set_delta` / instantánea de chunk / evento en vivo).

**`KitBuilding`** (un `.glb` de `assets/models/buildings/<style>/<template>.glb`):
- metadatos de raíz del contrato de edificio de ciudad (`floors`, `floor_h` 3.0, `ground_h` 3.3, `foundation` 0.3,
  `kind`, `enterable`) leídos de los extras del `ShadowProxy`, que es `SHADOWS_ONLY` en todas partes;
- clientes con pantalla: `CityBuilding.attach` (materiales `world_vcol_struct` / `window_city`, registro en `CityCut`:
  el corte urbano actúa desde la calle y como «edificio propio»; proxy único que proyecta; rangos de visibilidad) y su
  `BuildingCutaway` pasa al `CutawayManager`; *headless*: los `_Stub` se ocultan;
- `KitDoor` en cada `Door_<n>`; `WindowBoxes` (un `StaticBody3D` con una caja por `Window_<n>`: los cristales
  bloquean hasta que haya ventanas rompibles);
- contenedores de `Spawn_Container_<n>` / `Spawn_Loot_<n>` (`LootSpawns.attach`, §9.6), **reparentados** bajo el
  `Interior<k>` de su planta para que el corte los oculte con ella;
- carteles en `Spawn_Sign_<n>` (número de casa, rótulo de tienda) hijos de su grupo de corte (el número del hastial
  se va con el `Roof`);
- servidor: un `Area3D` «refugio» (`collision_layer` 32, `collision_mask` 2 = jugadores) sobre las plantas → `Player.in_house` (contador por
  meta, como la cabaña del claro).

**Puertas (`KitDoor`, §9.2 primer paso).** `StaticBody3D` en la bisagra (el pivote de `Door_<n>` está en y = 0: el
shader de estructura lee la base del edificio de `MODEL_MATRIX[3].y`), caja de colisión en la hoja que gira con ella
(cerrada bloquea; abierta queda contra el muro), `InteractableComponent` (capa 8; acciones `use` / `open` / `close`;
«Abrir puerta» / «Cerrar puerta»). Servidor: `server_interact` (tras la validación normal de `request_interact`:
distancia 2.2 + 1.0 m) → `NetWorld.set_delta(wid, {open, swing})`, ruido de 6 m (`SoundEvents.Kind.DOOR`), `[EVT]
door %x open|closed by peer n`. Todos: `apply_net_delta` anima 0.35 s en vivo o coloca de golpe desde una instantánea
(quien llega tarde ve la puerta como está); las exteriores abren hacia dentro, las interiores hacia el lado contrario
de quien abre; `AudioManager.play(&"door_open" | &"door_close", pos)` (S1 pone los sonidos). Estados `locked`,
`broken`, `barricaded`, las acciones `force` / `break` / `lock` / `barricade` y el `NavigationLink3D` por puerta
quedan para M6b / M9.

**Corte (`CutawayManager`, §9.3).** Un nodo por mundo cliente (`CutawayManager.ensure`: hijo de `World`, de la escena
o de la raíz en tests), rejilla de registro de 32 m, sondeo a 10 Hz de los **pies del jugador local** (radio 30 m): el
edificio cuya huella y banda de planta los contiene recibe `apply_floor(k)`, el que se deja vuelve entero. Diferencias
con §9.3: se implementa sobre `BuildingCutaway` (§9.7) con `managed = true` y en modo **`SHADOW`**: lo oculto pasa a
`SHADOWS_ONLY` (o invisible si no proyectaba y un proxy lo hace por ello), nunca `visible = false` sobre algo que
proyecta — la habitación sigue a la sombra de su tejado (medido: razón 1.000). Reaplica con `camera_yaw_changed` y
cuando la cámara pasa a otro lado del edificio (tras un `/tp` o reaparecer dentro, la regla de fachadas usaba la cámara
vieja). Emite `inside_changed(inside, edificio, planta)` y `Events.shelter_changed`. El cursor todavía no cuenta (solo
los pies). **Sustituye a `PoiCutaway` en el mundo** (`world_chunk.gd`: `CutawayManager.attach`): `cabin_small` y
`lookout_tower` cortan ahora conservando la sombra; `PoiCutaway` queda para la comprobación de W0 en
`render_steps.gd`. La cabaña del claro sigue con su `Cutaway` (M6b: `house_hunter`).
Cambios aditivos en `building_cutaway.gd` (compartido con C0): `managed` (el `_process` propio no hace nada),
`Door_` / `Window_` con `cut_group` `Interior<k>` / `Floor<k>` se ocultan con su planta, `footprint_aabb()`,
`model_root()`.

**Carteles diegéticos (`SignText`).** Texto como **malla** compuesta con la fuente de mallas
`assets/models/signs/glyphs.glb` (Barlow Condensed SemiBold, altura de mayúscula 1): mayúsculas, líneas centradas,
comprimido al ancho del tablero, color de vértice lineal con el material compartido `world_vcol`; un `ArrayMesh` (1
*draw call*) por texto, cacheado. Sin `Label3D` ni atlas: igual en Forward+, Compatibility y Web, nítido a cualquier
distancia, iluminado como el tablero. `place()` pone `Text_0` / `Text_1` en los `TextPanel` del tablero
(`back = "strike"`: la barra roja del S‑500 por detrás). Altura de mayúscula 0.30–0.45 m (doc 10 §7.4).

**Pruebas y números** (VM compartida de 4 vCPU, `taskset`):
- `godot --headless --path . -s tests/m6a_checks.gd` (`tests/m6a_steps.gd`): **75 comprobaciones, 0 fallos** — la
  calle (7 edificios, metadatos, proxy, puertas y cajas de ventana, contenedores por planta, cortes gestionados, rótulo
  y números), `CutawayManager` en las plantas 0/1/2 y en una casa girada 180°, `shelter_changed`, puerta (abre hacia
  dentro, anima, cierra, delta, colocación desde delta), wids deterministas (la calle reconstruida da los mismos),
  cobertura de glifos, POIs `cabin_small` / `lookout_tower` con el tejado `SHADOWS_ONLY`.
- `tests/run_street_bench.sh gate` (xvfb, Compatibility; banco `tests/street_bench/` con el mismo `KitStreet`, la
  pila de render del juego, `CityCut`, `Silhouettes`, `CutawayManager`, jugador y 14 zombis): `citycut_probe` en la
  calle — **jugador visible 100 %** en las 15 filas vista × zoom (calle con la fila sur delante, patio trasero, hueco
  entre casas, plantas 0 y 1 de la casa de 2 plantas, planta 2 del bloque, casa sur; 16–38 m; puerta ≥ 99 % desde
  24 m) y **zombis legibles 100 %** en las vistas de calle a 24–38 m (puerta ≥ 95 %; cuentan los zombis a ≤ 14 m del
  jugador: los de detrás de otra casa ni se cortan ni se perciben, como en el banco de W0). **Sombra interior**: el
  suelo alrededor del jugador con el corte frente a solo los que proyectan: casa del kit **1.000** (×1.80 más oscuro
  que sin tejado), `cabin_small` **1.000** (×2.91); puerta ±5 %.
- Red: `tests/net/run_net_test.sh --clients 3 --duration 62 --soak 100 --scenario street --port 7877`
  (`tests/net/net_steps_m6a.gd`): A abre la puerta de la casa de 2 plantas, B la ve abrirse y la cierra, A lo ve y la
  reabre, C entra 34 s tarde y la encuentra abierta por la instantánea (0 eventos): **PASSED**.
- Capturas: `RENDER=forward tests/run_screenshots.sh docs/screenshots/m6a street_day street_night house_inside`
  (`tests/m6a_shots.gd`, en el mundo real); el banco da las mismas en Compatibility (`run_street_bench.sh shots`).

**Desviaciones.** Calle de datos a mano en vez del generador; sin cinta de carretera real (§9.1 paso 3: la de la calle
es solo visual y no aplana); la cabaña del claro sigue siendo la del slice (su sustitución por `house_hunter` pasa a
M6b); ventanas sin romper; puertas sin cerraduras ni `NavigationLink3D`; el corte no sigue al cursor; las
plantillas que faltan están en ASSET_SPEC «M6a.6». Aspecto pendiente (W0 / C0): dentro del pasillo del corte urbano, la
«planta legible» pinta la cara superior de los `_Stub` del kit (geometría real de 0.6 m, no un corte del shader) como
plano, y se ve una franja clara a lo largo del muñón del lado de la cámara (`house_inside.jpg`).

---
