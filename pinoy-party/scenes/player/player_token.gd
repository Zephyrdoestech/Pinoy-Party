extends Node2D

const Utils = preload("res://scripts/utils.gd")

var player_index: int = 0
var board_ref: Node2D  # assign the Board node from the scene that owns this token

func setup(index: int, board: Node2D) -> void:
	player_index = index
	board_ref = board
	global_position = board_ref.get_tile_position(0) + Utils.token_offset(player_index)
	EventBus.dice_rolled.connect(_on_dice_rolled)

func _on_dice_rolled(rolled_player_index: int, result: int) -> void:
	if rolled_player_index == player_index:
		move_steps(result)

func move_steps(steps: int) -> void:
	if board_ref == null:
		return
	_step_one(steps)

func _step_one(remaining: int) -> void:
	if remaining <= 0:
		var tile_idx: int = GameManager.players[player_index]["tile_index"]
		GameManager.on_move_complete()
		EventBus.emit_signal("tile_landed", player_index, board_ref.get_tile_type(tile_idx))
		return

	var current_idx: int = GameManager.players[player_index]["tile_index"]
	var next_idx: int = min(current_idx + 1, Constants.TOTAL_TILES - 1)
	var target: Vector2 = board_ref.get_tile_position(next_idx) + Utils.token_offset(player_index)

	var tween := create_tween()
	tween.tween_property(self, "global_position", target, Constants.MOVE_STEP_DURATION)
	tween.finished.connect(func():
		GameManager.players[player_index]["tile_index"] = next_idx
		_step_one(remaining - 1)
	) 
