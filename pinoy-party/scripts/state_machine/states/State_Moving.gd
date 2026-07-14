class_name State_Moving
extends State

func enter() -> void:
	var gm: GameManager = GameManager
	var player_idx: int = gm.current_player_index
	var roll: int       = gm.pending_roll

	gm.state = Enums.GameState.MOVING
	gm.players[player_idx]["state"] = Enums.PlayerState.MOVING

	var old_tile: int = gm.players[player_idx]["tile_index"]
	var last_tile: int = Constants.TOTAL_TILES - 1
	var raw_target: int = old_tile + roll
	var new_tile: int
	var bounced: bool = raw_target > last_tile

	if bounced:
		# Bounce back off the finish tile by the overshoot amount instead of
		# refusing to move. The token still visits the finish tile itself
		# before rebounding - see _animate_and_advance()'s two-leg handling.
		var overshoot: int = raw_target - last_tile
		new_tile = last_tile - overshoot
		EventBus.roll_exceeded.emit(player_idx, last_tile - old_tile)
	else:
		new_tile = raw_target

	# Detect first arrival at the finish tile and award the bonus.
	# We check here (pre-animation) so the flag is set before State_TileEvent
	# or State_EndTurn can run. add_score() emits score_changed, which updates
	# the HUD immediately once the token lands. A bounce always visits the
	# finish tile mid-animation, so it earns the bonus too, same as landing
	# on it exactly.
	if (new_tile == last_tile or bounced) and not gm.players[player_idx]["finished"]:
		gm.players[player_idx]["finished"] = true
		gm.add_score(player_idx, Constants.FINISH_LINE_BONUS)
		EventBus.player_finished.emit(player_idx)

	if bounced:
		_animate_bounce.call_deferred(player_idx, last_tile, new_tile)
	else:
		_animate_and_advance.call_deferred(player_idx, new_tile)

## Two-leg animation for an overshoot: walk to the finish tile, then walk
## back to the actual resting tile. Reuses _animate_one_leg() for each leg
## so the movement_finished waiting/timeout logic isn't duplicated.
func _animate_bounce(player_idx: int, peak_tile: int, final_tile: int) -> void:
	await _animate_one_leg(player_idx, peak_tile)
	await _animate_one_leg(player_idx, final_tile)

	var gm: GameManager = GameManager
	gm.players[player_idx]["state"] = Enums.PlayerState.IDLE
	request_transition(&"State_TileEvent")

func _animate_and_advance(player_idx: int, new_tile: int) -> void:
	await _animate_one_leg(player_idx, new_tile)

	var gm: GameManager = GameManager
	gm.players[player_idx]["state"] = Enums.PlayerState.IDLE
	request_transition(&"State_TileEvent")

## Animates the token from its current tile to `target_tile` and waits for
## that specific player's movement_finished signal (or a timeout), then
## persists the authoritative tile_index. Shared by both the normal
## single-leg move and each leg of a bounce.
func _animate_one_leg(player_idx: int, target_tile: int) -> void:
	var gm: GameManager = GameManager

	# Tell the token to animate. Game.gd will re-emit movement_finished
	# on EventBus when the token's own signal fires.
	EventBus.player_moved.emit(player_idx, target_tile)

	# Use an Array as the "done" flag so the lambda captures it by reference.
	# A plain `var done := false` would be captured by VALUE in GDScript,
	# meaning `done[0] = true` inside the lambda would not affect the outer scope.
	var done := [false]
	var _handler := func(finished_idx: int) -> void:
		if finished_idx == player_idx:
			done[0] = true
	EventBus.movement_finished.connect(_handler, CONNECT_ONE_SHOT)

	# Poll each frame until our specific player's token finishes, or until
	# MOVEMENT_TIMEOUT_SEC elapses. Without this cap, a dropped/never-fired
	# movement_finished (packet loss, a token that failed to spawn, etc.)
	# hangs the FSM forever with no error - force-completing trades a
	# possible visual snap for the game never getting permanently stuck.
	var elapsed := 0.0
	while not done[0] and elapsed < Constants.MOVEMENT_TIMEOUT_SEC:
		await get_tree().process_frame
		elapsed += get_process_delta_time()

	if not done[0]:
		push_warning("[State_Moving] movement_finished timed out for player %d - forcing completion." % player_idx)

	# Safety: disconnect if still connected (e.g. signal never fired).
	if EventBus.movement_finished.is_connected(_handler):
		EventBus.movement_finished.disconnect(_handler)

	# Persist the final tile position so subsequent legs / State_TileEvent
	# read it correctly. Also covers the timeout case: GameManager's
	# authoritative position is correct even if the token visually fell
	# short of target_tile.
	gm.players[player_idx]["tile_index"] = target_tile
