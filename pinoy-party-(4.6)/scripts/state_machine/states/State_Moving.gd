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

	# Use an Array as the "done" flag so the lambda captures it by reference.
	# A plain `var done := false` would be captured by VALUE in GDScript,
	# meaning `done[0] = true` inside the lambda would not affect the outer scope.
	var done := [false]
	var _handler := func(finished_idx: int) -> void:
		if finished_idx == player_idx:
			done[0] = true
	EventBus.movement_finished.connect(_handler, CONNECT_ONE_SHOT)

	# Poll each frame until our specific player's token finishes.
	while not done[0]:
		await get_tree().process_frame

	# Safety: disconnect if still connected (e.g. signal never fired).
	if EventBus.movement_finished.is_connected(_handler):
		EventBus.movement_finished.disconnect(_handler)

	# Persist the final tile position so State_TileEvent reads it correctly.
	gm.players[player_idx]["tile_index"] = new_tile
	gm.players[player_idx]["state"] = Enums.PlayerState.IDLE
	request_transition(&"State_TileEvent")
