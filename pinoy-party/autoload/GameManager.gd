# autoload/GameManager.gd
# ---------------------------------------------------------------------------
# Global game state singleton.
# The FSM (StateMachine + State_* nodes) lives inside the GameScene (Game.tscn)
# and reads/writes the properties defined here.  The legacy imperative methods
# (start_turn, on_dice_rolled, etc.) are kept for backward-compatibility during
# the migration; they will be removed once the FSM is fully wired in Game.tscn.
# ---------------------------------------------------------------------------
extends Node

# ---------------------------------------------------------------------------
# Game-wide state
# ---------------------------------------------------------------------------

## Legacy enum-based state (kept for the roll-guard in Game.gd).
## Will be replaced by the FSM's current_state once migration is complete.
var state: Enums.GameState = Enums.GameState.WAITING

## Index of the player whose turn it currently is (0-based).
var current_player_index := 0

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

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	for i in Constants.MAX_PLAYERS:
		players.append({
			"name":       "Player %d" % (i + 1),
			"tile_index": 0,
			"score":      0,
			"color":      [Color.RED, Color.BLUE, Color.GREEN, Color.YELLOW][i],
			"state":      Enums.PlayerState.IDLE,
		})
	EventBus.minigame_finished.connect(_on_minigame_finished)

func _on_minigame_finished(scores: Dictionary) -> void:
	for idx in scores:
		players[idx]["score"] += scores[idx]
		print("[GameManager] Player %d earned %d point(s) from minigame." % [idx, scores[idx]])
	current_player_index = (current_player_index + 1) % Constants.MAX_PLAYERS
# ---------------------------------------------------------------------------
# Legacy API (kept for backward-compatibility – do not remove until Game.gd
# no longer calls these directly).
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


func on_minigame_finished(scores: Dictionary) -> void:
	for idx: int in scores:
		players[idx]["score"] += scores[idx]
	state = Enums.GameState.ROLLING
	_advance_turn()


func _advance_turn() -> void:
	current_player_index = (current_player_index + 1) % Constants.MAX_PLAYERS
	start_turn()


func add_score(player_index: int, points: int) -> void:
	players[player_index]["score"] += points
	EventBus.score_changed.emit(player_index, players[player_index]["score"])
	if _is_game_over():
		EventBus.game_over.emit(_get_winner())


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
	for p: Dictionary in players:
		p["tile_index"] = 0
		p["score"] = 0
		p["state"] = Enums.PlayerState.IDLE
