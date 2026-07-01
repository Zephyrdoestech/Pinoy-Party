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
# For mini-games: score application + advancing the turn is handled by
# GameManager._on_minigame_finished(), NOT by this node. This node (and its
# whole StateMachine) is destroyed by SceneLoader's change_scene_to_file()
# before EventBus.minigame_finished can ever fire, so it cannot safely await
# the result itself — only an autoload (GameManager) survives that scene
# change. See GameManager.gd.
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
	# All 4 players compete simultaneously (per design decision)
	var all_players: Array[int] = []
	for i in GameManager.players.size():
		all_players.append(i)
	# Every client calls this, but only the host's instance actually picks
	# the minigame ID and broadcasts it — see NetworkManager.start_minigame_synced().
	# This replaces calling Utils.random_minigame() + SceneLoader.go_to_minigame()
	# directly, which let each client pick a different minigame independently.
	NetworkManager.start_minigame_synced(all_players)
	# Deliberately NOT awaiting EventBus.minigame_finished here — this node
	# is destroyed by the scene change above before the signal can fire.
	# GameManager._on_minigame_finished() (autoload, survives the scene
	# change) applies scores and advances current_player_index instead.
	# The board scene that rebuilds after the minigame starts a brand-new
	# StateMachine at State_StartTurn, which reads the now-already-advanced
	# current_player_index — so the turn correctly moves to the next player.
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
