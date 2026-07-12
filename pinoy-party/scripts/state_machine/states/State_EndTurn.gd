# scripts/state_machine/states/State_EndTurn.gd
# ---------------------------------------------------------------------------
# Phase 5 - End Turn
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

	# 1. Persist turn-end state.
	_save_state(gm)

	# 2. Update the global UI.
	_update_ui(gm, player_idx)

	# 3. Check win condition before advancing.
	if _check_game_over(gm):
		var winner: int = gm._get_winner()
		gm.state = Enums.GameState.GAME_OVER
		EventBus.game_over.emit(winner)
		# Do NOT loop back - the game is finished.
		return

	# 4. Advance to the next player who has not yet finished.
	# The simple modulo is replaced with a loop so players who have already
	# reached the finish tile are skipped entirely. The attempts cap is a
	# safety net against an infinite loop if _is_game_over() somehow missed
	# that every player is finished (should never happen in practice).
	var next_index: int = (player_idx + 1) % gm.active_player_count
	var attempts: int = 0
	while gm.players[next_index]["finished"] and attempts < gm.active_player_count:
		next_index = (next_index + 1) % gm.active_player_count
		attempts += 1
	gm.current_player_index = next_index

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
	# Delegate to the single source of truth on GameManager - avoids
	# the win-condition logic being duplicated in two places.
	return gm._is_game_over()
