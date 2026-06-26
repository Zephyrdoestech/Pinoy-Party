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

func _process(delta: float) -> void:
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
	var scores: Dictionary = {}
	# Award points by finish order; anyone who didn't finish goes last, ranked by progress.
	var unfinished: Array[int] = participating_players.filter(func(p): return p not in finished_order)
	unfinished.sort_custom(func(a, b): return progress[a] > progress[b])
	var final_order: Array[int] = finished_order + unfinished
	for rank in final_order.size():
		var player_idx: int = final_order[rank]
		var points: int = max(3 - rank, 0)  # 1st=3, 2nd=2, 3rd=1, 4th=0
		scores[player_idx] = points
		GameManager.add_score(player_idx, points)
	print("[SackRace] Final order: %s" % [final_order])
	_finish(scores)
