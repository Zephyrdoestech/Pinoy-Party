class_name SackRace
extends BaseMinigame

const FINISH_DISTANCE := 30.0      # "hops" needed to win
const HOP_DISTANCE := 1.0          # progress per press
const RACE_TIMEOUT := 15.0         # seconds, safety net
const HOP_PIXELS := 30.0           # how many pixels each ColorRect moves per press

var progress: Dictionary = {}      # player_idx -> float progress
var finished_order: Array[int] = []
var race_active := false
var timeout_timer := 0.0

func _get_track_rect(player_idx: int) -> ColorRect:
	return get_node("Tracks/Player %d" % (player_idx + 1))

func start_game(players: Array[int]) -> void:
	participating_players = players
	for idx in players:
		progress[idx] = 0.0
		var rect := _get_track_rect(idx)
		rect.position.x = 0.0  # reset to start line each race
	finished_order.clear()
	race_active = true
	timeout_timer = 0.0
	$UI/TimerLabel.text = "Time: %.1f" % RACE_TIMEOUT
	print("[SackRace] Race started for players: %s" % [players])
	run_intro()

func _process(delta: float) -> void:
	if gameplay_locked:
		return
	
	if not race_active:
		return
	timeout_timer += delta
	var time_left := RACE_TIMEOUT - timeout_timer
	$UI/TimerLabel.text = "Time: %.1f" % max(time_left, 0.0)
	if timeout_timer >= RACE_TIMEOUT:
		print("[SackRace] Timeout reached, ending race early.")
		_end_race()

func _unhandled_input(event: InputEvent) -> void:
	if not race_active:
		return
	for player_idx in participating_players:
		if player_idx in finished_order:
			continue  # already done, ignore further input
		var action := "p%d_jump" % (player_idx + 1)
		if event.is_action_pressed(action):
			_advance(player_idx)

func _advance(player_idx: int) -> void:
	progress[player_idx] += HOP_DISTANCE
	var rect := _get_track_rect(player_idx)
	rect.position.x = progress[player_idx] * HOP_PIXELS
	if progress[player_idx] >= FINISH_DISTANCE and player_idx not in finished_order:
		finished_order.append(player_idx)
		print("[SackRace] Player %d finished in place %d." % [player_idx, finished_order.size()])
		if finished_order.size() == participating_players.size():
			_end_race()

func _end_race() -> void:
	race_active = false

	# Players who actually crossed the finish line have a strict, tie-free
	# order (only one player advances per key-press event, so two players
	# can't finish on the exact same input) — each is their own group.
	var groups: Array = []
	for idx in finished_order:
		groups.append([idx])

	# Anyone who didn't finish is ranked by remaining progress, with equal
	# progress at the timeout treated as a genuine tie (grouped together)
	# instead of being arbitrarily ordered by sort_custom.
	var unfinished: Array[int] = participating_players.filter(func(p): return p not in finished_order)
	unfinished.sort_custom(func(a, b): return progress[a] > progress[b])

	var i := 0
	while i < unfinished.size():
		var tie_group: Array = [unfinished[i]]
		var j := i + 1
		while j < unfinished.size() and is_equal_approx(progress[unfinished[j]], progress[unfinished[i]]):
			tie_group.append(unfinished[j])
			j += 1
		groups.append(tie_group)
		i = j

	var scores: Dictionary = compute_placement_scores(groups)
	print("[SackRace] Final placement groups (best to worst): %s" % [groups])
	_finish(scores)
