# autoload/GameManager.gd
# ---------------------------------------------------------------------------
# Global game state singleton. The FSM (StateMachine + State_* nodes)
# lives inside Game.tscn and reads/writes the properties defined here.
# ---------------------------------------------------------------------------
extends Node

const PLUS_TILE_SFX := preload("res://assets/sfx/board/plus_tile_sfx.mp3")
const MINUS_TILE_SFX := preload("res://assets/sfx/board/minus_tile_sfx.mp3")

# ---------------------------------------------------------------------------
# Game-wide state
# ---------------------------------------------------------------------------

## Legacy enum-based state (kept for the roll-guard in Game.gd).
## Will be replaced by the FSM's current_state once migration is complete.
var state: Enums.GameState = Enums.GameState.WAITING

## Index of the player whose turn it currently is (0-based).
var current_player_index := 0

## How many real players are actually in this match. Defaults to
## Constants.MAX_PLAYERS for the offline/local-only case, but is overwritten
## by NetworkManager (via _sync_player_index_map) before Game.tscn loads
## whenever a LAN match starts with fewer than the max players.
var active_player_count: int = Constants.MAX_PLAYERS

## Player data array.  Each element is a Dictionary:
##   {
##     "name":       String,
##     "tile_index": int,
##     "score":      int,
##     "color":      Color,
##     "state":      Enums.PlayerState,
##   }
var players: Array[Dictionary] = []

## The result of the most recent dice roll.
## Written by State_WaitingForDice, read by State_Moving.
var pending_roll: int = 0
var board_ref: Node2D = null

## Tracks which tutorial overlays have already been shown this session.
## Key: tutorial ID string (e.g. "main_board", "sack_race").
## Resets when the game restarts; not persisted to disk.
var tutorials_shown: Dictionary = {}

func has_shown_tutorial(tutorial_id: String) -> bool:
	return tutorials_shown.get(tutorial_id, false)

func mark_tutorial_shown(tutorial_id: String) -> void:
	tutorials_shown[tutorial_id] = true

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_setup_players()
	EventBus.minigame_finished.connect(_on_minigame_finished)
	EventBus.trivia_finished.connect(_on_trivia_finished)

## Builds the players array from active_player_count. Called once at
## autoload _ready() with the default count (4, for local/offline play),
## and called again by NetworkManager once the real LAN player count is
## known - _ready() runs before the lobby exists, so it can't know that
## count up front.
func _setup_players() -> void:
	players.clear()
	for i in active_player_count:
		players.append({
			"name":       NetworkManager.get_player_name(i, "Player %d" % (i + 1)),
			"tile_index": 0,
			"score":      0,
			"color":      [Color.RED, Color.BLUE, Color.GREEN, Color.YELLOW][i],
			"state":      Enums.PlayerState.IDLE,
		})

func _on_minigame_finished(scores: Dictionary) -> void:
	var has_positive_delta := false
	var has_negative_delta := false
	for idx in scores:
		# Guard: a buggy minigame could emit an out-of-range player index - fail
		# loudly here rather than crashing silently inside the array access below.
		if idx < 0 or idx >= players.size():
			push_error("[GameManager] _on_minigame_finished: invalid player index %d in scores dict" % idx)
			continue
		players[idx]["score"] += scores[idx]
		has_positive_delta = has_positive_delta or scores[idx] > 0
		has_negative_delta = has_negative_delta or scores[idx] < 0
		EventBus.score_changed.emit(idx, players[idx]["score"])
	_play_score_delta_sfx(1 if has_positive_delta else -1 if has_negative_delta else 0)
	current_player_index = (current_player_index + 1) % active_player_count

func _on_trivia_finished(scores: Dictionary) -> void:
	for idx in scores:
		add_score(idx, scores[idx])

# ---------------------------------------------------------------------------
# Legacy API - methods still used by dice.gd and Game.gd during FSM migration.
# on_minigame_finished() and _advance_turn() have been removed: the FSM
# (State_EndTurn) owns turn advancement and BaseMinigame._finish() routes
# scores exclusively through EventBus.minigame_finished.
# ---------------------------------------------------------------------------

func start_turn() -> void:
	state = Enums.GameState.ROLLING
	EventBus.turn_started.emit(current_player_index)


func on_dice_rolled(result: int) -> void:
	state = Enums.GameState.MOVING
	EventBus.dice_rolled.emit(current_player_index, result)


func on_move_complete() -> void:
	var tile_idx: int = players[current_player_index]["tile_index"]
	EventBus.player_moved.emit(current_player_index, tile_idx)


func add_score(player_index: int, points: int) -> void:
	players[player_index]["score"] += points
	EventBus.score_changed.emit(player_index, players[player_index]["score"])
	_play_score_delta_sfx(points)


func _is_game_over() -> bool:
	for p: Dictionary in players:
		if p["tile_index"] >= Constants.TOTAL_TILES - 1:
			return true
	return false


func _get_winner() -> int:
	var best := 0
	for i in players.size():
		if players[i]["score"] > players[best]["score"]:
			best = i
	return best

func reset_for_new_game() -> void:
	current_player_index = 0
	state = Enums.GameState.WAITING
	tutorials_shown.clear()
	for p: Dictionary in players:
		p["tile_index"] = 0
		p["score"] = 0
		p["state"] = Enums.PlayerState.IDLE

func _play_score_delta_sfx(points: int) -> void:
	if points > 0:
		_play_sfx("PlusTileSfx", PLUS_TILE_SFX)
	elif points < 0:
		_play_sfx("MinusTileSfx", MINUS_TILE_SFX)

func _play_sfx(player_name: String, stream: AudioStream) -> void:
	var player := _get_or_create_sfx_player(player_name, stream)
	if player == null or player.stream == null:
		return
	player.stop()
	player.play()

func _get_or_create_sfx_player(player_name: String, stream: AudioStream) -> AudioStreamPlayer:
	var existing := get_node_or_null(player_name) as AudioStreamPlayer
	if existing != null:
		if existing.stream == null:
			existing.stream = stream
		return existing

	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.stream = stream
	add_child(player)
	return player
