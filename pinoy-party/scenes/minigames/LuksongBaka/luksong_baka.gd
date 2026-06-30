# scenes/minigames/LuksongBaka/luksong_baka.gd
class_name LuksongBaka
extends BaseMinigame

const ROUND_TIME_START := 2.2      # seconds for marker to sweep bar at round 1
const ROUND_TIME_MIN := 0.7        # fastest the sweep will ever get
const ROUND_SPEEDUP := 0.85        # multiply sweep time by this each round
const ZONE_WIDTH_START := 0.30     # green zone width as % of bar (round 1)
const ZONE_WIDTH_MIN := 0.12       # narrowest the zone will ever get
const ZONE_SHRINK := 0.92          # multiply zone width by this each round
const BAR_WIDTH := 400.0

@onready var player_bars: Node2D = $PlayerBars
@onready var round_label: Label = $UI/RoundLabel

var current_round := 0
var round_time := ROUND_TIME_START
var zone_width := ZONE_WIDTH_START
var zone_start := 0.0  # 0.0–1.0 position of zone start on the bar

var alive_players: Array[int] = []
var jumped_this_round: Dictionary = {}   # player_index -> bool
var marker_t := 0.0                      # 0.0–1.0 sweep progress
var sweeping := false

var eliminated_this_round: Array[int] = []
var elimination_order: Array = []  # Array of Array[int], chronological (earliest round first)

var bars: Dictionary = {}  # player_index -> bar UI nodes

func start_game(players: Array[int]) -> void:
	super(players)
	alive_players = players.duplicate()
	_spawn_player_bars()
	await run_intro()
	_start_countdown()

func _spawn_player_bars() -> void:
	var spacing := 90
	var start_y := 0
	for i in alive_players.size():
		var player_idx: int = alive_players[i]
		var bar := _create_bar_ui(player_idx)
		bar.position = Vector2(0, start_y + i * spacing)
		player_bars.add_child(bar)
		bars[player_idx] = bar

func _create_bar_ui(player_idx: int) -> Control:
	var container := Control.new()
	container.custom_minimum_size = Vector2(BAR_WIDTH + 120, 70)

	var name_label := Label.new()
	name_label.text = GameManager.players[player_idx]["name"]
	name_label.position = Vector2(0, 0)
	container.add_child(name_label)

	var track := ColorRect.new()
	track.name = "Track"
	track.color = Color(0.25, 0.25, 0.25)
	track.position = Vector2(0, 24)
	track.size = Vector2(BAR_WIDTH, 24)
	container.add_child(track)

	var zone := ColorRect.new()
	zone.name = "Zone"
	zone.color = Color(0.3, 0.85, 0.4)
	zone.position = Vector2(0, 24)
	zone.size = Vector2(BAR_WIDTH * zone_width, 24)
	track.add_child(zone)

	var marker := ColorRect.new()
	marker.name = "Marker"
	marker.color = Color.WHITE
	marker.position = Vector2(0, 20)
	marker.size = Vector2(4, 32)
	track.add_child(marker)

	var status := Label.new()
	status.name = "Status"
	status.text = ""
	status.position = Vector2(BAR_WIDTH + 10, 24)
	container.add_child(status)

	return container

func _start_countdown() -> void:
	current_round += 1
	round_label.text = "Round %d" % current_round
	jumped_this_round.clear()
	eliminated_this_round.clear()

	# Only the host picks the zone position — avoids each client randomizing
	# independently and disagreeing on where the safe zone actually is.
	if NetworkManager.is_host:
		var picked_zone_start := randf_range(0.0, 1.0 - zone_width)
		NetworkManager.sync_luksong_round.rpc(picked_zone_start)
	# Non-host clients wait for _apply_luksong_round() to call _begin_round()
	# via the broadcast — don't call _begin_round() here directly on clients.

## Called on every peer once the host has broadcast the zone position for
## this round. Does the actual bar/zone/marker reset and starts the sweep.
func _begin_round(synced_zone_start: float) -> void:
	zone_start = synced_zone_start
	for player_idx in alive_players:
		var zone_rect: ColorRect = bars[player_idx].get_node("Track/Zone")
		zone_rect.position.x = BAR_WIDTH * zone_start
		zone_rect.size.x = BAR_WIDTH * zone_width
		var marker_rect: ColorRect = bars[player_idx].get_node("Track/Marker")
		marker_rect.position.x = 0.0
		var status: Label = bars[player_idx].get_node("Status")
		status.text = ""
		status.modulate = Color.WHITE
	_begin_sweep()

func _begin_sweep() -> void:
	marker_t = 0.0
	sweeping = true

func _process(delta: float) -> void:
	if gameplay_locked:
		return
	if not sweeping:
		return

	marker_t += delta / round_time
	if marker_t >= 1.0:
		marker_t = 1.0
		_end_round_sweep()

	for player_idx in alive_players:
		if jumped_this_round.has(player_idx):
			continue
		var marker_rect: ColorRect = bars[player_idx].get_node("Track/Marker")
		marker_rect.position.x = marker_t * BAR_WIDTH

func _unhandled_input(event: InputEvent) -> void:
	if not sweeping:
		return
	if not event.is_action_pressed("jump"):
		return
	var my_idx: int = NetworkManager.get_my_player_index()
	if my_idx == -1 or not alive_players.has(my_idx):
		return
	if jumped_this_round.has(my_idx):
		return
	if NetworkManager.is_host:
		NetworkManager.process_luksong_jump(my_idx, marker_t)
	else:
		NetworkManager.request_luksong_jump.rpc_id(1, my_idx, marker_t)

func _try_jump(player_idx: int) -> void:
	if not alive_players.has(player_idx) or jumped_this_round.has(player_idx):
		return

	jumped_this_round[player_idx] = true
	var in_zone: bool = marker_t >= zone_start and marker_t <= (zone_start + zone_width)
	var status: Label = bars[player_idx].get_node("Status")

	if in_zone:
		status.text = "Cleared!"
		status.modulate = Color(0.3, 0.9, 0.4)
	else:
		status.text = "Caught!"
		status.modulate = Color(0.9, 0.3, 0.3)
		_eliminate(player_idx)

func _end_round_sweep() -> void:
	sweeping = false
	if not NetworkManager.is_host:
		return  # only host drives round-end logic; results arrive via RPC

	# Find anyone who never jumped — auto-eliminated this round
	var auto_eliminated: Array[int] = []
	for player_idx in alive_players.duplicate():
		if not jumped_this_round.has(player_idx):
			auto_eliminated.append(player_idx)

	NetworkManager.sync_luksong_round_end.rpc(auto_eliminated)

## Called on every peer by NetworkManager._apply_luksong_jump().
## in_zone was evaluated by the host using its authoritative marker_t.
func apply_jump_result(player_idx: int, in_zone: bool) -> void:
	if not alive_players.has(player_idx):
		return
	jumped_this_round[player_idx] = true
	var status: Label = bars[player_idx].get_node("Status")
	if in_zone:
		status.text = "Cleared!"
		status.modulate = Color(0.3, 0.9, 0.4)
	else:
		status.text = "Caught!"
		status.modulate = Color(0.9, 0.3, 0.3)
		_eliminate(player_idx)

## Called on every peer by NetworkManager._apply_luksong_round_end().
## auto_eliminated contains players who never jumped before the sweep finished.
func apply_round_end(auto_eliminated: Array) -> void:
	for player_idx in auto_eliminated:
		var status: Label = bars[player_idx].get_node("Status")
		status.text = "Caught!"
		status.modulate = Color(0.9, 0.3, 0.3)
		_eliminate(player_idx)

	if eliminated_this_round.size() > 0:
		elimination_order.append(eliminated_this_round.duplicate())

	_check_game_over()

func _eliminate(player_idx: int) -> void:
	alive_players.erase(player_idx)
	eliminated_this_round.append(player_idx)

func _check_game_over() -> void:
	if alive_players.size() <= 1:
		_end_game()
		return

	# Speed up + shrink zone for next round
	round_time = max(ROUND_TIME_MIN, round_time * ROUND_SPEEDUP)
	zone_width = max(ZONE_WIDTH_MIN, zone_width * ZONE_SHRINK)

	await get_tree().create_timer(1.0).timeout
	_start_countdown()

func _end_game() -> void:
	# Build placement groups, BEST placement first: a lone survivor (if any)
	# is 1st on their own, then each elimination round's group in reverse
	# chronological order (most recently eliminated = better placement).
	var groups: Array = []
	if alive_players.size() == 1:
		groups.append(alive_players.duplicate())
	var reversed_eliminations: Array = elimination_order.duplicate()
	reversed_eliminations.reverse()
	groups += reversed_eliminations

	var scores: Dictionary = compute_placement_scores(groups)
	_finish(scores)
