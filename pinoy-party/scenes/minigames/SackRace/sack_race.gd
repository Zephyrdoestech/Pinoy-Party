class_name SackRace
extends BaseMinigame

const FINISH_DISTANCE := 48.0      # "hops" needed to win
const HOP_DISTANCE := 1.0          # progress per press
const RACE_TIMEOUT := 15.0         # seconds, safety net
const HOP_PIXELS := 30.0           # how many pixels each ColorRect moves per press

var progress: Dictionary = {}      # player_idx -> float progress
var finished_order: Array[int] = []
var race_active := false
var timeout_timer := 0.0


#func _get_track_node(player_idx: int) -> Node2D:
	#return get_node("Tracks/Player %d" % (player_idx + 1))

func _get_track_node(player_idx: int) -> Node2D:
	var path := "SplitScreenContainer/P%d_Container/Viewport%d/Track%d/Player%d" % [
		player_idx + 1, player_idx + 1, player_idx + 1, player_idx + 1
	]
	
	var node = get_node_or_null(path)
	if not node:
		return null
	return node

func start_game(players: Array[int]) -> void:
	super.start_game(players)
	for idx in players:
		progress[idx] = 0.0
		var node := _get_track_node(idx)
		if node:
			node.position.x = 0.0  # reset to start line each race
	finished_order.clear()
	race_active = true
	timeout_timer = 0.0
	$UI/TimerLabel.text = "Time: %.1f" % RACE_TIMEOUT
	await run_intro()

func _process(delta: float) -> void:
	if not race_active or gameplay_locked:
		return
	timeout_timer += delta
	var time_left := RACE_TIMEOUT - timeout_timer
	$UI/TimerLabel.text = "Time: %.1f" % max(time_left, 0.0)
	if timeout_timer >= RACE_TIMEOUT:
		_end_race()

func _input(event: InputEvent) -> void:
	if not race_active:
		return
	if not event.is_action_pressed("jump"):
		return
	#DEBUG
	if not multiplayer.has_multiplayer_peer() or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		apply_hop(1) # control p1 for testing
		return
		
	var my_idx: int = NetworkManager.get_my_player_index()
	if my_idx == -1 or my_idx not in participating_players:
		return  # not a participant in this race (or no LAN match active)
	if my_idx in finished_order:
		return  # already finished, ignore further presses
	# Route through the host so every client's progress stays in sync -
	# same request -> host-broadcast pattern used for dice rolls.
	if NetworkManager.is_host:
		NetworkManager.process_sack_race_hop(my_idx)
	else:
		NetworkManager.request_sack_race_hop.rpc_id(1, my_idx)

## Called by NetworkManager._apply_sack_race_hop() on every peer once the
## host has validated and broadcast the hop. This is the only place
## progress should be advanced from now - local input no longer calls
## _advance() directly, it just requests a hop via NetworkManager.
func apply_hop(player_idx: int) -> void:
	if not race_active:
		return
	if player_idx in finished_order:
		return
	play_jump_sfx()
	_advance(player_idx)

func _advance(player_idx: int) -> void:
	
	progress[player_idx] += HOP_DISTANCE
	var player_node := _get_track_node(player_idx)
	
	if player_node:
		player_node.position.x = progress[player_idx] * HOP_PIXELS
		var anim = player_node.find_child("AnimationPlayer")
		if anim:
			player_node.find_child("AnimationPlayer").play("jump")
	
	if progress[player_idx] >= FINISH_DISTANCE and player_idx not in finished_order:
		finished_order.append(player_idx)
		if finished_order.size() == participating_players.size():
			_end_race()

func _end_race() -> void:
	race_active = false

	# Players who actually crossed the finish line have a strict, tie-free
	# order (only one player advances per key-press event, so two players
	# can't finish on the exact same input) - each is their own group.
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

	var scores: Dictionary = BaseMinigame.compute_placement_scores(groups)
	_finish(scores)
