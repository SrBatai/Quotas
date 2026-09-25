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
