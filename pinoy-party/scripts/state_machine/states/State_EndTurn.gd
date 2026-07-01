# scripts/state_machine/states/State_EndTurn.gd
# ---------------------------------------------------------------------------
# Phase 5 – End Turn
#
# Responsibilities:
#   1. Persist any turn-end state (save game, flush pending score deltas).
#   2. Update the global UI (scoreboard, turn order indicators, etc.).
#   3. Check win condition.
#   4. Advance current_player_index (wrapping around with modulo).
#   5. Transition back to State_StartTurn to begin the next player's turn.
# ---------------------------------------------------------------------------
class_name State_EndTurn
extends State


func enter() -> void:
	var gm: GameManager = GameManager
	var player_idx: int = gm.current_player_index

	print("[EndTurn] Ending turn for Player %d." % player_idx)

	# 1. Persist turn-end state.
	_save_state(gm)

	# 2. Update the global UI.
	_update_ui(gm, player_idx)

	# 3. Check win condition before advancing.
	if _check_game_over(gm):
		var winner: int = gm._get_winner()
		print("[EndTurn] Game over! Winner is Player %d." % winner)
		gm.state = Enums.GameState.GAME_OVER
		EventBus.game_over.emit(winner)
		# Do NOT loop back – the game is finished.
		return

	# 4. Advance the player index (wrap around with modulo).
	gm.current_player_index = (player_idx + 1) % gm.active_player_count

	print("[EndTurn] Next player: %d." % gm.current_player_index)

	# 5. Loop back to the start of the next player's turn.
	request_transition(&"State_StartTurn")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _save_state(_gm: GameManager) -> void:
	# TODO: Integrate with your persistence layer (e.g. FileAccess / JSON save).
	# Example placeholder:
	#   SaveGame.save(_gm.players)
	pass


func _update_ui(_gm: GameManager, _player_idx: int) -> void:
	# The UI subscribes to EventBus signals; emit whatever is needed here.
	# turn_started is emitted by State_StartTurn, so here we only need
	# to refresh the scoreboard if you have a dedicated signal for it.
	# Example:
	#   EventBus.scores_updated.emit(_gm.players)
	pass


func _check_game_over(gm: GameManager) -> bool:
	return gm._is_game_over()
