class_name Balance
## Every gameplay number lives here (values from GDD.md).

# --- time ---
const DAY_LENGTH_SEC := 420.0
const START_DAY := 1
const START_HOUR := 8.0
const NIGHT_START := 20.0
const NIGHT_END := 6.0
const WIN_DAY := 6

# --- stats ---
const HEALTH_MAX := 100.0
const WARMTH_MAX := 100.0
const HUNGER_MAX := 100.0
const WARMTH_START := 80.0
const HUNGER_START := 70.0
const HEALTH_LOSS_FREEZING := 4.0
const HEALTH_LOSS_STARVING := 2.0
const HEALTH_REGEN := 0.5
const REGEN_MIN_STAT := 40.0
const WARMTH_DRAIN_DAY := 0.4
const WARMTH_DRAIN_NIGHT := 1.0
const BLIZZARD_WARMTH_MULT := 2.0
const WARMTH_HOUSE_STOVE_ON := 4.0
const WARMTH_HOUSE_STOVE_OFF := -0.15
const CAMPFIRE_WARMTH := 5.0
const CAMPFIRE_HEAT_RADIUS := 4.5
const TORCH_DRAIN_MULT := 0.6
const COAT_DRAIN_MULT := 0.6
const HUNGER_DRAIN := 0.15
const RUN_HUNGER_MULT := 2.0
const COLD_VIGNETTE_START := 30.0
const FREEZING_SLOW_BELOW := 15.0
const FREEZING_SPEED_MULT := 0.8
const HUNGRY_WARN := 25.0
const LOW_HEALTH := 25.0

# --- movement / camera (PLAN C19, M1 decision: walk 2.2 / run 6.0 / crouch 1.3 m/s, matched by the skeletal locomotion) ---
const WALK_SPEED := 2.2
const RUN_SPEED := 6.0
const CROUCH_SPEED := 1.3
const ACCEL := 12.0
const TURN_SPEED := 12.0
const INTERACT_RANGE := 2.2
const AUTO_WALK_TIMEOUT := 8.0
const CAMERA_PITCH_DEG := -48.0
const CAMERA_YAW_DEG := 45.0
const CAMERA_DIST := 24.0   # G1: the reference frames the cabin at ~24 m (doc 06 §3.12); zoom range unchanged
const CAMERA_DIST_MIN := 16.0
const CAMERA_DIST_MAX := 38.0
const CAMERA_FOV := 36.0
const CAMERA_FAR := 70.0
const CAMERA_FOLLOW := 6.0
const CAMERA_LOOKAHEAD := 1.5
const CAMERA_FORWARD_OFFSET := 3.0
const CAMERA_YAW_STEP := 45.0

# --- fire ---
const STOVE_FUEL_START := 45.0
const STOVE_FUEL_PER_WOOD := 90.0
const STOVE_FUEL_MAX := 600.0
const CAMPFIRE_FUEL_START := 60.0
const CAMPFIRE_FUEL_PER_WOOD := 60.0
const CAMPFIRE_FUEL_MAX := 300.0
const TORCH_DURATION := 180.0
const CAMPFIRE_FEAR_RADIUS := 7.0
const TORCH_FEAR_RADIUS := 4.0

# --- gathering ---
const TREE_HITS := 3
const DEAD_TREE_HITS := 2
const LOG_HITS := 2
const CHOP_COOLDOWN := 0.5
const TREE_WOOD := 4
const DEAD_TREE_WOOD := 2
const LOG_WOOD := 3
const BERRIES_PER_BUSH := 3
const BUSH_REGROW := 240.0
const STACK_MAX := 20
const HOTBAR_SLOTS := 10
const CONTAINER_SLOTS := 6

# --- wolves ---
const WOLF_HEALTH := 60.0
const WOLF_WALK := 2.5
const WOLF_RUN := 6.0
const WOLF_BITE := 15.0
const WOLF_BITE_RANGE := 1.6
const WOLF_BITE_COOLDOWN := 1.5
const WOLVES_PER_NIGHT := [2, 3, 4, 5]
const WOLF_SPAWN_MIN := 35.0
const WOLF_SPAWN_MAX := 45.0
const WOLF_DESPAWN_DIST := 60.0
const WOLF_STALK_MIN := 8.0
const WOLF_STALK_MAX := 12.0
const WOLF_FLEE_TIME := 8.0
const WOLF_HIT_FLEE_CHANCE := 0.3
const AXE_DAMAGE := 20.0
const HAND_DAMAGE := 6.0
const AXE_COOLDOWN := 0.8
const HAND_COOLDOWN := 0.6
const ATTACK_RANGE := 2.0
const KNOCKBACK := 1.5

# --- deer ---
const DEER_COUNT := 4
const DEER_FLEE_RADIUS := 12.0
const DEER_SPEED := 7.0
const DEER_HEALTH := 40.0
const DEER_MEAT := 2

# --- weather ---
const BLIZZARD_FIRST_DAY := 1
const BLIZZARD_FIRST_HOUR := 14.0
const BLIZZARD_CHANCE_PER_HOUR := 0.08
const BLIZZARD_MIN_GAP_HOURS := 6.0
const BLIZZARD_WARNING := 10.0
const BLIZZARD_MIN := 60.0
const BLIZZARD_MAX := 90.0

# --- world ---
const WORLD_SIZE := 160.0
const TERRAIN_CELL := 2.0
const BOUNDS := 78.0
const TERRAIN_SEED := 1337
const FOOTPRINT_STEP := 0.6
const FOOTPRINT_LIFETIME := 20.0
const FOOTPRINT_POOL := 60
const RESPAWN_FIREWOOD_PER_DAY := 20
const RESPAWN_STONE_PER_DAY := 12
const MAX_FIREWOOD := 60
const MAX_STONES := 40
const PROCEDURAL_AUDIO := false

# --- network (PLAN C10/C11, ARQ v2 §6) ---
const NET_TICK := 60                    # physics / input generation rate
const NET_SEND_EVERY := 2               # inputs packed 2 per packet -> 30 Hz
const NET_INPUT_REDUNDANCY := 2         # the 2 previous commands travel again in each packet
const NET_STATE_EVERY := 2              # one poses packet (all players + owner ack/vel) per client at 30 Hz
const NET_SYNC_INTERVAL := 0.0333       # (reserved) synchronizer interval; player poses no longer use ALWAYS props
const NET_ACTOR_SYNC_INTERVAL := 0.1    # wolves / deer (10 Hz)
const NET_INTERP_DELAY := 0.1           # remote players rendered 100 ms in the past
const NET_EXTRAPOLATE_MAX := 0.1
const NET_RECONCILE_THRESHOLD := 0.05   # 5 cm
const NET_MAX_INPUT_QUEUE := 6          # server jitter buffer cap
const NET_MAX_AIM_DIST := 40.0
const NET_INTERACT_TOLERANCE := 1.0     # m over the interactable range (latency)
const NET_GRACE_SECONDS := 60.0         # body stays after a disconnect
const NET_CHAT_MAX_CHARS := 200
const NET_CHAT_PER_SECOND := 2.0
const NET_INTERACT_PER_SECOND := 5.0
const NET_CRAFT_PER_SECOND := 3.0
const NET_WORLDSTATE_SYNC_SECONDS := 5.0
const NET_INFRACTIONS_KICK := 30

# --- stamina (GDD v2 §5 "Aguante") ---
const STAMINA_MAX := 100.0
const STAMINA_RUN_DRAIN := 5.0          # /s running
const STAMINA_REGEN_IDLE := 8.0         # /s standing still
const STAMINA_REGEN_WALK := 4.0         # /s walking
const STAMINA_MELEE := 8.0              # per light swing
const STAMINA_CHARGED := 12.0
const STAMINA_SHOVE := 8.0
const STAMINA_MIN_RUN := 20.0           # below: no running, no charged swings (hysteresis: back at 30)
const STAMINA_RESUME_RUN := 30.0

# --- melee (GDD v2 §7.1, §7.5; ARQ v2 §6.8) ---
const MELEE_REACH_TOLERANCE := 0.5      # m the server adds to the weapon reach (latency)
const MELEE_CONE_DEG := 110.0           # full arc in front of the attacker
const MELEE_REWIND_MAX := 0.15          # s of hit history the server may rewind (lag compensation)
const MELEE_CRIT_MULT := 3.0
const MELEE_CHARGED_MULT := 1.5
const MELEE_CHARGED_EXTRA := 0.4        # s of wind-up
const MELEE_CHARGED_NOISE := 4.0        # m added to the weapon noise
const MELEE_CHARGE_HOLD := 0.35         # s the click is held before it becomes a charged swing
const MELEE_MISS_NOISE := 8.0
const FROZEN_BLUNT_MULT := 1.5          # "se astilla"
const SHOVE_RANGE := 1.6
const SHOVE_TIME := 0.5
const SHOVE_KNOCKDOWN := 0.35
const SHOVE_NOISE := 8.0
const STOMP_TIME := 1.0
const STOMP_DAMAGE := 200.0
const STOMP_NOISE := 6.0
const EXECUTE_TIME := 1.5
const EXECUTE_RANGE := 1.4
const HITSTOP_MELEE := 0.06
const HITSTOP_CHARGED := 0.1
const SHAKE_HIT := 0.12
const SHAKE_HURT := 0.35
const BLOOD_DECAL_SECONDS := 120.0

# --- zombies (GDD v2 §6, ARQ v2 §10; PLAN C9) ---
const ZOMBIE_L0_RADIUS := 40.0          # LOD 0 (body from the pool, 10 Hz brain)
const ZOMBIE_L1_RADIUS := 120.0         # LOD 1 (record, 2 Hz, moves along its route)
const ZOMBIE_DESPAWN_RADIUS := 200.0    # beyond: back into the chunk population counters
const ZOMBIE_L0_MAX := 150              # bodies in the pool (web: ZOMBIE_L0_MAX_WEB)
const ZOMBIE_L0_MAX_WEB := 40
const ZOMBIE_MAX := 500                 # records (web: ZOMBIE_MAX_WEB)
const ZOMBIE_MAX_WEB := 120
const ZOMBIE_THINK_L0 := 6              # physics ticks between two thoughts (10 Hz)
const ZOMBIE_THINK_L1 := 30             # (2 Hz)
const ZOMBIE_LOD_PERIOD := 0.5
const ZOMBIE_MEMORY := 20.0             # s the last known position is chased
const ZOMBIE_FORGET := 45.0             # s without stimulus -> wander
const ZOMBIE_INVESTIGATE_WAIT := 15.0   # s standing at the investigated point
const ZOMBIE_PERIPHERAL := 3.0          # 360° vision radius
const ZOMBIE_ATTACK_WINDUP := 0.45      # s to the damage window without data/anim_events.json (Zom_Attack_A/B hit_start)
const ZOMBIE_ATTACK_CONE_DEG := 60.0
const ZOMBIE_HIT_STAGGER := 0.4         # s of flinch after a hit
const ZOMBIE_KNOCKED_TIME := 2.5        # s on the ground after a knockdown (stomp window)
const ZOMBIE_FREEZE_AFTER := 300.0      # s outdoors at night without stimulus -> frozen (GDD §6.4)
const ZOMBIE_WAKE_TIME := 1.5           # s of Zom_Wake before a woken frozen moves
const ZOMBIE_SEPARATION := 0.75         # m between two zombies (spatial hash push)
const ZOMBIE_STOP_DIST := 0.95          # m from the target player where a chaser stops
const ZOMBIE_REPATH_L0 := 0.75          # s between two routes of the same zombie (target moved > 2 m)
const ZOMBIE_CORPSE_SECONDS := 30.0     # dead record kept (replicated corpse pose), then freed
const ZOMBIE_BITE_BLEED := 5.0          # s taken from a downed player's bleed-out per bite
const NAV_QUERIES_PER_TICK := 40
const NAV_SHARE_RADIUS := 6.0           # zombies this close with the same goal share the leader's route

# --- downed / revive / death (GDD v2 §12.2, ARQ v2 §11.5) ---
const DOWNED_BLEED := 60.0
const DOWNED_BLEED_COLD := 40.0         # warmth < 30
const DOWNED_CRAWL_SPEED := 0.8
const DOWNED_MAX := 2                   # downs between rests (the third kills); reset at dawn until beds exist
const REVIVE_TIME := 4.0
const REVIVE_RANGE := 2.2
const REVIVE_HEALTH := 30.0
const SOLO_GETUP_TIME := 20.0           # alone on the server: get up once per day after this (GDD "Solo")
const HURT_SPEED_MULT := 0.85           # "Malherido" after a revive
const HURT_SECONDS := 300.0
const RESPAWN_DELAY := 20.0
const GIVE_UP_HOLD := 3.0
const CORPSE_DAYS := 2                  # 48 h of game time

# --- firearms / bow / throwables (GDD v2 §7.1–§7.6, ARQ v2 §6.8, §11.3; M5) ---
const GUN_REWIND_MAX := 0.2             # s of lag compensation (hitscan, PLAN §3.2 "≤ 200 ms")
const GUN_HISTORY := 1.0                # s of hit history kept per player / zombie (30 samples at 30 Hz)
const GUN_ORIGIN_HEIGHT := 1.3          # m: the muzzle height of a standing shooter (0.6 crouched / downed)
const GUN_HIT_RADIUS := 0.4             # m: horizontal radius of a zombie / player for a bullet (top-down 2D test)
const GUN_MAX_AIM := 60.0               # m: farthest aim point a fire request may carry
const GUN_CADENCE_TOLERANCE := 0.85     # the server accepts a shot after cadence × this (jitter)
const GUN_CRIT_MULT := 3.0
const GUN_CRIT_GREEN := 0.15            # crit chance bonus with the reticle green (GDD §7.1)
const GUN_SPREAD_WALK := 3.0            # degrees added to the minimum (GDD §7.4)
const GUN_SPREAD_RUN := 8.0
const GUN_SPREAD_CROUCH := -1.0
const GUN_SPREAD_COLD_MULT := 1.5       # Calor < 15
const GUN_SPREAD_HURT := 4.0            # degrees added when hit
const GUN_SPREAD_OPEN_RATE := 30.0      # °/s toward a bigger target (starting to move)
const GUN_SPREAD_CLOSE_TIME := 0.8      # s to close to the minimum standing still (GDD §7.1)
const GUN_SPREAD_CLOSE_RATE := 14.0     # °/s: closes any posture opening (≤ +8° run… +11°) within 0.8 s
const GUN_RECOIL_RECOVER := 12.0        # °/s (GDD §7.4; the close rate covers it)
const GUN_BAND_AMBER := 4.0             # reticle colours: green < 4° ≤ amber ≤ 8° < red
const GUN_BAND_RED := 8.0
const GUN_SHAKE := 0.1                  # camera shake per shot (shotgun 0.25)
const GUN_UNJAM_TIME := 1.5             # s (Act_Unjam, GDD §7.3)
const GUN_WORN_JAM := 0.02              # extra jam chance with durability < 30
const GUN_OIL_SECONDS := 1800.0         # gun oil protects from cold jams for a game day (default day length)
const GUN_DRY_NOISE := 2.0              # m: the click of an empty gun
const GUN_MAGNET_RADIUS := 1.2          # m: cursor magnetism (GDD §7.1); off for the rifle beyond 25 m
const GUN_MAGNET_RIFLE_MAX := 25.0
const BOW_MIN_DRAW := 0.35              # fraction of the draw below which the arrow falls short (damage ×draw)
const BOW_WARMTH_MIN := 15.0            # without gloves and Calor < 15 the bow cannot be drawn
const ARROW_GRAVITY := 9.8
const ARROW_LIFETIME := 2.5             # s before a flying arrow is dropped
const THROW_RANGE := 12.0               # m (GDD §7.6 row 14)
const THROW_TIME := 0.8                 # s (Act_Throw)
const THROW_SPEED := 14.0               # m/s along the arc
const CAN_NOISE := 15.0                 # m: a thrown can / rock lands (lure)
const FLARE_LURE_RADIUS := 40.0         # m: zombies drift to the light for FLARE_SECONDS, no noise ring
const FLARE_SECONDS := 30.0
const FLARE_WARMTH := 5.0

# --- loot / weight (GDD v2 §9, C22; M5) ---
const LOOT_CHANCE := 0.65               # a container holds something (GDD §9.2)
const LOOT_RESTOCK_DAYS := 3            # game days a container stays untouched before a restock roll (72 h)
const LOOT_RESTOCK_FRACTION := 0.6      # a restock rolls 60 % of the items (C22 "al 60 %"); never ammo
const CARRY_CAPACITY := 20.0            # kg (GDD §9.4; + backpacks / Forma física later)
const CARRY_SLOW_AT := 0.8              # > 80 %: speed ×0.85
const CARRY_SLOW_MULT := 0.85
const CARRY_HEAVY_AT := 1.0             # > 100 %: ×0.6 and no running
const CARRY_HEAVY_MULT := 0.6
const CARRY_STUCK_AT := 1.2             # > 120 %: cannot move
const CARRY_HAND_FACTOR := 0.5          # the weapon in hand weighs half
