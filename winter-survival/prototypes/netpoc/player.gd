extends CharacterBody3D
## PoC player: server-authoritative body. The owning client streams inputs (InputSync,
## authority = client); the server simulates and streams state back (ServerSync, authority = 1).

const SPEED := 4.0
const AIM_MAX_DIST := 40.0

# --- state written ONLY by the server (ServerSync) ---
@export var display_name: String = ""
@export var net_position: Vector3 = Vector3.ZERO
@export var aim_yaw: float = 0.0          # isometric camera + mouse aim: replicated so remote avatars face the cursor
@export var aim_point: Vector3 = Vector3.ZERO
@export var hp: int = 100

# --- inputs written ONLY by the owning client (InputSync) ---
@export var input_dir: Vector2 = Vector2.ZERO
@export var input_aim_yaw: float = 0.0
@export var input_aim_point: Vector3 = Vector3.ZERO

var is_local := false
var max_reconcile_err := 0.0
var snaps := 0


func _enter_tree() -> void:
	# Node name == owning peer id (set by the server before add_child). Must happen before
	# the child synchronizer enters the tree.
	$InputSync.set_multiplayer_authority(str(name).to_int())


func _ready() -> void:
	is_local = str(name).to_int() == multiplayer.get_unique_id()
	position = net_position
	if is_local:
		# Inputs only need to reach the server, not the other clients.
		$InputSync.public_visibility = false
		$InputSync.set_visibility_for(1, true)


func _physics_process(delta: float) -> void:
	var d := input_dir.limit_length(1.0)
	if multiplayer.is_server():
		# Authoritative simulation from (validated) client inputs.
		velocity = Vector3(d.x, 0.0, d.y) * SPEED
		move_and_slide()
		net_position = position
		aim_yaw = wrapf(input_aim_yaw, -PI, PI)
		var rel := input_aim_point - position
		aim_point = position + rel.limit_length(AIM_MAX_DIST)
	elif is_local:
		# Client-side prediction with the same movement code; crude reconciliation
		# (real game: input sequence numbers + replay of unacknowledged inputs).
		velocity = Vector3(d.x, 0.0, d.y) * SPEED
		move_and_slide()
		var err := position.distance_to(net_position)
		max_reconcile_err = maxf(max_reconcile_err, err)
		if err > 1.0:
			position = net_position
			snaps += 1
	else:
		# Remote player: smooth toward the last server state (interpolation).
		position = position.lerp(net_position, 1.0 - exp(-12.0 * delta))
