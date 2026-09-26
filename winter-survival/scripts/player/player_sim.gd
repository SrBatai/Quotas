class_name PlayerSim
## Pure shared movement step (ARQ v2 §6.7): the server simulation and the owner's prediction/replay run exactly
## this code. Reads nothing global: the command carries the world-space move vector and buttons, `params`
## carries what the server decides (speed multiplier, whether running is allowed).

static var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)


static func speed_for(cmd: Dictionary, params: Dictionary) -> float:
	var btn := int(cmd.get("btn", 0))
	var move: Vector2 = cmd.get("move", Vector2.ZERO)
	var speed := Balance.WALK_SPEED
	if bool(params.get("downed", false)):
		return Balance.DOWNED_CRAWL_SPEED   # M4: a downed survivor crawls (GDD v2 §12.2)
	if btn & Packets.BTN_CROUCH:
		speed = Balance.CROUCH_SPEED
	elif (btn & Packets.BTN_RUN) and bool(params.get("can_run", true)) and move != Vector2.ZERO:
		speed = Balance.RUN_SPEED
	return speed * float(params.get("speed_mult", 1.0))


static func step(body: CharacterBody3D, cmd: Dictionary, dt: float, params: Dictionary) -> void:
	var move: Vector2 = (cmd.get("move", Vector2.ZERO) as Vector2).limit_length(1.0)
	var target := Vector3(move.x, 0.0, move.y) * speed_for(cmd, params)
	body.velocity.x = move_toward(body.velocity.x, target.x, Balance.ACCEL * dt)
	body.velocity.z = move_toward(body.velocity.z, target.z, Balance.ACCEL * dt)
	if body.is_on_floor():
		body.velocity.y = -0.5
	else:
		body.velocity.y -= gravity * dt
	body.move_and_slide()
