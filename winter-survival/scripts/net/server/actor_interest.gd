class_name ActorInterest
## Server-side interest management for replicated actors (ARQ v2 §6.5, M3 chunk version): a peer receives an
## actor's synchronizer (and therefore its spawn) only while the actor is in the 3 × 3 chunks around the peer's
## own player (NetWorld.sees); the spawn/despawn follows the visibility (verified in the PoC). `radius` is kept
## as an extra distance cap for callers that want a tighter set (0 = chunks only).


static func install(sync: MultiplayerSynchronizer, actor: Node3D, radius: float = 0.0) -> void:
	sync.visibility_update_mode = MultiplayerSynchronizer.VISIBILITY_PROCESS_PHYSICS
	sync.add_visibility_filter(func(for_peer: int) -> bool:
		# peer 0 = "everyone": false makes the replication interface evaluate each peer (true = visible to all)
		if for_peer == 0:
			return false
		if for_peer == 1:
			return true
		if not actor.is_inside_tree() or NetWorld.instance == null:
			return true
		if not NetWorld.instance.sees(for_peer, actor.global_position):
			return false
		if radius <= 0.0:
			return true
		var p := NetWorld.instance._player_of(for_peer)
		if p == null:
			return false
		var d := Vector2(p.global_position.x - actor.global_position.x, p.global_position.z - actor.global_position.z).length()
		return d <= radius)
