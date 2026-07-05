class_name State_Moving
extends State

func enter() -> void:
	var gm: GameManager = GameManager
	var player_idx: int = gm.current_player_index
	var roll: int       = gm.pending_roll

	gm.state = Enums.GameState.MOVING
	gm.players[player_idx]["state"] = Enums.PlayerState.MOVING

	var old_tile: int = gm.players[player_idx]["tile_index"]
	var tiles_remaining: int = Constants.TOTAL_TILES - 1 - old_tile
 
	if roll > tiles_remaining:
		# Overshoot - don't move at all. tile_index is never touched, so this
		# can't be mistaken for a finish by State_TileEvent/game-over checks.
		gm.players[player_idx]["state"] = Enums.PlayerState.IDLE
		EventBus.roll_exceeded.emit(player_idx, tiles_remaining)
		request_transition.call_deferred(&"State_EndTurn")
		return
 
	var new_tile: int = old_tile + roll
 
	_animate_and_advance.call_deferred(player_idx, new_tile)

func _animate_and_advance(player_idx: int, new_tile: int) -> void:
	var gm: GameManager = GameManager

	# Tell the token to animate. Game.gd will re-emit movement_finished
	# on EventBus when the token's own signal fires.
	EventBus.player_moved.emit(player_idx, new_tile)

	# Use an Array as the "done" flag so the lambda captures it by reference.
	# A plain `var done := false` would be captured by VALUE in GDScript,
	# meaning `done[0] = true` inside the lambda would not affect the outer scope.
	var done := [false]
	var _handler := func(finished_idx: int) -> void:
		if finished_idx == player_idx:
			done[0] = true
	EventBus.movement_finished.connect(_handler, CONNECT_ONE_SHOT)

	# Poll each frame until our specific player's token finishes, or until
	# MOVEMENT_TIMEOUT_SEC elapses. Without this cap, a dropped/never-fired
	# movement_finished (packet loss, a token that failed to spawn, etc.)
	# hangs the FSM forever with no error - force-completing trades a
	# possible visual snap for the game never getting permanently stuck.
	var elapsed := 0.0
	while not done[0] and elapsed < Constants.MOVEMENT_TIMEOUT_SEC:
		await get_tree().process_frame
		elapsed += get_process_delta_time()

	if not done[0]:
		push_warning("[State_Moving] movement_finished timed out for player %d - forcing completion." % player_idx)

	# Safety: disconnect if still connected (e.g. signal never fired).
	if EventBus.movement_finished.is_connected(_handler):
		EventBus.movement_finished.disconnect(_handler)

	# Persist the final tile position so State_TileEvent reads it correctly.
	# Also covers the timeout case: GameManager's authoritative position is
	# correct even if the token visually fell short of new_tile.
	gm.players[player_idx]["tile_index"] = new_tile
	gm.players[player_idx]["state"] = Enums.PlayerState.IDLE
	request_transition(&"State_TileEvent")
