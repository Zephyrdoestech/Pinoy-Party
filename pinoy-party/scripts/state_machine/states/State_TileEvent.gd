# scripts/state_machine/states/State_TileEvent.gd
# ---------------------------------------------------------------------------
# Phase 4 - Tile Event
#
# Reads the tile the current player just landed on from GameManager, then
# dispatches to the appropriate sub-system:
#
#   TileType.BLANK        -> no effect, go straight to EndTurn.
#   TileType.GAME_TRIGGER -> load a random mini-game via SceneLoader.
#   (future)              -> Sari-Sari trivia, penalty, bonus, etc.
#
# For mini-games: score application + advancing the turn is handled by
# GameManager._on_minigame_finished(), NOT by this node. This node (and its
# whole StateMachine) is destroyed by SceneLoader's change_scene_to_file()
# before EventBus.minigame_finished can ever fire, so it cannot safely await
# the result itself - only an autoload (GameManager) survives that scene
# change. See GameManager.gd.
# ---------------------------------------------------------------------------
class_name State_TileEvent
extends State

const MINIGAME_TILE_SFX := preload("res://assets/sfx/board/plus_tile_sfx.mp3")
const SARI_SARI_TILE_SFX := preload("res://assets/sfx/board/sari_sari_tile_sfx.mp3")
const TILE_EVENT_SFX_FALLBACK_DURATION := 0.8
const TILE_EVENT_SFX_EXTRA_PADDING := 0.05

func enter() -> void:
	var gm: GameManager  = GameManager
	var player_idx: int  = gm.current_player_index
	var tile_idx: int    = gm.players[player_idx]["tile_index"]

	# If this player already finished (reached the final tile this turn),
	# skip tile-event resolution entirely and go straight to EndTurn.
	# State_Moving sets finished = true before _animate_and_advance runs,
	# so by the time we reach here the flag is already authoritative.
	if gm.players[player_idx]["finished"]:
		request_transition(&"State_EndTurn")
		return

	# Resolve tile type. Swap this lookup for your actual Board / TileMap API.
	var tile_type: Enums.TileType = _get_tile_type(tile_idx)
	print("[TileEvent] Player %d landed on tile %d (type: %s)."
		% [player_idx, tile_idx, Enums.TileType.keys()[tile_type]])

	# Emit once — the if/else previously emitted the identical signal in
	# both branches, which was redundant. Moved here before the await so
	# listeners always receive it regardless of tile type.
	EventBus.tile_landed.emit(player_idx, tile_type)
	if tile_type != Enums.TileType.BLANK:
		await _wait_for_tile_sfx_duration(tile_type)

	match tile_type:
		Enums.TileType.BLANK:
			_handle_blank()
		Enums.TileType.GAME_TRIGGER:
			_handle_minigame()
		Enums.TileType.TRIVIA:
			_handle_trivia()
		_:
			# Unknown tile type - treat as blank to avoid softlocking.
			push_warning("[TileEvent] Unhandled tile type %d - defaulting to BLANK." % tile_type)
			_handle_blank()
# ---------------------------------------------------------------------------
# Tile handlers
# ---------------------------------------------------------------------------
func _wait_for_tile_sfx_duration(tile_type: int) -> void:
	var stream := _get_tile_sfx_stream(tile_type)
	var duration := TILE_EVENT_SFX_FALLBACK_DURATION
	if stream != null and stream.get_length() > 0.0:
		duration = stream.get_length() + TILE_EVENT_SFX_EXTRA_PADDING
	await get_tree().create_timer(duration).timeout

func _get_tile_sfx_stream(tile_type: int) -> AudioStream:
	match tile_type:
		Enums.TileType.GAME_TRIGGER:
			return MINIGAME_TILE_SFX
		Enums.TileType.TRIVIA:
			return SARI_SARI_TILE_SFX
	return null

func _handle_blank() -> void:
	# Nothing happens - go straight to EndTurn.
	request_transition(&"State_EndTurn")
func _handle_minigame() -> void:
	# Build the participant list from active_player_count, not players.size().
	# players.size() is always MAX_PLAYERS (4); in a 2-player match this would
	# send [0,1,2,3] to the minigame, which would crash looking for non-existent
	# nodes for players 2 and 3.
	var all_players: Array[int] = []
	for i in GameManager.active_player_count:
		all_players.append(i)
	# Every client calls this, but only the host's instance actually picks
	# the minigame ID and broadcasts it - see NetworkManager.start_minigame_synced().
	# This replaces calling Utils.random_minigame() + SceneLoader.go_to_minigame()
	# directly, which let each client pick a different minigame independently.
	NetworkManager.start_minigame_synced(all_players)
	# Deliberately NOT awaiting EventBus.minigame_finished here - this node
	# is destroyed by the scene change above before the signal can fire.
	# GameManager._on_minigame_finished() (autoload, survives the scene
	# change) applies scores and advances current_player_index instead.
	# The board scene that rebuilds after the minigame starts a brand-new
	# StateMachine at State_StartTurn, which reads the now-already-advanced
	# current_player_index - so the turn correctly moves to the next player.
func _handle_trivia() -> void:
	NetworkManager.start_trivia_synced(GameManager.current_player_index)
	# Unlike _handle_minigame(), this node is NOT destroyed while trivia
	# runs (no scene change involved) - so it's safe to just await the
	# result directly here, instead of relying on GameManager to advance
	# the turn in the background. Only one trivia round is ever active at
	# a time (by design - only the landing player answers), so a plain
	# await is safe with no signal-filtering needed.
	await EventBus.trivia_finished
	request_transition(&"State_EndTurn")
# ---------------------------------------------------------------------------
# Tile type resolution
# ---------------------------------------------------------------------------
## Returns the TileType for the given board tile index.
func _get_tile_type(tile_index: int) -> Enums.TileType:
	if GameManager.board_ref == null:
		push_warning("[TileEvent] board_ref not set - defaulting to BLANK.")
		return Enums.TileType.BLANK
	return GameManager.board_ref.get_tile_type(tile_index) as Enums.TileType
