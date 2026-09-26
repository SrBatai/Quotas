# 03 · Multijugador (1–4 jugadores) y servidores propios — Godot 4.7.2

> Investigación para VENTISCA (supervivencia invernal, mundo abierto, zombis) · Godot **4.7.2 stable** (GDScript) · fecha: 2026‑09‑24.
> Decisiones de diseño ya tomadas por el equipo y asumidas aquí: **cámara isométrica alta de seguimiento con apuntado por ratón** (la dirección de apuntado y el punto del cursor en el mundo se replican) y **cooperativo PvE para 1–4 jugadores con fuego amigo / PvP opcional por configuración del servidor** (la validación de daño jugador‑jugador existe siempre, pero se activa por config).

---

## 0. Resumen ejecutivo (decisiones recomendadas)

| Tema | Decisión | Por qué (en una línea) |
|---|---|---|
| Topología | **Servidor dedicado autoritativo** (export "dedicated server", headless Linux). "Crear partida" desde el juego = **lanzar ese mismo servidor como proceso hijo local** y conectarse a `127.0.0.1`. | Un solo camino de código (el servidor siempre es un proceso aparte), sin `call_local` ni dobles roles; el host puede cerrar el juego y dejar el servidor vivo. |
| Transporte | `ENetMultiplayerPeer` (UDP) con compresión `COMPRESS_RANGE_CODER`; canales: 0 movimiento/estado, 1 fiable (interacción, inventario, chat), 2 zombis (unreliable_ordered), 3 voz. | Es el camino soportado y probado de Godot; canales evitan bloqueo head‑of‑line. |
| Replicación | **Híbrida**: `MultiplayerSpawner` + `MultiplayerSynchronizer` para pocas entidades "caras" (jugadores, vehículos, objetos colocados, estado del mundo); **serialización propia (`PackedByteArray`)** para inputs con secuencia y para snapshots de zombis con cuantización e *interest management* por chunk. | El sincronizador es cómodo pero envía Variants sin cuantizar ni priorizar; con cientos de zombis se dispara el ancho de banda. |
| Tick | Física/servidor **60 Hz**; envío estado jugadores/vehículos **30 Hz**; zombis **10 Hz** (15 Hz cerca, 2–5 Hz lejos); mundo: al cambiar. | Presupuesto ≤ 20–30 kB/s de bajada por cliente (≈160–240 kbps), ≤ 3 kB/s de subida. |
| Netcode | Predicción cliente + reconciliación (inputs con `seq`), interpolación 100 ms para entidades remotas, **lag compensation acotada (≤ 200 ms)** para hitscan, validación de melee por cono/alcance en el servidor, proyectiles simulados determinísticamente en ambos lados desde el estado inicial. | Técnicas estándar (Valve/Overwatch/Gaffer) escaladas a 4 jugadores. |
| Vehículos | **Conductor autoritativo con validación** (velocidad máxima, sin teletransportes, colisiones con zombis resueltas por servidor); el servidor sigue siendo dueño del vehículo cuando nadie conduce. | Coop entre amigos: mejor sensación de conducción con mucho menos trabajo que predicción de cuerpos rígidos. Se puede endurecer más tarde. |
| Persistencia | **SQLite** vía `godot-sqlite` v4.9 (GDExtension, MIT, binarios compilados contra Godot 4.7.1) con WAL; autoguardado incremental de "dirty" cada 120 s + en eventos; perfiles de jugador por token. Fallback: JSON por chunk. | Actualizaciones parciales baratas, consultas, un solo fichero, robusto a cortes. |
| Hosting | Linux VPS 2 vCPU/4 GB (≈ 5–8 €/mes), Docker opcional, `systemd` con `Restart=always`, un puerto **UDP 7777** (+ TCP 7778 local para admin). Windows soportado (`--headless` en el export de Windows). | El servidor headless usa < 1 core y ~300–500 MB. |
| Descubrimiento | IP:puerto + contraseña (con *nonce* + HMAC, nunca en claro), descubrimiento LAN por broadcast UDP, **lista de servidores propia** vía HTTP (heartbeat cada 60 s), UPnP + relé (noray) para partidas alojadas por jugadores; Steam (GodotSteam) sólo si se publica en Steam. | Escalonado: lo simple primero, lo complejo sólo si hace falta. |
| Seguridad | Autoridad total del servidor (inventario, crafteo, daño, posición con límite de velocidad), rate‑limit por RPC, `auth_callback` con versión + contraseña + token; `pvp`/`friendly_fire` en `server.cfg`. | Coop ≠ sin trampas: basta con que un amigo use un script para arruinar la partida. |
| Chat | Texto v1 (RPC fiable canal 1). Voz v2 con TwoVoIP (Opus + RNNoise) relayada por el servidor en canal 3. | Voz añade complejidad (micro, GDExtension, permisos) y no bloquea nada. |
| Addons | `godot-sqlite` (sí), `netfox` (MIT; **no usar** el rollback completo, quizá `TickInterpolator`/`NetworkTime`; no verificado en 4.7), `GodotSteam` 4.20.x (sólo si Steam), `TwoVoIP` 6.x (v2). | Menos dependencias = menos riesgo de rotura al actualizar Godot. |
| Prueba de concepto | **Funciona en 4.7.2** (ver §12): servidor + 2 y 4 clientes headless, auth, spawn, sincronización 30 Hz, interest management con despawn/re‑spawn, RPC validado, chat relayado, PvP bloqueado por config, 75 s sin el "stall" reportado en 4.7.1; ≈ 3.5 kB/s por cliente con 4 jugadores. Hallazgo: `SIGTERM` mata el proceso headless sin apagado limpio → guardar vía socket de admin. | Base de código para la fase 0. |

---

## 1. Topología: dedicado vs. listen‑server

```
             Opción A (recomendada)                     Opción B (descartada)
  ┌─────────────┐   UDP 7777    ┌──────────────┐        ┌──────────────────────┐
  │ Cliente 1   │◄────────────►│              │        │ Proceso del host     │
  ├─────────────┤              │  Servidor     │        │  ┌─────────┐ ┌─────┐ │
  │ Cliente 2   │◄────────────►│  dedicado     │        │  │ servidor│ │cli 1│ │
  ├─────────────┤              │  (headless,   │        │  └─────────┘ └─────┘ │
  │ Cliente 3   │◄────────────►│  autoritativo)│        └──────────▲───────────┘
  ├─────────────┤              │              │                   │ UDP
  │ Cliente 4   │◄────────────►│  SQLite      │           cli 2, 3, 4
  └─────────────┘              └──────────────┘
  "Crear partida" = OS.create_process(mismo ejecutable, ["--headless","--","--server",...])
                    + conectarse a 127.0.0.1 como un cliente más.
```

**Recomendación: A.** Razones:

1. **Mismo camino de código.** El servidor nunca es "también un jugador": no hay RPC con `call_local`, no hay `if is_server() and also_player`. El PoC (§12) usa exactamente este esquema y el mismo `main.gd` sirve para ambos roles.
2. **Host desde el juego sin ramas especiales.** El menú "Crear partida" escribe un `server.cfg`, lanza el propio ejecutable del juego con `--headless -- --server --config <ruta>` (el export de cliente contiene todo el código del servidor; sólo pesa más por los assets) y se une a `127.0.0.1:7777`. Coste: un segundo proceso (~300–500 MB RAM, < 1 core). Ventajas: el host puede salir y dejar el servidor corriendo, y el servidor no sufre los *hitches* del render del host.
3. **Godot lo soporta oficialmente:** `--headless` funciona con el binario de export normal o con el export "dedicated server" (que además marca `OS.has_feature("dedicated_server")` y elimina visuales). Los docs señalan explícitamente que los ejemplos "asumen que el servidor es un jugador" y hay que adaptarlos para dedicado; nosotros partimos ya de dedicado.
4. **B sólo si** algún día hay que publicar en consola/Web donde no se puedan lanzar procesos hijos. Godot permite dos `MultiplayerAPI` en ramas distintas del árbol (`SceneTree.set_multiplayer(api, root_path)`), pero implicaría dos mundos en un proceso; no compensa.

Coste del modelo autoritativo: latencia perceptible en acciones no predichas (abrir puertas, coger objetos) = RTT. Con 4 amigos en la misma región (20–60 ms) se resuelve con *feedback optimista* en UI (animación local inmediata + confirmación) sin predecir el estado.

---

## 2. Godot 4.7 — API de alto nivel: qué hay, qué falla, cuándo hacer serialización propia

### 2.1 Piezas (verificadas en docs 4.7 y en el PoC)

| Pieza | Uso | Notas 4.7 |
|---|---|---|
| `ENetMultiplayerPeer` | `create_server(port, max_clients, max_channels, in_bw, out_bw)`, `create_client(addr, port, …, local_port)`. Peer 1 = servidor; clientes reciben ids aleatorios. Sólo UDP. `set_bind_ip()` para escuchar en una interfaz. | Compresión por host: `peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)` (la mejor para paquetes pequeños; ZSTD no compensa < 4 KB). DTLS disponible (`dtls_server_setup`). Estadísticas: `ENetPacketPeer.get_statistic(PEER_ROUND_TRIP_TIME / PEER_PACKET_LOSS…)`, `ENetConnection.pop_statistic(HOST_TOTAL_SENT_DATA…)` (usadas en el PoC para medir kB/s). |
| `SceneMultiplayer` | Implementación por defecto de `MultiplayerAPI`: RPCs, replicación, **autenticación** (`auth_callback`, `auth_timeout`=3 s, `send_auth`, `complete_auth`, `peer_authenticating`, `peer_authentication_failed`), `server_relay` (true: el servidor reenvía RPC cliente→cliente; **poner a `false`** en nuestro caso: todo pasa por lógica del servidor), `allow_object_decoding` (dejar `false`: deserializar objetos ejecuta código), `max_sync_packet_size` (1350 B) y `max_delta_packet_size` (65535 B), `refuse_new_connections`, `disconnect_peer(id)`, `send_bytes()/peer_packet` para paquetes crudos. | Se polea en `process_frame` (`SceneTree.multiplayer_poll`); se puede desactivar y llamar `multiplayer.poll()` en `_physics_process` para que RPC y física vayan en el mismo paso. |
| `@rpc(mode, sync, transfer, channel)` | `any_peer`/`authority`; `call_remote`/`call_local`; `reliable`/`unreliable`/`unreliable_ordered`; canal. Firma verificada por checksum: **todos los `@rpc` deben existir con la misma firma en ambos lados y el `NodePath` del nodo debe coincidir** (`multiplayer.get_remote_sender_id()` para saber quién llama). | 4.4 expuso `get_rpc_config()`/`get_node_rpc_config()`; 4.6 mejoró mensajes de error de RPC. |
| `MultiplayerSpawner` | `spawn_path`, lista `_spawnable_scenes` (auto‑spawn de hijos añadidos en la autoridad) o `spawn_function` + `spawn(data)` (spawn custom con datos). Señales `spawned`/`despawned` sólo en peers remotos. Gestiona *late join* (envía lo existente al que entra; verificado en el PoC). | **4.7.2 corrige** "peers dejan de replicar al borrar un nodo spawneado" (GH‑109864, `net_id` no único entre peers) → exigir ≥ 4.7.2. Abierto: carga las escenas spawnables **síncronamente** (GH‑102325) → precargar/mantener ligeras las escenas spawnables; no usar el spawner para niveles. |
| `MultiplayerSynchronizer` | `replication_config` (`SceneReplicationConfig`: por propiedad `spawn`, `replication_mode` = `NEVER`/`ALWAYS` (no fiable, cada frame de red)/`ON_CHANGE` (fiable, al cambiar)), `replication_interval`, `delta_interval`, `public_visibility`, `set_visibility_for(peer, bool)`, `add_visibility_filter(Callable)`, `visibility_update_mode` (IDLE/PHYSICS/NONE), `update_visibility()`. **El spawn/despawn de nodos spawneados sigue la visibilidad del sincronizador** → interest management "gratis" (verificado en el PoC). | No sincroniza `Object`/`Resource` ni ids únicos por peer; algunas propiedades nativas (p. ej. `CharacterBody3D.velocity`) no se pueden sincronizar directamente (GH‑68516) → espejarlas en variables de script. Límite práctico: ≤ 64 propiedades por sincronizador en `ON_CHANGE` (GH‑103938). **El orden de los nodos importa** (GH‑75884): el sincronizador de estado antes que el de inputs. Observado en el PoC: con `VISIBILITY_PROCESS_PHYSICS`, `visibility_changed` se emite **cada tick para el peer 0** y no para las transiciones por peer; usar `spawned/despawned` del spawner para reaccionar. |
| Autoridad | `Node.set_multiplayer_authority(id, recursive=true)`. Por defecto todo es del servidor (1). Patrón oficial: nodo raíz del jugador = servidor; un `MultiplayerSynchronizer` hijo "Inputs" con autoridad = cliente dueño (asignada en `_enter_tree` del jugador, antes de que el hijo entre al árbol). | GH‑101847: errores `get_cached_object` al borrar nodos con **cliente** como autoridad del spawner → mantener spawners siempre con autoridad servidor (nuestro diseño). GH‑86501: reparentar un nodo con sincronizador rompe la sync → no reparentar jugadores bajo vehículos; usar "asiento" por referencia. |
| Export dedicado | Preset con "Export as dedicated server": añade la *feature* `dedicated_server` y permite **Strip Visuals** (texturas/materiales → placeholders con dimensiones), **Keep** o **Remove**. Detectar por `OS.has_feature("dedicated_server")`, `DisplayServer.get_name() == "headless"` o `--server` en `OS.get_cmdline_user_args()`. | Los colliders importados de los `.glb` (`-convcolonly`) siguen presentes con Strip Visuals; los `MeshInstance3D` quedan sin píxeles. |

### 2.2 Cambios relevantes 4.2 → 4.7 (fuentes: CHANGELOG del repo y PRs con etiqueta `topic:multiplayer`)

- **4.3 (ago‑2024):** gran tanda de fixes de replicación: limpieza de la *scene cache* (GH‑87190/87186), `disconnect_peer` (GH‑91011), auth esperando confirmación (GH‑86260, 86257), spawner liberando nodos tras desconexión (GH‑92359), routing del relay con targets negativos (GH‑95194), DTLS con peers desconectados (GH‑95067). Editor: **Debug → Customize Run Instances** (varias instancias con argumentos por instancia).
- **4.4 (mar‑2025):** `get_rpc_config`/`get_node_rpc_config` (GH‑96024), UIDs de escena en `MultiplayerSpawner` (GH‑99137/99712), fix de RPC tras cambio de tipo de claves de diccionario (GH‑96915), tests unitarios de `SceneMultiplayer`; ENet destruye hosts explícitamente al cerrar (GH‑102861).
- **4.5 (sep‑2025):** fix de cache con spawners anidados (GH‑101416), tests de `MultiplayerSpawner`, normalización de parsing IP/IPv6 (GH‑114827), mbedTLS 3.6.5. Feature tags por instancia en "Run Instances".
- **4.6 (ene‑2026):** **Jolt es el motor 3D por defecto en proyectos nuevos** (los existentes no cambian; VENTISCA debería migrar a Jolt explícitamente y validar el `HeightMapShape3D`), mejores mensajes de error de RPC (GH‑109216), ENet: fix de fuga de peers en servidor DTLS (GH‑114834).
- **4.7 (18‑jun‑2026), 4.7.1 (jul), 4.7.2 (17/18‑ago‑2026):** sin cambios de API de red; 4.7.2 incorpora GH‑109864 (arriba). En `master` (4.8) se unifica la implementación de `Callable` de RPC (GH‑122422). **API estable desde 4.4 → bajo riesgo de rotura al actualizar.**

### 2.3 Bugs/limitaciones abiertos que nos afectan (estado a sep‑2026)

| Issue | Impacto en VENTISCA | Mitigación |
|---|---|---|
| GH‑122707 "Headless se atasca tras 25–55 s con cualquier escena principal" (4.7.1, Windows/WSL2; cerrado *not planned*) | Crítico si fuera real en Linux. | **No reproducido**: nuestro servidor 4.7.2/Linux corrió 75 s con escena principal a 60 fps/60 ticks (§12). Mantener el *soak test* en CI y vigilar en Windows. |
| GH‑102325 spawner carga escenas síncronamente | *Hitches* al spawnear escenas pesadas. | Precargar (`preload`) todas las escenas spawnables; zombis fuera del spawner (pool propio). |
| GH‑91869 Network Profiler infra‑reporta ancho de banda (~10×) | Medidas engañosas. | Medir con `ENetConnection.pop_statistic` (PoC) y con `ss`/Wireshark. |
| GH‑79246 breakpoints desconectan peers (timeouts ENet) | Depuración incómoda. | En desarrollo: `peer.get_peer(id).set_timeout(…)` alto o `--` flag `--net-dev-timeouts`. |
| GH‑97690 simplificación de paths ignora visibilidad; GH‑68508 sincronizadores hermanos con distinta `public_visibility` → error | Diseño de escenas. | Un sincronizador de estado por entidad, visibilidad decidida en el servidor, inputs en sincronizador separado con visibilidad sólo servidor. |
| GH‑121800 profiler cuenta mal `ON_CHANGE` | Cosmético. | — |

### 2.4 Cuándo escribir serialización propia

Usar RPC con un único `PackedByteArray` (o `SceneMultiplayer.send_bytes`) y `StreamPeerBuffer` (`put_u16`, `put_16`, `put_float`…) cuando:

1. **Muchas entidades** (zombis, drops): el sincronizador envía un paquete por nodo con Variants sin cuantizar (cabecera 4 B + `Vector3` 12 B + `float` 4/8 B…). Medido en el PoC: ≈1 kB/s por jugador remoto a 30 Hz con 3 propiedades `ALWAYS` (ENet agrupa varios syncs en un datagrama y el range coder ayuda). 200 zombis × 30 Hz así serían ~200 kB/s por cliente: inviable.
2. **Inputs con número de secuencia** (reconciliación) y *jitter buffer*.
3. **Cuantización/deltas/prioridad** (Gaffer: posición a 512 valores/m ≈ 2 mm en 18 bits; cuaternión "smallest three" 29 bits; bit "en reposo"; *priority accumulator* con presupuesto por paquete).
4. **Snapshots masivos** al entrar a un chunk (estado de cientos de objetos en un solo paquete fiable comprimido con `PackedByteArray.compress(FileAccess.COMPRESSION_ZSTD)`).

`var_to_bytes` es cómodo pero paga 4 B de cabecera por Variant; para paquetes calientes escribir campos a mano.

---

## 3. Netcode a nuestra escala (4 jugadores, cientos de zombis)

### 3.1 Reloj, ticks y latencias objetivo

- Servidor: `physics_ticks_per_second = 60` (ya en el proyecto). `Engine.max_fps = 60` en headless (sin vsync el bucle giraría al 100 % de CPU). Red poleada en `_physics_process` (`multiplayer_poll = false` + `multiplayer.poll()`) para que inputs y simulación estén alineados.
- Cliente: envía 1 input por tick de física (60 Hz, ~20–30 B → 1.5–2 kB/s subida). Puede agrupar 2 ticks por paquete (30 Hz) y **repetir los últimos 2–3 inputs en cada paquete** (redundancia estilo Overwatch/Quake) para que una pérdida no cree huecos.
- Estado jugadores/vehículos: 30 Hz (`replication_interval = 1/30`). Interpolación remota: 100 ms (Valve: 2 snapshots de margen a 20 Hz; a 30 Hz bastan 66–100 ms). Gaffer: a 10 pps hacen falta ~300 ms de buffer para sobrevivir 2 pérdidas seguidas; a 30 pps ~150 ms; a 60 pps ~85 ms.
- Overwatch: comando fijo de 16 ms, cliente adelantado ½ RTT + 1 frame (≈96 ms a 160 ms RTT), todo predicho por defecto, "favor the shooter" con rewind acotado. Nosotros: predecir **sólo movimiento y apuntado**; todo lo demás optimista‑en‑UI + confirmación.

### 3.2 Movimiento del jugador: predicción + reconciliación

```
cliente (60 Hz)                                   servidor (60 Hz)
 input{seq,move,aim_yaw,aim_pt,btn} ──unrel_ord──►  cola por jugador (jitter buffer 1–2 ticks)
 simula localmente (PlayerSim.step)                 PlayerSim.step(mismo código) → pos,vel
 guarda pending[seq]                                cada 2 ticks: state{ack_seq,pos,vel} ──► dueño
 al recibir state: descarta pending ≤ ack_seq;      cada 2 ticks: net_position, aim_yaw, aim_point,
   si |pos_pred − pos_srv| > 5 cm → pos = pos_srv     anim_state ──► todos (MultiplayerSynchronizer 30 Hz)
   y re‑simula pending (replay)
```

- `PlayerSim.step(body, cmd, dt)` es **una función pura compartida** (aceleración, gravedad, `move_and_slide`) sin leer `Input` ni `Inventory`; velocidad efectiva (`RUN_SPEED`, `FREEZING_SPEED_MULT`) la decide el servidor y la envía en el estado (el cliente predice con la última conocida).
- Validación servidor: `move.length() ≤ 1`, `seq` estrictamente creciente, no más de N inputs por segundo (descartar exceso), `aim_point` dentro de 40 m del jugador. El servidor **nunca** acepta posiciones del cliente.
- Cámara isométrica + ratón: `aim_yaw` (giro del `Visual`) y `aim_point` (punto del cursor en el terreno) viajan en el input; el servidor los clampa y los replica a los demás para orientar el modelo remoto, el arma y los efectos (linterna/mira).
- Terreno determinista por semilla en ambos lados → la predicción coincide salvo por objetos móviles; el umbral de 5 cm evita "snaps" por errores de coma flotante. En el PoC (sin replay, sólo umbral 1 m) el error máximo fue 0.33–0.47 m: coherente con 4 m/s × (33 ms de intervalo + ~60–80 ms de tubería); con replay de inputs pendientes el error cae a milímetros.

### 3.3 Entidades remotas: interpolación por snapshot

Buffer de 2–3 estados con marca de tiempo del servidor; renderizar `t_render = t_srv_estimado − 100 ms`; interpolar posición (lerp) y yaw (lerp_angle); extrapolar ≤ 100 ms si falta snapshot; `physics_interpolation` de Godot no sustituye esto (interpola entre ticks locales). Animación: enviar `anim_state: u8` (idle/walk/run/attack/hit/dead…) + `anim_speed` derivado de la velocidad; el animador procedural actual (fase por velocidad) se alimenta de la velocidad interpolada, no de la red.

### 3.4 Armas hitscan: lag compensation acotada

El servidor guarda un **historial de 1 s** (30 muestras a 30 Hz) de posición/yaw de cada entidad "impactable" (jugadores, zombis, vehículos). Al recibir `request_fire(seq, client_tick, aim_point)`:

1. Comprobar cadencia/munición/arma equipada (estado del servidor).
2. `t_disparo = client_tick − interp_delay(100 ms)`; acotar el rewind a **≤ 200 ms** (Valve usa hasta 1 s; con amigos y 4 jugadores 200 ms basta y limita el "me disparó desde detrás de la pared").
3. Rebobinar sólo los candidatos cercanos al rayo (bounding sphere), hacer el test cápsula‑rayo en GDScript (no rebobinar el `PhysicsServer`), aplicar daño, restaurar.
4. Origen del rayo = posición del jugador **en el servidor** + offset del arma; dirección = hacia `aim_point` validado. Nunca aceptar "he acertado a X".
5. Respuesta: `fire_result` al tirador (para el *hit marker*) y evento replicado a todos (sangre, sonido).

Fuego amigo/PvP: `if victim is Player and not cfg.pvp: no daño (pero sí feedback "aliado")`; con `pvp = true`, el mismo camino aplica daño (y se registra `attacker` para el mensaje de muerte). La validación existe siempre; sólo cambia la política.

### 3.5 Melee

`request_melee(seq)` → servidor: cooldown por arma, cono de 90° alrededor de `aim_yaw`, alcance `ATTACK_RANGE + 0.5 m` de tolerancia por latencia, rewind 100–150 ms de los objetivos; daño y `KNOCKBACK` aplicados en servidor; el cliente reproduce la animación de golpe inmediatamente (optimista).

### 3.6 Proyectiles (molotov, granadas, flechas)

Servidor: `ProjectileSpawner.spawn({id, origin, vel, tick})` (spawn custom por `MultiplayerSpawner.spawn_function`), sin sincronizar cada tick: ambos lados integran la trayectoria desde el estado inicial (determinista salvo colisiones con dinámicos). El cliente lanza una copia predicha al instante y la sustituye por la oficial al llegar (emparejando `seq`). El impacto lo decide el servidor y lo replica como evento (explosión, fuego).

### 3.7 Vehículos

| Opción | Pros | Contras |
|---|---|---|
| Servidor simula (`RigidBody3D`/`VehicleBody3D` con Jolt), conductor envía inputs, cliente interpola/extrapola | Autoritativo, anti‑cheat. | Conducir con RTT completo se siente "flotante" > 80 ms; predicción de cuerpo rígido en cliente = mucho trabajo. |
| **Conductor autoritativo con validación** (recomendada) | Conducción inmediata, simple (el vehículo cambia de autoridad al subir: `set_multiplayer_authority(peer)` del nodo del vehículo). Valheim usa este modelo de "propiedad" y va bien para 4 jugadores. | Trampas posibles del conductor (aceptable en coop); atropellos a zombis se validan en el servidor (posición/velocidad recibidas contra límites). |

Detalles: estado del vehículo a 30 Hz (`pos`, `rot` como cuaternión, `lin_vel`, `ang_vel`, `steer`, `throttle`) con extrapolación por velocidad en receptores; pasajeros no se reparentan (GH‑86501): el jugador guarda `vehicle_id + seat` y su cuerpo se desactiva; cuando nadie conduce, la autoridad vuelve al servidor (persiste posición). Validación: `speed ≤ v_max × 1.2`, desplazamiento por tick ≤ `v_max × dt × 1.5`, altura sobre terreno razonable; si falla → el servidor fuerza estado (snap) y cuenta infracción.

### 3.8 Zombis (cientos): IA sólo en servidor + snapshots comprimidos + interés

- **IA en el servidor** (`ZombieBrain` sin nodos visuales): estados idle/wander/chase/attack/hit/dead, `NavigationServer3D` (funciona headless) o *steering* como los lobos actuales. **LOD de IA**: cerca de un jugador (< 40 m) piensa a 10 Hz; 40–120 m a 2 Hz; > 120 m de todos, *dormido* (sin proceso, sin física; se reactiva al acercarse alguien o por ruido). Escalonar zombis por tick (round‑robin) → 300 zombis ≈ 30 actualizaciones/tick ≈ 1–2 ms de GDScript.
- **Replicación propia** (no `MultiplayerSpawner`): por peer, conjunto de interés = zombis en los chunks 3×3 alrededor (§4). Al entrar en el conjunto: mensaje fiable `zombie_enter{id, kind, pos, yaw, hp, state}`; al salir: `zombie_leave{id}`; el cliente mantiene un **pool** de vistas (modelo + animador) y recicla.
- **Snapshot** (canal 2, `unreliable_ordered`, ≤ 1200 B): `u8 tipo | u32 tick | por chunk: u16 chunk, u8 n, n × {u16 id, i16 dx, i16 dy, i16 dz (cm respecto al origen del chunk), u8 yaw (360/256°), u8 state|flags}` = **8 B/zombi**. Solo zombis que se movieron/cambiaron (dirty) + *keyframe* completo cada 1 s por chunk para cubrir pérdidas. Frecuencia por banda de distancia: < 30 m 15 Hz, 30–60 m 10 Hz, 60–100 m 4 Hz. Salud sólo `ON_CHANGE` (evento fiable), muerte = evento.
- Golpes a zombis: siempre servidor (§3.4/3.5); animación de reacción por `state`.

### 3.9 Presupuesto de ancho de banda por cliente (estimación + medidas)

| Flujo | Cálculo | kB/s |
|---|---|---|
| Estado de 3 jugadores remotos (30 Hz) | medido en PoC (3 props `ALWAYS` + cabeceras, con range coder): ≈ 1 kB/s por jugador | 3 |
| Estado propio (ack + pos/vel para reconciliación, 30 Hz) | 30 × ~40 B | 1.2 |
| Zombis, caso típico (60 en interés, media 8 Hz efectivos) | 60 × 8 × 8 B + cabeceras | 4–5 |
| Zombis, horda (200 en interés) | 200 × 10 × 8 B | 16 (pico; el presupuesto por paquete recorta a ~12) |
| Vehículos (1–2 en interés, 30 Hz × ~48 B) | | 1.5–3 |
| Mundo (puertas, contenedores, drops, tiempo/clima) | ráfagas al cambiar; join de chunk ≈ 2–10 kB comprimidos | < 0.5 media |
| Chat texto | despreciable | 0 |
| Voz (opcional, Opus 24 kbps por hablante) | 3 kB/s × hablantes | 0–9 |
| **Total bajada** | típico **10–15 kB/s (80–120 kbps)**; pico **≈ 30 kB/s (240 kbps)** | |
| **Subida** | inputs 60 Hz × ~30 B ≈ 1.8 kB/s (+ voz 3) | 2–5 |

Servidor: 4 clientes × 30 kB/s pico = 120 kB/s ≈ 1 Mbps; **tráfico mensual** con 4 jugadores 4 h/día ≈ 4 × 15 kB/s × 4 h × 30 d ≈ 26 GB/mes → cualquier VPS (Hetzner incluye 20 TB) sobra. Medidas del PoC (4 clientes moviéndose, 30 Hz, sin zombis): servidor **out 13.8–15.6 kB/s total, in 5.1 kB/s**.

Reglas: `SceneMultiplayer.max_sync_packet_size` = 1350 B (por debajo del MTU); paquetes propios ≤ 1200 B; nada fiable en el camino caliente.

---

## 4. Mundo abierto: chunks, interés, spawn por peer, persistencia

### 4.1 Chunks e interest management

- Mundo dividido en **chunks de 64 m** (id = `(cx, cz)` empaquetado en u32). Cada jugador tiene un conjunto de interés de **3×3 chunks** (radio efectivo ~96 m; la cámara isométrica ve ~35–45 m, el resto es margen para audio, luces y para no ver aparecer cosas).
- El servidor recalcula el conjunto por peer cada 0.5 s; la diferencia produce `enter`/`leave` (fiables). Para jugadores/vehículos/objetos colocados se implementa con `add_visibility_filter` en su `MultiplayerSynchronizer` (el spawner los crea/destruye en el cliente automáticamente; verificado en el PoC: despawn al alejarse > radio y re‑spawn con estado fresco al volver). Para zombis y drops, con la replicación propia de §3.8.
- **Objetos estáticos generados por semilla** (árboles, rocas, arbustos, coches abandonados, edificios) **no se replican**: el cliente los genera igual que el servidor. Sólo se replica su **delta** (árbol talado, arbusto cosechado, loot cogido, puerta abierta) como registro `wid → estado`, enviado al entrar en el chunk (snapshot del chunk) y como eventos al cambiar.
- Identidad estable de objetos: `wid` = hash(chunk, índice de generación) para lo procedural; ids de BD (autoincrement) para lo colocado por jugadores/drops. Los RPC de interacción viajan por `wid`, no por `NodePath` (así no dependen del árbol del cliente).

### 4.2 Estado que persiste en el servidor

| Dato | Formato | Frecuencia de guardado |
|---|---|---|
| Mundo global: semilla, día/hora, clima, versión de datos | tabla `world(key, value)` | cada autosave |
| Deltas de objetos procedurales (talado, cosechado, saqueado, puerta) | `deltas(wid PK, chunk, kind, state JSON, updated_at)` | dirty → autosave |
| Contenedores (armarios, camioneta, cajas) | `containers(wid PK, slots JSON)` | al cerrar el contenedor + autosave |
| Objetos colocados (fogatas, tiendas, cajas, barricadas) | `placed(id PK, kind, chunk, x,y,z,yaw, state JSON, owner)` | al colocar/cambiar |
| Vehículos | `vehicles(id PK, kind, x,y,z, rot(qx..qw), fuel, hp, inventory JSON)` | 60 s si se movió + al aparcar |
| Drops en el suelo | `drops(id PK, item, count, x,y,z, chunk, expires_at)` | dirty → autosave; caducan (p. ej. 30 min) |
| Zombis | **no** (se regeneran por reglas de densidad/tiempo); sí "muertos recientes" por chunk para no repoblar al instante | — |
| Jugadores | `players(token_hash PK, name, x,y,z, hp, warmth, hunger, inventory JSON, hand_tool, flags JSON, quests JSON, last_seen)` | al desconectar, cada 60 s si conectado, y en autosave |

### 4.3 Formato: SQLite (recomendado) vs JSON/binario

- **SQLite** con `godot-sqlite` (2shady4u; v4.9 del 9‑ago‑2026 compilada contra Godot 4.7.1, GDExtension para Linux/Windows/macOS/Android/iOS, MIT). API: `open_db`, `query_with_bindings`, `create_table`, `insert_row`, `select_rows`, `update_rows`, `verbosity_level`. Configurar `PRAGMA journal_mode=WAL; synchronous=NORMAL`. Escrituras del autosave en **una transacción** (miles de filas en pocos ms). Copia de seguridad diaria con `VACUUM INTO 'backup-YYYYMMDD.db'`. Incluir la `.so`/`.dll` en el export del servidor (y del cliente, que también la usa cuando aloja).
- **JSON/binario** (fallback sin dependencias): un fichero por chunk (`user://world/chunks/cx_cz.json`) + `players/<token>.json` + `world.json`; escritura atómica (escribir `.tmp` y `DirAccess.rename`). Con `var_to_bytes`/`bytes_to_var` es rápido pero opaco; con JSON es depurable. Problema: reescribir todo el fichero por cada cambio → agrupar por autosave. Aceptable para el vertical slice; SQLite en cuanto haya vehículos/bases.
- Autosave: cada **120 s** (configurable) + al desconectar un jugador + `save` por admin + al apagar. Migraciones por `PRAGMA user_version`.

### 4.4 Perfiles de jugador entre sesiones

El cliente genera en el primer arranque un **token aleatorio de 32 bytes** (`Crypto.generate_random_bytes(32)`) guardado en `user://identity.cfg`; el servidor guarda `sha256(token)` como clave del personaje. Reconexión = mismo personaje, mismo inventario, misma posición (con "gracia" de 60 s en la que el cuerpo sigue en el mundo). Cuentas reales sólo si algún día hay Steam (SteamID + ticket de sesión) o un servicio propio (fuera de alcance).

---

## 5. Hosting del servidor

### 5.1 Export y arranque

- Preset Linux x86_64 (y opcionalmente **arm64**: hay plantillas oficiales desde 4.3, útil para Hetzner CAX) con **"Export as dedicated server" + Strip Visuals**. Salida: `ventisca_server.x86_64` + `ventisca_server.pck` (o embebido). Windows: `ventisca_server.exe` con el mismo modo.
- Comando: `./ventisca_server.x86_64 --headless -- --server --config /srv/ventisca/server.cfg` (todo lo que va tras `--` llega en `OS.get_cmdline_user_args()`).
- `application/run/flush_stdout_on_print = true` para que `journald` reciba las líneas al momento; `debug/file_logging/enable_file_logging = true` para rotar logs en `user://logs`.
- CPU: con `Engine.max_fps = 60` el servidor del PoC usa < 5 % de un núcleo vacío; con 300 zombis prever 30–60 % de un núcleo. RAM: ~150 MB vacío; prever 300–500 MB con mundo cargado.
- Godot 4 carga X11/Wayland/ALSA/PulseAudio dinámicamente en tiempo de ejecución → `--headless` funciona en un contenedor `debian:bookworm-slim` sin librerías gráficas. Verificado: `ldd` del binario oficial 4.7.2 Linux x86_64 sólo lista `libc, libm, libdl, libpthread, librt` (libstdc++ va estático).
- **Señales (verificado en 4.7.2 Linux):** con `SIGTERM`/`SIGINT` el proceso headless **termina al instante** (exit 143/130) sin emitir `NOTIFICATION_WM_CLOSE_REQUEST` ni `NOTIFICATION_EXIT_TREE` → **no hay apagado limpio por señal**. Guardar antes de parar mediante el socket de admin (`ExecStop`) y acotar la pérdida con el autosave periódico.

### 5.2 `server.cfg` (formato `ConfigFile` de Godot)

```ini
[server]
name="Ventisca de Pedro"
password="cambia-esto"          ; vacío = sin contraseña
port=7777                       ; UDP
max_players=4
public=false                    ; anunciar en la lista de servidores
registry_url="https://lista.ventisca.example/api"
registry_key=""                 ; clave por servidor para el heartbeat
admin_tokens=["sha256-del-token-del-admin"]
motd="Abrígate."

[world]
seed=1337
save_path="user://world.db"
autosave_seconds=120
day_length_sec=420
difficulty="normal"
zombie_density=1.0
pvp=false                       ; daño jugador↔jugador con armas
friendly_fire=false             ; daño por explosiones/fuego/vehículos entre aliados
structure_damage=false          ; aliados pueden dañar construcciones

[net]
send_rate=30
zombie_rate=10
interest_chunks=1               ; radio en chunks (1 = 3×3)
max_kbps_per_client=300
admin_port=7778                 ; TCP, sólo 127.0.0.1
```

### 5.3 systemd (Linux)

```ini
# /etc/systemd/system/ventisca.service
[Unit]
Description=Ventisca dedicated server
After=network-online.target
Wants=network-online.target

[Service]
User=ventisca
WorkingDirectory=/srv/ventisca
ExecStart=/srv/ventisca/ventisca_server.x86_64 --headless -- --server --config /srv/ventisca/server.cfg
ExecStop=/srv/ventisca/admin.sh save-and-quit      ; guarda y cierra por el socket de admin antes del SIGTERM
Restart=always
RestartSec=5
TimeoutStopSec=30
Environment=HOME=/srv/ventisca                     ; user:// → ~/.local/share/Ventisca
Nice=-5

[Install]
WantedBy=multi-user.target
```

`journalctl -u ventisca -f` para logs. **Importante:** como Godot headless no procesa `SIGTERM` de forma limpia (§5.1), el `ExecStop` con `save-and-quit` por el socket de admin es el único apagado ordenado; `systemd` sólo envía `SIGTERM` si ese comando no termina en `TimeoutStopSec`. El autosave periódico acota la pérdida a ≤ 2 min ante un *crash* o un `kill` (`NOTIFICATION_CRASH` permite un último intento de volcado en crashes del motor, no en señales).

### 5.4 Docker

```Dockerfile
FROM debian:bookworm-slim
# el binario oficial sólo depende de glibc (ldd: libc, libm, libdl, libpthread, librt); ca-certificates para el heartbeat HTTPS
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*
RUN useradd -m ventisca
WORKDIR /srv/ventisca
COPY --chown=ventisca ventisca_server.x86_64 ventisca_server.pck libgdsqlite.linux.template_release.x86_64.so ./
USER ventisca
VOLUME ["/data"]                     # world.db, server.cfg, logs
EXPOSE 7777/udp
ENV HOME=/data
ENTRYPOINT ["./ventisca_server.x86_64", "--headless", "--", "--server", "--config", "/data/server.cfg"]
```

`docker run -d --name ventisca -p 7777:7777/udp -v /srv/ventisca-data:/data --restart unless-stopped ventisca:latest`. (Imágenes comunitarias de referencia: `briancain/GodotServer-Docker` (Ubuntu 24.04 + binario Godot + `--headless`), `robpc/godot-headless`.)

### 5.5 Puertos, firewall, admin, logs

- Abrir sólo **UDP 7777** (ENet). Si se usa lista de servidores, el heartbeat es saliente (HTTPS). Descubrimiento LAN: UDP 7776 broadcast.
- **Admin/RCON**: Godot no trae RCON. Implementar (a) comandos de chat `/kick /ban /save /time 8 /weather blizzard /give /tp /pvp on` autorizados por `admin_tokens`, y (b) un **socket TCP local** (`TCPServer` en `127.0.0.1:7778`, protocolo de líneas, token en la primera línea) para `systemd ExecStop`, cron y un script `admin.sh`. Nunca exponerlo a Internet (usar SSH).
- Logs: stdout → journald; además `user://logs/godot.log` rotado por Godot; eventos de juego (conexiones, muertes, guardados) con prefijo `[EVT]` para `grep`.
- Actualización: parar → sustituir binario/pck → `PRAGMA user_version` migra la BD al arrancar → arrancar. Versión de protocolo en el handshake (§7) evita clientes viejos.

### 5.6 Tamaño y coste del VPS (precios sep‑2026, **verificar**: Hetzner y OVH subieron precios en abril–junio de 2026 y varios planes CX/CAX aparecen "not available")

| Proveedor / plan | vCPU / RAM / disco | Tráfico | €/mes aprox. | Comentario |
|---|---|---|---|---|
| Hetzner CX23 (x86 compartido) | 2 / 4 GB / 40 GB | 20 TB | ~5.5 | Suficiente para 4 jugadores + 300 zombis. Precio pre‑subida; fuentes de sept‑2026 lo listan agotado en algunas regiones. |
| Hetzner CAX11 (ARM Ampere) | 2 / 4 GB / 40 GB | 20 TB | ~6 | Requiere export **linux arm64** (plantilla oficial) y binario arm64 de godot‑sqlite (existe). |
| Hetzner CX33 | 4 / 8 GB / 80 GB | 20 TB | ~6.5–?? | Fuentes contradictorias tras la subida de junio‑2026 (algunas hablan de >19 €). |
| OVH VPS‑1 | 4 / 8 GB / 75 GB | ilimitado (400 Mbps) | ~7.6 (antes 4.9) | Anti‑DDoS incluido; subida de abril‑2026. |
| OVH VPS‑2 | 6 / 12 GB | | ~10 | Sobredimensionado. |
| PC propio en casa (Linux o Windows) | — | — | 0 + luz | Abrir UDP 7777 en el router (o UPnP); mismo binario. |

Recomendación: **Hetzner CX23 o CAX11 (Falkenstein/Helsinki) para jugadores en Europa**; OVH VPS‑1 como alternativa con anti‑DDoS. Presupuestar **≈ 6–10 €/mes**. Un VPS de 1 vCPU/1–2 GB es demasiado justo por la IA de zombis en GDScript.

### 5.7 Windows

El export de Windows con "dedicated server" también corre con `--headless`. Para amigos que alojan en su PC: `ventisca_server.exe --headless -- --server --config server.cfg` en un `.bat`; como servicio: NSSM o Tarea programada al inicio. Windows Server en VPS cuesta 2–3× por licencia → sólo si ya se tiene.

---

## 6. Descubrimiento y conexión

| Mecanismo | Cómo | Cuándo |
|---|---|---|
| **IP:puerto + contraseña** | Campo en "Unirse"; lista de "recientes" en `user://servers.cfg`. Contraseña nunca en claro: el servidor envía un *nonce* en el handshake y el cliente responde `HMAC‑SHA256(password, nonce)` (`HMACContext`). | v1, siempre. |
| **LAN** | Cliente envía `VENTISCA?` por `PacketPeerUDP` con `set_broadcast_enabled(true)` a `255.255.255.255:7776`; cada servidor responde con `{name, port, players, max, version, has_password}`. (Android necesita permiso `CHANGE_WIFI_MULTICAST_STATE`; irrelevante aquí.) | v1 (barato). |
| **Lista de servidores propia** | Servicio HTTP mínimo (Go/Python/Worker) con `POST /heartbeat` cada 60 s `{key, name, port, players, max, version, password:bool, region}` (la IP la toma del emisor) y `GET /servers?version=`; caducidad 3 min. El servidor de juego usa `HTTPRequest`; el cliente muestra ping midiendo un `ENet` connect o un eco UDP. | v2, si hay comunidad. |
| **NAT en partidas alojadas por jugadores** | 1) Instrucciones de *port forwarding*; 2) `UPNP` de Godot (`discover()` + `add_port_mapping(7777, 7777, "Ventisca", "UDP")` **en un `Thread`**, renovar cada 5 min, `delete_port_mapping` al salir; no todos los routers lo permiten); 3) **relé**: `noray` (foxssake, MIT, Bun) hace *punchthrough* y relé UDP en un VPS propio (puertos 8890/tcp + 49152‑51200/udp); 4) `ENetMultiplayerPeer.create_client(..., local_port)` ayuda en *hole punching* manual. | Sólo si se quiere "host desde casa sin abrir puertos". Con servidores propios en VPS no hace falta. |
| **Steam (GodotSteam)** | GodotSteam 4.20.x (para Godot 4.7.x; repositorio movido a Codeberg, GitHub archivado sep‑2026) incluye `SteamMultiplayerPeer` desde 4.17: sustituye a ENet, aporta NAT traversal + relé (Steam Datagram Relay) gratis, lobbies, invitaciones y SteamID como identidad. Contras: requiere Steam en todos los clientes, licencia/AppID, y un servidor dedicado necesita GodotSteam Server (4.9.x). | Sólo si el juego se publica en Steam. Mantener la capa de transporte abstracta (`MultiplayerPeer`) para poder cambiar. |

Flujo de conexión (con autenticación de `SceneMultiplayer`):

```mermaid
sequenceDiagram
  participant C as Cliente
  participant S as Servidor
  C->>S: ENet connect (UDP 7777)
  S-->>C: send_auth(nonce)            %% peer_authenticating en ambos
  C->>S: send_auth({version, proto, name, token, hmac(pw, nonce)}) + complete_auth(1)
  alt versión/contraseña OK y hay hueco
    S->>S: complete_auth(id) → peer_connected(id)
    S->>C: spawn del jugador (MultiplayerSpawner) + snapshot de chunks de interés + world state
    C->>S: inputs 60 Hz … (juego)
  else rechazo
    S-->>C: send_auth("ERR:version 0.3 requerida") ; disconnect_peer(id)
    C->>C: muestra motivo (auth_callback) → connection_failed
  end
```

`auth_timeout` = 5 s; con 4 plazas usar `refuse_new_connections = true` al llenarse; `peer_authentication_failed` para registrar intentos.

---

## 7. Seguridad y anti‑trampas para cooperativo

1. **Autoridad del servidor en todo estado de juego**: inventario, crafteo, colocación, daño, salud/calor/hambre, hora/clima, loot, vehículos (con validación). El cliente sólo envía **intenciones** (inputs, `request_*`).
2. **Validación de cada RPC**: quién (`get_remote_sender_id()` == dueño), qué (ids existen, están en interés), dónde (distancia ≤ `range + tolerancia`), cuándo (cooldowns, `seq`), cuánto (cantidades ≤ stack, ≥ 0). Rechazos silenciosos + contador de infracciones por peer → *kick* al superar N (avisar por chat).
3. **Rate limiting** por peer y tipo: inputs ≤ 90/s, interact ≤ 5/s, chat ≤ 2/s (y ≤ 200 chars), crafteo ≤ 3/s; descartar el exceso.
4. **Límites de movimiento**: desplazamiento por tick ≤ `RUN_SPEED × dt × 1.5`; si el cliente pide teletransportes, el servidor ignora (nunca toma posiciones del cliente).
5. **Handshake**: versión del juego + versión de protocolo (constante `NET_PROTOCOL` incrementada en cada cambio incompatible de RPC/paquetes; además Godot ya rechaza RPC con firmas distintas), contraseña con nonce+HMAC, token de identidad; `allow_object_decoding = false`; `server_relay = false`.
6. **Listas**: `banned_tokens`, `banned_ips`; `admin_tokens` para comandos.
7. **Config de daño**: `pvp`, `friendly_fire`, `structure_damage` leídas por `DamageSystem.apply(attacker, victim, dmg, kind)`; la ruta de validación es idéntica con la política encendida o apagada (verificado en el PoC: `request_hit_player` → `BLOCKED (friendly_fire off)`).
8. **Sistema**: proceso sin privilegios, sólo UDP 7777 expuesto, admin por socket local; opcional DTLS de ENet si se quiere cifrar el tráfico (coste CPU pequeño; certificado autofirmado + `verify=false` en clientes de amigos).
9. Lo que **no** hacemos (por coste/beneficio en coop): ofuscación del cliente, detección de *aimbots*, kernel anti‑cheat.

---

## 8. Chat de texto y voz

- **Texto (v1)**: `say(text)` `any_peer` fiable canal 1 → el servidor sanea (longitud, caracteres de control), aplica rate limit y hace `broadcast_say(who, text)` a todos (`call_local` para que el host‑jugador lo vea si alguna vez es listen‑server). Historial de 100 líneas en el HUD, tecla Enter, `/comandos` para admin. Verificado en el PoC (mensajes relayados, canal separado).
- **Voz (v2)**: captura con `AudioEffectCapture` en un bus "Record" + `AudioStreamMicrophone`; codificación **Opus** con **TwoVoIP** (goatchurchprime; GDExtension con Opus + RNNoise/SpeexDSP; v6.6 compilada para Godot 4.6, sept‑2026 — comprobar carga en 4.7 vía `compatibility_minimum`), tramas de 20 ms (~60 B a 24 kbps) enviadas `unreliable` por canal 3 al servidor, que reenvía a los peers en interés (voz posicional: `AudioStreamPlayer3D` + `AudioStreamGenerator` por hablante). Alternativas: `microtaur/godot4-opus` (sólo códec), `ikbencasdoei/godot-voip` (antiguo). Complejidad media‑alta (permisos de micro, *push‑to‑talk*, jitter buffer de audio, sin soporte Web). Muchos grupos usan Discord: dejarlo para después del vertical slice.

---

## 9. Pruebas y herramientas

- **Local**: editor → **Debug → Customize Run Instances** (N instancias, argumentos y *feature tags* por instancia: instancia 1 `--server`, 2–4 `--client --name X`). Desde consola: `run_poc.sh` del PoC (1 servidor + N clientes headless).
- **CI headless** (GitHub Actions o similar con el binario 4.7.2): script tipo `tests/net/run_net_test.sh` que lanza servidor + 2–4 clientes headless con `--duration`, cada proceso imprime `RESULT OK/FAIL` y sale con código; el runner hace `grep` de `SCRIPT ERROR|ERROR:` (mismo estilo que `tests/run_smoke.sh`). Añadir un **soak** de 90 s del servidor con escena principal cargada (por GH‑122707).
- **Condiciones de red**: Linux `sudo tc qdisc add dev lo root netem delay 80ms 20ms distribution normal loss 2%` (en CI dentro de un contenedor con `NET_ADMIN`), Windows `clumsy`. O simulación en la app: cola de envío con retardo/pérdida configurables detrás de un flag (`--net-sim 80,20,2`) — netfox trae un simulador integrado si se adopta. Diseñar para **≤ 200 ms y 5–10 % de pérdida**.
- **Métricas en juego**: `ENetPacketPeer.get_statistic(PEER_ROUND_TRIP_TIME, PEER_PACKET_LOSS)` (loss sobre `PACKET_LOSS_SCALE`=65536) y `pop_statistic(HOST_TOTAL_SENT_DATA)` → HUD de depuración con RTT, pérdida, kB/s, entidades en interés, tamaño de la cola de inputs, correcciones de predicción/seg.
- **Network Profiler** del depurador de Godot: lista de nodos con RPC entrantes/salientes y un medidor de ancho de banda; útil para ver **quién** habla, pero **infra‑reporta** bytes (GH‑91869): no fiarse para el presupuesto.
- **Registro de replay**: grabar inputs + snapshots del servidor en fichero para reproducir bugs de desincronización.

---

## 10. Plan de migración de la arquitectura VENTISCA

### 10.1 Principio: un solo `game.tscn`, dos "sabores"

Los RPC exigen **NodePaths idénticos** en cliente y servidor. Por tanto: el mismo `game.tscn` se instancia en ambos; `game.gd` añade en tiempo de ejecución las ramas **sólo‑cliente** (`UI`, `CameraRig`, `Snowfall`, `Footprints`, efectos, `AudioManager` real) cuando no es servidor, y activa las **sólo‑servidor** (`Persistence`, `ZombieBrains`, `Spawners`) cuando lo es. Los nodos "compartidos" con RPC viven en rutas fijas: `/root/Game/Net` (conexión), `/root/Game/World/Players` (spawn_path), `/root/Game/WorldState`, `/root/Game/NetWorld` (interacción/crafteo), `/root/Game/Zombies`.

### 10.2 Qué pasa con cada autoload/sistema

| Actual (single‑player) | En multijugador | Dónde vive |
|---|---|---|
| `Events` (bus de señales) | Se mantiene, pero dividido semánticamente: señales de **presentación** (hover, toasts, camera_shake, quest_updated para HUD) sólo cliente; señales de **simulación** (`item_picked_up`, `tree_felled`, `stove_fueled`…) se emiten en el servidor **con el jugador como argumento** (`player: PlayerServer`) para que quests/estadísticas sean por jugador. El cliente recibe eventos replicados y re‑emite las señales de presentación. | Ambos |
| `GameState` (día/hora/clima, flujo de escenas) | Se parte en (a) `WorldState` **replicado** (nodo con `MultiplayerSynchronizer`: `day` ON_CHANGE, `hour` cada 5 s ON_CHANGE + reloj local extrapolando, `weather`, `wind_yaw`, `seed`) con autoridad servidor; el planificador de ventiscas corre sólo en servidor; y (b) `GameFlow` cliente (menús, pausa local sin `get_tree().paused`, muerte/respawn por RPC). Fin de partida ("día 6") deja de existir: mundo persistente; "victoria" → logros/objetivos opcionales. | WorldState: servidor→todos; GameFlow: cliente |
| `Inventory` (autoload, 10 huecos) | Deja de ser autoload. `InventoryComponent` **por jugador en el servidor** (hijo del nodo del jugador) con la misma API (`add/remove/count/has/hand_tool/equip_from_slot/use_slot…`) pero llamada sólo por lógica de servidor. Al dueño le llega un espejo de sólo lectura vía `MultiplayerSynchronizer` con visibilidad **sólo para su peer** (`public_visibility=false` + `set_visibility_for(owner,true)`): propiedad `slots_packed: PackedByteArray` ON_CHANGE (10 × (u16 id, u8 count)) + `hand_tool`, `has_coat`. El HUD lee el espejo. Acciones (equipar, comer, mover a contenedor) = `request_*` RPC. | Servidor + espejo en dueño |
| `QuestManager` | Por jugador en servidor (progreso guardado en perfil) o compartido por partida (decisión de diseño; recomendado **compartido** en coop: "objetivos del grupo"). Escucha señales de simulación; replica `quest_state: Dictionary` ON_CHANGE a todos. | Servidor → todos |
| `Assets` / `Placeholders` | Cliente completo. En el servidor (`dedicated_server`) `spawn_model` devuelve el mismo árbol (Strip Visuals ya vacía las mallas) — los **anchors y colliders siguen existiendo**, que es lo que la simulación necesita. | Ambos (visuales sólo cliente) |
| `AudioManager` | Sólo cliente; en servidor stub no‑op (ya lo es en v1). | Cliente |
| `player.gd` (movimiento) | Se divide: `PlayerSim` (función pura compartida), `PlayerInput` (cliente: lee acciones, cursor→`aim_point`, genera `cmd{seq…}`), `PlayerNet` (envío/recepción, predicción y reconciliación), `PlayerView` (cliente: `Visual`, `Animator`, `FootprintEmitter`, `BreathParticles`, `HoverRing`, `ToolHolder` visual). `Stats` (`player_stats.gd`) pasa **al servidor** (calor/hambre/salud calculados allí; el cliente recibe `stat_changed` replicado y muestra anillos/viñetas). | Sim: ambos; Input/View: cliente; Stats: servidor |
| `Interactor` (raycast + clic + auto‑walk) | Cliente: resuelve el `InteractableComponent` bajo el cursor (igual que hoy), muestra etiqueta/aro, hace auto‑walk **predicho**, y al llegar envía `NetWorld.request_interact(wid, action)`. El servidor valida y ejecuta `owner.server_interact(player, action)`; el resultado llega como cambio de estado replicado (árbol cae, contenedor se abre) + `interact_ok/denied` al solicitante. Los objetos exponen `wid` y separan `interact()` (v1) en `server_interact()` + `client_preview()`. | Cliente pide, servidor decide |
| `PlacementController` | Cliente: fantasma y validez local (misma función de validación que el servidor, para *feedback*); confirmación = `request_place(kind, pos, yaw)`; el servidor revalida (pendiente, distancia, bloqueadores, materiales) y **spawnea** el objeto vía `PlacedSpawner` (MultiplayerSpawner) + BD. | Cliente propone, servidor coloca |
| `craft_panel.gd` / `Recipes` | UI cliente; `Recipes.status(recipe, player)` se ejecuta en cliente con el espejo del inventario (para pintar botones) y **otra vez en servidor** al `request_craft(recipe_id)`; "requiere fuego cerca" lo comprueba el servidor con sus fogatas. | Ambos (decisión en servidor) |
| `Storage` (armario, camioneta, cajas) | Estado en servidor (BD); al abrir: `request_open_storage(wid)` → el servidor marca "abierto por X" (exclusión mutua: otro jugador ve "en uso"), y sincroniza sus 6 huecos sólo al peer que lo tiene abierto; `take/deposit` por RPC; cierre por distancia lo decide el servidor. | Servidor |
| `wolf.gd` → zombis, `wolf_spawner.gd` | `ZombieBrain` (servidor, sin visual) + `ZombieView` (cliente, pool). Spawner por reglas de densidad/chunk/hora en servidor. `deer.gd` igual (fauna). | Servidor / cliente |
| `weather.gd`, `day_night.gd`, `region_tracker.gd` | Weather: decisión en servidor, render en cliente; DayNight y RegionTracker: cliente (leen `WorldState` y la posición local). | Mixto |
| `terrain.gd`, `scatter.gd`, `respawner.gd` | Deterministas por `seed` en ambos lados; `respawner` (leña/piedra diaria) sólo servidor → crea `drops` replicados. Aplicar los **deltas** del chunk al instanciar en cliente (árbol ya talado → tocón). | Ambos / servidor |
| `game_over.gd`, `pause_menu.gd`, `hud` | Cliente. La pausa **no pausa el mundo**; "Reiniciar" desaparece; muerte → pantalla + `request_respawn`. | Cliente |
| `tests/smoke_test.gd` | Se mantiene para single‑player (el servidor local con 1 cliente **es** el modo single‑player en adelante; considerar un modo "sin red" con `OfflineMultiplayerPeer` para pruebas rápidas: `multiplayer.is_server()` es true y los RPC se ejecutan localmente). | — |

### 10.3 Orden de construcción

1. **Fase 0 — Esqueleto de red (1–2 semanas).** `Net` autoload (roles, `server.cfg`, auth con nonce/HMAC, host desde el juego con proceso hijo), `game.tscn` de doble sabor, `PlayerSpawner` + jugador con `ServerSync`/`InputSync`, `PlayerSim` compartido + predicción/reconciliación, `WorldState` replicado, chat, HUD de depuración de red, test headless en CI. *(El PoC de §12 cubre ~60 % de esto.)*
2. **Fase 1 — Mundo interactivo.** `wid` estables, deltas por chunk, `NetWorld.request_interact/craft/place`, `InventoryComponent` servidor + espejo, `Storage` con exclusión, stats en servidor, pickups como `drops` replicados, persistencia JSON provisional.
3. **Fase 2 — Zombis y combate.** `ZombieBrain` + LOD + replicación propia con interés por chunk, `ZombieView` con pool e interpolación, melee validado, hitscan con lag compensation acotada, proyectiles, `DamageSystem` con `pvp/friendly_fire`, muerte/respawn.
4. **Fase 3 — Vehículos y persistencia real.** Conductor autoritativo con validación, asientos sin reparentar, SQLite + autosave + migraciones + backups, reconexión con gracia.
5. **Fase 4 — Operación.** Export dedicado (Linux x86_64/arm64, Windows), Docker + systemd, socket admin + comandos, lista de servidores (HTTP), descubrimiento LAN, UPnP para host doméstico, métricas.
6. **Fase 5 — Extras.** Voz (TwoVoIP), Steam (GodotSteam) si procede, relé (noray).

### 10.4 Esqueletos GDScript

#### (a) Arranque del servidor / detección de rol — `scripts/autoload/net.gd` (autoload `Net`)

```gdscript
extends Node
# Autoload "Net": decide el rol y arranca. Mismo código en cliente, host‑desde‑el‑juego y dedicado.
enum Role { NONE, SERVER, CLIENT }
const GAME_VERSION := "0.3.0"
const NET_PROTOCOL := 3            # subir en cada cambio incompatible de RPC/paquetes
var role := Role.NONE
var cfg := ConfigFile.new()
var _nonces: Dictionary = {}       # peer_id -> PackedByteArray (servidor)
var _server_pid := -1              # proceso hijo cuando alojamos desde el juego
signal auth_failed(reason: String)

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if OS.has_feature("dedicated_server") or "--server" in args:
		start_server(_arg(args, "--config", "user://server.cfg"))

func start_server(cfg_path: String) -> Error:
	if cfg.load(cfg_path) != OK:
		push_warning("Sin %s; usando valores por defecto" % cfg_path)
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(cfg.get_value("server", "port", 7777), cfg.get_value("server", "max_players", 4))
	if err != OK:
		push_error("create_server: %s" % error_string(err)); get_tree().quit(2); return err
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = peer
	multiplayer.server_relay = false
	multiplayer.auth_timeout = 5.0
	multiplayer.auth_callback = _server_auth
	multiplayer.peer_authenticating.connect(func(id: int) -> void:
		_nonces[id] = Crypto.new().generate_random_bytes(16)
		multiplayer.send_auth(id, _nonces[id]))
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	role = Role.SERVER
	Engine.max_fps = 60                        # el bucle headless no tiene vsync
	get_tree().multiplayer_poll = false        # poleamos en _physics_process (inputs alineados con la física)
	get_tree().change_scene_to_file("res://scenes/main/game.tscn")
	return OK

func _physics_process(_dt: float) -> void:
	if role != Role.NONE and not get_tree().multiplayer_poll:
		multiplayer.poll()

func _server_auth(id: int, data: PackedByteArray) -> void:
	var d: Variant = JSON.parse_string(data.get_string_from_utf8())
	var reason := ""
	if typeof(d) != TYPE_DICTIONARY: reason = "handshake"
	elif d.get("proto") != NET_PROTOCOL or d.get("version") != GAME_VERSION: reason = "version:%s" % GAME_VERSION
	elif not _password_ok(id, d.get("hmac", "")): reason = "password"
	elif multiplayer.get_peers().size() >= cfg.get_value("server", "max_players", 4): reason = "full"
	if reason != "":
		multiplayer.send_auth(id, ("ERR:" + reason).to_utf8_buffer())   # el cliente lo lee en su auth_callback
		multiplayer.disconnect_peer(id)
		return
	Players.register(id, d.get("name", "?"), d.get("token", ""))       # perfil por sha256(token)
	multiplayer.complete_auth(id)

func _password_ok(id: int, hmac_hex: String) -> bool:
	var pw: String = cfg.get_value("server", "password", "")
	if pw == "": return true
	var h := HMACContext.new()
	h.start(HashingContext.HASH_SHA256, pw.to_utf8_buffer()); h.update(_nonces.get(id, PackedByteArray()))
	return h.finish().hex_encode() == hmac_hex

# "Crear partida": lanza este mismo ejecutable como servidor headless y nos unimos a él.
func host_from_game(cfg_path: String, password: String) -> void:
	_server_pid = OS.create_process(OS.get_executable_path(), ["--headless", "--", "--server", "--config", ProjectSettings.globalize_path(cfg_path)])
	await get_tree().create_timer(1.0).timeout
	join("127.0.0.1", 7777, password, "Anfitrión")
```

#### (b) Flujo de conexión del cliente (mismo `net.gd`)

```gdscript
func join(host: String, port: int, password: String, player_name: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(host, port)
	if err != OK: return err
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = peer
	multiplayer.auth_callback = func(_id: int, data: PackedByteArray) -> void:
		var s := data.get_string_from_utf8()
		if s.begins_with("ERR:"):
			auth_failed.emit(s.substr(4))          # "version:0.3.0", "password", "full"
			return
		var h := HMACContext.new()                 # data = nonce del servidor
		h.start(HashingContext.HASH_SHA256, password.to_utf8_buffer()); h.update(data)
		var payload := {"version": GAME_VERSION, "proto": NET_PROTOCOL, "name": player_name,
			"token": Identity.token_hex(), "hmac": h.finish().hex_encode()}
		multiplayer.send_auth(1, JSON.stringify(payload).to_utf8_buffer())
		multiplayer.complete_auth(1)
	multiplayer.connected_to_server.connect(func() -> void:
		role = Role.CLIENT
		get_tree().change_scene_to_file("res://scenes/main/game.tscn"))   # el spawner nos entregará nuestro jugador
	multiplayer.connection_failed.connect(func() -> void: Events.notify.emit("No se pudo conectar", 3.0))
	multiplayer.server_disconnected.connect(func() -> void: GameFlow.to_main_menu("Desconectado del servidor"))
	return OK
```

#### (c) Spawn del jugador con `MultiplayerSpawner` (servidor) y escena del jugador

```gdscript
# en Net (servidor)
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")   # precargada: el spawner carga síncrono
func _on_peer_connected(id: int) -> void:
	var p := PLAYER_SCENE.instantiate()
	p.name = str(id)                                   # nombre == peer dueño (convención)
	var profile := Persistence.load_player(Players.token_of(id))
	p.net_position = profile.position if profile else World.get_spawn_point()
	p.get_node("ServerSync").add_visibility_filter(Interest.player_filter(p))   # 3×3 chunks + siempre el dueño
	p.get_node("ServerSync").visibility_update_mode = MultiplayerSynchronizer.VISIBILITY_PROCESS_PHYSICS
	get_node("/root/Game/World/Players").add_child(p, true)   # el MultiplayerSpawner lo replica (y a los que entren después)

func _on_peer_disconnected(id: int) -> void:
	var p := get_node_or_null("/root/Game/World/Players/%d" % id)
	if p: Persistence.save_player(p); p.queue_free()   # despawn replicado
```

```
Player (CharacterBody3D) [player.gd: _enter_tree → $InputSync.set_multiplayer_authority(str(name).to_int())]
├── ServerSync (MultiplayerSynchronizer, autoridad 1, 30 Hz)   # ORDEN: antes que InputSync (GH‑75884)
│     net_position ALWAYS·spawn | aim_yaw ALWAYS | aim_point ALWAYS | anim_state ON_CHANGE | display_name ON_CHANGE·spawn | hp/warmth/hunger ON_CHANGE (visibilidad: dueño + interés)
├── InputSync (MultiplayerSynchronizer, autoridad = dueño, 30–60 Hz, public_visibility=false, visible sólo para 1)
│     (opcional: para movimiento usamos el RPC con seq de (d); InputSync sirve para inputs "lentos": aim, botones sostenidos)
├── Inventory (Node, servidor) + InventorySync (visible sólo para el dueño; slots_packed ON_CHANGE)
├── Shape, Stats (servidor), NearbyArea (cliente)
└── [cliente] Visual, Animator, Interactor, ToolHolder, Placement, FootprintEmitter, HoverRing, CameraRig
```

#### (d) Movimiento con autoridad de input + reconciliación — `scripts/player/player_net.gd`

```gdscript
extends Node
# Hijo del Player. Cliente dueño: predice y reconcilia. Servidor: aplica inputs validados.
const RATE := 60
@onready var body: CharacterBody3D = get_parent()
var owner_peer: int
var _seq := 0
var _pending: Array[PackedByteArray] = []     # inputs no confirmados (cliente)
var _queue: Array[Dictionary] = []            # inputs recibidos (servidor), jitter buffer
var _last_cmd := {"seq": 0, "move": Vector2.ZERO, "aim_yaw": 0.0, "aim": Vector3.ZERO, "btn": 0}
var _last_state_seq := 0

func _ready() -> void: owner_peer = str(body.name).to_int()
func is_owner() -> bool: return owner_peer == multiplayer.get_unique_id()

func _physics_process(dt: float) -> void:
	if multiplayer.is_server():
		var cmd: Dictionary = _queue.pop_front() if not _queue.is_empty() else _last_cmd   # sin input → repetir último
		while _queue.size() > 3: _queue.pop_front()                                         # el buffer no crece sin límite
		PlayerSim.step(body, cmd, dt)                       # mismo código que el cliente
		body.net_position = body.position
		body.aim_yaw = wrapf(cmd.aim_yaw, -PI, PI)
		body.aim_point = body.position + (cmd.aim - body.position).limit_length(40.0)
		_last_cmd = cmd
		if Engine.get_physics_frames() % 2 == 0:           # 30 Hz al dueño: ack + estado para reconciliar
			_state.rpc_id(owner_peer, cmd.seq, body.position, body.velocity)
	elif is_owner():
		var cmd := {"seq": _seq, "move": PlayerInput.move_vector(), "aim_yaw": PlayerInput.aim_yaw(),
			"aim": PlayerInput.cursor_world_point(), "btn": PlayerInput.buttons()}
		_seq += 1
		var packed := _pack(cmd)
		_pending.append(packed)
		PlayerSim.step(body, cmd, dt)                       # predicción
		_input.rpc_id(1, packed)                            # 60 Hz, unreliable_ordered, canal 0
	else:
		RemoteInterp.step(body, dt)                          # interpolación 100 ms hacia net_position/aim

@rpc("any_peer", "call_remote", "unreliable_ordered", 0)
func _input(bytes: PackedByteArray) -> void:
	if multiplayer.get_remote_sender_id() != owner_peer: return       # sólo el dueño manda inputs
	var cmd := _unpack(bytes)
	if cmd.is_empty() or cmd.seq <= _last_cmd.seq and not _queue.is_empty(): return   # duplicado/antiguo
	cmd.move = (cmd.move as Vector2).limit_length(1.0)                # validación
	_queue.append(cmd)

@rpc("authority", "call_remote", "unreliable_ordered", 0)
func _state(ack_seq: int, pos: Vector3, vel: Vector3) -> void:      # sólo llega al dueño
	if ack_seq <= _last_state_seq: return
	_last_state_seq = ack_seq
	while not _pending.is_empty() and _unpack(_pending[0]).seq <= ack_seq: _pending.pop_front()
	if body.position.distance_to(pos) > 0.05:                         # reconciliación: corregir y re‑simular pendientes
		body.position = pos; body.velocity = vel
		for p in _pending: PlayerSim.step(body, _unpack(p), 1.0 / RATE)

func _pack(c: Dictionary) -> PackedByteArray:   # 26 B: u32 seq | 2×i8 move | i16 aim_yaw | 3×i16 aim (cm rel.) | u8 btn
	var b := StreamPeerBuffer.new()
	b.put_u32(c.seq); b.put_8(int(c.move.x * 127)); b.put_8(int(c.move.y * 127))
	b.put_16(int(c.aim_yaw / PI * 32767)); var rel: Vector3 = (c.aim - body.position) * 100.0
	b.put_16(int(rel.x)); b.put_16(int(rel.y)); b.put_16(int(rel.z)); b.put_u8(c.btn)
	return b.data_array
func _unpack(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 14: return {}
	var b := StreamPeerBuffer.new(); b.data_array = bytes
	var seq := b.get_u32(); var mv := Vector2(b.get_8() / 127.0, b.get_8() / 127.0); var yaw := b.get_16() / 32767.0 * PI
	var aim := body.position + Vector3(b.get_16(), b.get_16(), b.get_16()) / 100.0
	return {"seq": seq, "move": mv, "aim_yaw": yaw, "aim": aim, "btn": b.get_u8()}
```

`PlayerSim.step(body, cmd, dt)` contiene exactamente la lógica de `player.gd._physics_process` actual (dirección relativa a la cámara la calcula ya el cliente: `cmd.move` viene en espacio mundo), sin leer `Input`, `Inventory` ni `GameState`; velocidad y multiplicadores los aporta `body.move_speed` (fijado por el servidor y replicado).

#### (e) RPC de interacción validado en servidor — `scripts/net/net_world.gd` (nodo `/root/Game/NetWorld`)

```gdscript
extends Node
const LATENCY_TOLERANCE := 1.0    # m extra sobre el range del InteractableComponent

@rpc("any_peer", "call_remote", "reliable", 1)
func request_interact(wid: int, action: StringName, arg: int = 0) -> void:
	if not multiplayer.is_server(): return
	var peer := multiplayer.get_remote_sender_id()
	var player: Node = Players.by_peer(peer)
	if player == null or not RateLimit.allow(peer, &"interact", 5.0): return
	var obj: Node = WorldRegistry.get_object(wid)                     # wid estable (semilla+índice o id de BD)
	if obj == null or not obj.has_method("server_interact"): return _deny(peer, wid, "no_existe")
	var comp: InteractableComponent = obj.get_meta("interactable")
	var d := Vector2(player.global_position.x, player.global_position.z).distance_to(
		Vector2(comp.global_position.x, comp.global_position.z))
	if d > comp.range + LATENCY_TOLERANCE: return _deny(peer, wid, "lejos")
	if comp.requires_tool != &"" and player.inventory.hand_tool() != comp.requires_tool: return _deny(peer, wid, "sin_herramienta")
	if not comp.can_interact(player): return _deny(peer, wid, "no_disponible")
	var result: Dictionary = obj.server_interact(player, action, arg)  # muta estado autoritativo; marca dirty (persistencia)
	interact_ok.rpc_id(peer, wid, action, result)                     # el cambio visible llega a todos por sync/eventos replicados

func _deny(peer: int, wid: int, reason: String) -> void:
	Infractions.note(peer, reason)
	interact_denied.rpc_id(peer, wid, reason)

@rpc("authority", "call_remote", "reliable", 1)
func interact_ok(wid: int, action: StringName, result: Dictionary) -> void:
	Events.interact_confirmed.emit(wid, action, result)               # cliente: cierra el "optimismo" de la UI

@rpc("authority", "call_remote", "reliable", 1)
func interact_denied(wid: int, reason: String) -> void:
	Events.notify.emit({"lejos": "Acércate", "sin_herramienta": "Necesitas un hacha", "no_disponible": "No disponible"}.get(reason, "No puedes hacer eso"), 2.0)
```

Cada objeto del mundo migra su `interact(player)` a `server_interact(player, action, arg) -> Dictionary` (misma lógica de hoy: golpes de hacha, leña a la estufa, coger bayas) y expone `wid`; el árbol al caer no llama a `Inventory.add`, sino a `player.inventory.add(...)` del servidor, que se refleja en el espejo del dueño.

---

## 11. Riesgos y mitigaciones

| Riesgo | Prob. | Impacto | Mitigación |
|---|---|---|---|
| Rendimiento de la IA de zombis en GDScript en un VPS de 2 vCPU | Media | Alto | LOD de IA + zombis dormidos + round‑robin; medir con 300 zombis desde la fase 2; opción C#/GDExtension para el `ZombieBrain` si hace falta. |
| Divergencia de predicción (terreno/objetos distintos entre cliente y servidor) | Media | Medio | Generación determinista por semilla + aplicar deltas antes de habilitar la predicción; umbral y suavizado de correcciones (0.95/0.85 como Gaffer). |
| Bugs del sincronizador con visibilidad/re‑entrada (histórico 4.2) | Baja | Alto | Verificado OK en 4.7.2 (PoC); test automático de re‑entrada en CI; fallback: replicación propia también para jugadores. |
| GH‑122707 (stall headless) en Windows | Baja | Alto | Soak test en Windows antes de ofrecer hosting Windows; recomendar Linux. |
| Cambio de precios/disponibilidad de VPS | Alta | Bajo | Docker + config → mover de proveedor en minutos; backups diarios de `world.db`. |
| Trampas de un jugador en coop | Media | Medio | Autoridad de servidor + validaciones + `pvp/friendly_fire` por config + kick/ban. |
| Dependencias GDExtension (godot‑sqlite, TwoVoIP) rompiéndose con Godot 4.8 | Media | Medio | Fijar versiones; fallback JSON para persistencia; voz opcional. |
| Reparentar jugador en vehículo rompe la sync (GH‑86501) | Alta si se hace | Medio | Diseño de asientos por referencia (nunca reparentar). |
| Paquetes > MTU fragmentados y perdidos | Media | Medio | ≤ 1200 B por paquete propio; `max_sync_packet_size` por defecto (1350). |

---

## 12. Prueba de concepto (scratchpad, fuera del repo)

Ruta: `/tmp/claude-0/-home-user-Quotas/3c3b507e-0838-5643-8cd6-6e5a40202a08/scratchpad/netpoc/` — `project.godot`, `main.tscn`, `main.gd`, `player.tscn`, `player.gd`, `run_poc.sh` (1 servidor + N clientes, procesos separados, Godot **4.7.2.stable.official** en Linux, `--headless`).

Qué prueba: `ENetMultiplayerPeer` + range coder; **autenticación** `SceneMultiplayer` (versión + contraseña + nombre; rechazo → `disconnect_peer`); `MultiplayerSpawner` con **late join**; jugador con `ServerSync` (autoridad servidor, `net_position`/`aim_yaw`/`aim_point` `ALWAYS` a 30 Hz, `display_name`/`hp` `ON_CHANGE`) e `InputSync` (autoridad cliente, visible sólo para el servidor); simulación en servidor a 60 Hz desde inputs; **predicción local + reconciliación** (umbral) e interpolación de remotos; **interest management** por distancia con `add_visibility_filter` (radio 15 m → despawn/re‑spawn); RPC `request_interact` validado por distancia (OK cerca, RECHAZO lejos); chat relayado por canal 1; `request_hit_player` bloqueado por `friendly_fire=false`; despawn limpio al desconectar; **soak de 75 s** del servidor con escena principal; medición de kB/s con `pop_statistic` y RTT con `get_statistic`.

Resultado: **PASA con 2 y con 4 clientes** (`POC PASSED`, exit 0 en todos los procesos, sin `ERROR`/`WARNING`). Líneas clave de la ejecución con 2 clientes:

```
[SERVER] t=  0.00 listening UDP 7777 | display=headless | dedicated_server feature=false | godot=4.7.2-stable (official) | friendly_fire=false
[SERVER] t=  1.53 auth OK peer 1445292103 name=A
[SERVER] t=  1.55 peer_connected 1445292103 -> spawning player
[SERVER] t=  2.57 request_interact from 1445292103 target=door_1 dist=1.00 -> OK
[SERVER] t=  3.52 auth OK peer 459893986 name=B
[SERVER] t=  5.00 alive wall=5.0s frames=303 physics_ticks=301 (expected~300) peers=2 net: out=1.9 kB/s in=1.4 kB/s
[SERVER] t=  6.55 request_interact from 1445292103 target=door_1 dist=10.80 -> REJECT
[SERVER] t=  6.55 request_hit_player from 1445292103 on 459893986 dmg=10 -> BLOCKED (friendly_fire off)
[SERVER] t= 15.02 alive wall=15.0s frames=904 physics_ticks=902 (expected~901) peers=2 net: out=4.5 kB/s in=2.6 kB/s
[CLIENT B] t=  0.03 connected_to_server, my id=459893986
[CLIENT B] t=  0.05 spawned node 459893986 (local=true) at (2.0, 0.0, 0.0)
[CLIENT B] t=  0.07 spawned node 1445292103 (local=false) at (0.0, 0.0, 0.0)      ← late join: recibe al jugador ya existente
[CLIENT B] t=  3.92 despawned node 1445292103                                      ← A se aleja > 15 m (interest management)
[CLIENT B] t=  6.42 spawned node 1445292103 (local=false) at (14.66666, 0.0, 0.0)  ← A vuelve: re‑spawn con estado fresco
[CLIENT A] t= 15.00 POC RESULT OK: remote_spawns=2 remote_despawns=1 interest_reentry_synced=true remote_moved=true remote_aim_synced=true rpc_near_ok=true rpc_far_rejected=true chat_relayed=true pvp_blocked=true local_reconcile_max_err=0.400m snaps=0 rtt=18ms
[CLIENT B] t= 15.00 POC RESULT OK: remote_spawns=2 remote_despawns=2 interest_reentry_synced=true remote_moved=true remote_aim_synced=true rpc_near_ok=true rpc_far_rejected=true chat_relayed=true pvp_blocked=true local_reconcile_max_err=0.333m snaps=0 rtt=21ms
POC PASSED
```

Soak (servidor solo, escena principal cargada, 4.7.2 Linux): sin atasco —

```
[SERVER] t= 25.05 alive wall=25.1s frames=1506 physics_ticks=1504 (expected~1503) peers=0
[SERVER] t= 50.07 alive wall=50.1s frames=3007 physics_ticks=3005 (expected~3003) peers=0
[SERVER] t= 70.10 alive wall=70.1s frames=4209 physics_ticks=4207 (expected~4205) peers=0
[SERVER] t= 75.01 server done, quitting
```

4 clientes (todos moviéndose, 30 Hz, sin zombis):

```
[CLIENT A] POC RESULT OK: remote_spawns=6 remote_despawns=3 interest_reentry_synced=true ... pvp_blocked=true local_reconcile_max_err=0.467m snaps=0 rtt=23ms
[CLIENT B] POC RESULT OK: remote_spawns=4 remote_despawns=3 ... rtt=20ms
[CLIENT C] POC RESULT OK: remote_spawns=4 remote_despawns=2 ... rtt=19ms
[CLIENT D] POC RESULT OK: remote_spawns=4 remote_despawns=3 ... rtt=20ms
[SERVER] t= 10.00 alive wall=10.0s frames=603 physics_ticks=601 (expected~600) peers=4 net: out=12.6 kB/s in=5.3 kB/s
[SERVER] t= 15.02 alive wall=15.0s frames=904 physics_ticks=902 (expected~901) peers=4 net: out=14.9 kB/s in=5.1 kB/s
POC PASSED
```

→ **≈ 3.2–3.7 kB/s de bajada y 1.3 kB/s de subida por cliente** con 4 jugadores en movimiento; RTT 17–23 ms en localhost; error máximo de predicción sin *replay* 0.33–0.47 m (esperable: 4 m/s × ~100 ms de tubería), 0 *snaps*.

Prueba de apagado (servidor solo): `kill -TERM` → exit 143 y `kill -INT` → exit 130 **inmediatos**, sin ninguna línea de `_notification` (ni `WM_CLOSE_REQUEST` ni `EXIT_TREE`) en el log → ver §5.1/§5.3.

Observaciones útiles: (1) `visibility_changed` sólo se emitió con `peer == 0` (cada tick en modo PHYSICS), no por transiciones de peer → reaccionar con `spawned/despawned`; (2) hay que **precargar** la escena del jugador (`preload`) y nombrar el nodo con el peer id **antes** de `add_child`; (3) la autoridad del `InputSync` se fija en `_enter_tree` del jugador; (4) `OS.has_feature("dedicated_server")` es `false` al ejecutar con el binario del editor (sólo el export dedicado lo activa) → detectar también por `--server`/`DisplayServer.get_name() == "headless"`; (5) las descargas desde la shell de este entorno están bloqueadas, así que **netfox no se pudo probar** en 4.7.2 (queda como tarea si se decide usarlo).

---

## 13. Fuentes consultadas

Documentación y código de Godot (vía GitHub, ya que docs.godotengine.org no era accesible desde este entorno):
- High‑level multiplayer — https://raw.githubusercontent.com/godotengine/godot-docs/master/tutorials/networking/high_level_multiplayer.rst
- Exporting for dedicated servers — https://raw.githubusercontent.com/godotengine/godot-docs/master/tutorials/export/exporting_for_dedicated_servers.rst
- Debugging tools (Customize Run Instances) — https://raw.githubusercontent.com/godotengine/godot-docs/master/tutorials/scripting/debug/overview_of_debugging_tools.rst
- Binary serialization API — https://raw.githubusercontent.com/godotengine/godot-docs/master/tutorials/io/binary_serialization_api.rst
- Clases 4.7: MultiplayerSynchronizer, MultiplayerSpawner, SceneMultiplayer, SceneReplicationConfig — https://github.com/godotengine/godot/tree/4.7/modules/multiplayer/doc_classes ; ENetMultiplayerPeer, ENetConnection, ENetPacketPeer — https://github.com/godotengine/godot/tree/4.7/modules/enet/doc_classes ; UPNP — https://github.com/godotengine/godot/blob/4.7/modules/upnp/doc_classes/UPNP.xml ; PacketPeerUDP, SceneTree, Engine — https://github.com/godotengine/godot/tree/4.7/doc/classes
- CHANGELOG 4.7/4.6/4.5/4.4 — https://github.com/godotengine/godot/blob/4.7/CHANGELOG.md (y ramas 4.6, 4.5, 4.4)
- Release 4.7‑stable — https://github.com/godotengine/godot/releases/tag/4.7-stable ; resúmenes de 4.7 y 4.6: https://80.lv/articles/godot-4-7-has-been-released , https://godotlearning.com/blog/godot-4-7-whats-new , https://www.strayspark.studio/blog/godot-46-jolt-physics-migration-guide
- PRs `topic:multiplayer` 4.3–4.6 (búsqueda GitHub), p. ej. https://github.com/godotengine/godot/pull/109864 , /pull/96024 , /pull/99137 , /pull/101416 , /pull/109216 , /pull/114834 , /pull/122422
- Issues: https://github.com/godotengine/godot/issues/122707 , /issues/102325 , /issues/91869 , /issues/75884 , /issues/103938 , /issues/75264 , /issues/68516 , /issues/101847 , /issues/97690 , /issues/93254 , /issues/86501 , /issues/79246 , /issues/68508 , /issues/121800 , /issues/109432 , /issues/28582 , /issues/102914

Netcode (artículos/charlas):
- Gaffer On Games — Snapshot Interpolation, Snapshot Compression, State Synchronization (espejo en GitHub): https://github.com/mas-bandwidth/gafferongames/blob/master/content/post/snapshot_interpolation.md , …/snapshot_compression.md , …/state_synchronization.md
- Valve, Source Multiplayer Networking (espejo): https://gist.github.com/CoolOppo/fe0586836de3fb2f90f9 (original: https://developer.valvesoftware.com/wiki/Source_Multiplayer_Networking)
- Overwatch Gameplay Architecture and Netcode (GDC 2017, Tim Ford): https://www.gdcvault.com/play/1024001/-Overwatch-Gameplay-Architecture-and ; resúmenes: https://gamedev.net/forums/topic/696756-command-frames-and-tick-synchronization/ , https://www.gamedev.net/forums/topic/701388-overwatch-predicted-rockets-analysis/
- Postmortems/arquitecturas de supervivencia coop: Project Zomboid "Zed OwnerZhip"/"OwnerZhip" — https://projectzomboid.com/blog/news/2020/06/zed-ownerzhip/ , https://projectzomboid.com/blog/news/2021/04/ownerzhip/ ; Valheim (ZDO, propiedad de zonas) — https://edgegap.com/blog/valheim-multiplayer-game-backend-deep-dive , https://github.com/bpage-dev/valheim-server-zone-ownership ; Don't Starve Together (predicción de movimiento/"lag compensation") — https://support.klei.com/hc/en-us/articles/360029555272-Network-and-Performance-Troubleshooting-Guide

Addons y herramientas:
- netfox — https://github.com/foxssake/netfox (README, tags/releases) ; noray — https://github.com/foxssake/noray
- godot‑sqlite — https://github.com/2shady4u/godot-sqlite (README, releases/tags: v4.9, 2026‑08‑09, Godot 4.7.1)
- GodotSteam — https://github.com/GodotSteam/GodotSteam (archivado; ahora https://codeberg.org/godotsteam/godotsteam), blog: https://godotsteam.com/blog/2026/07/16/all-the-releases/ , https://godotsteam.com/blog/2026/06/24/new-godot-new-godotsteam-and-more/ ; alternativas: https://github.com/expressobits/steam-multiplayer-peer
- TwoVoIP — https://github.com/goatchurchprime/two-voip-godot-4 (releases 6.4–6.6, Godot 4.6) ; https://github.com/microtaur/godot4-opus ; https://github.com/ikbencasdoei/godot-voip
- Docker/hosting: https://github.com/briancain/GodotServer-Docker (ubuntu.Dockerfile) , https://github.com/robpc/docker-godot-headless , https://gameye.com/blog/godot-dedicated-server-hosting/
- Simulación de red / testing: https://forum.godotengine.org/t/how-do-i-reproduce-ping-packet-loss-and-general-latency-for-multiplayer-game-testing-locally/86334 , https://studios.ptilouk.net/little-brats/blog/2024-10-23_netcode.html , https://medium.com/@florian-trautweiler/launch-arguments-in-godot-4-3-accelerate-multiplayer-development-05fb6a7f94aa

Precios (sep‑2026; contradictorios entre fuentes tras las subidas de 2026 — verificar antes de contratar):
- Hetzner: https://www.hetzner.com/cloud/ (bloqueado desde aquí), https://docs.hetzner.com/general/infrastructure-and-availability/price-adjustment/ , https://betterstack.com/community/guides/web-servers/hetzner-cloud-review/ , https://comparedge.com/tools/hetzner/pricing , https://costgoat.com/pricing/hetzner
- OVH: https://www.ovhcloud.com/en/vps/ , https://learnwithhasan.com/vps-providers/ovh-vps/ , https://abdulkadersafi.com/blog/vps-prices-are-rising-everywhere-in-2026-hetzner-ovhcloud-hostinger
