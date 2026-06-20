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

	# NOTE: tile_index is intentionally NOT updated here anymore.
	# move_to() will update it step-by-step as the token actually hops.
	_animate_and_advance.call_deferred(player_idx, new_tile)

func _animate_and_advance(player_idx: int, new_tile: int) -> void:
	var gm: GameManager = GameManager

	EventBus.player_moved.emit(player_idx, new_tile)

	var finished_idx: int = await EventBus.movement_finished
	while finished_idx != player_idx:
		finished_idx = await EventBus.movement_finished

	gm.players[player_idx]["state"] = Enums.PlayerState.IDLE
	request_transition(&"State_TileEvent")
