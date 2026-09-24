class_name ActorInterest
## Server-side interest management for replicated actors (ARQ v2 §6.5, M1 distance version; M3 switches to
## the 3 × 3 chunk set). A peer receives an actor's synchronizer (and therefore its spawn) only while its own
## player is within `radius`; the spawn/despawn follows the visibility (verified in the PoC).


static func install(sync: MultiplayerSynchronizer, actor: Node3D, radius: float) -> void:
	sync.visibility_update_mode = MultiplayerSynchronizer.VISIBILITY_PROCESS_PHYSICS
	sync.add_visibility_filter(func(for_peer: int) -> bool:
		if for_peer == 1 or for_peer == 0:
			return true
		var world := actor.get_tree().get_first_node_in_group("world") if actor.is_inside_tree() else null
		if world == null:
			return true
		var p: Node3D = world.get_node("Players").get_node_or_null(str(for_peer))
		if p == null:
			return false
		var d := Vector2(p.global_position.x - actor.global_position.x, p.global_position.z - actor.global_position.z).length()
		return d <= radius)
