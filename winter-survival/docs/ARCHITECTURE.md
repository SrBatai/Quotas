# VENTISCA — Technical Architecture

Godot **4.7.2**, GDScript, project root `winter-survival/` (`winter-survival/project.godot`). Companion docs: `GDD.md` (design, Spanish, all numbers and UI strings) and `ASSET_SPEC.md` (3D asset contract). The code agent implements **everything in this document**; the 3D agent produces the `.glb` files in parallel. **Code must never depend on a .glb being present** (see §18, fallbacks).

Terminology: "Godot units" = meters, Y up, **−Z is forward**. All in-game text is Spanish (copy strings verbatim from the GDD).

---

## 1. Principles

1. **Runs headless and in Compatibility.** Only features available in the `gl_compatibility` renderer are used for core behavior: `DirectionalLight3D` + `OmniLight3D`, `WorldEnvironment` with `ProceduralSkyMaterial`, exponential depth fog, **`CPUParticles3D`** (never `GPUParticles3D`), `StandardMaterial3D`, canvas shaders. No `Decal`, no `FogVolume`, no SDFGI/SSAO/SSR, no `GeometryInstance3D.transparency` dependence.
2. **Mouse-first interaction.** A camera→cursor raycast resolves a hovered `InteractableComponent`; LMB interacts (auto-walking there if far). Every interactable declares its label text.
3. **Data-driven balance.** All numbers live in `scripts/data/balance.gd` (`class_name Balance`, constants) and items/recipes/quests in `scripts/data/*.gd`. The GDD numbers are the source of truth; constant names are listed in §5.
4. **Signal bus.** Cross-system communication goes through the `Events` autoload. Nodes never reach into siblings' internals except parent→child.
5. **Asset loader with placeholders.** `Assets.spawn_model(name)` always returns a usable `Node3D` with the anchor nodes the code needs.
6. **Static typing everywhere**, `class_name` on reusable scripts, `@export` for tunables, `_unhandled_input` for gameplay input so UI (`Control`) consumes clicks first.

---

## 2. Folder layout

```
winter-survival/
├── project.godot
├── icon.svg                       # simple snowflake, hand-written SVG
├── export_presets.cfg             # optional (Linux/Windows presets)
├── .gitignore                     # .godot/, *.import for nothing else, /tmp
├── docs/                          # GDD.md, ARCHITECTURE.md, ASSET_SPEC.md
├── assets/
│   ├── models/                    # *.glb written by the 3D agent (see ASSET_SPEC)
│   ├── icons/                     # *.svg written by the code agent (§19)
│   ├── materials/                 # .tres materials built in code or saved (terrain, ice, ghost, glow)
│   ├── shaders/frost_vignette.gdshader
│   └── themes/ui_theme.tres       # panel styles, fonts sizes (built once, reused)
├── blender/                       # 3D agent territory (scripts + sources), see ASSET_SPEC
├── scenes/
│   ├── main/       main_menu.tscn, game.tscn
│   ├── player/     player.tscn
│   ├── actors/     wolf.tscn, deer.tscn
│   ├── world/      world.tscn, cabin.tscn, a_frame_cabin.tscn, pickup_truck.tscn, signpost.tscn,
│   │               fence.tscn, tree.tscn, stump.tscn, rock.tscn, berry_bush.tscn, pickup.tscn,
│   │               campfire.tscn, wood_stove.tscn, cabinet.tscn, furniture.tscn (generic decor)
│   ├── effects/    snowfall.tscn, fire_effect.tscn, smoke_effect.tscn, hit_puff.tscn, footprints.tscn
│   └── ui/         hud.tscn, ring_meter.tscn, day_clock.tscn, hotbar.tscn, hotbar_slot.tscn,
│                   category_bar.tscn, craft_panel.tscn, storage_panel.tscn, quest_panel.tscn,
│                   region_banner.tscn, toast.tscn, pause_menu.tscn, game_over.tscn, controls_panel.tscn
├── scripts/
│   ├── autoload/   events.gd, game_state.gd, inventory.gd, assets.gd, audio_manager.gd, quest_manager.gd
│   ├── data/       balance.gd, items.gd, recipes.gd, quests.gd, regions.gd, placeholders.gd
│   ├── components/ interactable.gd, health.gd, storage.gd, fuel_burner.gd, heat_zone.gd, hover_ring.gd
│   ├── player/     player.gd, player_stats.gd, player_animator.gd, interactor.gd, camera_rig.gd,
│   │               tool_holder.gd, footprint_emitter.gd, placement_controller.gd
│   ├── actors/     wolf.gd, deer.gd, quadruped_animator.gd, steering.gd
│   ├── world/      world.gd, terrain.gd, scatter.gd, day_night.gd, weather.gd, wolf_spawner.gd,
│   │               deer_spawner.gd, region_tracker.gd, cabin.gd, cutaway.gd, tree.gd, rock.gd,
│   │               berry_bush.gd, pickup.gd, campfire.gd, wood_stove.gd, cabinet.gd, signpost.gd,
│   │               wall_clock.gd, lantern.gd, bounds.gd, respawner.gd
│   ├── effects/    fire_effect.gd, light_flicker.gd, snowfall.gd, camera_shake.gd
│   ├── ui/         hud.gd, ring_meter.gd, day_clock.gd, hotbar.gd, hotbar_slot.gd, category_bar.gd,
│   │               craft_panel.gd, storage_panel.gd, quest_panel.gd, region_banner.gd, toast.gd,
│   │               pause_menu.gd, game_over.gd, main_menu.gd, ui_icons.gd
│   └── main/       game.gd
└── tests/
    ├── smoke_test.gd               # SceneTree script, headless
    ├── screenshot.gd               # SceneTree script, xvfb + Compatibility
    ├── inspect_models.gd           # prints node tree of every .glb (shared with the 3D agent)
    ├── run_smoke.sh
    └── run_screenshots.sh
```

---

## 3. `project.godot` essentials

```ini
[application]
config/name="Ventisca"
run/main_scene="res://scenes/main/main_menu.tscn"
config/features=PackedStringArray("4.7", "Forward Plus")
config/icon="res://icon.svg"

[autoload]                      ; order matters
Events="*res://scripts/autoload/events.gd"
GameState="*res://scripts/autoload/game_state.gd"
Inventory="*res://scripts/autoload/inventory.gd"
Assets="*res://scripts/autoload/assets.gd"
AudioManager="*res://scripts/autoload/audio_manager.gd"
QuestManager="*res://scripts/autoload/quest_manager.gd"

[display]
window/size/viewport_width=1280
window/size/viewport_height=720
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"

[rendering]
renderer/rendering_method="forward_plus"
renderer/rendering_method.mobile="gl_compatibility"
anti_aliasing/quality/msaa_3d=1                  ; 2x
lights_and_shadows/directional_shadow/size=2048
lights_and_shadows/directional_shadow/soft_shadow_filter_quality=2
textures/default_filters/anisotropic_filtering_level=0
environment/defaults/default_clear_color=Color(0.79, 0.85, 0.92)

[physics]
common/physics_ticks_per_second=60
3d/default_gravity=9.8

[layer_names]  ; see §9
3d_physics/layer_1="world"
3d_physics/layer_2="player"
3d_physics/layer_3="animals"
3d_physics/layer_4="interactable"
3d_physics/layer_5="heat"
3d_physics/layer_6="shelter"
3d_physics/layer_7="placement_blocker"
```

Input map: §8. Anything the CLI passes (`--rendering-method gl_compatibility`) overrides the project setting, which is how tests run here.

---

## 4. Autoloads

| Autoload | File | Responsibility |
|---|---|---|
| `Events` | `scripts/autoload/events.gd` | Pure signal bus (§7). No logic. |
| `GameState` | `scripts/autoload/game_state.gd` | Run state: `day: int`, `hour: float` (0–24), `is_night: bool`, `weather: StringName` (`&"clear"`/`&"blizzard"`), `time_scale`, `is_paused`, `is_game_over`, `death_cause`, `best_days` (from `user://best.cfg`). Advances time in `_process` (only when a game is running and not paused): `hour += delta * 24.0 / Balance.DAY_LENGTH_SEC`; rolls day at 06:00; emits `Events.time_changed`, `day_started`, `night_started`; checks win (day 6 at 06:00). Scene flow: `start_game()`, `restart()`, `to_main_menu()`, `game_over(cause)`, `win()` (use `get_tree().change_scene_to_file`). Also `set_time(day, hour)` for tests. |
| `Inventory` | `scripts/autoload/inventory.gd` | 10 slots: `slots: Array[Dictionary]` (`{"id": StringName, "count": int}` or `{}`), slot 0 = HAND (tools only). API: `add(id, n) -> int` (returns leftover), `remove(id, n) -> bool`, `count(id) -> int`, `has(id, n=1)`, `hand_tool() -> StringName` (`&""` if empty), `equip_from_slot(i)` (swap with slot 0), `use_slot(i)` (eat if food), `eat_best() -> bool`, `take_from_container(storage, slot, all)`, `deposit_to_container(storage, slot, all)`, `clear()`. Emits `Events.inventory_changed`, `item_picked_up`, `item_consumed`, `tool_changed`. Also holds `has_coat: bool`. |
| `Assets` | `scripts/autoload/assets.gd` | `spawn_model(name: String) -> Node3D` (§18), `has_model(name)`, material helpers (`get_glow_material()`, `get_ghost_material(valid)`), caches `PackedScene`s. |
| `AudioManager` | `scripts/autoload/audio_manager.gd` | `play(event: StringName, at: Vector3 = Vector3.INF)`, `start_loop(event, owner: Node) / stop_loop(event, owner)`, `set_wind(intensity: float)`. v1: every call is a no-op stub that keeps a dictionary of `AudioStreamPlayer3D` nodes ready; optional procedural wind via `AudioStreamGenerator` behind `Balance.PROCEDURAL_AUDIO` (default `false`). Event names: GDD §18. |
| `QuestManager` | `scripts/autoload/quest_manager.gd` | Loads `scripts/data/quests.gd`; tracks current day's quest list, step index, counters; listens to `Events` signals named by each step's `trigger`; emits `Events.quest_updated`, `quest_step_completed`, `quest_day_completed`. `reset_for_day(day)` on `day_started`. |

`GameState` and `QuestManager` reset in `start_game()`. `Inventory.clear()` and `Inventory.add(&"madera", 2)`? **No** — the player starts with an empty bar (the quest teaches pickup).

---

## 5. Data scripts (`scripts/data/`)

### `balance.gd` (`class_name Balance`) — constants, values from the GDD

```
DAY_LENGTH_SEC = 420.0; START_DAY = 1; START_HOUR = 8.0; NIGHT_START = 20.0; NIGHT_END = 6.0; WIN_DAY = 6
HEALTH_MAX = 100; WARMTH_MAX = 100; HUNGER_MAX = 100; WARMTH_START = 80; HUNGER_START = 70
HEALTH_LOSS_FREEZING = 4.0; HEALTH_LOSS_STARVING = 2.0; HEALTH_REGEN = 0.5; REGEN_MIN_STAT = 40
WARMTH_DRAIN_DAY = 0.4; WARMTH_DRAIN_NIGHT = 1.0; BLIZZARD_WARMTH_MULT = 2.0
WARMTH_HOUSE_STOVE_ON = 4.0; WARMTH_HOUSE_STOVE_OFF = -0.15; CAMPFIRE_WARMTH = 5.0; CAMPFIRE_HEAT_RADIUS = 4.5
TORCH_DRAIN_MULT = 0.6; COAT_DRAIN_MULT = 0.6
HUNGER_DRAIN = 0.15; RUN_HUNGER_MULT = 2.0
COLD_VIGNETTE_START = 30; FREEZING_SLOW_BELOW = 15; FREEZING_SPEED_MULT = 0.8; HUNGRY_WARN = 25; LOW_HEALTH = 25
WALK_SPEED = 4.0; RUN_SPEED = 6.0; ACCEL = 12.0; TURN_SPEED = 12.0; INTERACT_RANGE = 2.2; AUTO_WALK_TIMEOUT = 8.0
CAMERA_PITCH_DEG = -52.0; CAMERA_YAW_DEG = 35.0; CAMERA_DIST = 22.0; CAMERA_DIST_MIN = 14.0; CAMERA_DIST_MAX = 30.0
CAMERA_FOV = 35.0; CAMERA_FOLLOW = 6.0; CAMERA_LOOKAHEAD = 1.5; CAMERA_YAW_STEP = 45.0
STOVE_FUEL_START = 45.0; STOVE_FUEL_PER_WOOD = 90.0; STOVE_FUEL_MAX = 600.0
CAMPFIRE_FUEL_START = 60.0; CAMPFIRE_FUEL_PER_WOOD = 60.0; CAMPFIRE_FUEL_MAX = 300.0
TORCH_DURATION = 180.0; CAMPFIRE_FEAR_RADIUS = 7.0; TORCH_FEAR_RADIUS = 4.0
TREE_HITS = 3; DEAD_TREE_HITS = 2; LOG_HITS = 2; CHOP_COOLDOWN = 0.5
TREE_WOOD = 4; DEAD_TREE_WOOD = 2; LOG_WOOD = 3; BERRIES_PER_BUSH = 3; BUSH_REGROW = 240.0
STACK_MAX = 20; HOTBAR_SLOTS = 10; CONTAINER_SLOTS = 6
WOLF_HEALTH = 60; WOLF_WALK = 2.5; WOLF_RUN = 6.0; WOLF_BITE = 15; WOLF_BITE_RANGE = 1.6; WOLF_BITE_COOLDOWN = 1.5
WOLVES_PER_NIGHT = [2, 3, 4, 5]; WOLF_SPAWN_MIN = 35.0; WOLF_SPAWN_MAX = 45.0; WOLF_DESPAWN_DIST = 60.0
WOLF_STALK_MIN = 8.0; WOLF_STALK_MAX = 12.0; WOLF_FLEE_TIME = 8.0; WOLF_HIT_FLEE_CHANCE = 0.3
AXE_DAMAGE = 20; HAND_DAMAGE = 6; AXE_COOLDOWN = 0.8; HAND_COOLDOWN = 0.6; ATTACK_RANGE = 2.0; KNOCKBACK = 1.5
DEER_COUNT = 4; DEER_FLEE_RADIUS = 12.0; DEER_SPEED = 7.0
BLIZZARD_FIRST_DAY = 1; BLIZZARD_FIRST_HOUR = 14.0; BLIZZARD_CHANCE_PER_HOUR = 0.08; BLIZZARD_MIN_GAP_HOURS = 6.0
BLIZZARD_WARNING = 10.0; BLIZZARD_MIN = 60.0; BLIZZARD_MAX = 90.0
WORLD_SIZE = 160.0; TERRAIN_CELL = 2.0; BOUNDS = 78.0; TERRAIN_SEED = 1337
FOOTPRINT_STEP = 0.6; FOOTPRINT_LIFETIME = 20.0; FOOTPRINT_POOL = 60
RESPAWN_FIREWOOD_PER_DAY = 20; RESPAWN_STONE_PER_DAY = 12; MAX_FIREWOOD = 60; MAX_STONES = 40
PROCEDURAL_AUDIO = false
```

### `items.gd` (`class_name Items`)
`const DB := { &"madera": {"name": "Madera", "icon": "wood", "stack": 20, "kind": "material"}, ... }` with kinds `material | food | tool`. Food entries carry `"hunger"`, `"warmth"`, `"health"` deltas (GDD §9). Tools: `&"hacha"` (`stack: 1`), `&"antorcha"` (`stack: 20`). Helper: `Items.display_name(id)`, `Items.is_food(id)`, `Items.is_tool(id)`, `Items.food_priority()`.

### `recipes.gd` (`class_name Recipes`)
```
const CATEGORIES := [ &"herramientas", &"fuego", &"refugio", &"almacenaje", &"cocina", &"ropa" ]  # order = toolbar order
const TITLES := { &"herramientas": "HERRAMIENTAS", ... }
const DB := [
  {"id": &"hacha", "category": &"herramientas", "name": "Hacha de piedra", "icon": "axe",
   "cost": {&"madera": 2, &"piedra": 3}, "result": {&"hacha": 1}, "unique": true},
  {"id": &"antorcha", "category": &"fuego", "name": "Antorcha", "icon": "torch", "cost": {&"madera": 2, &"piedra": 1}, "result": {&"antorcha": 1}},
  {"id": &"fogata", "category": &"fuego", "name": "Fogata", "icon": "campfire", "cost": {&"madera": 3, &"piedra": 4}, "place": "campfire"},
  {"id": &"carne_asada", "category": &"cocina", ..., "needs_fire": true},
  {"id": &"bayas_calientes", "category": &"cocina", "cost": {&"bayas": 3}, "result": {&"bayas_calientes": 1}, "needs_fire": true},
  {"id": &"abrigo", "category": &"ropa", "name": "Abrigo de piel", "icon": "coat", "cost": {&"piel": 2}, "flag": "has_coat", "unique": true},
  {"id": &"tienda", "category": &"refugio", ..., "place": "tent", "priority": 2},
  {"id": &"caja", "category": &"almacenaje", ..., "place": "storage_box", "priority": 2},
]
```
`Recipes.status(recipe, player) -> Dictionary {ok: bool, text: String}` implements the GDD §10 status strings (`Materiales listos`, `Faltan materiales`, `Requiere fuego cerca`, `Ya fabricado`, `Sin hueco en el inventario`). `needs_fire` is satisfied when `player.is_near_fire()` (≤ 3 m from a lit campfire) **or** `player.is_in_house_with_stove_on()`.

### `quests.gd` (`class_name Quests`)
`static func for_day(day: int) -> Dictionary {"title_small": "PRIMER DÍA", "title_big": "SOBREVIVE", "steps": [...]}`. Each step: `{"title", "hint", "trigger": StringName (an Events signal name), "filter": Callable or null, "count": int}`. Day-1 steps and day 2–5 steps exactly as GDD §13. Triggers used: `item_picked_up` (filter id == madera, count 2), `stove_fueled`, `crafted` (filter id), `tree_felled`, `item_consumed`, `campfire_placed`, `day_started`. Day 2+: `stove_fueled`, `item_picked_up` madera ×6 (also counts wood from chopping — `item_picked_up` is emitted for every gain), `item_consumed`, `day_started`.

### `regions.gd` (`class_name Regions`)
`const ZONES := [ {"name": "CLARO", "center": Vector2(0, 0), "radius": 26.0}, {"name": "LAGO HELADO", "center": Vector2(-42, 30), "radius": 20.0}, {"name": "CABAÑA DEL PESCADOR", "center": Vector2(-20, 52), "radius": 14.0} ]`, `const DEFAULT := "BOSQUE PROFUNDO"`. First match wins (order above). Vector2 = (x, z).

### `placeholders.gd` (`class_name Placeholders`)
Table used by `Assets` when a `.glb` is missing (§18).

---

## 6. Scenes and scripts

### 6.1 Scene flow
`main_menu.tscn` → (Jugar) `game.tscn` → (death/win) overlay screens inside `game.tscn` → (Reintentar) reload `game.tscn` / (Menú) `main_menu.tscn`. `main_menu.tscn` instantiates `world.tscn` with `decorative_only = true` (no player, no wolves, fixed camera at dusk) as its background.

### 6.2 `game.tscn`
```
Game (Node3D) [game.gd]                      # wires player ↔ world ↔ UI; handles pause/game-over overlays
├── World (world.tscn)
├── Player (player.tscn)                      # placed at World.get_spawn_point() (cabin DoorAnchor + 2.5 m along the anchor's own −Z, i.e. out of the door)
└── UI (CanvasLayer, layer 10)
    ├── HUD (hud.tscn)
    ├── CraftPanel (craft_panel.tscn)         # hidden
    ├── StoragePanel (storage_panel.tscn)     # hidden
    ├── PauseMenu (pause_menu.tscn)           # hidden, process_mode = ALWAYS
    └── GameOver (game_over.tscn)             # hidden, process_mode = ALWAYS; also used for the win screen
```
`game.gd`: on `_ready` sets `Input.mouse_mode = MOUSE_MODE_VISIBLE`, `GameState.start_game()`, connects `Events.player_died` → `_show_game_over()`, `Events.game_won` → `_show_win()`, `pause` action → toggle `PauseMenu` (`get_tree().paused`), `Events.game_paused`. Any open panel is closed by `cancel` before pause.

### 6.3 `world.tscn`
```
World (Node3D) [world.gd]                     # exposes get_height(x,z), get_spawn_point(), region lookup, lists
├── Terrain (StaticBody3D) [terrain.gd]       # layer 1; children built in code:
│   ├── Mesh (MeshInstance3D)                 #   ArrayMesh, flat shaded, vertex colors
│   └── Shape (CollisionShape3D)              #   HeightMapShape3D, scaled (cell,1,cell)
├── Lake (MeshInstance3D)                     # flat disc r=20 at lake level+0.02, material ice, built in code
├── Bounds (StaticBody3D) [bounds.gd]         # 4 BoxShape3D walls at ±78 (layer 1)
├── Sun (DirectionalLight3D)                  # shadows on
├── Moon (DirectionalLight3D)                 # shadows off, blue, energy set by DayNight
├── Env (WorldEnvironment)                    # ProceduralSkyMaterial sky, fog, ambient
├── DayNight (Node) [day_night.gd]            # drives Sun/Moon/Env from GameState.hour
├── Weather (Node) [weather.gd]               # blizzard scheduler; drives Snowfall + fog + wind
├── Snowfall (snowfall.tscn) [snowfall.gd]    # follows the active camera
├── Cabin (cabin.tscn)                        # at (0, h0, 0), rotation_degrees.y = 180 (porch toward +Z); h0 = terrain height after flattening
├── AFrame (a_frame_cabin.tscn)               # at (-20, h, 52), yaw facing the lake
├── Truck (pickup_truck.tscn)                 # at (-11, h, -3), rotation_degrees.y = 155 (beside/behind the house, nose roughly toward −Z)
├── Signpost (signpost.tscn)                  # at (-7, h, 8) (front-left of the porch as seen by the camera)
├── Fences (Node3D)                           # fence.tscn instances: 6 segments left of the house, 4 by the A-frame
├── Scatter (Node3D) [scatter.gd]             # trees, stumps, rocks, bushes, pickups (children added in code)
├── Respawner (Node) [respawner.gd]           # daily firewood/stone respawn
├── WolfSpawner (Node) [wolf_spawner.gd]
├── DeerSpawner (Node) [deer_spawner.gd]
├── RegionTracker (Node) [region_tracker.gd]  # polls player position every 0.5 s → Events.region_changed
├── Footprints (footprints.tscn)              # pooled footprint meshes (player emits into it)
└── Actors (Node3D)                           # wolves, deer, campfires, placed objects go here
```

`world.gd` generation order (deterministic from `Balance.TERRAIN_SEED`, override with `@export var seed`): terrain → flatten pads (cabin r=12 at origin; A-frame r=8; truck r=4; lake r=20 clamp) → place fixed props on terrain → scatter → spawn deer. World is ready when `Events.world_ready` is emitted (Player waits for it before snapping to the spawn point).

### 6.4 Terrain (`terrain.gd`)
- Grid: `WORLD_SIZE / TERRAIN_CELL + 1 = 81 × 81` heights, x,z ∈ [−80, 80].
- Height: `FastNoiseLite` (fBm, 3 octaves, frequency 0.012) × 6.0 + second low-frequency noise (0.004) × 3.0. Lake: inside r=20 of `(-42, 30)` height → `lerp(h, lake_level, smoothstep(20, 14, dist))` where `lake_level = min(h at center) − 1.0`. Pads: `lerp(h, pad_h, smoothstep(r, r*0.6, dist))`.
- Mesh: `SurfaceTool`, **non-indexed triangles** (2 per cell) with per-face normals (flat shading) and per-vertex color: `snow` `#F1F5FA` mixed toward `snow_shadow` `#B9CBE3` by slope (normal.y < 0.85) and by a low-amplitude noise (±4 % lightness). Material: `StandardMaterial3D` `vertex_color_use_as_albedo = true`, roughness 1.0, `shading_mode = PER_PIXEL`.
- Collision: `HeightMapShape3D` (`map_width = map_depth = 81`, `map_data` row-major `z * 81 + x`), on a `CollisionShape3D` with `scale = (2, 1, 2)` at the terrain origin (shape is centered, so vertex (ix, iz) is at world `((ix − 40) * 2, h, (iz − 40) * 2)`).
- API: `get_height(x, z) -> float` (bilinear), `get_normal(x, z)`, `is_lake(x, z)`, `in_bounds(x, z)`, `random_point(rng, min_dist_from_origin) -> Vector3`.

### 6.5 Scatter (`scatter.gd`)
Poisson-like rejection sampling with `RandomNumberGenerator` (seeded). Exclusions: cabin pad r=13 (except a few firewood/stones near the porch), truck/A-frame pads, lake (trees/bushes only), beyond bounds. Counts (P0): pines 330 (weights a:50 %, b:30 %, c:20 %; extra ring density for |x| or |z| > 66), dead trees 40, stumps 15, rocks 110 (a 50 %, b 25 %, c 25 %), bushes 40, firewood 45, stones 30, fallen logs 14 (4 within 20 m of the cabin). Every instance snapped to `get_height`, random yaw, uniform scale 0.9–1.15 for trees/rocks. Trees are individual `tree.tscn` instances (they must be clickable/choppable); no MultiMesh in v1.

### 6.6 Player (`player.tscn`)
```
Player (CharacterBody3D) [player.gd]            layer 2, mask 1|3, group "player"
├── Shape (CollisionShape3D: CapsuleShape3D r=0.35 h=1.7, y=0.85)
├── Visual (Node3D)                             # yaw-rotated toward move dir; holds the model
│   └── (model from Assets.spawn_model("player"))   # anchors: Hips, Torso, Head, ArmL, ArmR, LegL, LegR, ToolSocket, BreathAnchor
├── Stats (Node) [player_stats.gd]
├── Animator (Node) [player_animator.gd]
├── Interactor (Node) [interactor.gd]           # cursor raycast, hover, click, auto-walk, attack
├── NearbyArea (Area3D, mask 4, SphereShape r=2.6 at y=1)   # gamepad "nearest interactable" + proximity list
├── ToolHolder (Node) [tool_holder.gd]          # spawns axe/torch model into ToolSocket; torch burn timer
├── Placement (Node) [placement_controller.gd]  # ghost placement mode
├── FootprintEmitter (Node) [footprint_emitter.gd]
├── HoverRing (MeshInstance3D) [hover_ring.gd]  # top_level; TorusMesh r=0.6 tube 0.05, unshaded accent color
├── BreathParticles (CPUParticles3D)            # reparented to BreathAnchor at ready
├── HitPuff (hit_puff.tscn)                     # spawned at chop target on hit (one-shot)
└── CameraRig (Node3D) [camera_rig.gd]          # top_level = true
    └── Pivot (Node3D)                          # yaw
        └── Pitch (Node3D)                      # pitch −52°
            └── Camera3D (fov 35, current)      # local position (0, 0, dist)
```

- **Movement** (`player.gd`, `_physics_process`): input vector from `move_*` → rotated by camera yaw → `velocity` accelerates toward `dir * speed` (`ACCEL`), gravity when not on floor, `move_and_slide()`. `speed = RUN_SPEED if run and hunger > 0 else WALK_SPEED`, × `FREEZING_SPEED_MULT` when warmth < 15. `Visual` rotates toward the move direction with `TURN_SPEED` (or toward the interaction target while auto-walking/interacting). `is_running` exported for hunger drain. No jump.
- **Auto-walk**: `Interactor` sets `player.auto_target`; `player.gd` steers straight to it until within `target.range`, then calls back `Interactor.perform_pending()`. Cancelled by any `move_*` press, by `cancel`, or after `AUTO_WALK_TIMEOUT`.
- **Stats** (`player_stats.gd`): `health, warmth, hunger` floats; `_process` applies GDD §5 rules using flags provided by the player: `in_house`, `stove_on` (from the cabin's shelter area + stove), `heat_sources_gain` (sum of `HeatZone` gains the player overlaps), `torch_lit`, `Inventory.has_coat`, `GameState.is_night`, `GameState.weather`. Emits `Events.stat_changed(&"health"|&"warmth"|&"hunger", value, max)` when the integer part changes, and `Events.player_died(cause)` once. Also fires threshold toasts (once per crossing) through `Events.notify`.
- **Animator** (`player_animator.gd`): procedural (ASSET_SPEC §4.1). Walk cycle phase advances by `horizontal_speed * 2.6 * delta`; `LegL.rotation.x = sin(phase) * 0.6`, `LegR = −`, `ArmL = −sin(phase) * 0.5`, `ArmR = sin(phase) * 0.5` (unless a tool pose overrides ArmR), `Hips.position.y = hips_rest_y + abs(sin(phase)) * 0.04`; run: amplitude × 1.3. Idle: `Torso.position.y` breathing ±0.01 at 1.2 Hz. **Chop/attack**: one-shot tween on `ArmR.rotation.x`: −2.4 rad (raised) → +0.6 over 0.18 s then back to rest over 0.3 s; body leans 0.15 rad. **Torch held**: `ArmR.rotation.x = −1.2` (forearm up) base pose. All anchors are looked up with `find_child(name, true, false)` on the spawned model; missing ones are created by `Assets` so no null checks are needed.
- **ToolHolder**: on `Events.tool_changed(id)` frees the current tool model and, if `id != &""`, `Assets.spawn_model("stone_axe" | "torch")` parented to `ToolSocket` with identity transform (the socket is pre-rotated in the asset). Torch: attaches `fire_effect.tscn` (small variant) to the torch's `FlameAnchor`, ticks `torch_seconds_left` (per torch), on 0 removes one `antorcha` from HAND, re-equips the next if any, toast `La antorcha se ha consumido`. Emits `Events.torch_toggled(lit)`.
- **Interactor** (`interactor.gd`), every physics frame when no panel is under the mouse (`get_viewport().gui_get_hovered_control() == null`) and not in placement mode:
  1. `from = camera.project_ray_origin(mouse)`, `to = from + camera.project_ray_normal(mouse) * 120`. `PhysicsRayQueryParameters3D` with `collision_mask = 1|3|4`, `collide_with_areas = true`, `collide_with_bodies = true`, exclude the player. 
  2. `target = InteractableComponent.find_from(result.collider)` — climbs `get_parent()` until a node that has a child `InteractableComponent` (cached via meta `"interactable"`) or reaches the scene root (`null`).
  3. Hover state → `Events.hover_changed(label_text)` (`""` when none), `HoverRing` placed at `target.get_ring_position()` (`global_position` of the owner + the component's `ring_offset`).
  4. On `interact_click` pressed (in `_unhandled_input`): if `target` and `target.can_interact(player)`: if `distance_2d(player, target) <= target.range` → `target.interact(player)`; else set pending + `player.auto_target = target` (label gets ` · acércate`). If no target → nothing (terrain clicks don't move the player).
  5. `attack` action: `Wolf` nearest within `ATTACK_RANGE` in any direction → `player.attack(wolf)`; else swings anyway (animation only).
  Gamepad `interact` (button X): picks the nearest interactable inside `NearbyArea` that `can_interact` → same path.
- **Attack** (`player.attack(wolf)`): cooldown per tool (`AXE_COOLDOWN`/`HAND_COOLDOWN`), damage `AXE_DAMAGE` if `Inventory.hand_tool() == &"hacha"` else `HAND_DAMAGE`; `wolf.take_damage(dmg, player)`; animator chop; `Events.camera_shake(0.1)`.
- **Placement** (`placement_controller.gd`): `begin(kind: String, recipe: Dictionary)` spawns a ghost (`Assets.spawn_model("campfire")` with `get_ghost_material(valid)` overriding all `MeshInstance3D` surfaces), follows the cursor ray hit on **layer 1 only, bodies only**, validity per GDD §10 (slope from `Terrain.get_normal`, distance to player ≤ 6, no `placement_blocker` overlap: uses a `ShapeCast3D` sphere r=1.5 with mask 1|7 that must hit only the terrain, not inside the cabin shelter area). LMB → `Inventory.remove` costs, instantiate `campfire.tscn` under `World/Actors` at the hit point, `Events.campfire_placed(node)`; RMB/`cancel` → abort. Emits `Events.placement_mode(active)` so the Interactor pauses hover.
- **FootprintEmitter**: every `FOOTPRINT_STEP` meters of ground travel (only on floor), calls `World.Footprints.stamp(position, yaw, left_right_toggle)`; also `AudioManager.play(&"footstep_snow")`.
- **CameraRig** (`camera_rig.gd`): `top_level = true`; `_process`: `target = player.global_position + move_dir * CAMERA_LOOKAHEAD`; `global_position = lerp(global_position, target, 1 − exp(−CAMERA_FOLLOW * delta))`. `yaw_index` (int, ×45°) tweened on `rotate_cam_left/right`; `dist` from zoom actions/wheel (tween 0.2 s, clamped). `Pitch.rotation_degrees.x = CAMERA_PITCH_DEG`. `Camera3D.position.z = dist`. `get_yaw() -> float` used by the player movement. Camera shake: `Events.camera_shake(strength)` → decaying random offset applied to the `Camera3D` local position (never to the rig). Exposes `static func active() -> CameraRig`.

### 6.7 Wolf (`wolf.tscn`) and Deer (`deer.tscn`)
```
Wolf (CharacterBody3D) [wolf.gd]           layer 3, mask 1|2|3, group "wolves"
├── Shape (CollisionShape3D: CapsuleShape3D r=0.3 h=1.1, rotation_degrees.x = 90, y=0.45)
├── Visual (Node3D) ← Assets.spawn_model("wolf")   # anchors: Body, Head, Muzzle, Tail, LegFL, LegFR, LegBL, LegBR
├── Animator (Node) [quadruped_animator.gd]
├── Health (Node) [health.gd]              # max 60; signals died(killer), damaged(amount)
├── Interactable (InteractableComponent, SphereShape r=1.0 at y=0.5)   # label "Atacar lobo", range 2.0, on interact → player.attack(self)
├── WhiskerL / WhiskerR (RayCast3D, mask 1, length 2.5, ±25° yaw, y=0.5)   # steering
└── Steering (Node) [steering.gd]          # seek/flee/wander + whisker avoidance, returns desired velocity
```
State machine (`enum State { ROAM, STALK, CHASE, ATTACK, FLEE, LEAVE, DEAD }`), rules from GDD §12. Per-frame: compute `fear_source` = nearest lit campfire (group `heat_source`, `is_lit`) within `CAMPFIRE_FEAR_RADIUS` or the player if `player.torch_lit` within `TORCH_FEAR_RADIUS` → FLEE for `WOLF_FLEE_TIME`. If `player.in_house` → ROAM around the cabin (orbit radius 6–10 m, never inside: treat the cabin shelter box expanded by 1.5 m as an obstacle: if the desired position is inside, steer tangentially). ATTACK: face the player, bite when `dist <= WOLF_BITE_RANGE` and cooldown elapsed → `player.take_damage(WOLF_BITE, &"lobo")`, lunge animation. Killed → `Events.wolf_died(self)`, drop pickups (`carne_cruda` ×2, `piel` ×1) via `pickup.tscn` instances around the body, shrink tween 1.5 s, `queue_free`. `LEAVE` at 06:00: run away from the player, free at > `WOLF_DESPAWN_DIST`. Gravity + `move_and_slide()`, `floor_max_angle = 50°`. `take_damage(amount, from)`: knockback `KNOCKBACK` away from `from`, 30 % FLEE.

Deer (`deer.gd`, reuses `steering.gd` and `quadruped_animator.gd`): states `GRAZE` (idle 3–8 s, small head bob), `WANDER` (walk 1.5 m/s to a random point ≤ 15 m), `FLEE` (`DEER_SPEED`, away from the player until > 25 m). Non-interactable. `deer_spawner.gd` spawns `DEER_COUNT` at start in the deep forest (> 45 m from origin), respawns one every 120 s if fewer than the count.

`quadruped_animator.gd`: phase by speed; front-left & back-right legs `rotation.x = sin(phase) * amp`, the other diagonal `−`; amp 0.5 walk / 0.8 run; `Body.position.y` bob 0.03; `Tail.rotation.y = sin(t * 3) * 0.3`; `Head.rotation.x` = −0.3 when chasing (lowered), `+0.4` lunge on bite; idle tail sway.

### 6.8 World objects
All of these are scenes whose root is the physics body (so the cursor ray hits it) plus an `InteractableComponent` child, plus `Visual` populated by `Assets.spawn_model`.

| Scene | Root | Script | Collision (code-side) | Interaction |
|---|---|---|---|---|
| `tree.tscn` | StaticBody3D, layer 1\|7, groups `choppable`,`tree` | `tree.gd` (`@export var variant: String` = `pine_a`…`dead_tree`) | CylinderShape3D r=0.35 h=3 at y=1.5 | label `Talar árbol (h/N)`, `requires_tool = &"hacha"`, `no_tool_label = "Necesitas un hacha"`, range 2.2. `interact` → one hit (cooldown `CHOP_COOLDOWN`): shake tween, hit puff, `Events.tree_hit`; at N hits → fall tween (rotate 80° away from the player over 1.0 s, then free), `Inventory.add(&"madera", wood)` (+ `Events.item_picked_up`), spawn `stump.tscn` at the base, `Events.tree_felled(variant)`. If the inventory can't take all wood, the rest drops as `pickup.tscn` (`firewood`). |
| `stump.tscn` | StaticBody3D layer 1 | — | CylinderShape3D r=0.3 h=0.5 | none |
| `rock.tscn` | StaticBody3D layer 1\|7 | `rock.gd` (`variant: rock_a/b/c`) | SphereShape3D (a: r=0.55 y=0.4; b: r=0.9 y=0.6; c: r=0.3 y=0.2) | none |
| `berry_bush.tscn` | StaticBody3D layer 7 (no walking block: shape on layer 7 only) | `berry_bush.gd` | SphereShape3D r=0.5 y=0.4 | label `Recoger bayas` / `Sin bayas (rebrotan)`; hides `Berries` node; regrow timer |
| `pickup.tscn` | Area3D layer 4, group `pickup` | `pickup.gd` (`@export var item_id`, `@export var model: String`) | SphereShape3D r=0.45 (the Area itself is the interactable; the scene root **is** an `InteractableComponent` subclass) | label `Recoger leña`/`Recoger piedra`/`Recoger carne`/`Recoger piel`; bob+spin; on interact → `Inventory.add`, free. Full inventory → toast `Inventory lleno`. |
| `campfire.tscn` | StaticBody3D layer 1\|7, groups `campfire`, `heat_source` | `campfire.gd` uses `fuel_burner.gd` | CylinderShape3D r=0.55 h=0.35 | label `Añadir leña (N)` / `Sin leña`; interact → `Inventory.remove(&"madera",1)`, fuel += 60, relight if out. Children: `Heat (HeatZone: Area3D layer 5, mask 2, SphereShape r=4.5)` with `gain = CAMPFIRE_WARMTH`, `Fire (fire_effect.tscn)` at `FlameAnchor`, `Interactable`. `is_lit` toggles Heat monitoring, Fire, light. Emits `campfire_lit/extinguished`. |
| `wood_stove.tscn` | StaticBody3D layer 1\|7, group `stove` | `wood_stove.gd` + `fuel_burner.gd` | BoxShape3D 0.6×0.9×0.6 at y=0.45 | label `Alimentar estufa (N)` / `Estufa apagada · Añadir leña (N)`; +90 s per wood; `is_lit` → `Events.stove_changed(lit)`, `Events.stove_fueled`; light + embers at `StoveAnchor`; chimney smoke is spawned by `cabin.gd` when lit. |
| `cabinet.tscn` | StaticBody3D layer 1\|7 | `cabinet.gd` + `storage.gd` (`title = "ARMARIO"`, initial contents from GDD §8) | BoxShape3D 0.9×1.8×0.5 | label `Abrir armario` / `Armario abierto`; interact → `Events.storage_opened(storage)` (HUD opens `StoragePanel`); auto-close beyond 3.5 m. |
| `pickup_truck.tscn` | Node3D | `storage.gd` (`title = "CAMIONETA"`) | embedded `-convcolonly` in the glb (placeholder builds boxes) | `Interactable` sphere r=1.6 at `BedAnchor`; label `Registrar camioneta` / `Camioneta abierta`. |
| `signpost.tscn` | Node3D (no collision) | `signpost.gd` | none | Adds a `Label3D` child with **identity transform** to `TextTop` and to `TextBottom` (the empties are pre-rotated in the asset so the text faces the board front and reads left-to-right; font size 48, `pixel_size` 0.004, text color `#F1E9D8`, outline `#3A2A20`, `double_sided = false`), texts `CABAÑA DEL PESCADOR` / `LAGO HELADO`. Yaws the whole post so its global +X (arrow tip) points toward the A-frame; then yaws the `BoardBottom` node (which parents `TextBottom`) so its +X points toward the lake. |
| `fence.tscn` | StaticBody3D layer 1 | — | BoxShape3D 2.0×1.0×0.15 at y=0.5 | none |
| `furniture.tscn` | StaticBody3D layer 1\|7 (`@export var model`) | — (`wall_clock.gd` for the clock: `HourHand.rotation.z = -TAU * (hour mod 12) / 12`, `MinuteHand.rotation.z = -TAU * frac(hour)`; verify visually that hands turn clockwise seen from the room and flip the sign if not) | BoxShape3D from a small table (bed 1.0×0.5×2.0, desk 1.4×0.75×0.6, chair 0.45×0.9×0.45, shelf/clock: none) | none |
| `a_frame_cabin.tscn` | Node3D | — | embedded `-convcolonly` | none (decorative). Warm window light at night (`OmniLight3D` energy 0 by day). |
| `lantern` | spawned by `cabin.gd` at `LanternSocket` | `lantern.gd` | none | `OmniLight3D` warm at `LightAnchor`, only at night, flicker. |

### 6.9 Cabin (`cabin.tscn`)
```
Cabin (Node3D) [cabin.gd]                 # in world.tscn: position (0, h0, 0), rotation_degrees.y = 180 (front/porch faces world +Z, toward the default camera)
├── Visual (Node3D) ← Assets.spawn_model("cabin")     # Floor, WallFront(+WindowsFront), WallBack, WallLeft(+WindowsLeft), WallRight, Roof, Chimney, Porch, DoorAnchor, LanternSocket, embedded Col* bodies
├── Shelter (Area3D layer 6, mask 2, BoxShape3D 5.6×2.6×4.6 at (0, 1.6, 0))   # interior volume, group "shelter"
├── Cutaway (Node) [cutaway.gd]
├── Stove (wood_stove.tscn)      pos (-2.15, 0.30, -0.6), rotation_degrees.y = -90   # against the left (−X, chimney) wall, front half; faces +X into the room
├── Cabinet (cabinet.tscn)       pos (2.35, 0.30, -1.2), rot y = 90                   # against the right (+X) wall, front half; faces −X
├── Bed (furniture.tscn model=bed)      pos (1.9, 0.30, 1.5), rot y = 0              # back-right corner, headboard toward +Z (back wall)
├── Desk (furniture.tscn model=desk)    pos (-0.6, 0.30, 2.0), rot y = 0             # against the back wall
├── Chair (furniture.tscn model=chair)  pos (-0.6, 0.30, 1.3), rot y = 180           # faces the desk (+Z)
├── Shelf (furniture.tscn model=shelf)  pos (-0.6, 1.9, 2.32), rot y = 0             # back wall inner face, above the desk
├── Clock (furniture.tscn model=clock) [wall_clock.gd]  pos (0.6, 2.1, 2.32), rot y = 0
├── ChimneySmoke (smoke_effect.tscn)   at (-3.35, 5.3, -0.6)   # chimney top; emitting only when the stove is lit
└── InteriorLight (OmniLight3D, warm, range 7, at (0, 2.2, 0); energy 0.9 when stove lit, 0.15 otherwise at night, 0 by day)
```
All positions are **cabin-local** (children of `Cabin`), converted from the Blender numbers in ASSET_SPEC §4.15/4.16 (`Godot = (x, z_blender, −y_blender)`), floor top at y = 0.30; the back wall's inner face is at local z = +2.32, the front (doorway, porch) at −Z. Furniture models face −Z locally; the `rot y` values above turn them to face into the room. Player spawn: `DoorAnchor.global_position − DoorAnchor.global_basis.z * 2.5` (2.5 m out of the door, past the steps), yaw facing the door.

`cabin.gd`: `player_inside` from `Shelter.body_entered/exited` → `Events.shelter_changed(inside)`; `stove_on` mirrors the stove; window glow: on `stove_changed`/night change, for every `MeshInstance3D` whose name begins with `Windows` set `set_surface_override_material(i, Assets.get_glow_material())` for surfaces whose material `resource_name == "window"` (or all surfaces on a placeholder), else clear override. Spawns the lantern at `LanternSocket`.

`cutaway.gd`: on `shelter_changed(true)` and on `Events.camera_yaw_changed`: hide `Roof`, `Chimney`, and every `Wall*` whose outward normal (`WallFront → −Z`, `WallBack → +Z`, `WallLeft → −X`, `WallRight → +X`, in the cabin's local space) satisfies `normal.dot(to_camera_dir) > 0.15` (`to_camera_dir` = horizontal direction from the cabin to the camera, transformed into cabin-local space with `global_transform.basis.inverse()`). With the default camera (yaw 35°) and the cabin rotated 180°, this hides `WallFront` and `WallLeft` (the chimney wall) — the same two faces the player sees from outside. On exit: show all. Hidden = `visible = false` (collision unaffected because `Col*` bodies are siblings, never children of walls).

### 6.10 Effects
- `snowfall.tscn`: two `CPUParticles3D` (`Light`: amount 500, box 40×20×40, lifetime 8, gravity (0,−1.6,0), initial velocity 0.3, scale 0.06–0.1, mesh `QuadMesh` with unshaded `snow` material, billboard; `Heavy`: amount 900, gravity (−4,−3,0) rotated by wind yaw, emitting only during blizzard). Follows `CameraRig.active()` position (x,z) at y+8.
- `fire_effect.tscn`: `Flames` (CPUParticles3D, 40, lifetime 0.7, upward 1.2 m/s, scale curve 0.35→0, color ramp `#FFD166`→`#FF8C2A`→`#E63B12` alpha 0, unshaded additive-ish material `BLEND_MODE_ADD`), `Smoke` (20 particles, lifetime 2.5, grey `#9AA3AD` alpha 0.35→0, growing), `Light` (`OmniLight3D` `#FFB454` energy 2.0 range 9, shadows off) with `light_flicker.gd` (energy × (1 + 0.15·noise(t·12))). `@export var scale_factor` (torch uses 0.35, light range 6).
- `smoke_effect.gd`: chimney smoke only.
- `hit_puff.tscn`: one-shot 12 particles `wood_light` chips, explosiveness 1.
- `footprints.tscn`: pool of `FOOTPRINT_POOL` `MeshInstance3D`s sharing one `CylinderMesh` (top r 0.16, bottom r 0.12, height 0.02, 8 sides) with material `snow_shadow` `#B9CBE3` alpha 0.8, placed at ground + 0.01 with the player's yaw, offset ±0.15 m left/right; each fades (`albedo_color.a` via per-instance `material_override` duplicate, or scale down) over `FOOTPRINT_LIFETIME` and is recycled.
- Frost vignette: `hud.tscn/Vignette` (`ColorRect` full-rect, `mouse_filter = IGNORE`) with `frost_vignette.gdshader` (canvas_item): radial mask from the edges, color `#BFE3F0`, uniform `strength` 0–1; plus a second `ColorRect` red vignette for low health.

---

## 7. Signal bus (`events.gd`)

```gdscript
# time & weather
signal time_changed(day: int, hour: float, is_night: bool)   # every frame the hour changes by ≥ 1/60 h
signal day_started(day: int)
signal night_started(day: int)
signal weather_changed(weather: StringName)                    # &"clear" | &"blizzard"
signal blizzard_warning(seconds: float)
signal world_ready()
signal region_changed(name: String)
# player
signal stat_changed(stat: StringName, value: float, max_value: float)
signal player_damaged(amount: float, source: StringName)
signal player_died(cause: StringName)                          # &"frio" | &"hambre" | &"lobo"
signal shelter_changed(inside: bool)
signal torch_toggled(lit: bool)
signal tool_changed(tool_id: StringName)
signal camera_shake(strength: float)
signal camera_yaw_changed(yaw_deg: float)
signal hover_changed(label: String)
signal placement_mode(active: bool)
# inventory & crafting
signal inventory_changed()
signal item_picked_up(item_id: StringName, amount: int)         # any gain (pickup, chop, container take)
signal item_consumed(item_id: StringName)
signal crafted(recipe_id: StringName)
signal craft_failed(reason: String)
signal storage_opened(storage: Node)                            # Storage component
signal storage_closed()
# world objects
signal tree_hit(tree: Node, hits: int, total: int)
signal tree_felled(variant: String)
signal campfire_placed(campfire: Node)
signal campfire_lit(campfire: Node)
signal campfire_extinguished(campfire: Node)
signal stove_fueled()
signal stove_changed(lit: bool)
signal wolf_spawned(wolf: Node)
signal wolf_died(wolf: Node)
# quests & flow
signal quest_updated(state: Dictionary)                          # {title_small, title_big, index, total, steps:[{title,hint,done}]}
signal quest_step_completed(step_index: int)
signal quest_day_completed(day: int)
signal notify(text: String, seconds: float)                      # toast
signal game_paused(paused: bool)
signal game_over(days: int, hours: int, cause: StringName)
signal game_won(days: int)
```

---

## 8. Input map (defined in `project.godot`)

| Action | Keyboard / mouse | Joypad |
|---|---|---|
| `move_forward` / `move_back` / `move_left` / `move_right` | W/↑, S/↓, A/←, D/→ | Left stick axis 1 −/+ , axis 0 −/+ (deadzone 0.2) |
| `run` | Shift | Button 7 (L3) |
| `interact_click` | Mouse button 1 | — |
| `interact` | — (E also mapped, as accessibility: nearest) | Button 2 (X) |
| `attack` | Space | Axis 5 (RT) > 0.5 |
| `cancel` | Mouse button 2, Escape | Button 1 (B) |
| `pause` | Escape | Button 6 (Start) |
| `rotate_cam_left` / `rotate_cam_right` | Q / E | Button 9 (LB) / 10 (RB) |
| `zoom_in` / `zoom_out` | Wheel up (button 4) / wheel down (button 5) | Button 11 (D-up) / 12 (D-down) |
| `hotbar_1` … `hotbar_9` | Keys 1–9 | — |
| `hotbar_prev` / `hotbar_next` / `hotbar_use` | — | Button 13 (D-left) / 14 (D-right) / 0 (A) |
| `toggle_craft` | Tab | Button 3 (Y) |
| `toggle_torch` | T | Button 12 held 0.4 s (implemented in `hotbar.gd`) |
| `eat` | F | — |

`Escape` is bound to both `cancel` and `pause`; `game.gd` resolves: if any panel/placement is active → cancel, else pause.

---

## 9. Physics layers and masks

| # | Name | Members | Notes |
|---|---|---|---|
| 1 | `world` | Terrain, Bounds, trees, stumps, rocks, campfires, stove, cabinet, furniture, fences, cabin/A-frame/truck `Col*` bodies | Player/wolves collide with it; cursor ray hits it |
| 2 | `player` | Player body | Detected by heat/shelter areas |
| 3 | `animals` | Wolves, deer | Cursor ray hits it (attack); collide with world/player/each other |
| 4 | `interactable` | Every `InteractableComponent` (Area3D), pickups | Cursor ray (areas) + player `NearbyArea` mask |
| 5 | `heat` | `HeatZone` areas (campfire) | mask 2 (player) — wolves use distance checks instead |
| 6 | `shelter` | Cabin `Shelter` area (P2: tent) | mask 2 |
| 7 | `placement_blocker` | trees, rocks, campfires, stove, cabinet, furniture, bushes | Placement `ShapeCast3D` mask 1\|7 |

| Body / area | Layer | Mask |
|---|---|---|
| Player | 2 | 1, 3 |
| Player `NearbyArea` | — | 4 |
| Wolf / Deer | 3 | 1, 2, 3 |
| Terrain, Bounds, static props | 1 | — |
| Tree, rock, campfire, stove, cabinet, furniture | 1 + 7 | — |
| Berry bush | 7 | — |
| `InteractableComponent`, Pickup | 4 | — |
| `HeatZone` | 5 | 2 |
| Cabin `Shelter` | 6 | 2 |
| Cursor ray | — | 1, 3, 4 (areas + bodies) |
| Placement ray | — | 1 (bodies) |
| Wolf whiskers | — | 1 |

---

## 10. Groups

`player`, `wolves`, `deer`, `interactable` (owner nodes of an `InteractableComponent`), `choppable`, `tree`, `pickup`, `campfire`, `heat_source` (lit campfires only — added/removed on light state), `stove`, `shelter`, `storage`, `cutaway_cabin`, `placed` (player-placed objects).

---

## 11. Interaction system

`scripts/components/interactable.gd`:
```gdscript
class_name InteractableComponent extends Area3D
@export var label: String = ""                 # static label; owner may override via get_interact_label()
@export var range: float = 2.2
@export var requires_tool: StringName = &""     # e.g. &"hacha"
@export var no_tool_label: String = ""
@export var ring_offset: Vector3 = Vector3.ZERO
@export var ring_radius: float = 0.6
@export var enabled: bool = true
signal interacted(player: Node)

func _ready(): collision_layer = 8; collision_mask = 0; get_parent().add_to_group("interactable"); get_parent().set_meta("interactable", self)
func get_label(player) -> String        # owner.get_interact_label(player) if it exists, else label; appends no_tool_label logic
func can_interact(player) -> bool       # enabled and (requires_tool == "" or Inventory.hand_tool() == requires_tool) and owner.can_interact(player) if defined
func interact(player) -> void           # owner.interact(player) if defined, then emit interacted
func get_ring_position() -> Vector3
static func find_from(node: Node) -> InteractableComponent   # climb parents; also accepts the Area itself
```
Owners implement optional `get_interact_label(player) -> String`, `can_interact(player) -> bool`, `interact(player) -> void`. Labels when `requires_tool` is unmet: return `no_tool_label` and `can_interact = false` (the ring turns red `#FF5A5A`).

Range is measured horizontally between the player and the component's global position. Auto-walk uses the same measure.

---

## 12. Stats, heat, shelter, fuel

- `heat_zone.gd` (`class_name HeatZone extends Area3D`, layer 5, mask 2): `@export var gain: float`, on `body_entered(player)` → `player.stats.add_heat_source(self)`; exited → remove. Disabled (`monitoring = false`) when the owner is unlit.
- `fuel_burner.gd` (`class_name FuelBurner extends Node`): `fuel`, `fuel_max`, `per_wood`, `is_lit`; `_process`: `fuel -= delta` when lit; at 0 → `is_lit = false`, `extinguished` signal. `add_wood(n) -> bool` (needs `Inventory.remove`), relights if it was out. `seconds_left()`.
- `player_stats.gd` warmth rate (per second) resolved in this order:
  1. `base = WARMTH_DRAIN_NIGHT if is_night else WARMTH_DRAIN_DAY` (negative sign applied), × `BLIZZARD_WARMTH_MULT` if blizzard, × `TORCH_DRAIN_MULT` if torch lit, × `COAT_DRAIN_MULT` if coat.
  2. If `in_house`: `base = WARMTH_HOUSE_STOVE_ON if stove_on else WARMTH_HOUSE_STOVE_OFF` (no multipliers; blizzard ignored inside).
  3. `rate = base + Σ heat_zone.gain` (campfires work inside or outside).
- Death cause: the stat that reached 0 most recently when health hits 0 (`&"frio"` if warmth == 0, else `&"hambre"` if hunger == 0), or `&"lobo"` if the last damage came from a wolf within 5 s.

---

## 13. Day/night and weather

`day_night.gd`: from `GameState.hour` compute `t_sun = (hour − 6) / 12` (0..1 by day). Sun elevation `elev = sin(t_sun·π) · 38°` (negative at night); `Sun.rotation_degrees = (−elev, 205 + t_sun·40 − 20, 0)` (comes from the south-west), `light_energy = clamp(elev/38, 0, 1) · 1.2`, `light_color` lerps `#FFB070` (elev < 8°) → `#FFF4E0`. `Moon`: energy `0.18 · (1 − clamp(elev/8, 0, 1))`, color `#7D9BD1`, fixed rotation (−45, 20, 0). Environment: four keyframes at hours 6, 12, 19.5, 0 (dawn, noon, dusk, midnight) for `sky_top_color`, `sky_horizon_color`, `ground_bottom_color`, `ambient_light_color`, `ambient_light_energy` (0.9 day / 0.35 night), `fog_light_color`, `fog_density` (0.010 / 0.022), each interpolated with `Gradient`s (or a keyframe table + `lerp`). Colors from GDD §6. `Env.environment.fog_enabled = true`, `fog_mode = EXPONENTIAL` — supported by Compatibility. Shadows: `Sun.shadow_enabled = true`, `directional_shadow_max_distance = 60`, `shadow_blur = 1.5`; OmniLights never cast shadows.

`weather.gd`: implements GDD §7 with an hourly roll on `time_changed` when `floor(hour)` changes. During a blizzard: `fog_density` target 0.06, `fog_light_color` `#B8C4D3`, `Snowfall.set_blizzard(true, wind_yaw)`, `AudioManager.set_wind(1.0)`. Fog/ambient targets are blended at 0.5/s so transitions are smooth. Emits `weather_changed`, `blizzard_warning`. Testing hook: `Weather.force_blizzard(seconds)`.

`wolf_spawner.gd`: on `night_started(day)` compute `count = WOLVES_PER_NIGHT[min(day − 1, 3)]`; spawn `ceil(count/2)` immediately, one every 60 s after; spawn position: random angle, distance 35–45 from the player, `in_bounds`, `!is_lake`, ≥ 15 m from the origin; snapped to terrain. On `day_started`: all wolves → `LEAVE`. `spawn_wolf(pos) -> Wolf` public for tests. `Events.notify("Los lobos merodean…")` on the first spawn of each night + `AudioManager.play(&"wolf_howl")`.

---

## 14. Inventory, hotbar, containers, crafting

- `Inventory` is the single model; `hotbar.gd` renders 10 `hotbar_slot.tscn` (slot 0 shows the `MANO` caption). Click on slot: tool → `equip_from_slot(i)`; food → `use_slot(i)`; if a `StoragePanel` is open → `deposit_to_container(open_storage, i, shift)`. Hover tooltip (`Lata de judías · Hambre +40`).
- `storage.gd` (`class_name Storage extends Node`): `title: String`, `slots: Array[Dictionary]` (6), `add/remove/take(slot, all)`, signal `changed`. Owners: cabinet, truck, (P2) storage box. `storage_panel.gd` binds to a `Storage`, renders slots with count and `+N` hunger badge for food, buttons `COGER TODO` and `✕`, footer text (GDD §15). Closes on `cancel`, `✕`, distance > 3.5 m (checked by the panel each frame), or `storage_closed`.
- `category_bar.gd`: six buttons (icons `tools, fire, tent, box, bowl, shirt`), toggles `CraftPanel.open(category)`; the active one is highlighted. `craft_panel.gd`: rows from `Recipes.DB` filtered by category; a selected row shows the status line and the `FABRICAR` button. On craft: `Recipes.status` → if ok and no `place` key: `Inventory.remove` costs, `Inventory.add` result (or set flag), `Events.crafted(id)`, toast `Fabricado: <nombre>` (e.g. `Fabricado: Hacha de piedra`). If `place`: `Placement.begin(place, recipe)` and close the panel (costs consumed on confirm).
- `toggle_craft` opens the last category (default `herramientas`). Panels are mutually exclusive: opening one closes the other. While a panel is open the game keeps running (not paused) but the Interactor ignores clicks over UI (Control consumes them).

---

## 15. Quest system

`QuestManager` keeps `{day, steps, index, counters}`. On `day_started(day)` (and at `start_game` for day 1) loads `Quests.for_day(day)` and emits `quest_updated`. For each step it connects to the `Events` signal named in `trigger` (via `Events.connect(trigger, Callable(self, "_on_trigger").bind(step_i))`) only while that step is current; `filter` (Callable taking the signal args) must return true; `count` accumulates. Completing: `quest_step_completed(i)`, `AudioManager.play(&"quest_done")`, index++; when all done: `quest_day_completed(day)` (panel shows `¡Día completado!` until the next day). `quest_panel.gd` renders GDD §13: `title_small`, `title_big`, `index/total`, progress bar, previous (struck-through: draw a line via a `ColorRect` over the label, or use BBCode `[s]` in a `RichTextLabel`), current (bold + hint), next (dimmed).

---

## 16. Region tracking

`region_tracker.gd` polls the player's XZ every 0.5 s against `Regions.ZONES`; on change → `Events.region_changed(name)`. `region_banner.gd`: shows `REGIÓN` (small) + name (big) at the top center, fades from full to 55 % opacity after 3 s.

---

## 17. Game flow and menus

- `main_menu.gd`: buttons `Jugar` → `GameState.start_game()`; `Controles` → `controls_panel.tscn`; `Salir` → `get_tree().quit()`. Shows `Mejor marca: N días` if `best_days > 0`.
- `pause_menu.gd`: `Continuar`, `Reiniciar` (`GameState.restart()`), `Menú principal`, `Salir del juego`. Sets `get_tree().paused`; `PauseMenu.process_mode = ALWAYS`.
- `game_over.gd`: `show_death(days, hours, cause)` / `show_win(days)` with GDD §14 texts; buttons wired to `GameState`.
- `GameState.game_over(cause)`: computes days/hours, saves best, emits `game_over`, sets `is_game_over` (stats stop, input disabled, camera keeps following). `win()` similar.

---

## 18. Asset loading and placeholders (`assets.gd`)

```gdscript
func spawn_model(name: String) -> Node3D:
    var path := "res://assets/models/%s.glb" % name
    var root: Node3D
    if ResourceLoader.exists(path, "PackedScene"):
        var scene: PackedScene = _cache.get(path) if _cache.has(path) else load(path)   # never load() a missing path (it prints an error)
        _cache[path] = scene
        root = scene.instantiate() as Node3D
        root.set_meta("placeholder", false)
    else:
        root = Placeholders.build(name)          # primitives, same anchor names
        root.set_meta("placeholder", true)
        push_warning("Model %s missing; using placeholder" % name)   # push_warning, NOT push_error (smoke test greps ERROR)
    _ensure_anchors(name, root)
    return root
```
- `_ensure_anchors` guarantees the named nodes from ASSET_SPEC §4 exist (`find_child(n, true, false)`; if missing, adds a `Node3D` with that name at the spec's fallback position, parented to the spec's parent name or to the root). Table in `Placeholders.ANCHORS`.
- `Placeholders.build(name)` returns a `Node3D` made of `MeshInstance3D`s with `BoxMesh/CylinderMesh/SphereMesh/PrismMesh` and flat `StandardMaterial3D` colors from the GDD palette, matching each asset's dimensions and **node names** (`Hips/Torso/...` for the player as a stack of boxes with the right pivots; `Body/Head/Legs` for quadrupeds; `Roof`, `WallFront`… and `Col*` `StaticBody3D`+`BoxShape3D` for the cabin; `FlameAnchor`, `ToolSocket` (with the −90° X pre-rotation), `Berries`, `BedAnchor`, `TextTop/TextBottom`, `LanternSocket`, `StoveAnchor`, `HourHand/MinuteHand`, etc.). The game must be fully playable with zero `.glb` files.
- Materials from glb files are used as-is (flat colors). `Assets.get_glow_material()`: `StandardMaterial3D` albedo `#FFB454`, emission `#FFB454` energy 2.5, unshaded. `Assets.get_ghost_material(valid)`: unshaded, `#6FD08C`/`#FF5A5A`, alpha 0.5, `transparency = ALPHA`.
- **Import step**: `.glb` files need Godot's importer to run once: `godot --headless --path winter-survival --import` (also executed by `tests/run_smoke.sh` before tests). Default import settings (scene, materials embedded) are used; no `.import` overrides needed. Because Blender writes `-convcolonly` names, the importer creates `StaticBody3D` + `CollisionShape3D` (convex) nodes named without the suffix — those bodies are on layer 1 by default, which is what we want.

---

## 19. UI construction

- Theme `assets/themes/ui_theme.tres` created in code at first run or saved as a resource: `PanelContainer` `StyleBoxFlat` bg `#1E2A3A` α 0.88, border 1 px `#8FA6C0` α 0.45, corner radius 4, plus a 2 px top border `#DCEBFA` α 0.7 ("ice edge"). Buttons: bg `#101826` α 0.7, hover `#2A3A50`, primary style `#DCEBFA` with dark text. Labels: titles `uppercase = true`, font size 22 bold, secondary labels size 11 `#93A6BF` with `uppercase`.
- Icons: hand-written SVG files in `assets/icons/` (64×64 viewBox, white fill `#FFFFFF`, 1–3 `<path>`/`<circle>`/`<rect>` elements each; Godot imports SVG as textures; set the `svg/scale` import default of 1). Required names: `heart, drumstick, thermometer, sun, moon, tools, fire, tent, box, bowl, shirt, axe, torch, wood, stone, berry, meat_raw, meat_cooked, berries_hot, can_beans, can_soup, pelt, campfire, coat, check, hand, snowflake`. `ui_icons.gd`: `static func tex(name) -> Texture2D` returns the SVG texture, or `null` if the file is missing; slot/meter widgets then fall back to a colored rounded square (`StyleBoxFlat` on a `Panel`) showing the item's first letter. Item tints: wood `#C7A16B`, stone `#7C8592`, berry `#D9403D`, meat `#C25A5A`, cans `#C23B3B`/`#3B6BC2`, pelt `#8A7A6A`, tools `#DDE6F0`.
- `ring_meter.tscn` (`ring_meter.gd`, `Control` 56×56): draws with `_draw()`: background ring `#101826` α 0.7, value arc (`draw_arc`, width 6, color per stat) starting at −90°, icon centered (`TextureRect` 24×24 modulated white), optional number on hover; low-value pulse (scale 1.0→1.08 at 1.2 Hz when < 25 %).
- `day_clock.tscn` (64×64): `_draw()` ring showing day progress since 06:00 (arc), sun/moon icon at the top, label `Día N` centered.
- `hud.tscn` layout: `MarginContainer` 16 px; anchors — top-center `RegionBanner`; top-right `VBox(DayClock, HBox(Hunger, Health, Warmth), WeatherLabel, CoatIcon)`; right-center `QuestPanel` (260 px wide); left-center `CategoryBar` (48 px buttons) with `CraftPanel` docked to its right; bottom-center `VBox(ContextLabel, Hotbar)`; `Toasts` under the region banner; vignettes full-rect behind everything (`mouse_filter = IGNORE` on all non-interactive nodes so 3D clicks pass through).
- Hover label priority: `hover_changed` text; during placement: `Clic: colocar · Clic derecho: cancelar`.

---

## 20. Audio manager

`audio_manager.gd` keeps `_players: Dictionary` for loops and a pool of 8 `AudioStreamPlayer` + 8 `AudioStreamPlayer3D`. `play(event, at)` looks up `_streams.get(event)` — empty in v1 → returns silently. `set_wind(intensity)` stores the value; if `Balance.PROCEDURAL_AUDIO`, feeds an `AudioStreamGenerator` (44.1 kHz, white noise through a one-pole low-pass, amplitude 0.08·intensity) — optional. All gameplay code calls these hooks with the GDD §18 names; adding real audio later is only a table change.

---

## 21. Tests

### 21.1 Smoke test (headless, Compatibility not needed)

`tests/run_smoke.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
godot --headless --path . --import > /tmp/ventisca_import.log 2>&1 || true
godot --headless --path . -s tests/smoke_test.gd 2>&1 | tee /tmp/ventisca_smoke.log
if grep -E "SCRIPT ERROR|ERROR: |FAIL:" /tmp/ventisca_smoke.log; then echo "SMOKE TEST FAILED"; exit 1; fi
echo "SMOKE TEST OK"
```

`tests/smoke_test.gd` (`extends SceneTree`): `_initialize()` starts `_run()` (a coroutine using `await process_frame`). Helper `check(cond, msg)` prints `FAIL: msg` and sets `_failed = true`; the script ends with `quit(1 if _failed else 0)`. Steps:
1. `change_scene_to_file("res://scenes/main/game.tscn")`, await `Events.world_ready` (with a 600-frame timeout).
2. Assert player, terrain (collision shape present), cabin, stove, cabinet, ≥ 200 nodes in group `tree`, ≥ 1 `pickup` exist; `GameState.day == 1`, `hour ≈ 8`.
3. Run 120 frames; assert no stat is NaN, `hunger < 70` (draining), player is on the floor.
4. Inventory: `Inventory.add(&"madera", 2)`; `add(&"piedra", 3)`; craft `hacha` via `CraftPanel`'s public `craft(recipe_id)` (or `Recipes.craft(recipe, player)` helper); assert `Inventory.hand_tool() == &"hacha"` after `equip_from_slot`.
5. Find the nearest tree; teleport the player next to it; call `tree.interactable.interact(player)` three times with `await create_timer(0.55)`; assert `tree_felled` fired (connect a lambda) and `Inventory.count(&"madera") == 4` (+ leftover from step 4 = 4 since 2 were consumed).
6. Stove: `stove.add_wood_from_player(player)` → assert `fuel` increased and `QuestManager` step index advanced appropriately (steps 1–4 by now; note step 1 needs 2 `item_picked_up` madera — the chop counts).
7. Container: open the cabinet's storage, `Inventory.take_from_container(storage, 0, false)`; assert `count(&"lata_judias") == 1`; `Inventory.eat_best()` → hunger increased, `item_consumed` fired.
8. Campfire: `Inventory.add(&"madera",3); add(&"piedra",4)`; `Placement.begin("campfire", recipe)`; `Placement.confirm_at(player.global_position + Vector3(2,0,0))`; assert one node in group `campfire`, `is_lit`, and player warmth rate > 0 after 60 frames when standing at 2 m.
9. Night: `GameState.set_time(1, 20.1)`; run 30 frames; assert `WolfSpawner` spawned ≥ 1 wolf (`get_nodes_in_group("wolves")`); teleport a wolf to 10 m and run 120 frames → its state ∈ {STALK, CHASE, ATTACK, FLEE}; move the campfire under the wolf → after 30 frames state == FLEE.
10. Kill the wolf: `wolf.take_damage(999, player)` → `wolf_died` fired; after 2 s, ≥ 2 pickups with `item_id` in {`carne_cruda`, `piel`}.
11. Blizzard: `Weather.force_blizzard(5)` → `GameState.weather == &"blizzard"`, `weather_changed` fired; after 6 s back to `&"clear"`.
12. Cutaway: teleport the player inside the cabin (0, 0.5, 0); run 10 frames; assert `Events.shelter_changed(true)` fired and `Roof.visible == false`; move out → visible again.
13. Day roll: `GameState.set_time(1, 5.98)`; run 90 frames; assert `day == 2`, `day_started(2)` fired, wolves leaving, quest reset (index 0, 4 steps).
14. Death: `player.stats.warmth = 0; player.stats.health = 1`; run 30 frames → `player_died(&"frio")`, `GameOver` visible, `GameState.is_game_over`.
15. Win path: `GameState.set_time(5, 5.98)`, `is_game_over = false` (test hook `GameState.debug_revive()`), run 90 frames → `game_won(5)`.
16. `quit(0)` if all passed.

Every public method used by the test exists in the code as described (test hooks are plain methods, no magic).

Additionally the raw scene boot test: `godot --headless --path . --quit-after 300` must exit 0 without `ERROR`.

### 21.2 Screenshots (xvfb + Compatibility)

`tests/run_screenshots.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p /tmp/ventisca_shots
for preset in day night blizzard interior menu; do
  LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1280x720x24" \
    godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility --resolution 1280x720 \
    -s tests/screenshot.gd ++ --preset=$preset --out=/tmp/ventisca_shots/$preset.png 2>&1 | tail -n 5
done
ls -la /tmp/ventisca_shots
```
`tests/screenshot.gd` (`extends SceneTree`): parses `OS.get_cmdline_user_args()`; loads `game.tscn` (`menu` preset loads `main_menu.tscn`), awaits `world_ready`, applies the preset (`day`: 11:00; `night`: 22:30 with a lit campfire 3 m from the player and the torch equipped; `blizzard`: 15:00 + `force_blizzard(60)`; `interior`: player teleported inside the cabin at 21:00 with the stove lit), waits 90 frames for particles/shadows, then `await RenderingServer.frame_post_draw`, `root.get_viewport().get_texture().get_image().save_png(out)`, `quit()`. Screens are reviewed by eye; the coordinator may compare them with the reference screenshots.

### 21.3 Model inspection (shared with the 3D agent)
`tests/inspect_models.gd` (`extends SceneTree`): for every `res://assets/models/*.glb` that imports, instantiate and print the node tree with type, and for each `MeshInstance3D` its AABB and surface material names; for each `Node3D` anchor its global position. Run: `godot --headless --path . -s tests/inspect_models.gd`. Used to verify the ASSET_SPEC contract (names, forward axis via anchor positions, dimensions).

---

## 22. Implementation order for the code agent

1. `project.godot`, autoloads, data scripts, `Assets` + `Placeholders` (everything below must run with zero glb files).
2. World: terrain + lake + bounds + day/night + snowfall; `game.tscn` with the player and camera rig; movement; footprints.
3. Interactable system, hover ring, context label, pickups, trees (chop), bushes, rocks, scatter.
4. Inventory + hotbar + tools (axe, torch), category bar + craft panel, placement + campfire, heat zones, stats + rings + vignettes.
5. Cabin: shelter, cutaway, stove, cabinet + storage panel, furniture, lantern, window glow, clock.
6. Wolves + spawner, attack, drops; deer.
7. Weather, quests, regions, toasts, menus, game over/win, best score.
8. `tests/` scripts; run smoke + screenshots; fix everything the logs show.
