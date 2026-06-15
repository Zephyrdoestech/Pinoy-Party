# autoload/GameManager.gd
extends Node

var state: Enums.GameState = Enums.GameState.WAITING
var current_player_index := 0
var players: Array[Dictionary] = []

func _ready() -> void:
	for i in Constants.MAX_PLAYERS:
		players.append({
			"name":       "Player %d" % (i + 1),
			"tile_index": 0,
			"score":      0,
			"color":      [Color.RED, Color.BLUE, Color.GREEN, Color.YELLOW][i],
			"state":      Enums.PlayerState.IDLE
		})

func start_turn() -> void:
	state = Enums.GameState.ROLLING
	EventBus.emit_signal("turn_started", current_player_index)

func on_dice_rolled(result: int) -> void:
	state = Enums.GameState.MOVING
	EventBus.emit_signal("dice_rolled", current_player_index, result)

func on_move_complete() -> void:
	var tile_idx: int = players[current_player_index]["tile_index"]
	EventBus.emit_signal("player_moved", current_player_index, tile_idx)

func on_minigame_finished(scores: Dictionary) -> void:
	for idx in scores:
		players[idx]["score"] += scores[idx]
	state = Enums.GameState.ROLLING
	_advance_turn()

func _advance_turn() -> void:
	current_player_index = (current_player_index + 1) % Constants.MAX_PLAYERS
	start_turn()

func add_score(player_index: int, points: int) -> void:
	players[player_index]["score"] += points
	EventBus.emit_signal("game_over", _get_winner()) if _is_game_over() else null

func _is_game_over() -> bool:
	for p in players:
		if p["tile_index"] >= Constants.TOTAL_TILES - 1:
			return true
	return false

func _get_winner() -> int:
	var best := 0
	for i in players.size():
		if players[i]["score"] > players[best]["score"]:
			best = i
	return best
