class_name State_Moving
extends State

func enter() -> void:
	var gm: GameManager = GameManager
	var player_idx: int = gm.current_player_index
	var roll: int       = gm.pending_roll

	gm.state = Enums.GameState.MOVING
	gm.players[player_idx]["state"] = Enums.PlayerState.MOVING

	var old_tile: int = gm.players[player_idx]["tile_index"]
	var new_tile: int = mini(old_tile + roll, Constants.TOTAL_TILES - 1)

	print("[Moving] Player %d moves %d tile(s) → tile %d." % [player_idx, roll, new_tile])

	_animate_and_advance.call_deferred(player_idx, new_tile)

func _animate_and_advance(player_idx: int, new_tile: int) -> void:
	var gm: GameManager = GameManager

	# Tell the token to animate. Game.gd will re-emit movement_finished
	# on EventBus when the token's own signal fires.
	EventBus.player_moved.emit(player_idx, new_tile)

	# Use a one-shot connection with a guard instead of an open await loop.
	# This prevents a stale coroutine from a previous turn stealing the signal
	# that belongs to a future player's movement.
	var done := false
	var _handler := func(finished_idx: int) -> void:
		if finished_idx == player_idx:
			done = true
	EventBus.movement_finished.connect(_handler, CONNECT_ONE_SHOT)

	# Wait until our specific player's token finishes.
	while not done:
		await get_tree().process_frame

	# Disconnect in case the while-loop exited for another reason.
	if EventBus.movement_finished.is_connected(_handler):
		EventBus.movement_finished.disconnect(_handler)

	# Persist the final tile position so State_TileEvent reads it correctly.
	gm.players[player_idx]["tile_index"] = new_tile
	gm.players[player_idx]["state"] = Enums.PlayerState.IDLE
	request_transition(&"State_TileEvent")

