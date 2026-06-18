# scripts/state_machine/states/State_Moving.gd
# ---------------------------------------------------------------------------
# Phase 3 – Moving
#
# Reads the pending_roll stored by State_WaitingForDice, advances the current
# player's tile_index by that many steps, then waits for the PlayerToken's
# movement animation to finish before transitioning to State_TileEvent.
#
# The PlayerToken node is expected to:
#   1. Expose a move_to(tile_index: int) → void method that starts the hop
#      animation.
#   2. Emit a signal  movement_finished  when the animation completes.
#
# If you don't have that signal yet, replace the await with a Timer or a
# Tween completion callback.
# ---------------------------------------------------------------------------
class_name State_Moving
extends State


func enter() -> void:
	var gm: GameManager = GameManager
	var player_idx: int = gm.current_player_index
	var roll: int       = gm.pending_roll

	gm.state = Enums.GameState.MOVING
	gm.players[player_idx]["state"] = Enums.PlayerState.MOVING

	print("[Moving] Player %d moves %d tile(s)." % [player_idx, roll])

	# Clamp movement so we never overshoot the end of the board.
	var old_tile: int = gm.players[player_idx]["tile_index"]
	var new_tile: int = mini(old_tile + roll, Constants.TOTAL_TILES - 1)
	gm.players[player_idx]["tile_index"] = new_tile

	# Trigger the animation and wait for it to finish asynchronously.
	# We use a coroutine so that the FSM stays event-driven, not polling.
	_animate_and_advance.call_deferred(player_idx, new_tile)


func _animate_and_advance(player_idx: int, new_tile: int) -> void:
	var gm: GameManager = GameManager

	# EventBus.player_moved tells the PlayerToken (or Board) to start moving.
	EventBus.player_moved.emit(player_idx, new_tile)

	# Wait until the token broadcasts that it has finished.
	# Replace 'movement_finished' with whatever signal your PlayerToken uses.
	# If the signal carries a player_index arg, add it after the signal name:
	#   await EventBus.movement_finished   (if it's on EventBus)
	# or reach into the token node directly:
	#   await game_scene.tokens[player_idx].movement_finished
	#
	# For now we await a generic EventBus signal that you can add later.
	# A fallback Timer is also shown (commented out) for rapid prototyping.
	#
	# --- Option A: EventBus signal (recommended) ---
	# await EventBus.movement_finished
	#
	# --- Option B: fixed-duration Timer (quick prototype) ---
	var wait_seconds: float = Constants.MOVE_STEP_DURATION * (gm.pending_roll + 1)
	await get_tree().create_timer(wait_seconds).timeout

	gm.players[player_idx]["state"] = Enums.PlayerState.IDLE

	request_transition(&"State_TileEvent")
