# scripts/state_machine/states/State_TileEvent.gd
# ---------------------------------------------------------------------------
# Phase 4 – Tile Event
#
# Reads the tile the current player just landed on from GameManager, then
# dispatches to the appropriate sub-system:
#
#   TileType.BLANK        → no effect, go straight to EndTurn.
#   TileType.GAME_TRIGGER → load a random mini-game via SceneLoader.
#   (future)              → Sari-Sari trivia, penalty, bonus, etc.
#
# For mini-games: we wait on EventBus.minigame_finished and then let
# State_EndTurn handle score persistence. The mini-game scene itself calls
# EventBus.minigame_finished.emit(scores) when it concludes.
# ---------------------------------------------------------------------------
class_name State_TileEvent
extends State


func enter() -> void:
	var gm: GameManager  = GameManager
	var player_idx: int  = gm.current_player_index
	var tile_idx: int    = gm.players[player_idx]["tile_index"]

	# Resolve tile type. Swap this lookup for your actual Board / TileMap API.
	var tile_type: Enums.TileType = _get_tile_type(tile_idx)

	print("[TileEvent] Player %d landed on tile %d (type: %s)."
		% [player_idx, tile_idx, Enums.TileType.keys()[tile_type]])

	# Notify listeners (e.g. UI highlights, board animations).
	EventBus.tile_landed.emit(player_idx, tile_type)

	match tile_type:
		Enums.TileType.BLANK:
			_handle_blank()

		Enums.TileType.GAME_TRIGGER:
			_handle_minigame()

		_:
			# Unknown tile type – treat as blank to avoid softlocking.
			push_warning("[TileEvent] Unhandled tile type %d – defaulting to BLANK." % tile_type)
			_handle_blank()


# ---------------------------------------------------------------------------
# Tile handlers
# ---------------------------------------------------------------------------

func _handle_blank() -> void:
	# Nothing happens – go straight to EndTurn.
	request_transition(&"State_EndTurn")


func _handle_minigame() -> void:
	var minigame_id: String = Utils.random_minigame()
	print("[TileEvent] Triggering mini-game: %s" % minigame_id)

	# All 4 players compete simultaneously (per design decision)
	var all_players: Array[int] = []
	for i in GameManager.players.size():
		all_players.append(i)

	EventBus.minigame_started.emit(minigame_id)
	SceneLoader.go_to_minigame(minigame_id, all_players)

	_wait_for_minigame_result.call_deferred()


func _wait_for_minigame_result() -> void:
	var scores: Dictionary = await EventBus.minigame_finished

	# Apply scores to all players.
	var gm: GameManager = GameManager
	for idx: int in scores:
		gm.players[idx]["score"] += scores[idx]
		print("[TileEvent] Player %d earned %d point(s)." % [idx, scores[idx]])

	request_transition(&"State_EndTurn")


# ---------------------------------------------------------------------------
# Tile type resolution
# ---------------------------------------------------------------------------

## Returns the TileType for the given board tile index.
## TODO: Replace this stub with a real lookup once your Board node exposes a
##       get_tile_type(tile_index: int) -> Enums.TileType method.
func _get_tile_type(tile_index: int) -> Enums.TileType:
	if GameManager.board_ref == null:
		push_warning("[TileEvent] board_ref not set — defaulting to BLANK.")
		return Enums.TileType.BLANK
	return GameManager.board_ref.get_tile_type(tile_index)
