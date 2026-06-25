# scenes/minigames/LuksongBaka/luksong_baka.gd
extends BaseMinigame

const ROUND_TIME_START := 2.2      # seconds for marker to sweep bar at round 1
const ROUND_TIME_MIN := 0.7        # fastest the sweep will ever get
const ROUND_SPEEDUP := 0.85        # multiply sweep time by this each round
const ZONE_WIDTH_START := 0.30     # green zone width as % of bar (round 1)
const ZONE_WIDTH_MIN := 0.12       # narrowest the zone will ever get
const ZONE_SHRINK := 0.92          # multiply zone width by this each round
const BAR_WIDTH := 400.0
const PLAYER_JUMP_ACTIONS := ["p1_jump", "p2_jump", "p3_jump", "p4_jump"]

@onready var player_bars: Node2D = $PlayerBars
@onready var round_label: Label = $UI/RoundLabel
@onready var countdown_label: Label = $UI/CountdownLabel

var current_round := 0
var round_time := ROUND_TIME_START
var zone_width := ZONE_WIDTH_START
var zone_start := 0.0  # 0.0–1.0 position of zone start on the bar

var alive_players: Array[int] = []
var jumped_this_round: Dictionary = {}   # player_index -> bool
var marker_t := 0.0                      # 0.0–1.0 sweep progress
var sweeping := false

var bars: Dictionary = {}  # player_index -> bar UI nodes

func start_game(players: Array[int]) -> void:
	super(players)
	alive_players = players.duplicate()
	_spawn_player_bars()
	_start_countdown()
	run_intro()

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
	sweeping = false
	current_round += 1
	round_label.text = "Round %d" % current_round
	jumped_this_round.clear()

	# Randomize zone position each round
	zone_start = randf_range(0.0, 1.0 - zone_width)
	for player_idx in alive_players:
		var zone_rect: ColorRect = bars[player_idx].get_node("Track/Zone")
		zone_rect.position.x = BAR_WIDTH * zone_start
		zone_rect.size.x = BAR_WIDTH * zone_width
		var marker_rect: ColorRect = bars[player_idx].get_node("Track/Marker")
		marker_rect.position.x = 0.0
		var status: Label = bars[player_idx].get_node("Status")
		status.text = ""
		status.modulate = Color.WHITE

	var count := 3
	while count > 0:
		countdown_label.text = str(count)
		await get_tree().create_timer(0.6).timeout
		count -= 1
	countdown_label.text = "JUMP!"
	await get_tree().create_timer(0.2).timeout
	countdown_label.text = ""

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
	for player_idx in alive_players:
		var action: String = PLAYER_JUMP_ACTIONS[player_idx]
		if event.is_action_pressed(action):
			_try_jump(player_idx)

func _try_jump(player_idx: int) -> void:
	if not alive_players.has(player_idx) or jumped_this_round.has(player_idx):
		return

	jumped_this_round[player_idx] = true
	var in_zone: bool = marker_t >= zone_start and marker_t <= (zone_start + zone_width)
	var status: Label = bars[player_idx].get_node("Status")

	if in_zone:
		status.text = "Cleared!"
		status.modulate = Color(0.3, 0.9, 0.4)
		GameManager.add_score(player_idx, 1)
	else:
		status.text = "Caught!"
		status.modulate = Color(0.9, 0.3, 0.3)
		_eliminate(player_idx)

func _end_round_sweep() -> void:
	sweeping = false
	# Anyone who never pressed space this round is auto-eliminated
	for player_idx in alive_players.duplicate():
		if not jumped_this_round.has(player_idx):
			var status: Label = bars[player_idx].get_node("Status")
			status.text = "Caught!"
			status.modulate = Color(0.9, 0.3, 0.3)
			_eliminate(player_idx)

	_check_game_over()

func _eliminate(player_idx: int) -> void:
	alive_players.erase(player_idx)

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
	var scores: Dictionary = {}
	for player_idx in participating_players:
		# Bonus: last one standing gets +3
		scores[player_idx] = 0
	if alive_players.size() == 1:
		scores[alive_players[0]] = 3

	_finish(scores)
