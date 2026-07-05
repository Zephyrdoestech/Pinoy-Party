# scripts/state_machine/states/State_StartTurn.gd
# ---------------------------------------------------------------------------
# Phase 1 - Start Turn
# Identifies the current player, resets per-turn variables, then immediately
# transitions to State_WaitingForDice.
# ---------------------------------------------------------------------------
class_name State_StartTurn
extends State


func enter() -> void:
	var gm: GameManager = GameManager  # Autoload reference
	var player_idx: int  = gm.current_player_index
	var player: Dictionary = gm.players[player_idx]

	# Reset any per-turn state on the player dictionary.
	player["state"] = Enums.PlayerState.IDLE

	# Notify the UI / other listeners.
	EventBus.turn_started.emit(player_idx)

	# No waiting needed - move straight to dice phase.
	request_transition(&"State_WaitingForDice")
