# scripts/state_machine/states/State_WaitingForDice.gd
# ---------------------------------------------------------------------------
# Phase 2 - Waiting For Dice
#
# This state PAUSES the FSM and waits for an external signal from the dice UI.
# Nothing progresses until the player presses the Roll button, which causes
# the Dice node to emit EventBus.dice_rolled(player_index, result).
#
# Flow:
#   enter()  -> subscribe to EventBus.dice_rolled
#   (idle…)  -> player presses Roll button -> Dice node rolls -> emits signal
#   _on_dice_rolled() -> store result on GameManager -> transition to Moving
#   exit()   -> unsubscribe from EventBus.dice_rolled
# ---------------------------------------------------------------------------
class_name State_WaitingForDice
extends State


func enter() -> void:
	var gm: GameManager = GameManager

	# Defensive guard: Step 5's skip logic in State_EndTurn should prevent a
	# finished player from ever reaching this state, but if they do (e.g. due
	# to a future code path we haven't anticipated), eject immediately rather
	# than leaving the UI waiting for a roll that shouldn't happen.
	if gm.players[gm.current_player_index]["finished"]:
		push_warning(
			"[WaitingForDice] player %d is finished but was given a turn - skipping to EndTurn."
			% gm.current_player_index
		)
		request_transition(&"State_EndTurn")
		return

	# Update the GameManager's legacy state enum so Game.gd's roll-guard still
	# works while we migrate to the FSM incrementally.
	gm.state = Enums.GameState.ROLLING

	# Connect to the dice result signal. Use a one-shot connection so we don't
	# need to worry about disconnecting in exit() for this particular path.
	EventBus.dice_rolled.connect(_on_dice_rolled, CONNECT_ONE_SHOT)


func exit() -> void:
	# Safety: disconnect if still connected (e.g., forced transition externally).
	if EventBus.dice_rolled.is_connected(_on_dice_rolled):
		EventBus.dice_rolled.disconnect(_on_dice_rolled)


# tick() is intentionally omitted - this state is fully event-driven.


# ---------------------------------------------------------------------------
# Signal handler
# ---------------------------------------------------------------------------

func _on_dice_rolled(player_index: int, result: int) -> void:
	var gm: GameManager = GameManager

	# Guard: ignore rolls that belong to a different player (shouldn't happen
	# with proper UI guards, but belt-and-suspenders).
	if player_index != gm.current_player_index:
		push_warning(
			"[WaitingForDice] dice_rolled for player %d but current is %d - ignoring."
			% [player_index, gm.current_player_index]
		)
		return

	# Store the roll result so State_Moving can read it.
	gm.pending_roll = result

	request_transition(&"State_Moving")
